--!strict
-- v29 (PC watcher phone frames): the MenuBackdrop was a partial dark rounded rectangle (the card
-- column box, not the window) and top-centre banners drew over card titles / X buttons. At the five
-- gate sizes: the open backdrop is exactly the viewport (under the top bar too), and no banner rect
-- exists while a menu is open, so none can touch a card's title bar or close X.
local fs = require("@lune/fs")

local Hint = require("../../src/ui/Hint")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local MenuState = require("../../src/ui/MenuState")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local EPS = 0.5
local TOP_BAR = 36 -- GuiService:GetGuiInset().Y with the Roblox top bar

local function intersects(a: Layout.Rect, b: Layout.Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

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
	it("init.client sizes it from Layout.backdrop, square, and nothing writes its Visible but syncMenus", function()
		local src = fs.readFile("src/ui/init.client.luau")
		expect(string.find(src, "Layout.backdrop(s, guiInset.X, guiInset.Y)", 1, true) ~= nil).toBe(true)
		local made = string.match(src, 'Name = "MenuBackdrop".-Parent = gui[^\n]*\n[^\n]*') or ""
		expect(string.find(made, "corner", 1, true)).toBeNil()
		expect(string.find(src, "s.panel.x", 1, true)).toBeNil()
	end)
end)

describe("banners never cover an open menu card's title or X", function()
	for _, entry in LayoutAssert.screens(LayoutAssert.GATE_VIEWPORTS) do
		it(`{entry.label}: no banner rect while any menu is open`, function()
			local s = entry.screen
			local b = s.banners
			local column = Layout.rect(b.x, b.y, b.w, s.height - b.y)
			for _, key in LayoutAssert.menuKeys() do
				local card = Layout.panelFor(s, key)
				local rect = MenuState.bannerRect(key, column)
				if rect then
					expect(intersects(rect, Layout.panelTitle(card))).toBe(false)
					expect(intersects(rect, Layout.panelClose(card))).toBe(false)
				end
				expect(rect).toBeNil()
			end
			expect(MenuState.bannerRect(nil, column)).toBe(column)
		end)
	end
	it("Hud hides the whole Banners frame (every banner is a child of it) with a menu open", function()
		local hud = fs.readFile("src/ui/Hud.luau")
		expect(string.find(hud, "banners.Visible = not menuOpen", 1, true) ~= nil).toBe(true)
		for _, name in
			{
				"StealAlert",
				"RareBanner",
				"RainBanner",
				"ModifierBadge",
				"FriendBadge",
				"WeekendChip",
				"EventsBoard",
				"EggReveal",
				"PadHint",
			}
		do
			expect(string.find(hud, `banner(banners, "{name}"`, 1, true) ~= nil).toBe(true)
		end
	end)
end)

-- v29 (shot 98): the "Step 1 of 7 Grab a slime" card covered the Codes input and Redeem on phone
-- landscape; the tutorial card and its hint ring / bubble hide while any menu is open.
describe("tutorial UI never covers an open menu card", function()
	local GRAB = { tutorialStepId = "Grab" }
	for _, entry in LayoutAssert.screens(LayoutAssert.GATE_VIEWPORTS) do
		it(`{entry.label}: no tutorial card / hint rect while any menu is open`, function()
			local s = entry.screen
			for _, key in LayoutAssert.menuKeys() do
				for _, idle in { s.tutorial, s.tutorialCarrying } do
					expect(MenuState.tutorialRect(key, idle)).toBeNil()
				end
				for _, step in { "Lock", "BuyPad", "Merge", "Rebirth" } do
					local view = Hint.fromState({ tutorialStepId = step }, nil)
					local p = if view then Hint.place(s, s.hud, view) else nil
					if p then
						expect(MenuState.tutorialRect(key, p.ring)).toBeNil()
						expect(MenuState.tutorialRect(key, p.bubble)).toBeNil()
					end
				end
			end
			expect(MenuState.tutorialRect(nil, s.tutorial)).toBe(s.tutorial)
		end)
	end
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
	it("init.client gates the card and the hint on the menu", function()
		local src = fs.readFile("src/ui/init.client.luau")
		expect(string.find(src, "tutorial.setMenuOpen(not MenuState.tutorialVisible(visibleKey))", 1, true) ~= nil).toBe(
			true
		)
		expect(string.find(src, "MenuState.tutorialVisible(openKey))", 1, true) ~= nil).toBe(true)
	end)
end)
