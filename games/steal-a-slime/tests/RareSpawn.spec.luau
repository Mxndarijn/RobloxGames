--!strict
-- Rare-spawn fx on wild slimes: a glow and sparkles, never a beam standing on the slime.
-- Locks the preset data (no Instance needed) and the cleanup contract of PlotVisuals' source.
local Effects = require("../src/visuals/shared/Effects")
local RareSpawn = require("../src/visuals/shared/RareSpawn")
local TestRunner = require("./TestRunner")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("RareSpawn fx", function()
	it("stands no beam on a slime at any tier, only glow and sparkles", function()
		for tier, fx in RareSpawn.TIERS do
			expect((fx :: any).beam).toBeNil()
			if tier >= 3 then
				expect((fx.sparkles or 0) > 0).toBe(true)
			end
		end
	end)
end)

describe("PlotVisuals rare fx lifetime", function()
	local src = fs.readFile("src/visuals/client/PlotVisuals.luau")

	it("only draws fx near the camera and parks the rest", function()
		local range = tonumber(string.match(src, "MAX_FX_DISTANCE = (%d+)"))
		expect(range ~= nil and range <= 200).toBe(true)
		expect(string.find(src, "model.Parent = nil", 1, true) ~= nil).toBe(true)
	end)

	it("destroys the fx when its slime goes away", function()
		expect(string.find(src, "model:Destroy()", 1, true) ~= nil).toBe(true)
		expect(string.find(src, "GetInstanceRemovedSignal", 1, true) ~= nil).toBe(true)
	end)
end)

describe("TutorialArrow beam cap", function()
	local props = fs.readFile("src/visuals/shared/Props.luau")
	local arrow = fs.readFile("src/visuals/client/TutorialArrow.luau")

	it("stays under the fx_streaks shot's 30 studs", function()
		local length = tonumber(string.match(props, "Props.ARROW_MAX_LENGTH = (%d+)"))
		expect(length ~= nil and length <= 30).toBe(true)
	end)

	it("clamps a far target's end attachment and keeps it aimed", function()
		expect(string.find(props, "offset.Unit * Props.ARROW_MAX_LENGTH", 1, true) ~= nil).toBe(true)
		expect(string.find(arrow, "Props.arrowAim", 1, true) ~= nil).toBe(true)
	end)

	it("is covered by the fx_streaks watcher shot", function()
		local shots = fs.readFile("../../tools/pipeline/pc-watcher/shots/103-v30-c11-night-streaks.json")
		expect(string.find(shots, '"tutorial_arrow"', 1, true) ~= nil).toBe(true)
	end)
end)

-- Roblox globals the shared modules use at call time; swapped in only while running fn.
local GLOBALS = {
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
	ColorSequence = roblox.ColorSequence,
	NumberSequence = roblox.NumberSequence,
	NumberRange = roblox.NumberRange,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	Vector2 = roblox.Vector2,
}

local function withRobloxGlobals(fn)
	local envs = { getfenv(RareSpawn.build), getfenv(Effects.emitter) }
	local saved = {}
	for i, env in envs do
		saved[i] = {}
		for name, value in GLOBALS do
			saved[i][name] = env[name]
			env[name] = value
		end
	end
	local ok, err = pcall(fn)
	for i, env in envs do
		for name in GLOBALS do
			env[name] = saved[i][name]
		end
	end
	if not ok then
		error(err, 0)
	end
end

describe("RareSpawn pose offsets", function()
	it("stores an FxOffset attribute on every part of every tier", function()
		withRobloxGlobals(function()
			for tier = 2, 6 do
				local fx = RareSpawn.build(tier, 1)
				expect(fx ~= nil).toBe(true)
				local parts = 0
				for _, child in fx:GetChildren() do
					if child:IsA("BasePart") then
						parts += 1
						expect(typeof(child:GetAttribute(RareSpawn.OFFSET_ATTRIBUTE))).toBe("CFrame")
					end
				end
				expect(parts > 0).toBe(true)
			end
		end)
	end)

	it("place() moves every part to pivot * offset", function()
		withRobloxGlobals(function()
			local fx = RareSpawn.build(6, 1)
			local pivot = roblox.CFrame.new(10, 20, 30)
			RareSpawn.place(fx, pivot, 0)
			for _, child in fx:GetChildren() do
				if child:IsA("BasePart") then
					local expected = roblox.CFrame.new(pivot.Position) * child:GetAttribute(RareSpawn.OFFSET_ATTRIBUTE)
					expect((child.CFrame.Position - expected.Position).Magnitude < 0.001).toBe(true)
				end
			end
		end)
	end)

	it("parks and hides a part that has no offset instead of skipping it", function()
		withRobloxGlobals(function()
			local fx = RareSpawn.build(7, 1)
			local mote = fx:FindFirstChild("Orbit_1")
			mote:SetAttribute(RareSpawn.OFFSET_ATTRIBUTE, nil)
			RareSpawn.place(fx, roblox.CFrame.new(5, 6, 7), 0)
			expect((mote.CFrame.Position - roblox.Vector3.new(5, 6, 7)).Magnitude < 0.001).toBe(true)
			expect(mote.Transparency).toBe(1)
		end)
	end)

	it("puts nothing flat on the ground around a wild slime, at any tier", function()
		withRobloxGlobals(function()
			for tier = 2, #RareSpawn.TIERS do
				local fx = RareSpawn.build(tier, 1)
				RareSpawn.place(fx, roblox.CFrame.new(0, 0, 0), 0)
				for _, child in fx:GetChildren() do
					if child:IsA("BasePart") and child.Transparency < 1 then
						local low = child.CFrame.Position.Y - child.Size.X / 2
						local flat = child.Shape == roblox.Enum.PartType.Cylinder and child.Size.X < 0.3
						expect(flat and low < 0.5).toBe(false)
					end
				end
			end
		end)
	end)

	it("keeps no weak-keyed offsets table in the module", function()
		local src = fs.readFile("src/visuals/shared/RareSpawn.luau")
		expect(string.find(src, "__mode", 1, true)).toBe(nil)
	end)
end)

describe("RareSpawn.orphans", function()
	it("returns only the fx-folder children no live slime owns", function()
		withRobloxGlobals(function()
			local a, b, c = roblox.Instance.new("Model"), roblox.Instance.new("Model"), roblox.Instance.new("Model")
			local slime = roblox.Instance.new("Model")
			local orphans = RareSpawn.orphans({ a, b, c }, { [slime] = b })
			expect(#orphans).toBe(2)
			expect(table.find(orphans, b)).toBe(nil)
		end)
	end)

	it("is wired into PlotVisuals once a second", function()
		local src = fs.readFile("src/visuals/client/PlotVisuals.luau")
		expect(string.find(src, "RareSpawn.orphans(", 1, true) ~= nil).toBe(true)
		expect(string.find(src, "nextSweep = t + 1", 1, true) ~= nil).toBe(true)
		expect(string.find(src, '~= "Wild"', 1, true) ~= nil).toBe(true)
	end)
end)
