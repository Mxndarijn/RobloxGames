--!strict
local Actions = require("../src/server/Actions")
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
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
		expect(call(world, 1, "VatAdd", 5).message).toBe("bad argument")
	end)
	it("has no Appraise: a reroll request is an unknown action and leaves the slime and cash alone", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1)
		PlayerData.addSlime(session.data, Fixtures.slime("goo", 3, { size = 1.2 }))
		session.data.cash = 10_000
		expect(call(world, 1, "Appraise", "goo", "size").message).toBe("unknown action")
		expect((PlayerData.findSlime(session.data, "goo") :: any).size).toBe(1.2)
		expect(session.data.cash).toBe(10_000)
	end)
	it("parseArgs accepts every declared action shape", function()
		for action, def in Remotes.ACTIONS do
			local args = {}
			for i, kind in def.args do
				if kind == "vector3?" or kind == "boolean?" then
					args[i] = nil
				else
					args[i] = if kind == "number" or kind == "number?"
						then 1
						elseif kind == "boolean" then true
						elseif kind == "kits" then "gummy"
						else "id-1"
				end
			end
			expect((Actions.parseArgs(action, args)) ~= nil).toBeTruthy()
		end
		expect((Actions.parseArgs("Favorite", {})) ~= nil).toBeTruthy()
	end)
	it("rate-limits per action, Sync to one per STATE_MIN_INTERVAL", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1)
		expect(call(world, 1, "Favorite", nil).ok).toBe(true)
		expect(call(world, 1, "Favorite", nil).message).toBe("too fast")
		expect(call(world, 1, "Sync").ok).toBe(true)
		for _ = 1, 5 do
			expect(call(world, 1, "Sync").message).toBe("too fast")
		end
		local later = T0 + 100 + Config.STATE_MIN_INTERVAL
		expect(Actions.handle(world, 1, "Sync", {}, later, ctx).ok).toBe(true)
	end)
	it("reports whether the call was dispatched (the adapter skips the world refresh otherwise)", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1)
		local function ran(userId: number, action: any, ...: any): boolean
			local _, dispatched = call(world, userId, action, ...)
			return dispatched
		end
		expect(ran(1, "Explode")).toBe(false)
		expect(ran(2, "Sync")).toBe(false) -- still loading
		expect(ran(1, "Sell", 5)).toBe(false) -- bad argument
		expect(ran(1, "Favorite", nil)).toBe(true)
		expect(ran(1, "Favorite", nil)).toBe(false) -- too fast
		expect(ran(1, "Sell", "nope")).toBe(true) -- dispatched, refused by the system ("not your slime")
		expect(ran(1, "Sync")).toBe(true)
		expect(ran(1, "Sync")).toBe(false)
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
	it("VatAdd, Lock and Rebirth route to their systems", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 1), Fixtures.slime("b", 1) }, 1e6)
		PlayerData.addSlime(s.data, Fixtures.slime("need", 2, { species = "bumble" }))
		expect(call(world, 1, "VatAdd", "a").ok).toBe(true)
		expect(s.data.vat ~= nil).toBe(true)
		expect(call(world, 1, "Lock").ok).toBe(true)
		expect(s.lockUntil > T0 + 100).toBeTruthy()
		expect(call(world, 1, "Rebirth").ok).toBe(true)
		expect(s.data.rebirths).toBe(1)
	end)
	it("Drop releases what you carry", function()
		local world = ServerFixtures.world()
		local victim = ServerFixtures.join(world, 1, { Fixtures.slime("gem", 3) })
		local thief = ServerFixtures.join(world, 2)
		ServerFixtures.unlock(victim)
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

describe("Actions SetHotbar", function()
	it("saves the order as 9 slot keys and marks the session dirty", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		s.dirty = false
		local res = call(world, 1, "SetHotbar", "tool:Bat,pvp:KnockGlove1,,consumable:LuckPotion")
		expect(res.ok).toBe(true)
		expect(s.data.hotbar).toEqual({ "tool:Bat", "pvp:KnockGlove1", "", "consumable:LuckPotion", "", "", "", "", "" })
		expect(s.dirty).toBe(true)
	end)
	it("refuses bad orders with a message and keeps the saved one", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		local function try(...: any)
			s.limiter = {}
			return call(world, 1, "SetHotbar", ...)
		end
		expect(try("tool:Bat").ok).toBe(true)
		local saved = s.data.hotbar
		expect(try(42).message).toBe("bad argument")
		expect(try(nil).message).toBe("bad argument")
		expect(try(string.rep("a", 401)).message).toBe("bad argument")
		expect(try("tool:Bat,tool:Bat").message).toBe("bad argument")
		expect(try("weapon:Bat").message).toBe("bad argument")
		expect(try(",,,,,,,,,").message).toBe("bad argument") -- 10 parts
		expect(s.data.hotbar).toBe(saved)
	end)
	it("is rate limited", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1)
		expect(call(world, 1, "SetHotbar", "").ok).toBe(true)
		expect(call(world, 1, "SetHotbar", "").message).toBe("too fast")
		local later = T0 + 100 + 0.5
		expect(Actions.handle(world, 1, "SetHotbar", { "tool:Bat" }, later, ctx).ok).toBe(true)
	end)
	it("the rate limit is per player: another player's order is not slowed", function()
		local world = ServerFixtures.world()
		local a = ServerFixtures.join(world, 1)
		local b = ServerFixtures.join(world, 2)
		expect(call(world, 1, "SetHotbar", "tool:Bat").ok).toBe(true)
		expect(call(world, 2, "SetHotbar", ",tool:Bat").ok).toBe(true)
		expect(call(world, 1, "SetHotbar", ",,tool:Bat").message).toBe("too fast")
		expect(call(world, 2, "SetHotbar", ",,,tool:Bat").message).toBe("too fast")
		expect((a.data.hotbar :: { string })[1]).toBe("tool:Bat")
		expect((b.data.hotbar :: { string })[2]).toBe("tool:Bat")
	end)
end)

describe("Actions RequestKits", function()
	it("hands the parsed kits to ctx.sendKits without marking the session dirty", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		s.dirty = false
		local got: { any } = {}
		local kitCtx = table.clone(ctx)
		kitCtx.sendKits = function(userId: number, kits: { string })
			table.insert(got, { userId, kits })
		end
		local res, ran = Actions.handle(world, 1, "RequestKits", { "gummy,mochi" }, T0 + 100, kitCtx)
		expect(res.ok).toBe(true)
		expect(ran).toBe(false) -- no view refresh or State push for it
		expect(s.dirty).toBe(false)
		expect(got).toEqual({ { 1, { "slime_gummy", "slime_mochi" } } })
	end)
	it("refuses bad requests and rate-limits per player", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		ServerFixtures.join(world, 2)
		expect(call(world, 1, "RequestKits", 42).message).toBe("bad argument")
		expect(call(world, 1, "RequestKits", "gummy,nope").message).toBe("bad argument")
		expect(call(world, 1, "RequestKits", "").message).toBe("bad argument")
		s.limiter = {}
		expect(call(world, 1, "RequestKits", "gummy").ok).toBe(true)
		expect(call(world, 1, "RequestKits", "mochi").message).toBe("too fast")
		expect(call(world, 2, "RequestKits", "mochi").ok).toBe(true)
		expect(Actions.handle(world, 1, "RequestKits", { "mochi" }, T0 + 100.3, ctx).ok).toBe(true)
	end)
end)
