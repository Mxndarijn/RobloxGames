--!strict
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Genome = require("../src/shared/Genome")
local PlayerData = require("../src/shared/PlayerData")
local Rng = require("../src/shared/Rng")
local SaveData = require("../src/shared/SaveData")
local SessionLock = require("../src/shared/SessionLock")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local serde = require("@lune/serde")

describe("SaveData round trip", function()
	it("serialize -> JSON -> deserialize preserves everything", function()
		local data = Fixtures.data(nil, 1234)
		local rng = Rng.new(11)
		for i = 1, 5 do
			PlayerData.addSlime(data, Genome.generate(rng, { id = `s{i}` }))
		end
		data.rebirths = 3
		data.favoriteId = "s2"
		data.daily = { lastDay = 20000, streak = 4 }
		data.totalStolen = 7
		local json = serde.encode("json", SaveData.serialize(data, 1700000000))
		local back = SaveData.deserialize(serde.decode("json", json))
		expect(back.cash).toBe(1234)
		expect(back.rebirths).toBe(3)
		expect(back.favoriteId).toBe("s2")
		expect(back.lastOnline).toBe(1700000000)
		expect(back.daily).toEqual({ lastDay = 20000, streak = 4 })
		expect(back.totalStolen).toBe(7)
		expect(back.slimes).toEqual(data.slimes)
		expect(back.found).toEqual(data.found)
		expect(next(back.found) ~= nil).toBe(true) -- generated slimes have a species
		expect(back.padsUnlocked).toBe(Config.PADS_MAX)
	end)
	it("keeps the SlimeDex: found species and the species reward ladder", function()
		local data = Fixtures.data(nil, 0)
		data.found.moo = true
		data.found.soda = true
		data.found.goozilla = true
		data.found.glitch = true -- bonus entry
		data.speciesRewards = 2
		local raw = SaveData.serialize(data, 1700000000)
		expect(raw.found).toEqual({ "glitch", "goozilla", "moo", "soda" })
		local back = SaveData.deserialize(serde.decode("json", serde.encode("json", raw)))
		expect(back.found).toEqual(data.found)
		expect(back.speciesRewards).toBe(2)
		expect(SaveData.serialize(back, 1700000000)).toEqual(raw)
	end)
	it("drops junk Dex ids and ignores stamps, and starts an old combination Dex empty", function()
		local back = SaveData.deserialize({
			version = Config.SAVE_VERSION,
			found = { "moo", "nope", 42, "goozilla" },
			stamps = { "moo:Gold", "moo:Nope", "nope:Gold", "goozilla:Gold", "glitch:Gold", 7, "moo" },
			speciesRewards = 99,
			stampRewards = -3,
			dex = { "1:None:Plain:Round" },
			dexRewards = 4,
		})
		expect(back.found).toEqual({ moo = true, goozilla = true })
		expect(back.speciesRewards).toBe(#Config.DEX_MILESTONES.species)
		local fresh = SaveData.deserialize({ version = 2, cash = 5, dex = { "1:None:Plain:Round" } })
		expect(next(fresh.found)).toBeNil()
	end)
	it("a won boss species counts as found", function()
		local raw = SaveData.serialize(Fixtures.data(nil, 0), 1700000000)
		raw.boss = { hits = 4, wins = { goozilla = 2 }, hauls = 0, mvps = 0, badges = {} }
		raw.found = {}
		local back = SaveData.deserialize(raw)
		expect(back.boss.wins.goozilla).toBe(2)
		expect(back.found.goozilla).toBe(true)
	end)
	it("owned slimes are always found on load", function()
		local slime = Fixtures.slime("a", 3, { species = "moo" })
		local raw = SaveData.serialize(Fixtures.data({ slime }, 0), 1700000000)
		raw.found = {}
		local back = SaveData.deserialize(raw)
		expect(back.found.moo).toBe(true)
	end)
	it("serialized output has the current version and integer cash", function()
		local data = Fixtures.data(nil, 10.75)
		local out = SaveData.serialize(data)
		expect(out.version).toBe(Config.SAVE_VERSION)
		expect(out.cash).toBe(10)
	end)
end)

describe("SaveData hotbar order", function()
	it("round-trips a saved order and leaves the key out until one is set", function()
		local data = Fixtures.data(nil, 0)
		local raw = SaveData.serialize(data, 1700000000)
		expect((raw :: any).hotbar).toBeNil()
		expect(SaveData.deserialize(serde.decode("json", serde.encode("json", raw))).hotbar).toBeNil()
		data.hotbar = { "tool:Bat", "", "pvp:KnockGlove1", "", "", "", "", "", "consumable:LuckPotion" }
		raw = SaveData.serialize(data, 1700000000)
		local back = SaveData.deserialize(serde.decode("json", serde.encode("json", raw)))
		expect(back.hotbar).toEqual(data.hotbar)
		expect(back.version).toBe(Config.SAVE_VERSION)
	end)
	it("cleans a junk hotbar: not a list -> nil, bad keys -> empty slots, at most 9", function()
		expect(SaveData.deserialize({ version = Config.SAVE_VERSION, hotbar = "tool:Bat" }).hotbar).toBeNil()
		local back = SaveData.deserialize({
			version = Config.SAVE_VERSION,
			hotbar = { "tool:Bat", {}, "tool:Bat", "x:y", "", "", "", "", "", "pvp:KnockGlove1" },
		})
		expect(back.hotbar).toEqual({ "tool:Bat", "", "", "", "", "", "", "", "" })
	end)
	it("an older save without a hotbar loads with none", function()
		expect(SaveData.deserialize({ version = 6, cash = 5 }).hotbar).toBeNil()
	end)
end)

describe("SaveData.deserialize", function()
	it("gives a fresh profile for nil / garbage", function()
		for _, v in { nil, 5, "x", {}, { foo = 1 } } :: { any } do
			local d = SaveData.deserialize(v)
			expect(d.cash).toBe(Config.STARTING_CASH)
			expect(#d.slimes).toBe(0)
			expect(d.version).toBe(Config.SAVE_VERSION)
		end
	end)
	it("clamps hostile numbers", function()
		local d =
			SaveData.deserialize({ version = 2, cash = -50, rebirths = 1e9, padsUnlocked = 999, lastOnline = 0 / 0 })
		expect(d.cash).toBe(0)
		expect(d.rebirths).toBe(Config.MAX_REBIRTHS)
		expect(d.padsUnlocked).toBe(Config.PADS_MAX)
		expect(d.lastOnline).toBe(0)
	end)
	it("drops invalid and duplicate slimes, fixes clashing pads", function()
		local d = SaveData.deserialize({
			version = 2,
			slimes = {
				{ id = "a", tier = 1, pad = 2 },
				{ id = "a", tier = 3, pad = 3 }, -- duplicate id
				{ id = "b", tier = 2, pad = 2 }, -- pad clash
				{ tier = 2 }, -- no id
				"junk",
				{ id = "c", tier = 1, pad = 99 }, -- out of range
			},
		})
		expect(#d.slimes).toBe(3)
		local pads = {}
		for _, s in d.slimes do
			expect(pads[s.pad :: number]).toBeNil()
			pads[s.pad :: number] = true
			expect((s.pad :: number) <= d.padsUnlocked).toBeTruthy()
		end
		expect(PlayerData.findSlime(d, "a").pad).toBe(2)
	end)
	it("unlocks pads to fit saved slimes and drops overflow beyond PADS_MAX", function()
		local slimes = {}
		for i = 1, Config.PADS_MAX + 3 do
			table.insert(slimes, { id = `s{i}`, tier = 1 })
		end
		local d = SaveData.deserialize({ version = 2, padsUnlocked = 4, slimes = slimes })
		expect(#d.slimes).toBe(Config.PADS_MAX)
		expect(d.padsUnlocked).toBe(Config.PADS_MAX)
	end)
	it("ignores a favourite that isn't owned", function()
		local d = SaveData.deserialize({ version = 2, favoriteId = "ghost", slimes = { { id = "a", tier = 1 } } })
		expect(d.favoriteId).toBeNil()
	end)
	it("reads unknown future versions field by field", function()
		local d = SaveData.deserialize({ version = 99, cash = 77, newField = true })
		expect(d.cash).toBe(77)
	end)
end)

describe("SaveData migration v1 -> v2", function()
	local v1 = {
		Cash = 500,
		Rebirths = 2,
		LastOnline = 1600000000,
		Slimes = {
			{ Id = "old1", Rarity = "Epic", Size = 1.5, Color = { 10, 20, 30 } },
			{ Rarity = "Mythic" },
			{ Id = "old3", Rarity = "Banana" },
		},
	}
	it("detects legacy saves and converts fields", function()
		local d = SaveData.deserialize(v1)
		expect(d.version).toBe(Config.SAVE_VERSION)
		expect(d.cash).toBe(500)
		expect(d.rebirths).toBe(2)
		expect(d.lastOnline).toBe(1600000000)
		expect(#d.slimes).toBe(3)
		local epic = PlayerData.findSlime(d, "old1")
		assert(epic, "precondition")
		expect(epic.tier).toBe(4)
		expect(epic.size).toBe(1.5)
		expect(epic.color).toEqual({ 10, 20, 30 })
		expect(PlayerData.findSlime(d, "legacy-2").tier).toBe(6)
		expect(PlayerData.findSlime(d, "old3").tier).toBe(1)
	end)
	it("migrated saves get pads (legacy slimes have no species, so no Dex entry)", function()
		local d = SaveData.deserialize(v1)
		for _, s in d.slimes do
			expect(s.pad ~= nil).toBeTruthy()
		end
		expect(PlayerData.dexCount(d)).toBe(0)
	end)
	it("re-saving a migrated profile is stable", function()
		local once = SaveData.serialize(SaveData.deserialize(v1))
		local twice = SaveData.serialize(SaveData.deserialize(once))
		expect(twice).toEqual(once)
	end)
end)

describe("SessionLock", function()
	it("unwraps records and legacy saves", function()
		local data, session = SessionLock.unwrap({ data = { cash = 1 }, session = { jobId = "A", time = 5 } })
		expect(data.cash).toBe(1)
		assert(session, "precondition")
		expect(session.jobId).toBe("A")
		local legacy, none = SessionLock.unwrap({ version = 2, cash = 3 })
		expect(legacy.cash).toBe(3)
		expect(none).toBeNil()
		expect((SessionLock.unwrap(nil))).toBeNil()
	end)
	it("status: free / own / locked / stale", function()
		expect(SessionLock.status(nil, "A", 0)).toBe("free")
		expect(SessionLock.status({ jobId = "A", time = 0 }, "A", 1e6)).toBe("own")
		expect(SessionLock.status({ jobId = "B", time = 100 }, "A", 150)).toBe("locked")
		expect(SessionLock.status({ jobId = "B", time = 100 }, "A", 100 + Config.SESSION_STALE_SECONDS + 1)).toBe(
			"stale"
		)
	end)
	it("acquire takes free and stale locks, refuses live ones", function()
		local rec, status = SessionLock.acquire(nil, "A", 10)
		assert(rec and rec.session, "precondition")
		expect(status).toBe("free")
		expect(rec.session.jobId).toBe("A")
		local locked, s2 = SessionLock.acquire({ data = {}, session = { jobId = "B", time = 5 } }, "A", 10)
		expect(locked).toBeNil()
		expect(s2).toBe("locked")
		local stolen, s3 = SessionLock.acquire({ data = { cash = 9 }, session = { jobId = "B", time = 0 } }, "A", 1e6)
		assert(stolen, "precondition")
		expect(s3).toBe("stale")
		expect(stolen.data.cash).toBe(9)
	end)
	it("write refreshes our lock and releases on leave", function()
		local rec, ok = SessionLock.write(
			{ data = {}, session = { jobId = "A", time = 1 } },
			"A",
			50,
			{ cash = 2 },
			false
		)
		assert(rec and rec.session, "precondition")
		expect(ok).toBe(true)
		expect(rec.session.time).toBe(50)
		expect(rec.data.cash).toBe(2)
		local released = SessionLock.write(rec, "A", 60, { cash = 3 }, true)
		assert(released, "precondition")
		expect(released.session).toBeNil()
	end)
	it("write refuses once another server owns the session", function()
		local rec, ok = SessionLock.write({ data = {}, session = { jobId = "B", time = 1 } }, "A", 50, {}, false)
		expect(rec).toBeNil()
		expect(ok).toBe(false)
		local _, ok2 = SessionLock.write({ data = {} }, "A", 50, {}, false)
		expect(ok2).toBe(false)
	end)
	it("backoff grows and is capped", function()
		expect(SessionLock.backoff(1)).toBe(2)
		expect(SessionLock.backoff(2)).toBe(4)
		expect(SessionLock.backoff(10)).toBe(10)
	end)
end)

describe("SaveData tutorial remap (v3 BuyPad step)", function()
	it("moves an old save's Merge / Steal / Rebirth step up one and keeps done / early steps", function()
		for old, new in { [0] = 0, [1] = 1, [3] = 3, [4] = 5, [5] = 6, [6] = 7 } do
			local d = SaveData.deserialize({ version = 2, cash = 10, slimes = {}, tutorialStep = old })
			expect(d.tutorialStep).toBe(new)
		end
		local v3 = SaveData.deserialize({ version = 3, cash = 10, slimes = {}, tutorialStep = 4 })
		expect(v3.tutorialStep).toBe(4)
	end)
end)

describe("SaveData.check", function()
	it("says what may be overwritten", function()
		expect(SaveData.check(nil)).toBe("empty")
		expect(SaveData.check(SaveData.serialize(PlayerData.new(), 1))).toBe("ok")
		expect(SaveData.check({ version = 2, cash = 5 })).toBe("ok")
		expect(SaveData.check({ Cash = 5, Slimes = {} })).toBe("ok") -- v1 legacy
		expect(SaveData.check({ version = Config.SAVE_VERSION + 1, cash = 5 })).toBe("newer")
		expect(SaveData.check("garbage")).toBe("unreadable")
		expect(SaveData.check(42)).toBe("unreadable")
		expect(SaveData.check({})).toBe("unreadable")
		expect(SaveData.check({ version = "abc", cash = 5 })).toBe("unreadable")
		expect(SaveData.check({ version = 0 / 0 })).toBe("unreadable")
	end)
end)
