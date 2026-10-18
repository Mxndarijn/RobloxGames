--!nocheck
-- The slime path flows into the goo drain: the lane's own last segments (same Cylinder crown strips, same width at EXIT)
-- bend on to the drain, then a thin pour rides the gap between two rim tiles over the curb into the basin. All decor.
local ParadeLane = require("../src/shared/ParadeLane")
local TestRunner = require("./TestRunner")
local fs = require("@lune/fs")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local D = ParadeLane.DRAIN
local CURB_OUTER, CURB_INNER = 4.4, 3.3 -- ranch_goo_drain Curb r 3.3-4.4
local WARN_TOP = 1.22 -- warning tiles on the curb
local TILE_GAP = 4 -- degrees between neighbouring tiles (Warn tiles span 26 of every 30)

local function radius(x: number, z: number): number
	return math.sqrt((x - D.x) ^ 2 + (z - D.z) ^ 2)
end

describe("ParadeLane drain mouth", function()
	local lane = ParadeLane.drainLanePoints()
	local pour = ParadeLane.pourPoints()
	local strips = ParadeLane.drainStrips()
	local last = pour[#pour]

	it("the taper starts on the lane route at the full lane width, TAPER_START studs before EXIT", function()
		local e = ParadeLane.EXIT
		expect(lane[1][3]).toBe(ParadeLane.HALF_WIDTH)
		local d = math.sqrt((lane[1][1] - e[1]) ^ 2 + (lane[1][2] - e[2]) ^ 2)
		expect(math.abs(d - ParadeLane.TAPER_START) < 1.2).toBe(true)
		local stop = ParadeLane.stripEndPoints()
		local s = stop[#stop]
		expect(math.abs(s[1] - lane[1][1]) < 1e-9 and math.abs(s[2] - lane[1][2]) < 1e-9).toBe(true)
	end)
	it(
		"is continuous with the lane: first segment is a Cylinder strip overlapping the lane's, same crown height",
		function()
			local first = strips[1]
			expect(first.shape).toBe(nil) -- Cylinder, like ParadeLane.strips()
			expect(first.size[1] > 0).toBe(true)
			local top = first.cf[2] + first.size[2] / 2
			expect(math.abs(top - (ParadeLane.LANE_Y + ParadeLane.TAPER_STRIP_STEP)) < 1e-6).toBe(true)
		end
	)
	it("narrows monotonically from the lane width to the ribbon width over ~8-12 studs, in small even steps", function()
		local arc = 0
		for i = 1, #lane do
			expect(lane[i][3] <= ParadeLane.HALF_WIDTH + 1e-9).toBe(true)
			if i > 1 then
				arc += math.sqrt((lane[i][1] - lane[i - 1][1]) ^ 2 + (lane[i][2] - lane[i - 1][2]) ^ 2)
				expect(lane[i][3] <= lane[i - 1][3] + 1e-9).toBe(true)
				-- no jump: a smoothstep over ~10.5 studs changes at most 1.5 * 2.25 / 10.5 per stud, so <= 0.3 per 0.8 stud segment
				expect(lane[i - 1][3] - lane[i][3] <= 0.3).toBe(true)
			end
		end
		expect(arc >= 8 and arc <= 13).toBe(true)
		expect(math.abs(lane[#lane][3] - ParadeLane.POUR_HALF_WIDTH) < 1e-9).toBe(true)
		expect(ParadeLane.POUR_HALF_WIDTH * 2 >= 1.4 and ParadeLane.POUR_HALF_WIDTH * 2 <= 2.2).toBe(true)
		-- the second differences of the width are small too (a curve, not a staircase)
		for i = 3, #lane do
			local k = (lane[i - 2][3] - lane[i - 1][3]) - (lane[i - 1][3] - lane[i][3])
			expect(math.abs(k) <= 0.2).toBe(true)
		end
	end)
	it("the ribbon is as wide as the taper's end", function()
		for _, p in pour do
			expect(math.abs(p[4] - lane[#lane][3]) < 1e-9).toBe(true)
		end
	end)
	it("every drain piece is laid as decor: CanCollide, CanQuery and CanTouch false", function()
		local src = fs.readFile("src/server/ParadeView.luau")
		local lay = string.match(src, "local function layStrips.-\nend\n") or ""
		for _, flag in { "CanCollide", "CanQuery", "CanTouch" } do
			expect(string.find(lay, "part." .. flag .. " = false", 1, true) ~= nil).toBe(true)
		end
		expect(string.find(src, "layStrips(mouth, ParadeLane.drainStrips())", 1, true) ~= nil).toBe(true)
	end)
	it("ends in the drain's rim, outside the grate, and the pour finishes inside the curb ring", function()
		expect(radius(last[1], last[3]) < CURB_INNER).toBe(true)
		expect(radius(last[1], last[3]) > ParadeLane.GRATE_RADIUS).toBe(true)
		local join = lane[#lane]
		expect(radius(join[1], join[2]) > CURB_OUTER).toBe(true)
	end)
	it("pours between two rim tiles: it rides a tile gap line and is narrow", function()
		local gap = ParadeLane.RIM_TILE_GAP_DEGREES
		local deg = math.deg(ParadeLane.pourAngle())
		expect(math.abs(deg / gap - math.floor(deg / gap + 0.5)) < 1e-6).toBe(true)
		for _, p in pour do
			expect(math.abs(math.deg(math.atan2(p[3] - D.z, p[1] - D.x)) - deg) < 1e-6).toBe(true)
			-- at the tile ring (r 3.45-4.25) the ribbon laps at most a tile's edge: under a tile (arc ~1.7 studs)
			expect(p[4] <= 0.75 + 1e-9).toBe(true)
		end
		expect(TILE_GAP > 0).toBe(true)
	end)
	it("rises over the curb and its warning tiles, then drops into the basin", function()
		local top = 0
		for _, p in pour do
			top = math.max(top, p[2])
		end
		expect(top > WARN_TOP).toBe(true)
		expect(last[2] < ParadeLane.POUR_CROWN_Y - 0.5).toBe(true)
		-- the pour ends well inside the basin, a hair above the goo there (funnel surface ~0.67 at r 2)
		expect(radius(last[1], last[3]) <= 2.2).toBe(true)
		expect(last[2] >= 0.67 and last[2] <= 0.85).toBe(true)
		expect(pour[1][2]).toBe(ParadeLane.LANE_Y)
	end)
	it("never covers the grate", function()
		for _, strip in strips do
			local c = strip.cf
			local along = (D.x - c[1]) * c[4] + (D.z - c[3]) * c[10]
			along = math.clamp(along, -strip.length / 2, strip.length / 2)
			local px, pz = c[1] + c[4] * along, c[3] + c[10] * along
			expect(radius(px, pz) > ParadeLane.GRATE_RADIUS).toBe(true)
		end
	end)
	it(
		"turns in to the gap with soft bends (each ~0.6 stud step turns under 35 degrees; slimes do not walk it)",
		function()
			local pts = {}
			for _, p in lane do
				table.insert(pts, { p[1], p[2] })
			end
			for _, p in pour do
				table.insert(pts, { p[1], p[3] })
			end
			local worst = 0
			for i = 2, #pts - 1 do
				local ax, az = pts[i][1] - pts[i - 1][1], pts[i][2] - pts[i - 1][2]
				local bx, bz = pts[i + 1][1] - pts[i][1], pts[i + 1][2] - pts[i][2]
				local cos = (ax * bx + az * bz) / (math.sqrt(ax * ax + az * az) * math.sqrt(bx * bx + bz * bz))
				worst = math.max(worst, math.deg(math.acos(math.clamp(cos, -1, 1))))
			end
			expect(worst <= 35).toBe(true)
		end
	)
	it("has one strip per lane segment plus one thin Block slab per pour step", function()
		expect(#strips).toBe(#lane - 1 + #pour - 1)
		for i = #lane, #strips do
			expect(strips[i].shape).toBe("Block")
			expect(strips[i].size[2] <= 0.5).toBe(true)
		end
	end)
end)
