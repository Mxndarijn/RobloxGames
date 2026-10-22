--!strict
--[[
	BossAttacks (pure, contract/boss-event.md "Attacks")

	What each boss attack does, as geometry over a BossChoreo move: which attacks a species has (Config.BOSS.MOVES),
	whether a player standing somewhere was struck between two moments, how much a bat hit counts, and where guards
	stand. server/BossEvent applies the results (knockback, stun, slow, guards); clients draw the same geometry as
	telegraphs. Positions are plaza coordinates, like BossChoreo.

	  BossAttacks.get(species, slot) -> Attack?             slot "<set>.<index>", set "start" | "phase"
	  BossAttacks.available(species, meter) -> { slot }     the attacks it may wind up (no passive ones)
	  BossAttacks.vent(species, meter) -> Attack?           its passive back weak spot, once the phase is on
	  BossAttacks.strikes(move, attack, t0, t1, player) -> boolean
	  BossAttacks.hitValue(species, meter, move, t, from) -> (number?, reason?)   meter points for a bat hit
	  BossAttacks.guardSpots(x, z, hx, hz, count) -> { { x, z } }
	  BossAttacks.chargeEnd(x, z, hx, hz, attack) -> (x, z)
]]

local BossArea = if script then require(script.Parent.BossArea) else require("./BossArea")
local BossChoreo = if script then require(script.Parent.BossChoreo) else require("./BossChoreo")
local Config = if script then require(script.Parent.Config) else require("./Config")

local BOSS = Config.BOSS

export type Attack = BossChoreo.Attack

-- A player as an attack sees them: plaza spot and whether they are off the ground (a jump clears a ring).
export type Target = { x: number, z: number, airborne: boolean? }

local BossAttacks = {}

local PASSIVE: { [string]: boolean } = { vent = true }

local function set(species: string, name: string): { Attack }
	local moves = (BOSS.MOVES :: any)[species]
	return if moves and moves[name] then moves[name] else {}
end

function BossAttacks.get(species: string, slot: string): Attack?
	local name, index = string.match(slot, "^(%a+)%.(%d+)$")
	if not name or not index then
		return nil
	end
	return set(species, name)[tonumber(index) :: number]
end

function BossAttacks.available(species: string, meter: number): { string }
	local out = {}
	local names: { string } = if meter >= BOSS.PHASE_AT then { "start", "phase" } else { "start" }
	for _, name in names do
		for i, attack in set(species, name) do
			if not PASSIVE[attack.kind] then
				table.insert(out, `{name}.{i}`)
			end
		end
	end
	return out
end

function BossAttacks.vent(species: string, meter: number): Attack?
	local names: { string } = if meter >= BOSS.PHASE_AT then { "start", "phase" } else { "start" }
	for _, name in names do
		for _, attack in set(species, name) do
			if attack.kind == "vent" then
				return attack
			end
		end
	end
	return nil
end

local function dist(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

-- Where a charge from (x, z) along unit (hx, hz) stops: its distance, or the edge of the boss area.
function BossAttacks.chargeEnd(x: number, z: number, hx: number, hz: number, attack: Attack): (number, number)
	local ex, ez = BossArea.reach(x, z, hx, hz, attack.distance or 30)
	return ex, ez
end

--[[
	True when attack move `move` (definition `attack`) struck `player` between server times t0 and t1. A ring is a
	band RING_WIDTH thick running out from where the boss stomped (from RING_DELAY on, at `speed`, up to `radius`); a
	jumping player clears it. A cone pushes once at CONE_HIT_AT, inside `radius` and `angle` of its heading. A charge
	hits anyone the boss's Body (plus `width` / 2) passes. Spits, guards and vents never strike here.
]]
function BossAttacks.strikes(move: BossChoreo.Move, attack: Attack, t0: number, t1: number, player: Target): boolean
	if move.kind ~= "attack" or t1 < move.at then
		return false
	end
	local kind = attack.kind
	if kind == "ring" then
		if player.airborne then
			return false
		end
		local speed, radius = attack.speed or 20, attack.radius or 20
		local start = move.at + BOSS.RING_DELAY
		if t1 < start then
			return false
		end
		local r0 = math.max(0, speed * (t0 - start))
		local r1 = speed * (t1 - start)
		if r0 > radius then
			return false
		end
		local d = dist(player.x, player.z, move.fx, move.fz)
		local half = BOSS.RING_WIDTH / 2
		return d >= r0 - half and d <= math.min(r1, radius) + half
	elseif kind == "cone" then
		local at = move.at + BOSS.CONE_HIT_AT
		if not (t0 < at and at <= t1) then
			return false
		end
		local dx, dz = player.x - move.fx, player.z - move.fz
		local d = math.sqrt(dx * dx + dz * dz)
		if d > (attack.radius or 18) then
			return false
		end
		if d < 1e-6 then
			return true
		end
		local cos = (dx * move.hx + dz * move.hz) / d
		return cos >= math.cos(math.rad((attack.angle or 90) / 2))
	elseif kind == "charge" then
		if t0 > move.at + move.seconds then
			return false
		end
		local x, z = BossChoreo.pose(move, math.min(t1, move.at + move.seconds))
		return dist(player.x, player.z, x, z) <= BossArea.BODY_RADIUS + (attack.width or 8) / 2
	end
	return false
end

--[[
	Meter points for a bat hit at server time `t` from plaza spot `from` (nil = unknown). nil + reason when it can't be
	hit: floating out of reach while its guards are out. Dazed: DAZED_MULTIPLIER, or a vent's multiplier from behind.
]]
function BossAttacks.hitValue(
	species: string,
	meter: number,
	move: BossChoreo.Move?,
	t: number,
	from: { number }?
): (number?, string?)
	if not move then
		return 1, nil
	end
	if move.kind == "rise" or move.kind == "land" then
		return nil, "it's out of reach"
	end
	if move.kind ~= "dazed" then
		return 1, nil
	end
	local vent = BossAttacks.vent(species, meter)
	if vent and from then
		local x, z, hx, hz = BossChoreo.pose(move, t)
		local dx, dz = from[1] - x, from[2] - z
		local d = math.sqrt(dx * dx + dz * dz)
		if d > 1e-6 and (dx * hx + dz * hz) / d < -0.3 then
			return vent.multiplier or BOSS.DAZED_MULTIPLIER, nil
		end
	end
	return BOSS.DAZED_MULTIPLIER, nil
end

-- `count` guard spots in a ring GUARD_RADIUS round (x, z), the first one in front of the boss.
function BossAttacks.guardSpots(x: number, z: number, hx: number, hz: number, count: number): { { number } }
	local out = {}
	local base = math.atan2(hz, hx)
	for i = 0, math.max(1, count) - 1 do
		local a = base + 2 * math.pi * i / math.max(1, count)
		table.insert(out, { x + math.cos(a) * BOSS.GUARD_RADIUS, z + math.sin(a) * BOSS.GUARD_RADIUS })
	end
	return out
end

return table.freeze(BossAttacks)
