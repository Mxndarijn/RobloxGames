--!strict
-- The join loading screen wears the HUD's Goo palette, not a look of its own.
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("loading screen look", function()
	it("matches the HUD palette (Widgets.Theme)", function()
		local Theme = UiHarness.ui("Widgets").Theme
		local Look = UiHarness.ui("../first/LoadingLook")
		for key, themeKey in { bg = "Bg", barBack = "Ink", bar = "Good", text = "Text", muted = "Muted" } do
			expect(Look[key] == Theme[themeKey]).toBe(true)
		end
		expect(Look.font == Theme.Font).toBe(true)
	end)
end)
