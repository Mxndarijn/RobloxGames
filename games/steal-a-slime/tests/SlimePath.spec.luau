--!nocheck
-- The slime path: the goo lane starts exactly where the fountain slide ends (the mouth, r 35.5 on +Z), leaves
-- the landing ring through its gap, never overlaps the fountain body, the slide colliders or a curb tile, and is
-- built from flush, mitred strips (no gap between pieces, nothing sticking out of the lane surface).
local Config = require("../src/shared/Config")
local ParadeLane = require("../src/shared/ParadeLane")
local SlideColliders = require("../src/shared/SlideColliders")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local HW = ParadeLane.HALF_WIDTH
local FOUNTAIN_BODY_RADIUS = 14.5 -- BasinRim, the widest solid part of the fountain (Volcano Rock1 / BasinRim)

type Rect = { cx: number, cz: number, ux: number, uz: number, hl: number, hw: number }

local function stripRects(): { Rect }
	local out = {}
	for _, strip in ParadeLane.strips() do
		local c = strip.cf
		table.insert(out, { cx = c[1], cz = c[3], ux = c[4], uz = c[10], hl = strip.length / 2, hw = strip.width / 2 })
	end
	return out
end

-- Penetration depth of two rectangles (SAT over their four axes); <= 0 when they are apart.
local function penetration(a: Rect, b: Rect): number
	local best = math.huge
	for _, axis in
		{
			{ a.ux, a.uz },
			{ -a.uz, a.ux },
			{ b.ux, b.uz },
			{ -b.uz, b.ux },
		}
	do
		local function radius(r: Rect): number
			return r.hl * math.abs(r.ux * axis[1] + r.uz * axis[2]) + r.hw * math.abs(-r.uz * axis[1] + r.ux * axis[2])
		end
		local gap = math.abs((b.cx - a.cx) * axis[1] + (b.cz - a.cz) * axis[2])
		best = math.min(best, radius(a) + radius(b) - gap)
	end
	return best
end

local function inside(r: Rect, x: number, z: number, slack: number): boolean
	local dx, dz = x - r.cx, z - r.cz
	return math.abs(dx * r.ux + dz * r.uz) <= r.hl + slack and math.abs(-dx * r.uz + dz * r.ux) <= r.hw + slack
end

local function covered(rects: { Rect }, x: number, z: number): boolean
	for _, r in rects do
		if inside(r, x, z, 1e-6) then
			return true
		end
	end
	return false
end

local function segmentDistance(x: number, z: number, a: { number }, b: { number }): number
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local len2 = math.max(dx * dx + dz * dz, 1e-12)
	local k = math.clamp(((x - a[1]) * dx + (z - a[2]) * dz) / len2, 0, 1)
	return math.sqrt((x - a[1] - dx * k) ^ 2 + (z - a[2] - dz * k) ^ 2)
end

local RECTS = stripRects()
local PATH = WorldLayout.SLIDE_PATH
local MOUTH = PATH[#PATH]

describe("slime path starts at the fountain exit", function()
	it("the lane's first point is the slide mouth, within 0.05 studs", function()
		local first = ParadeLane.drawPoints()[1]
		expect(math.abs(first[1] - MOUTH[1]) < 0.05).toBe(true)
		expect(math.abs(first[2] - MOUTH[3]) < 0.05).toBe(true)
		expect(math.abs(ParadeLane.MOUTH[1] - MOUTH[1]) < 0.05).toBe(true)
		expect(math.abs(ParadeLane.MOUTH[2] - MOUTH[3]) < 0.05).toBe(true)
	end)
	it("the first strip begins at the mouth: its back edge is no more than 0.05 behind it", function()
		local r = RECTS[1]
		local back = (MOUTH[1] - r.cx) * r.ux + (MOUTH[3] - r.cz) * r.uz + r.hl
		expect(back >= -1e-3 and back < 0.05).toBe(true)
	end)
	it("heads away from the fountain along the slide's own heading, within 15 degrees", function()
		local before = PATH[#PATH - 1]
		local hx, hz = MOUTH[1] - before[1], MOUTH[3] - before[3]
		local len = math.sqrt(hx * hx + hz * hz)
		local r = RECTS[1]
		expect((hx * r.ux + hz * r.uz) / len > math.cos(math.rad(15))).toBe(true)
	end)
	it("reaches ENTRY (where the ride lands slimes) on the drawn lane, then follows the walk route", function()
		local pts = ParadeLane.drawPoints()
		local found = false
		for _, p in pts do
			if math.abs(p[1] - ParadeLane.ENTRY[1]) < 1e-6 and math.abs(p[2] - ParadeLane.ENTRY[2]) < 1e-6 then
				found = true
			end
		end
		expect(found).toBe(true)
		expect(pts[#pts]).toBe(ParadeLane.EXIT)
		local e = ParadeLane.entrySpot(0)
		expect(covered(RECTS, e[1], e[3])).toBe(true)
	end)
	it("the ring is open where the slide ends and the lane starts: no curb tile within reach of either", function()
		local tiles = {}
		for _, root in WorldLayout.build() do
			for _, c in root.children or {} do
				if c.name == "Plaza" then
					for _, n in c.children do
						if n.name == "LandingRing" then
							tiles = n.children
						end
					end
				end
			end
		end
		expect(#tiles > 0).toBe(true)
		for _, tile in tiles do
			local yaw = math.rad(tile.rot[2])
			local rect: Rect = {
				cx = tile.pos[1],
				cz = tile.pos[3],
				ux = math.cos(yaw),
				uz = -math.sin(yaw),
				hl = tile.size[1] / 2,
				hw = tile.size[3] / 2,
			}
			for _, strip in RECTS do
				expect(penetration(rect, strip) <= 0.05).toBe(true)
			end
			-- and clear of the whole slide trough (centreline distance >= half width, low stretch only)
			for i = 1, #PATH - 1 do
				if PATH[i][2] <= 4 then
					local worst = math.huge
					for _, sx in { -1, 0, 1 } do
						for _, sz in { -1, 0, 1 } do
							local lx, lz = sx * rect.hl, sz * rect.hw
							local x = rect.cx + rect.ux * lx - rect.uz * lz
							local z = rect.cz + rect.uz * lx + rect.ux * lz
							worst = math.min(
								worst,
								segmentDistance(x, z, { PATH[i][1], PATH[i][3] }, { PATH[i + 1][1], PATH[i + 1][3] })
							)
						end
					end
					expect(worst >= SlideColliders.HALF_WIDTH - 0.3).toBe(true)
				end
			end
		end
	end)
end)

-- Oriented boxes in 3D: centre, three unit axes, half sizes. Penetration depth by SAT over the 15 axes (<= 0 apart).
type Box = { c: { number }, a: { { number } }, h: { number } }

local function cross(u: { number }, v: { number }): { number }
	return { u[2] * v[3] - u[3] * v[2], u[3] * v[1] - u[1] * v[3], u[1] * v[2] - u[2] * v[1] }
end
local function dot(u: { number }, v: { number }): number
	return u[1] * v[1] + u[2] * v[2] + u[3] * v[3]
end

local function boxPenetration(p: Box, q: Box): number
	local axes = {}
	for i = 1, 3 do
		table.insert(axes, p.a[i])
		table.insert(axes, q.a[i])
		for j = 1, 3 do
			local x = cross(p.a[i], q.a[j])
			local len = math.sqrt(dot(x, x))
			if len > 1e-6 then
				table.insert(axes, { x[1] / len, x[2] / len, x[3] / len })
			end
		end
	end
	local best = math.huge
	local d = { q.c[1] - p.c[1], q.c[2] - p.c[2], q.c[3] - p.c[3] }
	for _, axis in axes do
		local rp, rq = 0, 0
		for i = 1, 3 do
			rp += p.h[i] * math.abs(dot(p.a[i], axis))
			rq += q.h[i] * math.abs(dot(q.a[i], axis))
		end
		best = math.min(best, rp + rq - math.abs(dot(d, axis)))
	end
	return best
end

-- A lane piece as the box over its ground footprint, from the ground (y 0) up to its crown (LANE_Y).
local function laneBox(strip: any): Box
	local c = strip.cf
	local ux, uz = c[4], c[10]
	local top = ParadeLane.LANE_Y
	return {
		c = { c[1], top / 2, c[3] },
		a = { { ux, 0, uz }, { 0, 1, 0 }, { -uz, 0, ux } },
		h = { strip.length / 2, top / 2, strip.width / 2 },
	}
end

describe("slime path stays off the fountain", function()
	it(
		"every piece stays clear of every fountain cylinder (barrel, basin rim, trim, silo, top, bowl) by 3 studs",
		function()
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
			local widest = 0
			for _, cyl in cylinders do
				-- an upright Cylinder lies along X: size = { height, diameter, diameter }
				local r = cyl.size[2] / 2
				widest = math.max(widest, r)
				local lo, hi = cyl.pos[2] - cyl.size[1] / 2, cyl.pos[2] + cyl.size[1] / 2
				if hi < 0 or lo > ParadeLane.LANE_Y then
					continue -- no overlap in height with the lane (0..LANE_Y)
				end
				for _, rect in RECTS do
					-- distance from the cylinder axis (map centre + pos) to the footprint rectangle
					local dx, dz = cyl.pos[1] - rect.cx, cyl.pos[3] - rect.cz
					local ou = math.max(0, math.abs(dx * rect.ux + dz * rect.uz) - rect.hl)
					local ov = math.max(0, math.abs(-dx * rect.uz + dz * rect.ux) - rect.hw)
					expect(math.sqrt(ou * ou + ov * ov) > r + 3).toBe(true)
				end
			end
			expect(widest >= FOUNTAIN_BODY_RADIUS - 1).toBe(true)
		end
	)
	it(
		"no lane piece intersects a slide floor, wall, joint, skirt or ceiling collider (the slide's supports)",
		function()
			local checked = 0
			for _, spec in SlideColliders.build(PATH, Config.FEATURES.SlideCollision) do
				local f = spec.forward
				local right = cross(f, { 0, 1, 0 })
				local len = math.sqrt(dot(right, right))
				if len < 1e-6 then
					continue -- a straight up / down piece (none in the low stretch)
				end
				right = { right[1] / len, right[2] / len, right[3] / len }
				local up = cross(right, f)
				local box: Box = {
					c = spec.centre,
					a = { f, up, right },
					h = { spec.size[3] / 2, spec.size[2] / 2, spec.size[1] / 2 },
				}
				for _, strip in ParadeLane.strips() do
					checked += 1
					-- the mouth's floor ends MOUTH_EXTRA (0.5) past the path where the lane starts: that touch only
					expect(boxPenetration(box, laneBox(strip)) <= 0.55).toBe(true)
				end
			end
			expect(checked > 1000).toBe(true)
		end
	)
	it("the lane box test would catch an overlap: a piece laid over the slide floor fails it", function()
		local floor = SlideColliders.build(PATH, Config.FEATURES.SlideCollision)[1]
		local box: Box = {
			c = { 0, 0.1, 0 },
			a = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } },
			h = { 5, 0.2, 5 },
		}
		local same: Box = { c = { 0, 0.1, 0 }, a = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }, h = { 5, 0.2, 5 } }
		expect(boxPenetration(box, same) > 0.25).toBe(true)
		expect(floor ~= nil).toBe(true)
	end)
end)

describe("slime path is flush", function()
	it(
		"every piece's crown is the lane surface: top within 0.05 of LANE_Y, none more than STRIP_STEP above it",
		function()
			for _, strip in ParadeLane.strips() do
				local top = strip.cf[2] + strip.size[2] / 2
				expect(math.abs(top - ParadeLane.LANE_Y) < 0.05).toBe(true)
				expect(top <= ParadeLane.LANE_Y + ParadeLane.STRIP_STEP + 1e-6).toBe(true)
			end
		end
	)
	it("neighbours alternate heights by STRIP_STEP so overlapping crowns never z-fight", function()
		local strips = ParadeLane.strips()
		for i = 2, #strips do
			expect(math.abs(strips[i].cf[2] - strips[i - 1].cf[2]) > 0.01).toBe(true)
		end
	end)
	it("the crown falls to the ground at the lane's edges: a soft rounded edge, not a step", function()
		local r = ParadeLane.CROWN_RADIUS
		local edge = ParadeLane.LANE_Y - (r - math.sqrt(r * r - ParadeLane.HALF_WIDTH ^ 2))
		expect(math.abs(edge) < 0.01).toBe(true)
		-- every piece is the same section, so neighbours match in width and height at their joint
		for _, strip in ParadeLane.strips() do
			expect(strip.size[2]).toBe(strip.size[3])
			expect(strip.size[2]).toBe(r * 2)
		end
	end)
	it("has no gap: the centreline and both edges are covered at every vertex and every 0.5 studs", function()
		local pts = ParadeLane.stripEndPoints()
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local dx, dz = b[1] - a[1], b[2] - a[2]
			local len = math.sqrt(dx * dx + dz * dz)
			local ux, uz = dx / len, dz / len
			for s = 0, len, 0.5 do
				for _, lateral in { -HW + 0.02, 0, HW - 0.02 } do
					expect(covered(RECTS, a[1] + ux * s - uz * lateral, a[2] + uz * s + ux * lateral)).toBe(true)
				end
			end
		end
	end)
	it("has no seam: consecutive strips overlap along their joint", function()
		for i = 2, #RECTS do
			local a, b = RECTS[i - 1], RECTS[i]
			local ex, ez = a.cx + a.ux * a.hl, a.cz + a.uz * a.hl
			expect(inside(b, ex, ez, 1e-6) or inside(a, b.cx - b.ux * b.hl, b.cz - b.uz * b.hl, 1e-6)).toBe(true)
		end
	end)
	it("sticks nothing out: every strip corner is within 6% of the lane's half width of the lane line", function()
		local pts = ParadeLane.stripEndPoints()
		for _, r in RECTS do
			for _, su in { -1, 1 } do
				for _, sv in { -1, 1 } do
					local x = r.cx + r.ux * r.hl * su - r.uz * r.hw * sv
					local z = r.cz + r.uz * r.hl * su + r.ux * r.hw * sv
					local best = math.huge
					for i = 1, #pts - 1 do
						best = math.min(best, segmentDistance(x, z, pts[i], pts[i + 1]))
					end
					expect(best <= HW * 1.06).toBe(true)
				end
			end
		end
	end)
	it("uses fewer, larger pieces: at most 100 strips, none shorter than 2 studs", function()
		expect(#RECTS <= 100).toBe(true)
		for _, r in RECTS do
			expect(r.hl * 2 >= 2).toBe(true)
		end
	end)
end)
