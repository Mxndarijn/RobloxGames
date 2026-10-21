--!strict
local EdgeArrow = require("../src/shared/EdgeArrow")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local RECT = { left = 100, top = 50, right = 900, bottom = 550 }
local CENTRE = { x = 500, y = 300 }

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

describe("EdgeArrow.direction", function()
	it("matches the on-screen side for targets in front", function()
		local dx, dy = EdgeArrow.direction({ x = 10, y = 0, z = -5 })
		expect(near(dx, 1) and near(dy, 0)).toBe(true)
		dx, dy = EdgeArrow.direction({ x = 0, y = 10, z = -5 })
		expect(near(dx, 0) and near(dy, -1)).toBe(true) -- above: up the screen
		dx, dy = EdgeArrow.direction({ x = -3, y = -4, z = -50 })
		expect(near(dx, -0.6) and near(dy, 0.8)).toBe(true)
	end)
	it("keeps a target beside the camera on its own side (no mirroring)", function()
		local dx = EdgeArrow.direction({ x = 20, y = 0, z = 0.001 })
		expect(dx > 0.99).toBe(true)
		dx = EdgeArrow.direction({ x = -20, y = 0, z = 0.001 })
		expect(dx < -0.99).toBe(true)
	end)
	it("points down, towards the target's side, for targets behind", function()
		local dx, dy = EdgeArrow.direction({ x = 0, y = 0, z = 40 })
		expect(near(dx, 0) and near(dy, 1)).toBe(true)
		dx, dy = EdgeArrow.direction({ x = 0, y = 30, z = 40 }) -- behind and above: still down
		expect(dy > 0.99).toBe(true)
		dx, dy = EdgeArrow.direction({ x = 40, y = 0, z = 40 })
		expect(dx > 0.7 and dy > 0.7).toBe(true)
		dx, dy = EdgeArrow.direction({ x = -40, y = 0, z = 40 })
		expect(dx < -0.7 and dy > 0.7).toBe(true)
	end)
	it("returns a unit vector and survives degenerate input", function()
		for _, rel in { { x = 0, y = 0, z = 0 }, { x = 0 / 0, y = 1, z = 1 }, { x = math.huge, y = 0, z = 0 } } do
			local dx, dy = EdgeArrow.direction(rel)
			expect(near(dx * dx + dy * dy, 1)).toBe(true)
		end
	end)
end)

describe("EdgeArrow.place", function()
	it("lands on the edge the direction points at", function()
		local a = EdgeArrow.place(CENTRE, 1, 0, RECT)
		expect(near(a.x, 900) and near(a.y, 300) and near(a.angle, 0)).toBe(true)
		a = EdgeArrow.place(CENTRE, 0, -1, RECT)
		expect(near(a.x, 500) and near(a.y, 50) and near(a.angle, -90)).toBe(true)
		a = EdgeArrow.place(CENTRE, 0, 1, RECT)
		expect(near(a.y, 550) and near(a.angle, 90)).toBe(true)
	end)
	it("stays on the ray from the origin, so the arrow points where it sits", function()
		for i = 0, 35 do
			local t = i / 36 * 2 * math.pi
			local dx, dy = math.cos(t), math.sin(t)
			local a = EdgeArrow.place(CENTRE, dx, dy, RECT)
			local ox, oy = a.x - CENTRE.x, a.y - CENTRE.y
			expect(math.abs(ox * dy - oy * dx) < 1e-6).toBe(true) -- on the ray
			expect(ox * dx + oy * dy > 0).toBe(true) -- on the right side of it
			local onEdge = near(a.x, RECT.left)
				or near(a.x, RECT.right)
				or near(a.y, RECT.top)
				or near(a.y, RECT.bottom)
			expect(onEdge and EdgeArrow.inside(a, RECT)).toBe(true)
		end
	end)
	it("uses an off-centre origin, not the rect centre", function()
		local a = EdgeArrow.place({ x = 300, y = 300 }, 0, -1, RECT)
		expect(near(a.x, 300) and near(a.y, 50)).toBe(true)
	end)
	it("clamps an origin outside the rect and never returns NaN", function()
		local a = EdgeArrow.place({ x = -500, y = 9999 }, 1, 0, RECT)
		expect(near(a.x, 900) and near(a.y, 550)).toBe(true)
		a = EdgeArrow.place({ x = 0 / 0, y = 0 / 0 }, 0, 0, { left = 10, top = 10, right = 5, bottom = 5 })
		expect(a.x == a.x and a.y == a.y and a.angle == a.angle).toBe(true)
	end)
end)
