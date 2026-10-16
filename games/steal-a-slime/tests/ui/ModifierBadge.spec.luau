--!strict
local ModifierBadge = require("../../src/ui/ModifierBadge")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("ModifierBadge.banner", function()
	local luck = { name = "LuckSurge", label = "Luck Surge", luck = 2, mutation = 1, endsAt = 200 }
	it("shows name, multiplier and time left", function()
		expect(ModifierBadge.banner(luck, 80, true)).toBe("Luck Surge x2 luck - 2:00 left")
	end)
	it("lists both multipliers", function()
		local both = { name = "GoldenHour", label = "Golden Hour", luck = 1.5, mutation = 2, endsAt = 200 }
		expect(ModifierBadge.banner(both, 140, true)).toBe("Golden Hour x1.5 luck, x2 mutations - 1:00 left")
	end)
	it("hides for None, nil, expired or the feature off", function()
		expect(ModifierBadge.banner({ name = "None", label = "None", luck = 1, mutation = 1, endsAt = 200 }, 0, true)).toBeNil()
		expect(ModifierBadge.banner(nil, 0, true)).toBeNil()
		expect(ModifierBadge.banner(luck, 200, true)).toBeNil()
		expect(ModifierBadge.banner(luck, 0, false)).toBeNil()
	end)
end)
