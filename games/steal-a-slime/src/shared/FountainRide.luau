--!strict
--[[
	FountainRide (pure)

	The whole trip a fresh wild slime makes out of the fountain, as a timed
	polyline WorldView plays back on the anchored model:

	  Emerge  rises EMERGE_DEPTH studs out of the goo crown to the slide head;
	  Slide   follows the slide path (WorldLayout.SLIDE_PATH) waypoint by
	          waypoint, speeding up from SLIDE_START_SPEED to SLIDE_SPEED;
	  Run     shoots EXIT_RUN studs straight out of the mouth (through the
	          splash pool), slows to RUN_SPEED and walks round the fountain to
	          its landing, eased to a stop on the plaza.

	The run never crosses the low slide or its posts: every point stays
	FOOTPRINT studs (slide lip + the biggest slime) from the low slide's
	centreline, pushed out along its ray from the fountain axis when the
	plain curl would cut through. It takes the shorter way round. Landings
	inside that footprint move out the same way (clearLanding).

	Positions are { x, y, z } with the fountain axis at the origin (as
	SLIDE_PATH). The path is passed in, so this module stays free of Roblox
	APIs and of the Visuals tree.
]]

export type Vec = { number }
export type Phase = "Emerge" | "Slide" | "Run" | "Done"

export type Ride = {
	points: { Vec },
	times: { number },
	phases: { Phase },
	landing: Vec,
	duration: number,
	emergeSeconds: number,
	slideEndsAt: number, -- time the slime leaves the mouth
	slideLength: number,
	runLength: number,
}

local FountainRide = {}

FountainRide.EMERGE_DEPTH = 3 -- studs below the slide head the slime starts (inside the goo crown)
FountainRide.EMERGE_SECONDS = 0.6
FountainRide.SLIDE_START_SPEED = 8 -- studs/s at the head
FountainRide.SLIDE_ACCEL = 40 -- studs/s^2 until SLIDE_SPEED
FountainRide.SLIDE_SPEED = 48 -- studs/s: the 235-stud slide takes ~5 s
FountainRide.RUN_DECEL = 60 -- studs/s^2 from SLIDE_SPEED down to RUN_SPEED
FountainRide.RUN_SPEED = 20 -- studs/s walking round the plaza
FountainRide.STOP_DISTANCE = 3 -- studs over which it eases to a stop
FountainRide.MIN_SPEED = 2 -- floor of the stop ease, so the ride always ends
FountainRide.EXIT_RUN = 9 -- studs straight out of the mouth before it curls
FountainRide.LOW_SLIDE_Y = 10 -- slide segments at or below this are on posts near the ground
-- Slide lip half-width 3.5, 20 % wider at the mouth, plus the biggest slime
-- (SLIME_BASE_DIAMETER 3 x MAX_SIZE 2, half of it).
FountainRide.FOOTPRINT = 3.5 * 1.2 + 3
FountainRide.STEP = 0.5 -- studs between ride samples

local function v3(x: number, y: number, z: number): Vec
	return { x, y, z }
end

local function dist(a: Vec, b: Vec): number
	return math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
end

local function dist2(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
end

-- Horizontal distance from (x, z) to segment a-b.
local function segmentDistance(x: number, z: number, a: Vec, b: Vec): number
	local dx, dz = b[1] - a[1], b[3] - a[3]
	local len2 = dx * dx + dz * dz
	local k = if len2 < 1e-9 then 0 else math.clamp(((x - a[1]) * dx + (z - a[3]) * dz) / len2, 0, 1)
	return dist2(x, z, a[1] + dx * k, a[3] + dz * k)
end

-- Horizontal distance from (x, z) to the low part of the slide's centreline.
function FountainRide.clearance(path: { Vec }, x: number, z: number): number
	local best = math.huge
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		if math.min(a[2], b[2]) <= FountainRide.LOW_SLIDE_Y then
			best = math.min(best, segmentDistance(x, z, a, b))
		end
	end
	return best
end

-- Smallest radius >= r on the ray at `angle` that keeps FOOTPRINT from the low slide.
local function clearRadius(path: { Vec }, angle: number, r: number): number
	local c, s = math.cos(angle), math.sin(angle)
	local probe = r
	for _ = 1, 400 do
		if FountainRide.clearance(path, c * probe, s * probe) >= FountainRide.FOOTPRINT then
			return probe
		end
		probe += 0.1
	end
	return probe
end

-- (x, z) moved straight out from the fountain axis until it is clear of the low slide.
function FountainRide.clearLanding(path: { Vec }, x: number, z: number): (number, number)
	if FountainRide.clearance(path, x, z) >= FountainRide.FOOTPRINT then
		return x, z
	end
	local angle = math.atan2(z, x)
	local r = clearRadius(path, angle, math.sqrt(x * x + z * z))
	return math.cos(angle) * r, math.sin(angle) * r
end

-- Points every <= STEP studs from a to b (a excluded, b included).
local function subdivide(out: { Vec }, a: Vec, b: Vec)
	local n = math.max(1, math.ceil(dist(a, b) / FountainRide.STEP))
	for k = 1, n do
		local u = k / n
		table.insert(out, v3(a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u, a[3] + (b[3] - a[3]) * u))
	end
end

local function length(points: { Vec }, from: Vec): number
	local total, prev = 0, from
	for _, p in points do
		total += dist(prev, p)
		prev = p
	end
	return total
end

-- The curl from `from` round the fountain to `to` (polar: the angle sweeps
-- `sweep` radians, the radius eases between the two), pushed clear of the
-- low slide. `from` excluded, `to` included.
local function curl(path: { Vec }, from: Vec, to: Vec, sweep: number): { Vec }
	local a0, r0 = math.atan2(from[3], from[1]), math.sqrt(from[1] ^ 2 + from[3] ^ 2)
	local r1 = math.sqrt(to[1] ^ 2 + to[3] ^ 2)
	local rough = math.abs(sweep) * math.max(r0, r1) + math.abs(r1 - r0)
	local n = math.max(2, math.ceil(rough / FountainRide.STEP))
	local out = {}
	for k = 1, n - 1 do
		local u = k / n
		local angle = a0 + sweep * u
		local r = clearRadius(path, angle, r0 + (r1 - r0) * (u * u * (3 - 2 * u)))
		table.insert(out, v3(math.cos(angle) * r, to[2], math.sin(angle) * r))
	end
	table.insert(out, v3(to[1], to[2], to[3]))
	-- Pushed points can sit further apart than STEP: fill the gaps.
	local even = {}
	local prev = from
	for _, p in out do
		subdivide(even, prev, p)
		prev = p
	end
	return even
end

-- Run-out points after the mouth: EXIT_RUN straight on, then the shorter clear curl.
local function runOut(path: { Vec }, landing: Vec): { Vec }
	local mouth = path[#path]
	local before = path[#path - 1]
	local dx, dz = mouth[1] - before[1], mouth[3] - before[3]
	local len = math.max(math.sqrt(dx * dx + dz * dz), 1e-6)
	local exit =
		v3(mouth[1] + dx / len * FountainRide.EXIT_RUN, landing[2], mouth[3] + dz / len * FountainRide.EXIT_RUN)
	local out = {}
	subdivide(out, mouth, exit)
	local a0 = math.atan2(exit[3], exit[1])
	local d = (math.atan2(landing[3], landing[1]) - a0) % (math.pi * 2)
	local ahead = curl(path, exit, landing, d)
	local back = curl(path, exit, landing, d - math.pi * 2)
	local chosen = if length(back, exit) < length(ahead, exit) then back else ahead
	for _, p in chosen do
		table.insert(out, p)
	end
	return out
end

-- Speed on the slide `s` studs from the head.
local function slideSpeed(s: number): number
	local v0 = FountainRide.SLIDE_START_SPEED
	return math.min(FountainRide.SLIDE_SPEED, math.sqrt(v0 * v0 + 2 * FountainRide.SLIDE_ACCEL * s))
end

-- Speed on the run `s` studs past the mouth with `left` studs to the landing.
local function runSpeed(s: number, left: number): number
	local top = FountainRide.SLIDE_SPEED
	local walk = FountainRide.RUN_SPEED
	local v = math.max(walk, math.sqrt(math.max(0, top * top - 2 * FountainRide.RUN_DECEL * s)))
	if left < FountainRide.STOP_DISTANCE then
		v = math.min(v, walk * math.sqrt(left / FountainRide.STOP_DISTANCE))
	end
	return math.max(FountainRide.MIN_SPEED, v)
end

--[[
	Plans the ride for a slime landing at `landing` ({ x, y, z }; y = the
	ground there). `path` is the slide's waypoints from head to mouth.
	The landing is used as given: pass it through clearLanding first.
]]
function FountainRide.new(path: { Vec }, landing: Vec): Ride
	assert(#path >= 2, "FountainRide.new: slide path needs two waypoints")
	local head = path[1]
	local points: { Vec } = { v3(head[1], head[2] - FountainRide.EMERGE_DEPTH, head[3]) }
	local times: { number } = { 0 }
	local phases: { Phase } = { "Emerge" }

	-- Emerge: straight up to the head at an even pace.
	local rise: { Vec } = {}
	subdivide(rise, points[1], head)
	for k, p in rise do
		table.insert(points, p)
		table.insert(times, FountainRide.EMERGE_SECONDS * k / #rise)
		table.insert(phases, "Emerge")
	end

	-- Slide: through every waypoint in order.
	local t = FountainRide.EMERGE_SECONDS
	local s = 0
	local prev = head
	for i = 2, #path do
		local seg: { Vec } = {}
		subdivide(seg, path[i - 1], path[i])
		for _, p in seg do
			local ds = dist(prev, p)
			t += ds / slideSpeed(s + ds / 2)
			s += ds
			table.insert(points, p)
			table.insert(times, t)
			table.insert(phases, "Slide")
			prev = p
		end
	end
	local slideEndsAt, slideLength = t, s

	-- Run: out of the mouth and round to the landing.
	local run = runOut(path, landing)
	local runLength = length(run, prev)
	local r = 0
	for _, p in run do
		local ds = dist(prev, p)
		t += ds / runSpeed(r + ds / 2, runLength - r - ds / 2)
		r += ds
		table.insert(points, p)
		table.insert(times, t)
		table.insert(phases, "Run")
		prev = p
	end

	return {
		points = points,
		times = times,
		phases = phases,
		landing = v3(landing[1], landing[2], landing[3]),
		duration = t,
		emergeSeconds = FountainRide.EMERGE_SECONDS,
		slideEndsAt = slideEndsAt,
		slideLength = slideLength,
		runLength = runLength,
	}
end

-- Index i with times[i] <= t < times[i + 1] (binary search).
local function find(times: { number }, t: number): number
	local lo, hi = 1, #times
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if times[mid] <= t then
			lo = mid
		else
			hi = mid
		end
	end
	return lo
end

-- Unit direction of travel around point i (horizontal outside the slide).
local function heading(ride: Ride, i: number): Vec
	local pts = ride.points
	local n = #pts
	local a, b = pts[math.max(1, i - 1)], pts[math.min(n, i + 1)]
	local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
	if ride.phases[i] ~= "Slide" then
		dy = 0
	end
	if ride.phases[i] == "Emerge" or dx * dx + dy * dy + dz * dz < 1e-9 then
		-- Face down the slide while rising out of the crown.
		local p1, p2 = pts[1], nil
		for k = 1, n do
			if ride.phases[k] == "Slide" then
				p2 = pts[k]
				break
			end
		end
		p2 = p2 or pts[n]
		dx, dy, dz = p2[1] - p1[1], 0, p2[3] - p1[3]
	end
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	if len < 1e-9 then
		return { 0, 0, -1 }
	end
	return { dx / len, dy / len, dz / len }
end

--[[
	Where the slime is `t` seconds into the ride: position, unit heading and
	phase. t <= 0 is the emerge start; t >= duration is the landing ("Done").
]]
function FountainRide.sample(ride: Ride, t: number): (Vec, Vec, Phase)
	local times, pts = ride.times, ride.points
	local n = #pts
	if t >= ride.duration then
		return v3(ride.landing[1], ride.landing[2], ride.landing[3]), heading(ride, n), "Done"
	end
	if t <= 0 then
		return v3(pts[1][1], pts[1][2], pts[1][3]), heading(ride, 1), "Emerge"
	end
	local i = find(times, t)
	local j = math.min(i + 1, n)
	local span = times[j] - times[i]
	local k = if span > 1e-9 then (t - times[i]) / span else 0
	local a, b = pts[i], pts[j]
	local p = v3(a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k)
	return p, heading(ride, j), ride.phases[j]
end

return FountainRide
