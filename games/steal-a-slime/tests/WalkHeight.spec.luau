--!strict
-- A slime walking back to the lane follows small steps and falls off ledges (server/WalkHeight).
local TestRunner = require("./TestRunner")
local WalkHeight = require("../src/server/WalkHeight")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local DT = 1 / 60

-- Steps `state` over a fixed `ground` until it settles or `seconds` pass; returns the state and seconds taken.
local function run(state: WalkHeight.State, ground: number?, seconds: number): (WalkHeight.State, number)
	local t = 0
	while t < seconds do
		state = WalkHeight.step(state, ground, DT)
		t += DT
		if ground and state.vy == 0 and math.abs(state.y - ground) < 1e-3 then
			break
		end
	end
	return state, t
end

describe("WalkHeight", function()
	it("eases onto a small step down without falling", function()
		local s = WalkHeight.step(WalkHeight.new(1), 1 - WalkHeight.STEP_DOWN * 0.8, DT)
		expect(WalkHeight.falling(s)).toBe(false)
		expect(s.y < 1).toBe(true)
		local settled = run(s, 1 - WalkHeight.STEP_DOWN * 0.8, 2)
		expect(math.abs(settled.y - (1 - WalkHeight.STEP_DOWN * 0.8)) < 0.01).toBe(true)
	end)

	it("eases up a step instead of snapping", function()
		local s = WalkHeight.step(WalkHeight.new(0), 1, DT)
		expect(s.y > 0 and s.y < 1).toBe(true)
		expect(WalkHeight.falling(s)).toBe(false)
	end)

	it("falls off a ledge and lands on the ground below", function()
		-- the fountain dome (about 36) down to the plaza (0)
		local s = WalkHeight.step(WalkHeight.new(36), 0, DT)
		expect(WalkHeight.falling(s)).toBe(true)
		local landed, seconds = run(s, 0, 5)
		expect(landed.y).toBe(0)
		expect(landed.vy).toBe(0)
		-- a free fall: sqrt(2 * 36 / GRAVITY) seconds, not an ease that hangs in the air
		local expected = math.sqrt(2 * 36 / WalkHeight.GRAVITY)
		expect(math.abs(seconds - expected) < 0.1).toBe(true)
	end)

	it("speeds up as it falls", function()
		local a = WalkHeight.step(WalkHeight.new(30), 0, DT)
		local b = WalkHeight.step(a, 0, DT)
		expect(30 - a.y < a.y - b.y).toBe(true)
	end)

	it("never ends a fall under the ground", function()
		local s = WalkHeight.new(10)
		for _ = 1, 600 do
			s = WalkHeight.step(s, 2, DT)
			expect(s.y >= 2).toBe(true)
		end
	end)

	it("keeps falling onto lower ground that turns up mid-fall", function()
		local s = WalkHeight.step(WalkHeight.new(20), 10, DT)
		s = WalkHeight.step(s, 0, DT) -- walked past the lower roof's edge
		expect(WalkHeight.falling(s)).toBe(true)
		local landed = run(s, 0, 5)
		expect(landed.y).toBe(0)
	end)

	it("keeps its height with nothing below", function()
		local s = WalkHeight.step(WalkHeight.new(12), nil, DT)
		expect(s.y).toBe(12)
		expect(WalkHeight.falling(s)).toBe(false)
	end)
end)
