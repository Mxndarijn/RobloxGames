--!strict
-- v30 C11: rare-spawn beams must stay small markers over their slime. At night the Neon beams (up to 150 x 3
-- studs, visible from 600 studs) read as huge glowing yellow / pink / blue streaks shooting into the sky.
-- Locks the preset data (no Instance needed) and the cleanup contract of PlotVisuals' source.
local Effects = require("../src/visuals/shared/Effects")
local RareSpawn = require("../src/visuals/shared/RareSpawn")
local TestRunner = require("./TestRunner")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("RareSpawn beams", function()
	it("keeps every tier's beam short, thin and see-through", function()
		for tier, fx in RareSpawn.TIERS do
			local b = fx.beam
			if b then
				expect(b.height <= RareSpawn.MAX_BEAM_HEIGHT).toBe(true)
				expect(b.width <= RareSpawn.MAX_BEAM_WIDTH).toBe(true)
				expect(b.height <= 24).toBe(true)
				expect(b.width <= 1).toBe(true)
				expect(tier >= 3).toBe(true)
			end
		end
		expect(RareSpawn.BEAM_TRANSPARENCY >= 0.6).toBe(true)
	end)

	it("grows the beam with the tier but never past the cap", function()
		local last = 0
		for _, fx in RareSpawn.TIERS do
			if fx.beam then
				expect(fx.beam.height >= last).toBe(true)
				last = fx.beam.height
			end
		end
		expect(last > 0).toBe(true)
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

	it("shares the rare-spawn beam cap, under the fx_streaks shot's 30 studs", function()
		expect(string.find(props, "Props.ARROW_MAX_LENGTH = RareSpawn.MAX_BEAM_HEIGHT", 1, true) ~= nil).toBe(true)
		expect(RareSpawn.MAX_BEAM_HEIGHT <= 30).toBe(true)
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
			local fx = RareSpawn.build(3, 1)
			local beam = fx:FindFirstChild("Beam")
			beam:SetAttribute(RareSpawn.OFFSET_ATTRIBUTE, nil)
			RareSpawn.place(fx, roblox.CFrame.new(5, 6, 7), 0)
			expect((beam.CFrame.Position - roblox.Vector3.new(5, 6, 7)).Magnitude < 0.001).toBe(true)
			expect(beam.Transparency).toBe(1)
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
