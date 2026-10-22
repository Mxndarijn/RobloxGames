--!strict
--[[
	BossChoreo (pure, contract/boss-event.md "Moves")

	How the fighting boss moves, one move at a time. The server picks each move when the last one ends
	(server/BossEvent: where the players are, which attack is due) and publishes it on the boss model as one string
	attribute (BossMove). Every client draws the move from server time, and the server checks hits against the same
	pose, so nobody chases the replicated Body.

	A move: a kind, a start time and length, a start and end spot (plaza coordinates round the fountain centre), the
	heading it ends on, and the plaza origin in world studs, so clients need no map lookup.

	  stroll    walks a straight line, easing in and out (BOSS.STROLL_EASE)
	  look      stands and turns to a player
	  arrive    drops onto the boss spot from BOSS.ARRIVE_HEIGHT and splats
	  windup    stands facing its target; `slot` names the attack (Config.BOSS.MOVES)
	  attack    the attack itself; a charge runs from start to end (facing ahead, or sideways for a scuttle), the rest
	            stand. A multi-leg charge winds up again (LEG_WINDUP_SECONDS) before each leg; slot "<slot>#<leg>"
	  hop       one leg of a hops attack: it leaps to its end spot over HOP_SECONDS, then a ring runs out from there
	  dazed     stands, dizzy (hits count more, BossFight)
	  rise      floats up BOSS.RISE_HEIGHT while its guards are out
	  land      floats back down; slot "daze" = dazed after it
	  down      the meter is full: stands while it shrinks to carry size

	  BossChoreo.first(now, ox, oz) -> Move
	  BossChoreo.after(prev, input) -> Move
	  BossChoreo.hold(kind, prev, now, seconds, slot?) -> Move    stands where `prev` is at `now`
	  BossChoreo.pose(move, t) -> (x, z, hx, hz, lift, u)          plaza spot, unit heading, lift (studs), progress
	  BossChoreo.world(move, t) -> (x, z, hx, hz, lift)            the same in world studs
	  BossChoreo.encode(move) -> string / decode(text) -> Move?
]]

local BossArea = if script then require(script.Parent.BossArea) else require("./BossArea")
local Config = if script then require(script.Parent.Config) else require("./Config")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")

local BOSS = Config.BOSS

export type Kind = "stroll" | "look" | "arrive" | "windup" | "attack" | "hop" | "dazed" | "rise" | "land" | "down"

export type Move = {
	n: number, -- move counter: a new number is a new move
	kind: Kind,
	slot: string, -- windup / attack: "<set>.<index>" in Config.BOSS.MOVES[species]; land: "daze" or ""
	at: number, -- server time it starts
	seconds: number,
	fx: number, -- start spot (plaza)
	fz: number,
	tx: number, -- end spot (plaza)
	tz: number,
	hx: number, -- unit heading it ends on
	hz: number,
	ox: number, -- plaza origin (world studs)
	oz: number,
}

-- An attack definition (Config.BOSS.MOVES entries): kind plus its numbers.
export type Attack = { kind: string, [string]: any }

export type Input = {
	now: number,
	rng: Rng.Rng,
	players: { { number } }, -- plaza x / z of the players near the fight
	target: { number }?, -- the top hitter's plaza spot (charges aim there), else the nearest player
	speed: number, -- move speed multiplier (it speeds up as the meter fills)
	attack: string?, -- slot of the attack to wind up now (nil = none due)
	resolve: (slot: string) -> Attack?, -- slot -> its definition
}

local BossChoreo = {}

local KINDS: { [string]: boolean } = {
	stroll = true,
	look = true,
	arrive = true,
	windup = true,
	attack = true,
	hop = true,
	dazed = true,
	rise = true,
	land = true,
	down = true,
}

local function unit(x: number, z: number, fx: number, fz: number): (number, number)
	local length = math.sqrt(x * x + z * z)
	if length < 1e-6 then
		return fx, fz
	end
	return x / length, z / length
end

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

-- Share of the way walked at `t` of `seconds`, easing in and out over `ease` seconds (a trapezoid speed profile).
local function walked(t: number, seconds: number, ease: number): number
	if seconds <= 0 then
		return 1
	end
	t = math.clamp(t, 0, seconds)
	local e = math.min(ease, seconds / 2)
	local cruise = seconds - e -- v_max = 1 / cruise (shares per second)
	if e <= 0 then
		return t / seconds
	end
	if t < e then
		return t * t / (2 * e) / cruise
	elseif t < seconds - e then
		return (t - e / 2) / cruise
	end
	local left = seconds - t
	return 1 - left * left / (2 * e) / cruise
end

local function make(
	n: number,
	kind: Kind,
	at: number,
	seconds: number,
	fx: number,
	fz: number,
	tx: number,
	tz: number,
	hx: number,
	hz: number,
	ox: number,
	oz: number,
	slot: string?
): Move
	return {
		n = n,
		kind = kind,
		slot = slot or "",
		at = at,
		seconds = math.max(seconds, 0.05),
		fx = fx,
		fz = fz,
		tx = tx,
		tz = tz,
		hx = hx,
		hz = hz,
		ox = ox,
		oz = oz,
	}
end

-- The boss lands on the boss spot facing out of the plaza (away from the fountain).
function BossChoreo.first(now: number, ox: number, oz: number): Move
	local x, z = BossArea.home()
	local hx, hz = unit(x, z, 1, 0)
	return make(1, "arrive", now, BOSS.ARRIVE_SECONDS, x, z, x, z, hx, hz, ox, oz)
end

function BossChoreo.pose(move: Move, t: number): (number, number, number, number, number, number)
	local u = math.clamp((t - move.at) / move.seconds, 0, 1)
	local kind = move.kind
	local x, z = move.tx, move.tz
	local hx, hz = move.hx, move.hz
	local lift = 0
	if kind == "stroll" or (kind == "attack" and (move.fx ~= move.tx or move.fz ~= move.tz)) then
		local ease = if kind == "stroll" then BOSS.STROLL_EASE else BOSS.CHARGE_EASE
		local s = walked(t - move.at, move.seconds, ease)
		x, z = move.fx + (move.tx - move.fx) * s, move.fz + (move.tz - move.fz) * s
		if kind == "stroll" then
			hx, hz = unit(move.tx - move.fx, move.tz - move.fz, hx, hz)
		end -- a charge keeps its facing: a crab scuttles sideways
	elseif kind == "hop" then
		local k = math.clamp((t - move.at) / BOSS.HOP_SECONDS, 0, 1)
		local s = smooth(k)
		x, z = move.fx + (move.tx - move.fx) * s, move.fz + (move.tz - move.fz) * s
		lift = BOSS.HOP_HEIGHT * 4 * k * (1 - k)
	elseif kind == "arrive" then
		local fall = BOSS.ARRIVE_FALL / move.seconds
		local k = math.clamp(u / fall, 0, 1)
		lift = BOSS.ARRIVE_HEIGHT * (1 - k * k)
	elseif kind == "rise" then
		lift = BOSS.RISE_HEIGHT * smooth((t - move.at) / BOSS.RISE_SECONDS)
	elseif kind == "land" then
		lift = BOSS.RISE_HEIGHT * (1 - smooth(u))
	end
	return x, z, hx, hz, lift, u
end

function BossChoreo.world(move: Move, t: number): (number, number, number, number, number)
	local x, z, hx, hz, lift = BossChoreo.pose(move, t)
	return x + move.ox, z + move.oz, hx, hz, lift
end

function BossChoreo.ended(move: Move, now: number): boolean
	return now >= move.at + move.seconds
end

-- Stands where `prev` is at `now` (facing where it faces) for `seconds`.
function BossChoreo.hold(kind: Kind, prev: Move, now: number, seconds: number, slot: string?): Move
	local x, z, hx, hz = BossChoreo.pose(prev, now)
	return make(prev.n + 1, kind, now, seconds, x, z, x, z, hx, hz, prev.ox, prev.oz, slot)
end

-- The nearest of `players` to (x, z), or nil.
local function nearest(players: { { number } }, x: number, z: number): { number }?
	local best, bestD = nil, math.huge
	for _, p in players do
		local d = (p[1] - x) ^ 2 + (p[2] - z) ^ 2
		if d < bestD then
			best, bestD = p, d
		end
	end
	return best
end

local function middle(players: { { number } }): { number }?
	if #players == 0 then
		return nil
	end
	local sx, sz = 0, 0
	for _, p in players do
		sx += p[1]
		sz += p[2]
	end
	return { sx / #players, sz / #players }
end

local function between(rng: Rng.Rng, range: { number }): number
	return range[1] + rng:float() * (range[2] - range[1])
end

local function look(prev: Move, input: Input): Move
	local x, z = prev.tx, prev.tz
	local hx, hz = prev.hx, prev.hz
	local p = nearest(input.players, x, z)
	if p then
		hx, hz = unit(p[1] - x, p[2] - z, hx, hz)
	end
	return make(
		prev.n + 1,
		"look",
		input.now,
		between(input.rng, BOSS.LOOK_SECONDS),
		x,
		z,
		x,
		z,
		hx,
		hz,
		prev.ox,
		prev.oz
	)
end

local function stroll(prev: Move, input: Input): Move
	local x, z = prev.tx, prev.tz
	local toward = if input.rng:float() < BOSS.STROLL_TOWARD then middle(input.players) else nil
	local tx, tz = BossArea.pick(input.rng, x, z, toward)
	if not tx or not tz then
		return look(prev, input) -- boxed in: turn round instead
	end
	local hx, hz = unit(tx - x, tz - z, prev.hx, prev.hz)
	local distance = math.sqrt((tx - x) ^ 2 + (tz - z) ^ 2)
	local seconds = distance / (BOSS.STROLL_SPEED * input.speed) + BOSS.STROLL_EASE
	return make(prev.n + 1, "stroll", input.now, seconds, x, z, tx, tz, hx, hz, prev.ox, prev.oz)
end

-- "start.1#2" -> ("start.1", 2): an attack slot and which leg of it (1 without a suffix).
function BossChoreo.slotLeg(slot: string): (string, number)
	local base, leg = string.match(slot, "^(.-)#(%d+)$")
	if base and leg then
		return base, tonumber(leg) :: number
	end
	return slot, 1
end

local function withLeg(slot: string, leg: number): string
	local base = BossChoreo.slotLeg(slot)
	return if leg <= 1 then base else `{base}#{leg}`
end

-- How many legs attack `attack` runs: a charge 1 + bounces, hops `count`, anything else 1.
function BossChoreo.legs(attack: Attack): number
	if attack.kind == "charge" then
		return 1 + math.max(0, attack.bounces or 0)
	elseif attack.kind == "hops" then
		return math.max(1, attack.count or 3)
	end
	return 1
end

-- The way a charge travels for facing (hx, hz): straight ahead, or to its right for a sideways scuttle.
function BossChoreo.travel(attack: Attack, hx: number, hz: number): (number, number)
	if attack.sideways then
		return -hz, hx
	end
	return hx, hz
end

-- The facing that makes `attack` travel along unit (ux, uz) (the inverse of `travel`).
local function facingFor(attack: Attack, ux: number, uz: number): (number, number)
	if attack.sideways then
		return uz, -ux
	end
	return ux, uz
end

local function windup(prev: Move, input: Input, slot: string, attack: Attack): Move
	local x, z = prev.tx, prev.tz
	local _, leg = BossChoreo.slotLeg(slot)
	local ux, uz = BossChoreo.travel(attack, prev.hx, prev.hz)
	if leg > 1 and attack.backAndForth then
		ux, uz = unit(prev.fx - prev.tx, prev.fz - prev.tz, -ux, -uz) -- runs back the way it came
	elseif attack.sideways then
		-- a scuttle runs along the boss area (a thin strip round the fountain), toward the side its target is on
		local rx, rz = unit(x, z, 1, 0)
		ux, uz = -rz, rx
		local aim = input.target or nearest(input.players, x, z)
		if aim and (aim[1] - x) * ux + (aim[2] - z) * uz < 0 then
			ux, uz = -ux, -uz
		end
	else
		local aim = if attack.kind == "charge" then input.target else nil
		aim = aim or nearest(input.players, x, z)
		if aim then
			ux, uz = unit(aim[1] - x, aim[2] - z, ux, uz)
		elseif leg > 1 then
			ux, uz = -ux, -uz
		end
		-- the area is a thin strip: a charge that would stop within CHARGE_MIN runs along the strip instead
		if attack.kind == "charge" then
			local ex, ez = BossArea.reach(x, z, ux, uz, attack.distance or 30)
			if (ex - x) ^ 2 + (ez - z) ^ 2 < BOSS.CHARGE_MIN ^ 2 then
				local rx, rz = unit(x, z, 1, 0)
				local tx, tz = -rz, rx
				if ux * tx + uz * tz < 0 then
					tx, tz = -tx, -tz
				end
				ux, uz = tx, tz
			end
		end
	end
	local hx, hz = facingFor(attack, ux, uz)
	local seconds = if leg > 1 then BOSS.LEG_WINDUP_SECONDS else BOSS.WINDUP_SECONDS
	return make(prev.n + 1, "windup", input.now, seconds, x, z, x, z, hx, hz, prev.ox, prev.oz, slot)
end

-- One hop of a `hops` attack: toward the target (or the nearest player) by `distance`, inside the area.
local function hop(prev: Move, input: Input, attack: Attack, leg: number): Move
	local x, z = prev.tx, prev.tz
	local aim = input.target or nearest(input.players, x, z)
	local ux, uz = prev.hx, prev.hz
	if aim then
		ux, uz = unit(aim[1] - x, aim[2] - z, ux, uz)
	end
	local distance = attack.distance or 7
	local ex, ez = BossArea.reach(x, z, ux, uz, distance)
	if (ex - x) ^ 2 + (ez - z) ^ 2 < (distance / 2) ^ 2 then
		-- aimed off the thin strip: hop along it instead, toward the target's side
		local rx, rz = unit(x, z, 1, 0)
		local tx, tz = -rz, rx
		if ux * tx + uz * tz < 0 then
			tx, tz = -tx, -tz
		end
		ux, uz = tx, tz
		ex, ez = BossArea.reach(x, z, ux, uz, distance)
	end
	local seconds = BOSS.HOP_SECONDS + (attack.radius or 12) / (attack.speed or 24)
	return make(prev.n + 1, "hop", input.now, seconds, x, z, ex, ez, ux, uz, prev.ox, prev.oz, withLeg(prev.slot, leg))
end

-- How long a ring attack runs: until its last wave has run out (a wave starts `waveGap` after the last, `waveSpeedUp`
-- times as fast).
function BossChoreo.ringSeconds(attack: Attack): number
	local longest = 0
	for w = 0, math.max(1, attack.waves or 1) - 1 do
		local start = w * (attack.waveGap or 0.7)
		local speed = (attack.speed or 20) * (attack.waveSpeedUp or 1) ^ w
		longest = math.max(longest, start + (attack.radius or 20) / speed)
	end
	return BOSS.RING_DELAY + longest
end

-- How long attack `attack` runs, and where it ends (only a charge moves).
local function attackMove(prev: Move, input: Input, attack: Attack, leg: number): Move
	local x, z = prev.tx, prev.tz
	local kind = attack.kind
	if kind == "hops" then
		return hop(prev, input, attack, leg)
	end
	if kind == "guards" then
		return make(
			prev.n + 1,
			"rise",
			input.now,
			BOSS.GUARD_SECONDS,
			x,
			z,
			x,
			z,
			prev.hx,
			prev.hz,
			prev.ox,
			prev.oz,
			prev.slot
		)
	end
	if kind == "charge" then
		local ux, uz = BossChoreo.travel(attack, prev.hx, prev.hz)
		local ex, ez = BossArea.reach(x, z, ux, uz, attack.distance or 30)
		local distance = math.sqrt((ex - x) ^ 2 + (ez - z) ^ 2)
		local seconds = distance / (attack.speed or 30) + BOSS.CHARGE_EASE
		return make(
			prev.n + 1,
			"attack",
			input.now,
			seconds,
			x,
			z,
			ex,
			ez,
			prev.hx,
			prev.hz,
			prev.ox,
			prev.oz,
			prev.slot
		)
	end
	local seconds = BOSS.STRIKE_SECONDS
	if kind == "ring" then
		seconds = BossChoreo.ringSeconds(attack)
	elseif kind == "spit" then
		seconds = BOSS.SPIT_FLIGHT + BOSS.STRIKE_SECONDS
	end
	return make(prev.n + 1, "attack", input.now, seconds, x, z, x, z, prev.hx, prev.hz, prev.ox, prev.oz, prev.slot)
end

-- The move after `prev` (which has ended).
function BossChoreo.after(prev: Move, input: Input): Move
	local kind = prev.kind
	if kind == "down" then
		return BossChoreo.hold("down", prev, input.now, BOSS.HAUL_SECONDS)
	elseif kind == "windup" then
		local attack = input.resolve(prev.slot)
		if attack then
			local _, leg = BossChoreo.slotLeg(prev.slot)
			return attackMove(prev, input, attack, leg)
		end
		return look(prev, input)
	elseif kind == "attack" or kind == "hop" then
		-- the next leg: a charge winds up again (a short one), a hop springs straight on
		local attack = input.resolve(prev.slot)
		local _, leg = BossChoreo.slotLeg(prev.slot)
		if attack and leg < BossChoreo.legs(attack) then
			if attack.kind == "hops" then
				return hop(prev, input, attack, leg + 1)
			end
			return windup(prev, input, withLeg(prev.slot, leg + 1), attack)
		end
		return make(
			prev.n + 1,
			"dazed",
			input.now,
			BOSS.DAZED_SECONDS,
			prev.tx,
			prev.tz,
			prev.tx,
			prev.tz,
			prev.hx,
			prev.hz,
			prev.ox,
			prev.oz,
			prev.slot
		)
	elseif kind == "rise" then
		return BossChoreo.hold("land", prev, input.now, BOSS.LAND_SECONDS)
	elseif kind == "land" and prev.slot == "daze" then
		return make(
			prev.n + 1,
			"dazed",
			input.now,
			BOSS.DAZED_SECONDS,
			prev.tx,
			prev.tz,
			prev.tx,
			prev.tz,
			prev.hx,
			prev.hz,
			prev.ox,
			prev.oz
		)
	elseif kind == "stroll" or kind == "arrive" or kind == "land" then
		return look(prev, input)
	end
	-- look / dazed: an attack when one is due, else walk on
	local slot = input.attack
	local attack = if slot and kind == "look" then input.resolve(slot) else nil
	if slot and attack then
		return windup(prev, input, slot, attack)
	end
	return stroll(prev, input)
end

local function num(value: number): string
	return string.format("%.3f", value)
end

function BossChoreo.encode(move: Move): string
	return table.concat({
		tostring(move.n),
		move.kind,
		move.slot,
		num(move.at),
		num(move.seconds),
		num(move.fx),
		num(move.fz),
		num(move.tx),
		num(move.tz),
		num(move.hx),
		num(move.hz),
		num(move.ox),
		num(move.oz),
	}, "|")
end

function BossChoreo.decode(text: any): Move?
	if type(text) ~= "string" then
		return nil
	end
	local parts = string.split(text, "|")
	if #parts ~= 13 or not KINDS[parts[2]] then
		return nil
	end
	local values = {}
	for i, index in { 1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13 } do
		local v = tonumber(parts[index])
		if v == nil or v ~= v then
			return nil
		end
		values[i] = v
	end
	return {
		n = values[1],
		kind = parts[2] :: Kind,
		slot = parts[3],
		at = values[2],
		seconds = math.max(values[3], 0.05),
		fx = values[4],
		fz = values[5],
		tx = values[6],
		tz = values[7],
		hx = values[8],
		hz = values[9],
		ox = values[10],
		oz = values[11],
	}
end

return table.freeze(BossChoreo)
