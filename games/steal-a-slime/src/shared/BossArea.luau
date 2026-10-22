--!strict
--[[
	BossArea (pure, contract/boss-event.md)

	Where the fighting boss may stand: the plaza inside the parade lane, within Config.BOSS.WANDER_ARC of the boss
	spot. Its Body stays outside the landing ring, and its centre stays Config.BOSS.WANDER_CLEARANCE from the lane's
	edge and the goo drain's lip. Positions are plaza coordinates: x / z round the fountain centre.

	  BossArea.home() -> (x, z)                               the boss spot, where it arrives
	  BossArea.allowed(x, z) -> boolean
	  BossArea.clear(ax, az, bx, bz) -> boolean               every point of the straight walk is allowed
	  BossArea.reach(x, z, ux, uz, distance) -> (x, z, full)  furthest allowed point along a unit direction
	  BossArea.pick(rng, x, z, toward?) -> (x, z)?            a stroll target from (x, z), nil if none fits
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Fountain = if script then require(script.Parent.Fountain) else require("./Fountain")
local ParadeLane = if script then require(script.Parent.ParadeLane) else require("./ParadeLane")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")

local BOSS = Config.BOSS

local BossArea = {}

-- The fighting boss's Body radius: its centre stays this far past the landing ring.
BossArea.BODY_RADIUS = Config.SLIME_BASE_DIAMETER * Config.MAX_SIZE * BOSS.SCALE / 2
BossArea.INNER_RADIUS = Fountain.LANDING_RING_OUTER + BossArea.BODY_RADIUS
BossArea.PATH_STEP = 1 -- studs between the points a walk is checked at
BossArea.PICK_TRIES = 16 -- stroll targets tried per pick

function BossArea.home(): (number, number)
	return math.cos(BOSS.SPOT_ANGLE) * BOSS.SPOT_RADIUS, math.sin(BOSS.SPOT_ANGLE) * BOSS.SPOT_RADIUS
end

-- Smallest angle between `a` and `b` (radians, 0..pi).
local function angleBetween(a: number, b: number): number
	local d = (a - b) % (2 * math.pi)
	return math.min(d, 2 * math.pi - d)
end

function BossArea.allowed(x: number, z: number): boolean
	if x ~= x or z ~= z then
		return false
	end
	if math.sqrt(x * x + z * z) < BossArea.INNER_RADIUS then
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

function BossArea.clear(ax: number, az: number, bx: number, bz: number): boolean
	local length = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
	local steps = math.max(1, math.ceil(length / BossArea.PATH_STEP))
	for i = 0, steps do
		local u = i / steps
		if not BossArea.allowed(ax + (bx - ax) * u, az + (bz - az) * u) then
			return false
		end
	end
	return true
end

-- The furthest allowed point up to `distance` studs along unit (ux, uz) from (x, z); `full` = it got all the way.
function BossArea.reach(x: number, z: number, ux: number, uz: number, distance: number): (number, number, boolean)
	local bx, bz = x, z
	local s = BossArea.PATH_STEP
	while s <= distance + 1e-9 do
		local px, pz = x + ux * s, z + uz * s
		if not BossArea.allowed(px, pz) then
			return bx, bz, false
		end
		bx, bz = px, pz
		s += BossArea.PATH_STEP
	end
	local ex, ez = x + ux * distance, z + uz * distance
	if BossArea.allowed(ex, ez) then
		return ex, ez, true
	end
	return bx, bz, false
end

--[[
	A stroll target BOSS.STROLL_MIN..STROLL_MAX studs from (x, z) with a clear straight walk to it. The area is a
	long, thin strip round the fountain, so targets are tried along it: a step round the fountain either way and a
	radius anywhere across the strip. With `toward` (the players' middle) it takes the try closest to it, so the
	boss walks into the fight; else a random one.
]]
function BossArea.pick(rng: Rng.Rng, x: number, z: number, toward: { number }?): (number?, number?)
	local bestX, bestZ, best = nil :: number?, nil :: number?, math.huge
	local r = math.max(math.sqrt(x * x + z * z), 1)
	local here = math.atan2(z, x)
	for _ = 1, BossArea.PICK_TRIES do
		local distance = BOSS.STROLL_MIN + rng:float() * (BOSS.STROLL_MAX - BOSS.STROLL_MIN)
		local side = if rng:float() < 0.5 then -1 else 1
		local angle = here + side * distance / r
		local radius = BossArea.INNER_RADIUS + rng:float() * (ParadeLane.LANE_RADIUS - BossArea.INNER_RADIUS)
		local tx, tz = math.cos(angle) * radius, math.sin(angle) * radius
		local d = math.sqrt((tx - x) ^ 2 + (tz - z) ^ 2)
		if d >= BOSS.STROLL_MIN and d <= BOSS.STROLL_MAX and BossArea.clear(x, z, tx, tz) then
			local score = if toward then (tx - toward[1]) ^ 2 + (tz - toward[2]) ^ 2 else rng:float()
			if score < best then
				bestX, bestZ, best = tx, tz, score
			end
		end
	end
	return bestX, bestZ
end

return table.freeze(BossArea)
