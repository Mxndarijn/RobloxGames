--!strict
local BrokeTopUp = require("../src/server/BrokeTopUp")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local GameLoop = require("../src/server/GameLoop")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")
local World = require("../src/server/World")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local TOPUP = Config.BROKE_TOPUP_CASH
local GRACE = Config.BROKE_TOPUP_GRACE_SECONDS
local COOLDOWN = Config.BROKE_TOPUP_COOLDOWN_SECONDS

local function topUps(world: World.World, userId: number): number
	local n = 0
	for _, event in world.outbox do
		if
			event.type == "Analytics"
			and event.userId == userId
			and event.track
			and event.track.name == "BrokeTopUp"
		then
			n += 1
		end
	end
	return n
end

-- Runs BrokeTopUp.check once a second from `from` to `to` (inclusive).
local function run(world: World.World, session: World.Session, from: number, to: number)
	for t = from, to do
		BrokeTopUp.check(world, session, T0 + t)
	end
end

describe("BrokeTopUp", function()
	it("tops a new player with starting cash and no slimes up to the bar after the grace period", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, {}, Config.STARTING_CASH)
		run(world, s, 0, GRACE - 1)
		expect(s.data.cash).toBe(Config.STARTING_CASH)
		run(world, s, GRACE, GRACE)
		expect(s.data.cash).toBe(TOPUP)
		expect(ServerFixtures.notifications(world, 1)[1]).toBe(BrokeTopUp.TEXT)
		expect(topUps(world, 1)).toBe(1)
	end)

	it("raises cash to the bar, never adds the bar on top", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, {}, TOPUP - 3)
		run(world, s, 0, GRACE)
		expect(s.data.cash).toBe(TOPUP)
	end)

	it("leaves a player alone who owns any slime or egg, or is carrying one", function()
		local world = ServerFixtures.world()
		local owner = ServerFixtures.join(world, 1, { Fixtures.slime("a", 1) }, 0)
		local egg = ServerFixtures.join(world, 2, { Fixtures.slime("e", 1, { egg = { kind = "basic" } }) }, 0)
		local carrier = ServerFixtures.join(world, 3, {}, 0)
		carrier.carry = { slimeId = "w", kind = "wild", slime = Fixtures.slime("w") } :: any
		for t = 0, GRACE * 3 do
			BrokeTopUp.step(world, T0 + t)
		end
		expect(owner.data.cash).toBe(0)
		expect(egg.data.cash).toBe(0)
		expect(carrier.data.cash).toBe(0)
	end)

	it("counts uncollected cash pad piles as cash", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, {}, 0)
		s.data.padCash = { [1] = TOPUP }
		run(world, s, 0, GRACE * 2)
		expect(s.data.cash).toBe(0)
		s.data.padCash = { [1] = TOPUP - 10 }
		run(world, s, GRACE * 2 + 1, GRACE * 4)
		expect(s.data.cash).toBe(10)
	end)

	it("restarts the grace period when the player stops being broke for a moment", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, {}, 0)
		run(world, s, 0, GRACE - 2)
		s.carry = { slimeId = "w", kind = "wild", slime = Fixtures.slime("w") } :: any -- grabbing a slime
		run(world, s, GRACE - 1, GRACE - 1)
		s.carry = nil -- dropped it
		run(world, s, GRACE, GRACE * 2 - 1)
		expect(s.data.cash).toBe(0)
		run(world, s, GRACE * 2, GRACE * 2)
		expect(s.data.cash).toBe(TOPUP)
	end)

	it("tops up a player whose last slime was stolen, once the steal lands", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 1) }, 0)
		run(world, s, 0, GRACE * 2) -- the slime is still theirs while a thief carries it
		expect(s.data.cash).toBe(0)
		s.data.slimes = {} -- the steal landed
		run(world, s, GRACE * 2 + 1, GRACE * 3 + 1)
		expect(s.data.cash).toBe(TOPUP)
	end)

	it("gives an AFK player one top-up", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, {}, 0)
		run(world, s, 0, COOLDOWN * 3)
		expect(topUps(world, 1)).toBe(1)
		expect(s.data.cash).toBe(TOPUP)
	end)

	it("tops up a player who spends it and is broke again at most once per cooldown", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, {}, 0)
		run(world, s, 0, GRACE)
		s.data.cash = 0 -- spent it on something that isn't a slime
		run(world, s, GRACE + 1, GRACE + COOLDOWN - 1)
		expect(topUps(world, 1)).toBe(1)
		expect(s.data.cash).toBe(0)
		run(world, s, GRACE + COOLDOWN, GRACE + COOLDOWN)
		expect(topUps(world, 1)).toBe(2)
		expect(s.data.cash).toBe(TOPUP)
	end)

	it("runs from the game loop", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, {}, 0)
		for t = 1, GRACE + 2 do
			GameLoop.step(world, T0 + t)
		end
		expect(s.data.cash).toBe(TOPUP)
	end)
end)
