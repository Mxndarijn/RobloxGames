--!strict
local Actions = require("../src/server/Actions")
local Carry = require("../src/server/Carry")
local Economy = require("../src/shared/Economy")
local Fixtures = require("./Fixtures")
local PlayerData = require("../src/shared/PlayerData")
local Progression = require("../src/shared/Progression")
local Remotes = require("../src/shared/Remotes")
local ServerFixtures = require("./ServerFixtures")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

local ctx: Actions.Context = {
	distanceBetween = function()
		return 2
	end,
	positionOf = function()
		return "pos"
	end,
}

local function call(world: any, userId: number, action: any, ...: any)
	return Actions.handle(world, userId, action, table.pack(...), T0 + 100, ctx)
end

describe("Actions.handle guards", function()
	it("rejects unknown actions, unloaded players and bad arguments without erroring", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1)
		expect(call(world, 1, "Explode").message).toBe("unknown action")
		expect(call(world, 1, 42).message).toBe("unknown action")
		expect(call(world, 2, "Sync").message).toBe("still loading")
		expect(call(world, 1, "Sell", 5).message).toBe("bad argument")
		expect(call(world, 1, "Sell", "bad id!").message).toBe("bad argument")
		expect(call(world, 1, "Merge", "a").message).toBe("bad argument")
		expect(call(world, 1, "Slap", "x").message).toBe("bad argument")
		expect(call(world, 1, "Slap", 0 / 0).message).toBe("bad argument")
		expect(call(world, 1, "Slap", math.huge).message).toBe("bad argument")
	end)
	it("parseArgs accepts every declared action shape", function()
		for action, def in Remotes.ACTIONS do
			local args = {}
			for i, kind in def.args do
				args[i] = if kind == "number" then 1 elseif kind == "boolean" then true else "id-1"
			end
			expect((Actions.parseArgs(action, args)) ~= nil).toBeTruthy()
		end
		expect((Actions.parseArgs("Favorite", {})) ~= nil).toBeTruthy()
	end)
	it("rate-limits per action but never Sync", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1)
		expect(call(world, 1, "Favorite", nil).ok).toBe(true)
		expect(call(world, 1, "Favorite", nil).message).toBe("too fast")
		for _ = 1, 5 do
			expect(call(world, 1, "Sync").ok).toBe(true)
		end
	end)
	it("Sync and successful actions mark State dirty", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		s.dirty = false
		call(world, 1, "Sync")
		expect(s.dirty).toBe(true)
	end)
end)

describe("Actions dispatch", function()
	it("Sell pays sellPrice and refuses busy or foreign slimes", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2), Fixtures.slime("b", 2) }, 0)
		ServerFixtures.join(world, 2)
		expect(call(world, 2, "Sell", "a").message).toBe("not your slime")
		expect(call(world, 1, "Sell", "a").ok).toBe(true)
		expect(s.data.cash).toBe(Economy.sellPrice(Fixtures.slime("a", 2), 0))
		ServerFixtures.unlock(s)
		Carry.grab(world, 2, "b", 1, T0)
		s.limiter = {}
		expect(call(world, 1, "Sell", "b").message).toBe("slime is busy")
	end)
	it("Favorite sets and clears the keeper", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a") })
		expect(call(world, 1, "Favorite", "a").ok).toBe(true)
		expect(s.data.favoriteId).toBe("a")
		s.limiter = {}
		expect(call(world, 1, "Favorite", nil).ok).toBe(true)
		expect(s.data.favoriteId).toBeNil()
		s.limiter = {}
		expect(call(world, 1, "Favorite", "zzz").message).toBe("not your slime")
	end)
	it("BuyPad unlocks the next pad for padCost", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, nil, 1000)
		s.data.padsUnlocked = 4
		local cost = Economy.padCost(4) :: number
		expect(call(world, 1, "BuyPad").ok).toBe(true)
		expect(s.data.padsUnlocked).toBe(5)
		expect(s.data.cash).toBe(1000 - cost)
	end)
	it("Daily pays once per day", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, nil, 0)
		expect(call(world, 1, "Daily").ok).toBe(true)
		expect(s.data.cash).toBe(Progression.dailyAmount(1, 0))
		s.limiter = {}
		expect(call(world, 1, "Daily").message).toBe("already claimed today")
	end)
	it("Merge, Lock and Rebirth route to their systems", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 1), Fixtures.slime("b", 1) }, 1e6)
		PlayerData.addSlime(s.data, Fixtures.slime("need", 2, { species = "sprout" }))
		expect(call(world, 1, "Merge", "a", "b").ok).toBe(true)
		expect(s.data.slimes[1].tier).toBe(2)
		expect(call(world, 1, "Lock").ok).toBe(true)
		expect(s.lockUntil > T0 + 100).toBeTruthy()
		expect(call(world, 1, "Rebirth").ok).toBe(true)
		expect(s.data.rebirths).toBe(1)
	end)
	it("Slap uses the context distance; Drop releases what you carry", function()
		local world = ServerFixtures.world()
		local victim = ServerFixtures.join(world, 1, { Fixtures.slime("gem", 3) })
		local thief = ServerFixtures.join(world, 2)
		ServerFixtures.unlock(victim)
		Carry.grab(world, 2, "gem", 1, T0 + 100)
		expect(call(world, 1, "Slap", 2).ok).toBe(true)
		expect(thief.carry).toBeNil()

		local id = Spawner.spawnOne(world, T0)
		world.wild[id].price = 0
		Carry.grab(world, 2, id, 1, T0 + 100)
		expect(call(world, 2, "Drop").ok).toBe(true)
		expect(world.wild[id].position).toBe("pos")
		thief.limiter = {}
		expect(call(world, 2, "Drop").message).toBe("not carrying")
		expect(PlayerData.findSlime(victim.data, "gem") ~= nil).toBeTruthy()
	end)
end)
