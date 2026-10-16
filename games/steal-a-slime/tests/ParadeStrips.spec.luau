--!nocheck
-- The goo lane strip (ParadeView.place) is drawn with fewer straight Parts than the route has
-- waypoint pairs (ParadeLane.stripPoints, Douglas-Peucker within STRIP_TOLERANCE). Checked here:
-- the part count (it was one Part per waypoint pair, 133), that the drawn coverage matches the
-- original strip union within the tolerance (both ways), and that the strips are still the same
-- non-colliding Glass goo with overlapping neighbours at distinct heights (no z-fighting).
local ParadeLane = require("../src/shared/ParadeLane")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local WIDTH = ParadeLane.HALF_WIDTH * 2
local TOL = ParadeLane.STRIP_TOLERANCE
local MAX_STRIPS = 52 -- was 133 (one per waypoint pair); only ever lower it

-- Footprint rectangles of a strip polyline, as ParadeView lays them (length + width / 2).
local function rects(points: { { number } })
	local out = {}
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local dx, dz = b[1] - a[1], b[2] - a[2]
		local len = math.sqrt(dx * dx + dz * dz)
		if len >= 1e-3 then
			table.insert(out, {
				mx = (a[1] + b[1]) / 2,
				mz = (a[2] + b[2]) / 2,
				ux = dx / len,
				uz = dz / len,
				half = (len + WIDTH / 2) / 2,
			})
		end
	end
	return out
end

-- Distance outside the union of rects (0 when inside any), each rect narrowed by `inset` on both sides.
local function outside(rs, x: number, z: number, inset: number): number
	local best = math.huge
	for _, r in rs do
		local ax = math.abs((x - r.mx) * r.ux + (z - r.mz) * r.uz) - r.half
		local lat = math.abs(-(x - r.mx) * r.uz + (z - r.mz) * r.ux) - (ParadeLane.HALF_WIDTH - inset)
		best = math.min(best, math.max(ax, lat, 0))
	end
	return best
end

local original = rects(ParadeLane.WAYPOINTS)
local simple = ParadeLane.stripPoints()
local drawn = rects(simple)

describe("ParadeLane goo strip parts", function()
	it("draws the lane with far fewer strips than waypoint pairs", function()
		expect(#ParadeLane.WAYPOINTS - 1).toBe(133)
		expect(#drawn <= MAX_STRIPS).toBe(true)
		expect(#drawn * 2 < #original).toBe(true)
	end)
	it("keeps the entry and exit of the route", function()
		expect(simple[1]).toBe(ParadeLane.ENTRY)
		expect(simple[#simple]).toBe(ParadeLane.EXIT)
	end)
	it("every route waypoint stays within the tolerance of the drawn polyline", function()
		for _, p in ParadeLane.WAYPOINTS do
			expect(outside(drawn, p[1], p[2], 0) == 0).toBe(true)
			-- the centreline is deep inside a strip: even shrunk by the tolerance it is covered
			expect(outside(drawn, p[1], p[2], ParadeLane.HALF_WIDTH - TOL - 0.05) == 0).toBe(true)
		end
	end)
	it("coverage matches the original strips both ways within the tolerance", function()
		local worstMissing, worstExtra = 0, 0
		for _, r in original do -- the original goo, sampled across and along each strip
			for u = -1, 1, 0.5 do
				for v = -1, 1, 0.5 do
					local x = r.mx + r.ux * r.half * u * 0.95 - r.uz * ParadeLane.HALF_WIDTH * v * 0.95
					local z = r.mz + r.uz * r.half * u * 0.95 + r.ux * ParadeLane.HALF_WIDTH * v * 0.95
					worstMissing = math.max(worstMissing, outside(drawn, x, z, 0))
				end
			end
		end
		for _, r in drawn do -- the new goo may not spill past the old
			for u = -1, 1, 0.5 do
				for v = -1, 1, 0.5 do
					local x = r.mx + r.ux * r.half * u - r.uz * ParadeLane.HALF_WIDTH * v
					local z = r.mz + r.uz * r.half * u + r.ux * ParadeLane.HALF_WIDTH * v
					worstExtra = math.max(worstExtra, outside(original, x, z, 0))
				end
			end
		end
		expect(worstMissing <= TOL + 0.05).toBe(true)
		expect(worstExtra <= TOL + 0.05).toBe(true)
	end)
end)
