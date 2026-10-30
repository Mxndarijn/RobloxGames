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
	it("a refused code turns the box's outline pink and says why under it, until the box is edited again", function()
		local Theme = UiHarness.ui("Widgets").Theme
		local Codes = UiHarness.ui("Panels/Codes")
		local asked = {}
		local ctx: any = {
			Config = Config,
			send = function() end,
			ask = function(action: string, done: any, ...: any)
				table.insert(asked, { action = action, done = done, args = { ... } })
			end,
			serverNow = function()
				return 0
			end,
		}
		local panel = Codes.new(UiHarness.root(), ctx)
		panel.update({ codes = { redeemed = 0, boostMult = 1, boostEndsAt = 0 } })
		local box = UiHarness.find(panel.frame, "CodeBox")
		local redeem = UiHarness.find(panel.frame, "RedeemButton")
		local buttonY = redeem.Position.Y.Offset
		box.Text = "SLIMEBOOST"
		UiHarness.fire(redeem, "Activated")
		expect(asked[1].action).toBe("Redeem")
		expect(asked[1].args[1]).toBe("SLIMEBOOST")
		asked[1].done({ ok = false, message = "You already used that code" })
		local err = UiHarness.find(panel.frame, "Error")
		expect(err.Visible).toBe(true)
		expect(err.Text).toBe("You already used that code.")
		expect(err.TextColor3).toBe(Theme.Bad)
		expect(box:FindFirstChildOfClass("UIStroke").Color).toBe(Theme.Bad)
		expect(redeem.Position.Y.Offset > buttonY).toBe(true) -- the line pushes the rows down, nothing overlaps
		UiHarness.fire(box, "Focused")
		expect(err.Visible).toBe(false)
		expect(box:FindFirstChildOfClass("UIStroke").Color).toBe(Theme.Ink)
		expect(redeem.Position.Y.Offset).toBe(buttonY)
	end)
	it("the card grows to fit the error line, so the content never needs a scroll bar", function()
		local Codes = UiHarness.ui("Panels/Codes")
		local Widgets = UiHarness.ui("Widgets")
		local asked, relayouts = {}, 0
		local ctx: any = {
			Config = Config,
			send = function() end,
			ask = function(_action: string, done: any)
				table.insert(asked, done)
			end,
			relayout = function()
				relayouts += 1
			end,
			serverNow = function()
				return 0
			end,
		}
		local panel = Codes.new(UiHarness.root(), ctx)
		local body = panel.frame:FindFirstChild("Body")
		local box = UiHarness.find(panel.frame, "CodeBox")
		local before = Widgets.contentHeight(body)
		expect(before).toBe(Codes.CONTENT_H)
		box.Text = "NOTACODE"
		UiHarness.fire(UiHarness.find(panel.frame, "RedeemButton"), "Activated")
		asked[1]({ ok = false, message = "That code doesn't exist" })
		expect(Widgets.contentHeight(body)).toBe(before + Codes.ERROR_SHIFT)
		expect(relayouts).toBe(1)
		UiHarness.fire(box, "Focused") -- clicking back in drops the line and the card shrinks back, once
		UiHarness.fire(box, "Focused")
		expect(Widgets.contentHeight(body)).toBe(before)
		expect(relayouts).toBe(2)
	end)
	it("leaves room above the code box so its outline isn't clipped at the top", function()
		local Codes = UiHarness.ui("Panels/Codes")
		local Layout = UiHarness.ui("Layout")
		local panel = build()
		local content = UiHarness.find(panel.frame, "Content")
		local ring = Layout.PANEL_CHROME.ring
		expect(content.Position.Y.Offset).toBe(-ring)
		expect(content:FindFirstChild("Ring").PaddingTop.Offset).toBe(ring)
		expect(UiHarness.find(panel.frame, "CodeBox").Position.Y.Offset).toBe(Codes.ROWS.input.y)
	end)
	it("errorText makes the server's reason a sentence, with a fallback", function()
		local Codes = UiHarness.ui("Panels/Codes")
		expect(Codes.errorText({ ok = false, message = "That code has expired" })).toBe("That code has expired.")
		expect(Codes.errorText({ ok = false })).toBe("That code doesn't work.")
	end)
end)
