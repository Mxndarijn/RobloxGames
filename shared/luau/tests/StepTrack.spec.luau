--!strict
local StepTrack = require("../src/core/StepTrack")
local T = require("../testing/TestRunner")
local describe, it, expect = T.describe, T.it, T.expect

local FPS = 60

-- A value moving at `speed` units / s that arrives every `every` frames; returns per-frame drawn x.
local function run(speed: number, every: number, seconds: number): ({ number }, { number })
	local truth = 0
	local input = 0
	local track = StepTrack.new(0, 0, 0, 0)
	local drawn, truths = {}, {}
	for f = 1, math.floor(seconds * FPS) do
		local now = f / FPS
		truth = speed * now
		if f % every == 0 then
			input = truth
		end
		local x = StepTrack.step(track, input, 0, 0, now)
		table.insert(drawn, x)
		table.insert(truths, truth)
	end
	return drawn, truths
end

describe("StepTrack", function()
	it("draws a stepwise steady walk as an even glide", function()
		local drawn = run(6, 2, 3) -- 30 Hz input at 60 fps
		-- after it locks on, every frame moves about the same distance (no still frame, no double step)
		local worst = 0
		for i = 90, #drawn do
			local step = drawn[i] - drawn[i - 1]
			worst = math.max(worst, math.abs(step - 6 / FPS) / (6 / FPS))
		end
		expect(worst < 0.15).toBe(true)
	end)

	it("the raw input judders (sanity check for the test above)", function()
		local _, truths = run(6, 2, 1)
		local input, worst = 0, 0
		local prev = 0
		for f, truth in truths do
			if f % 2 == 0 then
				input = truth
			end
			worst = math.max(worst, math.abs((input - prev) - 6 / FPS) / (6 / FPS))
			prev = input
		end
		expect(worst >= 0.9).toBe(true)
	end)

	it("stays close behind the true spot", function()
		local drawn, truths = run(10, 3, 3) -- 20 Hz input
		for i = 90, #drawn do
			expect(math.abs(drawn[i] - truths[i]) < 0.6).toBe(true)
		end
	end)

	it("stops without running far past the last input", function()
		local track = StepTrack.new(0, 0, 0, 0)
		local input = 0
		for f = 1, 60 do
			if f % 2 == 0 then
				input = 6 * f / FPS
			end
			StepTrack.step(track, input, 0, 0, f / FPS)
		end
		local last = input
		local x = 0
		for f = 61, 120 do
			x = StepTrack.step(track, last, 0, 0, f / FPS)
		end
		expect(math.abs(x - last) < 0.05).toBe(true)
	end)

	it("snaps on a teleport", function()
		local track = StepTrack.new(0, 0, 0, 0)
		StepTrack.step(track, 0, 0, 0, 1 / 60)
		local x, y, z = StepTrack.step(track, 50, 2, -3, 2 / 60)
		expect(x).toBe(50)
		expect(y).toBe(2)
		expect(z).toBe(-3)
	end)

	it("tracks height too (a slide)", function()
		local track = StepTrack.new(0, 10, 0, 0)
		local y = 10
		for f = 1, 120 do
			local input = 10 - 3 * math.floor(f / 2) * 2 / FPS
			_, y = StepTrack.step(track, 0, input, 0, f / FPS)
		end
		expect(y < 4.3 and y > 3.5).toBe(true)
	end)

	it("turns a heading the shortest way round and snaps a big jump", function()
		local a = StepTrack.angle(3.0, -3.0, 1 / 60) -- across +-pi
		expect(a > 3.0 or a < -3.0).toBe(true)
		expect(StepTrack.angle(0, 2.5, 1 / 60)).toBeCloseTo(2.5, 6)
		local b = 0
		for _ = 1, 60 do
			b = StepTrack.angle(b, 1, 1 / 60)
		end
		expect(b).toBeCloseTo(1, 3)
	end)
end)
