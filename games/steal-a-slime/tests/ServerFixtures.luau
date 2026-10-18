--!strict
-- Test helpers for the pure server modules: a World with joined players.

local Collection = require("../src/shared/Collection")
local Fixtures = require("./Fixtures")
local Goals = require("../src/shared/Goals")
local Sessions = require("../src/server/Sessions")
local Spawner = require("../src/server/Spawner")
local World = require("../src/server/World")

local ServerFixtures = {}

ServerFixtures.T0 = 1_700_000_000

-- Seeded drops must not depend on the date: no weekly event schedule unless a spec sets Spawner.unixTime.
Spawner.unixTime = function()
	return nil
end

function ServerFixtures.world(now: number?): World.World
	return World.new({ now = now or ServerFixtures.T0, seed = 7 })
end

-- Joins `userId` with the given slimes (pads 1..n) and cash; returns the session.
-- Goal / SlimeDex rewards the fixture already qualifies for (8 pads, ...) are
-- settled silently first, so cash stays what the test asked for.
function ServerFixtures.join(
	world: World.World,
	userId: number,
	slimes: { any }?,
	cash: number?,
	now: number?
): World.Session
	local data = Fixtures.data(slimes, cash)
	local before = data.cash
	Goals.check(data)
	Collection.check(data)
	data.cash, data.totalEarned = before, 0
	local session = Sessions.join(world, userId, `P{userId}`, data, now or ServerFixtures.T0)
	assert(session, "join failed")
	return session
end

-- Lifts the join lock so the plot can be stolen from.
function ServerFixtures.unlock(session: World.Session)
	session.lockUntil = 0
end

function ServerFixtures.notifications(world: World.World, userId: number?): { string }
	local texts = {}
	for _, event in world.outbox do
		if event.type == "Notify" and event.userId == userId and event.text then
			table.insert(texts, event.text)
		end
	end
	return texts
end

export type PvpEvent = { target: number?, payload: { [string]: any } }

-- The PvpEvents queued in world.outbox, oldest first, as { target (nil = every client), payload }. Not drained.
function ServerFixtures.pvpEvents(world: World.World): { PvpEvent }
	local events = {}
	for _, event in world.outbox do
		if event.type == "PvpEvent" and event.payload then
			table.insert(events, { target = event.userId, payload = event.payload })
		end
	end
	return events
end

-- Forgets every queued event (what the adapter's flush does), so a spec can count from zero.
function ServerFixtures.clearEvents(world: World.World)
	World.drain(world)
end

return ServerFixtures
