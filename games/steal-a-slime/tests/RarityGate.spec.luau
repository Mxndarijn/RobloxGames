--!strict
-- Rarity gates (contract/slime-ladder.md §45.1): a wild slime of a gated rarity needs CATCH_REBIRTHS to grab,
-- stealing is never gated, and the Lucky Charm never lifts a slime past the player's gate.
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local PlayerData = require("../src/shared/PlayerData")
local ServerFixtures = require("./ServerFixtures")
local StealService = require("../src/server/StealService")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

-- Puts a free wild slime of `tier` at the fountain and returns its id.
local function wild(world: any, id: string, tier: number): string
	world.wild[id] = {
		slime = Fixtures.slime(id, tier),
		price = 0,
		spawnedAt = T0,
		expiresAt = T0 + 600,
		angle = 0,
		radius = 40,
	}
	return id
end

-- An rng whose every float is `value` (decides the Lucky Charm roll).
local function always(value: number): any
	return {
		float = function()
			return value
		end,
	}
end

describe("grabbing a gated rarity", function()
	it("refuses each gated rarity one rebirth short, with the rebirth it needs, and changes nothing", function()
		for tier = 1, Config.MAX_TIER do
			local need = Config.CATCH_REBIRTHS[tier]
			if need > 0 then
				local world = ServerFixtures.world()
				local s = ServerFixtures.join(world, 1, nil, 100)
				s.data.rebirths = need - 1
				local id = wild(world, "w", tier)
				world.wild[id].price = 10
				local ok, reason = Carry.grab(world, 1, id, 1, T0)
				expect(ok).toBe(false)
				expect(reason).toBe(`Rebirth {need} to grab this`)
				expect(s.carry).toBeNil()
				expect(world.carriedBy[id]).toBeNil()
				expect(s.data.cash).toBe(100)
			end
		end
	end)
	it("grabs every rarity at exactly its CATCH_REBIRTHS and brings it home", function()
		for tier = 1, Config.MAX_TIER do
			local world = ServerFixtures.world()
			local s = ServerFixtures.join(world, 1)
			s.data.slimes = {}
			s.data.rebirths = Config.CATCH_REBIRTHS[tier]
			local id = wild(world, "w", tier)
			expect((Carry.grab(world, 1, id, 1, T0))).toBe(true)
			expect((Carry.deposit(world, 1, T0 + 1))).toBe(true)
			expect((PlayerData.findSlime(s.data, id) :: any).tier >= tier).toBe(true)
		end
	end)
	it(
		"opens Mythic at 5, Secret at 12, Celestial at 18 and Divine at 25; everything below is open from the start",
		function()
			expect(Config.CATCH_REBIRTHS).toEqual({ 0, 0, 0, 0, 0, 5, 12, 18, 25 })
			expect(#Config.CATCH_REBIRTHS).toBe(Config.MAX_TIER)
		end
	)
end)

describe("stealing a gated rarity", function()
	it("a fresh player steals a Divine off another plot and brings it home", function()
		local world = ServerFixtures.world()
		local owner = ServerFixtures.join(world, 1, { Fixtures.slime("d", Config.MAX_TIER) })
		local thief = ServerFixtures.join(world, 2)
		thief.data.rebirths = 0
		ServerFixtures.unlock(owner)
		expect((Carry.grab(world, 2, "d", 2, T0))).toBe(true)
		expect((Carry.deposit(world, 2, T0 + 5))).toBe(true)
		expect((PlayerData.findSlime(thief.data, "d") :: any).tier).toBe(Config.MAX_TIER)
		expect(PlayerData.findSlime(owner.data, "d")).toBeNil()
	end)
	it("StealService never asks for rebirths", function()
		local world = ServerFixtures.world()
		local owner = ServerFixtures.join(world, 1, { Fixtures.slime("s", Config.SECRET_TIER) })
		local thief = ServerFixtures.join(world, 2)
		ServerFixtures.unlock(owner)
		expect((StealService.steal(world, thief, "s", 2, T0))).toBe(true)
	end)
end)

describe("Lucky Charm and the gate", function()
	-- Player 1 with a maxed Lucky Charm that always hits deposits a wild slime of `tier`; returns its new tier.
	local function luckyDeposit(tier: number, rebirths: number): number
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		s.data.slimes = {}
		s.data.rebirths = rebirths
		s.data.upgrades.Luck = 5
		local id = wild(world, "w", tier)
		assert(Carry.grab(world, 1, id, 1, T0))
		world.rng = always(0)
		assert(Carry.deposit(world, 1, T0 + 1))
		return (PlayerData.findSlime(s.data, id) :: any).tier
	end

	it("never lifts a slime into a rarity the player can't grab yet", function()
		for tier = 1, Config.MAX_TIER - 1 do
			local need = Config.CATCH_REBIRTHS[tier + 1]
			local rebirths = math.max(Config.CATCH_REBIRTHS[tier], need - 1)
			if need > Config.CATCH_REBIRTHS[tier] then
				expect(`{tier} -> {luckyDeposit(tier, rebirths)}`).toBe(`{tier} -> {tier}`)
			end
		end
	end)
	it("lifts it one rarity once the player may grab the next one", function()
		for tier = 1, Config.MAX_TIER - 1 do
			local rebirths = Config.CATCH_REBIRTHS[tier + 1]
			expect(`{tier} -> {luckyDeposit(tier, rebirths)}`).toBe(`{tier} -> {tier + 1}`)
		end
	end)
	it("a Divine has nowhere higher to go", function()
		expect(luckyDeposit(Config.MAX_TIER, Config.CATCH_REBIRTHS[Config.MAX_TIER])).toBe(Config.MAX_TIER)
	end)
end)
