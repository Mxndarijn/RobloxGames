--!nocheck
-- The fountain ride (TODO 12, v27 playtest: slimes didn't go down the slide).
-- Pure: FountainRide over a few thousand rolled landings, sampled at 30 Hz
-- the way WorldView plays it (emerge -> every slide waypoint in order ->
-- run-out round the plaza), checked for order, speed, clearance and the
-- final spot. Live: the real server in the fake runtime, every wild model
-- tracked frame by frame from the crown to its resting spot: with
-- FEATURES.Parade the head of the goo lane (ParadeLane.entrySpot), where it
-- waits until the hop-on window ends (tests/ParadeLane.spec has the walk).
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Config = require("../src/shared/Config")
local Fountain = require("../src/shared/Fountain")
local FountainRide = require("../src/shared/FountainRide")
local ParadeLane = require("../src/shared/ParadeLane")
local Rng = require("../src/shared/Rng")
local Runtime = require("../tools/livetest/Runtime")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local PATH = WorldLayout.SLIDE_PATH
local HEAD, MOUTH = PATH[1], PATH[#PATH]
local GROUND = 0 -- the GroundTerrain surface
local FPS = 30
local SILO = WorldLayout.FOUNTAIN_PROFILE.plinthRadius
local SLIME_HALF = Config.SLIME_BASE_DIAMETER * Config.MAX_SIZE / 2
local MAX_RIDE_SECONDS = 20 -- well inside WILD_LIFETIME minus the despawn telegraph

local function dist(a, b): number
	return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
end
local function radius(p): number
	return math.sqrt(p[1] ^ 2 + p[3] ^ 2)
end

-- Rolled landings exactly as the server makes them (Fountain.roll -> clearLanding).
local function landings(seed: number, n: number): { { number } }
	local rng = Rng.new(seed)
	local out = {}
	for k = 1, n do
		local drop = Fountain.roll(rng, `s{k}`, k % 3 == 0)
		local x, z =
			FountainRide.clearLanding(PATH, math.cos(drop.angle) * drop.radius, math.sin(drop.angle) * drop.radius)
		table.insert(out, { x, GROUND, z })
	end
	return out
end

local LANDINGS = landings(28, 600)
local RIDES = {}
for k, landing in LANDINGS do
	RIDES[k] = FountainRide.new(PATH, landing)
end

-- 30 Hz playback like WorldView.animate: positions, phases.
local function play(ride)
	local frames = {}
	local n = math.ceil(ride.duration * FPS)
	for f = 0, n do
		local p, dir, phase = FountainRide.sample(ride, f / FPS)
		table.insert(frames, { p = p, dir = dir, phase = phase, t = f / FPS })
	end
	return frames
end

describe("FountainRide: landings", function()
	it("every rolled landing is on the plaza, clear of the silo and the low slide", function()
		for _, l in LANDINGS do
			local r = radius(l)
			expect(r >= Fountain.MIN_RADIUS - 1e-6).toBe(true)
			expect(r <= WorldLayout.PLAZA_RADIUS - SLIME_HALF).toBe(true)
			expect(FountainRide.clearance(PATH, l[1], l[3]) >= FountainRide.FOOTPRINT).toBe(true)
		end
	end)
	it("moves a landing on the slide's footprint straight out, keeps clear ones as they are", function()
		local moved = 0
		for a = 0, 359, 2 do
			for _, r in { 34, 36, 38, 40 } do
				local x, z = math.cos(math.rad(a)) * r, math.sin(math.rad(a)) * r
				local nx, nz = FountainRide.clearLanding(PATH, x, z)
				if FountainRide.clearance(PATH, x, z) >= FountainRide.FOOTPRINT then
					expect(nx).toBe(x)
					expect(nz).toBe(z)
				else
					moved += 1
					expect(math.atan2(nz, nx)).toBeCloseTo(math.atan2(z, x), 1e-6)
					expect(math.sqrt(nx * nx + nz * nz) > r).toBe(true)
					expect(FountainRide.clearance(PATH, nx, nz) >= FountainRide.FOOTPRINT).toBe(true)
				end
			end
		end
		-- the mouth end of the slide (r 32..35.5 on +Z) is where they were landing in it
		expect(moved > 0).toBe(true)
		local mx, mz = FountainRide.clearLanding(PATH, MOUTH[1], MOUTH[3])
		expect(dist({ mx, 0, mz }, { MOUTH[1], 0, MOUTH[3] }) >= FountainRide.FOOTPRINT - 1e-6).toBe(true)
	end)
end)

describe("FountainRide: emerge and slide", function()
	it("starts inside the goo crown under the slide head and rises straight to it", function()
		for k = 1, 20 do
			local frames = play(RIDES[k])
			local first = frames[1]
			expect(first.phase).toBe("Emerge")
			expect(dist(first.p, { HEAD[1], HEAD[2] - FountainRide.EMERGE_DEPTH, HEAD[3] }) < 1e-6).toBe(true)
			for _, f in frames do
				if f.phase ~= "Emerge" then
					break
				end
				expect(f.p[1]).toBeCloseTo(HEAD[1], 1e-6)
				expect(f.p[3]).toBeCloseTo(HEAD[3], 1e-6)
			end
		end
	end)
	it("goes through every slide waypoint, in order, head to mouth", function()
		for k = 1, 60 do
			local ride = RIDES[k]
			local at = 0
			for w, wp in PATH do
				local found = nil
				for i = at + 1, #ride.points do
					if dist(ride.points[i], wp) < 1e-6 then
						found = i
						break
					end
				end
				expect(found ~= nil).toBe(true)
				expect(ride.phases[found]).toBe(if w == 1 then "Emerge" else "Slide")
				at = found
			end
		end
	end)
	it("phases run Emerge -> Slide -> Run, times strictly increase", function()
		local order = { Emerge = 1, Slide = 2, Run = 3 }
		for _, ride in RIDES do
			for i = 2, #ride.points do
				expect(ride.times[i] > ride.times[i - 1]).toBe(true)
				expect(order[ride.phases[i]] >= order[ride.phases[i - 1]]).toBe(true)
			end
			expect(ride.phases[#ride.points]).toBe("Run")
		end
	end)
	it("rides the slide slowly enough to watch (was 1.8 s for 235 studs) and never faster than SLIDE_SPEED", function()
		for _, ride in RIDES do
			local slideSeconds = ride.slideEndsAt - ride.emergeSeconds
			expect(ride.slideLength).toBeCloseTo(235.2, 0.5)
			expect(slideSeconds >= 4).toBe(true)
			expect(slideSeconds <= 8).toBe(true)
		end
		for k = 1, 60 do
			local frames = play(RIDES[k])
			for f = 2, #frames do
				expect(dist(frames[f].p, frames[f - 1].p) <= FountainRide.SLIDE_SPEED / FPS + 1e-3).toBe(true)
			end
		end
	end)
	it("stays on the slide floor while sliding (pivot on the path, never under it)", function()
		for k = 1, 30 do
			for _, f in play(RIDES[k]) do
				if f.phase == "Slide" then
					expect(f.p[2] >= MOUTH[2] - 1e-6).toBe(true)
					expect(f.p[2] <= HEAD[2] + 1e-6).toBe(true)
				end
			end
		end
	end)
end)

describe("FountainRide: run-out and landing", function()
	it("leaves the mouth along the slide (no snap in heading at the hand-off)", function()
		local a, b = PATH[#PATH - 1], PATH[#PATH]
		local exit = { b[1] - a[1], b[3] - a[3] }
		local len = math.sqrt(exit[1] ^ 2 + exit[2] ^ 2)
		for k = 1, 60 do
			local ride = RIDES[k]
			local _, dir = FountainRide.sample(ride, ride.slideEndsAt + 0.05)
			local cos = (dir[1] * exit[1] + dir[3] * exit[2]) / len
			expect(cos > math.cos(math.rad(10))).toBe(true)
		end
	end)
	it("never crosses the low slide, its posts or the silo on the way round", function()
		local exitT = 40 / FountainRide.RUN_SPEED -- the straight exit runs on until the slime clears the landing ring
		for _, ride in RIDES do
			for i, p in ride.points do
				if ride.phases[i] == "Run" then
					expect(radius(p) > SILO + SLIME_HALF).toBe(true)
					if ride.times[i] > ride.slideEndsAt + exitT then
						expect(FountainRide.clearance(PATH, p[1], p[3]) >= FountainRide.FOOTPRINT - 0.05).toBe(true)
					end
				end
			end
		end
	end)
	it("walks on the plaza: ground height after the mouth, inside the plaza", function()
		for _, ride in RIDES do
			for i, p in ride.points do
				if ride.phases[i] == "Run" then
					expect(p[2] >= GROUND - 1e-6).toBe(true)
					expect(p[2] <= GROUND + FountainRide.RING_TOP + 1e-6).toBe(true)
					expect(radius(p) <= WorldLayout.PLAZA_RADIUS).toBe(true)
				end
			end
		end
	end)
	it("takes the shorter way round (never more than half a turn plus the slide detour)", function()
		for _, ride in RIDES do
			expect(ride.runLength <= math.pi * (Fountain.MAX_RADIUS + 4) + 2 * 30).toBe(true)
		end
	end)
	it("ends exactly on its landing, eased to a stop, and stays there", function()
		for _, ride in RIDES do
			expect(ride.duration < MAX_RIDE_SECONDS).toBe(true)
			local p, _, phase = FountainRide.sample(ride, ride.duration)
			expect(phase).toBe("Done")
			expect(dist(p, ride.landing) < 1e-9).toBe(true)
			local later = FountainRide.sample(ride, ride.duration + 30)
			expect(dist(later, ride.landing) < 1e-9).toBe(true)
			local near = FountainRide.sample(ride, ride.duration - 1 / FPS)
			expect(dist(near, ride.landing) <= FountainRide.RUN_SPEED / FPS).toBe(true)
		end
	end)
	it("rides finish long before the slime can expire", function()
		expect(MAX_RIDE_SECONDS < Config.WILD_LIFETIME - Config.DESPAWN_TELEGRAPH_SECONDS).toBe(true)
	end)
end)

-- The real server: wilds spawned by GameLoop, placed by WorldView.reconcile,
-- pivoted by its animate loop, watched at 30 Hz.
local placePath = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-ride-{os.time()}.rbxlx`
local built = process.exec("rojo", { "build", "-o", placePath })
assert(built.ok, `rojo build failed: {built.stderr}`)
local rt = Runtime.new(placePath, {
	createMeshPart = function(_meshId)
		return roblox.Instance.new("MeshPart")
	end,
})
require("@lune/fs").removeFile(placePath)
rt:boot()
local tracks = {}
local SIM_SECONDS = 50
-- Seconds the lead-in from the slide mouth to the lane entry takes at the wild walk pace.
local LEAD_SECONDS = ParadeLane.LEAD_LENGTH / ParadeLane.walkSpeed(Config.WILD_LIFETIME)
for _ = 1, SIM_SECONDS * FPS do
	rt:step(1 / FPS)
	local folder = rt.workspace:FindFirstChild("WildSlimes")
	local seen = {}
	for _, model in (if folder then folder:GetChildren() else {}) do
		local p = model:GetPivot().Position
		local track = tracks[model.Name]
		if not track then
			track = { born = rt.T, frames = {}, gone = nil, anchored = true }
			tracks[model.Name] = track
		end
		seen[model.Name] = true
		table.insert(track.frames, { t = rt.T, p = { p.X, p.Y, p.Z }, riding = model:GetAttribute("Riding") })
		track.anchored = track.anchored and model.PrimaryPart.Anchored and not model.PrimaryPart.CanCollide
	end
	for name, track in tracks do
		if not seen[name] and not track.gone then
			track.gone = rt.T
		end
	end
end

describe("FountainRide: the live server rides every spawned slime", function()
	local finished = {}
	for name, track in tracks do
		if track.born <= SIM_SECONDS - MAX_RIDE_SECONDS then
			finished[name] = track
		end
	end
	it("spawns enough slimes to check", function()
		local n = 0
		for _ in finished do
			n += 1
		end
		expect(n >= 5).toBe(true)
		expect(#rt.errors).toBe(0)
	end)
	it("each one emerges in the crown and passes the slide head and the mouth", function()
		for _, track in finished do
			local first = track.frames[1].p
			expect(dist(first, HEAD) <= FountainRide.EMERGE_DEPTH + 0.5).toBe(true)
			local nearMouth, nearMid = math.huge, math.huge
			local mid = PATH[math.ceil(#PATH / 2)]
			for _, f in track.frames do
				nearMouth = math.min(nearMouth, dist(f.p, MOUTH))
				nearMid = math.min(nearMid, dist(f.p, mid))
			end
			expect(nearMid <= FountainRide.SLIDE_SPEED / FPS).toBe(true)
			expect(nearMouth <= FountainRide.SLIDE_SPEED / FPS).toBe(true)
		end
	end)
	it(
		"each one carries Riding from the crown to its landing and not after (pc-watcher ring_slimes skips it)",
		function()
			for _, track in finished do
				expect(track.frames[1].riding).toBe(true)
				for _, f in track.frames do
					local r = math.sqrt(f.p[1] ^ 2 + f.p[3] ^ 2)
					-- crossing the landing ring's band is only ever the ride's run-out, never a resting wild
					if r < Fountain.RING_BAND_OUTER then
						expect(f.riding).toBe(true)
					end
					-- Riding runs through the lead-in from the slide mouth, and stops once the slime is on the lane
					if f.t >= track.born + ParadeLane.RIDE_SECONDS + LEAD_SECONDS + 0.3 then
						expect(f.riding).toBeNil()
					end
				end
			end
		end
	)
	it("none vanishes or despawns early (still in WildSlimes, anchored, non-colliding)", function()
		for _, track in finished do
			expect(track.gone).toBe(nil)
			expect(track.anchored).toBe(true)
		end
	end)
	it("none teleports: every frame moves at most SLIDE_SPEED / 30", function()
		for _, track in finished do
			for i = 2, #track.frames do
				-- (+0.25: the slide-to-lane shift eases in over the last frames)
				expect(dist(track.frames[i].p, track.frames[i - 1].p) <= FountainRide.SLIDE_SPEED / FPS + 0.25).toBe(
					true
				)
			end
		end
	end)
	it("bug #5: each one walks on from the slide mouth at once: no rest on the lane entry, never idle", function()
		expect(Config.FEATURES.Parade).toBe(true)
		local mouth = PATH[#PATH]
		for _, track in finished do
			-- from the slide's end on, every half second of frames moves it along the lead-in / lane
			local from = track.born + ParadeLane.RIDE_SECONDS
			local frames = {}
			for _, f in track.frames do
				if f.t >= from and f.t <= track.born + ParadeLane.RIDE_SECONDS + LEAD_SECONDS then
					table.insert(frames, f)
				end
			end
			expect(#frames >= FPS).toBe(true)
			expect(dist(frames[1].p, { mouth[1], mouth[2], mouth[3] }) <= ParadeLane.SPREAD / 2 + 2).toBe(true)
			for i = FPS // 2, #frames, FPS // 2 do
				local moved = math.sqrt(
					(frames[i].p[1] - frames[i - FPS // 2 + 1].p[1]) ^ 2
						+ (frames[i].p[3] - frames[i - FPS // 2 + 1].p[3]) ^ 2
				)
				expect(moved > 0.05).toBe(true)
			end
		end
	end)
end)

-- v30 C3: slimes clipped through the plaza's middle ring (Plaza.LandingRing, 18 curb tiles, 7 left out at the slide, visual-only). Slimes
-- are anchored and script moved, so the fix is routing: nothing places or walks a slime inside the ring.
describe("FountainRide: the landing ring (v30 C3)", function()
	local function ringOuter(): number
		local tiles = {}
		local function walk(nodes, path)
			for _, node in nodes or {} do
				local p = `{path}/{node.name}`
				if p == "/Map/Plaza/LandingRing" then
					tiles = node.children
				end
				walk(node.children, p)
			end
		end
		walk(WorldLayout.build(), "")
		assert(#tiles == 11, "LandingRing tiles missing") -- 18 less the 7 left out where the slide lands
		local worst = 0
		for _, tile in tiles do
			local yaw = math.rad(tile.rot[2])
			local c, s = math.cos(yaw), math.sin(yaw)
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local lx, lz = sx * tile.size[1] / 2, sz * tile.size[3] / 2
					local x = tile.pos[1] + c * lx + s * lz
					local z = tile.pos[3] - s * lx + c * lz
					worst = math.max(worst, math.sqrt(x * x + z * z))
				end
			end
		end
		return worst
	end
	local CLEAR = Fountain.LANDING_RING_OUTER + SLIME_HALF

	it("Fountain.LANDING_RING_OUTER covers the farthest corner of every curb tile", function()
		local outer = ringOuter()
		expect(outer <= Fountain.LANDING_RING_OUTER).toBe(true)
		expect(Fountain.LANDING_RING_OUTER - outer < 0.5).toBe(true)
	end)
	it("every rolled landing, even after clearLanding, keeps a whole slime outside the ring", function()
		for _, l in LANDINGS do
			expect(radius(l) >= CLEAR).toBe(true)
		end
		for a = 0, 359, 3 do
			local x, z = FountainRide.clearLanding(
				PATH,
				math.cos(math.rad(a)) * Fountain.MIN_RADIUS,
				math.sin(math.rad(a)) * Fountain.MIN_RADIUS
			)
			expect(math.sqrt(x * x + z * z) >= CLEAR - 1e-6).toBe(true)
		end
	end)
	it("the run-out hops over the curb, then keeps the whole slime outside the ring", function()
		for _, ride in RIDES do
			for i, p in ride.points do
				if ride.phases[i] == "Run" then
					local r = radius(p)
					-- any part of the slime can overlap the curb: its bottom is above the curb top (3.145)
					local bearing = math.deg(math.atan2(p[3], p[1]))
					local inGap = bearing >= FountainRide.RING_GAP_FROM and bearing <= FountainRide.RING_GAP_TO
					if r < Fountain.LANDING_RING_OUTER + SLIME_HALF and not inGap then
						expect(p[2] - GROUND >= 3.145 - 1e-6 or dist(p, MOUTH) < 3.5).toBe(true) -- the slide's own mouth is inside the ring
					end
				end
			end
			local last = ride.points[#ride.points]
			expect(radius(last) >= CLEAR - 1e-6).toBe(true)
		end
	end)
	it("the run-out is back on the ground once it is past the ring", function()
		for _, ride in RIDES do
			for i, p in ride.points do
				if ride.phases[i] == "Run" and radius(p) >= FountainRide.RING_CLEAR then
					expect(p[2]).toBeCloseTo(GROUND)
				end
			end
		end
	end)
	it("FountainRide's ring constants match Fountain's", function()
		expect(FountainRide.RING_OUTER).toBe(Fountain.LANDING_RING_OUTER)
		expect(FountainRide.RING_TOP > 3.145).toBe(true)
	end)
	it("the goo lane (walk) never enters the ring", function()
		for _, p in ParadeLane.WAYPOINTS do
			expect(math.sqrt(p[1] ^ 2 + p[2] ^ 2) - ParadeLane.SPREAD / 2 >= CLEAR).toBe(true)
		end
		for s = 0, ParadeLane.LENGTH, 0.5 do
			for _, lat in { -ParadeLane.SPREAD / 2, 0, ParadeLane.SPREAD / 2 } do
				local x, z = ParadeLane.offsetAt(s, lat)
				expect(math.sqrt(x * x + z * z) >= CLEAR).toBe(true)
			end
		end
	end)
end)
