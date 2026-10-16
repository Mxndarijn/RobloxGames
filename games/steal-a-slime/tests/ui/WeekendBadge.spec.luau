--!strict
local MenuState = require("../../src/ui/MenuState")
local TestRunner = require("../TestRunner")
local WeekendBadge = require("../../src/ui/WeekendBadge")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("WeekendBadge", function()
	it("shows the multiplier and the time left", function()
		expect(WeekendBadge.banner({ active = true, multiplier = 2, endsAt = 1000 + 100800 }, 1000)).toBe(
			"💰 x2 Weekend - 1d 4h left"
		)
		expect(WeekendBadge.banner({ active = true, multiplier = 2, endsAt = 1000 + 5 * 3600 + 720 }, 1000)).toBe(
			"💰 x2 Weekend - 5h 12m left"
		)
		expect(WeekendBadge.banner({ active = true, multiplier = 2, endsAt = 1000 + 125 }, 1000)).toBe(
			"💰 x2 Weekend - 2:05 left"
		)
		expect(WeekendBadge.banner({ active = true, multiplier = 2 }, 1000)).toBe("💰 x2 Weekend")
	end)
	it("hides while off, over, malformed or missing", function()
		expect(WeekendBadge.banner(nil, 0)).toBeNil()
		expect(WeekendBadge.banner({ active = false, multiplier = 1 }, 0)).toBeNil()
		expect(WeekendBadge.banner({ active = true, multiplier = 1 }, 0)).toBeNil()
		expect(WeekendBadge.banner({ active = true, multiplier = 2, endsAt = 10 }, 10)).toBeNil()
	end)
	it("lives in the banner stack, which hides while a menu is open", function()
		expect(MenuState.bannersVisible(nil)).toBe(true)
		expect(MenuState.bannersVisible("Shop")).toBe(false)
	end)
end)
