--!strict
-- Outbox: the server's routing of World events to remotes, attributes, badges and Effects, through fakes.
local Constants = require("../src/shared/Constants")
local Outbox = require("../src/server/Outbox")
local SafeCall = require("../src/server/SafeCall")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")
local World = require("../src/server/World")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local NOW = 500

type Fired = { player: any?, args: { any } }

local function remote(log: { Fired })
	return {
		FireClient = function(_self: any, player: any, ...: any)
			table.insert(log, { player = player, args = { ... } })
		end,
		FireAllClients = function(_self: any, ...: any)
			table.insert(log, { player = nil, args = { ... } })
		end,
	}
end

local function setup()
	local env = {
		world = ServerFixtures.world(),
		players = {} :: { [number]: any },
		notified = {} :: { Fired },
		pvp = {} :: { Fired },
		effects = {} :: { string },
		badges = {} :: { string },
		attributes = {} :: { [string]: any },
		splashes = 0,
		logs = {} :: { string },
	}
	local deps: Outbox.Deps = {
		now = function()
			return NOW
		end,
		playerOf = function(userId: number)
			return env.players[userId]
		end,
		notify = remote(env.notified),
		pvp = remote(env.pvp),
		playEffect = function(event)
			if event.effect == "Broken" then
				error("burst failed", 0)
			end
			table.insert(env.effects, event.effect :: string)
		end,
		splash = function()
			env.splashes += 1
		end,
		grantBadge = function(userId: number, badge: string)
			table.insert(env.badges, `{userId}:{badge}`)
		end,
		setWorldAttribute = function(name: string, value: any)
			env.attributes[name] = value
		end,
		safeCall = SafeCall.new(function(message)
			table.insert(env.logs, message)
		end),
		spawn = function(fn, ...)
			fn(...)
		end,
	}
	return env, deps
end

describe("Outbox.flush", function()
	it("sends a PvpEvent to its target or to everyone, stamping serverTime only when missing", function()
		local env, deps = setup()
		local player = { Name = "One" }
		env.players[1] = player
		World.emit(env.world, { type = "PvpEvent", userId = 1, payload = { kind = "Cooldown" } })
		World.emit(env.world, { type = "PvpEvent", payload = { kind = "Effect", serverTime = 7 } })
		World.emit(env.world, { type = "PvpEvent", userId = 2, payload = { kind = "TrapPlaced" } }) -- left the server
		Outbox.flush(env.world, deps)
		expect(#env.pvp).toBe(2)
		expect(env.pvp[1].player).toBe(player)
		expect(env.pvp[1].args[1]).toEqual({ kind = "Cooldown", serverTime = NOW })
		expect(env.pvp[2].player).toBeNil()
		expect(env.pvp[2].args[1].serverTime).toBe(7)
		expect(#env.world.outbox).toBe(0)
	end)
	it("routes Notify, Rare, Badge, Drained and Effect events", function()
		local env, deps = setup()
		env.players[3] = { Name = "Three" }
		World.notify(env.world, 3, "Hello", "good", "Cash", "Lock")
		World.notify(env.world, nil, "Rain!", "info")
		World.emit(env.world, { type = "Rare", slimeId = "s9", tier = 6 })
		World.emit(env.world, { type = "Badge", userId = 3, badge = "FirstSteal" })
		World.emit(env.world, { type = "Drained" })
		World.effect(env.world, "Merge", { plotIndex = 1 })
		Outbox.flush(env.world, deps)
		expect(env.notified[1].args).toEqual({ "Hello", "good", "Cash", "Lock" })
		expect(env.notified[2].player).toBeNil()
		expect(env.notified[2].args[1]).toBe("Rain!")
		expect(env.attributes[Constants.RARE_SPAWN_ID_ATTRIBUTE]).toBe("s9")
		expect(env.attributes[Constants.RARE_SPAWN_TIER_ATTRIBUTE]).toBe(6)
		expect(env.attributes[Constants.RARE_SPAWN_AT_ATTRIBUTE]).toBe(NOW)
		expect(env.badges).toEqual({ "3:FirstSteal" })
		expect(env.splashes).toBe(1)
		expect(env.effects).toEqual({ "Merge" })
	end)
	it("a failing Effect is logged and the events after it still go out", function()
		local env, deps = setup()
		World.effect(env.world, "Broken", { userId = 1 })
		World.notify(env.world, nil, "after", "info")
		Outbox.flush(env.world, deps)
		expect(env.logs).toEqual({ "[Server] Effects.play Broken failed: burst failed" })
		expect(#env.notified).toBe(1)
	end)
end)
