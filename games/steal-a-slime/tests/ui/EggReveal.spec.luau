--!strict
local EggReveal = require("../../src/ui/EggReveal")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function nameOf(slime: any): string
	return `Epic {slime.name}`
end

describe("EggReveal.banner", function()
	local view = { hatched = { slime = { name = "Blorp" }, at = 100 } }
	it("names the hatched slime while fresh", function()
		expect(EggReveal.banner(view, 103, 6, nameOf)).toBe("🥚 Hatched! Epic Blorp")
	end)
	it("hides when old, empty or nil", function()
		expect(EggReveal.banner(view, 107, 6, nameOf)).toBeNil()
		expect(EggReveal.banner({}, 100, 6, nameOf)).toBeNil()
		expect(EggReveal.banner(nil, 100, 6, nameOf)).toBeNil()
	end)
end)
