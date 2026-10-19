--!strict
--[[
	BossWander (pure, contract/boss-event.md)

	Where the fighting boss walks: laps of one smooth loop inside the boss area (the plaza inside the parade lane,
	within Config.BOSS.WANDER_ARC of the boss spot), walked without stopping at Config.BOSS.WANDER_SPEED. The free
	strip there is long and thin, so the loop is a racetrack laid along it: two long sides that follow the strip's
	middle, half a track width either side of it, joined by round ends as wide as the track. It never stops, snaps
	round or turns on the spot. Every point keeps the boss's Body outside the landing ring and its centre
	Config.BOSS.WANDER_CLEARANCE from the lane's edge and the goo drain's lip. Each boss walks it in a seeded
	direction. Positions are { x, z } round the fountain centre. Pure in time: server/WorldView and the client
	(visuals) get the same pose from the same plan.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Fountain = if script then require(script.Parent.Fountain) else require("./Fountain")
local ParadeLane = if script then require(script.Parent.ParadeLane) else require("./ParadeLane")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")

export type Plan = {
	startAt: number,
	home: { number }, -- where it stands when it arrives (the loop point nearest the boss spot)
	points: { { number } }, -- the walk (laps of the loop), dense enough to walk as a polyline
	cumulative: { number }, -- studs from the start to each point
	length: number,
}

local BOSS = Config.BOSS

local BossWander = {}

-- The fighting boss's Body radius: its centre stays this far past the landing ring (visual only, but never run through).
BossWander.BODY_RADIUS = Config.SLIME_BASE_DIAMETER * Config.MAX_SIZE * BOSS.SCALE / 2
BossWander.INNER_RADIUS = Fountain.LANDING_RING_OUTER + BossWander.BODY_RADIUS
BossWander.SCAN_DEGREES = 0.5 -- the strip is measured every this many degrees round the fountain
BossWander.SCAN_STEP = 0.25 -- and every this many studs out from it
BossWander.MARGIN = 0.5 -- studs the track keeps inside the strip's edges
BossWander.TRACK_HALF_WIDTH = 3 -- studs from the strip's middle to each side (and the round ends' radius)
BossWander.MIN_HALF_WIDTH = 1.5 -- narrowest track it settles for on a thin strip
BossWander.SMOOTH_DEGREES = 4 -- the strip's middle is averaged over this many degrees either side (no wiggles)
BossWander.POINT_STEP = 0.5 -- studs between the loop's points
BossWander.EASE_SECONDS = 1 -- it speeds up from a stand over this long when it arrives
BossWander.HEADING_WINDOW = 1.5 -- studs either side of it the heading is taken over

-- The boss spot (Config.BOSS.SPOT_ANGLE / SPOT_RADIUS): where the warning sends players; the loop runs through here.
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

local function dist(a: { number }, b: { number }): number
	return math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
end

local function polar(angle: number, radius: number): { number }
	return { math.cos(angle) * radius, math.sin(angle) * radius }
end

-- The allowed radii (inner, outer) at `angle`: the run of them that holds radius `near`, else the widest; nil if none.
local function strip(angle: number, near: number): (number?, number?)
	local runs: { { number } } = {}
	local open: number? = nil
	local last = BossWander.INNER_RADIUS
	local r = BossWander.INNER_RADIUS
	while r <= ParadeLane.LANE_RADIUS + 1e-9 do
		local p = polar(angle, r)
		if BossWander.allowed(p[1], p[2]) then
			open = open or r
			last = r
		elseif open then
			table.insert(runs, { open, last })
			open = nil
		end
		r += BossWander.SCAN_STEP
	end
	if open then
		table.insert(runs, { open, last })
	end
	local best: { number }? = nil
	for _, run in runs do
		if near >= run[1] and near <= run[2] then
			return run[1], run[2]
		end
		if not best or run[2] - run[1] > best[2] - best[1] then
			best = run
		end
	end
	if best then
		return best[1], best[2]
	end
	return nil, nil
end

type Band = { angles: { number }, mids: { number } }

--[[
	The strip round the boss spot wide enough for a track `half` studs either side of its middle: its angles (one
	every SCAN_DEGREES, contiguous through the spot) and its smoothed middle radius at each. Nil if the spot itself
	is too thin.
]]
local function band(half: number): Band?
	local step = math.rad(BossWander.SCAN_DEGREES)
	local need = 2 * (half + BossWander.MARGIN)
	local function measure(angle: number): (number?, number?)
		local inner, outer = strip(angle, BOSS.SPOT_RADIUS)
		if inner and outer and outer - inner >= need then
			return inner, outer
		end
		return nil, nil
	end
	if not measure(BOSS.SPOT_ANGLE) then
		return nil
	end
	local angles: { number }, inners: { number }, outers: { number } = {}, {}, {}
	local function grow(direction: number)
		local k = if direction > 0 then 1 else 0
		while true do
			local angle = BOSS.SPOT_ANGLE + direction * k * step
			if angleBetween(angle, BOSS.SPOT_ANGLE) > BOSS.WANDER_ARC then
				return
			end
			local inner, outer = measure(angle)
			if not inner then
				return
			end
			local at = if direction > 0 then #angles + 1 else 1
			table.insert(angles, at, angle)
			table.insert(inners, at, inner)
			table.insert(outers, at, outer :: number)
			k += 1
		end
	end
	grow(-1)
	grow(1)
	-- The middle, averaged so the sides bend gently, then pulled back wherever that left a side outside the strip.
	local reach = math.max(1, math.floor(BossWander.SMOOTH_DEGREES / BossWander.SCAN_DEGREES + 0.5))
	local mids = {}
	for i = 1, #angles do
		local sum, n = 0, 0
		for j = math.max(1, i - reach), math.min(#angles, i + reach) do
			sum += (inners[j] + outers[j]) / 2
			n += 1
		end
		local lo = inners[i] + half + BossWander.MARGIN
		local hi = outers[i] - half - BossWander.MARGIN
		mids[i] = math.clamp(sum / n, lo, math.max(lo, hi))
	end
	return { angles = angles, mids = mids }
end

-- The band's middle radius at `angle` (linear between scanned angles).
local function midAt(b: Band, angle: number): number
	local angles, mids = b.angles, b.mids
	if angle <= angles[1] then
		return mids[1]
	elseif angle >= angles[#angles] then
		return mids[#mids]
	end
	local u = (angle - angles[1]) / (angles[#angles] - angles[1]) * (#angles - 1)
	local i = math.floor(u) + 1
	local t = u - (i - 1)
	return mids[i] + (mids[math.min(i + 1, #mids)] - mids[i]) * t
end

--[[
	The racetrack along `b`, `half` studs either side of its middle, as a closed loop of points (the last joins the
	first). In track coordinates u (studs along the strip at the spot's radius) and v (studs out from the middle):
	the far side v = +half, a round end of radius `half`, the near side v = -half, the other round end.
]]
local function track(b: Band, half: number): { { number } }
	local scale = BOSS.SPOT_RADIUS -- studs per radian along the strip
	local a0, a1 = b.angles[1], b.angles[#b.angles]
	local centre = (a0 + a1) / 2
	local straight = math.max(0, (a1 - a0) / 2 * scale - half) -- half the length of each side
	local step = BossWander.POINT_STEP
	local out: { { number } } = {}
	local function put(u: number, v: number)
		local angle = centre + u / scale
		table.insert(out, polar(angle, midAt(b, angle) + v))
	end
	local sideSteps = math.max(1, math.ceil(2 * straight / step))
	local endSteps = math.max(2, math.ceil(math.pi * half / step))
	for i = 0, sideSteps - 1 do
		put(-straight + 2 * straight * i / sideSteps, half)
	end
	for i = 0, endSteps - 1 do
		local a = math.pi / 2 - math.pi * i / endSteps
		put(straight + half * math.cos(a), half * math.sin(a))
	end
	for i = 0, sideSteps - 1 do
		put(straight - 2 * straight * i / sideSteps, -half)
	end
	for i = 0, endSteps - 1 do
		local a = -math.pi / 2 - math.pi * i / endSteps
		put(-straight + half * math.cos(a), half * math.sin(a))
	end
	return out
end

local function allAllowed(points: { { number } }): boolean
	for _, p in points do
		if not BossWander.allowed(p[1], p[2]) then
			return false
		end
	end
	return true
end

-- The widest racetrack that fits round the boss spot (same for every boss), or nil when none does.
local loopCache: { { number } }? = nil
local loopBuilt = false
local function loop(): { { number } }?
	if loopBuilt then
		return loopCache
	end
	loopBuilt = true
	local half = BossWander.TRACK_HALF_WIDTH
	while half >= BossWander.MIN_HALF_WIDTH - 1e-9 do
		local b = band(half)
		if b and #b.angles >= 2 then
			local points = track(b, half)
			if allAllowed(points) then
				loopCache = points
				return points
			end
		end
		half -= 0.25
	end
	return nil
end

--[[
	The walk from `startAt`, at least `duration` seconds of it at WANDER_SPEED: laps of the loop from its point
	nearest the boss spot, in a direction picked by `seed`. Build it once per boss; `pose` reads it every frame.
	Without a loop (a map change left no room) the boss stands at the spot.
]]
function BossWander.plan(seed: number, startAt: number, duration: number): Plan
	local rng = Rng.new(seed)
	local ring = loop()
	local spot = BossWander.home()
	if not ring then
		return { startAt = startAt, home = spot, points = { spot }, cumulative = { 0 }, length = 0 }
	end
	local n = #ring
	local start, best = 1, math.huge
	for i, p in ring do
		local d = dist(p, spot)
		if d < best then
			start, best = i, d
		end
	end
	local direction = if rng:float() < 0.5 then 1 else -1
	local points: { { number } } = {}
	local cumulative: { number } = {}
	local want = duration * BOSS.WANDER_SPEED + BOSS.WANDER_SPEED * BossWander.EASE_SECONDS
	local i, total = start, 0
	while true do
		local p = ring[i]
		if #points > 0 then
			total += dist(points[#points], p)
		end
		table.insert(points, p)
		table.insert(cumulative, total)
		if total >= want then
			break
		end
		i = (i - 1 + direction) % n + 1
	end
	return { startAt = startAt, home = points[1], points = points, cumulative = cumulative, length = total }
end

-- Studs walked `t` seconds after the start: it speeds up from a stand over EASE_SECONDS, then walks at WANDER_SPEED.
function BossWander.walked(t: number): number
	local speed, ease = BOSS.WANDER_SPEED, BossWander.EASE_SECONDS
	if t <= 0 then
		return 0
	elseif t < ease then
		return speed * t * t / (2 * ease)
	end
	return speed * (t - ease / 2)
end

-- The point `s` studs along the walk (clamped to it).
local function pointAt(plan: Plan, s: number): { number }
	local points, cumulative = plan.points, plan.cumulative
	s = math.clamp(s, 0, plan.length)
	local lo, hi = 1, #points - 1
	while lo < hi do
		local m = (lo + hi + 1) // 2
		if cumulative[m] <= s then
			lo = m
		else
			hi = m - 1
		end
	end
	local a, b = points[lo], points[lo + 1]
	local span = cumulative[lo + 1] - cumulative[lo]
	local u = if span > 1e-9 then (s - cumulative[lo]) / span else 0
	return { a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u }
end

--[[
	The boss's centre { x, z } and unit heading { x, z } at `now`: its point along the walk, facing along it
	averaged over HEADING_WINDOW studs either side, so the heading turns a little every frame instead of stepping at
	each point.
]]
function BossWander.pose(plan: Plan, now: number): ({ number }, { number })
	if #plan.points < 2 then
		local face = { -plan.home[1], -plan.home[2] }
		local length = math.sqrt(face[1] ^ 2 + face[2] ^ 2)
		return plan.home, if length > 1e-9 then { face[1] / length, face[2] / length } else { 1, 0 }
	end
	local s = math.clamp(BossWander.walked(now - plan.startAt), 0, plan.length)
	local w = BossWander.HEADING_WINDOW
	local behind, ahead = pointAt(plan, math.min(s - w, plan.length - 2 * w)), pointAt(plan, math.max(s + w, 2 * w))
	local length = dist(behind, ahead)
	local face = if length > 1e-9
		then { (ahead[1] - behind[1]) / length, (ahead[2] - behind[2]) / length }
		else { 1, 0 }
	return pointAt(plan, s), face
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
