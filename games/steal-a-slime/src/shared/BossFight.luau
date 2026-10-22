--!strict
--[[
	BossFight (pure, contract/boss-event.md)

	One boss event as plain data: the phase ("warning" -> "fight" -> "haul" -> "won" | "failed"), its deadline, the goo
	meter, every player's hits, the sheds already paid and the haul (top-contributor head start, carrier, winner).

	The meter target scales with the players on the server (Config.BOSS.POINTS_PER_PLAYER x players, read live), so a
	fight takes about as long on any server. `step` advances time and returns what the caller must do (spawn the boss,
	shed slimes, start the haul, fail). No Roblox APIs, no randomness, no World: server/BossEvent wires it up.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

export type Phase = "warning" | "fight" | "haul" | "won" | "failed"

export type State = {
	species: string,
	phase: Phase,
	endsAt: number, -- deadline of the current phase (warning: the arrival)
	points: number, -- goo meter points (drains, may be fractional)
	contributions: { [number]: number }, -- userId -> hits on this boss (never drains)
	lastHitAt: { [number]: number }, -- userId -> last counted hit
	lastAnyHitAt: number, -- last counted hit by anyone (the drain waits DRAIN_GRACE after it)
	shed: number, -- sheds paid so far (one per SHED_EVERY of the meter)
	priorityUserId: number?, -- haul: the top contributor's head start
	priorityUntil: number?,
	carrierUserId: number?,
	winnerUserId: number?,
	failReason: string?, -- "fight" (meter not full in time) | "haul" (not home in time)
}

-- What `step` asks the caller to do, in order.
export type Event =
	{ kind: "fight" }
	| { kind: "shed", count: number }
	| { kind: "haul" }
	| { kind: "fail", reason: string }

local BossFight = {}

local BOSS = Config.BOSS

function BossFight.new(species: string, now: number): State
	return {
		species = species,
		phase = "warning",
		endsAt = now + BOSS.WARNING_SECONDS,
		points = 0,
		contributions = {},
		lastHitAt = {},
		lastAnyHitAt = -math.huge,
		shed = 0,
		priorityUserId = nil,
		priorityUntil = nil,
		carrierUserId = nil,
		winnerUserId = nil,
		failReason = nil,
	}
end

-- Meter points needed with `players` on the server (at least one).
function BossFight.target(players: number): number
	return BOSS.POINTS_PER_PLAYER * math.max(1, math.floor(players))
end

-- Goo meter 0..1 (1 from the haul on).
function BossFight.meter(state: State, players: number): number
	if state.phase == "haul" or state.phase == "won" then
		return 1
	end
	return math.clamp(state.points / BossFight.target(players), 0, 1)
end

-- True while the event is on (warning, fight or haul).
function BossFight.active(state: State): boolean
	return state.phase == "warning" or state.phase == "fight" or state.phase == "haul"
end

-- The top contributor and their points (ties go to the lower userId, so the pick is stable); nil before any hit.
function BossFight.top(state: State): (number?, number)
	local best, bestPoints = nil :: number?, 0
	for userId, points in state.contributions do
		if points > bestPoints or (points == bestPoints and best ~= nil and userId < best) then
			best, bestPoints = userId, points
		end
	end
	return best, bestPoints
end

-- `userId`'s points as a share of the top contributor's, 0..1.
function BossFight.share(state: State, userId: number): number
	local _, top = BossFight.top(state)
	if top <= 0 then
		return 0
	end
	return math.clamp((state.contributions[userId] or 0) / top, 0, 1)
end

-- One Bat hit by `userId` worth `amount` points (default 1; more while the boss is dazed). Returns (counted, reason):
-- at most one hit every HIT_GAP seconds per player.
function BossFight.hit(state: State, userId: number, now: number, amount: number?): (boolean, string?)
	if state.phase ~= "fight" then
		return false, "the boss isn't fighting"
	end
	local last = state.lastHitAt[userId]
	-- The epsilon keeps hits exactly HIT_GAP apart (the Bat's own swing gap) countable at large server times.
	if last and now - last < BOSS.HIT_GAP - 1e-6 then
		return false, "too fast"
	end
	local points = math.max(0, amount or 1)
	state.lastHitAt[userId] = now
	state.lastAnyHitAt = now
	state.points += points
	state.contributions[userId] = (state.contributions[userId] or 0) + points
	return true, nil
end

-- Meter points from something other than a Bat hit on the boss (a popped guard), credited to `userId`.
function BossFight.add(state: State, userId: number, points: number, now: number)
	if state.phase ~= "fight" then
		return
	end
	state.lastAnyHitAt = now
	state.points += points
	state.contributions[userId] = (state.contributions[userId] or 0) + points
end

-- Stage 0..3: how many SHED_EVERY of the meter have been reached (the boss speeds up with each).
function BossFight.stage(state: State): number
	return state.shed
end

local function fail(state: State, now: number, reason: string, events: { Event })
	state.phase = "failed"
	state.failReason = reason
	state.carrierUserId = nil
	state.endsAt = now + BOSS.LINGER_SECONDS
	table.insert(events, { kind = "fail", reason = reason })
end

--[[
	Advances the fight to `now` (`dt` seconds since the last step) with `players` on the server. Returns the events
	for the caller, in order: "fight" (the boss arrives), "shed" (count = slimes to spawn), "haul" (the meter is full;
	priority goes to the top contributor), "fail".
]]
function BossFight.step(state: State, now: number, dt: number, players: number, paused: boolean?): { Event }
	local events: { Event } = {}
	if state.phase == "warning" then
		if now >= state.endsAt then
			state.phase = "fight"
			state.endsAt = now + BOSS.FIGHT_SECONDS
			table.insert(events, { kind = "fight" })
		end
		return events
	end
	if state.phase == "fight" then
		local target = BossFight.target(players)
		-- `paused`: the boss is winding up or attacking, so dodging never costs the meter.
		if not paused and now - state.lastAnyHitAt >= BOSS.DRAIN_GRACE and dt > 0 then
			state.points = math.max(0, state.points - BOSS.DRAIN_PER_SECOND * target * dt)
		end
		local meter = math.clamp(state.points / target, 0, 1)
		-- Sheds at every SHED_EVERY crossed for the first time, below the full meter (that one pops the haul).
		local reached = math.min(math.floor(meter / BOSS.SHED_EVERY + 1e-9), math.ceil(1 / BOSS.SHED_EVERY) - 1)
		if reached > state.shed then
			table.insert(events, { kind = "shed", count = (reached - state.shed) * BOSS.SHED_COUNT })
			state.shed = reached
		end
		if meter >= 1 then
			state.phase = "haul"
			state.endsAt = now + BOSS.HAUL_SECONDS
			state.priorityUserId = BossFight.top(state)
			state.priorityUntil = now + BOSS.PRIORITY_SECONDS
			table.insert(events, { kind = "haul" })
		elseif now >= state.endsAt then
			fail(state, now, "fight", events)
		end
		return events
	end
	if state.phase == "haul" and now >= state.endsAt then
		fail(state, now, "haul", events)
	end
	return events
end

--[[
	Whether `userId` may grab the hauled boss now. `priorityPresent` = the top contributor is still on the server
	(their head start ends early when they leave).
]]
function BossFight.canGrab(state: State, userId: number, now: number, priorityPresent: boolean): (boolean, string?)
	if state.phase ~= "haul" then
		return false, "the boss isn't down yet"
	end
	if state.carrierUserId ~= nil then
		return false, "someone is already carrying it"
	end
	local priority = state.priorityUserId
	if
		priority ~= nil
		and priority ~= userId
		and priorityPresent
		and state.priorityUntil ~= nil
		and now < state.priorityUntil
	then
		return false, "the top helper grabs first"
	end
	return true, nil
end

function BossFight.grab(state: State, userId: number)
	state.carrierUserId = userId
end

-- The carrier dropped it (slap, Drop, left): it lies there and anyone may grab it. The deadline stays.
function BossFight.drop(state: State)
	state.carrierUserId = nil
end

function BossFight.win(state: State, userId: number, now: number)
	state.phase = "won"
	state.winnerUserId = userId
	state.carrierUserId = nil
	state.endsAt = now + BOSS.LINGER_SECONDS
end

-- True once a won / failed result has been shown for LINGER_SECONDS.
function BossFight.over(state: State, now: number): boolean
	return (state.phase == "won" or state.phase == "failed") and now >= state.endsAt
end

return table.freeze(BossFight)
