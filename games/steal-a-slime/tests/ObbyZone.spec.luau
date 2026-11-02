--!strict
-- The obby's "am I in this zone?" maths (src/visuals/shared/ObbyZone.luau; ObbyMoves' moon, dark and sticky walls,
-- ObbyFx's lifts and gusts): the body line counts, not just the root's centre; turned parts (yaw, pitch, roll and a
-- disc laid on its side) are tested in their own frame; a moving zone is tested where Kit's clock puts it now; the
-- side pad grows a column across, never taller; a moon bubble is the ellipsoid its dome draws, not its box; and a
-- sticky face is found from the shins to the shoulders.
local Kit = require("../src/shared/ObbySections/Kit")
local StaticWorld = require("../scripts/StaticWorld")
local TestRunner = require("./TestRunner")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local ObbyZone = StaticWorld.visual("ObbyZone")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local EPS = 1e-3

-- A point (both ends of the body line at one spot: the root alone).
local function point(cf: any, size: any, p: any, side: number, shape: string?): boolean
	return ObbyZone.touches(cf, size, shape or "box", p, p, side)
end

describe("ObbyZone.touches", function()
	-- A wind column 8 x 12 x 8 whose bottom is at y = 3.5 (a first Updraft column over a pad).
	local column = CFrame.new(14, 3.5 + 6, -6)
	local size = Vector3.new(8, 12, 8)

	it("takes a root just outside the side within the pad, not without it", function()
		local p = Vector3.new(14 + 4.4, 6, -6) -- 0.4 past the side
		expect(point(column, size, p, 0)).toBe(false)
		expect(point(column, size, p, 0.5)).toBe(true)
		expect(point(column, size, Vector3.new(14 + 4.6, 6, -6), 0.5)).toBe(false)
	end)

	it("keeps an edge steady: in at the stay pad, out at the come-in pad", function()
		local p = Vector3.new(14, 6, -6 + 4.8) -- 0.8 past the side
		expect(point(column, size, p, 0.5)).toBe(false) -- coming in: not yet
		expect(point(column, size, p, 1.0)).toBe(true) -- already in: stays
	end)

	it("never grows a column taller: a standing root under its bottom stays out", function()
		local p = Vector3.new(14, 3, -6) -- a walker's root, half a stud under the bottom
		expect(point(column, size, p, 1.0)).toBe(false)
		expect(point(column, size, Vector3.new(14, 3.6, -6), 0)).toBe(true)
	end)

	it("counts the body line: feet in the zone while the root is over its top", function()
		local zone = CFrame.new(0, 5, 0)
		local zsize = Vector3.new(10, 10, 10) -- top at y = 10
		local root = Vector3.new(0, 11.5, 0)
		expect(point(zone, zsize, root, 0)).toBe(false)
		local a, b = ObbyZone.body(root, 3, 2.5)
		expect(ObbyZone.touches(zone, zsize, "box", a, b, 0)).toBe(true)
		-- and the head in it while the root is under its bottom
		local low = Vector3.new(0, -1.5, 0)
		local la, lb = ObbyZone.body(low, 3, 2.5)
		expect(ObbyZone.touches(zone, zsize, "box", la, lb, 0)).toBe(true)
		-- a body wholly over it is out
		local ha, hb = ObbyZone.body(Vector3.new(0, 13.5, 0), 3, 2.5)
		expect(ObbyZone.touches(zone, zsize, "box", ha, hb, 0)).toBe(false)
	end)

	it("tests a turned box in its own frame (yaw)", function()
		local cf = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(45), 0)
		local s = Vector3.new(10, 4, 2)
		-- along the box's long axis 4.8 out: inside; the same distance along world X (off its thin side): outside
		local along = cf.XVector * 4.8
		expect(point(cf, s, along, 0)).toBe(true)
		expect(point(cf, s, Vector3.new(4.8, 0, 0), 0)).toBe(false)
	end)

	it("tests a tilted box in its own frame (pitch and roll)", function()
		local cf = CFrame.new(0, 10, 0) * CFrame.fromEulerAnglesYXZ(math.rad(30), 0, math.rad(20))
		local s = Vector3.new(6, 2, 6)
		local inLocal = cf:PointToWorldSpace(Vector3.new(2.9, 0.9, -2.9))
		local outLocal = cf:PointToWorldSpace(Vector3.new(0, 1.3, 0))
		expect(point(cf, s, inLocal, 0)).toBe(true)
		expect(point(cf, s, outLocal, 0)).toBe(false)
	end)

	it("tests a disc (a cylinder laid on its side) by its round shape", function()
		-- a 4 tall, 6 across puff whose bottom is at y = 2: ObbyParts lays a cylinder's X axis up
		local cf = CFrame.new(0, 4, 0) * CFrame.Angles(0, 0, math.rad(90))
		local s = Vector3.new(4, 6, 6)
		expect(point(cf, s, Vector3.new(2.9, 4, 0), 0, "cylinder")).toBe(true)
		expect(point(cf, s, Vector3.new(2.2, 4, 2.2), 0, "cylinder")).toBe(false) -- in the box's corner, off the disc
		expect(point(cf, s, Vector3.new(3.4, 4, 0), 0.5, "cylinder")).toBe(true)
		expect(point(cf, s, Vector3.new(0, 6.3, 0), 0.5, "cylinder")).toBe(false) -- over its top: not taller
		expect(ObbyZone.bottomY(cf, s)).toBeCloseTo(2, EPS)
	end)

	it("tests a ball by its round shape", function()
		local cf = CFrame.new(0, 0, 0)
		local s = Vector3.new(4, 4, 4)
		expect(point(cf, s, Vector3.new(1.9, 0, 0), 0, "ball")).toBe(true)
		expect(point(cf, s, Vector3.new(1.5, 1.5, 0), 0, "ball")).toBe(false)
	end)

	it("tests a moving zone where Kit's clock puts it now", function()
		local part: Kit.Part = {
			size = { 4, 6, 4 },
			pos = { 0, 0, 0 },
			look = "wind",
			motion = { kind = "slide", axis = "z", amp = 3, period = 2 },
		}
		local base = CFrame.new(0, 3, 0)
		local s = Vector3.new(4, 6, 4)
		for _, t in { 0.25, 0.5, 1.5 } do
			local dx, dy, dz = Kit.offsetAt(part, t)
			local now = base + Vector3.new(dx, dy, dz)
			local p = now.Position + Vector3.new(0, 0, if dz < 0 then -1.9 else 1.9) -- its leading edge
			expect(point(now, s, p, 0)).toBe(true)
			if math.abs(dz) > 0.5 then
				-- tested at its rest pose instead, the same spot reads wrong
				expect(point(base, s, p, 0)).toBe(false)
			end
		end
	end)
end)

describe("ObbyZone ellipsoid (a moon bubble: the dome a Sphere mesh draws in its box)", function()
	-- A bubble 40 long, 30 tall, 24 across centred at (0, 10, 0): radii 20, 15, 12.
	local cf = CFrame.new(0, 10, 0)
	local size = Vector3.new(40, 30, 24)

	it("takes the centre and points just inside the surface on every axis", function()
		expect(point(cf, size, Vector3.new(0, 10, 0), 0, "ellipsoid")).toBe(true)
		expect(point(cf, size, Vector3.new(19.9, 10, 0), 0, "ellipsoid")).toBe(true)
		expect(point(cf, size, Vector3.new(0, 24.9, 0), 0, "ellipsoid")).toBe(true)
		expect(point(cf, size, Vector3.new(0, 10, -11.9), 0, "ellipsoid")).toBe(true)
	end)

	it("leaves points just outside the surface out", function()
		expect(point(cf, size, Vector3.new(20.1, 10, 0), 0, "ellipsoid")).toBe(false)
		expect(point(cf, size, Vector3.new(0, 25.1, 0), 0, "ellipsoid")).toBe(false)
		expect(point(cf, size, Vector3.new(0, 10, 12.1), 0, "ellipsoid")).toBe(false)
		-- on a slant: (0.72, 0.72) of the radii is outside (0.72^2 * 2 > 1), (0.7, 0.7) inside
		expect(point(cf, size, Vector3.new(20 * 0.72, 10 + 15 * 0.72, 0), 0, "ellipsoid")).toBe(false)
		expect(point(cf, size, Vector3.new(20 * 0.7, 10 + 15 * 0.7, 0), 0, "ellipsoid")).toBe(true)
	end)

	it("leaves the box's corners and edges out, where a box test took them in", function()
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local corner = Vector3.new(sx * 19, 10 + sy * 14, sz * 11)
					expect(point(cf, size, corner, 0, "box")).toBe(true)
					expect(point(cf, size, corner, 0, "ellipsoid")).toBe(false)
				end
			end
		end
		-- a walker at the bubble's low end: in the box, under the dome
		expect(point(cf, size, Vector3.new(15, 0, 0), 0, "box")).toBe(true)
		expect(point(cf, size, Vector3.new(15, 0, 0), 0, "ellipsoid")).toBe(false)
	end)

	it("counts the body line: the head in the dome while the feet are under it, exactly (no sampling)", function()
		-- at x = 18 the dome spans y 10 +- 15 * sqrt(1 - 0.81) = 3.46 .. 16.54
		local feet = Vector3.new(18, 0, 0)
		expect(point(cf, size, feet, 0, "ellipsoid")).toBe(false)
		expect(ObbyZone.touches(cf, size, "ellipsoid", feet, feet + Vector3.new(0, 3.4, 0), 0)).toBe(false)
		expect(ObbyZone.touches(cf, size, "ellipsoid", feet, feet + Vector3.new(0, 3.5, 0), 0)).toBe(true)
		-- a line crossing the dome with both ends outside it still meets it
		expect(ObbyZone.touches(cf, size, "ellipsoid", Vector3.new(0, -10, 0), Vector3.new(0, 30, 0), 0)).toBe(true)
		-- a line passing beside it does not
		expect(ObbyZone.touches(cf, size, "ellipsoid", Vector3.new(21, -10, 0), Vector3.new(21, 30, 0), 0)).toBe(false)
	end)

	it("tests a turned bubble in its own frame (yaw, and pitch with roll)", function()
		local yaw = cf * CFrame.Angles(0, math.rad(90), 0) -- its 40-long axis now along world z
		expect(point(yaw, size, Vector3.new(0, 10, 19.5), 0, "ellipsoid")).toBe(true)
		expect(point(yaw, size, Vector3.new(19.5, 10, 0), 0, "ellipsoid")).toBe(false)
		local tilt = cf * CFrame.fromEulerAnglesYXZ(math.rad(30), 0, math.rad(20))
		expect(point(tilt, size, tilt:PointToWorldSpace(Vector3.new(0, 14.9, 0)), 0, "ellipsoid")).toBe(true)
		expect(point(tilt, size, tilt:PointToWorldSpace(Vector3.new(0, 15.1, 0)), 0, "ellipsoid")).toBe(false)
		expect(point(tilt, size, tilt:PointToWorldSpace(Vector3.new(14.5, 0, 8.5)), 0, "ellipsoid")).toBe(false)
	end)

	it("grows sideways by the come-in and stay pads, never taller", function()
		local p = Vector3.new(20.4, 10, 0) -- 0.4 past the side
		expect(point(cf, size, p, 0, "ellipsoid")).toBe(false)
		expect(point(cf, size, p, 0.5, "ellipsoid")).toBe(true)
		local q = Vector3.new(0, 10, -12.8) -- 0.8 past the side across
		expect(point(cf, size, q, 0.5, "ellipsoid")).toBe(false) -- coming in: not yet
		expect(point(cf, size, q, 1.0, "ellipsoid")).toBe(true) -- already in: stays
		-- over the top: no pad makes it taller
		expect(point(cf, size, Vector3.new(0, 25.3, 0), 1.0, "ellipsoid")).toBe(false)
	end)

	it("lineInEllipsoid: a zero-length line is a point; empty radii take nothing", function()
		expect(ObbyZone.lineInEllipsoid(1, 1, 1, 1, 1, 1, 2, 2, 2)).toBe(true)
		expect(ObbyZone.lineInEllipsoid(2, 2, 0, 2, 2, 0, 2, 2, 2)).toBe(false)
		expect(ObbyZone.lineInEllipsoid(0, 0, 0, 0, 0, 0, 0, 2, 2)).toBe(false)
	end)
end)

describe("ObbyZone.nearestFace", function()
	-- A sticky wall along x: 40 long, 10 tall (y 0..10), 1 thick (z -0.5..0.5).
	local wall = CFrame.new(0, 5, 0)
	local size = Vector3.new(40, 10, 1)

	it("finds the side face from the shins to the shoulders, also with the root over the top", function()
		local root = Vector3.new(0, 12, -1.5) -- 2 over the top, 1 off the face
		-- the root alone is off the top face (Y sticks out most): no grip
		local _, rootNormal = ObbyZone.nearestFace(wall, size, root, root)
		expect(math.abs(rootNormal.Y) > 0.5).toBe(true)
		local a, b = ObbyZone.body(root, 2.5, 1.5)
		local distance, normal = ObbyZone.nearestFace(wall, size, a, b)
		expect(distance).toBeCloseTo(1, EPS)
		expect(normal.Z).toBeCloseTo(-1, EPS)
		expect(math.abs(normal.Y) < 0.5).toBe(true)
	end)

	it("finds it with the root under the wall's bottom", function()
		local root = Vector3.new(5, -1.5, 1.2)
		local a, b = ObbyZone.body(root, 2.5, 1.5)
		local distance, normal = ObbyZone.nearestFace(wall, size, a, b)
		expect(distance).toBeCloseTo(0.7, EPS)
		expect(normal.Z).toBeCloseTo(1, EPS)
	end)

	it("measures a turned wall in its own frame", function()
		local cf = CFrame.new(0, 5, 0) * CFrame.Angles(0, math.rad(30), 0)
		local root = cf:PointToWorldSpace(Vector3.new(3, 0, 1.5))
		local a, b = ObbyZone.body(root, 2.5, 1.5)
		local distance, normal = ObbyZone.nearestFace(cf, size, a, b)
		expect(distance).toBeCloseTo(1, EPS)
		expect((normal - cf.ZVector).Magnitude).toBeCloseTo(0, EPS)
	end)

	it("treats a body inside the box (a wall moved into you) as on its nearest face", function()
		local root = Vector3.new(0, 5, -0.3)
		local distance, normal = ObbyZone.nearestFace(wall, size, root, root)
		expect(distance).toBe(0)
		expect(normal.Z).toBeCloseTo(-1, EPS)
	end)
end)
