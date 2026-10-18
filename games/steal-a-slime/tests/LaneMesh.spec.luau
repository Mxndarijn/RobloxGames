--!nocheck
-- The goo lane as ONE smooth kit mesh (models/slime_lane.py -> MeshAssets "slime_lane", bug 4): the game's pivot / size
-- match what the model script wrote (shared/modeling-kit/out/slime_lane_pivot.json), the sampled centreline starts at the
-- slide mouth and follows every walk waypoint, the crown is LANE_Y and no edge is above the ground, and the mesh footprint
-- clears the fountain barrel and the slide colliders. The strips (ParadeLane.strips) stay as the fallback until the upload.
local Config = require("../src/shared/Config")
local MeshAssets = require("../src/shared/MeshAssets")
local ParadeLane = require("../src/shared/ParadeLane")
local SlideColliders = require("../src/shared/SlideColliders")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local HW = ParadeLane.HALF_WIDTH
local info = serde.decode("json", fs.readFile("../../shared/modeling-kit/out/slime_lane_pivot.json"))
local C = info.centre

local function segmentDistance(x: number, z: number, a: { number }, b: { number }): number
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local len2 = math.max(dx * dx + dz * dz, 1e-12)
	local k = math.clamp(((x - a[1]) * dx + (z - a[2]) * dz) / len2, 0, 1)
	return math.sqrt((x - a[1] - dx * k) ^ 2 + (z - a[2] - dz * k) ^ 2)
end

local function distanceToCentre(x: number, z: number): number
	local best = math.huge
	for i = 1, #C - 1 do
		best = math.min(best, segmentDistance(x, z, C[i], C[i + 1]))
	end
	return best
end

-- Footprint samples: both edges and the centreline at every ring, with the left normal of the ring.
local function footprint(): { { number } }
	local out = {}
	-- ring 1 is the slide mouth itself: the lane starts inside the slide's last 0.3 studs by design
	for i = 2, #C do
		local a, b = C[math.max(1, i - 1)], C[math.min(#C, i + 1)]
		local dx, dz = b[1] - a[1], b[2] - a[2]
		local len = math.max(math.sqrt(dx * dx + dz * dz), 1e-9)
		for _, s in { -1, -0.5, 0, 0.5, 1 } do
			table.insert(out, { C[i][1] - dz / len * HW * s, C[i][2] + dx / len * HW * s })
		end
	end
	return out
end

local FOOT = footprint()

describe("slime lane mesh: what the game expects of the kit model", function()
	it("the pivot, size and mesh entry match the model script's output", function()
		for i = 1, 3 do
			expect(math.abs(ParadeLane.MESH_PIVOT[i] - info.pivot[i]) < 1e-3).toBe(true)
		end
		local entry = MeshAssets.get(ParadeLane.MESH)
		expect(entry ~= nil).toBe(true)
		for i = 1, 3 do
			expect(math.abs(entry.size[i] - info.size[i]) < 0.01).toBe(true)
		end
		expect(info.crownY).toBe(ParadeLane.LANE_Y)
		expect(info.halfWidth).toBe(HW)
		expect(info.edgeY).toBe(ParadeLane.EDGE_Y)
	end)
	it("is one mesh under the 10k kit limit, not a world slot (does not touch the 400 slot budget)", function()
		expect(table.find(MeshAssets.NAMES, ParadeLane.MESH)).toBe(nil)
		expect(#C > 100).toBe(true)
	end)
	it("top within 0.05 of LANE_Y; no edge above the ground", function()
		expect(math.abs(info.pivot[2] + info.size[2] / 2 - ParadeLane.LANE_Y) < 0.05).toBe(true)
		expect(info.edgeY <= 0).toBe(true)
		expect(info.pivot[2] - info.size[2] / 2 < 0).toBe(true)
	end)
	it("starts at the slide mouth, within 0.05 studs", function()
		local path = WorldLayout.SLIDE_PATH
		local mouth = path[#path]
		expect(math.abs(C[1][1] - mouth[1]) < 0.05).toBe(true)
		expect(math.abs(C[1][2] - mouth[3]) < 0.05).toBe(true)
	end)
	it(
		"follows the route: every waypoint and the drawn lead-in lie within 0.1 stud of the sampled centreline",
		function()
			-- up to the taper start: the mesh ends there (the drain strips draw the rest)
			local stop = ParadeLane.stripEndPoints()
			local from = stop[#stop]
			for _, p in ParadeLane.WAYPOINTS do
				expect(distanceToCentre(p[1], p[2]) < 0.1).toBe(true)
				if p == from then
					break
				end
			end
			for _, p in ParadeLane.LEAD do
				expect(distanceToCentre(p[1], p[2]) < 0.1).toBe(true)
			end
		end
	)
	it("ends where the drain taper starts, square to the lane, and the first taper strip laps the cut", function()
		local stop = ParadeLane.stripEndPoints()
		local from = stop[#stop]
		local last, before = C[#C], C[#C - 1]
		expect(math.abs(last[1] - from[1]) < 0.05 and math.abs(last[2] - from[2]) < 0.05).toBe(true)
		-- the mesh no longer reaches EXIT: it stops TAPER_START studs short (the taper strips draw the rest)
		local e = ParadeLane.EXIT
		local short = math.sqrt((last[1] - e[1]) ^ 2 + (last[2] - e[2]) ^ 2)
		expect(math.abs(short - ParadeLane.TAPER_START) < 1.2).toBe(true)
		-- the first taper strip starts TAPER_MESH_OVERLAP before the cut along its own heading
		local first = ParadeLane.drainStrips()[1]
		local c = first.cf
		local back = (last[1] - (c[1] - c[4] * first.length / 2)) * c[4]
			+ (last[2] - (c[3] - c[10] * first.length / 2)) * c[10]
		expect(back >= 0.2 and back <= 0.35).toBe(true)
		-- the last ring is the cut: the final segment keeps the lane's heading (square cut: rings are perpendicular to it)
		local dx, dz = last[1] - before[1], last[2] - before[2]
		local hx, hz = c[4], c[10]
		expect((dx * hx + dz * hz) / math.sqrt(dx * dx + dz * dz) > math.cos(math.rad(10))).toBe(true)
	end)
	it(
		"has no kink: the heading changes by under 20 degrees (the tightest route bends are r ~4, at 0.8-stud rings) between neighbouring rings",
		function()
			for i = 2, #C - 1 do
				local ax, az = C[i][1] - C[i - 1][1], C[i][2] - C[i - 1][2]
				local bx, bz = C[i + 1][1] - C[i][1], C[i + 1][2] - C[i][2]
				local cos = (ax * bx + az * bz)
					/ math.max(math.sqrt(ax * ax + az * az) * math.sqrt(bx * bx + bz * bz), 1e-9)
				expect(cos > math.cos(math.rad(20))).toBe(true)
			end
		end
	)
	it("its footprint clears the fountain barrel (r 14.5) and every upright volcano cylinder", function()
		local cylinders = {}
		for _, root in WorldLayout.build() do
			for _, node in root.children or {} do
				if node.name == "Volcano" then
					for _, part in node.children do
						if part.shape == "Cylinder" then
							table.insert(cylinders, part)
						end
					end
				end
			end
		end
		expect(#cylinders > 20).toBe(true)
		for _, cyl in cylinders do
			local lo, hi = cyl.pos[2] - cyl.size[1] / 2, cyl.pos[2] + cyl.size[1] / 2
			if hi < 0 or lo > ParadeLane.LANE_Y then
				continue
			end
			for _, p in FOOT do
				expect(math.sqrt((p[1] - cyl.pos[1]) ^ 2 + (p[2] - cyl.pos[3]) ^ 2) > cyl.size[2] / 2 + 0.25).toBe(true)
			end
		end
	end)
	it("its footprint clears every slide collider except the mouth's 0.25 touch", function()
		local checked = 0
		for _, spec in SlideColliders.build(WorldLayout.SLIDE_PATH, Config.FEATURES.SlideCollision) do
			local f = spec.forward
			local rx, rz = f[3] * 0 - f[2] * 0, 0 -- right = f x up = (-f.z, 0, f.x)
			rx, rz = -f[3], f[1]
			local len = math.sqrt(rx * rx + rz * rz)
			if len < 1e-6 then
				continue
			end
			rx, rz = rx / len, rz / len
			local hf, hr = spec.size[3] / 2, spec.size[1] / 2
			local fx, fz = f[1], f[3]
			local flen = math.max(math.sqrt(fx * fx + fz * fz), 1e-9)
			-- a footprint sample is inside when it is within the box's horizontal extent (inset by the 0.25 touch) and
			-- the box reaches the lane's height band (-0.05 .. LANE_Y)
			local lo = spec.centre[2] - spec.size[2] / 2 * math.abs(f[2] * 0 + 1)
			local hi = spec.centre[2] + spec.size[2] / 2
			if hi < -0.05 or lo > ParadeLane.LANE_Y then
				continue
			end
			for _, p in FOOT do
				checked += 1
				local dx, dz = p[1] - spec.centre[1], p[2] - spec.centre[3]
				local along = math.abs((dx * fx + dz * fz) / flen)
				local across = math.abs(dx * rx + dz * rz)
				expect(not (along < hf * flen - 0.25 and across < hr - 0.25)).toBe(true)
			end
		end
		expect(checked > 0).toBe(true)
	end)
end)
