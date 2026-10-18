--!nocheck
-- The slime path just touches the goo drain: the lane keeps its one uniform width and its own curve to the end, and the end
-- is cut to follow the drain's outer curb (WorldLayout.plazaColliders DrainCurb) so it meets the curb's outer face (no
-- gap, at most a hair of overlap) and nothing of the lane lies over the curb, the rim tiles or the basin. No taper
-- strips, curb ramp or pour ribbon (they made the path jagged). The mesh numbers come from shared/modeling-kit/out/slime_lane_pivot.json.
local ParadeLane = require("../src/shared/ParadeLane")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local TOLERANCE = 0.15
local HW = ParadeLane.HALF_WIDTH
local info = serde.decode("json", fs.readFile("../../shared/modeling-kit/out/slime_lane_pivot.json"))

local function curb(): (number, number, number)
	for _, node in WorldLayout.plazaColliders() do
		if node.name == "DrainCurb" then
			local c = WorldLayout.FOUNTAIN_CENTRE
			return c[1] + node.pos[1], c[3] + node.pos[3], node.size[2] / 2
		end
	end
	error("no DrainCurb collider")
end

local cx, cz, radius = curb()

local function gap(p: { number }): number
	return math.sqrt((p[1] - cx) ^ 2 + (p[2] - cz) ^ 2) - radius
end

describe("slime path touches the goo drain", function()
	it("has no drain taper, curb ramp or pour decor", function()
		expect(ParadeLane.drainStrips).toBe(nil)
		expect(ParadeLane.TAPER_START).toBe(nil)
		for _, strip in ParadeLane.strips() do
			expect(string.find(strip.name, "Drain") == nil and string.find(strip.name, "Pour") == nil).toBe(true)
		end
	end)
	it("every end-ring vertex sits on the curb's outer face (gap <= 0.15, overlap <= 0.15)", function()
		expect(#info.endRing).toBe(11)
		for _, p in info.endRing do
			expect(gap(p) <= TOLERANCE).toBe(true)
			expect(gap(p) >= -TOLERANCE).toBe(true)
		end
		local c = info.centre[#info.centre]
		expect(math.abs(gap(c)) <= TOLERANCE).toBe(true)
	end)
	it("no lane edge or centre sample lies inside the curb's outer radius (beyond the overlap)", function()
		local C = info.centre
		for i = 1, #C - 1 do
			local a, b = C[math.max(1, i - 1)], C[i + 1]
			local dx, dz = b[1] - a[1], b[2] - a[2]
			local len = math.max(math.sqrt(dx * dx + dz * dz), 1e-9)
			for _, s in { -1, -0.5, 0, 0.5, 1 } do
				expect(gap({ C[i][1] - dz / len * HW * s, C[i][2] + dx / len * HW * s }) >= -TOLERANCE).toBe(true)
			end
		end
	end)
	it("is the same width all the way to the end ring and ends only a few studs past the old walk end", function()
		for _, w in info.widths do
			expect(math.abs(w - 2 * HW) < 0.01).toBe(true)
		end
		for _, p in info.endRing do
			expect(math.sqrt((p[1] - cx) ^ 2 + (p[2] - cz) ^ 2) > radius - TOLERANCE).toBe(true)
		end
		local exit, last = ParadeLane.EXIT, info.centre[#info.centre]
		local extension = math.sqrt((last[1] - exit[1]) ^ 2 + (last[2] - exit[2]) ^ 2)
		expect(extension > 1 and extension < 6).toBe(true)
	end)
end)
