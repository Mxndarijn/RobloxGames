--!strict
-- Rare-spawn fx on wild slimes: a glow and sparkles, never a beam standing on the slime.
-- Locks the preset data (no Instance needed).
local Effects = require("../src/visuals/shared/Effects")
local RareSpawn = require("../src/visuals/shared/RareSpawn")
local TestRunner = require("./TestRunner")
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
end)
