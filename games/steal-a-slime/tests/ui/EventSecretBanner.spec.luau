--!strict
local EventSecretBanner = require("../../src/ui/EventSecretBanner")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("EventSecretBanner", function()
	local function view(endsAt: number): any
		return { id = "kitsune", name = "Kitsune", endsAt = endsAt }
	end
	it("names the featured Secret with days and hours left", function()
		expect(EventSecretBanner.banner(view(1000 + 3 * 86400 + 4 * 3600), 1000)).toBe(
			"✨ Featured Secret this week: Kitsune (ends in 3d 4h)"
		)
	end)
	it("shows hours and minutes below a day, m:ss in the last hour", function()
		expect(EventSecretBanner.banner(view(1000 + 5 * 3600 + 720), 1000)).toBe(
			"✨ Featured Secret this week: Kitsune (ends in 5h 12m)"
		)
		expect(EventSecretBanner.banner(view(1000 + 125), 1000)).toBe(
			"✨ Featured Secret this week: Kitsune (ends in 2:05)"
		)
	end)
	it("is nil when absent, malformed or over", function()
		expect(EventSecretBanner.banner(nil, 0)).toBeNil()
		expect(EventSecretBanner.banner({ id = "kitsune", name = "", endsAt = 100 } :: any, 0)).toBeNil()
		expect(EventSecretBanner.banner({ id = "kitsune", name = "Kitsune" } :: any, 0)).toBeNil()
		expect(EventSecretBanner.banner(view(0 / 0), 0)).toBeNil()
		expect(EventSecretBanner.banner(view(10), 10)).toBeNil()
	end)
end)
