--!strict
-- SlimeActor off the lane and on pads (src/ui/SlimeActor.luau, contract/slime-life.md "One pose writer, smooth off
-- the lane" and "Alive motion"): a Body that moves in replication steps is drawn as an even glide, its stepwise
-- yaw as a smooth turn; a moved pad slime hops over from its old spot; a slime put on its pad drops in; an escape
-- that reaches the pad lands.
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local SlimeActor = UiHarness.ui("SlimeActor")
local SlimeMotor = UiHarness.ui("SlimeMotor")
local SlimeFidget = UiHarness.ui("SlimeFidget")
local SlimeRig = UiHarness.ui("../visuals/shared/SlimeRig")
local Config = UiHarness.ui("../shared/Config")
local new = UiHarness.Instance.new
local roblox = require("@lune/roblox") :: any
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local FPS = 60

local function lcg(seed: number): () -> number
	local s = seed
	return function()
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end

-- A rigged slime standing at `at` in State `state`.
local function slime(state: string, at: any): any
	local model = new("Model")
	model:SetAttribute("Tier", 2)
	model:SetAttribute("State", state)
	model:SetAttribute("Species", "gummy")
	local body = new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2, 2, 2)
	body.Anchored = true
	body.CFrame = CFrame.new(at)
	body.Parent = model
	model.PrimaryPart = body
	local mesh = new("MeshPart")
	mesh.Name = "Mesh"
	mesh.Size = Vector3.new(2, 2, 2)
	mesh.CFrame = body.CFrame
	mesh.Parent = model
	local w = new("WeldConstraint")
	w.Part0 = body
	w.Part1 = mesh
	w.Parent = mesh
	SlimeRig.attach(model, body)
	return model
end

type Rig = { model: any, body: any, motor: any, actor: any, rand: () -> number }

local function rig(state: string, at: any, prevState: string?): Rig
	local model = slime(state, at)
	local r = lcg(5)
	local motor = SlimeMotor.attach(model, 0, r)
	local actor = SlimeActor.attach(model, motor, 0, prevState)
	return { model = model, body = model.PrimaryPart, motor = motor, actor = actor, rand = r }
end

local frame = { player = nil, cash = nil, userId = nil }

-- One frame at time `t`: the actor fills its mods (the light detail: no Instance effects).
local function step(r: Rig, t: number)
	SlimeActor.update(r.actor, frame, t, t, r.rand, false)
end

-- Where the slime is drawn this frame (Body + the actor's offsets), world studs.
local function drawn(r: Rig): any
	local p = r.body.CFrame.Position
	local m = r.actor.mods
	return Vector3.new(p.X + m.dx, p.Y + m.dy, p.Z + m.dz)
end

describe("SlimeActor off the lane", function()
	it("draws a Body that moves in 30 Hz steps as an even glide", function()
		local r = rig("Escaping", Vector3.new(0, 3, 0))
		local speed = 8
		local steps = {}
		local last = nil
		for f = 1, 3 * FPS do
			local t = f / FPS
			if f % 2 == 0 then -- the server's pivot lands every other frame
				r.body.CFrame = CFrame.new(speed * t, 3, 0)
			end
			step(r, t)
			local x = drawn(r).X
			if last and f > FPS then
				table.insert(steps, x - last)
			end
			last = x
		end
		local per = speed / FPS
		for _, d in steps do
			expect(math.abs(d - per) / per < 0.2).toBe(true)
		end
	end)

	it("turns smoothly while the Body's yaw arrives in steps", function()
		local r = rig("Escaping", Vector3.new(0, 3, 0))
		local worst = 0
		local lastYaw = nil
		for f = 1, 2 * FPS do
			local t = f / FPS
			if f % 2 == 0 then
				r.body.CFrame = CFrame.new(0, 3, 0) * CFrame.Angles(0, 1.2 * t, 0)
			end
			step(r, t)
			local look = r.body.CFrame.LookVector
			local yaw = math.atan2(-look.X, -look.Z) + r.actor.mods.heading
			if lastYaw and f > 20 then
				worst = math.max(worst, math.abs(yaw - lastYaw))
			end
			lastYaw = yaw
		end
		-- 1.2 rad / s is 0.02 rad a frame; the raw Body turns 0.04 then 0 every other frame
		expect(worst < 0.03).toBe(true)
	end)
end)

describe("SlimeActor on pads (FEATURES.SlimeAlive)", function()
	if not Config.FEATURES.SlimeAlive then
		return
	end

	it("hops over from the old pad when the Body jumps to a new one (Move)", function()
		local r = rig("Pad", Vector3.new(0, 3, 0))
		for f = 1, 10 do
			step(r, f / FPS)
		end
		r.body.CFrame = CFrame.new(16, 3, 0)
		local t0 = 10 / FPS
		step(r, t0 + 1 / FPS)
		-- still drawn at the old pad on the first frame
		expect(math.abs(drawn(r).X - 0) < 0.5).toBe(true)
		local top, arrivedAt = 0, nil
		for f = 2, 2 * FPS do
			local t = t0 + f / FPS
			step(r, t)
			top = math.max(top, r.actor.mods.lift)
			if not arrivedAt and math.abs(drawn(r).X - 16) < 0.05 then
				arrivedAt = t - t0
			end
		end
		expect(top > 1).toBe(true)
		expect(arrivedAt ~= nil and arrivedAt <= SlimeFidget.MOVE_HOP + 0.05).toBe(true)
	end)

	it("a slime put on its pad from a carry drops in from above and settles", function()
		local r = rig("Pad", Vector3.new(0, 3, 0), "Carried")
		step(r, 1 / FPS)
		expect(r.actor.mods.lift > SlimeFidget.DROP_HEIGHT * 0.8).toBe(true)
		for f = 2, 3 * FPS do
			step(r, f / FPS)
		end
		expect(math.abs(r.actor.mods.lift) < 0.3).toBe(true)
	end)

	it("an escape that reaches its pad lands with a hop", function()
		local r = rig("Escaping", Vector3.new(0, 3, 0))
		step(r, 1 / FPS)
		r.model:SetAttribute("State", "Pad")
		SlimeActor.setState(r.actor, "Escaping", "Pad", 1 / FPS)
		local top = 0
		for f = 2, FPS do
			step(r, f / FPS)
			top = math.max(top, r.actor.mods.lift)
		end
		expect(top > 0.4).toBe(true)
	end)

	it("a pad slime does not stand still: it fidgets within a few seconds", function()
		local r = rig("Pad", Vector3.new(0, 3, 0))
		local moved = 0
		for f = 1, 20 * FPS do
			step(r, f / FPS)
			local m = r.actor.mods
			if m.lift > 0.1 or math.abs(m.roll) > 0.05 or m.sy < 0.9 or m.sy > 1.1 then
				moved += 1
			end
		end
		expect(moved > FPS).toBe(true)
	end)
end)
