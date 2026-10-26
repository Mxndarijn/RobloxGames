--!strict
-- Every historical save shape (as the old code wrote it) through the current migrate / deserialize path and the
-- full DataService load path on the memory store: no crash, nothing silently lost that should survive, stable
-- round trip, newer versions read-only.
local Config = require("../src/shared/Config")
local DataService = require("../src/server/DataService")
local PlayerData = require("../src/shared/PlayerData")
local SaveData = require("../src/shared/SaveData")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local NOW = 1_700_000_000

local function slimeV2(id: string, tier: number, pad: number?, extra: { [string]: any }?): { [string]: any }
	local s: { [string]: any } = {
		id = id,
		name = "Blorp",
		tier = tier,
		color = { 10, 200, 30 },
		size = 1.2,
		pattern = "Plain",
		eyes = "Round",
		mouth = "Smile",
		pad = pad,
	}
	for k, v in extra or {} do
		s[k] = v
	end
	return s
end

-- Each fixture: the table the old code wrote, plus what must survive.
type Fixture = {
	name: string,
	save: { [string]: any },
	cash: number,
	rebirths: number,
	ids: { string },
	favoriteId: string?,
}

local fixtures: { Fixture } = {}

-- v1 legacy prototype (PascalCase, no version).
table.insert(fixtures, {
	name = "v1 legacy",
	save = {
		Cash = 1234,
		Rebirths = 3,
		LastOnline = 1_600_000_000,
		Slimes = {
			{ Id = "old-a", Rarity = "Epic", Size = 1.4, Color = { 255, 0, 0 } },
			{ Id = "old-b", Rarity = "Common", Size = 1, Color = { 0, 255, 0 } },
		},
	},
	cash = 1234,
	rebirths = 3,
	ids = { "old-a", "old-b" },
})

-- v2 as the initial monorepo wrote it: `mutation`, `dex` keys, `dexRewards`, `lockLevel`, old tutorial numbering.
table.insert(fixtures, {
	name = "v2 initial",
	save = {
		version = 2,
		cash = 98765,
		rebirths = 7,
		padsUnlocked = 6,
		slimes = {
			slimeV2("v2-a", 3, 1, { mutation = "Glow" }),
			slimeV2("v2-b", 6, 2, { mutation = "Gold" }),
			slimeV2("v2-c", 1, 3, { mutation = "None" }),
		},
		favoriteId = "v2-b",
		lastOnline = NOW - 5000,
		daily = { lastDay = 19000, streak = 4 },
		dex = { "Epic:Glow", "Common:None" },
		totalEarned = 500000,
		totalStolen = 3,
		lockLevel = 3,
		speedCoil = true,
		tutorialStep = 5,
		upgrades = { Income = 2 },
		stats = { caught = 10, merges = 2, locks = 1, sold = 0 },
		goals = { Catch = 1 },
		dexRewards = 2,
	},
	cash = 98765,
	rebirths = 7,
	ids = { "v2-a", "v2-b", "v2-c" },
	favoriteId = "v2-b",
})

-- v3: upgrades / goals, redeem codes and a boost added without bump.
table.insert(fixtures, {
	name = "v3",
	save = {
		version = 3,
		cash = 42,
		rebirths = 12,
		padsUnlocked = 5,
		slimes = { slimeV2("v3-a", 2, 1, { mutation = "Lava" }), slimeV2("v3-b", 5, 2) },
		lastOnline = NOW - 100,
		daily = { lastDay = 19100, streak = 1 },
		dex = {},
		totalEarned = 900,
		totalStolen = 0,
		lockLevel = 1,
		speedCoil = false,
		tutorialStep = 0,
		upgrades = { Income = 3, Luck = 1, CarrySpeed = 2 },
		stats = { caught = 5, merges = 5, locks = 0, sold = 1 },
		goals = { Merge = 2 },
		dexRewards = 0,
		redeemed = { "WELCOME", "SLIME10" },
		boost = { mult = 2, untilAt = NOW + 600 },
	},
	cash = 42,
	rebirths = 12,
	ids = { "v3-a", "v3-b" },
})

-- v4: mutations lists + legacy mutation, species ids of the first named roster (since removed).
table.insert(fixtures, {
	name = "v4 mutation lists, first roster",
	save = {
		version = 4,
		cash = 7_000_000,
		rebirths = 20,
		padsUnlocked = 8,
		slimes = {
			slimeV2("v4-a", 4, 1, { mutation = "Glow", mutations = { "Glow", "Gold" }, species = "pudding" }),
			slimeV2("v4-b", 7, 2, { mutation = "Rainbow", mutations = { "Rainbow" }, species = "clover" }),
			slimeV2("v4-c", 2, 3, { mutations = {}, species = "gummy" }),
		},
		favoriteId = "v4-a",
		lastOnline = NOW - 20,
		daily = { lastDay = 19200, streak = 9 },
		dex = { "Rare:Glow" },
		totalEarned = 8_000_000,
		totalStolen = 8,
		speedCoil = true,
		tutorialStep = 0,
		upgrades = { Income = 5 },
		stats = { caught = 50, merges = 20, locks = 2, sold = 4 },
		goals = { Catch = 3 },
		dexRewards = 4,
		redeemed = { "WELCOME" },
	},
	cash = 7_000_000,
	rebirths = 20,
	ids = { "v4-a", "v4-b", "v4-c" },
	favoriteId = "v4-a",
})

-- v5: weather mutations and combos, daily quests, plotSkin/stealLog unversioned, growth.
table.insert(fixtures, {
	name = "v5 weather mutations",
	save = {
		version = 5,
		cash = 123456789,
		rebirths = 31,
		padsUnlocked = 8,
		slimes = {
			slimeV2("v5-a", 3, 1, { mutations = { "Wet", "Frozen" }, mutation = "Wet", growth = 0.5 }),
			slimeV2("v5-b", 3, 2, { mutations = { "Sleet" }, mutation = "Sleet", species = "toffee_buck" }),
			slimeV2("v5-c", 3, 3, { mutations = { "Comet" }, mutation = "Comet" }),
		},
		lastOnline = NOW - 99,
		daily = { lastDay = 19300, streak = 2 },
		quests = { day = 19300, slots = { { id = "NoSuchQuest", target = 3, base = 0, claimed = false } } },
		totalEarned = 1e9,
		totalStolen = 20,
		tutorialStep = 0,
		upgrades = { Income = 8, Luck = 3 },
		stats = { caught = 400, merges = 120, locks = 12, sold = 90 },
		goals = { Catch = 4, Merge = 3 },
		dexRewards = 6,
		redeemed = { "WELCOME", "SLIME10" },
		boost = { mult = 3, untilAt = NOW + 60 },
		plotSkin = "candy",
		stealLog = { { thief = "Bob", slime = "Blorp", at = NOW - 10 } },
	},
	cash = 123456789,
	rebirths = 31,
	ids = { "v5-a", "v5-b", "v5-c" },
})

-- v6: SlimeDex found/stamps, settings, consumables incl. MutationSpray, RainMagnet, pvp, trophies, hotbar.
table.insert(fixtures, {
	name = "v6 dex stamps, RainMagnet, MutationSpray",
	save = {
		version = 6,
		cash = 5e12,
		rebirths = 44,
		padsUnlocked = 8,
		slimes = {
			slimeV2("v6-a", 5, 1, { mutations = { "Gold" }, mutation = "Gold", species = "gummy", keep = true }),
			slimeV2("v6-b", 5, 2, { species = "nonexistent_species" }),
		},
		favoriteId = "v6-b",
		lastOnline = NOW - 1,
		daily = { lastDay = 19400, streak = 5 },
		found = { "gummy", "mochi", "ghost_species_removed" },
		stamps = { "gummy:Gold" },
		totalEarned = 5e12,
		totalStolen = 30,
		tutorialStep = 0,
		upgrades = { Income = 9, RainMagnet = 2 },
		stats = { caught = 900, merges = 300, locks = 30, sold = 200 },
		goals = { Catch = 5 },
		speciesRewards = 3,
		stampRewards = 1,
		plotSkin = "classic",
		stealLog = {},
		settings = { musicVolume = 0.3, sfxVolume = 0.9, muted = true },
		redeemed = { "WELCOME" },
		consumables = {
			slot = 77,
			bought = { MutationSpray = 2, LuckPotion = 1 },
			held = { MutationSpray = 3, LuckPotion = 2 },
		},
		pvp = { tiers = { Knockback = 2, Blaster = 1 }, traps = {}, fun = { "FunConfetti" } },
		trophies = {},
		hotbar = { "", "", "", "", "", "", "", "", "" },
	},
	cash = 5e12,
	rebirths = 44,
	ids = { "v6-a", "v6-b" },
	favoriteId = "v6-b",
})

-- v7: mutation-free; owned trap tier.
table.insert(fixtures, {
	name = "v7 trap tier",
	save = {
		version = 7,
		cash = 1e15,
		rebirths = 50,
		padsUnlocked = Config.PADS_MAX,
		slimes = { slimeV2("v7-a", 7, 1, { species = "gummy" }) },
		lastOnline = NOW - 1,
		daily = { lastDay = 19500, streak = 1 },
		found = { "gummy" },
		totalEarned = 1e15,
		totalStolen = 99,
		speedCoil = true,
		tutorialStep = 0,
		upgrades = { Income = 10 },
		stats = { caught = 1, merges = 1, locks = 1, sold = 1 },
		goals = {},
		speciesRewards = 1,
		plotSkin = "classic",
		stealLog = {},
		settings = { musicVolume = 0.5, sfxVolume = 0.5, muted = false },
		consumables = { slot = 1, bought = {}, held = {} },
		pvp = { tiers = { Trap = 3 }, traps = {}, fun = {} },
		trophies = {},
	},
	cash = 1e15,
	rebirths = 50,
	ids = { "v7-a" },
})

-- v8: trap charges, quests, boost, egg luck; boss trophies held as a slime list.
local function trophyV8(id: string, species: string, tier: number): { [string]: any }
	local t = slimeV2(id, tier, nil, { species = species, size = Config.MAX_SIZE })
	t.pad = nil
	return t
end
table.insert(fixtures, {
	name = "v8 boss trophies",
	save = {
		version = 8,
		cash = 42_000,
		rebirths = 6,
		padsUnlocked = 8,
		slimes = { slimeV2("v8-a", 3, 1, { species = "gummy" }), slimeV2("v8-b", 2, 2) },
		lastOnline = NOW - 60,
		daily = { lastDay = 19600, streak = 4 },
		found = { "gummy" },
		totalEarned = 90_000,
		totalStolen = 3,
		speedCoil = true,
		tutorialStep = 0,
		upgrades = { Income = 2 },
		stats = { caught = 9, merges = 2, locks = 1, sold = 0 },
		goals = {},
		speciesRewards = 0,
		quests = { day = 0, slots = {} },
		plotSkin = "classic",
		stealLog = {},
		settings = { musicVolume = 0.4, sfxVolume = 0.6, muted = false },
		redeemed = {},
		boost = { mult = 1, untilAt = 0 },
		consumables = { slot = 0, bought = {}, held = {} },
		pvp = { tiers = { Knockback = 1 }, traps = { GooTrap1 = 2 }, fun = {} },
		trophies = {
			trophyV8("t-1", "goozilla", 6),
			trophyV8("t-2", "queen_jelly", 6),
			trophyV8("t-3", "gummy", 1),
		},
		eggLuck = {},
	},
	cash = 42_000,
	rebirths = 6,
	ids = { "v8-a", "v8-b" },
})

-- Extra unknown fields on a current save.
table.insert(fixtures, {
	name = "current version with unknown extra fields and junk types",
	save = {
		version = Config.SAVE_VERSION,
		cash = "5000",
		rebirths = 2.7,
		padsUnlocked = 4,
		slimes = { slimeV2("cur-a", 1, 1), "junk", 5, slimeV2("cur-a", 1, 2), slimeV2("cur-b", 99, 99) },
		futureFeature = { a = 1 },
		found = "notalist",
		redeemed = { "OK", 5, {} },
	},
	cash = 5000,
	rebirths = 2,
	ids = { "cur-a", "cur-b" },
})

local function idSet(data: PlayerData.Data): { [string]: boolean }
	local out = {}
	for _, s in data.slimes do
		out[s.id] = true
	end
	return out
end

local function stable(t: any): any
	-- lastOnline is the save time, ignore it.
	local c = table.clone(t)
	c.lastOnline = nil
	return c
end

describe("every historical save shape", function()
	for _, fx in fixtures do
		describe(fx.name, function()
			it("is recognised by SaveData.check and loads without error", function()
				expect(SaveData.check(fx.save)).toBe("ok")
				local d = SaveData.deserialize(fx.save)
				expect(type(d)).toBe("table")
			end)
			it("keeps cash, rebirths (up to MAX_REBIRTHS) and slime ids", function()
				local d = SaveData.deserialize(fx.save)
				expect(d.cash).toBe(fx.cash)
				expect(d.rebirths).toBe(math.min(fx.rebirths, Config.MAX_REBIRTHS))
				local ids = idSet(d)
				for _, id in fx.ids do
					expect(ids[id]).toBe(true)
				end
				expect(#d.slimes).toBe(#fx.ids)
				expect(d.favoriteId).toBe(fx.favoriteId)
			end)
			it("round-trips stably (save -> load -> save is identical)", function()
				local d1 = SaveData.deserialize(fx.save)
				local s1 = SaveData.serialize(d1, NOW)
				local d2 = SaveData.deserialize(s1)
				local s2 = SaveData.serialize(d2, NOW)
				expect(stable(s2)).toEqual(stable(s1))
				expect(s1.version).toBe(Config.SAVE_VERSION)
			end)
			it("loads through DataService on the memory store and saves back", function()
				local backend = DataService.memoryBackend()
				backend.records["u_9"] = fx.save -- unwrapped legacy record
				local svc = DataService.new({
					backend = backend,
					jobId = "job-A",
					now = function()
						return NOW
					end,
					wait = function() end,
					log = function() end,
				})
				local ok, d = DataService.load(svc, 9)
				expect(ok).toBe(true)
				expect(DataService.readOnly(svc, 9)).toBeNil()
				local data = d :: PlayerData.Data
				expect(data.cash).toBe(fx.cash)
				local saved, why = DataService.save(svc, 9, data, true)
				expect(saved).toBe(true)
				expect(why).toBeNil()
				expect(backend.records["u_9"].data.version).toBe(Config.SAVE_VERSION)
				expect(backend.records["u_9"].session).toBeNil()
			end)
		end)
	end
end)

describe("what old data becomes", function()
	it("v1 legacy rarity names map to tiers", function()
		local d = SaveData.deserialize(fixtures[1].save)
		local a = PlayerData.findSlime(d, "old-a")
		expect(a and a.tier).toBe(4)
	end)
	it("v2 tutorial steps 4..6 shift up one (BuyPad inserted)", function()
		local d = SaveData.deserialize(fixtures[2].save)
		expect(d.tutorialStep).toBe(6)
	end)
	it("v2 caught is seeded with the slime count", function()
		local d = SaveData.deserialize(fixtures[2].save)
		expect(d.stats.caught).toBe(3)
	end)
	it("mutations vanish but the slime and its tier survive (v3..v6)", function()
		for _, i in { 2, 4, 5, 6 } do
			local d = SaveData.deserialize(fixtures[i].save)
			for _, s in d.slimes do
				expect((s :: any).mutation).toBeNil()
				expect((s :: any).mutations).toBeNil()
			end
		end
	end)
	it("removed species ids are dropped to no species, the slime stays", function()
		local d = SaveData.deserialize(fixtures[4].save)
		local a = PlayerData.findSlime(d, "v4-a")
		local b = PlayerData.findSlime(d, "v4-b")
		local c = PlayerData.findSlime(d, "v4-c")
		expect(a and a.species).toBeNil()
		expect(b and b.species).toBeNil()
		expect(c and c.species).toBe("gummy")
	end)
	it("old combination dex entries and dexRewards are ignored; Dex starts from owned species", function()
		local d = SaveData.deserialize(fixtures[4].save)
		expect(d.speciesRewards).toBe(0)
		expect(PlayerData.dexCount(d)).toBe(1) -- only gummy (v4-c)
	end)
	it("unknown species ids in `found` are dropped, known kept", function()
		local d = SaveData.deserialize(fixtures[6].save)
		expect(d.found.gummy).toBe(true)
		expect(d.found.mochi).toBe(true)
		expect(d.found.ghost_species_removed).toBeNil()
	end)
	it("removed items MutationSpray and RainMagnet are gone, other consumables / upgrades kept", function()
		local d = SaveData.deserialize(fixtures[6].save)
		expect(d.consumables.held.MutationSpray).toBeNil()
		expect(d.consumables.bought.MutationSpray).toBeNil()
		expect(d.consumables.held.LuckPotion).toBe(2)
		expect(d.upgrades.RainMagnet).toBeNil()
		expect(d.upgrades.Income).toBe(9)
	end)
	it("unknown daily quest slots are dropped", function()
		local d = SaveData.deserialize(fixtures[5].save)
		expect(#d.quests.slots).toBe(0)
	end)
	it("codes, boost, plot skin, steal log, settings survive", function()
		local d = SaveData.deserialize(fixtures[3].save)
		expect(d.redeemed.WELCOME).toBe(true)
		expect(d.redeemed.SLIME10).toBe(true)
		expect(d.boostMult).toBe(2)
		local e = SaveData.deserialize(fixtures[6].save)
		expect(e.settings.muted).toBe(true)
		expect(e.settings.musicVolume).toBe(0.3)
		expect(e.pvp.fun.FunConfetti).toBe(true)
		expect(e.pvp.tiers.Knockback).toBe(2)
	end)
	it("an owned trap tier becomes full charges", function()
		local d = SaveData.deserialize(fixtures[7].save)
		expect(d.pvp.traps.GooTrap3).toBe(Config.PVP.TRAP_MAX_HELD)
	end)
	it("each boss trophy becomes one win of that species, with its badge earned and the species found", function()
		local fx = fixtures[8]
		local d = SaveData.deserialize(fx.save)
		expect(d.boss.wins).toEqual({ goozilla = 1, queen_jelly = 1 })
		expect(d.boss.badges).toEqual({ BossGoozilla = fx.save.lastOnline, BossQueenJelly = fx.save.lastOnline })
		expect(d.found.goozilla).toBe(true)
		expect(d.found.queen_jelly).toBe(true)
		expect(d.found.gummy).toBe(true)
		expect((d :: any).trophies).toBeNil()
		expect(d.pvp.traps.GooTrap1).toBe(2)
		expect(d.pvp.tiers.Knockback).toBe(1)
		local saved = SaveData.serialize(d, NOW)
		expect(saved.trophies).toBeNil()
		expect(saved.boss.wins).toEqual({ goozilla = 1, queen_jelly = 1 })
	end)
	it("junk entries are dropped, duplicates collapse, out-of-range tier and pad are clamped", function()
		local d = SaveData.deserialize(fixtures[9].save)
		local b = PlayerData.findSlime(d, "cur-b")
		expect(b and b.tier).toBe(Config.MAX_TIER)
		expect(b and b.pad ~= nil).toBe(true)
	end)
end)

describe("newer and unreadable saves", function()
	local function load(stored: any)
		local backend = DataService.memoryBackend()
		backend.records["u_5"] = stored
		local svc = DataService.new({
			backend = backend,
			jobId = "job-A",
			now = function()
				return NOW
			end,
			wait = function() end,
			log = function() end,
		})
		local ok, d = DataService.load(svc, 5)
		return svc, backend, ok, d
	end
	it("a newer version loads best-effort and is never overwritten", function()
		local stored = {
			version = Config.SAVE_VERSION + 1,
			cash = 777,
			rebirths = 4,
			slimes = { slimeV2("n-a", 2, 1) },
			shinyNewThing = { x = 1 },
		}
		local svc, backend, ok, d = load(stored)
		expect(ok).toBe(true)
		expect(DataService.readOnly(svc, 5)).toBe("newer")
		local data = d :: PlayerData.Data
		expect(data.cash).toBe(777)
		data.cash = 1
		expect(DataService.save(svc, 5, data, false)).toBe(true)
		expect(backend.records["u_5"].data.cash).toBe(777)
		expect(backend.records["u_5"].data.shinyNewThing.x).toBe(1)
		expect(backend.records["u_5"].data.version).toBe(Config.SAVE_VERSION + 1)
		DataService.save(svc, 5, data, true)
		expect(backend.records["u_5"].session).toBeNil()
		expect(backend.records["u_5"].data.cash).toBe(777)
	end)
	it("NaN, string and table versions are unreadable and never overwritten", function()
		for _, v in { 0 / 0, "abc", {} } do
			local svc, backend, ok = load({ version = v, cash = 5 })
			expect(ok).toBe(true)
			expect(DataService.readOnly(svc, 5)).toBe("unreadable")
			DataService.save(svc, 5, PlayerData.new(), true)
			expect(backend.records["u_5"].data.cash).toBe(5)
		end
	end)
	it("a table with no recognisable fields is unreadable, not a fresh profile to overwrite", function()
		local svc, backend = load({ foo = 1 })
		expect(DataService.readOnly(svc, 5)).toBe("unreadable")
		DataService.save(svc, 5, PlayerData.new(), true)
		expect(backend.records["u_5"].data.foo).toBe(1)
	end)
	it("a numeric-string version is read as that version", function()
		expect(SaveData.check({ version = tostring(Config.SAVE_VERSION), cash = 1 })).toBe("ok")
		expect(SaveData.check({ version = tostring(Config.SAVE_VERSION + 1), cash = 1 })).toBe("newer")
	end)
end)
