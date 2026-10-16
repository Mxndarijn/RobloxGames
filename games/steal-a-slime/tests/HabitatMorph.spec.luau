--!strict
local Config = require("../src/shared/Config")
local HabitatMorph = require("../src/shared/HabitatMorph")
local Habitats = require("../src/shared/Habitats")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local cfg = Config.HABITAT_ANIM

describe("HabitatMorph.propScale", function()
	it("is exactly 1 at weight 1 and the floor at weight 0 for every quality", function()
		for _, q in { "full", "simple", "snap" } :: { HabitatMorph.Quality } do
			for n = 1, 5 do
				for i = 1, n do
					expect(HabitatMorph.propScale(q, 1, i, n, true, cfg)).toBe(1)
					expect(HabitatMorph.propScale(q, 1, i, n, false, cfg)).toBe(1)
					expect(HabitatMorph.propScale(q, 0, i, n, true, cfg)).toBe(HabitatMorph.FLOOR)
				end
			end
		end
	end)
	it("staggers: a later prop starts after an earlier one", function()
		local first = HabitatMorph.propScale("full", 0.2, 1, 5, true, cfg)
		local last = HabitatMorph.propScale("full", 0.2, 5, 5, true, cfg)
		expect(first > last).toBe(true)
		expect(last).toBe(HabitatMorph.FLOOR) -- 0.2 < STAGGER: not started
	end)
	it("overshoots 1 while rising but never while shrinking", function()
		local peakUp, peakDown = 0, 0
		for k = 1, 99 do
			peakUp = math.max(peakUp, HabitatMorph.propScale("full", k / 100, 1, 4, true, cfg))
			peakDown = math.max(peakDown, HabitatMorph.propScale("full", k / 100, 1, 4, false, cfg))
		end
		expect(peakUp > 1).toBe(true)
		expect(peakUp < 1.25).toBe(true)
		expect(peakDown <= 1).toBe(true)
	end)
	it("the simple tier never overshoots or staggers", function()
		for k = 0, 100 do
			local w = k / 100
			expect(HabitatMorph.propScale("simple", w, 1, 4, true, cfg)).toBe(
				HabitatMorph.propScale("simple", w, 4, 4, true, cfg)
			)
			expect(HabitatMorph.propScale("simple", w, 1, 4, true, cfg) <= 1).toBe(true)
		end
	end)
	it("leaves in reverse order: the last prop is gone first", function()
		local w = 0.3
		expect(
			HabitatMorph.propScale("full", w, 5, 5, false, cfg) < HabitatMorph.propScale("full", w, 1, 5, false, cfg)
		).toBe(true)
	end)
end)

describe("HabitatMorph.quality / burst / tint", function()
	it("snaps for reduced motion, far away, or too many morphing pads", function()
		expect(HabitatMorph.quality(cfg, true, 5, 0)).toBe("snap")
		expect(HabitatMorph.quality(cfg, false, cfg.SNAP_BEYOND + 1, 0)).toBe("snap")
		expect(HabitatMorph.quality(cfg, false, 5, cfg.MAX_ANIMATING)).toBe("snap")
	end)
	it("full when near (or no camera), simple at mid distance", function()
		expect(HabitatMorph.quality(cfg, false, nil, 0)).toBe("full")
		expect(HabitatMorph.quality(cfg, false, 10, cfg.MAX_ANIMATING - 1)).toBe("full")
		expect(HabitatMorph.quality(cfg, false, cfg.SNAP_BEYOND * 0.75, 0)).toBe("simple")
	end)
	it("puff size follows the quality; snap has none", function()
		expect(HabitatMorph.burst(cfg, "full")).toBe(cfg.BURST_FULL)
		expect(HabitatMorph.burst(cfg, "simple") < cfg.BURST_FULL).toBe(true)
		expect(HabitatMorph.burst(cfg, "snap")).toBe(0)
	end)
	it("tint is 0 at base, 1 by half way", function()
		expect(HabitatMorph.tint(0)).toBe(0)
		expect(HabitatMorph.tint(0.5)).toBe(1)
		expect(HabitatMorph.tint(1)).toBe(1)
	end)
	it("one whole morph still takes Habitats.TRANSFORM_SECONDS", function()
		expect(Habitats.TRANSFORM_SECONDS).toBe(1)
	end)
end)
