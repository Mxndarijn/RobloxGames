--!strict
-- CarryWriggle (src/visuals/shared/CarryWriggle.luau, contract/slime-life.md "Alive motion"): a carried slime
-- struggles in bursts with rests between, never one constant buzz, and two slimes don't struggle in step.
local CarryWriggle = require("../src/visuals/shared/CarryWriggle")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local FPS = 60

-- Mean angular speed (rad / s) of the wriggle in each `bucket`-second window.
local function speeds(seed: number, seconds: number, bucket: number): { number }
	local out = {}
	local pp, py, pr = CarryWriggle.pose(0, seed)
	local sum, n = 0, 0
	for f = 1, math.floor(seconds * FPS) do
		local p, y, r = CarryWriggle.pose(f / FPS, seed)
		sum += math.sqrt((p - pp) ^ 2 + (y - py) ^ 2 + (r - pr) ^ 2) * FPS
		n += 1
		pp, py, pr = p, y, r
		if n * (1 / FPS) >= bucket - 1e-9 then
			table.insert(out, sum / n)
			sum, n = 0, 0
		end
	end
	return out
end

describe("CarryWriggle", function()
	it("struggles in bursts: fast windows and calm windows", function()
		local s = speeds(42, 20, 0.25)
		local lo, hi = math.huge, 0
		for _, v in s do
			lo, hi = math.min(lo, v), math.max(hi, v)
		end
		expect(hi > 4 * lo).toBe(true)
		expect(hi > 4).toBe(true)
	end)

	it("spends some of every few seconds resting and some struggling", function()
		local busy, calm = 0, 0
		for f = 0, 20 * FPS do
			local k = CarryWriggle.effort(f / FPS, 7)
			if k > 0.9 then
				busy += 1
			elseif k < 0.1 then
				calm += 1
			end
		end
		local total = 20 * FPS
		expect(busy / total > 0.2 and busy / total < 0.7).toBe(true)
		expect(calm / total > 0.2).toBe(true)
	end)

	it("two slimes don't struggle in step", function()
		local same = 0
		for f = 0, 20 * FPS do
			local a = CarryWriggle.effort(f / FPS, 1) > 0.5
			local b = CarryWriggle.effort(f / FPS, 2) > 0.5
			if a == b then
				same += 1
			end
		end
		expect(same / (20 * FPS) < 0.85).toBe(true)
	end)

	it("stays inside sane angles and lift", function()
		for f = 0, 30 * FPS do
			local p, y, r, lift = CarryWriggle.pose(f / FPS, 99)
			expect(math.abs(p) < 0.3 and math.abs(y) < 0.7 and math.abs(r) < 0.45).toBe(true)
			expect(lift >= 0 and lift < 0.25).toBe(true)
		end
	end)

	it("moves smoothly between frames (no jump in or out of a burst)", function()
		local pp, py, pr = CarryWriggle.pose(0, 5)
		for f = 1, 30 * FPS do
			local p, y, r = CarryWriggle.pose(f / FPS, 5)
			-- the fastest in-burst wriggle moves about 0.31 rad a frame over the three axes; nothing jumps past that
			expect(math.abs(p - pp) + math.abs(y - py) + math.abs(r - pr) < 0.35).toBe(true)
			pp, py, pr = p, y, r
		end
	end)
end)
