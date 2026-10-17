--!nocheck
-- The goo lane strip (ParadeView.place) is drawn with fewer straight Parts than the route has
-- waypoint pairs (ParadeLane.strips: the lead-in from the slide mouth plus ParadeLane.stripPoints, Douglas-Peucker
-- within STRIP_TOLERANCE). Checked here: the part count (it was one Part per waypoint pair, 133) and that every
-- route waypoint stays covered by the drawn strips. Flush joints and the lane start: tests/SlimePath.spec.
local ParadeLane = require("../src/shared/ParadeLane")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local TOL = ParadeLane.STRIP_TOLERANCE
local MAX_STRIPS = 50 -- was 133 (one per waypoint pair; 129 now the lead-in is not a waypoint), then 50 with the lead-in as smooth domed pieces; only ever lower it

-- Footprint of a drawn strip (ParadeLane.strips): centre, unit axis along it, half length.
local function rectsOf(strips: { any })
	local out = {}
	for _, strip in strips do
		local c = strip.cf
		table.insert(out, {
			mx = c[1],
			mz = c[3],
			ux = c[4],
			uz = c[10],
			half = strip.length / 2,
		})
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

local simple = ParadeLane.stripPoints()
local drawn = rectsOf(ParadeLane.strips())

describe("ParadeLane goo strip parts", function()
	it("draws the lane with far fewer strips than waypoint pairs", function()
		expect(#ParadeLane.WAYPOINTS - 1).toBe(129)
		expect(#drawn <= MAX_STRIPS).toBe(true)
		expect(#drawn * 2 < #ParadeLane.WAYPOINTS - 1).toBe(true)
	end)
	it("keeps the entry and exit of the route", function()
		expect(simple[1]).toBe(ParadeLane.ENTRY)
		expect(simple[#simple]).toBe(ParadeLane.EXIT)
	end)
	it("every route waypoint stays within the tolerance of the drawn polyline", function()
		for _, p in ParadeLane.WAYPOINTS do
			expect(outside(drawn, p[1], p[2], 0) < 1e-6).toBe(true)
			-- the centreline is deep inside a strip: even shrunk by the tolerance it is covered
			expect(outside(drawn, p[1], p[2], ParadeLane.HALF_WIDTH - TOL - 0.05) < 1e-6).toBe(true)
		end
	end)
end)
