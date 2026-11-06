--!strict
-- The join loading screen: what the bar and label show and when the screen lifts.
local LoadingGate = require("../src/first/LoadingGate")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function status(over: { [string]: any }?): LoadingGate.Status
	local s: { [string]: any } =
		{ gameLoaded = false, worldReady = false, preloaded = 0, preloadTotal = 0, preloadDone = false }
	for k, v in over or {} do
		s[k] = v
	end
	return s :: any
end

describe("loading gate", function()
	it("starts empty on a tip and stays up", function()
		local v = LoadingGate.step(status(), 0)
		expect(v.progress).toBe(0)
		expect(v.label).toBe(LoadingGate.TIPS[1])
		expect(v.lift).toBe(false)
		expect(v.canSkip).toBe(false)
	end)
	it("waits for the world meshes once the place is loaded", function()
		local v = LoadingGate.step(status({ gameLoaded = true }), 3)
		expect(v.progress).toBe(LoadingGate.WEIGHTS.gameLoaded)
		expect(v.lift).toBe(false)
	end)
	it("fills the preload share as assets answer", function()
		local half =
			LoadingGate.step(status({ gameLoaded = true, worldReady = true, preloaded = 50, preloadTotal = 100 }), 3)
		local w = LoadingGate.WEIGHTS
		expect(math.abs(half.progress - (w.gameLoaded + w.worldReady + w.preload / 2)) < 1e-9).toBe(true)
		expect(half.lift).toBe(false)
	end)
	it("never shows a full bar before everything is ready", function()
		local v =
			LoadingGate.step(status({ gameLoaded = true, worldReady = true, preloaded = 100, preloadTotal = 100 }), 3)
		expect(v.progress < 1).toBe(true)
	end)
	it("lifts when everything is ready, but not before MIN_SHOW", function()
		local ready = status({ gameLoaded = true, worldReady = true, preloadDone = true })
		expect(LoadingGate.step(ready, 0).lift).toBe(false)
		local v = LoadingGate.step(ready, LoadingGate.MIN_SHOW)
		expect(v.lift).toBe(true)
		expect(v.progress).toBe(1)
		expect(v.label).toBe(LoadingGate.DONE)
	end)
	it("offers a skip at SKIP_AFTER and lifts at MAX_WAIT whatever is still loading", function()
		expect(LoadingGate.step(status(), LoadingGate.SKIP_AFTER).canSkip).toBe(true)
		expect(LoadingGate.step(status(), LoadingGate.MAX_WAIT - 0.1).lift).toBe(false)
		expect(LoadingGate.step(status(), LoadingGate.MAX_WAIT).lift).toBe(true)
	end)

	it("changes the tip every TIP_EVERY seconds, from the chosen first tip, and wraps", function()
		local tips, every = LoadingGate.TIPS, LoadingGate.TIP_EVERY
		expect(LoadingGate.tip(0, 3)).toBe(tips[3])
		expect(LoadingGate.tip(every - 0.01, 3)).toBe(tips[3])
		expect(LoadingGate.tip(every, 3)).toBe(tips[4])
		expect(LoadingGate.tip(every * #tips, 3)).toBe(tips[3])
		expect(LoadingGate.step(status(), every, 2).label).toBe(tips[3])
	end)
	it("keeps every tip short enough for one line on a phone", function()
		for _, tip in LoadingGate.TIPS do
			expect(#tip <= 32).toBe(true)
		end
	end)
end)

describe("loading bar glide", function()
	local function run(target: number, seconds: number, from: number?): number
		local shown = from or 0
		for _ = 1, math.floor(seconds * 60) do
			shown = LoadingGate.glide(shown, target, 1 / 60)
		end
		return shown
	end
	it("slides toward the target instead of jumping", function()
		local one = LoadingGate.glide(0, 0.5, 1 / 60)
		expect(one > 0 and one < 0.1).toBe(true)
		expect(math.abs(run(0.5, 2) - 0.5) < 0.03).toBe(true)
	end)
	it("keeps creeping while a stage waits, but only a little past the real progress", function()
		local held = run(0.2, 30)
		expect(held > 0.2).toBe(true)
		expect(held <= 0.2 + LoadingGate.CREEP_LEAD + 1e-9).toBe(true)
	end)
	it("never moves back, and never shows full before the target is 1", function()
		expect(LoadingGate.glide(0.6, 0.3, 1 / 60)).toBe(0.6)
		expect(run(0.99, 60) <= 0.99).toBe(true)
	end)
	it("fills fast once everything is ready", function()
		expect(run(1, 0.5, 0.6) > 0.995).toBe(true)
	end)
end)
