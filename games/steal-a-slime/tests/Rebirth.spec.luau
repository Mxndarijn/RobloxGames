--!strict
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local Fixtures = require("./Fixtures")
local FountainTiers = require("../src/shared/FountainTiers")
local MergeRecipes = require("../src/shared/MergeRecipes")
local PlayerData = require("../src/shared/PlayerData")
local Progression = require("../src/shared/Progression")
local Rebirth = require("../src/server/Rebirth")
local ServerFixtures = require("./ServerFixtures")
local SlimeRoster = require("../src/shared/SlimeRoster")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

-- Rebirths a player needs before slimes of `id` can be caught (a hybrid: its recipe's inputs).
local function openAt(id: string): number
	local entry = assert(SlimeRoster.get(id), `unknown species {id}`)
	if entry.kind == "hybrid" then
		local recipe = assert(MergeRecipes.recipeFor(id), `no recipe for {id}`)
		local most = 0
		for _, input in recipe.inputs do
			most = math.max(most, openAt(input))
		end
		return most
	end
	return if entry.family then assert(FountainTiers.rebirthsFor(entry.family)) else 0
end

describe("Rebirth.rebirth", function()
	it("wipes cash and slimes, keeps the favourite, adds a rebirth", function()
		local world = ServerFixtures.world()
		local cost = Economy.rebirthCost(0)
		local s = ServerFixtures.join(
			world,
			1,
			{ Fixtures.slime("a", 5), Fixtures.slime("fav", 3), Fixtures.slime("b", 2, { species = "bumble" }) },
			cost
		)
		s.data.favoriteId = "fav"
		expect((Rebirth.rebirth(world, s))).toBe(true)
		expect(s.data.rebirths).toBe(1)
		expect(s.data.cash).toBe(Config.STARTING_CASH)
		expect(#s.data.slimes).toBe(1)
		expect(s.data.slimes[1].id).toBe("fav")
		expect(s.data.slimes[1].pad).toBe(1)
	end)
	it("refuses without enough cash", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a") }, 10)
		expect(select(2, Rebirth.rebirth(world, s))).toBe("not enough cash")
		expect(#s.data.slimes).toBe(1)
	end)
	it("never keeps a slime that is being stolen and ends that carry", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(
			world,
			1,
			{ Fixtures.slime("best", 6), Fixtures.slime("meh", 1), Fixtures.slime("b", 2, { species = "bumble" }) },
			1e9
		)
		local thief = ServerFixtures.join(world, 2)
		ServerFixtures.unlock(s)
		Carry.grab(world, 2, "best", 1, T0)
		expect((Rebirth.rebirth(world, s))).toBe(true)
		expect(s.data.slimes[1].id).toBe("meh")
		expect(thief.carry).toBeNil()
		expect(world.carriedBy.best).toBeNil()
	end)
end)

describe("Rebirth slime requirement", function()
	it("has its own list of one to three known species for every rebirth", function()
		expect(#Config.REBIRTH_SLIMES).toBe(Config.MAX_REBIRTHS)
		local seen: { [string]: number } = {}
		for level, list in Config.REBIRTH_SLIMES do
			expect(#list >= 1 and #list <= 3).toBe(true)
			for _, id in list do
				local entry = SlimeRoster.get(id)
				assert(entry, `unknown species {id} at level {level}`)
				expect(entry.kind ~= "event").toBe(true)
			end
			local key = MergeRecipes.key(list)
			expect(`{key}: {seen[key] or "new"}`).toBe(`{key}: new`)
			seen[key] = level
		end
	end)
	it("only asks for slimes a player of that rank can catch or merge", function()
		for level, list in Config.REBIRTH_SLIMES do
			for _, id in list do
				-- Rebirth `level` is done at level - 1 rebirths.
				expect(`{level} {id}: {openAt(id) <= level - 1}`).toBe(`{level} {id}: true`)
			end
		end
	end)
	it("gets harder: the best rarity asked for never drops by more than two tiers", function()
		local best = 0
		for level, list in Config.REBIRTH_SLIMES do
			local top = 0
			for _, id in list do
				top = math.max(top, (SlimeRoster.get(id) :: SlimeRoster.Entry).tier)
			end
			expect(`{level}: {top >= best - 2}`).toBe(`{level}: true`)
			best = math.max(best, top)
		end
		expect(best).toBe(SlimeRoster.SECRET_TIER)
	end)
	it("looks up the list for the next rebirth, nothing past the last", function()
		expect(table.concat(Progression.requiredSpecies(0), ",")).toBe(table.concat(Config.REBIRTH_SLIMES[1], ","))
		expect(table.concat(Progression.requiredSpecies(5), ",")).toBe(table.concat(Config.REBIRTH_SLIMES[6], ","))
		expect(#Progression.requiredSpecies(Config.MAX_REBIRTHS)).toBe(0)
	end)
	it("is rejected without the slime, with a reason, and wipes nothing", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 3) }, 1e9)
		expect(select(2, Rebirth.rebirth(world, s))).toBe("need a Bumble")
		expect(s.data.rebirths).toBe(0)
		expect(#s.data.slimes).toBe(1)
		expect(s.data.cash).toBe(1e9)
	end)
	it("needs the cash too, even when the slime is owned", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2, { species = "bumble" }) }, 10)
		expect(select(2, Rebirth.rebirth(world, s))).toBe("not enough cash")
	end)
	it("uses the required slime up, even when it is the favourite", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2, { species = "bumble" }) }, 1e9)
		s.data.favoriteId = "a"
		expect((Rebirth.rebirth(world, s))).toBe(true)
		expect(#s.data.slimes).toBe(0)
		expect(s.data.favoriteId).toBeNil()
		s.data.cash = 1e12
		expect(select(2, Rebirth.rebirth(world, s))).toBe("need a Froggo")
	end)
	it("uses up the weakest match and keeps a better one of the same species", function()
		local data = Fixtures.data({
			Fixtures.slime("big", 2, { species = "bumble", size = 3 }),
			Fixtures.slime("small", 2, { species = "bumble" }),
		}, 1e9)
		local ok, kept = Progression.rebirth(data)
		expect(ok).toBe(true)
		expect((kept :: any).id).toBe("big")
		expect(#data.slimes).toBe(1)
	end)
	it("spares the favourite when another slime of the species can pay", function()
		local data = Fixtures.data({
			Fixtures.slime("fav", 2, { species = "bumble" }),
			Fixtures.slime("big", 2, { species = "bumble", size = 3 }),
		}, 1e9)
		data.favoriteId = "fav"
		local _, kept = Progression.rebirth(data)
		expect((kept :: any).id).toBe("fav")
	end)
	it("needs one slime per listed species and uses all of them up", function()
		local need = Config.REBIRTH_SLIMES[6]
		expect(#need).toBe(2)
		local data = Fixtures.data({
			Fixtures.slime("first", 2, { species = need[1] }),
			Fixtures.slime("other", 1),
		}, 1e12)
		data.rebirths = 5
		expect(select(2, Progression.canRebirth(data))).toBe(`need a {(SlimeRoster.get(need[2]) :: any).name}`)
		PlayerData.addSlime(data, Fixtures.slime("second", 2, { species = need[2] }))
		expect((Progression.rebirth(data))).toBe(true)
		expect(#data.slimes).toBe(1)
		expect(data.slimes[1].id).toBe("other")
	end)
	it("reports one row per slime for the snapshot, and nothing at max level", function()
		local data = Fixtures.data({ Fixtures.slime("a", 2, { species = "bumble" }) })
		local rows = Progression.requiredSlimes(data)
		expect(#rows).toBe(1)
		expect(rows[1].id).toBe("bumble")
		expect(rows[1].name).toBe("Bumble")
		expect(rows[1].owned).toBe(true)
		expect(Progression.requiredSlimes(Fixtures.data())[1].owned).toBe(false)
		data.rebirths = Config.MAX_REBIRTHS
		expect(#Progression.requiredSlimes(data)).toBe(0)
		expect(select(2, Progression.canRebirth(data))).toBe("max rebirths reached")
	end)
	it("an egg of the species doesn't count", function()
		local data = Fixtures.data({ Fixtures.slime("e", 2, { species = "bumble", egg = "speckled" }) }, 1e9)
		expect(select(2, Progression.canRebirth(data))).toBe("need a Bumble")
	end)
end)
