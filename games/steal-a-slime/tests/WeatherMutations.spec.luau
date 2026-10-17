--!strict
-- Weather-driven mutations (FEATURES.WeatherMutations, save v5): Rain -> Wet, Snow -> Frozen,
-- Starfall -> Galaxy, and the v4 -> v5 save migration. Fixtures are v3 / v4 saves as serialized then.
local Config = require("../src/shared/Config")
local Genome = require("../src/shared/Genome")
local Merge = require("../src/shared/Merge")
local SaveData = require("../src/shared/SaveData")
local TestRunner = require("./TestRunner")
local Weather = require("../src/shared/Weather")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function fresh(id: string?)
	Weather.reset()
	Genome.bindWeather()
	if id then
		Weather.set(id)
	end
end

local FAVOURED = { Rain = "Wet", Snow = "Frozen", Starfall = "Galaxy" }

describe("Weather mutation config", function()
	it("maps Rain/Snow/Starfall to real mutations with a bonus, Clear to none", function()
		expect(Config.FEATURES.WeatherMutations).toBe(true)
		for id, m in FAVOURED do
			expect(Config.WEATHER[id].mutation).toBe(m)
			expect(Config.WEATHER[id].chanceBonus > 0).toBe(true)
			expect(Genome.mutationInfo(m) ~= nil).toBe(true)
		end
		expect(Config.WEATHER.Clear.mutation).toBe(nil)
		expect(Config.WEATHER.Clear.chanceBonus).toBe(0)
	end)
	it("keeps weather mutations out of MUTATIONS and COMBOS so the ladder, pool and Dex total are unchanged", function()
		local names = {}
		for _, m in Config.MUTATIONS do
			table.insert(names, m.name)
		end
		expect(names).toEqual({ "Glow", "Lava", "Galaxy", "Rainbow", "Gold", "Crystal", "Eclipse" })
		expect(#Config.COMBOS).toBe(4)
		local seen = {}
		for _, list in { Config.MUTATIONS, Config.WEATHER_MUTATIONS, Config.COMBOS, Config.WEATHER_COMBOS } do
			for _, m in list do
				expect(seen[m.name]).toBe(nil)
				seen[m.name] = true
			end
		end
		for _, m in Config.WEATHER_MUTATIONS do
			expect(m.weight).toBe(0)
		end
		expect(Genome.mutationMultiplier("Wet")).toBe(1.75)
		expect(Genome.mutationMultiplier("Frozen")).toBe(2.5)
	end)
	it("keeps Glow + Glow = Lava in a merge", function()
		expect(Merge.inheritedMutation("Glow", "Glow")).toBe("Lava")
	end)
	it("fuses the new combos", function()
		expect(Genome.addMutation({ "Wet" }, "Frozen")).toEqual({ "Sleet" })
		expect(Genome.addMutation({ "Frozen" }, "Galaxy")).toEqual({ "Comet" })
	end)
end)

describe("Genome.rollMutation with weather", function()
	it("is unchanged in Clear", function()
		fresh()
		expect(Genome.rollMutation(0.5, 0, 0.4)).toBe("None")
		expect(Genome.rollMutation(0.39, 0, 0.4)).toBe("Glow")
		expect(Genome.weatherBoost()).toBe(nil)
	end)
	it("adds each weather's bonus to its own mutation only while it is current", function()
		for id, m in FAVOURED do
			local bonus = Config.WEATHER[id].chanceBonus
			fresh()
			expect(Genome.rollMutation(0.4 + bonus / 2, 0, 0.4)).toBe("None")
			Weather.set(id)
			expect(Genome.rollMutation(0.4 + bonus / 2, 0, 0.4)).toBe(m)
			expect(Genome.rollMutation(0.4 + bonus + 0.001, 0, 0.4)).toBe("None") -- past the bonus band
			expect(Genome.rollMutation(0.39, 0, 0.4)).toBe("Glow") -- normal band is untouched
			Weather.set("Clear")
			expect(Genome.rollMutation(0.4 + bonus / 2, 0, 0.4)).toBe("None")
		end
	end)
	it("Changed swaps the cached bonus from one weather to the next", function()
		fresh("Rain")
		local name, bonus = Genome.weatherBoost()
		expect(name).toBe("Wet")
		expect(bonus).toBe(Config.WEATHER.Rain.chanceBonus)
		Weather.set("Snow")
		expect((Genome.weatherBoost())).toBe("Frozen")
		expect(Genome.rollMutation(0.41, 0, 0.4)).toBe("Frozen")
		Weather.set("Starfall")
		expect(Genome.rollMutation(0.41, 0, 0.4)).toBe("Galaxy")
	end)
	it("a roll that already succeeded is not changed by the weather", function()
		fresh("Rain")
		local pick = Genome.rollMutation(0.1, 0, 0.4)
		fresh()
		expect(Genome.rollMutation(0.1, 0, 0.4)).toBe(pick)
	end)
end)

local function v3Slime(id: string, mutation: string, pad: number): { [string]: any }
	return {
		id = id,
		name = "Globble",
		tier = 4,
		color = { 200, 60, 120 },
		size = 1.25,
		pattern = "Spots",
		eyes = "Happy",
		mouth = "Fang",
		mutation = mutation,
		pad = pad,
	}
end

local function save(version: number, slimes: { any }): { [string]: any }
	return {
		version = version,
		cash = 5000,
		rebirths = 2,
		padsUnlocked = 8,
		slimes = slimes,
		favoriteId = "s1",
		lastOnline = 1000,
		daily = { lastDay = 19000, streak = 3 },
		dex = { "4:Glow:Spots:Happy" },
		totalEarned = 9000,
		totalStolen = 1,
		lockLevel = 1,
		speedCoil = false,
		tutorialStep = 0,
		upgrades = {},
		stats = { caught = 5, merges = 1, locks = 0, sold = 0 },
		goals = {},
		dexRewards = 0,
	}
end

local function v4Slime(id: string, mutations: { any }, pad: number): { [string]: any }
	local s = v3Slime(id, if type(mutations[1]) == "string" then mutations[1] else "None", pad)
	s.mutations = mutations
	return s
end

describe("SaveData.migrateV4", function()
	it("loads a v4 save unchanged", function()
		local raw = save(4, { v4Slime("s1", { "Glow", "Lava" }, 1), v4Slime("s2", {}, 2) })
		local out = SaveData.migrateV4(raw)
		expect(out.version).toBe(5)
		local slimes = out.slimes :: { any }
		expect(slimes[1].mutations).toEqual({ "Glow", "Lava" })
		expect(slimes[1]).toBe((raw.slimes :: any)[1]) -- clean slimes are not even copied
		expect(slimes[2].mutations).toEqual({})
		local d = SaveData.deserialize(raw)
		expect(#d.slimes).toBe(2)
		expect(Genome.mutationList(d.slimes[1])).toEqual({ "Glow", "Lava" })
		expect(d.cash).toBe(5000)
	end)
	it("migrates a v3 save through v4 to v5 and loads the same slimes", function()
		local raw = save(3, { v3Slime("s1", "Lava", 1), v3Slime("s2", "None", 2) })
		local out = SaveData.migrate(raw) :: any
		expect(out.version).toBe(6)
		expect(out.migratedFrom).toBe(3)
		expect(out.slimes[1].mutations).toEqual({ "Lava" })
		local d = SaveData.deserialize(raw)
		expect(d.slimes[1].mutation).toBe("Lava")
		expect(Genome.mutationList(d.slimes[2])).toEqual({})
	end)
	it("cleans junk, duplicates and None inside a v4 list, and rebuilds a missing list", function()
		local raw = save(4, {
			v4Slime("s1", { "Glow", "Glow", 7, "None", "Lava" }, 1),
			v4Slime("s2", { "None" }, 2),
			v3Slime("s3", "Gold", 3),
		})
		local slimes = SaveData.migrateV4(raw).slimes :: { any }
		expect(slimes[1].mutations).toEqual({ "Glow", "Lava" })
		expect(slimes[2].mutations).toEqual({})
		expect(slimes[3].mutations).toEqual({ "Gold" })
	end)
	it("does not mutate its input and is idempotent", function()
		local raw = save(4, { v4Slime("s1", { "Glow", "Glow" }, 1) })
		local once = SaveData.migrateV4(raw)
		expect(raw.version).toBe(4)
		expect(((raw.slimes :: any)[1]).mutations).toEqual({ "Glow", "Glow" })
		local twice = SaveData.migrateV4(once)
		expect(twice.version).toBe(5)
		expect(twice.migratedFrom).toBe(4)
		expect(((twice.slimes :: any)[1]).mutations).toEqual({ "Glow" })
	end)
	it("leaves v6 alone and handles empty or odd saves", function()
		local raw = save(6, { v4Slime("s1", { "Wet" }, 1) })
		expect(SaveData.migrate(raw)).toBe(raw)
		expect(SaveData.migrateV4({ version = 4 }).version).toBe(5)
		expect(#(SaveData.migrateV4({ version = 4, slimes = {} }).slimes :: any)).toBe(0)
	end)
	it("round-trips the new weather mutations and keeps the save keys", function()
		local d = SaveData.deserialize(save(5, { v4Slime("s1", { "Wet" }, 1), v4Slime("s2", { "Sleet" }, 2) }))
		expect(d.slimes[1].mutation).toBe("Wet")
		expect(d.slimes[2].mutation).toBe("Sleet")
		local out = SaveData.serialize(d)
		expect(out.version).toBe(6)
		expect(out.slimes[1].mutation).toBe("Wet")
		expect(out.slimes[1].mutations).toEqual({ "Wet" })
		expect(out.cash).toBe(5000)
	end)
end)
