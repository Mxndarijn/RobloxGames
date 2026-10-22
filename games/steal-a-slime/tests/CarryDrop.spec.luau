--!strict
-- A hit makes the carrier drop whatever they hold (server/CarryDrop): a stolen slime bounces home, a wild one lands
-- at their feet.
local Carry = require("../src/server/Carry")
local CarryDrop = require("../src/server/CarryDrop")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local ServerFixtures = require("./ServerFixtures")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

-- Victim 1 owns "gem" (Epic); thief 2 stands next to it.
local function setup()
	local world = ServerFixtures.world()
	local victim = ServerFixtures.join(world, 1, { Fixtures.slime("gem", 4) })
	local thief = ServerFixtures.join(world, 2)
	return world, victim, thief
end

-- Player 2 carries a free wild slime; returns its id.
local function carryWild(world: any): string
	local id = Spawner.spawnOne(world, T0)
	world.wild[id].price = 0
	expect((Carry.grab(world, 2, id, 1, T0))).toBe(true)
	return id
end

describe("CarryDrop.slap", function()
	it("makes the carrier drop a stolen slime, which escapes home", function()
		local world, victim, thief = setup()
		ServerFixtures.unlock(victim)
		Carry.grab(world, 2, "gem", 1, T0)
		expect((CarryDrop.slap(world, victim, 2, 3, T0 + 2))).toBe(true)
		expect(thief.carry).toBeNil()
		expect(world.escaping.gem ~= nil).toBeTruthy()
		expect(victim.lastSlapAt).toBe(T0 + 2)
	end)
	it("makes the carrier drop a wild slime where they stand", function()
		local world, victim, thief = setup()
		local id = carryWild(world)
		expect((CarryDrop.slap(world, victim, 2, 3, T0 + 2, "here"))).toBe(true)
		expect(thief.carry).toBeNil()
		expect(world.carriedBy[id]).toBeNil()
		expect(world.wild[id].position).toBe("here")
		expect(victim.lastSlapAt).toBe(T0 + 2)
	end)
	it("checks reach, cooldown and that the target carries a slime", function()
		local world, victim, thief = setup()
		ServerFixtures.unlock(victim)
		expect(select(2, CarryDrop.slap(world, victim, 2, 3, T0))).toBe("target isn't carrying a slime")
		Carry.grab(world, 2, "gem", 1, T0)
		expect(select(2, CarryDrop.slap(world, victim, 2, Config.SLAP_REACH + 1, T0))).toBe("too far away")
		expect(select(2, CarryDrop.slap(world, victim, 1, 1, T0))).toBe("can't slap yourself")
		victim.lastSlapAt = T0
		expect(select(2, CarryDrop.slap(world, victim, 2, 1, T0 + 0.5))).toBe("slap on cooldown")
		expect(thief.carry ~= nil).toBeTruthy()
		expect(select(2, CarryDrop.slap(world, victim, 999, 1, T0 + 5))).toBe("target isn't carrying a slime")
	end)
end)

describe("CarryDrop.knockLoose", function()
	it("drops a wild slime at the given spot and tells the carrier", function()
		local world, _, thief = setup()
		local id = carryWild(world)
		expect(CarryDrop.knockLoose(world, thief, T0 + 5, "here")).toBe(id)
		expect(thief.carry).toBeNil()
		expect(world.carriedBy[id]).toBeNil()
		expect(world.wild[id] ~= nil).toBe(true) -- still in the wild for anyone to grab
		expect(world.wild[id].position).toBe("here")
		local said = ServerFixtures.notifications(world, 2)
		expect(string.find(said[#said], "You got bonked! You dropped the", 1, true) ~= nil).toBe(true)
	end)
	it("sends a stolen slime home", function()
		local world, victim, thief = setup()
		ServerFixtures.unlock(victim)
		Carry.grab(world, 2, "gem", 1, T0)
		expect(CarryDrop.knockLoose(world, thief, T0 + 5, nil)).toBe("gem")
		expect(thief.carry).toBeNil()
		expect(world.escaping.gem ~= nil).toBe(true)
	end)
	it("does nothing to a player carrying nothing", function()
		local world, _, thief = setup()
		expect(CarryDrop.knockLoose(world, thief, T0 + 5, nil)).toBeNil()
	end)
end)

describe("a dropped wild slime is for sale again", function()
	it("charges its full price on every grab, also to the player who paid", function()
		local world, victim, thief = setup()
		local id = Spawner.spawnOne(world, T0)
		world.wild[id].price = 80
		thief.data.cash, victim.data.cash = 200, 200
		expect((Carry.grab(world, 2, id, 1, T0))).toBe(true)
		expect(thief.data.cash).toBe(120)
		expect(world.wild[id].price).toBe(80)
		-- Dropped on purpose: the buyer pays again, nothing was refunded.
		expect((CarryDrop.release(world, 2, T0 + 1, "here", "drop"))).toBe(true)
		expect(thief.data.cash).toBe(120)
		expect((Carry.grab(world, 2, id, 1, T0 + 2))).toBe(true)
		expect(thief.data.cash).toBe(40)
		-- Bonked loose: the next grabber pays the price too.
		CarryDrop.knockLoose(world, thief, T0 + 3, "there")
		expect((Carry.grab(world, 1, id, 1, T0 + 4))).toBe(true)
		expect(victim.data.cash).toBe(120)
		-- The buyer, now short of the price, can't take it back for free.
		CarryDrop.release(world, 1, T0 + 5, "here", "drop")
		expect(select(2, Carry.grab(world, 2, id, 1, T0 + 6))).toBe("need $80")
	end)
end)
