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
ParadeLane.STRIP_TOLERANCE = 0.1
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
	{ 186, 49.8 }, -- inside the hub SpawnLocation (12 x 12 at r 64, 202.5°)
	{ 219, 49.8 },
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
ParadeLane.MESH_PIVOT = table.freeze({ 0.472784, 0.135, -1.707947 })
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

-- The drain mouth: the lane does not stop at the curb. Its LAST segment (the same Cylinder-crown strips as the lane,
-- same width where it leaves EXIT, same ~2 stud segment density, mitred and overlapped the same way) bends on from
-- EXIT's heading onto the radial line through the nearest GAP between two warning tiles, narrowing smoothly to FUNNEL_HALF_WIDTH,
-- and ends against the curb wall. The POUR is a thin tapered lip of a few slightly tilted slabs that rides that gap line over the curb
-- (between two tiles; it only overlaps the tiles' edges) and drops into the basin water. Visual only, drawn in every
-- mode (the uploaded lane mesh ends at EXIT).
ParadeLane.GRATE_RADIUS = 1.3 -- brass grate hoop (ranch_goo_drain Hoop r 1.15 + a hair)
ParadeLane.RIM_TILE_GAP_DEGREES = 30 -- the 12 warning tiles (ranch_goo_drain Warn0-11) meet every 30 degrees, a 4 degree gap
ParadeLane.POUR_START_RADIUS = 5.6 -- the funnelled lane ends just outside the curb (r 4.4) and the pour begins here
ParadeLane.POUR_END_RADIUS = 2.6 -- the pour ends this far from the drain's centre: inside the rim, outside the grate
ParadeLane.POUR_CROWN_Y = 1.34 -- over the curb (1.0) and its warning tiles (1.22)
ParadeLane.POUR_DIP_Y = 0.72 -- the pour's end, down in the basin water
ParadeLane.POUR_HALF_WIDTH = 0.6 -- a ribbon about 1.2 studs wide: the rim tile gap is 0.3, so it only laps the tiles' edges
ParadeLane.FUNNEL_HALF_WIDTH = 2.2 -- the lane eases in to this width where it meets the curb
ParadeLane.POUR_STEPS = 20
ParadeLane.POUR_THICKNESS = 0.25
ParadeLane.POUR_OVERLAP = 0.04
ParadeLane.DRAIN_BLEND_STEPS = 4 -- lane-extension segments between EXIT and POUR_START_RADIUS

local function smoothstep(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

-- Angle (radians, Roblox x / z about the drain's centre) of the tile gap the pour rides: the one nearest EXIT.
function ParadeLane.pourAngle(): number
	local d, e = ParadeLane.DRAIN, ParadeLane.EXIT
	local step = math.rad(ParadeLane.RIM_TILE_GAP_DEGREES)
	return math.floor(math.atan2(e[2] - d.z, e[1] - d.x) / step + 0.5) * step
end

local function onGap(r: number): (number, number)
	local d, a = ParadeLane.DRAIN, ParadeLane.pourAngle()
	return d.x + math.cos(a) * r, d.z + math.sin(a) * r
end

-- { x, z, halfWidth } from EXIT (full lane width) to where the pour begins: a cubic Hermite off EXIT's heading onto
-- the gap line (heading straight at the drain), the width easing down.
function ParadeLane.drainLanePoints(): { { number } }
	local d, pts = ParadeLane.DRAIN, ParadeLane.WAYPOINTS
	local e, before = pts[#pts], pts[#pts - 1]
	local hx, hz = e[1] - before[1], e[2] - before[2]
	local hl = math.sqrt(hx * hx + hz * hz)
	hx, hz = hx / hl, hz / hl
	local tx, tz = onGap(ParadeLane.POUR_START_RADIUS)
	local ex, ez = d.x - tx, d.z - tz -- end heading: straight at the drain's centre
	local el = math.sqrt(ex * ex + ez * ez)
	ex, ez = ex / el, ez / el
	local span = math.sqrt((tx - e[1]) ^ 2 + (tz - e[2]) ^ 2)
	local out = {}
	local n = ParadeLane.DRAIN_BLEND_STEPS
	for i = 0, n do
		local u = i / n
		local h00, h10 = 2 * u ^ 3 - 3 * u ^ 2 + 1, u ^ 3 - 2 * u ^ 2 + u
		local h01, h11 = -2 * u ^ 3 + 3 * u ^ 2, u ^ 3 - u ^ 2
		local x = h00 * e[1] + h10 * span * hx + h01 * tx + h11 * span * ex
		local z = h00 * e[2] + h10 * span * hz + h01 * tz + h11 * span * ez
		local hw = ParadeLane.HALF_WIDTH + (ParadeLane.FUNNEL_HALF_WIDTH - ParadeLane.HALF_WIDTH) * smoothstep(u)
		table.insert(out, { x, z, hw })
	end
	return out
end

-- The lane's goo carried on to the pour: the same Cylinder crown strips as strips() (own crown radius per width).
local function laneExtension(): { any }
	local pts = ParadeLane.drainLanePoints()
	local main = ParadeLane.drawPoints()
	local count = #pts - 1
	local ux, uz, len = {}, {}, {}
	for i = 1, count do
		local dx, dz = pts[i + 1][1] - pts[i][1], pts[i + 1][2] - pts[i][2]
		len[i] = math.max(math.sqrt(dx * dx + dz * dz), 1e-9)
		ux[i], uz[i] = dx / len[i], dz / len[i]
	end
	local px, pz = main[#main][1] - main[#main - 1][1], main[#main][2] - main[#main - 1][2]
	local pl = math.max(math.sqrt(px * px + pz * pz), 1e-9)
	ux[0], uz[0] = px / pl, pz / pl
	local function reach(i: number, j: number, hw: number): number
		if j > count then
			return 0
		end
		local cos = math.clamp(ux[i] * ux[j] + uz[i] * uz[j], -1, 1)
		return hw * math.tan(math.acos(cos) / 2) + ParadeLane.JOIN_OVERLAP
	end
	local out = {}
	for i = 1, count do
		local hw = math.max(pts[i][3], pts[i + 1][3])
		local radius = (hw ^ 2 + ParadeLane.LANE_Y ^ 2) / (2 * ParadeLane.LANE_Y)
		local ea, eb = reach(i, i - 1, hw), reach(i, i + 1, hw)
		if i == count then
			eb = ParadeLane.JOIN_OVERLAP -- the pour's first slab lies over this end
		end
		local shift = (eb - ea) / 2
		local a, b = pts[i], pts[i + 1]
		local dx, dz = ux[i], uz[i]
		local length = len[i] + ea + eb
		table.insert(out, {
			name = `LaneDrain{i}`,
			size = { length, radius * 2, radius * 2 },
			length = length,
			width = hw * 2,
			cf = {
				(a[1] + b[1]) / 2 + dx * shift,
				ParadeLane.LANE_Y - radius + (if i % 2 == 1 then ParadeLane.STRIP_STEP else 0),
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

-- { x, y, z, halfWidth } along the gap line from POUR_START_RADIUS (on the lane) over the curb into the basin.
function ParadeLane.pourPoints(): { { number } }
	local r0, r1 = ParadeLane.POUR_START_RADIUS, ParadeLane.POUR_END_RADIUS
	local lane, crown, dip = ParadeLane.LANE_Y, ParadeLane.POUR_CROWN_Y, ParadeLane.POUR_DIP_Y
	local out = {}
	for i = 0, ParadeLane.POUR_STEPS do
		local t = i / ParadeLane.POUR_STEPS
		local r = r0 + (r1 - r0) * t
		-- up onto the curb from the lane's end, over its top, then down into the basin from r 3.5 on
		local y = lane + (crown - lane) * smoothstep((r0 - r) / (r0 - 4.1))
		y -= (crown - dip) * smoothstep((3.5 - r) / 0.9)
		local x, z = onGap(r)
		table.insert(out, { x, y, z, ParadeLane.POUR_HALF_WIDTH })
	end
	return out
end

-- Up axis of a cylinder lying along t = (tx, ty, tz) with horizontal side s = (sx, 0, sz): s x t.
local function upAxis(sx: number, sz: number, tx: number, ty: number, tz: number): (number, number, number)
	return -sz * ty, sz * tx - sx * tz, sx * ty
end

-- The pour's thin tilted slabs along pourPoints(): Block Parts (no cylinder end caps to poke out over the curb), each
-- overlapping its neighbours, each a hair above the last so overlaps do not z-fight. Same cf layout as strips().
function ParadeLane.pourStrips(): { any }
	local pts = ParadeLane.pourPoints()
	local out = {}
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local tx, ty, tz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
		local len = math.sqrt(tx * tx + ty * ty + tz * tz)
		tx, ty, tz = tx / len, ty / len, tz / len
		local hl = math.sqrt(tx * tx + tz * tz)
		local sx, sz = -tz / hl, tx / hl -- horizontal side, Z axis of the block
		local ux, uy, uz = upAxis(sx, sz, tx, ty, tz)
		local hw = (a[4] + b[4]) / 2
		local thick = ParadeLane.POUR_THICKNESS
		local length = len + ParadeLane.POUR_OVERLAP * 2
		local mx, my, mz = (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2
		table.insert(out, {
			name = `Pour{i}`,
			shape = "Block",
			size = { length, thick, hw * 2 },
			length = length,
			width = hw * 2,
			cf = {
				mx - ux * thick / 2,
				my - uy * thick / 2 + i * 0.001,
				mz - uz * thick / 2,
				tx,
				ux,
				sx,
				ty,
				uy,
				0,
				tz,
				uz,
				sz,
			},
		})
	end
	return out
end

-- Everything ParadeView lays in Plaza.DrainMouth: the lane's last segments, then the pour.
function ParadeLane.drainStrips(): { any }
	local out = laneExtension()
	for _, s in ParadeLane.pourStrips() do
		table.insert(out, s)
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
