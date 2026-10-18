--!nocheck
-- The slime path flows into the goo drain: the goo carries on from the lane's end (EXIT) over the drain's curb and ends
-- just inside the curb ring, continuous (no gap between slabs, nor to the lane), clear of the grate, visual only.
local ParadeLane = require("../src/shared/ParadeLane")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local D = ParadeLane.DRAIN
local CURB_INNER = 3.3 -- ranch_goo_drain Curb r 3.3-4.4
local WARN_TOP = 1.22 -- warning tiles on the curb

local function radius(x: number, z: number): number
	return math.sqrt((x - D.x) ^ 2 + (z - D.z) ^ 2)
end

describe("ParadeLane drain mouth", function()
	local mouth = ParadeLane.drainMouth()
	local last = mouth[#mouth]

	it("starts exactly on the lane's end, at lane height, no wider than the lane", function()
		local e = ParadeLane.EXIT
		expect(math.abs(mouth[1][1] - e[1]) < 1e-9).toBe(true)
		expect(math.abs(mouth[1][3] - e[2]) < 1e-9).toBe(true)
		expect(mouth[1][2]).toBe(ParadeLane.LANE_Y)
		expect(mouth[1][4] <= ParadeLane.HALF_WIDTH).toBe(true)
	end)
	it("ends inside the drain's curb ring, outside the grate", function()
		local r = radius(last[1], last[3])
		expect(r <= D.lipRadius).toBe(true)
		expect(r < CURB_INNER).toBe(true)
		expect(r > ParadeLane.GRATE_RADIUS).toBe(true)
	end)
	it("never covers the grate", function()
		for _, strip in ParadeLane.drainStrips() do
			local c = strip.cf
			-- nearest point of the slab's centre line to the drain centre (slab axis = c[4], c[10])
			local along = (D.x - c[1]) * c[4] + (D.z - c[3]) * c[10]
			along = math.clamp(along, -strip.length / 2, strip.length / 2)
			local px, pz = c[1] + c[4] * along, c[3] + c[10] * along
			expect(radius(px, pz) > ParadeLane.GRATE_RADIUS).toBe(true)
		end
	end)
	it("has continuous spacing: small steps, all of them closing in on the drain", function()
		for i = 2, #mouth do
			local a, b = mouth[i - 1], mouth[i]
			local step = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
			expect(step <= 1.2).toBe(true)
			expect(radius(b[1], b[3]) < radius(a[1], a[3])).toBe(true)
		end
	end)
	it("rises over the curb and its warning tiles, and the goo is never wider than the lane", function()
		local top = 0
		for _, p in mouth do
			top = math.max(top, p[2])
			expect(p[4] <= ParadeLane.HALF_WIDTH + 1e-9).toBe(true)
		end
		expect(top > WARN_TOP).toBe(true)
	end)
	it("bends no sharper than the lane itself (LaneTurn limit)", function()
		local pts = {}
		for _, p in mouth do
			table.insert(pts, { p[1], p[3] })
		end
		local before = ParadeLane.WAYPOINTS[#ParadeLane.WAYPOINTS - 1]
		table.insert(pts, 1, before)
		local worst = 0
		for i = 2, #pts - 1 do
			local ax, az = pts[i][1] - pts[i - 1][1], pts[i][2] - pts[i - 1][2]
			local bx, bz = pts[i + 1][1] - pts[i][1], pts[i + 1][2] - pts[i][2]
			local cos = (ax * bx + az * bz) / (math.sqrt(ax * ax + az * az) * math.sqrt(bx * bx + bz * bz))
			worst = math.max(worst, math.deg(math.acos(math.clamp(cos, -1, 1))))
		end
		expect(worst <= 20).toBe(true)
	end)
	it("slabs overlap their neighbours (no gap) and are decor-sized: thin Block slabs, one per mouth step", function()
		local strips = ParadeLane.drainStrips()
		expect(#strips).toBe(#mouth - 1)
		for i, strip in strips do
			expect(strip.shape).toBe("Block")
			expect(strip.size[2] <= 0.5).toBe(true)
			local a, b = mouth[i], mouth[i + 1]
			local step = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
			expect(strip.length >= step + ParadeLane.MOUTH_OVERLAP).toBe(true)
		end
	end)
end)
