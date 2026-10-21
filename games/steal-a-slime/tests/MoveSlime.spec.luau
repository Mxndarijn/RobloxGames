--!strict
-- MoveSlime (CONTRACT.md §3, FEATURES.MoveSlime): an owner moves a pad slime to another unlocked pad, swapping
-- with a slime already there, through Actions.handle.
local Actions = require("../src/server/Actions")
local Fixtures = require("./Fixtures")
local PlayerData = require("../src/shared/PlayerData")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

local function ctx(on: boolean): Actions.Context
	return {
		distanceBetween = function()
			return 2
		end,
		positionOf = function()
			return "pos"
		end,
		features = { MoveSlime = on },
	}
end

local clock = 0
local function move(world: any, id: string, pad: any, on: boolean?): any
	clock += 1 -- MoveSlime is rate-limited per player (Validate.ACTIONS)
	return Actions.handle(world, 1, "MoveSlime", table.pack(id, pad), T0 + clock, ctx(on ~= false))
end

-- A world with player 1 owning slimes a, b, c on pads 1, 2, 3 and `unlocked` pads.
local function setup(unlocked: number?): (any, any)
	local world = ServerFixtures.world()
	local session =
		ServerFixtures.join(world, 1, { Fixtures.slime("a", 2), Fixtures.slime("b", 3), Fixtures.slime("c", 1) })
	session.data.padsUnlocked = unlocked or 6
	return world, session
end

local function padOf(session: any, id: string): number?
	local slime = PlayerData.findSlime(session.data, id)
	return slime and slime.pad
end

describe("MoveSlime", function()
	it("moves a slime to an empty unlocked pad", function()
		local world, session = setup()
		expect(padOf(session, "a")).toBe(1)
		expect(move(world, "a", 5).ok).toBe(true)
		expect(padOf(session, "a")).toBe(5)
		expect(padOf(session, "b")).toBe(2)
		expect(PlayerData.slimeOnPad(session.data, 1)).toBeNil()
	end)

	it("swaps with the slime already on the target pad", function()
		local world, session = setup()
		expect(move(world, "a", 3).ok).toBe(true)
		expect(padOf(session, "a")).toBe(3)
		expect(padOf(session, "c")).toBe(1)
		expect(#session.data.slimes).toBe(3)
	end)

	it("moving to its own pad is a no-op", function()
		local world, session = setup()
		expect(move(world, "b", 2).ok).toBe(true)
		expect(padOf(session, "b")).toBe(2)
	end)

	it("refuses locked, out-of-range, fractional and non-finite pads", function()
		local world, session = setup(4)
		expect(move(world, "a", 5).message).toBe("pad is locked")
		expect(move(world, "a", 0).message).toBe("pad is locked")
		expect(move(world, "a", 2.5).message).toBe("pad is locked")
		expect(move(world, "a", 0 / 0).message).toBe("bad argument")
		expect(move(world, "a", math.huge).message).toBe("bad argument")
		expect(padOf(session, "a")).toBe(1)
	end)

	it("refuses a slime that isn't yours", function()
		local world = setup()
		ServerFixtures.join(world, 2, { Fixtures.slime("theirs", 2) })
		expect(move(world, "theirs", 4).message).toBe("not your slime")
		expect(move(world, "nope", 4).message).toBe("not your slime")
	end)

	it("refuses while the slime, or the one it would swap with, is being stolen or escaping", function()
		local world, session = setup()
		world.carriedBy.a = 2
		expect(move(world, "a", 5).message).toBe("slime is busy")
		world.carriedBy.a = nil
		world.escaping.c = T0 + 100
		expect(move(world, "a", 3).message).toBe("slime is busy")
		expect(padOf(session, "a")).toBe(1)
		expect(padOf(session, "c")).toBe(3)
	end)

	it("is refused with the flag off", function()
		local world, session = setup()
		expect(move(world, "a", 5, false).message).toBe("moving slimes is off")
		expect(padOf(session, "a")).toBe(1)
	end)

	it("rejects bad arguments", function()
		local world = setup()
		expect(move(world, "a", "5").message).toBe("bad argument")
		expect(move(world, "bad id!", 5).message).toBe("bad argument")
	end)
end)
