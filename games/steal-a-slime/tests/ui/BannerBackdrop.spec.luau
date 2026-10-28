--!strict
-- The menu backdrop is the whole window at the five gate sizes (under the top bar too), and the tutorial UI
-- steps aside for an open menu.
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local MenuState = require("../../src/ui/MenuState")
local TestRunner = require("../TestRunner")
local Tutorial = require("../../src/ui/Tutorial")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local TutorialCard = UiHarness.ui("TutorialCard")

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

-- The tutorial card (in the top banner stack) and its hint ring / bubble hide while any menu is open, so they never
-- cover a menu's inputs.
describe("tutorial UI never covers an open menu card", function()
	local GRAB = { tutorialStepId = "Grab" }
	local function newCard(): any
		return UiHarness.ui("TutorialCard").new(UiHarness.root(), {}, 2)
	end
	local function step(card: any): any
		return UiHarness.find(card.frame, "Step")
	end
	it("the tutorial shows only with no menu card and no bag panel open", function()
		expect(MenuState.tutorialVisible(nil, false)).toBe(true)
		expect(MenuState.tutorialVisible(nil)).toBe(true)
		expect(MenuState.tutorialVisible(nil, true)).toBe(false)
		expect(MenuState.tutorialVisible("Shop", false)).toBe(false)
		expect(MenuState.tutorialVisible("Shop", true)).toBe(false)
		expect(MenuState.tutorialShown(nil, true)).toBe(false) -- the daily popup
	end)
	it("the card hides with a menu open and returns on the same step", function()
		local card = newCard()
		card.update(GRAB)
		local title = UiHarness.find(step(card), "Title").Text
		expect(card.frame.Visible).toBe(true)
		card.setMenuOpen(true)
		expect(card.frame.Visible).toBe(false)
		card.update(GRAB) -- a State push while the menu is open must not re-show it
		expect(card.frame.Visible).toBe(false)
		expect(card.shown()).toBe(true)
		card.setMenuOpen(false)
		expect(card.frame.Visible).toBe(true)
		expect(UiHarness.find(step(card), "Title").Text).toBe(title)
	end)
	it("a step change while a menu is open shows the new step when it closes", function()
		UiHarness.virtualTime(true)
		local card = newCard()
		card.update(GRAB)
		card.setMenuOpen(true)
		card.update({ tutorialStepId = "Deposit" }) -- the server moved on under the menu
		expect(card.frame.Visible).toBe(false)
		card.setMenuOpen(false)
		expect(card.frame.Visible).toBe(true)
		expect(UiHarness.find(step(card), "Title").Text).toBe((Tutorial.find("Deposit") :: any).title)
		card.update({}) -- tutorial finished: the step card is gone, menu or not
		card.setMenuOpen(true)
		expect(card.frame.Visible).toBe(false)
		card.setMenuOpen(false)
		expect(step(card).Visible).toBe(false)
		UiHarness.advance(TutorialCard.FINISHED_SECONDS + 0.1)
		card.tick(0)
		expect(card.frame.Visible).toBe(false)
		UiHarness.virtualTime(false)
	end)
end)
