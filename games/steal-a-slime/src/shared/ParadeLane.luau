--!strict
--[[
	ParadeLane (pure, FEATURES.Parade)

	The goo parade: how an unclaimed wild slime leaves the plaza. It rides
	the fountain slide (FountainRide) and its run-out lands it on ENTRY, the
	head of a goo lane that loops round the plaza. It glides along the lane at
	a steady pace (no hops; its heading eases through the bends) and, at the
	far end, climbs over the goo drain's curb and sinks in; the server
	removes it at expiresAt with a splash at the drain.

	Lane position is time left. With lifetime = expiresAt - spawnedAt and
	  progress = 1 - (expiresAt - now) / lifetime        (0 at spawn, 1 at expiry)
	the slime is
	  Ride   progress < RIDE_SECONDS / lifetime: on the slide (WorldView plays
	         the emerge + slide; it leaves the mouth at RIDE_SECONDS)
	  Walk   then walking at once from the slide mouth, through the lead-in
	         to ENTRY and along the lane: LEAD_LENGTH + LENGTH * the share of
	         the walk window gone, linear in time left, ending on the last
	         waypoint
	  Drain  the last DRAIN_SECONDS: climb onto the curb lip, slide into the
	         funnel and sink below the plaza (DRAIN.sinkY)
	  Gone   now >= expiresAt (Spawner removes it; DespawnTelegraph.shouldRemove)
	Spawn cadence, cap and lifetimes don't change, and removal is still at
	expiresAt. A slime that is carried, or was dropped somewhere
	(wild.position set), is off the lane. A dropped one walks back
	(returnPlan / returnPose, contract/slime-walk.md): from the drop spot
	towards the nearest lane point, merging onto the lane a little ahead of it
	along a quadratic Bezier, at its own lane pace; rejoin() sets its lane
	times so it carries on from the merge point when it arrives.

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

	Width (halfWidthAt): HALF_WIDTH round the loop, easing smoothly down to
	END_HALF_WIDTH over the last TAPER_LENGTH studs before the goo drain's
	curb, so the lane's end can be cut onto the curb circle (r 4.4). The
	tightest spots for CLEARANCE are the ring path beside the r 68 runs and
	the ~12.4-stud gap between the landing ring and the spawn pad (about 6.2).

	Readability of the despawn telegraph (DespawnTelegraphFx):
	the warning window (DESPAWN_TELEGRAPH_SECONDS) starts while the slime is
	still walking the lane next to the drain (WARN_SECONDS > DRAIN_SECONDS)
	and consecutive drops (SPAWN_INTERVAL apart) are far enough apart on the
	lane that two countdowns never stack.

	No Roblox APIs at load time.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Fountain = if script then require(script.Parent.Fountain) else require("./Fountain")
local DespawnTelegraph = if script then require(script.Parent.DespawnTelegraph) else require("./DespawnTelegraph")

export type Phase = "Ride" | "Walk" | "Drain" | "Gone"
-- A dropped slime's walk back to the lane: a quadratic Bezier (from, nearest lane point, merge point); `s` = lane
-- distance of the merge point, `length` its arc length in studs, `speed` studs / s.
export type Return = {
	fromX: number,
	fromZ: number,
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	s: number,
	startAt: number,
	arriveAt: number,
	speed: number,
	length: number,
}
export type Pose = {
	position: { number }, -- x, y (pivot = slime bottom), z
	heading: { number }, -- unit x, z of travel
	phase: Phase,
}

local ParadeLane = {}

ParadeLane.LANE_RADIUS = 68 -- FOUNTAIN_SIZES goo-parade centreline (PropClearance keeps r 62.25-73.75 clear)
ParadeLane.HALF_WIDTH = 5 -- kit lane incl. edging: 10 studs wide round the loop
ParadeLane.END_HALF_WIDTH = 4.2 -- at the goo drain's curb (r 4.4): narrower, so the end is cut onto the curb circle
ParadeLane.TAPER_LENGTH = 8 -- studs before the curb over which the width eases from HALF_WIDTH to END_HALF_WIDTH
ParadeLane.SPREAD = 4 -- slimes walk up to SPREAD / 2 either side of the centreline (from their Fountain.roll radius)
-- Studs from the outermost walking line to the lane edge: the room a slime's zig-zag hops and sniffs lean into.
ParadeLane.ROOM = ParadeLane.HALF_WIDTH - ParadeLane.SPREAD / 2
ParadeLane.SLIME_RADIUS = Config.SLIME_BASE_DIAMETER * Config.MAX_SIZE / 2 -- the biggest slime
ParadeLane.MARGIN = 1
-- Air from the centreline to any prop: the lane edge or the widest slime, whichever is further, + MARGIN.
ParadeLane.CLEARANCE = math.max(ParadeLane.HALF_WIDTH, ParadeLane.SPREAD / 2 + ParadeLane.SLIME_RADIUS)
	+ ParadeLane.MARGIN
ParadeLane.LANE_Y = 0.35 -- top of the goo strip (ParadeView); slime pivots stand on it
-- The goo strip is drawn with as few straight Parts as stay within this many studs of the route
-- (stripPoints); the 2.5° route steps are far finer than the eye needs. Visual only.
ParadeLane.STRIP_TOLERANCE = 0.12
ParadeLane.LEAD_TOLERANCE = 0.2 -- the lead-in from the mouth and ENTRY's bend out to r 68 curve hardest: finer, so their corners stay soft
-- Emerge + slide: the slime leaves the slide mouth at FountainRide's slideEndsAt (5.92 s) and walks on at once, no
-- idle wait and no separate glide to the lane (tests/ParadeLane.spec keeps this within 0.25 s above it).
ParadeLane.RIDE_SECONDS = 6
ParadeLane.DRAIN_SECONDS = 1.5
ParadeLane.WARN_SECONDS = Config.DESPAWN_TELEGRAPH_SECONDS -- ring warn = despawn telegraph window
-- ranch_goo_drain (WorldLayout Plaza.GooDrain, box centre z 52): the curb
-- ring (r 3.3-4.4, 1 stud tall) sits on the +Z end of the box, its post on
-- the fountain side.
ParadeLane.DRAIN = table.freeze({ x = 0, z = 52.5, lipRadius = 4.4, lipY = 1, sinkY = -3 })
ParadeLane.DRAIN_LIP_SHARE = 0.4 -- share of DRAIN_SECONDS spent climbing onto the lip
-- The return walk of a dropped slime (contract/slime-walk.md).
ParadeLane.RETURN_DELAY = 0.6 -- seconds from the drop to the first step (it falls out of the carrier's arms first)
ParadeLane.RETURN_EASE = 0.8 -- seconds to speed up from a stand to its lane pace
ParadeLane.RETURN_MERGE = 8 -- studs past the nearest lane point where it merges onto the lane (at most half the walk)
ParadeLane.RETURN_SAMPLES = 24 -- Bezier chords for its arc length
-- Farther than this from the lane is off the map (the ground is 640 x 640 round the fountain, its corners ~385 studs
-- from the lane): no walk, it goes back to its fountain spot like any drop over the void (CONTRACT.md §8.11).
ParadeLane.RETURN_MAX_GAP = 400

-- Lane route as (wild angle in degrees, radius) controls; radii ease
-- (smoothstep) between neighbours. Angles grow counter-clockwise from the
-- entry at 112.5° to 430° (= 70°) beside the drain.
local CONTROLS: { { number } } = {
	{ 124, 50 }, -- ENTRY: where the ride lands, just past the landing-ring gap, on the mouth's run-out line
	{ 146, 68 },
	{ 170, 68 },
	{ 186, 50.3 }, -- between the landing ring and the hub SpawnLocation (12 x 12 at r 64, 202.5°), centred in the gap between them
	{ 219, 50.3 },
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
local MOUTH_HEADING = { -0.9806, 0.1961 } -- unit x, z the slide leaves the mouth in (WorldLayout.SLIDE_PATH's last segment)
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

-- Raw route (the radius-eased arcs above): the lead-in, the lane, TAIL and the last waypoint just outside the drain's curb.
local function rawRoute(): { { number } }
	local points = polar(LEAD_CONTROLS)
	for i, p in polar(CONTROLS) do
		if i > 1 then
			table.insert(points, p)
		end
	end
	for _, p in TAIL do
		table.insert(points, { p[1], p[2] })
	end
	local d = ParadeLane.DRAIN
	local last = points[#points]
	local dx, dz = last[1] - d.x, last[2] - d.z
	local len = math.sqrt(dx * dx + dz * dz)
	local out = d.lipRadius + ParadeLane.SLIME_RADIUS
	table.insert(points, { d.x + dx / len * out, d.z + dz / len * out })
	return points
end

-- The raw route's corners (the radius eases and the tail) are too sharp for a slime to turn, and a goo mesh through them
-- shows a kink. Resample it every 1 stud, smooth it with a Gaussian of SMOOTH_SIGMA studs (the slide mouth keeps its heading and
-- position, the drain end is point-reflected so it stays put) and keep every POINT_SPACING studs. The walkers and the
-- mesh centreline (tools/render/lane_centreline) use these same points.
local SMOOTH_SIGMA = 5
local POINT_SPACING = 2
local MOUTH_BLEND = 8
local function smoothRoute(raw: { { number } }): { { number } }
	local dense: { { number } } = { { raw[1][1], raw[1][2] } }
	local carry = 0
	for i = 2, #raw do
		local a, b = raw[i - 1], raw[i]
		local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local at = 1 - carry
		while at <= len do
			table.insert(dense, { a[1] + (b[1] - a[1]) * at / len, a[2] + (b[2] - a[2]) * at / len })
			at += 1
		end
		carry = len - (at - 1)
	end
	local tailEnd = raw[#raw]
	local n = #dense
	local gap = math.sqrt((tailEnd[1] - dense[n][1]) ^ 2 + (tailEnd[2] - dense[n][2]) ^ 2)
	if gap > 1e-6 then
		n += 1
		dense[n] = { tailEnd[1], tailEnd[2] }
	end
	local reach = math.ceil(SMOOTH_SIGMA * 3)
	local weights: { number } = {}
	local total = 0
	for k = -reach, reach do
		local w = math.exp(-(k * k) / (2 * SMOOTH_SIGMA * SMOOTH_SIGMA))
		weights[k + reach + 1] = w
		total += w
	end
	local function at(i: number): (number, number)
		if i < 1 then -- the slide's heading carries on straight back from the mouth
			return dense[1][1] + (i - 1) * MOUTH_HEADING[1], dense[1][2] + (i - 1) * MOUTH_HEADING[2]
		elseif i > n then -- point reflection about the last point
			local j = math.max(2 * n - i, 1)
			return 2 * dense[n][1] - dense[j][1], 2 * dense[n][2] - dense[j][2]
		end
		return dense[i][1], dense[i][2]
	end
	local smooth: { { number } } = {}
	for i = 1, n do
		local sx, sz = 0, 0
		for k = -reach, reach do
			local x, z = at(i + k)
			local w = weights[k + reach + 1]
			sx += x * w
			sz += z * w
		end
		smooth[i] = { sx / total, sz / total }
	end
	-- The raw lead-in is already gentle and starts on the slide's line: the smoothing fades in over MOUTH_BLEND studs.
	for i = 1, math.min(n, MOUTH_BLEND) do
		local u = (i - 1) / MOUTH_BLEND
		local w = u * u * (3 - 2 * u)
		smooth[i] = { dense[i][1] + (smooth[i][1] - dense[i][1]) * w, dense[i][2] + (smooth[i][2] - dense[i][2]) * w }
	end
	-- the chords of a smoothed 1-stud polyline are about 1 stud: keep every POINT_SPACING-th and the last
	local out: { { number } } = {}
	for i = 1, n, POINT_SPACING do
		table.insert(out, smooth[i])
	end
	if (n - 1) % POINT_SPACING ~= 0 then
		table.insert(out, smooth[n])
	end
	return out
end

local smoothed = smoothRoute(rawRoute())
-- ENTRY: the smoothed point nearest where the ride lands (the raw ENTRY).
local rawEntry = polar(LEAD_CONTROLS)[#polar(LEAD_CONTROLS)]
local entryIndex, entryGap = 1, math.huge
for i, p in smoothed do
	local g = (p[1] - rawEntry[1]) ^ 2 + (p[2] - rawEntry[2]) ^ 2
	if g < entryGap then
		entryIndex, entryGap = i, g
	end
end
local lead: { { number } } = {}
for i = 1, entryIndex do
	table.insert(lead, smoothed[i])
end
ParadeLane.LEAD = table.freeze(lead) :: { { number } } -- { x, z } from the slide mouth to ENTRY (inclusive)
local points: { { number } } = {}
for i = entryIndex, #smoothed do
	table.insert(points, smoothed[i])
end
local cumulative = { 0 }
for i = 2, #points do
	local a, b = points[i - 1], points[i]
	cumulative[i] = cumulative[i - 1] + math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
end
for _, p in smoothed do
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
local routeTangents: { { number } } = {}
for i = 1, #route do
	local a, b = route[math.max(1, i - 1)], route[math.min(#route, i + 1)]
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local len = math.max(math.sqrt(dx * dx + dz * dz), 1e-9)
	routeNormals[i] = { -dz / len, dx / len }
	routeTangents[i] = { dx / len, dz / len }
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

-- Half width of the lane at (x, z): HALF_WIDTH, easing (smoothstep) down to END_HALF_WIDTH over the last
-- TAPER_LENGTH studs before the goo drain's curb (ParadeLane.DRAIN, lipRadius). The mesh (models/slime_lane.py, from
-- tools/render/lane_centreline) uses the same rule.
function ParadeLane.halfWidthAt(x: number, z: number): number
	local d = ParadeLane.DRAIN
	local gap = math.sqrt((x - d.x) ^ 2 + (z - d.z) ^ 2) - d.lipRadius
	local u = math.clamp(gap / ParadeLane.TAPER_LENGTH, 0, 1)
	return ParadeLane.END_HALF_WIDTH + (ParadeLane.HALF_WIDTH - ParadeLane.END_HALF_WIDTH) * (u * u * (3 - 2 * u))
end

-- The goo channel ParadeView lays: { name, size = {x, y, z}, cf = CFrame components, length, width }, one
-- Cylinder per segment of drawPoints(), lying along the lane (its X axis). The cylinder is wide (crownRadius)
-- and sunk so only its crown shows: the top is LANE_Y on the centreline and falls away to the ground at +-its half
-- width, a soft rounded edge with no step. Each piece is lengthened at a bend by its half width * tan(turn / 2) so the
-- outer edge runs to the mitre point and neighbours meet with no gap; at the small angle steps of the route the two
-- crowns coincide at the joint, so it does not show. In the taper before the drain the segments are cut into
-- pieces of TAPER_PIECE studs or more, each as wide as halfWidthAt its middle. `length` x `width` is the footprint on the ground.
function ParadeLane.crownRadius(halfWidth: number): number
	return (halfWidth ^ 2 + ParadeLane.LANE_Y ^ 2) / (2 * ParadeLane.LANE_Y)
end
ParadeLane.CROWN_RADIUS = ParadeLane.crownRadius(ParadeLane.HALF_WIDTH)
ParadeLane.TAPER_PIECE = 2
-- Every other piece stands STRIP_STEP higher: where two crowns overlap at a joint they would otherwise be the same
-- surface twice and z-fight (bands across the lane); the higher one simply wins, a 0.02 step nobody can see.
ParadeLane.STRIP_STEP = 0.02
-- Extra reach past the mitre at every inner joint, so the cut ends overlap instead of just touching (no hairline).
ParadeLane.JOIN_OVERLAP = 0.1
-- The lane as one mesh (MeshAssets "slime_lane", models/slime_lane.py): the MeshPart's centre (the mesh's bbox
-- centre, world studs; out/slime_lane_pivot.json), laid like a MeshSwap slot (turned MeshAssets.IMPORT_YAW).
-- Its crown is LANE_Y, its edges sit EDGE_Y (under the ground), its width is 2 * halfWidthAt.
ParadeLane.MESH = "slime_lane"
ParadeLane.MESH_PIVOT = table.freeze({ 0.46311, 0.135, -1.711067 })
ParadeLane.EDGE_Y = -0.05
ParadeLane.COLOR = table.freeze({ 140, 222, 200 }) -- the slide's water

-- drawPoints() with the segments in the taper cut into pieces of TAPER_PIECE studs or more.
local function stripPointsTapered(): { { number } }
	local pts = ParadeLane.drawPoints()
	local out: { { number } } = { pts[1] }
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local mx, mz = (a[1] + b[1]) / 2, (a[2] + b[2]) / 2
		local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local d = ParadeLane.DRAIN
		local near = math.sqrt((mx - d.x) ^ 2 + (mz - d.z) ^ 2) - d.lipRadius - len / 2 < ParadeLane.TAPER_LENGTH
		local n = if near then math.max(1, math.floor(len / ParadeLane.TAPER_PIECE)) else 1
		for k = 1, n do
			local u = k / n
			table.insert(out, { a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u })
		end
	end
	return out
end

function ParadeLane.strips(): { any }
	local pts = stripPointsTapered()
	local count = #pts - 1
	local ux, uz, len, hw = {}, {}, {}, {}
	for i = 1, count do
		local dx, dz = pts[i + 1][1] - pts[i][1], pts[i + 1][2] - pts[i][2]
		len[i] = math.max(math.sqrt(dx * dx + dz * dz), 1e-9)
		ux[i], uz[i] = dx / len[i], dz / len[i]
		hw[i] = ParadeLane.halfWidthAt((pts[i][1] + pts[i + 1][1]) / 2, (pts[i][2] + pts[i + 1][2]) / 2)
	end
	-- Extension of strip i at the vertex shared with strip j.
	local function reach(i: number, j: number): number
		if j < 1 or j > count then
			return 0
		end
		local cos = math.clamp(ux[i] * ux[j] + uz[i] * uz[j], -1, 1)
		return hw[i] * math.tan(math.acos(cos) / 2) + ParadeLane.JOIN_OVERLAP
	end
	local out = {}
	for i = 1, count do
		local ea, eb = reach(i, i - 1), reach(i, i + 1)
		local shift = (eb - ea) / 2
		local a, b = pts[i], pts[i + 1]
		local dx, dz = ux[i], uz[i]
		local length = len[i] + ea + eb
		local radius = ParadeLane.crownRadius(hw[i])
		table.insert(out, {
			name = `Lane{i}`,
			size = { length, radius * 2, radius * 2 },
			length = length,
			width = hw[i] * 2,
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
	local ride = math.min(ParadeLane.RIDE_SECONDS, lifetime)
	local drain = math.min(ParadeLane.DRAIN_SECONDS, lifetime - ride)
	return ride / lifetime, 1 - drain / lifetime
end

function ParadeLane.phase(spawnedAt: number, expiresAt: number, now: number): Phase
	if now >= expiresAt then
		return "Gone"
	end
	local p = ParadeLane.progress(spawnedAt, expiresAt, now)
	local start, stop = ParadeLane.walkWindow(expiresAt - spawnedAt)
	if p < start - 1e-9 then -- float slack: now = spawnedAt + RIDE_SECONDS is the first Walk instant
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

-- The walk of a slime on the lane (ParadeChoreo times): server time it leaves the slide mouth, seconds it walks
-- (mouth to drain curb) and seconds of that on the lead-in to ENTRY.
function ParadeLane.walkTimes(spawnedAt: number, expiresAt: number): (number, number, number)
	local lifetime = expiresAt - spawnedAt
	local start, stop = ParadeLane.walkWindow(lifetime)
	local seconds = (stop - start) * lifetime
	local total = LEAD_LENGTH + ParadeLane.LENGTH
	return spawnedAt + start * lifetime, seconds, if total > 0 then seconds * LEAD_LENGTH / total else 0
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
-- of travel there: the tangents at the two waypoints blended, so a walker turns smoothly through a bend instead of
-- snapping at each waypoint.
function ParadeLane.pointAt(s: number): (number, number, number, number)
	local lo, hi, k = locate(s)
	local a, b = route[lo], route[hi]
	local ta, tb = routeTangents[lo], routeTangents[hi]
	local hx, hz = ta[1] + (tb[1] - ta[1]) * k, ta[2] + (tb[2] - ta[2]) * k
	local len = math.max(math.sqrt(hx * hx + hz * hz), 1e-9)
	return a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, hx / len, hz / len
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

-- Full pose of a lane slime at `now`. `ahead` (FEATURES.SlimeChoreo, ParadeChoreo) moves its walk that many studs
-- ahead of the plain spot (negative: behind), clamped to the lane.
function ParadeLane.pose(spawnedAt: number, expiresAt: number, lateral: number, now: number, ahead: number?): Pose
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
			-- climb from the lane end onto the curb lip
			local k = u / lip
			x, z = ex + (lipX - ex) * k, ez + (lipZ - ez) * k
			y = ParadeLane.LANE_Y + (d.lipY - ParadeLane.LANE_Y) * (k * k * (3 - 2 * k))
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
	if ahead then
		s = math.clamp(s + ahead, -LEAD_LENGTH, ParadeLane.LENGTH)
	end
	local _, _, hx, hz = ParadeLane.pointAt(s)
	local x, z = ParadeLane.offsetAt(s, lateral)
	return { position = { x, ParadeLane.LANE_Y, z }, heading = { hx, hz }, phase = phase :: Phase }
end

-- Lane distance (0..LENGTH, never the lead-in) of the centreline point nearest (x, z), and how far away it is.
function ParadeLane.nearest(x: number, z: number): (number, number)
	local bestS, best = 0, math.huge
	for i = #lead, #route - 1 do
		local a, b = route[i], route[i + 1]
		local dx, dz = b[1] - a[1], b[2] - a[2]
		local len2 = dx * dx + dz * dz
		local k = if len2 > 1e-12 then math.clamp(((x - a[1]) * dx + (z - a[2]) * dz) / len2, 0, 1) else 0
		local px, pz = a[1] + dx * k, a[2] + dz * k
		local d = (x - px) ^ 2 + (z - pz) ^ 2
		if d < best then
			best = d
			bestS = routeCumulative[i] + (routeCumulative[i + 1] - routeCumulative[i]) * k - LEAD_LENGTH
		end
	end
	return math.clamp(bestS, 0, ParadeLane.LENGTH), math.sqrt(best)
end

-- Sideways lane offset of a wild slime from its Fountain.roll radius.
function ParadeLane.wildLateral(radius: number): number
	return ParadeLane.lateral(radius, Fountain.MIN_RADIUS, Fountain.MAX_RADIUS)
end

-- Lane times that put a slime living `lifetime` seconds at lane distance `s` at time `at`: (spawnedAt, expiresAt).
function ParadeLane.rejoin(s: number, lifetime: number, at: number): (number, number)
	local start, stop = ParadeLane.walkWindow(lifetime)
	local share = (math.clamp(s, 0, ParadeLane.LENGTH) + LEAD_LENGTH) / (LEAD_LENGTH + ParadeLane.LENGTH)
	local spawnedAt = at - (start + share * (stop - start)) * lifetime
	return spawnedAt, spawnedAt + lifetime
end

local function bezier(plan: Return, u: number): (number, number)
	local a, b, c = (1 - u) * (1 - u), 2 * (1 - u) * u, u * u
	return a * plan.fromX + b * plan.x1 + c * plan.x2, a * plan.fromZ + b * plan.z1 + c * plan.z2
end

-- Bezier parameter `want` studs along the curve (the same RETURN_SAMPLES chords that measure its length).
local function bezierAt(plan: Return, want: number): number
	local walked = 0
	local px, pz = plan.fromX, plan.fromZ
	for i = 1, ParadeLane.RETURN_SAMPLES do
		local x, z = bezier(plan, i / ParadeLane.RETURN_SAMPLES)
		local chord = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
		if walked + chord >= want then
			local k = if chord > 1e-9 then (want - walked) / chord else 0
			return (i - 1 + k) / ParadeLane.RETURN_SAMPLES
		end
		walked += chord
		px, pz = x, z
	end
	return 1
end

local function bezierLength(plan: Return): number
	local length = 0
	local px, pz = plan.fromX, plan.fromZ
	for i = 1, ParadeLane.RETURN_SAMPLES do
		local x, z = bezier(plan, i / ParadeLane.RETURN_SAMPLES)
		length += math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
		px, pz = x, z
	end
	return length
end

-- Studs walked `t` seconds after the first step: speeding up over RETURN_EASE, then `speed`.
function ParadeLane.returnTravelled(t: number, speed: number): number
	local ease = ParadeLane.RETURN_EASE
	if t <= 0 then
		return 0
	elseif t < ease then
		return speed * t * t / (2 * ease)
	end
	return speed * (t - ease / 2)
end

-- Seconds from the first step to the end of a `length`-stud walk (returnTravelled's inverse).
local function walkSeconds(length: number, speed: number): number
	local ease = ParadeLane.RETURN_EASE
	if length <= speed * ease / 2 then
		return math.sqrt(2 * ease * length / speed)
	end
	return length / speed + ease / 2
end

-- The walk back to the lane of a slime living `lifetime` seconds, dropped at world (x, z) at `now` (fountain axis
-- at the origin, like the route). nil when the spot is more than RETURN_MAX_GAP from the lane.
function ParadeLane.returnPlan(x: number, z: number, lateral: number, lifetime: number, now: number): Return?
	local fromX, fromZ = Fountain.clearOfRing(x, z)
	local near, away = ParadeLane.nearest(fromX, fromZ)
	if away > ParadeLane.RETURN_MAX_GAP then
		return nil
	end
	local x1, z1 = ParadeLane.offsetAt(near, lateral)
	local gap = math.sqrt((x1 - fromX) ^ 2 + (z1 - fromZ) ^ 2)
	local s = math.min(near + math.min(ParadeLane.RETURN_MERGE, gap / 2), ParadeLane.LENGTH)
	local x2, z2 = ParadeLane.offsetAt(s, lateral)
	local speed = ParadeLane.walkSpeed(lifetime)
	local plan: Return = {
		fromX = fromX,
		fromZ = fromZ,
		x1 = x1,
		z1 = z1,
		x2 = x2,
		z2 = z2,
		s = s,
		startAt = now + ParadeLane.RETURN_DELAY,
		arriveAt = 0,
		speed = speed,
		length = 0,
	}
	plan.length = bezierLength(plan)
	plan.arriveAt = plan.startAt + walkSeconds(plan.length, speed)
	return plan
end

-- Spot (x, z) and unit heading (hx, hz) of a returning slime at `now`: at the start until startAt, on the merge
-- point from arriveAt on. The heading is the curve's tangent (the lane's where the curve has none).
function ParadeLane.returnPose(plan: Return, now: number): (number, number, number, number)
	local want = ParadeLane.returnTravelled(now - plan.startAt, plan.speed)
	local u = if want < plan.length then bezierAt(plan, want) else 1
	local x, z = bezier(plan, u)
	local hx = 2 * (1 - u) * (plan.x1 - plan.fromX) + 2 * u * (plan.x2 - plan.x1)
	local hz = 2 * (1 - u) * (plan.z1 - plan.fromZ) + 2 * u * (plan.z2 - plan.z1)
	local len = math.sqrt(hx * hx + hz * hz)
	if len < 1e-6 then
		local _, _, lx, lz = ParadeLane.pointAt(plan.s)
		return x, z, lx, lz
	end
	return x, z, hx / len, hz / len
end

-- On the lane = not carried and never dropped somewhere else.
function ParadeLane.onLane(wild: { position: any? }, carried: boolean): boolean
	return wild.position == nil and not carried
end

function ParadeLane.inWarnWindow(now: number, expiresAt: number, warnSeconds: number?): boolean
	return DespawnTelegraph.inWarnWindow(now, expiresAt, warnSeconds or ParadeLane.WARN_SECONDS)
end

return table.freeze(ParadeLane)
