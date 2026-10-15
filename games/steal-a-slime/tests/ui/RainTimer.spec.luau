--!strict
-- Slime Rain HUD banner (src/ui/RainTimer.luau, CONTRACT §5.1 / §5.2).
local RainTimer = require("../../src/ui/RainTimer")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("RainTimer.fromAttributes", function()
	it("needs a boolean RainActive", function()
		expect(RainTimer.fromAttributes(nil, 100, nil)).toBeNil()
		expect(RainTimer.fromAttributes("yes", 100, nil)).toBeNil()
	end)
	it("keeps numeric times and drops others", function()
		local rain = RainTimer.fromAttributes(true, 150, "soon") :: RainTimer.Rain
		expect(rain.active).toBe(true)
		expect(rain.endsAt).toBe(150)
		expect(rain.nextAt).toBeNil()
	end)
end)

describe("RainTimer.resolve", function()
	it("prefers the workspace attributes over State.rain", function()
		local attrs = RainTimer.fromAttributes(false, nil, 500)
		local rain = RainTimer.resolve(attrs, { active = true, endsAt = 10 }) :: RainTimer.Rain
		expect(rain.active).toBe(false)
		expect(rain.nextAt).toBe(500)
	end)
	it("falls back to State.rain, then nil", function()
		local rain = RainTimer.resolve(nil, { active = true, endsAt = 10 }) :: RainTimer.Rain
		expect(rain.active).toBe(true)
		expect(rain.endsAt).toBe(10)
		expect(RainTimer.resolve(nil, nil)).toBeNil()
		expect(RainTimer.resolve(nil, { active = "no" })).toBeNil()
	end)
end)

describe("RainTimer.banner", function()
	it("counts down an active rain", function()
		local banner = RainTimer.banner({ active = true, endsAt = 1151 }, 1000, 3) :: RainTimer.Banner
		expect(banner.kind).toBe("active")
		expect(banner.text).toBe("SLIME RAIN! Luck x3 - 2:31 left")
	end)
	it("shows an active rain without an end time", function()
		expect((RainTimer.banner({ active = true }, 0, 3) :: RainTimer.Banner).text).toBe("SLIME RAIN! Luck x3")
	end)
	it("announces the next rain only when it's close", function()
		local soon = RainTimer.banner({ active = false, nextAt = 1065 }, 1000, 3) :: RainTimer.Banner
		expect(soon.kind).toBe("soon")
		expect(soon.text).toBe("Slime Rain in 1:05")
		expect(RainTimer.banner({ active = false, nextAt = 1000 + RainTimer.SOON_SECONDS + 1 }, 1000, 3)).toBeNil()
		expect(RainTimer.banner({ active = false, nextAt = 900 }, 1000, 3)).toBeNil()
		expect(RainTimer.banner({ active = false }, 1000, 3)).toBeNil()
		expect(RainTimer.banner(nil, 1000, 3)).toBeNil()
	end)
end)
