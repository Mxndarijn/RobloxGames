--!strict
local Config = require("../src/shared/Config")
local CycleModifier = require("../src/shared/CycleModifier")
local DayNight = require("../src/shared/DayNight")
local Fountain = require("../src/shared/Fountain")
local Rng = require("../src/shared/Rng")
local ServerFixtures = require("./ServerFixtures")
local Snapshot = require("../src/server/Snapshot")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local DAY = Config.DAY_LENGTH * Config.DAY_FRACTION

local function find(name: string): CycleModifier.Modifier
	for _, m in Config.MODIFIERS do
		if m.name == name then
			return m
		end
	end
	error(`no modifier {name}`)
end

describe("DayNight.phase", function()
	it("alternates dawn / dusk phases and counts down to the next", function()
		local p0, left0 = DayNight.phase(0)
		expect(p0).toBe(0)
		expect(left0).toBeCloseTo(DAY)
		expect((DayNight.phase(DAY - 0.1))).toBe(0)
		local p1, left1 = DayNight.phase(DAY)
		expect(p1).toBe(1)
		expect(left1).toBeCloseTo(Config.DAY_LENGTH - DAY)
		expect((DayNight.phase(Config.DAY_LENGTH))).toBe(2)
	end)
end)

describe("CycleModifier roll", function()
	it("is weighted by Config.MODIFIERS", function()
		local counts: { [string]: number } = {}
		local rng = Rng.new(5)
		local n = 20000
		for _ = 1, n do
			local m = CycleModifier.pick(rng:float())
			counts[m.name] = (counts[m.name] or 0) + 1
		end
		local total = 0
		for _, m in Config.MODIFIERS do
			total += m.weight
		end
		for _, m in Config.MODIFIERS do
			expect(math.abs((counts[m.name] or 0) / n - m.weight / total) < 0.02).toBeTruthy()
		end
	end)
	it("picks the first / last entry at the edges and honours a custom list", function()
		expect(CycleModifier.pick(0).name).toBe("None")
		expect(CycleModifier.pick(0.999999).name).toBe(Config.MODIFIERS[#Config.MODIFIERS].name)
		local only = { { name = "X", label = "X", weight = 1, luck = 9 } }
		expect(CycleModifier.pick(0.5, only).name).toBe("X")
	end)
	it("is a pure function of (seed, phase)", function()
		for phase = 0, 10 do
			expect(CycleModifier.forPhase(7, phase).name).toBe(CycleModifier.forPhase(7, phase).name)
		end
		local seen: { [string]: boolean } = {}
		for phase = 0, 60 do
			seen[CycleModifier.forPhase(7, phase).name] = true
		end
		for _, m in Config.MODIFIERS do
			expect(seen[m.name]).toBe(true)
		end
	end)
	it("has a None entry and positive multipliers", function()
		expect(find("None").luck).toBe(1)
		for _, m in Config.MODIFIERS do
			expect(m.weight > 0 and m.luck >= 1).toBeTruthy()
		end
	end)
end)

describe("CycleModifier odds", function()
	local function rareRate(luck: number): number
		local rng = Rng.new(11)
		local n, rare = 6000, 0
		for i = 1, n do
			local drop = Fountain.roll(rng, `s{i}`, false, nil, luck)
			rare += if drop.slime.tier >= 3 then 1 else 0
		end
		return rare / n
	end
	it("a luck multiplier raises rarer spawns", function()
		local base = rareRate(1)
		local lucky = rareRate(find("LuckSurge").luck)
		expect(lucky > base * 1.3).toBeTruthy()
	end)
	it("the multiplier is 1 for None and when the feature is off", function()
		expect(CycleModifier.multiplier(find("None"))).toBe(1)
		expect(CycleModifier.multiplier(nil)).toBe(1)
	end)
	it("Spawner.spawnOne applies the world's modifier server-side", function()
		local function rareShare(modifier: CycleModifier.Modifier): number
			local world = ServerFixtures.world()
			world.modifier = modifier
			local n = 0
			for _ = 1, 600 do
				local id = Spawner.spawnOne(world, T0)
				n += if world.wild[id].slime.tier >= 3 then 1 else 0
				world.wild[id] = nil
			end
			return n / 600
		end
		expect(rareShare(find("LuckSurge")) > rareShare(find("None")) * 1.3).toBeTruthy()
	end)
end)

describe("Spawner.stepModifier", function()
	it("rolls at the first step, rerolls at dusk and dawn, never in between", function()
		local world = ServerFixtures.world()
		Spawner.stepModifier(world, T0)
		expect(world.modifierPhase).toBe(0)
		expect(world.modifier.name).toBe(CycleModifier.forPhase(world.modifierSeed, 0).name)
		expect(world.modifierEndsAt).toBeCloseTo(T0 + DAY)
		Spawner.stepModifier(world, T0 + DAY - 1)
		expect(world.modifierPhase).toBe(0)
		Spawner.stepModifier(world, T0 + DAY)
		expect(world.modifierPhase).toBe(1)
		expect(world.modifier.name).toBe(CycleModifier.forPhase(world.modifierSeed, 1).name)
		expect(world.modifierEndsAt).toBeCloseTo(T0 + Config.DAY_LENGTH)
		Spawner.stepModifier(world, T0 + Config.DAY_LENGTH)
		expect(world.modifierPhase).toBe(2)
	end)
	it("resets to the next phase's roll (None when it rolls None)", function()
		local world = ServerFixtures.world()
		-- find a seed where phase 0 is active and phase 1 is None
		for seed = 1, 200 do
			if CycleModifier.forPhase(seed, 0).name ~= "None" and CycleModifier.forPhase(seed, 1).name == "None" then
				world.modifierSeed = seed
				break
			end
		end
		Spawner.stepModifier(world, T0)
		expect(world.modifier.name ~= "None").toBeTruthy()
		Spawner.stepModifier(world, T0 + DAY)
		expect(world.modifier.name).toBe("None")
	end)
	it("notifies everyone and marks State dirty on a real modifier", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, {}, 0)
		for seed = 1, 200 do
			if CycleModifier.forPhase(seed, 0).name ~= "None" then
				world.modifierSeed = seed
				break
			end
		end
		s.dirty = false
		Spawner.stepModifier(world, T0)
		expect(s.dirty).toBe(true)
		local found = false
		for _, e in world.outbox do
			if e.type == "Notify" and string.find(e.text, world.modifier.label, 1, true) then
				found = true
			end
		end
		expect(found).toBe(true)
	end)
	it("replicates the active modifier in State", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, {}, 0)
		Spawner.stepModifier(world, T0)
		local state = Snapshot.build(world, s, T0)
		expect(state.modifier.name).toBe(world.modifier.name)
		expect(state.modifier.endsAt).toBeCloseTo(T0 + DAY)
	end)
end)
