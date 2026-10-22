--!strict
-- The boss record and its save-only boss badges (src/shared/BossBadges.luau, Config.BOSS_BADGES,
-- contract/boss-event.md).
local BossBadges = require("../src/shared/BossBadges")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local PlayerData = require("../src/shared/PlayerData")
local SaveData = require("../src/shared/SaveData")
local SlimeRoster = require("../src/shared/SlimeRoster")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local WIN_SHARE = Config.BOSS.WIN_SHARE

describe("Config.BOSS_BADGES", function()
	it("has unique keys, known triggers and a win badge for every boss species", function()
		local keys: { [string]: boolean } = {}
		local winFor: { [string]: boolean } = {}
		local triggers = { hits = true, win = true, wins = true, hauls = true, mvps = true }
		for _, badge in Config.BOSS_BADGES do
			expect(keys[badge.key]).toBeNil()
			keys[badge.key] = true
			expect(triggers[badge.trigger]).toBe(true)
			expect(type(badge.name)).toBe("string")
			expect(type(badge.description)).toBe("string")
			expect(badge.value >= 1).toBe(true)
			local species = (badge :: any).species
			if badge.trigger == "win" then
				local entry = SlimeRoster.get(species)
				expect(entry and entry.kind).toBe("boss")
				winFor[species] = true
			end
		end
		for _, entry in SlimeRoster.ofKind("boss") do
			expect(winFor[entry.id]).toBe(true)
		end
	end)
end)

describe("BossBadges.record", function()
	it("counts hits, hauls and MVPs", function()
		local data = PlayerData.new()
		expect(BossBadges.record(data, { kind = "hit" })).toBe(true)
		BossBadges.record(data, { kind = "hit" })
		BossBadges.record(data, { kind = "haul" })
		BossBadges.record(data, { kind = "mvp" })
		expect(data.boss.hits).toBe(2)
		expect(data.boss.hauls).toBe(1)
		expect(data.boss.mvps).toBe(1)
	end)
	it("counts a win only for a boss species and a share of at least WIN_SHARE", function()
		local data = PlayerData.new()
		expect(BossBadges.record(data, { kind = "win", species = "goozilla", share = WIN_SHARE })).toBe(true)
		expect(BossBadges.record(data, { kind = "win", species = "goozilla", share = WIN_SHARE / 2 })).toBe(false)
		expect(BossBadges.record(data, { kind = "win", species = "gummy", share = 1 })).toBe(false)
		expect(BossBadges.record(data, { kind = "win", share = 1 })).toBe(false)
		expect(data.boss.wins).toEqual({ goozilla = 1 })
	end)
end)

describe("BossBadges.reached / grant", function()
	it("a fresh record reaches nothing", function()
		local data = PlayerData.new()
		expect(BossBadges.reached(data)).toEqual({})
		expect(BossBadges.grant(data, 100)).toEqual({})
		expect(BossBadges.count(data)).toBe(0)
	end)
	it("each trigger earns its badge once, stamped with the time", function()
		local data = PlayerData.new()
		BossBadges.record(data, { kind = "hit" })
		expect(BossBadges.grant(data, 100.7)).toEqual({ "BossBrawler" })
		expect(BossBadges.grant(data, 200)).toEqual({})
		expect(data.boss.badges.BossBrawler).toBe(100)
		BossBadges.record(data, { kind = "win", species = "queen_jelly", share = 1 })
		BossBadges.record(data, { kind = "haul" })
		BossBadges.record(data, { kind = "mvp" })
		expect(BossBadges.grant(data, 300)).toEqual({ "BossQueenJelly", "BossHauler", "BossMvp" })
		expect(BossBadges.count(data)).toBe(4)
		expect(BossBadges.view(data)[1]).toEqual({ key = "BossBrawler", earnedAt = 100 })
	end)
	it("Boss Hunter needs 10 wins over every species", function()
		local data = PlayerData.new()
		for i = 1, 9 do
			local species = if i % 2 == 0 then "goozilla" else "mecha_goo"
			BossBadges.record(data, { kind = "win", species = species, share = 1 })
		end
		expect(table.find(BossBadges.reached(data), "BossHunter10")).toBeNil()
		BossBadges.record(data, { kind = "win", species = "goozilla", share = 1 })
		expect(table.find(BossBadges.grant(data, 1), "BossHunter10") ~= nil).toBe(true)
		expect(BossBadges.totalWins(data.boss)).toBe(10)
	end)
end)

describe("BossBadges.clean", function()
	it("missing or junk gives a fresh record", function()
		expect(BossBadges.clean(nil)).toEqual(BossBadges.new())
		expect(BossBadges.clean("x")).toEqual(BossBadges.new())
	end)
	it("clamps numbers and drops unknown species and badge keys", function()
		local out = BossBadges.clean({
			hits = -5,
			hauls = 2.9,
			mvps = 0 / 0,
			wins = { goozilla = 3, gummy = 2, nope = 1, mecha_goo = "x", queen_jelly = 0 },
			badges = { BossBrawler = 1700000000, Nope = 5, [3] = 1 },
		})
		expect(out.hits).toBe(0)
		expect(out.hauls).toBe(2)
		expect(out.mvps).toBe(0)
		expect(out.wins).toEqual({ goozilla = 3 })
		expect(out.badges).toEqual({ BossBrawler = 1700000000 })
	end)
end)

describe("SaveData boss record", function()
	it("round-trips the record and its badges", function()
		local data = Fixtures.data(nil, 0)
		BossBadges.record(data, { kind = "hit" })
		BossBadges.record(data, { kind = "win", species = "mecha_goo", share = 1 })
		BossBadges.grant(data, 1700000000)
		local back = SaveData.deserialize(SaveData.serialize(data, 1700000100))
		expect(back.boss).toEqual(data.boss)
	end)
	it("grants a reached but unstamped badge on load, at lastOnline, and finds won species", function()
		local raw = SaveData.serialize(Fixtures.data(nil, 0), 1700000000)
		raw.boss = { hits = 1, wins = { queen_jelly = 1 }, hauls = 0, mvps = 0, badges = {} }
		raw.found = {}
		local back = SaveData.deserialize(raw)
		expect(back.boss.badges).toEqual({ BossBrawler = 1700000000, BossQueenJelly = 1700000000 })
		expect(back.found.queen_jelly).toBe(true)
	end)
	it("boss wins earn no income", function()
		local data = Fixtures.data({ Fixtures.slime("a", 3, { pad = 1 }) }, 0)
		local before = PlayerData.incomePerSecond(data)
		BossBadges.record(data, { kind = "win", species = "goozilla", share = 1 })
		expect(PlayerData.incomePerSecond(data)).toBe(before)
	end)
end)
