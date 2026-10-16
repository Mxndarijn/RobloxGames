--!strict
--[[
	ParadeLane (pure, FEATURES.Parade)

	The goo parade: how an unclaimed wild slime leaves the plaza. It rides
	the fountain slide (FountainRide) and its run-out lands it on ENTRY, the
	head of a goo lane that loops round the plaza. It hops along the lane
	and, at the far end, slides over the goo drain's curb and sinks in; the
	server removes it at expiresAt with a splash at the drain.

	Lane position is time left. With lifetime = expiresAt - spawnedAt and
	  progress = 1 - (expiresAt - now) / lifetime        (0 at spawn, 1 at expiry)
	the slime is
	  Ride   progress < HOP_SECONDS / lifetime: on the slide, then waiting
	         on ENTRY (WorldView plays the ride; it lands before HOP_SECONDS)
	  Walk   then along the lane, distance LENGTH * the share of the walk
	         window gone, linear in time left, ending on the last waypoint
	  Drain  the last DRAIN_SECONDS: hop onto the curb lip, slide into the
	         funnel and sink below the plaza (DRAIN.sinkY)
	  Gone   now >= expiresAt (Spawner removes it; DespawnTelegraph.shouldRemove)
	Spawn cadence, cap and lifetimes don't change, and removal is still at
	expiresAt. A slime that is carried, or was dropped somewhere
	(wild.position set), is off the lane: it stays where it was put.

	Route (WAYPOINTS, Roblox x / z, fountain axis at the origin, wild angle
	convention: (cos a, sin a)): from the slide exit side (+Z, just past the
	drain) counter-clockwise on the r 68 goo-parade centreline, dipping
	inside the hub SpawnLocation (r 64 at 202.5°) and the leaderboard
	podiums + signpost (285°-337.5°), back out to r 68 and round to the
	drain on +Z. tests/ParadeLane.spec checks the route clears every plaza
	prop, podium, prop spot, ranch prop, plot, the spawn pad, the ring path,
	the landing ring and the low slide by CLEARANCE. The whole route stays
	inside Visuals.PropClearance's keep-clear rings (landing band r 34-62,
	lane / gate posts r 62.25-73.75), so kit props stay off it.

	Readability of the despawn telegraph (DespawnTelegraphFx, "leaving! N"):
	the warning window (DESPAWN_TELEGRAPH_SECONDS) starts while the slime is
	still walking the lane next to the drain (WARN_SECONDS > DRAIN_SECONDS)
	and consecutive drops (SPAWN_INTERVAL apart) are far enough apart on the
	lane that two countdowns never stack.

	No Roblox APIs at load time.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local DespawnTelegraph = if script then require(script.Parent.DespawnTelegraph) else require("./DespawnTelegraph")

export type Phase = "Ride" | "Walk" | "Drain" | "Gone"
export type Pose = {
	position: { number }, -- x, y (pivot = slime bottom), z
	heading: { number }, -- unit x, z of travel
	phase: Phase,
}

local ParadeLane = {}

ParadeLane.LANE_RADIUS = 68 -- FOUNTAIN_SIZES goo-parade centreline (PropClearance keeps r 64.75-71.25 clear)
ParadeLane.HALF_WIDTH = 3.25 -- kit lane incl. edging: 6.5 studs wide
ParadeLane.SPREAD = 3 -- slimes walk up to SPREAD / 2 either side of the centreline (from their Fountain.roll radius)
ParadeLane.SLIME_RADIUS = Config.SLIME_BASE_DIAMETER * Config.MAX_SIZE / 2 -- the biggest slime
ParadeLane.MARGIN = 1
-- Air from the centreline to any prop: the lane edge or the widest slime, whichever is further, + MARGIN.
ParadeLane.CLEARANCE = math.max(ParadeLane.HALF_WIDTH, ParadeLane.SPREAD / 2 + ParadeLane.SLIME_RADIUS)
	+ ParadeLane.MARGIN
ParadeLane.LANE_Y = 0.35 -- top of the goo strip (ParadeView); slime pivots stand on it
ParadeLane.STRIP_THICKNESS = 0.3
-- Ride + hop on: every ride to ENTRY lands well before this (tests/ParadeLane.spec).
ParadeLane.HOP_SECONDS = 9
ParadeLane.DRAIN_SECONDS = 1.5
ParadeLane.HOP_HEIGHT = 1.2 -- studs at the top of each hop while walking
ParadeLane.HOP_PERIOD = 0.5 -- seconds per hop (rounded so the walk holds a whole number)
ParadeLane.WARN_SECONDS = Config.DESPAWN_TELEGRAPH_SECONDS -- ring warn = despawn telegraph window
-- ranch_goo_drain (WorldLayout Plaza.GooDrain, box centre z 52): the curb
-- ring (r 3.3-4.4, 1 stud tall) sits on the +Z end of the box, its post on
-- the fountain side.
ParadeLane.DRAIN = table.freeze({ x = 0, z = 52.5, lipRadius = 4.4, lipY = 1, sinkY = -3 })
ParadeLane.DRAIN_LIP_SHARE = 0.4 -- share of DRAIN_SECONDS spent hopping onto the lip

-- Lane route as (wild angle in degrees, radius) controls; radii ease
-- (smoothstep) between neighbours. Angles grow counter-clockwise from the
-- entry at 112.5° to 430° (= 70°) beside the drain.
local CONTROLS: { { number } } = {
	{ 112.5, 68 },
	{ 170, 68 },
	{ 186, 49.5 }, -- inside the hub SpawnLocation (12 x 12 at r 64, 202.5°)
	{ 219, 49.5 },
	{ 235, 68 },
	{ 262, 68 },
	{ 276, 56 }, -- inside the podiums (285°-300°) and the signpost (337.5°)
	{ 350, 56 },
	{ 366, 68 },
	{ 430, 68 },
}
local STEP_DEGREES = 2.5
local TAIL: { { number } } = { { 9.5, 61.5 } } -- off r 68 towards the drain's outer (+Z) side

local function build(): { { number } }
	local points: { { number } } = {}
	for k = 1, #CONTROLS - 1 do
		local a0, r0 = CONTROLS[k][1], CONTROLS[k][2]
		local a1, r1 = CONTROLS[k + 1][1], CONTROLS[k + 1][2]
		local n = math.max(1, math.ceil((a1 - a0) / STEP_DEGREES))
		for i = if k == 1 then 0 else 1, n do
			local u = i / n
			local a = math.rad(a0 + (a1 - a0) * u)
			local r = r0 + (r1 - r0) * (u * u * (3 - 2 * u))
			table.insert(points, { math.cos(a) * r, math.sin(a) * r })
		end
	end
	for _, p in TAIL do
		table.insert(points, { p[1], p[2] })
	end
	-- Last waypoint: just outside the curb, on the line from the tail to the drain centre.
	local d = ParadeLane.DRAIN
	local last = points[#points]
	local dx, dz = last[1] - d.x, last[2] - d.z
	local len = math.sqrt(dx * dx + dz * dz)
	local out = d.lipRadius + ParadeLane.SLIME_RADIUS
	table.insert(points, { d.x + dx / len * out, d.z + dz / len * out })
	return points
end

local points = build()
local cumulative = { 0 }
for i = 2, #points do
	local a, b = points[i - 1], points[i]
	cumulative[i] = cumulative[i - 1] + math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
end
-- Unit normal (-hz, hx) at each waypoint, averaged over its two segments,
-- so a sideways offset bends smoothly round the turns.
local normals: { { number } } = {}
for i = 1, #points do
	local a, b = points[math.max(1, i - 1)], points[math.min(#points, i + 1)]
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local len = math.max(math.sqrt(dx * dx + dz * dz), 1e-9)
	normals[i] = { -dz / len, dx / len }
end
for _, p in points do
	table.freeze(p)
end

ParadeLane.WAYPOINTS = table.freeze(points) :: { { number } } -- { x, z }, entry first, drain approach last
ParadeLane.LENGTH = cumulative[#cumulative]
ParadeLane.ENTRY = points[1]
ParadeLane.EXIT = points[#points]

function ParadeLane.enabled(features: { [string]: boolean }?): boolean
	local f = features or Config.FEATURES
	return f.Parade == true
end

-- 0 at spawn, 1 at expiresAt: 1 - time left / lifetime.
function ParadeLane.progress(spawnedAt: number, expiresAt: number, now: number): number
	local lifetime = expiresAt - spawnedAt
	if lifetime <= 0 then
		return 1
	end
	return math.clamp(1 - (expiresAt - now) / lifetime, 0, 1)
end

-- Progress at which the walk starts and ends (the drain slide fills the rest).
function ParadeLane.walkWindow(lifetime: number): (number, number)
	if lifetime <= 0 then
		return 0, 0
	end
	local hop = math.min(ParadeLane.HOP_SECONDS, lifetime)
	local drain = math.min(ParadeLane.DRAIN_SECONDS, lifetime - hop)
	return hop / lifetime, 1 - drain / lifetime
end

function ParadeLane.phase(spawnedAt: number, expiresAt: number, now: number): Phase
	if now >= expiresAt then
		return "Gone"
	end
	local p = ParadeLane.progress(spawnedAt, expiresAt, now)
	local start, stop = ParadeLane.walkWindow(expiresAt - spawnedAt)
	if p < start then
		return "Ride"
	elseif p < stop then
		return "Walk"
	end
	return "Drain"
end

-- Studs walked along the lane: 0 until the walk starts, LENGTH from the drain slide on.
function ParadeLane.distance(spawnedAt: number, expiresAt: number, now: number): number
	local p = ParadeLane.progress(spawnedAt, expiresAt, now)
	local start, stop = ParadeLane.walkWindow(expiresAt - spawnedAt)
	if stop <= start then
		return if p >= stop then ParadeLane.LENGTH else 0
	end
	return ParadeLane.LENGTH * math.clamp((p - start) / (stop - start), 0, 1)
end

-- Segment holding lane distance `s` (clamped) and how far along it (0..1).
local function locate(s: number): (number, number, number)
	s = math.clamp(s, 0, ParadeLane.LENGTH)
	local lo, hi = 1, #points
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if cumulative[mid] <= s then
			lo = mid
		else
			hi = mid
		end
	end
	local span = cumulative[hi] - cumulative[lo]
	return lo, hi, if span > 1e-9 then (s - cumulative[lo]) / span else 0
end

-- Lane point `s` studs from ENTRY (clamped) and the unit direction of travel there.
function ParadeLane.pointAt(s: number): (number, number, number, number)
	local lo, hi, k = locate(s)
	local a, b = points[lo], points[hi]
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local len = math.max(math.sqrt(dx * dx + dz * dz), 1e-9)
	return a[1] + dx * k, a[2] + dz * k, dx / len, dz / len
end

-- Point `lateral` studs to the side of the centreline at `s` (along the
-- smoothed normal; positive = the lane's left, the fountain side).
function ParadeLane.offsetAt(s: number, lateral: number): (number, number)
	local lo, hi, k = locate(s)
	local a, b = points[lo], points[hi]
	local na, nb = normals[lo], normals[hi]
	local nx, nz = na[1] + (nb[1] - na[1]) * k, na[2] + (nb[2] - na[2]) * k
	local len = math.max(math.sqrt(nx * nx + nz * nz), 1e-9)
	return a[1] + (b[1] - a[1]) * k + nx / len * lateral, a[2] + (b[2] - a[2]) * k + nz / len * lateral
end

-- Sideways offset of a slime from the centreline, from its Fountain.roll
-- radius (minRadius..maxRadius -> -SPREAD/2..SPREAD/2). Keeps a rain's drops
-- from stacking on one line without another rng draw.
function ParadeLane.lateral(rollRadius: number, minRadius: number, maxRadius: number): number
	local span = maxRadius - minRadius
	local u = if span > 0 then math.clamp((rollRadius - minRadius) / span, 0, 1) else 0.5
	return (u - 0.5) * ParadeLane.SPREAD
end

-- Where the ride lands a slime with this lateral offset (y = LANE_Y).
function ParadeLane.entrySpot(lateral: number): { number }
	local x, z = ParadeLane.offsetAt(0, lateral)
	return { x, ParadeLane.LANE_Y, z }
end

-- Full pose of a lane slime at `now`.
function ParadeLane.pose(spawnedAt: number, expiresAt: number, lateral: number, now: number): Pose
	local phase = ParadeLane.phase(spawnedAt, expiresAt, now)
	if phase == "Drain" or phase == "Gone" then
		local d = ParadeLane.DRAIN
		local ex, ez = ParadeLane.offsetAt(ParadeLane.LENGTH, lateral) -- where the walk ended
		local dx, dz = d.x - ParadeLane.EXIT[1], d.z - ParadeLane.EXIT[2]
		local len = math.max(math.sqrt(dx * dx + dz * dz), 1e-9)
		local hx, hz = dx / len, dz / len
		local lipX, lipZ = d.x - hx * d.lipRadius, d.z - hz * d.lipRadius
		local drain = math.min(ParadeLane.DRAIN_SECONDS, math.max(0, expiresAt - spawnedAt))
		local u = if drain > 0 then math.clamp(1 - (expiresAt - now) / drain, 0, 1) else 1
		local lip = ParadeLane.DRAIN_LIP_SHARE
		local x, y, z
		if u < lip then
			-- hop from the lane end onto the curb lip
			local k = u / lip
			x, z = ex + (lipX - ex) * k, ez + (lipZ - ez) * k
			y = ParadeLane.LANE_Y + (d.lipY - ParadeLane.LANE_Y) * k + math.sin(k * math.pi) * ParadeLane.HOP_HEIGHT
		else
			-- slide down the funnel to the centre and sink below the plaza
			local k = (u - lip) / (1 - lip)
			local ease = k * k
			x, z = lipX + (d.x - lipX) * math.min(1, k * 1.5), lipZ + (d.z - lipZ) * math.min(1, k * 1.5)
			y = d.lipY + (d.sinkY - d.lipY) * ease
		end
		return { position = { x, y, z }, heading = { hx, hz }, phase = phase }
	end
	local s = ParadeLane.distance(spawnedAt, expiresAt, now)
	local _, _, hx, hz = ParadeLane.pointAt(s)
	local x, z = ParadeLane.offsetAt(s, lateral)
	local y = ParadeLane.LANE_Y
	if phase == "Walk" then
		-- A whole number of hops (about HOP_PERIOD each) over the walk, so the
		-- last one lands exactly as the drain slide starts.
		local lifetime = expiresAt - spawnedAt
		local start, stop = ParadeLane.walkWindow(lifetime)
		local walk = (stop - start) * lifetime
		local hops = math.max(1, math.floor(walk / ParadeLane.HOP_PERIOD + 0.5))
		local walked = now - spawnedAt - start * lifetime
		y += math.abs(math.sin(walked / walk * hops * math.pi)) * ParadeLane.HOP_HEIGHT
	end
	return { position = { x, y, z }, heading = { hx, hz }, phase = phase :: Phase }
end

-- On the lane = not carried and never dropped somewhere else.
function ParadeLane.onLane(wild: { position: any? }, carried: boolean): boolean
	return wild.position == nil and not carried
end

function ParadeLane.inWarnWindow(now: number, expiresAt: number, warnSeconds: number?): boolean
	return DespawnTelegraph.inWarnWindow(now, expiresAt, warnSeconds or ParadeLane.WARN_SECONDS)
end

-- Countdown billboard text: "leaving! 3" on the parade, else just "3".
function ParadeLane.warnText(seconds: number, enabled: boolean): string
	return if enabled then `leaving! {seconds}` else tostring(seconds)
end

return table.freeze(ParadeLane)
