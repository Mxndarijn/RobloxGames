--!strict
local GuideRoute = require("../../src/guide/GuideRoute")
local T = require("../../testing/TestRunner")
local describe, it, expect = T.describe, T.it, T.expect

local function p(x: number, y: number, z: number): GuideRoute.Point
	return { x = x, y = y, z = z }
end

local BOX: GuideRoute.Footprint = { x = 0, z = 0, axisX = 1, axisZ = 0, halfA = 10, halfB = 2 }

describe("GuideRoute.approachCandidates", function()
	it("puts one candidate per direction, margin studs outside each face", function()
		local spots = GuideRoute.approachCandidates(BOX, 5, { directions = 4, margin = 3 })
		expect(#spots).toBe(4)
		expect(spots[1].x).toBeCloseTo(13) -- along +A
		expect(spots[1].z).toBeCloseTo(0)
		expect(spots[2].x).toBeCloseTo(0) -- along +B
		expect(spots[2].z).toBeCloseTo(5)
		expect(spots[3].x).toBeCloseTo(-13)
		expect(spots[4].z).toBeCloseTo(-5)
		expect(spots[1].y).toBe(5)
	end)

	it("never lands inside the footprint, corners included", function()
		local square = { x = 0, z = 0, axisX = 1, axisZ = 0, halfA = 10, halfB = 10 }
		for _, spot in GuideRoute.approachCandidates(square, 0, { directions = 16, margin = 2 }) do
			-- the margin runs along the direction, so it is at least margin * cos 45 clear of a face
			expect(math.max(math.abs(spot.x), math.abs(spot.z)) >= 10 + 2 * math.sqrt(0.5) - 1e-6).toBe(true)
		end
	end)

	it("follows the footprint's rotation", function()
		local turned = { x = 100, z = 50, axisX = 0, axisZ = 1, halfA = 10, halfB = 2 }
		local spots = GuideRoute.approachCandidates(turned, 0, { directions = 4, margin = 3 })
		expect(spots[1].x).toBeCloseTo(100)
		expect(spots[1].z).toBeCloseTo(63) -- the long axis now runs along +Z
		expect(spots[2].x).toBeCloseTo(95) -- axis B is (-1, 0)
	end)
end)

describe("GuideRoute.pickApproach", function()
	it("picks the spot closest to the player on the ground plane", function()
		local spots = { p(13, 0, 0), p(0, 0, 5), p(-13, 0, 0) }
		local best, index = GuideRoute.pickApproach(spots, p(-40, 3, 1))
		expect(index).toBe(3)
		expect((best :: GuideRoute.Point).x).toBe(-13)
	end)

	it("keeps the earlier spot on a tie", function()
		local _, index = GuideRoute.pickApproach({ p(5, 0, 0), p(-5, 0, 0) }, p(0, 0, 10))
		expect(index).toBe(1)
	end)

	it("skips spots far above or below the target's base", function()
		local spots = { p(1, 20, 0), p(5, 0.5, 0) }
		local _, index = GuideRoute.pickApproach(spots, p(0, 0, 0), 0, { maxStep = 6 })
		expect(index).toBe(2)
	end)

	it("returns nothing when no spot qualifies", function()
		expect(GuideRoute.pickApproach({}, p(0, 0, 0))).toBeNil()
		expect(GuideRoute.pickApproach({ p(0, 50, 0) }, p(0, 0, 0), 0)).toBeNil()
	end)
end)

local L = { p(0, 0, 0), p(20, 0, 0), p(20, 0, 20) } -- an L: 20 east, then 20 north

describe("GuideRoute.project", function()
	it("measures along the route and away from it on the ground plane", function()
		local along, distance = GuideRoute.project(L, p(5, 3, 2))
		expect(along).toBeCloseTo(5)
		expect(distance).toBeCloseTo(2) -- the height difference does not count
		along, distance = GuideRoute.project(L, p(23, 0, 10))
		expect(along).toBeCloseTo(30)
		expect(distance).toBeCloseTo(3)
	end)

	it("only matches inside the given range", function()
		local along = GuideRoute.project(L, p(5, 0, 0), 10, 40)
		expect(along).toBeCloseTo(10)
	end)
end)

describe("GuideRoute.advance", function()
	it("moves forward as the player walks the route", function()
		local along = GuideRoute.advance(L, p(8, 0, 1), 0)
		expect(along).toBeCloseTo(8)
		along = GuideRoute.advance(L, p(19, 0, 3), along)
		expect(along).toBeCloseTo(23)
	end)

	it("never moves backwards", function()
		expect(GuideRoute.advance(L, p(2, 0, 0), 15)).toBeCloseTo(15)
	end)

	it("does not jump to a later leg that bends back near the player", function()
		-- a U: out 20 east, 6 north, back 20 west; the player stands on the first leg near the far leg's end
		local u = { p(0, 0, 0), p(20, 0, 0), p(20, 0, 6), p(0, 0, 6) }
		local along = GuideRoute.advance(u, p(2, 0, 3.5), 0, { lookahead = 16 })
		expect(along).toBeCloseTo(2)
	end)
end)

describe("GuideRoute.offRoute", function()
	it("is the distance to the remaining route only", function()
		expect(GuideRoute.offRoute(L, p(5, 0, 4), 0)).toBeCloseTo(4)
		-- past the first leg, the same spot is measured to the second leg
		expect(GuideRoute.offRoute(L, p(5, 0, 4), 20)).toBeCloseTo(15)
	end)
end)

describe("GuideRoute.ahead", function()
	it("starts at the player and keeps the waypoints past the progress point", function()
		local points = GuideRoute.ahead(L, 12, p(12, 3, 1))
		expect(#points).toBe(3)
		expect(points[1].y).toBe(3)
		expect(points[2].x).toBe(20)
		expect(points[2].z).toBe(0)
		expect(points[3].z).toBe(20)
	end)

	it("keeps the last waypoint at the end of the route", function()
		local points = GuideRoute.ahead(L, 40, p(20, 0, 20))
		expect(#points).toBe(2)
		expect(points[2].z).toBe(20)
	end)
end)

describe("GuideRoute.length and reaches", function()
	it("sums the route on the ground plane", function()
		expect(GuideRoute.length({ p(0, 0, 0), p(3, 9, 4), p(3, 0, 14) })).toBeCloseTo(15)
	end)

	it("accepts a route ending near the goal only", function()
		expect(GuideRoute.reaches(L, p(21, 5, 22), 6)).toBe(true)
		expect(GuideRoute.reaches(L, p(40, 0, 20), 6)).toBe(false)
		expect(GuideRoute.reaches({}, p(0, 0, 0))).toBe(false)
	end)
end)

describe("GuideRoute.backoff", function()
	it("doubles per failure up to the cap", function()
		local options = { retryBase = 1, retryMax = 4 }
		expect(GuideRoute.backoff(0, options)).toBe(0)
		expect(GuideRoute.backoff(1, options)).toBe(1)
		expect(GuideRoute.backoff(2, options)).toBe(2)
		expect(GuideRoute.backoff(3, options)).toBe(4)
		expect(GuideRoute.backoff(7, options)).toBe(4)
	end)
end)

describe("GuideRoute.shouldRecompute", function()
	local function state(changes: { [string]: any }): GuideRoute.RecomputeState
		local s: { [string]: any } =
			{ hasRoute = true, computing = false, failures = 0, sinceAttempt = 1, offRoute = 0, goalMoved = 0 }
		for k, v in changes do
			s[k] = v
		end
		return s :: any
	end

	it("asks for a first route straight away", function()
		local yes, reason = GuideRoute.shouldRecompute(state({ hasRoute = false, sinceAttempt = 0 }))
		expect(yes).toBe(true)
		expect(reason).toBe("NoRoute")
	end)

	it("never starts a second compute while one runs", function()
		expect((GuideRoute.shouldRecompute(state({ hasRoute = false, computing = true })))).toBe(false)
	end)

	it("keeps a good route while the player follows it", function()
		expect((GuideRoute.shouldRecompute(state({ offRoute = 3, goalMoved = 2 })))).toBe(false)
	end)

	it("recomputes when the player leaves the route or the goal moves", function()
		local _, off = GuideRoute.shouldRecompute(state({ offRoute = 7 }))
		expect(off).toBe("OffRoute")
		local _, moved = GuideRoute.shouldRecompute(state({ goalMoved = 7 }))
		expect(moved).toBe("GoalMoved")
	end)

	it("refreshes a route every safetyRefresh seconds", function()
		local _, reason = GuideRoute.shouldRecompute(state({ sinceAttempt = 5 }), { safetyRefresh = 5 })
		expect(reason).toBe("Refresh")
	end)

	it("backs off after failures", function()
		expect((GuideRoute.shouldRecompute(state({ hasRoute = false, failures = 3, sinceAttempt = 3 })))).toBe(false)
		expect((GuideRoute.shouldRecompute(state({ hasRoute = false, failures = 3, sinceAttempt = 4 })))).toBe(true)
		-- a kept route that left the player behind waits for the back-off too
		expect((GuideRoute.shouldRecompute(state({ failures = 1, sinceAttempt = 0.5, offRoute = 20 })))).toBe(false)
	end)
end)

describe("GuideRoute.arrival", function()
	it("hides the trail within the arrive distance and fades it back in over the band", function()
		expect(GuideRoute.arrival(8, 10, 4)).toBe(0)
		expect(GuideRoute.arrival(12, 10, 4)).toBeCloseTo(0.5)
		expect(GuideRoute.arrival(30, 10, 4)).toBe(1)
		expect(GuideRoute.arrival(10.5, 10, 0)).toBe(1)
	end)
end)
