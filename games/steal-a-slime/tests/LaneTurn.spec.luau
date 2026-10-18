--!nocheck
-- Bug 4b: the slime lane has no sharp turn. Same math as the live probe tools/pipeline/pc-watcher/luau/bug04_lane_smooth.luau:
-- the heading change between consecutive 2-stud chords of ParadeLane.drawPoints() (resampled every 2 studs) and of
-- ParadeLane.pointAt(s) (the walker route) stays under the probe's 20 degrees. The mesh centreline
-- (shared/modeling-kit/out/slime_lane_pivot.json, built from the same route points) must stay on the walker route.
local ParadeLane = require("../src/shared/ParadeLane")
local TestRunner = require("./TestRunner")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local STEP, LIMIT = 2, 20

local function maxTurn(points: { { number } }): number
	local worst, prev = 0, nil
	for i = 2, #points do
		local dx, dz = points[i][1] - points[i - 1][1], points[i][2] - points[i - 1][2]
		local m = math.sqrt(dx * dx + dz * dz)
		if m > 1e-4 then
			dx, dz = dx / m, dz / m
			if prev then
				worst = math.max(worst, math.deg(math.acos(math.clamp(prev[1] * dx + prev[2] * dz, -1, 1))))
			end
			prev = { dx, dz }
		end
	end
	return worst
end

local function resample(poly: { { number } }): { { number } }
	local out, carry = { poly[1] }, 0
	for i = 2, #poly do
		local a, b = poly[i - 1], poly[i]
		local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local at = STEP - carry
		while at <= len do
			table.insert(out, { a[1] + (b[1] - a[1]) * at / len, a[2] + (b[2] - a[2]) * at / len })
			at += STEP
		end
		carry = len - (at - STEP)
	end
	table.insert(out, poly[#poly])
	return out
end

local function walk(): { { number } }
	local out, s = {}, 0
	while s < ParadeLane.LENGTH do
		local x, z = ParadeLane.pointAt(s)
		table.insert(out, { x, z })
		s += STEP
	end
	local x, z = ParadeLane.pointAt(ParadeLane.LENGTH)
	table.insert(out, { x, z })
	return out
end

local function segmentDistance(x: number, z: number, a: { number }, b: { number }): number
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local k = math.clamp(((x - a[1]) * dx + (z - a[2]) * dz) / math.max(dx * dx + dz * dz, 1e-12), 0, 1)
	return math.sqrt((x - a[1] - dx * k) ^ 2 + (z - a[2] - dz * k) ^ 2)
end

describe("slime lane has no sharp turn (probe bug04_lane_smooth)", function()
	it("the drawn polyline turns under 20 degrees per 2 studs (target 12 or less, with margin)", function()
		expect(maxTurn(resample(ParadeLane.drawPoints())) < LIMIT).toBe(true)
		expect(maxTurn(resample(ParadeLane.drawPoints())) <= 13).toBe(true)
	end)
	it("the walker route (pointAt every 2 studs) turns under 20 degrees per 2 studs", function()
		expect(maxTurn(walk()) < LIMIT).toBe(true)
		expect(maxTurn(walk()) <= 13).toBe(true)
	end)
	it("starts on the slide mouth and ends at the drain approach", function()
		local d = ParadeLane.drawPoints()
		expect(d[1][1]).toBeCloseTo(ParadeLane.MOUTH[1], 1e-6)
		expect(d[1][2]).toBeCloseTo(ParadeLane.MOUTH[2], 1e-6)
		local x, z = ParadeLane.pointAt(ParadeLane.LENGTH)
		expect(x).toBeCloseTo(ParadeLane.EXIT[1], 1e-6)
		expect(z).toBeCloseTo(ParadeLane.EXIT[2], 1e-6)
	end)
	it("the mesh centreline stays within 0.3 studs of the walker route", function()
		local info = serde.decode("json", fs.readFile("../../shared/modeling-kit/out/slime_lane_pivot.json"))
		local C = info.centre
		-- the mesh stops where the drain taper starts (<= TAPER_START + 1.2 before EXIT, see LaneMesh.spec)
		for s = -ParadeLane.LEAD_LENGTH, ParadeLane.LENGTH - ParadeLane.TAPER_START - 1.2, 0.5 do
			local x, z = ParadeLane.pointAt(s)
			local best = math.huge
			for i = 1, #C - 1 do
				best = math.min(best, segmentDistance(x, z, C[i], C[i + 1]))
			end
			expect(best < 0.3).toBe(true)
		end
		-- and the other way: every mesh ring lies on the walker route (the route is a polyline of its own points)
		local route = {}
		for _, p in ParadeLane.LEAD do
			table.insert(route, p)
		end
		for _, p in ParadeLane.WAYPOINTS do
			table.insert(route, p)
		end
		for _, c in C do
			local best = math.huge
			for i = 1, #route - 1 do
				best = math.min(best, segmentDistance(c[1], c[2], route[i], route[i + 1]))
			end
			expect(best < 0.3).toBe(true)
		end
	end)
end)
