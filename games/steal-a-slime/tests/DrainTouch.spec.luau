--!nocheck
-- The slime path just touches the goo drain: the lane follows its own curve to the end, easing smoothly from HALF_WIDTH
-- to END_HALF_WIDTH over the last TAPER_LENGTH studs (ParadeLane.halfWidthAt; no stepped taper strips), and the end is
-- cut to follow the drain's outer curb (WorldLayout.plazaColliders DrainCurb) so it meets the curb's outer face (no gap,
-- at most a hair of overlap) and nothing of the lane lies over the curb, the rim tiles or the basin. No curb ramp or pour
-- ribbon (they made the path jagged). The mesh numbers come from shared/modeling-kit/out/slime_lane_pivot.json.
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
	it("has no curb ramp or pour decor, and its end is narrower than the curb", function()
		expect(ParadeLane.drainStrips).toBe(nil)
		for _, strip in ParadeLane.strips() do
			expect(string.find(strip.name, "Drain") == nil and string.find(strip.name, "Pour") == nil).toBe(true)
		end
		expect(ParadeLane.END_HALF_WIDTH < radius - 0.1).toBe(true)
		expect(ParadeLane.END_HALF_WIDTH < HW).toBe(true)
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
			local hw = ParadeLane.halfWidthAt(C[i][1], C[i][2])
			for _, s in { -1, -0.5, 0, 0.5, 1 } do
				expect(gap({ C[i][1] - dz / len * hw * s, C[i][2] + dx / len * hw * s }) >= -TOLERANCE).toBe(true)
			end
		end
	end)
	it("is HALF_WIDTH wide round the loop and tapers smoothly to END_HALF_WIDTH at the curb", function()
		local C = info.centre
		for i, w in info.widths do
			local want = 2 * ParadeLane.halfWidthAt(C[i][1], C[i][2])
			expect(math.abs(w - want) < 0.01).toBe(true)
			if gap(C[i]) > ParadeLane.TAPER_LENGTH + 0.1 then
				expect(math.abs(w - 2 * HW) < 0.01).toBe(true)
			end
			if i > 1 then -- no step: neighbouring rings differ by a hair
				expect(math.abs(w - info.widths[i - 1]) < 0.25).toBe(true)
			end
		end
		expect(math.abs(info.widths[#info.widths] - 2 * ParadeLane.END_HALF_WIDTH) < 0.05).toBe(true)
		-- the stand-in strips follow the same rule, piece by piece
		local strips = ParadeLane.strips()
		for i, strip in strips do
			local cf = strip.cf
			expect(math.abs(strip.width - 2 * ParadeLane.halfWidthAt(cf[1], cf[3])) < 0.35).toBe(true)
			if i > 1 then
				expect(math.abs(strip.width - strips[i - 1].width) < 0.6).toBe(true)
			end
		end
	end)
	it("ends only a few studs past the old walk end", function()
		for _, p in info.endRing do
			expect(math.sqrt((p[1] - cx) ^ 2 + (p[2] - cz) ^ 2) > radius - TOLERANCE).toBe(true)
		end
		local exit, last = ParadeLane.EXIT, info.centre[#info.centre]
		local extension = math.sqrt((last[1] - exit[1]) ^ 2 + (last[2] - exit[2]) ^ 2)
		expect(extension > 1 and extension < 6).toBe(true)
	end)
end)
