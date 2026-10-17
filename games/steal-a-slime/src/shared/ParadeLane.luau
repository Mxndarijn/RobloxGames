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
	  Ride   progress < HOP_SECONDS / lifetime: on the slide (WorldView plays
	         the emerge + slide; it leaves the mouth at HOP_SECONDS)
	  Walk   then walking at once from the slide mouth, through the lead-in
	         to ENTRY and along the lane: LEAD_LENGTH + LENGTH * the share of
	         the walk window gone, linear in time left, ending on the last
	         waypoint
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

	Readability of the despawn telegraph (DespawnTelegraphFx):
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
-- The goo strip is drawn with as few straight Parts as stay within this many studs of the route
-- (stripPoints); the 2.5° route steps are far finer than the eye needs. Visual only.
ParadeLane.STRIP_TOLERANCE = 0.55
ParadeLane.LEAD_TOLERANCE = 0.2 -- the lead-in from the mouth and ENTRY's bend out to r 68 curve hardest: finer, so their corners stay soft
-- Emerge + slide: the slime leaves the slide mouth at FountainRide's slideEndsAt (5.92 s) and walks on at once, no
-- idle wait and no separate glide to the lane (tests/ParadeLane.spec keeps this within 0.25 s above it).
ParadeLane.HOP_SECONDS = 6
ParadeLane.DRAIN_SECONDS = 1.5
ParadeLane.HOP_HEIGHT = 1.2 -- studs at the top of each hop while walking
ParadeLane.HOP_PERIOD = 0.5 / Config.SLIME_MOVE_SPEED_MULT -- seconds per hop (rounded so the walk holds a whole number); slower with the pace
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
	{ 124, 50 }, -- ENTRY: where the ride lands, just past the landing-ring gap, on the mouth's run-out line
	{ 146, 68 },
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
-- Lead-in: from the slide mouth (WorldLayout.SLIDE_PATH end, r 35.5 on +Z) to ENTRY, tangent to the mouth's
-- heading. The goo strip starts here so the lane starts exactly where the slide ends; slimes ride it in the
-- air and land on ENTRY, so the walk (WAYPOINTS) is unchanged.
ParadeLane.MOUTH = table.freeze({ 0, 35.5 })
local LEAD_CONTROLS: { { number } } = { { 90, 35.5 }, { 124, 50 } }
local STEP_DEGREES = 2.5
local BEND_POINTS = math.ceil((CONTROLS[2][1] - CONTROLS[1][1]) / STEP_DEGREES) + 1 -- waypoints of the first control interval
local TAIL: { { number } } = { { 9.5, 61.5 } } -- off r 68 towards the drain's outer (+Z) side

local function polar(controls: { { number } }): { { number } }
	local points: { { number } } = {}
	for k = 1, #controls - 1 do
		local a0, r0 = controls[k][1], controls[k][2]
		local a1, r1 = controls[k + 1][1], controls[k + 1][2]
		local n = math.max(1, math.ceil((a1 - a0) / STEP_DEGREES))
		for i = if k == 1 then 0 else 1, n do
			local u = i / n
			local a = math.rad(a0 + (a1 - a0) * u)
			local r = r0 + (r1 - r0) * (u * u * (3 - 2 * u))
			table.insert(points, { math.cos(a) * r, math.sin(a) * r })
		end
	end
	return points
end

local function build(): { { number } }
	local points = polar(CONTROLS)
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

local lead = polar(LEAD_CONTROLS)
ParadeLane.LEAD = table.freeze(lead) :: { { number } } -- { x, z } from the slide mouth to ENTRY (inclusive)
local points = build()
local cumulative = { 0 }
for i = 2, #points do
	local a, b = points[i - 1], points[i]
	cumulative[i] = cumulative[i - 1] + math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
end
for _, p in points do
	table.freeze(p)
end

-- Walk route: the lead-in from the slide mouth (lead ends on ENTRY), then WAYPOINTS. Walked distance is measured
-- from the mouth; lane distance `s` (0 at ENTRY) is that minus LEAD_LENGTH, so it is negative on the lead-in.
local route: { { number } } = {}
for i = 1, #lead - 1 do
	table.insert(route, lead[i])
end
for _, p in points do
	table.insert(route, p)
end
local routeCumulative = { 0 }
for i = 2, #route do
	local a, b = route[i - 1], route[i]
	routeCumulative[i] = routeCumulative[i - 1] + math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
end
local LEAD_LENGTH = routeCumulative[#lead]
local routeNormals: { { number } } = {}
for i = 1, #route do
	local a, b = route[math.max(1, i - 1)], route[math.min(#route, i + 1)]
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local len = math.max(math.sqrt(dx * dx + dz * dz), 1e-9)
	routeNormals[i] = { -dz / len, dx / len }
end

ParadeLane.WAYPOINTS = table.freeze(points) :: { { number } } -- { x, z }, entry first, drain approach last
ParadeLane.LENGTH = cumulative[#cumulative]
ParadeLane.LEAD_LENGTH = LEAD_LENGTH -- studs from the slide mouth to ENTRY
ParadeLane.ENTRY = points[1]
ParadeLane.EXIT = points[#points]

-- Waypoints the goo strip is drawn through: the route simplified (Douglas-Peucker) so no waypoint
-- is more than STRIP_TOLERANCE studs from the drawn polyline. Entry and exit are kept. { x, z }.
local function simplify(pts: { { number } }, lo: number, hi: number, keep: { boolean }, tolerance: number)
	local ax, az = pts[lo][1], pts[lo][2]
	local dx, dz = pts[hi][1] - ax, pts[hi][2] - az
	local len = math.max(math.sqrt(dx * dx + dz * dz), 1e-9)
	local worst, at = 0, 0
	for i = lo + 1, hi - 1 do
		local d = math.abs((pts[i][1] - ax) * dz - (pts[i][2] - az) * dx) / len
		if d > worst then
			worst, at = d, i
		end
	end
	if worst > tolerance then
		keep[at] = true
		simplify(pts, lo, at, keep, tolerance)
		simplify(pts, at, hi, keep, tolerance)
	end
end

function ParadeLane.stripPoints(): { { number } }
	-- ENTRY's bend out to r 68 (the first control interval) is drawn finer than the long r 68 run.
	local bend = math.min(BEND_POINTS, #points - 1)
	local keep = { [1] = true, [bend] = true, [#points] = true }
	simplify(points, 1, bend, keep, ParadeLane.LEAD_TOLERANCE)
	simplify(points, bend, #points, keep, ParadeLane.STRIP_TOLERANCE)
	local out: { { number } } = {}
	for i = 1, #points do
		if keep[i] then
			table.insert(out, points[i])
		end
	end
	return out
end

-- Waypoints the whole goo strip is drawn through: the slide mouth, the lead-in to ENTRY, then stripPoints()
-- (which starts at ENTRY). { x, z }.
function ParadeLane.drawPoints(): { { number } }
	local full: { { number } } = { ParadeLane.MOUTH }
	for i = 2, #lead - 1 do
		table.insert(full, lead[i])
	end
	local rest = ParadeLane.stripPoints()
	local n = #full
	for _, p in rest do
		table.insert(full, p)
	end
	local keep = { [1] = true, [n + 1] = true, [#full] = true }
	simplify(full, 1, n + 1, keep, ParadeLane.LEAD_TOLERANCE)
	local out: { { number } } = {}
	for i = 1, #full do
		if keep[i] or i > n then
			table.insert(out, full[i])
		end
	end
	return out
end

-- The goo channel ParadeView lays: { name, size = {x, y, z}, cf = CFrame components, length, width }, one
-- Cylinder per segment of drawPoints(), lying along the lane (its X axis). The cylinder is wide (CROWN_RADIUS)
-- and sunk so only its crown shows: the top is LANE_Y on the centreline and falls away to the ground at +-HALF_WIDTH,
-- a soft rounded edge with no step. Each piece is lengthened at a bend by HALF_WIDTH * tan(turn / 2) so the outer
-- edge runs to the mitre point and neighbours meet with no gap; at the small angle steps of the route the two
-- crowns coincide at the joint, so it does not show. `length` x `width` is the footprint on the ground.
ParadeLane.CROWN_RADIUS = (ParadeLane.HALF_WIDTH ^ 2 + ParadeLane.LANE_Y ^ 2) / (2 * ParadeLane.LANE_Y)
-- Every other piece stands STRIP_STEP higher: where two crowns overlap at a joint they would otherwise be the same
-- surface twice and z-fight (bands across the lane); the higher one simply wins, a 0.02 step nobody can see.
ParadeLane.STRIP_STEP = 0.02
-- Extra reach past the mitre at every inner joint, so the cut ends overlap instead of just touching (no hairline).
ParadeLane.JOIN_OVERLAP = 0.1
-- The lane as one mesh (MeshAssets "slime_lane", models/slime_lane.py): the MeshPart's centre (the mesh's bbox
-- centre, world studs; out/slime_lane_pivot.json), laid like a MeshSwap slot (turned MeshAssets.IMPORT_YAW).
-- Its crown is LANE_Y, its edges sit EDGE_Y (under the ground), its width is 2 * HALF_WIDTH.
ParadeLane.MESH = "slime_lane"
ParadeLane.MESH_PIVOT = table.freeze({ 0.321459, 0.135, -1.692511 })
ParadeLane.EDGE_Y = -0.05
ParadeLane.COLOR = table.freeze({ 140, 222, 200 }) -- the slide's water
function ParadeLane.strips(): { any }
	local pts = ParadeLane.drawPoints()
	local hw = ParadeLane.HALF_WIDTH
	local count = #pts - 1
	local ux, uz, len = {}, {}, {}
	for i = 1, count do
		local dx, dz = pts[i + 1][1] - pts[i][1], pts[i + 1][2] - pts[i][2]
		len[i] = math.max(math.sqrt(dx * dx + dz * dz), 1e-9)
		ux[i], uz[i] = dx / len[i], dz / len[i]
	end
	-- Extension of strip i at the vertex shared with strip j.
	local function reach(i: number, j: number): number
		if j < 1 or j > count then
			return 0
		end
		local cos = math.clamp(ux[i] * ux[j] + uz[i] * uz[j], -1, 1)
		return hw * math.tan(math.acos(cos) / 2) + ParadeLane.JOIN_OVERLAP
	end
	local radius = ParadeLane.CROWN_RADIUS
	local out = {}
	for i = 1, count do
		local ea, eb = reach(i, i - 1), reach(i, i + 1)
		local shift = (eb - ea) / 2
		local a, b = pts[i], pts[i + 1]
		local dx, dz = ux[i], uz[i]
		local length = len[i] + ea + eb
		table.insert(out, {
			name = `Lane{i}`,
			size = { length, radius * 2, radius * 2 },
			length = length,
			width = hw * 2,
			cf = {
				(a[1] + b[1]) / 2 + dx * shift,
				ParadeLane.LANE_Y - radius + (if i % 2 == 0 then ParadeLane.STRIP_STEP else 0),
				(a[2] + b[2]) / 2 + dz * shift,
				dx,
				0,
				-dz,
				0,
				1,
				0,
				dz,
				0,
				dx,
			},
		})
	end
	return out
end

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
	if p < start - 1e-9 then -- float slack: now = spawnedAt + HOP_SECONDS is the first Walk instant
		return "Ride"
	elseif p < stop then
		return "Walk"
	end
	return "Drain"
end

-- Studs walked from the slide mouth: 0 until the walk starts, LEAD_LENGTH + LENGTH from the drain slide on.
function ParadeLane.walked(spawnedAt: number, expiresAt: number, now: number): number
	local total = LEAD_LENGTH + ParadeLane.LENGTH
	local p = ParadeLane.progress(spawnedAt, expiresAt, now)
	local start, stop = ParadeLane.walkWindow(expiresAt - spawnedAt)
	if stop <= start then
		return if p >= stop then total else 0
	end
	return total * math.clamp((p - start) / (stop - start), 0, 1)
end

-- Studs along the lane from ENTRY: negative on the lead-in from the slide mouth, LENGTH from the drain slide on.
function ParadeLane.distance(spawnedAt: number, expiresAt: number, now: number): number
	return ParadeLane.walked(spawnedAt, expiresAt, now) - LEAD_LENGTH
end

-- Studs per second a slime walks the lane when it lives `lifetime` seconds.
function ParadeLane.walkSpeed(lifetime: number): number
	local start, stop = ParadeLane.walkWindow(lifetime)
	return (LEAD_LENGTH + ParadeLane.LENGTH) / ((stop - start) * lifetime)
end

-- Route segment holding lane distance `s` (clamped to the lead-in .. LENGTH) and how far along it (0..1).
local function locate(s: number): (number, number, number)
	s = math.clamp(s, -LEAD_LENGTH, ParadeLane.LENGTH) + LEAD_LENGTH
	local lo, hi = 1, #route
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if routeCumulative[mid] <= s then
			lo = mid
		else
			hi = mid
		end
	end
	local span = routeCumulative[hi] - routeCumulative[lo]
	return lo, hi, if span > 1e-9 then (s - routeCumulative[lo]) / span else 0
end

-- Lane point `s` studs from ENTRY (negative: on the lead-in from the slide mouth; clamped) and the unit direction
-- of travel there.
function ParadeLane.pointAt(s: number): (number, number, number, number)
	local lo, hi, k = locate(s)
	local a, b = route[lo], route[hi]
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local len = math.max(math.sqrt(dx * dx + dz * dz), 1e-9)
	return a[1] + dx * k, a[2] + dz * k, dx / len, dz / len
end

-- Point `lateral` studs to the side of the centreline at `s` (along the
-- smoothed normal; positive = the lane's left, the fountain side). Before ENTRY
-- (s < 0, the lead-in) the offset grows from 0 at the slide mouth to `lateral`.
function ParadeLane.offsetAt(s: number, lateral: number): (number, number)
	local lo, hi, k = locate(s)
	local a, b = route[lo], route[hi]
	local na, nb = routeNormals[lo], routeNormals[hi]
	local nx, nz = na[1] + (nb[1] - na[1]) * k, na[2] + (nb[2] - na[2]) * k
	local len = math.max(math.sqrt(nx * nx + nz * nz), 1e-9)
	if s < 0 then -- on the lead-in the offset eases in from the slide mouth's centre to the full offset at ENTRY
		local u = math.clamp(1 + s / LEAD_LENGTH, 0, 1)
		lateral *= u * u * (3 - 2 * u)
	end
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

return table.freeze(ParadeLane)
