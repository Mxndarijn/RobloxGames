--!nocheck
-- The goo parade (TODO 16): wild slimes ride the slide onto a goo lane, hop
-- round the plaza with lane position = time left, and slide into the goo
-- drain with a splash as they expire. Checked here: the time mapping
-- (progress = 1 - time left / lifetime), the route's clearance from every
-- plaza prop, podium, spot, plot and the spawn pad, grab / buy / steal
-- taking a slime off the lane, the handoff to the drain and the Drained
-- event, the despawn telegraph staying readable, and the real server in the
-- fake runtime (lane laid, slimes walking it, a live grab, drain + splash).
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Fountain = require("../src/shared/Fountain")
local FountainRide = require("../src/shared/FountainRide")
local MinimapData = require("../src/visuals/shared/MinimapData")
local ParadeLane = require("../src/shared/ParadeLane")
local PropClearance = require("../src/visuals/shared/PropClearance")
local Runtime = require("../tools/livetest/Runtime")
local Scene = require("../src/server/Scene")
local ServerFixtures = require("./ServerFixtures")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local LIFE = Config.WILD_LIFETIME
local HOP = ParadeLane.HOP_SECONDS
local DRAIN = ParadeLane.DRAIN
local FPS = 30
local PATH = WorldLayout.SLIDE_PATH
local POINTS = ParadeLane.WAYPOINTS

local function hdist(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

-- Distance from (x, z) to a turned rectangle (0 inside).
local function rectDistance(r, x: number, z: number): number
	local a = math.rad(r.yaw)
	local ux, uz, vx, vz = math.cos(a), -math.sin(a), math.sin(a), math.cos(a)
	local dx, dz = x - r.cx, z - r.cz
	local ou = math.max(0, math.abs(dx * ux + dz * uz) - r.hx)
	local ov = math.max(0, math.abs(dx * vx + dz * vz) - r.hz)
	return math.sqrt(ou * ou + ov * ov)
end

local function findNode(node, name: string)
	if node.name == name then
		return node
	end
	for _, child in node.children or {} do
		local hit = findNode(child, name)
		if hit then
			return hit
		end
	end
	return nil
end
local function layoutNode(name: string)
	for _, root in WorldLayout.build() do
		local hit = findNode(root, name)
		if hit then
			return hit
		end
	end
	error(`no {name} in WorldLayout`)
end

-- Lane centreline every 0.25 studs, with its distance along the lane.
local SAMPLES = {}
for s = 0, ParadeLane.LENGTH, 0.25 do
	local x, z = ParadeLane.pointAt(s)
	table.insert(SAMPLES, { s = s, x = x, z = z })
end
-- Distance along the lane where it turns in towards the drain (last r 68 waypoint).
local TURN_IN = 0
for i = 2, #POINTS - 2 do
	TURN_IN += hdist(POINTS[i - 1][1], POINTS[i - 1][2], POINTS[i][1], POINTS[i][2])
end

describe("ParadeLane timing: lane position is time left", function()
	it("progress = 1 - time left / lifetime, for wild and Boss lifetimes", function()
		for _, life in { LIFE, Config.BOSS_LIFETIME } do
			for _, left in { life, life * 0.75, life / 2, 10, 1, 0 } do
				expect(ParadeLane.progress(T0, T0 + life, T0 + life - left)).toBeCloseTo(1 - left / life, 1e-9)
			end
			expect(ParadeLane.progress(T0, T0 + life, T0 - 5)).toBe(0)
			expect(ParadeLane.progress(T0, T0 + life, T0 + life + 30)).toBe(1)
		end
	end)
	it("phases: Ride for HOP_SECONDS, Walk, Drain for the last DRAIN_SECONDS, Gone at expiresAt", function()
		local E = T0 + LIFE
		expect(ParadeLane.phase(T0, E, T0)).toBe("Ride")
		expect(ParadeLane.phase(T0, E, T0 + HOP - 0.01)).toBe("Ride")
		expect(ParadeLane.phase(T0, E, T0 + HOP + 0.01)).toBe("Walk")
		expect(ParadeLane.phase(T0, E, E - ParadeLane.DRAIN_SECONDS - 0.01)).toBe("Walk")
		expect(ParadeLane.phase(T0, E, E - ParadeLane.DRAIN_SECONDS + 0.01)).toBe("Drain")
		expect(ParadeLane.phase(T0, E, E - 0.01)).toBe("Drain")
		expect(ParadeLane.phase(T0, E, E)).toBe("Gone")
	end)
	it("C9: wild pace reads Config.SLIME_MOVE_SPEED_MULT: the lane walk and hop rate are slower by it", function()
		local mult = Config.SLIME_MOVE_SPEED_MULT
		expect(mult < 1 and mult >= 0.6 and mult <= 0.7).toBe(true) -- ~30-40% slower
		local OLD_LIFE = Config.WILD_BASE_LIFETIME
		local oldSpeed = ParadeLane.walkSpeed(OLD_LIFE)
		local newSpeed = ParadeLane.walkSpeed(Config.WILD_LIFETIME)
		expect(newSpeed < oldSpeed).toBe(true)
		-- the lifetime stretches by ~1 / mult, so the speed drops by about mult (within the fixed hop + drain)
		expect(newSpeed / oldSpeed <= 0.7 and newSpeed / oldSpeed >= 0.6).toBe(true)
		expect(Config.WILD_LIFETIME).toBe(math.round(OLD_LIFE / mult))
		expect(ParadeLane.HOP_PERIOD).toBeCloseTo(0.5 / mult, 1e-9)
		-- the drain is still reached at expiry: the walk ends exactly DRAIN_SECONDS before it
		local E = T0 + LIFE
		expect(ParadeLane.distance(T0, E, E - ParadeLane.DRAIN_SECONDS)).toBeCloseTo(ParadeLane.LENGTH, 1e-6)
		-- measured: studs covered in 10 s mid-walk match walkSpeed
		local a = ParadeLane.distance(T0, E, T0 + 40)
		local b = ParadeLane.distance(T0, E, T0 + 50)
		expect(b - a).toBeCloseTo(newSpeed * 10, 1e-6)
		-- the ride still lands well before the walk starts and the warning still fits the walk
		expect(HOP + ParadeLane.DRAIN_SECONDS < LIFE - Config.DESPAWN_TELEGRAPH_SECONDS).toBe(true)
	end)
	it(
		"distance walked is linear in time left: equal time left, equal share of the route from the slide mouth",
		function()
			local total = ParadeLane.LEAD_LENGTH + ParadeLane.LENGTH
			for _, life in { LIFE, Config.BOSS_LIFETIME } do
				local walk = life - HOP - ParadeLane.DRAIN_SECONDS
				local E = T0 + life
				for _, share in { 0, 0.1, 0.25, 0.5, 0.9, 1 } do
					-- time left at this share of the walk
					local left = ParadeLane.DRAIN_SECONDS + walk * (1 - share)
					expect(ParadeLane.walked(T0, E, E - left)).toBeCloseTo(total * share, 1e-6)
				end
				expect(ParadeLane.walked(T0, E, T0 + HOP)).toBeCloseTo(0, 1e-9)
				expect(ParadeLane.distance(T0, E, T0 + 1)).toBe(-ParadeLane.LEAD_LENGTH)
				expect(ParadeLane.distance(T0, E, E - 0.5)).toBe(ParadeLane.LENGTH)
			end
		end
	)
	it(
		"bug #5: the walk starts at the slide mouth the instant the slide ends: no idle wait, no glide to the lane",
		function()
			local mouth = PATH[#PATH]
			for _, lateral in { -ParadeLane.SPREAD / 2, 0, ParadeLane.SPREAD / 2 } do
				local ride = FountainRide.new(PATH, ParadeLane.entrySpot(lateral))
				-- the walk begins when the slide ends (at most 0.25 s of rounding)
				expect(HOP >= ride.slideEndsAt and HOP - ride.slideEndsAt <= 0.25).toBe(true)
				local mouthPose = ParadeLane.pose(T0, T0 + LIFE, lateral, T0 + HOP - 0.01).position
				expect(mouthPose[2]).toBeCloseTo(ParadeLane.LANE_Y, 1e-9)
				-- the slide's last sample and the walk's first point are one spot (the lateral spread aside)
				local p = FountainRide.sample(ride, ride.slideEndsAt)
				expect(hdist(p[1], p[3], mouth[1], mouth[3]) < 1e-6).toBe(true)
				expect(hdist(mouthPose[1], mouthPose[3], mouth[1], mouth[3]) < 1e-6).toBe(true) -- the offset grows from there
				-- moving on the very next frames: no wait before the first step
				local prev = mouthPose
				for f = 1, 6 do
					local now = T0 + HOP + f / FPS
					local q = ParadeLane.pose(T0, T0 + LIFE, lateral, now)
					expect(q.phase).toBe("Walk")
					expect(hdist(q.position[1], q.position[3], prev[1], prev[3]) > 1e-3).toBe(true)
					-- every step lies on the lead-in / lane (no off-lane glide target)
					local x, z = ParadeLane.offsetAt(ParadeLane.distance(T0, T0 + LIFE, now), lateral)
					expect(hdist(q.position[1], q.position[3], x, z) < 1e-6).toBe(true)
					prev = q.position
				end
				-- the lead-in joins the unchanged lane at ENTRY, then the original waypoints
				local atEntry = ParadeLane.offsetAt(0, lateral)
				expect(atEntry).toBeCloseTo(ParadeLane.entrySpot(lateral)[1], 1e-9)
				local x, z = ParadeLane.pointAt(0)
				expect(hdist(x, z, ParadeLane.ENTRY[1], ParadeLane.ENTRY[2]) < 1e-9).toBe(true)
				local mx, mz = ParadeLane.pointAt(-ParadeLane.LEAD_LENGTH)
				expect(hdist(mx, mz, mouth[1], mouth[3]) < 1e-6).toBe(true)
			end
			expect(ParadeLane.LEAD_LENGTH > 5).toBe(true)
		end
	)
	it("moves smoothly at 30 Hz from the entry to the drain (no teleports) and only forwards", function()
		for _, life in { LIFE, Config.BOSS_LIFETIME } do
			local E = T0 + life
			local prev = ParadeLane.pose(T0, E, 1, T0).position
			local lastS = -math.huge
			for f = 1, math.floor(life * FPS) do
				local now = T0 + f / FPS
				local p = ParadeLane.pose(T0, E, 1, now).position
				local step = math.sqrt((p[1] - prev[1]) ^ 2 + (p[2] - prev[2]) ^ 2 + (p[3] - prev[3]) ^ 2)
				expect(step <= FountainRide.RUN_SPEED / FPS).toBe(true)
				local s = ParadeLane.distance(T0, E, now)
				expect(s >= lastS).toBe(true)
				lastS, prev = s, p
			end
		end
	end)
	it(
		"walking slimes stay on the lane: within SPREAD / 2 of the centreline, hopping no higher than HOP_HEIGHT",
		function()
			for _, lateral in { -ParadeLane.SPREAD / 2, 0.4, ParadeLane.SPREAD / 2 } do
				for t = HOP + 0.01, LIFE - ParadeLane.DRAIN_SECONDS - 0.01, 0.37 do
					local pose = ParadeLane.pose(T0, T0 + LIFE, lateral, T0 + t)
					local p = pose.position
					expect(pose.phase).toBe("Walk")
					local cx, cz = ParadeLane.pointAt(ParadeLane.distance(T0, T0 + LIFE, T0 + t))
					expect(hdist(p[1], p[3], cx, cz) <= ParadeLane.SPREAD / 2 + 1e-6).toBe(true)
					expect(
						p[2] >= ParadeLane.LANE_Y - 1e-9 and p[2] <= ParadeLane.LANE_Y + ParadeLane.HOP_HEIGHT + 1e-9
					).toBe(true)
				end
			end
		end
	)
	it("lateral offset spans the Fountain.roll radius band", function()
		local lo = ParadeLane.lateral(Fountain.MIN_RADIUS, Fountain.MIN_RADIUS, Fountain.MAX_RADIUS)
		local hi = ParadeLane.lateral(Fountain.MAX_RADIUS, Fountain.MIN_RADIUS, Fountain.MAX_RADIUS)
		expect(lo).toBeCloseTo(-ParadeLane.SPREAD / 2, 1e-9)
		expect(hi).toBeCloseTo(ParadeLane.SPREAD / 2, 1e-9)
	end)
end)

describe("ParadeLane route: loops round the plaza, clear of props and podiums", function()
	it("sweeps most of a turn round the fountain, entry beside the drain on the slide-exit side", function()
		local swept, prev = 0, math.atan2(POINTS[1][2], POINTS[1][1])
		for i = 2, #POINTS - 2 do
			local a = math.atan2(POINTS[i][2], POINTS[i][1])
			local d = (a - prev + math.pi) % (2 * math.pi) - math.pi
			expect(d > 0).toBe(true) -- counter-clockwise all the way (wild angle grows)
			swept += d
			prev = a
		end
		expect(math.deg(swept) >= 300).toBe(true)
		expect(ParadeLane.ENTRY[2] > 0 and ParadeLane.ENTRY[1] < -DRAIN.lipRadius).toBe(true)
		expect(ParadeLane.LENGTH > 350).toBe(true)
	end)
	it("DRAIN matches the GooDrain on the plaza (curb ring on the +Z end of the box)", function()
		local node = layoutNode("GooDrain")
		local ringZ = node.pos[3] + (node.size[3] - node.size[1]) / 2
		expect(DRAIN.x).toBeCloseTo(node.pos[1], 1e-6)
		expect(math.abs(DRAIN.z - ringZ) < 0.1).toBe(true)
		expect(DRAIN.lipRadius * 2).toBeCloseTo(node.size[1], 1e-6)
	end)

	-- Obstacles: name -> distance from a lane point to its bounds.
	local obstacles = {}
	local function add(name: string, fn)
		table.insert(obstacles, { name = name, distance = fn })
	end
	for _, def in WorldLayout.PLAZA_PROPS do
		local a = math.rad(def.yaw)
		local rect = {
			cx = math.sin(a) * def.r,
			cz = math.cos(a) * def.r,
			hx = def.size[1] / 2,
			hz = def.size[3] / 2,
			yaw = def.yaw,
		}
		add(`{def.name} bounds`, function(x, z)
			return rectDistance(rect, x, z)
		end)
	end
	for _, zone in PropClearance.ZONES do
		-- plots, entrances, buy stands, prop spots (shop, leaderboard board, NPC), plaza props / podiums (circles)
		if zone.kind == "rect" then
			add(zone.name, function(x, z)
				return rectDistance(zone.rect, x, z)
			end)
		elseif zone.kind == "circle" then
			add(zone.name, function(x, z)
				return hdist(x, z, zone.x, zone.z) - zone.radius
			end)
		end
	end
	for _, prop in WorldLayout.RANCH_PROPS do
		local rect = PropClearance.footprint(prop)
		add(prop.name, function(x, z)
			return rectDistance(rect, x, z)
		end)
	end
	local hub = roblox.deserializeModel(fs.readFile("world/HubSpawn.rbxmx"))[1]
	local hubPart = if hub:IsA("BasePart") then hub else hub:FindFirstChildWhichIsA("BasePart", true)
	local _, hubYaw = hubPart.CFrame:ToOrientation()
	local hubRect = {
		cx = hubPart.CFrame.Position.X,
		cz = hubPart.CFrame.Position.Z,
		hx = hubPart.Size.X / 2,
		hz = hubPart.Size.Z / 2,
		yaw = math.deg(hubYaw),
	}
	add("HubSpawn", function(x, z)
		return rectDistance(hubRect, x, z)
	end)
	add("ring path", function(x, z)
		return WorldLayout.RING_PATH_RADIUS - WorldLayout.RING_PATH_WIDTH / 2 - math.sqrt(x * x + z * z)
	end)
	local tile = layoutNode("Tile6")
	local landingOuter = math.sqrt(tile.pos[1] ^ 2 + tile.pos[3] ^ 2) + tile.size[3] / 2
	add("landing ring", function(x, z)
		return math.sqrt(x * x + z * z) - landingOuter
	end)

	it("HubSpawn in the place matches MinimapData (the bounds the lane dodges)", function()
		for _, p in MinimapData.points() do
			if p.name == "HubSpawn" then
				expect(hdist(p.x, p.z, hubRect.cx, hubRect.cz) < 0.5).toBe(true)
			end
		end
	end)
	it(
		`keeps CLEARANCE ({ParadeLane.CLEARANCE} studs) from every prop, podium, spot, plot, the spawn pad, ring path and landing ring`,
		function()
			expect(ParadeLane.CLEARANCE >= ParadeLane.SPREAD / 2 + ParadeLane.SLIME_RADIUS).toBe(true)
			expect(#obstacles > 40).toBe(true)
			for _, o in obstacles do
				local worst, at = math.huge, 0
				for _, p in SAMPLES do
					local d = o.distance(p.x, p.z)
					if d < worst then
						worst, at = d, p.s
					end
				end
				if worst < ParadeLane.CLEARANCE then
					error(`lane comes {worst} studs from {o.name} at s = {at} (needs {ParadeLane.CLEARANCE})`)
				end
			end
		end
	)
	it("podiums and the signpost stand on the plain r 68 circle (why the route dips inside them)", function()
		for _, name in { "Podium_1", "Podium_2", "Podium_3", "Signpost" } do
			local plain = math.huge -- the old r 68 circle went straight through
			for _, def in WorldLayout.PLAZA_PROPS do
				if def.name == name then
					local a = math.rad(def.yaw)
					plain = math.abs(
						math.sqrt((math.sin(a) * def.r) ^ 2 + (math.cos(a) * def.r) ^ 2) - ParadeLane.LANE_RADIUS
					)
				end
			end
			expect(plain < 1).toBe(true)
		end
	end)
	it("keeps the biggest slime FOOTPRINT clear of the low slide", function()
		for _, p in SAMPLES do
			expect(FountainRide.clearance(PATH, p.x, p.z) >= FountainRide.FOOTPRINT + ParadeLane.SPREAD / 2).toBe(true)
		end
	end)
	it("walks clear of the goo drain until it turns in, and never touches the curb before the drain slide", function()
		local node = layoutNode("GooDrain")
		local box = { cx = node.pos[1], cz = node.pos[3], hx = node.size[1] / 2, hz = node.size[3] / 2, yaw = 0 }
		for _, p in SAMPLES do
			if p.s <= TURN_IN then
				expect(rectDistance(box, p.x, p.z) >= ParadeLane.CLEARANCE).toBe(true)
			end
			expect(hdist(p.x, p.z, DRAIN.x, DRAIN.z) >= DRAIN.lipRadius + ParadeLane.SLIME_RADIUS - 1e-6).toBe(true)
		end
	end)
	it("stays inside PropClearance's keep-clear rings, so kit props stay off it", function()
		for _, p in SAMPLES do
			local r = math.sqrt(p.x * p.x + p.z * p.z)
			expect(r - ParadeLane.HALF_WIDTH >= 34).toBe(true) -- landing band inner edge
			expect(r + ParadeLane.HALF_WIDTH <= PropClearance.LANE_POSTS_OUTER).toBe(true)
		end
	end)
end)

describe("ParadeLane: grab / buy / steal take a slime off the lane", function()
	local function laneWorld()
		local world = ServerFixtures.world()
		local id = Spawner.spawnOne(world, T0)
		return world, id
	end
	local function entryOf(world, id)
		return Scene.describe(world, T0 + 20)[id]
	end
	it("lane slimes keep their Grab / Buy prompt the whole way, drain slide included", function()
		local world, id = laneWorld()
		world.wild[id].price = 40
		for _, t in { HOP + 1, LIFE / 2, LIFE - ParadeLane.DRAIN_SECONDS + 0.5, LIFE - 0.05 } do
			local entry = Scene.describe(world, T0 + t)[id]
			expect(entry.state).toBe("Wild")
			expect(entry.promptEnabled).toBe(true)
			expect(entry.promptText).toBe("Buy $40")
		end
		world.wild[id].price = 0
		expect(entryOf(world, id).promptText).toBe("Grab")
	end)
	it("grab: a free lane slime is carried, off the lane, and never drains", function()
		local world, id = laneWorld()
		ServerFixtures.join(world, 1, nil, 0)
		world.wild[id].price = 0
		expect(ParadeLane.onLane(world.wild[id], world.carriedBy[id] ~= nil)).toBe(true)
		expect((Carry.grab(world, 1, id, 3, T0 + 30))).toBe(true)
		expect(ParadeLane.onLane(world.wild[id], world.carriedBy[id] ~= nil)).toBe(false)
		expect(entryOf(world, id).state).toBe("Carried")
		table.clear(world.outbox)
		Spawner.step(world, T0 + LIFE + 1)
		expect(world.wild[id] ~= nil).toBe(true) -- carried slimes outlive expiresAt
		for _, event in world.outbox do
			expect(event.type ~= "Drained").toBe(true)
		end
	end)
	it("buy: a priced lane slime is charged on grab, then deposited off the lane for good", function()
		local world, id = laneWorld()
		local s = ServerFixtures.join(world, 1, nil, 100)
		world.wild[id].price = 60
		expect((Carry.grab(world, 1, id, 3, T0 + LIFE - 3))).toBe(true) -- in the countdown, beside the drain
		expect(s.data.cash).toBe(40)
		expect((Carry.deposit(world, 1))).toBe(true)
		expect(world.wild[id]).toBe(nil)
		expect(world.carriedBy[id]).toBe(nil)
		expect(Scene.describe(world, T0 + LIFE)[id].state).toBe("Pad")
	end)
	it("steal: first grabber wins, the dropped slime leaves the lane and the rival grabs it there", function()
		local world, id = laneWorld()
		ServerFixtures.join(world, 1, nil, 0)
		ServerFixtures.join(world, 2, nil, 0)
		world.wild[id].price = 0
		expect((Carry.grab(world, 1, id, 3, T0 + 20))).toBe(true)
		local ok, reason = Carry.grab(world, 2, id, 3, T0 + 20)
		expect(ok).toBe(false)
		expect(reason).toBe("someone is already carrying it")
		-- dropped by the plot gate: it stays there (fresh lifetime), off the lane
		expect(Carry.release(world, 1, T0 + 25, "dropped-at-gate", "drop")).toBe(true)
		local wild = world.wild[id]
		expect(wild.position).toBe("dropped-at-gate")
		expect(wild.expiresAt).toBe(T0 + 25 + LIFE)
		expect(ParadeLane.onLane(wild, false)).toBe(false)
		expect((Carry.grab(world, 2, id, 3, T0 + 26))).toBe(true)
		expect(world.carriedBy[id]).toBe(2)
	end)
	it("a grab after the slime drained finds it gone", function()
		local world, id = laneWorld()
		ServerFixtures.join(world, 1, nil, 0)
		Spawner.step(world, T0 + LIFE)
		local ok, reason = Carry.grab(world, 1, id, 3, T0 + LIFE)
		expect(ok).toBe(false)
		expect(reason).toBe("slime is gone")
	end)
end)

describe("ParadeLane: handoff to the goo drain", function()
	it("the lane ends just outside the curb; the drain slide crosses the lip and sinks at the centre", function()
		local E = T0 + LIFE
		local start = ParadeLane.pose(T0, E, 0, E - ParadeLane.DRAIN_SECONDS).position
		expect(hdist(start[1], start[3], ParadeLane.EXIT[1], ParadeLane.EXIT[2]) < 1e-6).toBe(true)
		local crossed = false
		for f = 0, ParadeLane.DRAIN_SECONDS * FPS do
			local pose = ParadeLane.pose(T0, E, 0, E - ParadeLane.DRAIN_SECONDS + f / FPS)
			local p = pose.position
			local r = hdist(p[1], p[3], DRAIN.x, DRAIN.z)
			if r <= DRAIN.lipRadius + 1e-6 then
				crossed = true
				-- inside the curb: never below the plaza until it's past the lip's inner edge (3.3)
				if r > 3.3 then
					expect(p[2] >= DRAIN.lipY - 0.1).toBe(true)
				end
			end
		end
		expect(crossed).toBe(true)
		local done = ParadeLane.pose(T0, E, 0, E)
		expect(done.phase).toBe("Gone")
		expect(hdist(done.position[1], done.position[3], DRAIN.x, DRAIN.z) < 1e-6).toBe(true)
		expect(done.position[2]).toBeCloseTo(DRAIN.sinkY, 1e-9)
		expect(DRAIN.sinkY < 0).toBe(true)
	end)
	it("lateral offset folds into the drain: every slime ends in the funnel", function()
		for _, lateral in { -ParadeLane.SPREAD / 2, ParadeLane.SPREAD / 2 } do
			local p = ParadeLane.pose(T0, T0 + LIFE, lateral, T0 + LIFE).position
			expect(hdist(p[1], p[3], DRAIN.x, DRAIN.z) < 1e-6).toBe(true)
		end
	end)
	it("Spawner removes a lane slime at expiresAt (not before) and emits Drained once", function()
		local world = ServerFixtures.world()
		local id = Spawner.spawnOne(world, T0)
		Spawner.step(world, T0 + LIFE - 0.01)
		expect(world.wild[id] ~= nil).toBe(true)
		table.clear(world.outbox)
		Spawner.step(world, T0 + LIFE)
		expect(world.wild[id]).toBe(nil)
		Spawner.step(world, T0 + LIFE + 0.5)
		local drained = 0
		for _, event in world.outbox do
			if event.type == "Drained" then
				drained += 1
				expect(event.slimeId).toBe(id)
			end
		end
		expect(drained).toBe(1)
	end)
	it("a dropped slime expires where it lies: no Drained, no splash", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1, nil, 0)
		local id = Spawner.spawnOne(world, T0)
		world.wild[id].price = 0
		Carry.grab(world, 1, id, 3, T0 + 10)
		Carry.release(world, 1, T0 + 12, "here", "drop")
		table.clear(world.outbox)
		Spawner.step(world, T0 + 12 + LIFE)
		expect(world.wild[id]).toBe(nil)
		for _, event in world.outbox do
			expect(event.type ~= "Drained").toBe(true)
		end
	end)
	it("Spawner keeps the Fountain.roll angle / radius (same rng stream, lateral offset source)", function()
		local world = ServerFixtures.world()
		local id = Spawner.spawnOne(world, T0)
		local wild = world.wild[id]
		local angle, radius = wild.angle, wild.radius
		expect(radius >= Fountain.MIN_RADIUS and radius <= Fountain.MAX_RADIUS).toBe(true)
		for t = T0, T0 + LIFE - 1, 5 do
			Spawner.step(world, t)
		end
		expect(wild.angle).toBe(angle)
		expect(wild.radius).toBe(radius)
	end)
	it("the flag is on, and off reads as off", function()
		expect(Config.FEATURES.Parade).toBe(true)
		expect(ParadeLane.enabled()).toBe(true)
		expect(ParadeLane.enabled({ Parade = false })).toBe(false)
		expect(ParadeLane.enabled({})).toBe(false)
	end)
end)

describe("ParadeLane: the despawn telegraph stays readable", function()
	it("the countdown opens while the slime still walks the lane, beside the drain", function()
		local W = ParadeLane.WARN_SECONDS
		expect(W).toBe(Config.DESPAWN_TELEGRAPH_SECONDS)
		expect(W >= ParadeLane.DRAIN_SECONDS + 2).toBe(true) -- 2 s+ of "leaving!" on the lane first
		local E = T0 + LIFE
		local pose = ParadeLane.pose(T0, E, 0, E - W)
		expect(pose.phase).toBe("Walk")
		local p = pose.position
		expect(hdist(p[1], p[3], DRAIN.x, DRAIN.z) < 40).toBe(true)
		expect(ParadeLane.inWarnWindow(E - W, E)).toBe(true)
		expect(ParadeLane.inWarnWindow(E - W - 0.01, E)).toBe(false)
	end)
	it("lane slimes get DespawnAt in the window, carried ones don't", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1, nil, 0)
		local a = Spawner.spawnOne(world, T0)
		local b = Spawner.spawnOne(world, T0)
		world.wild[b].price = 0
		Carry.grab(world, 1, b, 3, T0 + 1)
		local now = T0 + LIFE - 2
		local entries = Scene.describe(world, now)
		expect(entries[a].despawnAt).toBe(T0 + LIFE)
		expect(entries[b].despawnAt).toBe(nil)
		expect(Scene.describe(world, T0 + 30)[a].despawnAt).toBe(nil)
	end)
	it("consecutive drops are far apart on the lane, so countdowns never stack", function()
		local gap = ParadeLane.distance(T0, T0 + LIFE, T0 + 40)
			- ParadeLane.distance(T0 + Config.SPAWN_INTERVAL, T0 + Config.SPAWN_INTERVAL + LIFE, T0 + 40)
		-- two of the biggest slimes between neighbours (slower pace, C9: the drops sit closer on the lane)
		expect(gap >= 4 * ParadeLane.SLIME_RADIUS).toBe(true)
		expect(gap).toBeCloseTo(Config.SPAWN_INTERVAL * ParadeLane.walkSpeed(LIFE), 1e-6)
		-- at most two countdowns at once at the normal cadence
		expect(math.ceil(ParadeLane.WARN_SECONDS / Config.SPAWN_INTERVAL) <= 2).toBe(true)
	end)
	it("no despawn text helper: nothing says leaving!", function()
		expect(rawget(ParadeLane :: any, "warnText")).toBeNil()
	end)
end)

-- The real server: lane laid at boot, wilds tracked at 15 Hz to past the
-- first expiry, one grabbed live by a fake player through its prompt.
local placePath = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-parade-{os.time()}-{math.random(1, 1e9)}.rbxlx`
local built = process.exec("rojo", { "build", "-o", placePath })
assert(built.ok, `rojo build failed: {built.stderr}`)
local rt = Runtime.new(placePath, {
	createMeshPart = function(_meshId)
		return roblox.Instance.new("MeshPart")
	end,
})
fs.removeFile(placePath)
rt:boot()
local player = rt:addPlayer(901, "Parader", roblox.Vector3.new(0, 5, -200))
local HZ = 15
local SIM = LIFE + 6
local tracks = {}
local splashes = {}
local grab = nil
for _ = 1, SIM * HZ do
	rt:step(1 / HZ)
	local folder = rt.workspace:FindFirstChild("WildSlimes")
	local seen = {}
	for _, model in (if folder then folder:GetChildren() else {}) do
		local p = model:GetPivot().Position
		local track = tracks[model] or { born = rt.T, frames = {}, gone = nil }
		tracks[model] = track
		seen[model] = true
		table.insert(track.frames, { t = rt.T, p = { p.X, p.Y, p.Z }, state = model:GetAttribute("State") })
	end
	for model, track in tracks do
		if not seen[model] and not track.gone then
			track.gone = rt.T
		end
	end
	local splash = rt.workspace:FindFirstChild("DrainSplash")
	if splash and not splashes[splash] then
		splashes[splash] = rt.T
	end
	-- Live grab: at 30 s walk up to the second slime on the lane and press E.
	if not grab and rt.T >= 30 then
		local candidates = {}
		for model, track in tracks do
			if not track.gone and track.born < 10 then
				table.insert(candidates, { model = model, born = track.born })
			end
		end
		table.sort(candidates, function(x, y)
			return x.born < y.born
		end)
		local target = candidates[2]
		if target then
			local body = target.model.PrimaryPart
			player.Character.HumanoidRootPart.CFrame =
				roblox.CFrame.new(body.CFrame.Position + roblox.Vector3.new(2, 2, 0))
			body:FindFirstChild("GrabPrompt").Triggered:Fire(player)
			grab = { model = target.model, at = rt.T }
		end
	end
end

describe("ParadeLane in the live server", function()
	it("boots clean and lays Map.Plaza.ParadeLane: one walk-through goo strip per simplified lane segment", function()
		expect(#rt.errors).toBe(0)
		local lane = rt.workspace.Map.Plaza:FindFirstChild("ParadeLane")
		expect(lane ~= nil).toBe(true)
		local parts = lane:GetChildren()
		expect(#parts).toBe(#ParadeLane.drawPoints() - 1)
		for _, part in parts do
			expect(part.Anchored).toBe(true)
			expect(part.CanCollide).toBe(false)
			expect(part.CanQuery).toBe(false)
			expect(part.CanTouch).toBe(false)
			local top = part.CFrame.Position.Y + part.Size.Y / 2
			expect(top >= ParadeLane.LANE_Y - 1e-3 and top <= ParadeLane.LANE_Y + ParadeLane.STRIP_STEP + 1e-3).toBe(
				true
			)
		end
	end)
	it("walking slimes follow the lane: on the centreline band, hopping, never teleporting", function()
		local checked = 0
		for model, track in tracks do
			if model ~= (grab and grab.model) then
				for i, f in track.frames do
					local age = f.t - track.born
					if age > HOP + 0.3 and age < LIFE - ParadeLane.DRAIN_SECONDS - 0.3 then
						checked += 1
						local cx, cz = ParadeLane.pointAt(ParadeLane.distance(track.born, track.born + LIFE, f.t))
						expect(hdist(f.p[1], f.p[3], cx, cz) <= ParadeLane.SPREAD / 2 + 1.5).toBe(true)
						expect(f.p[2] >= ParadeLane.LANE_Y - 1e-3).toBe(true)
						expect(f.p[2] <= ParadeLane.LANE_Y + ParadeLane.HOP_HEIGHT + 1e-3).toBe(true)
					end
					if i > 1 and age > HOP + 0.1 then -- the frame the slide ends on still moves at slide speed
						local q = track.frames[i - 1].p
						local step = math.sqrt((f.p[1] - q[1]) ^ 2 + (f.p[2] - q[2]) ^ 2 + (f.p[3] - q[3]) ^ 2)
						expect(step <= FountainRide.RUN_SPEED / HZ + 1e-3).toBe(true)
					end
				end
			end
		end
		expect(checked > 500).toBe(true)
	end)
	it("lane position is time left: slimes born 4 s apart walk 4 s of lane apart", function()
		local first, second = nil, nil
		for model, track in tracks do
			if model ~= (grab and grab.model) and track.born < 12 then
				if not first or track.born < first.born then
					second = first
					first = track
				elseif not second or track.born < second.born then
					second = track
				end
			end
		end
		expect(first ~= nil and second ~= nil).toBe(true)
		local at = 40
		local function frameAt(track)
			for _, f in track.frames do
				if f.t >= at then
					return f
				end
			end
			return nil
		end
		-- each is where its own time left says (server time = born time within a reconcile tick)
		for _, track in { first, second } do
			local f = frameAt(track)
			local s = ParadeLane.distance(track.born, track.born + LIFE, f.t)
			local x, z = ParadeLane.pointAt(s)
			local tol = ParadeLane.SPREAD / 2
				+ 0.1 * (ParadeLane.LEAD_LENGTH + ParadeLane.LENGTH) / (LIFE - HOP - ParadeLane.DRAIN_SECONDS)
				+ 0.2
			expect(hdist(f.p[1], f.p[3], x, z) <= tol).toBe(true)
		end
	end)
	it("a live grab takes the slime off the lane into the player's arms", function()
		expect(grab ~= nil).toBe(true)
		local track = tracks[grab.model]
		local after = nil
		for _, f in track.frames do
			if f.t >= grab.at + 0.5 then
				after = f
				break
			end
		end
		expect(after.state).toBe("Carried")
		expect(track.gone).toBe(nil) -- carried past its expiry, not drained
	end)
	it("the first slimes slide into the drain at expiry, then go, with a DrainSplash at the drain", function()
		local drained = 0
		for model, track in tracks do
			if track.gone and model ~= (grab and grab.model) then
				drained += 1
				local life = track.gone - track.born
				expect(math.abs(life - LIFE) <= 0.3).toBe(true)
				local last = track.frames[#track.frames].p
				expect(hdist(last[1], last[3], DRAIN.x, DRAIN.z) <= DRAIN.lipRadius).toBe(true)
				local splashed = false
				for _, at in splashes do
					if math.abs(at - track.gone) <= 0.3 then
						splashed = true
					end
				end
				expect(splashed).toBe(true)
			end
		end
		expect(drained >= 1).toBe(true)
	end)
end)
