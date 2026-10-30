--!strict
-- A dropped slime's route back to the lane goes round everything solid, drops off roofs onto the ground, and gives
-- up (pop) only when there is no way out (server/WalkRoute).
local TestRunner = require("./TestRunner")
local WalkHeight = require("../src/server/WalkHeight")
local WalkRoute = require("../src/server/WalkRoute")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

type P = WalkRoute.P
type Box = { x0: number, x1: number, z0: number, z1: number, y0: number, y1: number }

local OPTS: WalkRoute.Options = {
	speed = 6,
	gravity = WalkHeight.GRAVITY,
	stepUp = WalkHeight.STEP_UP,
	stepDown = WalkHeight.STEP_DOWN,
}
local MAP = 100 -- the ground is y = 0 inside |x|, |z| <= MAP
local BAND_LOW = 1.6 -- a fake body: clear when nothing solid is between these heights over its feet, within RADIUS
local BAND_HIGH = 3.6
local RADIUS = 1

local function box(x0: number, x1: number, z0: number, z1: number, y0: number, y1: number): Box
	return { x0 = x0, x1 = x1, z0 = z0, z1 = z1, y0 = y0, y1 = y1 }
end

-- A fake world of boxes on flat ground. `engine` is the engine's path: a list of waypoints it returns for any search
-- (its last one replaced by the goal), or "straight" (only the goal), or nil (no path).
local function world(boxes: { Box }, engine: ({ P } | string)?): (WalkRoute.Probe, { number })
	local calls = { 0 }
	local probe: WalkRoute.Probe = {
		ground = function(x: number, z: number, fromY: number): number?
			if math.abs(x) > MAP or math.abs(z) > MAP then
				return nil
			end
			local best = if fromY >= 0 then 0 else nil
			for _, b in boxes do
				if x >= b.x0 and x <= b.x1 and z >= b.z0 and z <= b.z1 and b.y1 <= fromY then
					best = math.max(best or -math.huge, b.y1)
				end
			end
			return best
		end,
		clear = function(from: P, to: P): boolean
			local len = math.sqrt((to.x - from.x) ^ 2 + (to.y - from.y) ^ 2 + (to.z - from.z) ^ 2)
			local n = math.max(1, math.ceil(len / 0.25))
			for i = 0, n do
				local k = i / n
				local x = from.x + (to.x - from.x) * k
				local y = from.y + (to.y - from.y) * k
				local z = from.z + (to.z - from.z) * k
				for _, b in boxes do
					local inXZ = x >= b.x0 - RADIUS and x <= b.x1 + RADIUS and z >= b.z0 - RADIUS and z <= b.z1 + RADIUS
					if inXZ and b.y1 > y + BAND_LOW and b.y0 < y + BAND_HIGH then
						return false
					end
				end
			end
			return true
		end,
		path = function(_from: P, to: P, _wide: boolean): { P }?
			calls[1] += 1
			if engine == nil then
				return nil
			elseif engine == "straight" then
				return { to }
			end
			local out = table.clone(engine :: { P })
			table.insert(out, to)
			return out
		end,
	}
	return probe, calls
end

local function p(x: number, y: number, z: number): P
	return { x = x, y = y, z = z }
end

describe("WalkRoute.plan", function()
	it("takes the engine's path when every leg of it is clear", function()
		local probe = world({}, "straight")
		local route, how = WalkRoute.plan(p(0, 0, 0), p(30, 0, 0), probe, OPTS)
		expect(how).toBe("path")
		expect(route and #route).toBe(1)
	end)

	it("never takes a path that cuts through a wall", function()
		-- a wall between the drop and the lane; the engine (wrongly) goes straight through it
		local wall = box(10, 11, -20, 20, 0, 8)
		local probe = world({ wall }, "straight")
		local route, how = WalkRoute.plan(p(0, 0, 0), p(30, 0, 0), probe, OPTS)
		expect(route).toBe(nil)
		expect(how).toBe("none")
	end)

	it("takes a path round the wall", function()
		local wall = box(10, 11, -20, 20, 0, 8)
		local probe = world({ wall }, { p(5, 0, 25), p(16, 0, 25) })
		local route, how = WalkRoute.plan(p(0, 0, 0), p(30, 0, 0), probe, OPTS)
		expect(how).toBe("path")
		expect(route and #route).toBe(3)
	end)

	it("walks under nothing it does not fit under: it goes round a table top", function()
		local tableTop = box(10, 14, -3, 3, 3, 3.5)
		local probe = world({ tableTop }, "straight")
		local route, how = WalkRoute.plan(p(0, 0, 0), p(30, 0, 0), probe, OPTS)
		expect(how).toBe("path")
		assert(route, "a route")
		expect(#route).toBe(2) -- round it, not under it
		expect(WalkRoute.walkable(p(0, 0, 0), route, probe)).toBe(true)
	end)

	it("steps over a curb", function()
		local curb = box(10, 11, -20, 20, 0, 1.3)
		local probe = world({ curb }, "straight")
		local _, how = WalkRoute.plan(p(0, 0, 0), p(30, 0, 0), probe, OPTS)
		expect(how).toBe("path")
	end)

	it(
		"drops off a roof, landing on the ground on the lane's side, when the engine has no path from up there",
		function()
			local roof = box(-6, 6, -6, 6, 0, 20)
			-- the engine finds nothing from the roof, a straight path from the ground
			local probe, calls = world({ roof }, "straight")
			probe.path = function(from: P, to: P, _wide: boolean): { P }?
				calls[1] += 1
				return if from.y > 1 then nil else { to }
			end
			local route, how = WalkRoute.plan(p(0, 20, 0), p(40, 0, 0), probe, OPTS)
			expect(how).toBe("ledge")
			assert(route, "a route")
			local edge, landing = route[1], route[2]
			expect(edge.y).toBe(20)
			expect(math.abs(edge.x) <= 6 and math.abs(edge.z) <= 6).toBe(true) -- still on the roof
			expect(landing.y).toBe(0)
			expect(landing.x > 6).toBe(true) -- off the side that faces the goal
			expect(route[#route].x).toBe(40)
			expect(calls[1] <= 1 + WalkRoute.LEDGE_TRIES).toBe(true)
		end
	)

	it("prefers landing on the ground over landing on a lower roof", function()
		local roof = box(-6, 6, -6, 6, 0, 20)
		local slide = box(6, 30, -8, 8, 0, 10) -- a lower roof on the goal's side
		local probe = world({ roof, slide }, "straight")
		probe.path = function(from: P, to: P, _wide: boolean): { P }?
			-- nothing from up high; on the ground, round the lower roof's far corner
			return if from.y > 1 then nil else { p(35, 0, -40), to }
		end
		local route, how = WalkRoute.plan(p(0, 20, 0), p(40, 0, 0), probe, OPTS)
		expect(how).toBe("ledge")
		assert(route, "a route")
		expect(route[2].y).toBe(0)
	end)

	it("goes round something on the roof to reach an edge (a mascot in the middle)", function()
		local roof = box(-8, 8, -8, 8, 0, 20)
		local mascot = box(1, 4, -8, 8, 20, 26) -- a wall across the roof, between the start and the goal's side
		local probe = world({ roof, mascot }, "straight")
		probe.path = function(from: P, to: P, _wide: boolean): { P }?
			return if from.y > 1 then nil else { to }
		end
		local route, how = WalkRoute.plan(p(-3, 20, 0), p(40, 0, 0), probe, OPTS)
		expect(how).toBe("ledge")
		assert(route, "a route")
		expect(route[1].x < 1).toBe(true) -- its edge is on its own side of the mascot
	end)

	it("drops off ledge after ledge down a tiered roof", function()
		local top = box(-4, 4, -4, 4, 0, 20)
		local ring = box(-12, 12, -12, 12, 0, 10)
		local probe, calls = world({ top, ring }, "straight")
		probe.path = function(from: P, to: P, _wide: boolean): { P }?
			calls[1] += 1
			return if from.y > 1 then nil else { to }
		end
		local route, how = WalkRoute.plan(p(0, 20, 0), p(40, 0, 0), probe, OPTS)
		expect(how).toBe("ledge")
		assert(route, "a route")
		expect(route[2].y).toBe(10) -- onto the ring
		expect(route[4].y).toBe(0) -- then onto the ground
		expect(route[#route].x).toBe(40)
	end)

	it("searches at most MAX_PATHS times", function()
		local top = box(-4, 4, -4, 4, 0, 20)
		local ring = box(-12, 12, -12, 12, 0, 10)
		local probe, calls = world({ top, ring }, nil) -- the engine never finds a path
		local route, how = WalkRoute.plan(p(0, 20, 0), p(40, 0, 0), probe, OPTS)
		expect(route).toBe(nil)
		expect(how).toBe("none")
		expect(calls[1] <= WalkRoute.MAX_PATHS).toBe(true)
	end)

	it("asks again with a wider agent when the first path cuts a corner it can't step round", function()
		local wall = box(14, 16, -13, 13, 0, 6) -- too long to sidestep
		local probe = world({ wall }, "straight")
		probe.path = function(_from: P, to: P, wide: boolean): { P }?
			return if wide then { p(10, 0, 16), p(20, 0, 16), to } else { to }
		end
		local route, how = WalkRoute.plan(p(0, 0, 0), p(30, 0, 0), probe, OPTS)
		expect(how).toBe("path")
		assert(route, "a route")
		expect(route[1].z).toBe(16)
	end)

	it("gives up on a route far longer than the straight line", function()
		local probe = world({}, "straight")
		probe.path = function(_from: P, to: P, _wide: boolean): { P }?
			return { p(0, 0, 200), p(30, 0, 200), to } -- the long way round
		end
		local route, how = WalkRoute.plan(p(0, 0, 0), p(30, 0, 0), probe, OPTS)
		expect(route).toBe(nil)
		expect(how).toBe("none")
	end)

	it("steps round a prop the engine can't see (a mailbox on its path)", function()
		local mailbox = box(14, 16, -1, 1, 0, 6)
		local probe = world({ mailbox }, "straight")
		local route, how = WalkRoute.plan(p(0, 0, 0), p(30, 0, 0), probe, OPTS)
		expect(how).toBe("path")
		assert(route, "a route")
		expect(#route).toBe(2) -- a sidestep, then the goal
		expect(math.abs(route[1].z) >= 2).toBe(true)
		expect(WalkRoute.walkable(p(0, 0, 0), route, probe)).toBe(true)
	end)

	it("gives up when it is boxed in", function()
		local walls = {
			box(-6, -5, -6, 6, 0, 10),
			box(5, 6, -6, 6, 0, 10),
			box(-6, 6, -6, -5, 0, 10),
			box(-6, 6, 5, 6, 0, 10),
		}
		local probe = world(walls, "straight")
		local route, how = WalkRoute.plan(p(0, 0, 0), p(40, 0, 0), probe, OPTS)
		expect(route).toBe(nil)
		expect(how).toBe("none")
	end)
end)

describe("WalkRoute.ledges", function()
	it("finds no ledge on flat ground", function()
		local probe = world({}, nil)
		expect(#WalkRoute.ledges(p(0, 0, 0), probe, OPTS)).toBe(0)
	end)

	it("lands further out from a higher roof (it keeps walking while it falls)", function()
		local low = WalkRoute.ledges(p(0, 5, 0), world({ box(-6, 6, -6, 6, 0, 5) }, nil), OPTS)
		local high = WalkRoute.ledges(p(0, 30, 0), world({ box(-6, 6, -6, 6, 0, 30) }, nil), OPTS)
		expect(#low).toBe(WalkRoute.DIRECTIONS)
		expect(#high).toBe(WalkRoute.DIRECTIONS)
		local function out(l: WalkRoute.Ledge): number
			return math.sqrt((l.landing.x - l.edge.x) ^ 2 + (l.landing.z - l.edge.z) ^ 2)
		end
		expect(out(high[1]) > out(low[1])).toBe(true)
	end)

	it("walks down gentle steps on the way to an edge (a sloped dome)", function()
		local steps = {}
		for i = 0, 5 do
			table.insert(steps, box(-6 - i, 6 + i, -6 - i, 6 + i, 0, 20 - i))
		end
		local ledges = WalkRoute.ledges(p(0, 20, 0), world(steps, nil), OPTS)
		expect(#ledges > 0).toBe(true)
		expect(ledges[1].edge.y).toBe(15) -- the lowest step, not the first one down
	end)
end)
