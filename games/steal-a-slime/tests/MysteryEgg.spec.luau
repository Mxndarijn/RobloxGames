--!strict
-- The Mystery Egg is never sold: no buy action, no shop row, no State.shop entry.
local Actions = require("../src/server/Actions")
local Remotes = require("../src/shared/Remotes")
local ServerFixtures = require("./ServerFixtures")
local Shops = require("../src/shared/Shops")
local Snapshot = require("../src/server/Snapshot")
local TestRunner = require("./TestRunner")
local Validate = require("../src/shared/Validate")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

describe("MysteryEgg is not for sale", function()
	it("has no buy action and no shop row", function()
		expect(Remotes.ACTIONS.BuyEgg).toBeNil()
		expect(Validate.ACTIONS.BuyEgg).toBeNil()
		expect(Shops.shopOfAction("BuyEgg")).toBeNil()
		expect(Shops.shopOf("MysteryEgg")).toBeNil()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, nil, 1e9)
		local ctx: Actions.Context = {
			distanceBetween = function()
				return 2
			end,
			positionOf = function()
				return nil
			end,
		}
		expect(Actions.handle(world, 1, "BuyEgg", {}, T0 + 100, ctx).ok).toBe(false)
		expect(session.data.cash).toBe(1e9)
		expect(#session.data.slimes).toBe(0)
		local state = Snapshot.build(world, session, T0 + 101)
		expect((state.shop :: any).MysteryEgg).toBeNil()
	end)
end)
