--!strict
-- v29 (PC watcher phone frames): the MenuBackdrop was a partial dark rounded rectangle (the card
-- column box, not the window). At the five gate sizes the open backdrop is exactly the viewport
-- (under the top bar too).
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local MenuState = require("../../src/ui/MenuState")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local EPS = 0.5
local TOP_BAR = 36 -- GuiService:GetGuiInset().Y with the Roblox top bar

describe("menu backdrop is the whole window", function()
	for _, entry in LayoutAssert.screens(LayoutAssert.GATE_VIEWPORTS) do
		for _, inset in { 0, TOP_BAR } do
			it(`{entry.label}: backdrop == viewport (top inset {inset})`, function()
				local s = entry.screen
				local r = Layout.backdrop(s, 0, inset)
				-- design px -> screen px
				local x, y, w, h = r.x * s.scale, r.y * s.scale, r.w * s.scale, r.h * s.scale
				expect(math.abs(x) < EPS).toBe(true)
				expect(math.abs(y + inset) < EPS).toBe(true)
				expect(math.abs(x + w - s.viewportW) < EPS).toBe(true)
				expect(math.abs(y + h - s.viewportH) < EPS).toBe(true)
			end)
		end
	end
end)

-- v29 (shot 98): the "Step 1 of 7 Grab a slime" card covered the Codes input and Redeem on phone
-- landscape; the tutorial card and its hint ring / bubble hide while any menu is open.
describe("tutorial UI never covers an open menu card", function()
	local GRAB = { tutorialStepId = "Grab" }
	it("the tutorial shows only with no menu card and no bag panel open", function()
		expect(MenuState.tutorialVisible(nil, false)).toBe(true)
		expect(MenuState.tutorialVisible(nil)).toBe(true)
		expect(MenuState.tutorialVisible(nil, true)).toBe(false)
		expect(MenuState.tutorialVisible("Shop", false)).toBe(false)
		expect(MenuState.tutorialVisible("Shop", true)).toBe(false)
	end)
	it("TutorialOverlay hides with a menu open and returns on the same step", function()
		local overlay = UiHarness.ui("Panels/TutorialOverlay").new(UiHarness.root(), {})
		overlay.update(GRAB)
		local title = UiHarness.find(overlay.frame, "Title").Text
		expect(overlay.frame.Visible).toBe(true)
		overlay.setMenuOpen(true)
		expect(overlay.frame.Visible).toBe(false)
		overlay.update(GRAB) -- a State push while the menu is open must not re-show it
		expect(overlay.frame.Visible).toBe(false)
		expect(overlay.shown()).toBe(true)
		overlay.setMenuOpen(false)
		expect(overlay.frame.Visible).toBe(true)
		expect(UiHarness.find(overlay.frame, "Title").Text).toBe(title)
	end)
	it("a step change while a menu is open shows the new step when it closes", function()
		local overlay = UiHarness.ui("Panels/TutorialOverlay").new(UiHarness.root(), {})
		overlay.update(GRAB)
		overlay.setMenuOpen(true)
		overlay.update({ tutorialStepId = "Deposit" }) -- the server moved on under the menu
		expect(overlay.frame.Visible).toBe(false)
		overlay.setMenuOpen(false)
		expect(overlay.frame.Visible).toBe(true)
		overlay.update({}) -- tutorial finished: stays hidden, menu or not
		overlay.setMenuOpen(true)
		overlay.setMenuOpen(false)
		expect(overlay.frame.Visible).toBe(false)
	end)
end)

describe("a hidden tutorial card can be shown again", function()
	local GRAB = { tutorialStepId = "Grab" }
	it("Hide keeps the step hidden until showAgain brings it back", function()
		local overlay = UiHarness.ui("Panels/TutorialOverlay").new(UiHarness.root(), {})
		overlay.update(GRAB)
		expect(overlay.hidden()).toBe(false)
		UiHarness.fire(UiHarness.find(overlay.frame, "Hide"), "Activated")
		expect(overlay.frame.Visible).toBe(false)
		expect(overlay.hidden()).toBe(true)
		overlay.update(GRAB) -- a State push on the same step keeps it hidden
		expect(overlay.frame.Visible).toBe(false)
		overlay.showAgain()
		expect(overlay.frame.Visible).toBe(true)
		expect(overlay.hidden()).toBe(false)
		overlay.update(GRAB) -- and it stays shown on the next push
		expect(overlay.frame.Visible).toBe(true)
	end)
	it("showAgain under an open menu shows the card once the menu closes", function()
		local overlay = UiHarness.ui("Panels/TutorialOverlay").new(UiHarness.root(), {})
		overlay.update(GRAB)
		UiHarness.fire(UiHarness.find(overlay.frame, "Hide"), "Activated")
		overlay.setMenuOpen(true)
		overlay.showAgain()
		expect(overlay.frame.Visible).toBe(false)
		overlay.setMenuOpen(false)
		expect(overlay.frame.Visible).toBe(true)
	end)
	it("nothing counts as hidden on a new step or once the tutorial is done", function()
		local overlay = UiHarness.ui("Panels/TutorialOverlay").new(UiHarness.root(), {})
		overlay.update(GRAB)
		UiHarness.fire(UiHarness.find(overlay.frame, "Hide"), "Activated")
		overlay.update({ tutorialStepId = "Deposit" })
		expect(overlay.hidden()).toBe(false)
		expect(overlay.frame.Visible).toBe(true)
		UiHarness.fire(UiHarness.find(overlay.frame, "Hide"), "Activated")
		overlay.update({})
		expect(overlay.hidden()).toBe(false)
	end)
end)
