--!strict
-- Shared Fun item geometry (src/shared/PvpFunRules, CONTRACT.md §26.8): what server and client agree on.
local Config = require("../src/shared/Config")
local PvpFunRules = require("../src/shared/PvpFunRules")
local TestRunner = require("./TestRunner")
local roblox = require("@lune/roblox")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local FUN = Config.PVP_FUN
local O = { X = 0, Y = 3, Z = 0 }

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

describe("PvpFunRules aims", function()
	it("reads a Vector3 or a table, refuses junk", function()
		local v = PvpFunRules.vec(roblox.Vector3.new(1, 2, 3)) :: any
		expect(v.X + v.Y + v.Z).toBe(6)
		expect(PvpFunRules.vec({ X = 0 / 0, Y = 0, Z = 0 })).toBe(nil)
		expect(PvpFunRules.vec({ X = math.huge, Y = 0, Z = 0 })).toBe(nil)
		expect(PvpFunRules.vec("x")).toBe(nil)
		expect(PvpFunRules.vec(nil)).toBe(nil)
	end)
	it("pulls a far aim in along its direction, never pushes a near one out", function()
		local p = PvpFunRules.within(O, { X = 100, Y = 3, Z = 0 }, 10)
		expect(near(p.X, 10) and near(p.Y, 3)).toBe(true)
		expect(PvpFunRules.within(O, { X = 4, Y = 3, Z = 0 }, 10).X).toBe(4)
		local flat = PvpFunRules.withinFlat(O, { X = 0, Y = 50, Z = 100 }, 20)
		expect(near(flat.Z, 20) and flat.Y == 50).toBe(true)
	end)
	it("a lob aimed at the sky lands at the user's feet height; a ground aim keeps its height", function()
		expect(PvpFunRules.landing(O, { X = 5, Y = 200, Z = 0 }, 40).Y).toBe(O.Y - PvpFunRules.FEET)
		expect(PvpFunRules.landing(O, { X = 5, Y = 1, Z = 0 }, 40).Y).toBe(1)
		expect(PvpFunRules.landing(O, { X = 5, Y = -500, Z = 0 }, 40).Y).toBe(O.Y - PvpFunRules.FEET)
	end)
	it("lob flights are clamped between the shortest and longest flight", function()
		expect(PvpFunRules.flightTime(O, O)).toBe(FUN.THROW_MIN_SECONDS)
		expect(PvpFunRules.flightTime(O, { X = 1e4, Y = 0, Z = 0 })).toBe(FUN.THROW_MAX_SECONDS)
		local mid = PvpFunRules.flightTime(O, { X = FUN.THROW_SPEED * 0.6, Y = 3, Z = 0 })
		expect(near(mid, 0.6)).toBe(true)
	end)
end)

describe("PvpFunRules bubbles", function()
	local stream = { origin = O, direction = { X = 1, Y = 0, Z = 0 }, startedAt = 100 }
	it("each bubble is blown SPACING after the last, floats along and rises, then is gone", function()
		expect(PvpFunRules.bubbleAt(stream, 2, 100)).toBe(nil) -- not blown yet
		local first = PvpFunRules.bubbleAt(stream, 1, 101) :: any
		expect(near(first.X, FUN.BUBBLES.SPEED) and near(first.Y, O.Y + FUN.BUBBLES.RISE)).toBe(true)
		local born = PvpFunRules.bubbleBorn(stream, 3)
		expect(near(born, 100 + 2 * FUN.BUBBLES.SPACING)).toBe(true)
		expect(PvpFunRules.bubbleAt(stream, 1, 100 + FUN.BUBBLES.LIFETIME + 0.01)).toBe(nil)
		expect(PvpFunRules.streamEnds(stream) >= born + FUN.BUBBLES.LIFETIME).toBe(true)
	end)
end)

describe("PvpFunRules hat shot", function()
	it("hits the candidate nearest the muzzle within the radius, else ends at the range", function()
		local dir = { X = 1, Y = 0, Z = 0 }
		local list = {
			{ id = 1, position = { X = 20, Y = 3, Z = 1 } },
			{ id = 2, position = { X = 10, Y = 3, Z = -2 } },
			{ id = 3, position = { X = 5, Y = 3, Z = 9 } }, -- off the line
		}
		local hit, finish = PvpFunRules.firstHit(O, dir, 40, 3, list)
		expect((hit :: any).id).toBe(2)
		expect(finish.X).toBe(10)
		local miss, far = PvpFunRules.firstHit(O, dir, 40, 3, { list[3] })
		expect(miss).toBe(nil)
		expect(far.X).toBe(40)
	end)
	it("hats stack while the last is still on, up to MAX_STACK", function()
		expect(PvpFunRules.hatStack(0, false)).toBe(1)
		expect(PvpFunRules.hatStack(1, true)).toBe(2)
		expect(PvpFunRules.hatStack(FUN.HATS.MAX_STACK, true)).toBe(FUN.HATS.MAX_STACK)
		expect(PvpFunRules.hatStack(2, false)).toBe(1)
	end)
end)

describe("PvpFunRules hammer combo", function()
	it("COMBO_HITS hits on one target within the window make a combo, then it starts over", function()
		local c, combo = PvpFunRules.combo(nil, "p2", 0)
		expect(combo).toBe(false)
		for i = 2, FUN.HAMMER.COMBO_HITS do
			c, combo = PvpFunRules.combo(c, "p2", (i - 1) * 1.5)
		end
		expect(combo).toBe(true)
		expect(c.count).toBe(0)
	end)
	it("another target or a slow hit starts a new count", function()
		local c = PvpFunRules.combo(nil, "p2", 0)
		c = PvpFunRules.combo(c, "sgem", 1)
		expect(c.key).toBe("sgem")
		expect(c.count).toBe(1)
		c = PvpFunRules.combo(c, "sgem", 1 + FUN.HAMMER.COMBO_WINDOW + 0.1)
		expect(c.count).toBe(1)
	end)
end)
