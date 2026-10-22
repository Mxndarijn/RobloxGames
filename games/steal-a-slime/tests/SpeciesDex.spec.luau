--!strict
-- The species Dex (src/shared/SpeciesDex.luau, CONTRACT.md §36): entries, counts and State.dex, and
-- data.found set from every way a player gets a slime.
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local MysteryEgg = require("../src/shared/MysteryEgg")
local PlayerData = require("../src/shared/PlayerData")
local Rng = require("../src/shared/Rng")
local ServerFixtures = require("./ServerFixtures")
local SlimeRoster = require("../src/shared/SlimeRoster")
local Spawner = require("../src/server/Spawner")
local SpeciesDex = require("../src/shared/SpeciesDex")
local Steal = require("../src/shared/Steal")
local TestRunner = require("./TestRunner")
local TripleMerge = require("../src/shared/TripleMerge")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

local function blank(): SpeciesDex.Data
	return { found = {} }
end

local function slime(species: string?): any
	return Fixtures.slime("x", 1, { species = species })
end

local function entry(view: SpeciesDex.View, id: string): SpeciesDex.EntryView
	for _, e in view.entries do
		if e.id == id then
			return e
		end
	end
	error(`no entry {id}`)
end

local WEEK = 7 * 86400
local NOW = 1760918400 + 3 * 86400 -- a Thursday
local RECIPES = {
	soda = { inputs = { "bubbles", "gummy", "mochi" }, hint = "Fizzy, chewy and soft." },
	truffle = { inputs = { "flan", "flan", "mushie" }, hint = "Double caramel on a mushroom." },
}
local WEEKS = { glitch = 1760918400, doodle = 1760918400 + WEEK }
local SOURCES = Fixtures.dexSources(RECIPES, WEEKS)

describe("SpeciesDex entries", function()
	it("has 50 entries (spawn, hybrid, boss) and the event Secrets as bonus entries", function()
		expect(SpeciesDex.TOTAL).toBe(50)
		expect(#SpeciesDex.ENTRIES).toBe(50)
		for _, e in SpeciesDex.ENTRIES do
			expect(e.kind ~= "event").toBe(true)
		end
		expect(#SpeciesDex.BONUS).toBe(#SlimeRoster.ofKind("event"))
	end)
	it("every tier has entries, and the tier sizes add up to the total", function()
		local sum = 0
		for tier = 1, Config.MAX_TIER do
			expect(SpeciesDex.tierSize(tier) > 0).toBe(true)
			sum += SpeciesDex.tierSize(tier)
		end
		expect(sum).toBe(SpeciesDex.TOTAL)
	end)
	it("knows which keys can exist", function()
		expect(SpeciesDex.isSpecies("moo")).toBe(true)
		expect(SpeciesDex.isSpecies("glitch")).toBe(true)
		expect(SpeciesDex.isSpecies("nope")).toBe(false)
		expect(SpeciesDex.isSpecies(5)).toBe(false)
	end)
end)

describe("SpeciesDex.record", function()
	it("marks the species found once", function()
		local data = blank()
		expect(SpeciesDex.record(data, slime("moo"))).toBe(true)
		expect(SpeciesDex.record(data, slime("moo"))).toBe(false)
		expect(data.found.moo).toBe(true)
		expect(SpeciesDex.count(data)).toBe(1)
	end)
	it("bosses are found; event Secrets count as bonus only", function()
		local data = blank()
		SpeciesDex.record(data, slime("goozilla"))
		SpeciesDex.record(data, slime("glitch"))
		expect(data.found.goozilla).toBe(true)
		expect(SpeciesDex.count(data)).toBe(1)
		expect(SpeciesDex.bonusCount(data)).toBe(1)
	end)
	it("ignores slimes without a known species", function()
		local data = blank()
		expect(SpeciesDex.record(data, slime(nil))).toBe(false)
		expect(SpeciesDex.record(data, slime("nope"))).toBe(false)
		expect(next(data.found)).toBeNil()
	end)
	it("tierCount / tierMask follow the found entries", function()
		local data = blank()
		data.found.gummy, data.found.moo, data.found.glitch = true, true, true
		expect(SpeciesDex.tierCount(data, 1)).toBe(1)
		expect(SpeciesDex.tierCount(data, 3)).toBe(1)
		expect(SpeciesDex.tierCount(data, 7)).toBe(0) -- the event Secret is not in a set
		expect(SpeciesDex.tierMask(data)).toBe(0b101)
	end)
end)

describe("SpeciesDex.view (State.dex)", function()
	it("counts and lists every entry, then the bonus entries", function()
		local data = blank()
		SpeciesDex.record(data, slime("gummy"))
		local view = SpeciesDex.view(data, NOW, SOURCES)
		expect(view.found).toBe(1)
		expect(view.total).toBe(50)
		expect(view.bonusTotal).toBe(#SpeciesDex.BONUS)
		expect(#view.entries).toBe(50 + #SpeciesDex.BONUS)
		expect(view.entries[51].kind).toBe("event")
		local gummy = entry(view, "gummy")
		expect(gummy.found).toBe(true)
		expect(gummy.name).toBe("Gummy")
	end)
	it("never names an unfound spawn species", function()
		local moo = entry(SpeciesDex.view(blank(), NOW, SOURCES), "moo")
		expect(moo.found).toBe(false)
		expect(moo.name).toBeNil()
		expect(moo.hint).toBeNil()
	end)
	it("a hybrid always shows its hint; slots reveal found ingredients; the name shows once known", function()
		local data = blank()
		data.found.gummy = true
		local soda = entry(SpeciesDex.view(data, NOW, SOURCES), "soda")
		expect(soda.hint).toBe("Fizzy, chewy and soft.")
		expect(table.concat(soda.ingredients :: { string }, ",")).toBe(",gummy,")
		expect(soda.name).toBeNil()
		data.found.bubbles, data.found.mochi = true, true
		soda = entry(SpeciesDex.view(data, NOW, SOURCES), "soda")
		expect(soda.found).toBe(false)
		expect(soda.name).toBe("Soda Pop") -- known recipe
		-- A repeated ingredient fills both of its slots.
		data.found.flan = true
		local truffle = entry(SpeciesDex.view(data, NOW, SOURCES), "truffle")
		expect(table.concat(truffle.ingredients :: { string }, ",")).toBe("flan,flan,")
	end)
	it("a hybrid without a recipe source keeps no hint and no slots", function()
		local soda = entry(SpeciesDex.view(blank(), NOW, Fixtures.dexSources()), "soda")
		expect(soda.hint).toBeNil()
		expect(soda.ingredients).toBeNil()
	end)
	it("bosses say Defeat the boss event", function()
		local boss = entry(SpeciesDex.view(blank(), NOW, SOURCES), "mecha_goo")
		expect(boss.hint).toBe("Defeat the boss event")
		expect(boss.name).toBeNil()
	end)
	it("event Secrets: the featured one is named with its week, an owned one too, the rest are ???", function()
		local data = blank()
		data.found.doodle = true
		local view = SpeciesDex.view(data, NOW, SOURCES)
		local glitch = entry(view, "glitch") -- featured this week
		expect(glitch.name).toBe("Gl1tch")
		expect(glitch.hint).toBe(`Featured Secret: week of {SpeciesDex.weekLabel(WEEKS.glitch)}`)
		local doodle = entry(view, "doodle") -- owned, featured next week
		expect(doodle.name).toBe("Doodle")
		expect(doodle.hint).toBe(`Featured Secret: week of {SpeciesDex.weekLabel(WEEKS.doodle)}`)
		local disco = entry(view, "disco") -- neither
		expect(disco.name).toBeNil()
		expect(disco.hint).toBe("???")
		expect(SpeciesDex.weekLabel(1760918400)).toBe("20 Oct")
	end)
end)

describe("data.found is set from every source", function()
	it("catch: a wild slime brought home", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, nil, 0)
		local id = Spawner.spawnOne(world, T0)
		world.wild[id].price = 0
		world.wild[id].slime.species = "moo"
		world.wild[id].slime.tier = 3
		Carry.grab(world, 1, id, 1, T0)
		expect((Carry.deposit(world, 1))).toBe(true)
		expect(s.data.found.moo).toBe(true)
	end)
	it("steal: the thief finds the stolen species", function()
		local victim = Fixtures.data({ Fixtures.slime("v", 4, { species = "octo" }) })
		local thief = Fixtures.data()
		expect((Steal.complete(victim, thief, "v"))).toBe(true)
		expect(thief.found.octo).toBe(true)
	end)
	it("merge: the vat child's species", function()
		local data = Fixtures.data({
			Fixtures.slime("a", 1, { species = "gummy" }),
			Fixtures.slime("b", 1, { species = "mochi" }),
			Fixtures.slime("c", 1, { species = "pebble" }),
		})
		local ok, child = TripleMerge.apply(data, { "a", "b", "c" }, nil, Rng.new(4), "child")
		expect(ok).toBe(true)
		local species = (child :: any).species :: string
		expect(species ~= nil).toBe(true)
		expect(data.found[species]).toBe(true)
	end)
	it("recipe: a hybrid child placed by the vat", function()
		local data = Fixtures.data()
		PlayerData.addSlime(data, Fixtures.slime("h", 2, { species = "soda" }))
		expect(data.found.soda).toBe(true)
	end)
	it("boss win: a slime credited without a pad goes through PlayerData.discover", function()
		local data = Fixtures.data()
		expect(PlayerData.discover(data, Fixtures.slime("boss", 6, { species = "goozilla" }))).toBe(true)
		expect(data.found.goozilla).toBe(true)
		expect(SpeciesDex.count(data)).toBe(1)
	end)
	it("egg: a Mystery Egg records its species at the hatch, not before", function()
		local egg = Fixtures.slime("egg", 3, { species = "lop", egg = { kind = "speckled", hatchAt = 0 } })
		local data = Fixtures.data({ egg })
		expect(data.found.lop).toBeNil()
		expect((MysteryEgg.hatchEgg(data, "egg", 1))).toBe(true)
		expect(data.found.lop).toBe(true)
	end)
end)
