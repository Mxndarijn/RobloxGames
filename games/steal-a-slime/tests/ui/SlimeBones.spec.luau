--!strict
-- SlimeBones: the pose math for the Bones inside a species mesh, and the
-- driver on a fake rigged slime (attach through SlimeMotor, LOD tiers, release).
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local SlimeBones = UiHarness.ui("SlimeBones")
local SlimeLife = UiHarness.ui("SlimeLife")
local SlimeMotor = UiHarness.ui("SlimeMotor")
local SlimeRig = UiHarness.ui("../visuals/shared/SlimeRig")
local new = UiHarness.Instance.new
local roblox = require("@lune/roblox") :: any
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

local function rand(seed: number): () -> number
	local s = seed
	return function()
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end

describe("SlimeBones pose math", function()
	it("sorts bones by name: body, eyes, lids and accessory presets", function()
		expect(SlimeBones.kind("Root")).toBe("Root")
		expect(SlimeBones.kind("Top")).toBe("Top")
		for _, side in { "SideL", "SideR", "SideF", "SideB" } do
			expect(SlimeBones.kind(side)).toBe("Side")
		end
		expect(SlimeBones.kind("Eyes")).toBe("Eyes")
		expect(SlimeBones.kind("Lids")).toBe("Lids")
		expect(SlimeBones.kind("Crown")).toBeNil()
		local presets = {
			WingL = "Wing",
			WingR = "Wing",
			EarL = "Ear",
			AntC = "Ant",
			["Tail-1"] = "Tail",
			FinL = "Fin",
			PecR = "Fin",
			["Tent-3"] = "Tent",
			Ribbon1 = "Tent",
			Band = "Tent",
			Flame2 = "Tent",
		}
		for name, preset in presets do
			expect(SlimeBones.preset(name)).toBe(preset)
			expect(SlimeBones.kind(name)).toBe("Accessory")
		end
		expect(SlimeBones.preset("Mouth")).toBeNil()
	end)

	it("squash moves Top down and pushes the sides out; stretch does the opposite", function()
		local top, bulge, drop = SlimeBones.body(1, 2)
		expect(near(top, 0) and near(bulge, 0) and near(drop, 0)).toBe(true)
		top, bulge, drop = SlimeBones.body(0.8, 2)
		expect(near(top, -0.4)).toBe(true)
		expect(near(bulge, 0.4 * SlimeBones.BULGE)).toBe(true)
		expect(near(drop, -0.4 * SlimeBones.SIDE_DROP)).toBe(true)
		top, bulge = SlimeBones.body(1.1, 2)
		expect(top > 0 and bulge < 0).toBe(true)
	end)

	it("blinks only inside the blink window, and keeps the eyes closed mid-air", function()
		local far = -100 -- no hop around
		expect(SlimeBones.blink(9.99, 10, far)).toBe(0)
		expect(SlimeBones.blink(10 + SlimeBones.BLINK_TIME / 2, 10, far) > 0.99).toBe(true)
		expect(SlimeBones.blink(10 + SlimeBones.BLINK_TIME * 0.1, 10, far) > 0.5).toBe(true)
		expect(SlimeBones.blink(10 + SlimeBones.BLINK_TIME + 0.01, 10, far)).toBe(0)
		expect(SlimeBones.blink(0, 10, SlimeLife.AIR * 0.5)).toBe(1)
		expect(SlimeBones.blink(0, 10, -SlimeLife.WINDUP / 2)).toBe(0) -- wind-up: eyes open
	end)

	it("accessory presets by name: amplitude, air boost and per-part phase", function()
		local quarter = 1 / (4 * SlimeBones.PRESETS.Wing.hz) -- sin peaks
		expect(near(SlimeBones.accessory("Wing", quarter, 0, 0), math.rad(28), 1e-4)).toBe(true)
		expect(near(SlimeBones.accessory("Wing", quarter, 0, 1), math.rad(38), 1e-4)).toBe(true)
		expect(near(SlimeBones.accessory("Wing", quarter, 2, 0), math.rad(28), 1e-4)).toBe(true) -- pairs flap together
		local tailA = SlimeBones.accessory("Tail", 0.3, 0, 0)
		local tailB = SlimeBones.accessory("Tail", 0.3, 2.1, 0)
		expect(math.abs(tailA - tailB) > 0.05).toBe(true) -- each tail its own phase
		for name, spec in SlimeBones.PRESETS do
			local peak = 0
			for i = 0, 200 do
				peak = math.max(peak, math.abs(SlimeBones.accessory(name, i / 100, 0.7, 0)))
			end
			expect(peak <= math.rad(spec.amp) + 1e-6 and peak > math.rad(spec.amp) * 0.9).toBe(true)
		end
		expect(SlimeBones.accessory("Nope" :: any, 1, 0, 0)).toBe(0)
	end)

	it("wobbles Top a little at rest and more over a hop", function()
		local params = SlimeLife.params(3, "Wild")
		local rest, hop = 0, 0
		for i = 0, 100 do
			local t = i / 50
			rest = math.max(rest, math.abs(SlimeBones.tilt(params, t, -100)))
		end
		local span = SlimeLife.WINDUP + SlimeLife.AIR + SlimeLife.LAND
		for i = 0, 100 do
			hop = math.max(hop, math.abs(SlimeBones.tilt(params, 0, -SlimeLife.WINDUP + span * i / 100)))
		end
		expect(rest > 0 and rest <= params.wobble * SlimeBones.TILT_GAIN + 1e-6).toBe(true)
		expect(hop > rest).toBe(true)
	end)
end)

-- A rigged slime whose Mesh carries the _slimerig bones. Mesh space: Y up, the face drawn at +Z, so
-- (bones report the drawn positions mirrored in Z, SlimeBones.drawnAt) the Eyes bone sits at -Z.
-- Each bone gets an odd own orientation so the bone-space conversion is tested.
local H, R = 2, 1
local WORLD = {
	Root = CFrame.new(0, 0, 0) * CFrame.Angles(-math.pi / 2, 0, 0),
	Top = CFrame.new(0, SlimeBones.TOP_AT * H, 0) * CFrame.Angles(0.3, 1.1, -0.4),
	SideL = CFrame.new(0.9 * R, 0.38 * H, 0) * CFrame.Angles(0, 0, 0.7),
	SideR = CFrame.new(-0.9 * R, 0.38 * H, 0) * CFrame.Angles(0.2, 0, -0.7),
	SideF = CFrame.new(0, 0.38 * H, -0.9 * R) * CFrame.Angles(1, 0, 0),
	SideB = CFrame.new(0, 0.38 * H, 0.9 * R) * CFrame.Angles(-1, 0.5, 0),
	Eyes = CFrame.new(0, 0.55 * H, -R) * CFrame.Angles(math.pi / 2, 0.2, 0),
	Lids = CFrame.new(0, 0.5 * H, -R) * CFrame.Angles(math.pi / 2, -0.2, 0),
	WingL = CFrame.new(0.95, 1.2, 0.3) * CFrame.Angles(0, -0.6, 0.4),
	WingR = CFrame.new(-0.95, 1.2, 0.3) * CFrame.Angles(0, 0.6, -0.4),
	["Tail-1"] = CFrame.new(0.2, 0.4, 0.95),
	["Tail-2"] = CFrame.new(-0.2, 0.4, 0.95),
}
local PARENT = {
	Root = nil,
	Top = "Root",
	SideL = "Root",
	SideR = "Root",
	SideF = "Root",
	SideB = "Root",
	Eyes = "Top",
	Lids = "Top",
	WingL = "Top",
	WingR = "Top",
	["Tail-1"] = "Root",
	["Tail-2"] = "Root",
}
local ORDER =
	{ "Root", "Top", "SideL", "SideR", "SideF", "SideB", "Eyes", "Lids", "WingL", "WingR", "Tail-1", "Tail-2" }

local function bonedSlime(): (any, { [string]: any })
	local model = new("Model")
	model:SetAttribute("Tier", 4)
	model:SetAttribute("State", "Wild")
	local body = new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2, 2, 2)
	body.Anchored = true
	body.Parent = model
	model.PrimaryPart = body
	local mesh = new("MeshPart")
	mesh.Name = "Mesh"
	mesh.Size = Vector3.new(2.6, 2.4, 2.2)
	mesh.Parent = model
	local bones = {}
	for _, name in ORDER do
		local bone = new("Bone")
		bone.Name = name
		local parentName = PARENT[name]
		bone.CFrame = if parentName then WORLD[parentName]:Inverse() * WORLD[name] else WORLD[name]
		bone.Parent = if parentName then bones[parentName] else mesh
		bones[name] = bone
	end
	local weld = new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = mesh
	weld.Parent = mesh
	SlimeRig.attach(model, body)
	return model, bones
end

-- A bone's own displacement, seen in Mesh space (ignores what its parents do).
local function moved(bones: { [string]: any }, name: string): any
	return WORLD[name].Rotation * bones[name].Transform.Position
end

-- Mesh-space direction `v` after the bone's own rotation.
local function turned(bones: { [string]: any }, name: string, v: any): any
	local rot = WORLD[name].Rotation
	return rot * (bones[name].Transform.Rotation * (rot:Inverse() * v))
end

local function allRest(bones: { [string]: any }): boolean
	for _, bone in bones do
		if bone.Transform ~= CFrame.new() then
			return false
		end
	end
	return true
end

describe("SlimeBones driver on a rigged species mesh", function()
	it("SlimeMotor attaches the bones and leaves the Mesh Size alone", function()
		local model = bonedSlime()
		local motor = SlimeMotor.attach(model, 0, rand(1))
		expect(motor.bones ~= nil).toBe(true)
		expect(near(motor.bones.H, H, 1e-5)).toBe(true)
		expect(model:GetAttribute("LifeSkinSize")).toBeNil()
		local mesh = model:FindFirstChild("Mesh")
		local size = mesh.Size
		local r = rand(4)
		for i = 0, 10 * 30 do
			SlimeMotor.step(motor, i / 30, r)
			expect(mesh.Size == size).toBe(true)
		end
	end)

	it("a mesh without bones is not a bone rig", function()
		local mesh = new("MeshPart")
		expect(SlimeBones.attach(mesh, 0, rand(1))).toBeNil()
	end)

	it("hops squash Top down (Mesh -Y) and push the sides outward", function()
		local model, bones = bonedSlime()
		local r = rand(7)
		local motor = SlimeMotor.attach(model, 0, r)
		SlimeMotor.force(motor, "Hop", 1)
		local lowest, maxSide, horizontal = 0, 0, 0
		for i = 0, 40 do
			local now = 1 + i / 60
			SlimeMotor.step(motor, now, r)
			local top = moved(bones, "Top")
			horizontal = math.max(horizontal, Vector3.new(top.X, 0, top.Z).Magnitude)
			if top.Y < lowest then
				lowest = top.Y
				maxSide = moved(bones, "SideL").X
				local f = moved(bones, "SideF")
				expect(f.Z > 0).toBe(true) -- the front side pushes to the front (drawn at +Z)
				expect(moved(bones, "SideB").Z < 0).toBe(true)
				expect(moved(bones, "SideR").X < 0).toBe(true)
			end
		end
		-- the wind-up and landing squash reach HOP_SQUASH on top of the breathing
		expect(lowest < -SlimeLife.HOP_SQUASH * H * 0.8).toBe(true)
		expect(maxSide > 0).toBe(true)
		expect(horizontal < 1e-4).toBe(true)
	end)

	it("blinks: the eyes go into the body (-Z) while the lids come out (+Z)", function()
		local model, bones = bonedSlime()
		local r = rand(11)
		local motor = SlimeMotor.attach(model, 0, r)
		motor.clock.hopAt = 1e6 -- no hop in the way
		local blinkAt = motor.bones.blinkAt
		SlimeMotor.step(motor, blinkAt + SlimeBones.BLINK_TIME / 2, r)
		local eyes, lids = moved(bones, "Eyes"), moved(bones, "Lids")
		local share = SlimeBones.EYE_SHARE
		expect(near(eyes.Z, -SlimeBones.EYE_IN / share, 1e-3)).toBe(true)
		expect(near(lids.Z, SlimeBones.LID_OUT / share, 1e-3)).toBe(true)
		SlimeMotor.step(motor, blinkAt + SlimeBones.BLINK_TIME + 0.05, r)
		expect(moved(bones, "Eyes").Magnitude < 1e-6).toBe(true)
		expect(motor.bones.blinkAt > blinkAt).toBe(true) -- the next blink is scheduled
	end)

	it("wings flap as a mirrored pair and two tails wag out of step", function()
		local model, bones = bonedSlime()
		local r = rand(13)
		local motor = SlimeMotor.attach(model, 0, r)
		local maxTip, maxTailGap = 0, 0
		for i = 0, 60 do
			SlimeMotor.step(motor, i / 60, r)
			local tipL = turned(bones, "WingL", Vector3.new(1, 0, 0))
			local tipR = turned(bones, "WingR", Vector3.new(-1, 0, 0))
			expect(near(tipL.Y, tipR.Y, 1e-4)).toBe(true) -- both tips go up and down together
			maxTip = math.max(maxTip, math.abs(tipL.Y))
			local tailA = turned(bones, "Tail-1", Vector3.new(0, 0, 1))
			local tailB = turned(bones, "Tail-2", Vector3.new(0, 0, 1))
			expect(math.abs(tailA.Y) < 1e-4).toBe(true) -- a wag stays horizontal
			maxTailGap = math.max(maxTailGap, (tailA - tailB).Magnitude)
		end
		expect(maxTip > math.sin(math.rad(20))).toBe(true)
		expect(maxTailGap > 0.1).toBe(true)
	end)

	it("turns each part about where it is drawn, not about the bone's mirrored position", function()
		local model, bones = bonedSlime()
		local r = rand(19)
		local motor = SlimeMotor.attach(model, 0, r)
		SlimeMotor.step(motor, 0.4, r)
		for _, name in { "WingL", "WingR", "Tail-1", "Tail-2" } do
			local rest = WORLD[name]
			local delta = rest * bones[name].Transform * rest:Inverse()
			local drawn = SlimeBones.drawnAt(rest.Position, 1)
			local spin = delta.Rotation * Vector3.new(0, 0, 1) - Vector3.new(0, 0, 1)
			expect(spin.Magnitude > 1e-3).toBe(true) -- it does turn
			expect((delta * drawn - drawn).Magnitude < 1e-4).toBe(true)
		end
		expect(SlimeBones.drawnAt(Vector3.new(1, 2, 3), 2) == Vector3.new(2, 4, -6)).toBe(true)
	end)

	it("mid tier squashes the body only; far tier and release put every bone at rest", function()
		local model, bones = bonedSlime()
		local r = rand(17)
		local motor = SlimeMotor.attach(model, 0, r)
		for i = 0, 20 do
			SlimeMotor.step(motor, i / 30, r)
		end
		SlimeMotor.stepSquish(motor, 2.3, 1)
		expect(bones.WingL.Transform == CFrame.new()).toBe(true)
		expect(bones.Eyes.Transform == CFrame.new()).toBe(true)
		local moving = false
		for i = 0, 30 do
			SlimeMotor.stepSquish(motor, 3 + i / 10, 1)
			moving = moving or moved(bones, "Top").Magnitude > 1e-4
		end
		expect(moving).toBe(true)
		expect(SlimeMotor.park(motor)).toBe(true)
		expect(allRest(bones)).toBe(true)
		expect(SlimeMotor.park(motor)).toBe(false) -- once
		for i = 0, 20 do
			SlimeMotor.step(motor, 5 + i / 30, r)
		end
		expect(allRest(bones)).toBe(false)
		SlimeMotor.release(motor)
		expect(allRest(bones)).toBe(true)
		expect(model:FindFirstChild("Body"):FindFirstChild("SkinRoot").Transform == CFrame.new()).toBe(true)
	end)
end)
