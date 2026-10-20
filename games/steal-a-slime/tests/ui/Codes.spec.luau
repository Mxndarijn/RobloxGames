--!strict
-- Codes panel (src/ui/Panels/Codes.luau): ink text box, green Redeem, boost chip.
local Config = require("../../src/shared/Config")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function build(now: number?): (any, { any })
	local sent = {}
	local ctx: any = {
		Config = Config,
		send = function(...)
			table.insert(sent, { ... })
		end,
		serverNow = function()
			return now or 0
		end,
	}
	return UiHarness.ui("Panels/Codes").new(UiHarness.root(), ctx), sent
end

describe("Codes panel", function()
	it("is an ink well input over a full-width green Redeem, no second gift icon", function()
		local Theme = UiHarness.ui("Widgets").Theme
		local panel = build()
		local box = UiHarness.find(panel.frame, "CodeBox")
		expect(box.BackgroundColor3).toBe(Theme.Ink)
		expect(box.PlaceholderColor3).toBe(Theme.Muted)
		local redeem = UiHarness.find(panel.frame, "RedeemButton")
		expect(redeem.Text).toBe("Redeem")
		expect(redeem.BackgroundColor3).toBe(Theme.Good)
		expect(redeem.Size.X.Scale).toBe(1)
	end)
	it("sends the trimmed code from Redeem and clears the box once a code counts", function()
		local panel, sent = build()
		local box = UiHarness.find(panel.frame, "CodeBox")
		panel.update({ codes = { redeemed = 0, boostMult = 1, boostEndsAt = 0 } })
		box.Text = "  SLIME  "
		UiHarness.fire(UiHarness.find(panel.frame, "RedeemButton"), "Activated")
		expect(#sent).toBe(1)
		expect(sent[1][1]).toBe("Redeem")
		expect(sent[1][2]).toBe("SLIME")
		panel.update({ codes = { redeemed = 1, boostMult = 1, boostEndsAt = 0 } })
		expect(box.Text).toBe("")
	end)
	it("shows the boost as a chip: muted when none, gold with the potion while active", function()
		local Theme = UiHarness.ui("Widgets").Theme
		local panel = build(100)
		local chip = UiHarness.find(panel.frame, "Boost")
		panel.update({ codes = { redeemed = 0, boostMult = 1, boostEndsAt = 0 } })
		expect(chip.Text).toBe("No boost active")
		expect(chip.TextColor3).toBe(Theme.Muted)
		expect(chip.Size.Y.Offset < 40).toBe(true)
		panel.update({ codes = { redeemed = 1, boostMult = 2, boostEndsAt = 400 } })
		expect(chip.TextColor3).toBe(Theme.Gold)
		expect(string.find(chip.Text, "income", 1, true) ~= nil).toBe(true)
		expect(UiHarness.find(panel.frame, "BoostIcon").Visible).toBe(true)
	end)
end)
