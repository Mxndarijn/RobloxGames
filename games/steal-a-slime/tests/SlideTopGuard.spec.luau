--!nocheck
-- Bug #9 follow-up: nobody stays on top of the slide fill. Pure checks of the ridge roof (steep faces) and of
-- Shared.SlideTopGuard (detects a root on every fill, ignores the trough and the ground beside the slide, nudges
-- outside every footprint), plus the guarantee that the slime ride is untouched (WorldLayout.SLIDE_PATH snapshot).
local SlideColliders = require("../src/shared/SlideColliders")
local SlideTopGuard = require("../src/shared/SlideTopGuard")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local PATH = WorldLayout.SLIDE_PATH
local SPECS = SlideColliders.build(PATH, true)
local FILLS = {}
for _, spec in SPECS do
	if spec.kind == "Fill" then
		table.insert(FILLS, spec)
	end
end

local function frame(spec)
	local f = spec.forward
	local len = math.sqrt(f[1] * f[1] + f[3] * f[3])
	local right = { -f[3] / len, 0, f[1] / len }
	local up =
		{ right[2] * f[3] - right[3] * f[2], right[3] * f[1] - right[1] * f[3], right[1] * f[2] - right[2] * f[1] }
	return right, up, f
end

-- world point at (lx across, above the ride line along up, lz along) of a fill spec
local function at(spec, lx, above, lz)
	local right, up, f = frame(spec)
	local ly = above - SlideColliders.FILL / 2
	local c = spec.centre
	return c[1] + right[1] * lx + up[1] * ly + f[1] * lz,
		c[2] + right[2] * lx + up[2] * ly + f[2] * lz,
		c[3] + right[3] * lx + up[3] * ly + f[3] * lz
end

describe("SlideTopGuard: the fill roof", function()
	it("has 63 fills (32 segments + 31 joints) and every roof face is at least RIDGE_ANGLE steep", function()
		expect(#FILLS).toBe(63)
		for _, spec in FILLS do
			local r = SlideColliders.ridge(spec)
			expect(r.angle >= SlideColliders.RIDGE_ANGLE - 1e-6).toBe(true)
			expect(r.height >= SlideColliders.FILL).toBe(true)
			expect(math.abs(math.deg(math.atan2(r.height, r.half)) - r.angle) < 1e-9).toBe(true)
		end
	end)
	it("keeps the old box specs (the guard and the probes read them) and the ride untouched", function()
		-- snapshot of main: WorldLayout.SLIDE_PATH (the ride line the slimes follow)
		local sum = 0
		for i, p in PATH do
			sum += (p[1] * 1.3 + p[2] * 2.7 + p[3] * 0.9) * i
		end
		expect(#PATH).toBe(33)
		expect(math.abs(sum - 19832.8303) < 1e-3).toBe(true)
		expect(PATH[1][2]).toBe(36.4)
		expect(PATH[#PATH][2]).toBe(0.7)
		expect(SlideColliders.FILL).toBe(11)
		for _, spec in FILLS do
			expect(spec.size[2]).toBe(SlideColliders.FILL)
		end
	end)
end)

describe("SlideTopGuard.onTop", function()
	it("detects a root standing on the ridge and on the roof flank of every segment and joint fill", function()
		for _, spec in FILLS do
			local r = SlideColliders.ridge(spec)
			local x, y, z = at(spec, 0, r.height + 3, 0)
			expect(SlideTopGuard.onTop(SPECS, x, y, z, 0) ~= nil).toBe(true)
			local fx, fy, fz = at(spec, r.half * 0.4, r.height * 0.6 + 3, spec.size[3] * 0.25)
			expect(SlideTopGuard.onTop(SPECS, fx, fy, fz, 0) ~= nil).toBe(true)
		end
	end)
	it("ignores the trough, the ride line, and positions beside, under and far above the slide", function()
		for _, spec in FILLS do
			local r = SlideColliders.ridge(spec)
			for _, k in { -0.3, 0, 0.3 } do
				-- on the ride line (a slime) and just over it: inside the solid, under the roof
				for _, above in { 0, 1.5 } do
					local x, y, z = at(spec, 0, above, spec.size[3] * k)
					expect(SlideTopGuard.onTop(SPECS, x, y, z, 0)).toBe(nil)
				end
			end
			-- beside the slide, any height
			local bx, by, bz = at(spec, r.half + 1, r.height + 3, 0)
			local hit = SlideTopGuard.onTop(SPECS, bx, by, bz, 0)
			-- (a neighbouring lap / joint may cover the point; then it is on THAT roof, never nil by accident of this spec)
			if hit then
				expect(hit ~= spec).toBe(true)
			end
			-- way above the roof (a jump apex is REACH)
			local ax, ay, az = at(spec, 0, r.height + SlideTopGuard.REACH + 5, 0)
			expect(SlideTopGuard.onTop({ spec }, ax, ay, az, 0)).toBe(nil) -- (alone: an upper lap may own that point)
		end
	end)
	it("ignores a root on the ground at the low mouth fringe", function()
		local last = FILLS[#FILLS - 1]
		local x, _, z = at(last, SlideColliders.ridge(last).half - 0.5, 0, 0)
		expect(SlideTopGuard.onTop(SPECS, x, 3, z, 0)).toBe(nil) -- roof edge is < MIN_RISE over the ground
	end)
end)

describe("SlideTopGuard.nudge", function()
	local cx, cz = 0, 0
	for _, spec in FILLS do
		cx += spec.centre[1] / #FILLS
		cz += spec.centre[3] / #FILLS
	end
	it("lands outside every fill footprint, close by, from the ridge of every fill", function()
		for _, spec in FILLS do
			local x, y, z = at(spec, 0, SlideColliders.ridge(spec).height + 3, 0)
			local nx, nz = SlideTopGuard.nudge(SPECS, spec, x, z, cx, cz)
			local moved = math.sqrt((nx - x) ^ 2 + (nz - z) ^ 2)
			expect(moved > 1 and moved <= SlideTopGuard.MAX_STEPS).toBe(true)
			-- not on any roof either, whatever the height
			for _, other in FILLS do
				local r = SlideColliders.ridge(other)
				local right, _, f = frame(other)
				local dx, dz = nx - other.centre[1], nz - other.centre[3]
				local across = math.abs(dx * right[1] + dz * right[3])
				local hLen = math.sqrt(f[1] * f[1] + f[3] * f[3])
				local along = math.abs((dx * f[1] + dz * f[3]) / hLen)
				expect(across >= r.half or along >= other.size[3] / 2 * hLen).toBe(true)
			end
		end
	end)
	it("never ends in the trough: the target is across the slide, past the footprint edge", function()
		for _, spec in FILLS do
			local x, y, z = at(spec, 0, SlideColliders.ridge(spec).height + 3, 0)
			local nx, nz = SlideTopGuard.nudge(SPECS, spec, x, z, cx, cz)
			local right = frame(spec)
			local across = math.abs((nx - spec.centre[1]) * right[1] + (nz - spec.centre[3]) * right[3])
			expect(across >= SlideColliders.ridge(spec).half).toBe(true)
		end
	end)
end)
