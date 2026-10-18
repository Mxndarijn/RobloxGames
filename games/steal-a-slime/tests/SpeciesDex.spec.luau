--!strict
-- The species Dex (src/shared/SpeciesDex.luau, CONTRACT.md §36): entries, stamps, counts and State.dex, and
-- data.found / data.stamps set from every way a player gets a slime.
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Genome = require("../src/shared/Genome")
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
	return { found = {}, stamps = {} }
end

local function slime(species: string?, mutations: { string }?): any
	local s = Fixtures.slime("x", 1, { species = species })
	Genome.setMutations(s, mutations or {})
	return s
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

describe("SpeciesDex entries and stamps", function()
	it("has 50 entries (spawn, hybrid, boss) and the event Secrets as bonus entries", function()
		expect(SpeciesDex.TOTAL).toBe(50)
		expect(#SpeciesDex.ENTRIES).toBe(50)
		for _, e in SpeciesDex.ENTRIES do
			expect(e.kind ~= "event").toBe(true)
		end
		expect(#SpeciesDex.BONUS).toBe(#SlimeRoster.ofKind("event"))
		expect(SpeciesDex.STAMP_TOTAL).toBe(47 * 8)
		expect(#SpeciesDex.CORE_STAMPS).toBe(#Config.MUTATIONS + 1)
		expect(SpeciesDex.CORE_STAMPS[1]).toBe("None")
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
		expect(SpeciesDex.isStamp("moo:Gold")).toBe(true)
		expect(SpeciesDex.isStamp("soda:None")).toBe(true)
		expect(SpeciesDex.isStamp("moo:Solar")).toBe(true) -- gold stamp
		expect(SpeciesDex.isStamp("goozilla:Gold")).toBe(false) -- bosses have none
		expect(SpeciesDex.isStamp("glitch:Gold")).toBe(false) -- nor event Secrets
		expect(SpeciesDex.isStamp("moo:Nope")).toBe(false)
		expect(SpeciesDex.isStamp("moo")).toBe(false)
		expect(SpeciesDex.isStamp("eclipse:Eclipse")).toBe(true) -- the species and the mutation share a word
	end)
end)

describe("SpeciesDex.record", function()
	it("marks the species found once and stamps its primary mutation", function()
		local data = blank()
		expect(SpeciesDex.record(data, slime("moo", { "Glow", "Gold" }))).toBe(true)
		expect(SpeciesDex.record(data, slime("moo"))).toBe(false)
		expect(data.found.moo).toBe(true)
		expect(data.stamps["moo:Gold"]).toBe(true) -- Gold beats Glow
		expect(data.stamps["moo:Glow"]).toBeNil()
		expect(data.stamps["moo:None"]).toBe(true)
		expect(SpeciesDex.count(data)).toBe(1)
		expect(SpeciesDex.stampCount(data)).toBe(2)
	end)
	it("combo and weather mutations are gold stamps outside the total", function()
		local data = blank()
		SpeciesDex.record(data, slime("gummy", { "Solar" }))
		SpeciesDex.record(data, slime("gummy", { "Wet" }))
		expect(SpeciesDex.stampCount(data)).toBe(0)
		expect(SpeciesDex.goldCount(data)).toBe(2)
	end)
	it("bosses are found without stamps; event Secrets count as bonus only", function()
		local data = blank()
		SpeciesDex.record(data, slime("goozilla", { "Glow" }))
		SpeciesDex.record(data, slime("glitch", { "Gold" }))
		expect(data.found.goozilla).toBe(true)
		expect(next(data.stamps)).toBeNil()
		expect(SpeciesDex.count(data)).toBe(1)
		expect(SpeciesDex.bonusCount(data)).toBe(1)
	end)
	it("ignores slimes without a known species", function()
		local data = blank()
		expect(SpeciesDex.record(data, slime(nil))).toBe(false)
		expect(SpeciesDex.record(data, slime("nope"))).toBe(false)
		expect(next(data.found)).toBeNil()
		expect(next(data.stamps)).toBeNil()
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
		SpeciesDex.record(data, slime("gummy", { "Solar" }))
		SpeciesDex.record(data, slime("gummy", { "Glow" }))
		local view = SpeciesDex.view(data, NOW, SOURCES)
		expect(view.found).toBe(1)
		expect(view.total).toBe(50)
		expect(view.stamps).toBe(1)
		expect(view.stampTotal).toBe(376)
		expect(view.gold).toBe(1)
		expect(view.bonusTotal).toBe(#SpeciesDex.BONUS)
		expect(#view.entries).toBe(50 + #SpeciesDex.BONUS)
		expect(view.entries[51].kind).toBe("event")
		local gummy = entry(view, "gummy")
		expect(gummy.found).toBe(true)
		expect(gummy.name).toBe("Gummy")
		expect(table.concat(gummy.stamps, ",")).toBe("Glow")
		expect(table.concat(gummy.gold, ",")).toBe("Solar")
	end)
	it("never names an unfound spawn species", function()
		local moo = entry(SpeciesDex.view(blank(), NOW, SOURCES), "moo")
		expect(moo.found).toBe(false)
		expect(moo.name).toBeNil()
		expect(moo.hint).toBeNil()
		expect(#moo.stamps).toBe(0)
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
		local caught = PlayerData.findSlime(s.data, id) :: any
		expect(s.data.stamps[`moo:{Genome.primaryMutation(Genome.mutationList(caught))}`]).toBe(true)
	end)
	it("steal: the thief finds the stolen species", function()
		local victim = Fixtures.data({ Fixtures.slime("v", 4, { species = "octo" }) })
		local thief = Fixtures.data()
		expect((Steal.complete(victim, thief, "v"))).toBe(true)
		expect(thief.found.octo).toBe(true)
		expect(thief.stamps["octo:None"]).toBe(true)
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
		PlayerData.addSlime(
			data,
			Fixtures.slime("h", 2, { species = "soda", mutation = "Glow", mutations = { "Glow" } })
		)
		expect(data.found.soda).toBe(true)
		expect(data.stamps["soda:Glow"]).toBe(true)
	end)
	it("boss trophy: a slime given without a pad goes through PlayerData.discover", function()
		local data = Fixtures.data()
		expect(PlayerData.discover(data, Fixtures.slime("boss", 6, { species = "goozilla" }))).toBe(true)
		expect(data.found.goozilla).toBe(true)
		expect(SpeciesDex.count(data)).toBe(1)
	end)
	it("egg: a hatched Mystery Egg slime", function()
		local data = Fixtures.data(nil, 1e9)
		local ok, hatched = MysteryEgg.buy(data, Rng.new(7), "egg")
		expect(ok).toBe(true)
		local species = (hatched :: any).species :: string
		expect(species ~= nil and data.found[species]).toBe(true)
	end)
end)
