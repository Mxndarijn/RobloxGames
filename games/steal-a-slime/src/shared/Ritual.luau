--!strict
--[[
	Ritual (pure, FEATURES.CoopRitual, CONTRACT.md §13)

	The plaza ritual circle: Config.RITUAL.SPOTS glowing spots round a centre. When at least
	MIN_PLAYERS distinct players stand on distinct spots for HOLD_SECONDS, each of them gets a
	timed "Blessed" income bonus (more players, more bonus). Then the circle rests for
	SERVER_COOLDOWN, and a blessed player can't count again for PLAYER_COOLDOWN.

	  Idle      fewer than MIN_PLAYERS stand on spots (the sign reads "n/MIN players")
	  Charging  MIN_PLAYERS or more stand; completes HOLD_SECONDS after the group first reached
	            MIN_PLAYERS. Dropping below MIN_PLAYERS goes back to Idle and the timer restarts.
	  Cooldown  until readyAt

	No Roblox APIs: the server (server/RitualService) feeds in player positions.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

export type Phase = "Idle" | "Charging" | "Cooldown"
export type Candidate = { userId: number, x: number, y: number, z: number }
export type Blessing = { bonus: number, untilAt: number }
export type State = {
	phase: Phase,
	count: number, -- distinct players on spots right now
	chargeEndsAt: number?,
	readyAt: number, -- Cooldown: when the circle can be used again
	lastBlessedAt: { [number]: number }, -- userId -> when they last took part in a completed ritual
	blessed: { [number]: Blessing }, -- userId -> active Blessed bonus
	spotUsers: { [number]: number }, -- spot index -> userId standing on it right now
}
export type Completion = { userIds: { number }, bonus: number, untilAt: number }

local Ritual = {}

local function rad(degrees: number): number
	return math.rad(degrees)
end

-- Circle centre (x, z) on the ground: bearing 0 = +Z, like WorldLayout.PROP_SPOTS.
function Ritual.centre(): (number, number)
	local r = Config.RITUAL
	local a = rad(r.BEARING)
	return math.sin(a) * r.DISTANCE, math.cos(a) * r.DISTANCE
end

-- Spot centres (x, z), evenly round the circle starting on the fountain side.
function Ritual.spots(): { { number } }
	local r = Config.RITUAL
	local cx, cz = Ritual.centre()
	local out = {}
	for i = 1, r.SPOTS do
		local a = rad(r.BEARING + 180 + (i - 1) * 360 / r.SPOTS)
		table.insert(out, { cx + math.sin(a) * r.SPOT_DISTANCE, cz + math.cos(a) * r.SPOT_DISTANCE })
	end
	return out
end

function Ritual.new(): State
	return {
		phase = "Idle",
		count = 0,
		chargeEndsAt = nil,
		readyAt = 0,
		lastBlessedAt = {},
		blessed = {},
		spotUsers = {},
	}
end

-- The Blessed bonus for `players` participants (0 below MIN_PLAYERS; capped at the biggest tier).
function Ritual.bonus(players: number): number
	local r = Config.RITUAL
	if Config.FEATURES.CoopRitual ~= true or type(players) ~= "number" or players ~= players then
		return 0
	end
	players = math.min(math.floor(players), r.SPOTS)
	return r.BONUS[players] or 0
end

local function eligibleAt(state: State, userId: number, now: number): boolean
	local last = state.lastBlessedAt[userId]
	return last == nil or now - last >= Config.RITUAL.PLAYER_COOLDOWN
end

-- Which player stands on which spot. A player counts on the nearest spot within STAND_RADIUS
-- (and not high above the plaza ground, y = 0); a spot holds one player (the closest, lower userId on a tie),
-- so two accounts can't share a spot, and a player holds at most one spot.
-- Candidates must be pre-filtered by the server (loaded session, owns a slime); players still on
-- their personal cooldown are dropped here.
function Ritual.occupants(state: State, candidates: { Candidate }, now: number): { [number]: number }
	local r = Config.RITUAL
	local spots = Ritual.spots()
	local best: { [number]: { userId: number, dist: number } } = {}
	local seen: { [number]: boolean } = {}
	for _, c in candidates do
		if
			type(c.userId) == "number"
			and not seen[c.userId]
			and c.x == c.x
			and c.y == c.y
			and c.z == c.z
			and eligibleAt(state, c.userId, now)
		then
			seen[c.userId] = true
			local pickSpot, pickDist = nil, math.huge
			for i, s in spots do
				local d = math.sqrt((c.x - s[1]) ^ 2 + (c.z - s[2]) ^ 2)
				if d < pickDist then
					pickSpot, pickDist = i, d
				end
			end
			if pickSpot and pickDist <= r.STAND_RADIUS and c.y >= 0 and c.y <= r.STAND_HEIGHT then
				local cur = best[pickSpot]
				if not cur or pickDist < cur.dist or (pickDist == cur.dist and c.userId < cur.userId) then
					best[pickSpot] = { userId = c.userId, dist = pickDist }
				end
			end
		end
	end
	local out: { [number]: number } = {}
	for spot, entry in best do
		out[spot] = entry.userId
	end
	return out
end

local function sortedUsers(spotUsers: { [number]: number }): { number }
	local ids = {}
	for _, userId in spotUsers do
		table.insert(ids, userId)
	end
	table.sort(ids)
	return ids
end

-- Advances the state machine. `spotUsers` comes from Ritual.occupants. Returns a Completion when a
-- ritual finishes on this call (the blessings are recorded in state.blessed and lastBlessedAt),
-- plus the userIds whose Blessed bonus ended on this call.
function Ritual.step(state: State, spotUsers: { [number]: number }, now: number): (Completion?, { number })
	local r = Config.RITUAL
	local expired = {}
	for userId, blessing in state.blessed do
		if now >= blessing.untilAt then
			state.blessed[userId] = nil
			table.insert(expired, userId)
		end
	end
	table.sort(expired)
	state.spotUsers = spotUsers
	local ids = sortedUsers(spotUsers)
	state.count = #ids
	if Config.FEATURES.CoopRitual ~= true then
		state.phase = "Idle"
		state.chargeEndsAt = nil
		return nil, expired
	end
	if state.phase == "Cooldown" then
		if now < state.readyAt then
			state.count = 0 -- nobody counts while it rests
			state.spotUsers = {}
			return nil, expired
		end
		state.phase = "Idle"
	end
	if #ids < r.MIN_PLAYERS then
		state.phase = "Idle"
		state.chargeEndsAt = nil
		return nil, expired
	end
	if state.phase ~= "Charging" or not state.chargeEndsAt then
		state.phase = "Charging"
		state.chargeEndsAt = now + r.HOLD_SECONDS
		return nil, expired
	end
	if now < state.chargeEndsAt then
		return nil, expired
	end
	local bonus = Ritual.bonus(#ids)
	local untilAt = now + r.BLESS_SECONDS
	for _, userId in ids do
		state.blessed[userId] = { bonus = bonus, untilAt = untilAt }
		state.lastBlessedAt[userId] = now
	end
	state.phase = "Cooldown"
	state.chargeEndsAt = nil
	state.readyAt = now + r.SERVER_COOLDOWN
	return { userIds = ids, bonus = bonus, untilAt = untilAt }, expired
end

-- A player left: drops their active blessing (their data goes too). The personal cooldown stays,
-- so leaving and rejoining does not reset it.
function Ritual.forget(state: State, userId: number)
	state.blessed[userId] = nil
end

-- The sign text: (title, line). `now` is the server clock.
function Ritual.label(state: State, now: number): (string, string)
	local r = Config.RITUAL
	if state.phase == "Cooldown" then
		local left = math.max(0, math.ceil(state.readyAt - now))
		return "Ritual resting", string.format("%d:%02d", left // 60, left % 60)
	elseif state.phase == "Charging" and state.chargeEndsAt then
		return "Hold still!", `{state.count}/{r.MIN_PLAYERS} - {math.max(0, math.ceil(state.chargeEndsAt - now))}s`
	end
	return "Slime Ritual", `{state.count}/{r.MIN_PLAYERS} players`
end

-- Where the explanation sign stands (x, z): on the circle's edge on the plaza side (toward the fountain axis),
-- a few studs off to the side so it doesn't hide the near pad from the plaza.
function Ritual.signSpot(): (number, number)
	local cx, cz = Ritual.centre()
	local d = math.sqrt(cx * cx + cz * cz)
	local off, side = Config.RITUAL.CIRCLE_RADIUS + 0.5, 4
	local ux, uz = cx / d, cz / d
	return cx - ux * off + uz * side, cz - uz * off - ux * side
end

local function duration(seconds: number): string
	if seconds % 60 == 0 then
		return `{seconds // 60} min`
	end
	return `{seconds}s`
end

-- The explanation sign, generated from Config so it can't drift from the rules.
function Ritual.signText(): string
	local r = Config.RITUAL
	local percent = math.floor((r.BONUS[r.MIN_PLAYERS] or 0) * 100 + 0.5)
	return `Slime Ritual: {r.MIN_PLAYERS} players stand here {r.HOLD_SECONDS}s = +{percent}% income for {duration(
		r.BLESS_SECONDS
	)}`
end

return table.freeze(Ritual)
