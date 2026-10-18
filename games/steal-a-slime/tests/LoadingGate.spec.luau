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
	it("starts empty on the place label and stays up", function()
		local v = LoadingGate.step(status(), 0)
		expect(v.progress).toBe(0)
		expect(v.label).toBe(LoadingGate.LABELS.place)
		expect(v.lift).toBe(false)
		expect(v.canSkip).toBe(false)
	end)
	it("waits for the world meshes once the place is loaded", function()
		local v = LoadingGate.step(status({ gameLoaded = true }), 3)
		expect(v.label).toBe(LoadingGate.LABELS.world)
		expect(v.progress).toBe(LoadingGate.WEIGHTS.gameLoaded)
		expect(v.lift).toBe(false)
	end)
	it("fills the preload share as assets answer", function()
		local half =
			LoadingGate.step(status({ gameLoaded = true, worldReady = true, preloaded = 50, preloadTotal = 100 }), 3)
		expect(half.label).toBe(LoadingGate.LABELS.assets)
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
		expect(v.label).toBe(LoadingGate.LABELS.done)
	end)
	it("offers a skip at SKIP_AFTER and lifts at MAX_WAIT whatever is still loading", function()
		expect(LoadingGate.step(status(), LoadingGate.SKIP_AFTER).canSkip).toBe(true)
		expect(LoadingGate.step(status(), LoadingGate.MAX_WAIT - 0.1).lift).toBe(false)
		expect(LoadingGate.step(status(), LoadingGate.MAX_WAIT).lift).toBe(true)
	end)
end)
