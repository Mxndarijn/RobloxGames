--!strict
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local Fixtures = require("./Fixtures")
local Progression = require("../src/shared/Progression")
local Rebirth = require("../src/server/Rebirth")
local ServerFixtures = require("./ServerFixtures")
local SlimeRoster = require("../src/shared/SlimeRoster")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

describe("Rebirth.rebirth", function()
	it("wipes cash and slimes, keeps the favourite, adds a rebirth", function()
		local world = ServerFixtures.world()
		local cost = Economy.rebirthCost(0)
		local s = ServerFixtures.join(
			world,
			1,
			{ Fixtures.slime("a", 5), Fixtures.slime("fav", 1, { species = "bumble" }) },
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
			{ Fixtures.slime("best", 6), Fixtures.slime("meh", 1, { species = "bumble" }) },
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

describe("Rebirth slime requirement (v29)", function()
	it("maps every configured level to a roster species with escalating rarity", function()
		local last = 0
		local levels = {}
		for level in Config.REBIRTH_SLIMES do
			table.insert(levels, level)
		end
		table.sort(levels)
		expect(levels[1]).toBe(1)
		for _, level in levels do
			local entry = SlimeRoster.get(Config.REBIRTH_SLIMES[level])
			assert(entry, `unknown species at level {level}`)
			expect(entry.tier >= last).toBe(true)
			last = entry.tier
		end
	end)
	it("looks up the species for a level, carrying the last entry forward", function()
		expect(Progression.requiredSpecies(0)).toBe("bumble")
		expect(Progression.requiredSpecies(2)).toBe("lop")
		expect(Progression.requiredSpecies(10)).toBe("cosmo")
		expect(Progression.requiredSpecies(14)).toBe("midas")
		expect(Progression.requiredSpecies(40)).toBe("eclipse")
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
	it(
		"asks for the next level's species after a rebirth, and the owned slime is kept by the normal keeper rule",
		function()
			local world = ServerFixtures.world()
			local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2, { species = "bumble" }) }, 1e9)
			expect((Rebirth.rebirth(world, s))).toBe(true)
			expect(s.data.slimes[1].id).toBe("a") -- not consumed
			s.data.cash = 1e12
			expect(select(2, Rebirth.rebirth(world, s))).toBe("need a Froggo")
		end
	)
	it("reports the requirement for the snapshot, and nothing at max level", function()
		local data = Fixtures.data({ Fixtures.slime("a", 2, { species = "bumble" }) })
		local need = Progression.requiredSlime(data)
		assert(need, "precondition")
		expect(need.id).toBe("bumble")
		expect(need.name).toBe("Bumble")
		expect(need.owned).toBe(true)
		expect((Progression.requiredSlime(Fixtures.data()) :: any).owned).toBe(false)
		data.rebirths = Config.MAX_REBIRTHS
		expect(Progression.requiredSlime(data)).toBeNil()
		expect(select(2, Progression.canRebirth(data))).toBe("max rebirths reached")
	end)
end)
