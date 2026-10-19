--!strict
--[[
	BossWander (pure, contract/boss-event.md)

	Where the fighting boss walks: a seeded plan of legs (stand still for a while, then walk straight to a new point)
	inside the boss area, the plaza inside the parade lane within Config.BOSS.WANDER_ARC of the boss spot. Every point
	of every leg keeps the boss's centre outside the landing ring and Config.BOSS.WANDER_CLEARANCE from the lane's edge
	and the goo drain's lip. Positions are { x, z } round the fountain centre. server/WorldView pivots the model.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Fountain = if script then require(script.Parent.Fountain) else require("./Fountain")
local ParadeLane = if script then require(script.Parent.ParadeLane) else require("./ParadeLane")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")

export type Leg = {
	startAt: number, -- it stands at `from` from here
	moveAt: number, -- and walks from here
	endAt: number, -- reaching `to` here
	from: { number },
	to: { number },
}

export type Plan = { legs: { Leg }, home: { number } }

local BOSS = Config.BOSS

local BossWander = {}

-- The fighting boss's Body radius: its centre stays this far past the landing ring (visual only, but never run through).
BossWander.BODY_RADIUS = Config.SLIME_BASE_DIAMETER * Config.MAX_SIZE * BOSS.SCALE / 2
BossWander.INNER_RADIUS = Fountain.LANDING_RING_OUTER + BossWander.BODY_RADIUS
BossWander.MIN_STEP = 4 -- studs: shorter walks are not worth the turn
BossWander.MAX_STEP = 18
BossWander.TRIES = 24 -- target picks per leg before it stays where it is for another pause
BossWander.SAMPLE_STEP = 2 -- studs between the checked points of a leg

-- The boss spot (Config.BOSS.SPOT_ANGLE / SPOT_RADIUS): where the boss arrives and every plan starts.
function BossWander.home(): { number }
	return { math.cos(BOSS.SPOT_ANGLE) * BOSS.SPOT_RADIUS, math.sin(BOSS.SPOT_ANGLE) * BOSS.SPOT_RADIUS }
end

-- Smallest angle between `a` and `b` (radians, 0..pi).
local function angleBetween(a: number, b: number): number
	local d = (a - b) % (2 * math.pi)
	return math.min(d, 2 * math.pi - d)
end

-- True when the boss's centre may stand at (x, z).
function BossWander.allowed(x: number, z: number): boolean
	local r = math.sqrt(x * x + z * z)
	if r < BossWander.INNER_RADIUS then
		return false
	end
	if angleBetween(math.atan2(z, x), BOSS.SPOT_ANGLE) > BOSS.WANDER_ARC then
		return false
	end
	local _, laneGap = ParadeLane.nearest(x, z)
	if laneGap < ParadeLane.HALF_WIDTH + BOSS.WANDER_CLEARANCE then
		return false
	end
	local drain = ParadeLane.DRAIN
	return math.sqrt((x - drain.x) ^ 2 + (z - drain.z) ^ 2) >= drain.lipRadius + BOSS.WANDER_CLEARANCE
end

-- True when every point of the straight walk from `a` to `b` is allowed.
function BossWander.clearPath(a: { number }, b: { number }): boolean
	local length = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
	local n = math.max(1, math.ceil(length / BossWander.SAMPLE_STEP))
	for i = 0, n do
		local u = i / n
		if not BossWander.allowed(a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u) then
			return false
		end
	end
	return true
end

local function between(rng: Rng.Rng, lo: number, hi: number): number
	return lo + (hi - lo) * rng:float()
end

-- A new point within MIN_STEP..MAX_STEP of `from` that the boss can walk to in a straight line, or nil.
local function pickTarget(rng: Rng.Rng, from: { number }): { number }?
	for _ = 1, BossWander.TRIES do
		local direction = between(rng, 0, 2 * math.pi)
		local step = between(rng, BossWander.MIN_STEP, BossWander.MAX_STEP)
		local to = { from[1] + math.cos(direction) * step, from[2] + math.sin(direction) * step }
		if BossWander.clearPath(from, to) then
			return to
		end
	end
	return nil
end

--[[
	The walk from `startAt` for `duration` seconds, seeded by `seed`: legs back to back from the boss spot. Build it
	once per boss (it checks every leg against the lane); `pose` reads it every frame.
]]
function BossWander.plan(seed: number, startAt: number, duration: number): Plan
	local rng = Rng.new(seed)
	local home = BossWander.home()
	local legs: { Leg } = {}
	local at, t = home, startAt
	while t < startAt + duration do
		local moveAt = t + between(rng, BOSS.WANDER_PAUSE[1], BOSS.WANDER_PAUSE[2])
		local to = pickTarget(rng, at) or at
		local step = math.sqrt((to[1] - at[1]) ^ 2 + (to[2] - at[2]) ^ 2)
		local endAt = moveAt + step / BOSS.WANDER_SPEED
		table.insert(legs, { startAt = t, moveAt = moveAt, endAt = endAt, from = at, to = to })
		at, t = to, endAt
	end
	return { legs = legs, home = home }
end

-- Unit heading from `a` to `b`, or nil when they are the same point.
local function heading(a: { number }, b: { number }): { number }?
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local length = math.sqrt(dx * dx + dz * dz)
	return if length > 1e-6 then { dx / length, dz / length } else nil
end

--[[
	The boss's centre { x, z } and unit heading { x, z } at `now`. Standing still it faces where it is about to walk
	(the fountain when it has nowhere to go). It eases in and out of every walk.
]]
function BossWander.pose(plan: Plan, now: number): ({ number }, { number })
	local face = heading(plan.home, { 0, 0 }) or { 1, 0 }
	for _, leg in plan.legs do
		face = heading(leg.from, leg.to) or face
		if now < leg.moveAt then
			return leg.from, face
		elseif now < leg.endAt then
			local u = (now - leg.moveAt) / (leg.endAt - leg.moveAt)
			u = u * u * (3 - 2 * u)
			return { leg.from[1] + (leg.to[1] - leg.from[1]) * u, leg.from[2] + (leg.to[2] - leg.from[2]) * u }, face
		end
	end
	local last = plan.legs[#plan.legs]
	return if last then last.to else plan.home, face
end

-- A plan seed from the boss slime's id (any string).
function BossWander.seed(id: string): number
	local h = 5381
	for i = 1, #id do
		h = (h * 33 + string.byte(id, i)) % 2147483647
	end
	return h
end

return table.freeze(BossWander)
