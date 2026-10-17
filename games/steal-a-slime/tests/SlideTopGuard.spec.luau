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
			expect(r.base).toBe(SlideColliders.FILL)
			expect(math.abs(r.height - (SlideColliders.FILL + r.rise)) < 1e-9).toBe(true)
			expect(math.abs(math.deg(math.atan2(r.rise, r.half)) - r.angle) < 1e-9).toBe(true)
		end
	end)
	it("keeps the box top at least FILL over the ride line across the whole width; the roof starts there", function()
		for _, spec in FILLS do
			expect(spec.size[2] >= SlideColliders.FILL).toBe(true)
			-- box top (centre + size / 2 along up) is FILL over the ride line (the box centre is FILL / 2 over it)
			local r = SlideColliders.ridge(spec)
			local w = SlideColliders.wedge(spec, 1)
			-- the wedge's lowest edge (its centre - rise / 2 along up) is the box top: FILL / 2 (box half) above the box centre
			local _, up = frame(spec)
			local dy = (w.pos[1] - spec.centre[1]) * up[1]
				+ (w.pos[2] - spec.centre[2]) * up[2]
				+ (w.pos[3] - spec.centre[3]) * up[3]
			expect(math.abs(dy - r.rise / 2 - spec.size[2] / 2) < 1e-9).toBe(true)
		end
	end)
	it(
		"builds the wedges so the slope faces up and outward at >= 60 deg, friction aside (face normal from the basis)",
		function()
			-- Assumed Roblox WedgePart: triangle in Y/Z, vertical face at +Z, slope from (+Y, +Z) down to (-Y, -Z):
			-- outward slope normal in local coordinates n = (0, sz, -sy) / |.|, world = basis * n.
			for _, spec in FILLS do
				local right, up = frame(spec)
				local r = SlideColliders.ridge(spec)
				for _, side in { -1, 1 } do
					local w = SlideColliders.wedge(spec, side)
					local sy, sz = w.size[2], w.size[3]
					local len = math.sqrt(sy * sy + sz * sz)
					local n = {}
					for k = 1, 3 do
						n[k] = (w.y[k] * sz - w.z[k] * sy) / len
					end
					local dot = function(a, b)
						return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
					end
					-- basis orthonormal, right-handed (x = y cross z)
					expect(
						math.abs(dot(w.x, w.y)) < 1e-9
							and math.abs(dot(w.y, w.z)) < 1e-9
							and math.abs(dot(w.x, w.z)) < 1e-9
					).toBe(true)
					expect(math.abs(dot(w.y, up) - 1) < 1e-9).toBe(true)
					-- the normal points up (+up) and away from the centreline (side * right)
					expect(dot(n, up) > 0).toBe(true)
					expect(dot(n, right) * side > 0).toBe(true)
					-- steepness: angle of the face from flat = angle between its normal and up's complement
					local fromFlat = math.deg(math.acos(math.clamp(dot(n, up), -1, 1)))
					expect(fromFlat >= SlideColliders.RIDGE_ANGLE - 1e-6).toBe(true)
					expect(math.abs(fromFlat - r.angle) < 1e-6).toBe(true)
					-- tall edge (local +Z top) is on the centreline, low edge on the box edge (half out)
					local topX = w.pos[1] + w.y[1] * sy / 2 + w.z[1] * sz / 2
					local topY = w.pos[2] + w.y[2] * sy / 2 + w.z[2] * sz / 2
					local topZ = w.pos[3] + w.y[3] * sy / 2 + w.z[3] * sz / 2
					local across = (topX - spec.centre[1]) * right[1] + (topZ - spec.centre[3]) * right[3]
					expect(math.abs(across) < 1e-9).toBe(true)
					local above = (topX - spec.centre[1]) * up[1]
						+ (topY - spec.centre[2]) * up[2]
						+ (topZ - spec.centre[3]) * up[3]
					expect(math.abs(above + SlideColliders.FILL / 2 - r.height) < 1e-9).toBe(true)
				end
			end
		end
	)
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
			local fx, fy, fz = at(spec, r.half * 0.4, r.base + r.rise * 0.6 + 3, spec.size[3] * 0.25)
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
					-- (alone: this point may lie over a lower lap's roof, which is a different, legitimate hit)
					expect(SlideTopGuard.onTop({ spec }, x, y, z, 0)).toBe(nil)
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
	it("a root just over the box top at the eaves is on top, and inside the box under the eaves is not", function()
		for _, spec in FILLS do
			local r = SlideColliders.ridge(spec)
			local x, y, z = at(spec, r.half * 0.95, SlideColliders.FILL + 3, 0)
			expect(SlideTopGuard.onTop(SPECS, x, y, z, 0) ~= nil).toBe(true)
			local ix, iy, iz = at(spec, r.half * 0.95, SlideColliders.FILL - 4, 0)
			local hit = SlideTopGuard.onTop({ spec }, ix, iy, iz, 0)
			expect(hit).toBe(nil)
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
