--!strict
-- The Mystery Egg's glow on its pad: a gentle breathe that never goes dark or strobes.
local EggGlow = require("../src/visuals/shared/EggGlow")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local PROGRESSES = { 0, 0.25, 0.5, 0.76, 0.99, 1 }

-- Lowest and highest brightness over `seconds` of a 60 fps clock, and the biggest change between two frames.
local function sweep(f: (number) -> number, seconds: number): (number, number, number)
	local low, high, step = math.huge, -math.huge, 0
	local last = f(0)
	for frame = 0, seconds * 60 do
		local b = f(frame / 60)
		low, high = math.min(low, b), math.max(high, b)
		step = math.max(step, math.abs(b - last))
		last = b
	end
	return low, high, step
end

describe("EggGlow", function()
	it("breathes slowly at first and a little quicker near the hatch, never faster than MAX_RATE", function()
		expect(EggGlow.pulseRate(0)).toBe(EggGlow.MIN_RATE)
		expect(EggGlow.pulseRate(1)).toBe(EggGlow.MAX_RATE)
		expect(EggGlow.pulseRate(2)).toBe(EggGlow.MAX_RATE)
		expect(EggGlow.pulseRate(0.5) > EggGlow.pulseRate(0.25)).toBe(true)
		expect(EggGlow.MAX_RATE <= 1.5).toBe(true)
	end)

	it("never goes dark while incubating: it stays within its breathe below the base", function()
		for _, progress in PROGRESSES do
			local base = EggGlow.base(progress)
			local low, high = sweep(function(t)
				return EggGlow.incubating(progress, t)
			end, 6)
			expect(low >= base * (1 - EggGlow.DEPTH) - 1e-6).toBe(true)
			expect(high <= base + 1e-6).toBe(true)
			expect(low > 0).toBe(true)
		end
	end)

	it("changes only a little from one frame to the next, so it reads as a glow and not a flicker", function()
		for _, progress in PROGRESSES do
			local _, _, step = sweep(function(t)
				return EggGlow.incubating(progress, t)
			end, 6)
			expect(step < 0.05 * EggGlow.base(progress)).toBe(true)
		end
		local low, _, step = sweep(EggGlow.ready, 6)
		expect(low > 0).toBe(true)
		expect(step < 0.15).toBe(true)
	end)

	it("glows brighter the closer the hatch, and brightest once ready", function()
		expect(EggGlow.base(0.8) > EggGlow.base(0.2)).toBe(true)
		local readyLow = sweep(EggGlow.ready, 6)
		expect(readyLow >= EggGlow.READY_BASE - EggGlow.READY_SWING - 1e-6).toBe(true)
	end)
end)
