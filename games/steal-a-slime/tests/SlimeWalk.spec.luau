--!nocheck
-- The slime walk (contract/slime-walk.md): lane slimes glide with a heading that turns smoothly, and a dropped wild
-- slime walks back to the nearest point of the lane at its lane pace, then rejoins the flow with its lifetime kept.
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Fountain = require("../src/shared/Fountain")
local ParadeLane = require("../src/shared/ParadeLane")
local Scene = require("../src/server/Scene")
local ServerFixtures = require("./ServerFixtures")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local LIFE = Config.WILD_LIFETIME
local FPS = 30

local function hdist(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

-- A spot `out` studs outside the lane centreline at lane distance `s` (away from the fountain side).
local function offLane(s: number, out: number): (number, number)
	return ParadeLane.offsetAt(s, -out)
end

local function spot(x: number, z: number)
	return { X = x, Y = 0, Z = z }
end

describe("ParadeLane.nearest", function()
	it("finds the lane distance of a point on the centreline", function()
		for _, s in { 0, 12.5, ParadeLane.LENGTH / 3, ParadeLane.LENGTH / 2, ParadeLane.LENGTH - 1 } do
			local x, z = ParadeLane.pointAt(s)
			local found, gap = ParadeLane.nearest(x, z)
			expect(math.abs(found - s) < 1e-6).toBe(true)
			expect(gap < 1e-6).toBe(true)
		end
	end)
	it("a point off to the side maps to the lane point beside it, at that distance", function()
		local s = ParadeLane.LENGTH / 2
		local x, z = offLane(s, 10)
		local found, gap = ParadeLane.nearest(x, z)
		expect(math.abs(found - s) < 1.5).toBe(true)
		expect(math.abs(gap - 10) < 0.5).toBe(true)
	end)
	it("never answers the lead-in: a spot by the slide mouth maps to the lane (s >= 0)", function()
		local mx, mz = ParadeLane.pointAt(-ParadeLane.LEAD_LENGTH)
		local found = ParadeLane.nearest(mx, mz)
		expect(found >= 0 and found <= ParadeLane.LENGTH).toBe(true)
	end)
end)

describe("ParadeLane glide: steady pace, smooth turns", function()
	it("the heading turns at most a few degrees per frame anywhere on the lane", function()
		local speed = ParadeLane.walkSpeed(LIFE)
		local step = speed / FPS
		local _, _, px, pz = ParadeLane.pointAt(0)
		local worst = 0
		for s = step, ParadeLane.LENGTH, step do
			local _, _, hx, hz = ParadeLane.pointAt(s)
			local turn = math.acos(math.clamp(hx * px + hz * pz, -1, 1))
			worst = math.max(worst, turn)
			px, pz = hx, hz
		end
		expect(math.deg(worst) < 2).toBe(true)
	end)
	it("covers equal lane distance in equal time (a steady pace)", function()
		local E = T0 + LIFE
		local a = ParadeLane.distance(T0, E, T0 + 20)
		local b = ParadeLane.distance(T0, E, T0 + 30)
		local c = ParadeLane.distance(T0, E, T0 + 40)
		expect(b - a).toBeCloseTo(c - b, 1e-6)
	end)
end)

describe("ParadeLane.returnPlan / returnPose: the walk back", function()
	local lateral = 0.8
	local s0 = ParadeLane.LENGTH / 2
	local dropX, dropZ = offLane(s0, 20)
	local plan = ParadeLane.returnPlan(dropX, dropZ, lateral, LIFE, T0)

	it("starts at the drop spot after RETURN_DELAY and walks at the slime's lane pace", function()
		expect(plan.startAt).toBeCloseTo(T0 + ParadeLane.RETURN_DELAY, 1e-9)
		expect(plan.speed).toBeCloseTo(ParadeLane.walkSpeed(LIFE), 1e-9)
		for _, t in { T0, plan.startAt } do
			local x, z = ParadeLane.returnPose(plan, t)
			expect(hdist(x, z, dropX, dropZ) < 1e-6).toBe(true)
		end
		-- the walk takes its arc length at that speed, plus half the ease-in
		local walk = plan.arriveAt - plan.startAt
		expect(walk).toBeCloseTo(plan.length / plan.speed + ParadeLane.RETURN_EASE / 2, 1e-6)
		expect(plan.length >= 20 - 1e-6).toBe(true)
	end)
	it("heads for the nearest lane point and merges onto the slime's own line just ahead of it", function()
		local near = ParadeLane.nearest(dropX, dropZ)
		local nx, nz = ParadeLane.offsetAt(near, lateral)
		expect(hdist(plan.x1, plan.z1, nx, nz) < 1e-6).toBe(true)
		expect(plan.s > near and plan.s <= near + ParadeLane.RETURN_MERGE + 1e-9).toBe(true)
		local mx, mz = ParadeLane.offsetAt(plan.s, lateral)
		local ex, ez = ParadeLane.returnPose(plan, plan.arriveAt)
		expect(hdist(ex, ez, mx, mz) < 1e-6).toBe(true)
		-- first step: towards the nearest lane point
		local _, _, hx, hz = ParadeLane.returnPose(plan, plan.startAt)
		local dx, dz = nx - dropX, nz - dropZ
		local len = math.sqrt(dx * dx + dz * dz)
		expect(hx * dx / len + hz * dz / len > 0.99).toBe(true)
		-- last step: along the lane
		local _, _, ax, az = ParadeLane.returnPose(plan, plan.arriveAt)
		local _, _, lx, lz = ParadeLane.pointAt(plan.s)
		expect(ax * lx + az * lz > 0.98).toBe(true)
	end)
	it("walks smoothly: no step faster than its pace, the heading never snaps, it never stops on the way", function()
		local px, pz, phx, phz = ParadeLane.returnPose(plan, plan.startAt)
		local frames = math.ceil((plan.arriveAt - plan.startAt) * FPS)
		for f = 1, frames do
			local t = plan.startAt + f / FPS
			local x, z, hx, hz = ParadeLane.returnPose(plan, t)
			local step = hdist(x, z, px, pz)
			expect(step <= plan.speed / FPS * 1.05).toBe(true) -- 5 %: the chord-to-curve parameter is not quite uniform
			if t > plan.startAt + ParadeLane.RETURN_EASE and t < plan.arriveAt then
				expect(step > plan.speed / FPS * 0.9).toBe(true)
			end
			expect(math.deg(math.acos(math.clamp(hx * phx + hz * phz, -1, 1))) < 6).toBe(true)
			px, pz, phx, phz = x, z, hx, hz
		end
	end)
	it(
		"arrives facing and moving like a lane slime: rejoin puts the lane pose on the merge point at arriveAt",
		function()
			local spawnedAt, expiresAt = ParadeLane.rejoin(plan.s, LIFE, plan.arriveAt)
			expect(expiresAt - spawnedAt).toBeCloseTo(LIFE, 1e-9)
			expect(ParadeLane.distance(spawnedAt, expiresAt, plan.arriveAt)).toBeCloseTo(plan.s, 1e-6)
			local pose = ParadeLane.pose(spawnedAt, expiresAt, lateral, plan.arriveAt)
			local x, z = ParadeLane.returnPose(plan, plan.arriveAt)
			expect(hdist(pose.position[1], pose.position[3], x, z) < 1e-6).toBe(true)
			-- the next lane frame is one lane-pace step on: no jump at the hand-over
			local nextPose = ParadeLane.pose(spawnedAt, expiresAt, lateral, plan.arriveAt + 1 / FPS)
			local step = hdist(nextPose.position[1], nextPose.position[3], x, z)
			expect(step <= plan.speed / FPS * 1.2 + 1e-6).toBe(true)
		end
	)
	it("a drop inside the landing ring band starts just outside it (Fountain.clearOfRing)", function()
		local r = (Fountain.RING_BAND_INNER + Fountain.MIN_RADIUS) / 2
		local inner = ParadeLane.returnPlan(r, 0, 0, LIFE, T0)
		expect(hdist(inner.fromX, inner.fromZ, 0, 0)).toBeCloseTo(Fountain.MIN_RADIUS, 1e-6)
	end)
	it("dropped right on its lane line: it merges where it stands", function()
		local x, z = ParadeLane.offsetAt(s0, lateral)
		local onLine = ParadeLane.returnPlan(x, z, lateral, LIFE, T0)
		expect(onLine.length < 0.5).toBe(true)
		local _, _, hx, hz = ParadeLane.returnPose(onLine, onLine.startAt)
		expect(math.abs(math.sqrt(hx * hx + hz * hz) - 1) < 1e-6).toBe(true)
	end)
	it("near the drain end the merge point is clamped to the lane's end", function()
		local x, z = offLane(ParadeLane.LENGTH - 1, 12)
		local late = ParadeLane.returnPlan(x, z, 0, LIFE, T0)
		expect(late.s <= ParadeLane.LENGTH + 1e-9).toBe(true)
	end)
end)

describe("Carry.release + Spawner: a dropped wild slime walks back and rejoins the lane", function()
	local function carried()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1, nil, 0)
		local id = Spawner.spawnOne(world, T0)
		world.wild[id].price = 0
		expect((Carry.grab(world, 1, id, 3, T0 + 20))).toBe(true)
		return world, id
	end

	it("a drop with a world spot plans the walk and keeps the slime's lifetime", function()
		local world, id = carried()
		local x, z = offLane(ParadeLane.LENGTH / 3, 15)
		expect(Carry.release(world, 1, T0 + 25, spot(x, z), "drop")).toBe(true)
		local wild = world.wild[id]
		local plan = wild.returning
		expect(plan ~= nil).toBe(true)
		expect(plan.startAt).toBeCloseTo(T0 + 25 + ParadeLane.RETURN_DELAY, 1e-9)
		expect(wild.expiresAt - wild.spawnedAt).toBeCloseTo(Fountain.wildLifetime(wild.slime), 1e-9)
		expect(ParadeLane.distance(wild.spawnedAt, wild.expiresAt, plan.arriveAt)).toBeCloseTo(plan.s, 1e-6)
		expect(ParadeLane.onLane(wild, false)).toBe(false)
		local entry = Scene.describe(world, T0 + 26)[id]
		expect(entry.state).toBe("Wild")
		expect(entry.promptEnabled).toBe(true)
	end)
	it("while it walks it is off the lane; at arriveAt Spawner puts it back on and it walks on from there", function()
		local world, id = carried()
		local x, z = offLane(ParadeLane.LENGTH / 3, 15)
		Carry.release(world, 1, T0 + 25, spot(x, z), "drop")
		local wild = world.wild[id]
		local plan = wild.returning
		Spawner.step(world, plan.arriveAt - 0.05)
		expect(wild.returning).toBe(plan)
		expect(wild.position ~= nil).toBe(true)
		Spawner.step(world, plan.arriveAt)
		expect(wild.returning).toBe(nil)
		expect(wild.position).toBe(nil)
		expect(ParadeLane.onLane(wild, false)).toBe(true)
		-- and on along the lane, forwards, at the lane pace
		local a = ParadeLane.distance(wild.spawnedAt, wild.expiresAt, plan.arriveAt + 1)
		expect(a - plan.s).toBeCloseTo(ParadeLane.walkSpeed(LIFE), 1e-6)
	end)
	it("it drains at the end of the lane like any lane slime (Drained once)", function()
		local world, id = carried()
		local x, z = offLane(ParadeLane.LENGTH - 20, 10)
		Carry.release(world, 1, T0 + 25, spot(x, z), "drop")
		local wild = world.wild[id]
		local plan = wild.returning
		Spawner.step(world, plan.arriveAt)
		expect(wild.expiresAt > plan.arriveAt).toBe(true)
		table.clear(world.outbox)
		Spawner.step(world, wild.expiresAt)
		expect(world.wild[id]).toBe(nil)
		local drained = 0
		for _, event in world.outbox do
			if event.type == "Drained" then
				drained += 1
			end
		end
		expect(drained).toBe(1)
	end)
	it("grabbing it mid-walk ends the walk; dropping it again plans a new one", function()
		local world, id = carried()
		local x, z = offLane(ParadeLane.LENGTH / 3, 30)
		Carry.release(world, 1, T0 + 25, spot(x, z), "drop")
		local first = world.wild[id].returning
		ServerFixtures.join(world, 2, nil, 0)
		expect((Carry.grab(world, 2, id, 3, T0 + 28))).toBe(true)
		expect(world.wild[id].returning).toBe(nil)
		Spawner.step(world, first.arriveAt + 1) -- a carried slime is never put back on the lane
		expect(world.wild[id].position ~= nil).toBe(true)
		local x2, z2 = offLane(ParadeLane.LENGTH / 2, 8)
		Carry.release(world, 2, T0 + 40, spot(x2, z2), "slap")
		local second = world.wild[id].returning
		expect(second ~= nil and second ~= first).toBe(true)
		expect(second.startAt).toBeCloseTo(T0 + 40 + ParadeLane.RETURN_DELAY, 1e-9)
	end)
	it("a drop off the map (over the void) does not walk: it keeps the fountain-spot rule", function()
		expect(ParadeLane.returnPlan(3000, 3000, 0, LIFE, T0)).toBe(nil)
		-- the farthest corner of the ground still walks
		expect(ParadeLane.returnPlan(320, 320, 0, LIFE, T0) ~= nil).toBe(true)
		local world, id = carried()
		Carry.release(world, 1, T0 + 25, spot(3000, 3000), "drop")
		expect(world.wild[id].returning).toBe(nil)
		expect(world.wild[id].expiresAt).toBe(T0 + 25 + LIFE)
	end)
	it("a drop without a world spot rests where it was put with a fresh lifetime (no walk)", function()
		local world, id = carried()
		Carry.release(world, 1, T0 + 25, "here", "drop")
		local wild = world.wild[id]
		expect(wild.returning).toBe(nil)
		expect(wild.expiresAt).toBe(T0 + 25 + LIFE)
	end)
end)

-- The walk back along the server's path (ParadeLane.reroute / Carry.reroute).
local LATERAL = 0.5

local function carried()
	local world = ServerFixtures.world()
	ServerFixtures.join(world, 1, nil, 0)
	local id = Spawner.spawnOne(world, T0)
	world.wild[id].price = 0
	expect((Carry.grab(world, 1, id, 3, T0 + 20))).toBe(true)
	return world, id
end

local function planned()
	local x, z = offLane(ParadeLane.LENGTH / 2, 40)
	return ParadeLane.returnPlan(x, z, LATERAL, LIFE, T0)
end

-- A detour round something in the way: 20 studs sideways, forwards, then back onto the straight line.
local function detour(plan)
	local fx, fz = plan.fromX, plan.fromZ
	local dx, dz = plan.x1 - fx, plan.z1 - fz
	local len = math.sqrt(dx * dx + dz * dz)
	local ux, uz = dx / len, dz / len
	local sx, sz = -uz * 20, ux * 20
	return {
		fx + sx,
		fz + sz,
		fx + sx + ux * len * 0.7,
		fz + sz + uz * len * 0.7,
		fx + ux * len * 0.85,
		fz + uz * len * 0.85,
	}
end

describe("ParadeLane.reroute: the walk back along the server's path", function()
	it("walks every route point in order at a steady pace, then merges onto the lane at the same point", function()
		local plan = planned()
		local path = detour(plan)
		local walk = ParadeLane.reroute(plan, path)
		expect(walk.startAt).toBe(plan.startAt)
		expect(walk.s).toBe(plan.s)
		expect(walk.length > plan.length + 20).toBe(true)
		expect(walk.arriveAt - walk.startAt).toBeCloseTo(walk.length / walk.speed + ParadeLane.RETURN_EASE / 2, 1e-6)
		local x0, z0 = ParadeLane.returnPose(walk, walk.startAt)
		expect(hdist(x0, z0, plan.fromX, plan.fromZ) < 1e-6).toBe(true)
		local nextPoint, px, pz = 1, x0, z0
		for t = walk.startAt, walk.arriveAt, 1 / FPS do
			local x, z = ParadeLane.returnPose(walk, t)
			expect(hdist(x, z, px, pz) <= walk.speed / FPS * 1.05).toBe(true) -- never a jump (Bezier chords: within 5%)
			px, pz = x, z
			if nextPoint <= #path and hdist(x, z, path[nextPoint], path[nextPoint + 1]) < walk.speed / FPS then
				nextPoint += 2
			end
		end
		expect(nextPoint).toBe(#path + 1)
		local ex, ez = ParadeLane.returnPose(walk, walk.arriveAt)
		local mx, mz = ParadeLane.offsetAt(walk.s, LATERAL)
		expect(hdist(ex, ez, mx, mz) < 1e-6).toBe(true)
	end)
	it("turns smoothly round the route's corners", function()
		local plan = planned()
		local walk = ParadeLane.reroute(plan, detour(plan))
		local _, _, phx, phz = ParadeLane.returnPose(walk, walk.startAt)
		for t = walk.startAt, walk.arriveAt, 1 / FPS do
			local _, _, hx, hz = ParadeLane.returnPose(walk, t)
			local turn = math.deg(math.acos(math.clamp(hx * phx + hz * phz, -1, 1)))
			expect(turn < 12).toBe(true)
			phx, phz = hx, hz
		end
	end)
	it("an empty route leaves the plan as it was", function()
		local plan = planned()
		expect(ParadeLane.reroute(plan, {})).toBe(plan)
	end)
end)

describe("Carry.reroute: the server's path swapped into a dropped slime's walk", function()
	it("Carry.reroute swaps the walk in once, and its lane times follow the longer walk", function()
		local world, id = carried()
		local x, z = offLane(ParadeLane.LENGTH / 3, 30)
		Carry.release(world, 1, T0 + 25, spot(x, z), "drop")
		local wild = world.wild[id]
		local plan = wild.returning
		expect(Carry.reroute(world, id, plan.startAt, detour(plan), T0 + 25.2)).toBe(true)
		local walk = wild.returning
		expect(walk.route ~= nil and walk.arriveAt > plan.arriveAt).toBe(true)
		expect(wild.expiresAt - wild.spawnedAt).toBeCloseTo(Fountain.wildLifetime(wild.slime), 1e-9)
		expect(ParadeLane.distance(wild.spawnedAt, wild.expiresAt, walk.arriveAt)).toBeCloseTo(walk.s, 1e-6)
		expect(Carry.reroute(world, id, plan.startAt, detour(plan), T0 + 25.3)).toBe(false)
		Spawner.step(world, plan.arriveAt + 0.01)
		expect(wild.returning).toBe(walk) -- still on its longer path
		Spawner.step(world, walk.arriveAt)
		expect(wild.returning).toBe(nil)
		expect(ParadeLane.onLane(wild, false)).toBe(true)
	end)
	it("Carry.reroute ignores a stale path: another walk, well under way, grabbed again, or gone", function()
		local world, id = carried()
		local x, z = offLane(ParadeLane.LENGTH / 3, 30)
		Carry.release(world, 1, T0 + 25, spot(x, z), "drop")
		local plan = world.wild[id].returning
		local path = detour(plan)
		expect(Carry.reroute(world, id, plan.startAt - 1, path, T0 + 25.2)).toBe(false)
		expect(Carry.reroute(world, id, plan.startAt, path, plan.startAt + ParadeLane.REROUTE_GRACE + 0.01)).toBe(false)
		expect(world.wild[id].returning).toBe(plan)
		ServerFixtures.join(world, 2, nil, 0)
		expect((Carry.grab(world, 2, id, 3, T0 + 25.3))).toBe(true)
		expect(Carry.reroute(world, id, plan.startAt, path, T0 + 25.4)).toBe(false)
		expect(Carry.reroute(world, "nobody", plan.startAt, path, T0 + 25.4)).toBe(false)
	end)
end)
