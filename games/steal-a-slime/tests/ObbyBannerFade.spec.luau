--!strict
-- Which obby picture sign banners a runner sees (src/visuals/shared/ObbyBannerFade.luau; Merijn: a board the runner
-- has passed must not block the camera behind them): a banner hides once the root is HIDE_PAST beyond it along the
-- course, shows again once the root is back within SHOW_PAST (no flicker at the edge), always shows with no runner on
-- the course, and fades over SECONDS instead of popping.
local Config = require("../src/shared/Config")
local ObbyBannerFade = require("../src/visuals/shared/ObbyBannerFade")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local TUNE = Config.OBBY.BANNER_FADE
local EPS = 1e-6

describe("ObbyBannerFade.hidden", function()
	local at = 100

	it("shows a banner the runner is still before or under", function()
		expect(ObbyBannerFade.hidden(false, at - 30, at)).toBe(false)
		expect(ObbyBannerFade.hidden(false, at, at)).toBe(false)
		expect(ObbyBannerFade.hidden(false, at + TUNE.HIDE_PAST - 0.1, at)).toBe(false)
	end)

	it("hides a banner the runner has walked past", function()
		expect(ObbyBannerFade.hidden(false, at + TUNE.HIDE_PAST + 0.1, at)).toBe(true)
		expect(ObbyBannerFade.hidden(true, at + 50, at)).toBe(true)
	end)

	it("keeps a hidden banner hidden until the runner is back within SHOW_PAST", function()
		local between = at + (TUNE.HIDE_PAST + TUNE.SHOW_PAST) / 2
		expect(TUNE.SHOW_PAST < TUNE.HIDE_PAST).toBe(true)
		expect(ObbyBannerFade.hidden(true, between, at)).toBe(true)
		expect(ObbyBannerFade.hidden(false, between, at)).toBe(false)
		expect(ObbyBannerFade.hidden(true, at + TUNE.SHOW_PAST - 0.1, at)).toBe(false)
	end)

	it("shows every banner again after a reset to the start", function()
		local hidden = { true, true, true }
		local xs = { 40, 120, 200 }
		for i, x in xs do
			hidden[i] = ObbyBannerFade.hidden(hidden[i], 0, x)
			expect(hidden[i]).toBe(false)
		end
	end)

	it("shows every banner with no runner on the course", function()
		expect(ObbyBannerFade.hidden(true, nil, at)).toBe(false)
		expect(ObbyBannerFade.hidden(false, nil, at)).toBe(false)
	end)
end)

describe("ObbyBannerFade.step", function()
	it("fades out over SECONDS and stops at gone", function()
		local half = ObbyBannerFade.step(0, true, TUNE.SECONDS / 2)
		expect(half).toBeCloseTo(0.5, EPS)
		expect(ObbyBannerFade.step(half, true, TUNE.SECONDS)).toBe(1)
		expect(ObbyBannerFade.step(1, true, 1)).toBe(1)
	end)

	it("fades back in from wherever it was", function()
		expect(ObbyBannerFade.step(0.5, false, TUNE.SECONDS / 4)).toBeCloseTo(0.25, EPS)
		expect(ObbyBannerFade.step(0.25, false, 10)).toBe(0)
		expect(ObbyBannerFade.step(0, false, 0.1)).toBe(0)
	end)

	it("never moves backwards on a zero or negative frame time", function()
		expect(ObbyBannerFade.step(0.3, true, 0)).toBeCloseTo(0.3, EPS)
		expect(ObbyBannerFade.step(0.3, true, -1)).toBeCloseTo(0.3, EPS)
	end)
end)

describe("ObbyBannerFade.transparency", function()
	it("is the shown value at 0 and fully see-through at 1", function()
		expect(ObbyBannerFade.transparency(0, 0)).toBe(0)
		expect(ObbyBannerFade.transparency(0.4, 0)).toBeCloseTo(0.4, EPS)
		expect(ObbyBannerFade.transparency(0.4, 1)).toBe(1)
		expect(ObbyBannerFade.transparency(0, 0.5)).toBeCloseTo(0.5, EPS)
		expect(ObbyBannerFade.transparency(1, 0.5)).toBe(1)
	end)
end)
