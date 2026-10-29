--!strict
-- v28 blocker (6b115fc frames): a large translucent dark rounded rectangle covered the screen with no
-- menu open, the MenuBackdrop left Visible after a card was hidden from outside. With no menu open
-- (idle HUD) no backdrop / card / nav highlight may show, at the five gate viewports.
local LayoutAssert = require("./LayoutAssert")
local MenuState = require("../../src/ui/MenuState")
local Nav = require("../../src/ui/Nav")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local keys = {}
for _, entry in Nav.ENTRIES do
	table.insert(keys, entry.key)
end
table.insert(keys, "Guide")
table.insert(keys, "Welcome")

describe("idle HUD: no menu overlay", function()
	for _, entry in LayoutAssert.screens(LayoutAssert.GATE_VIEWPORTS) do
		it(`{entry.label}: backdrop, cards and nav highlights all hidden with no menu open`, function()
			local v = MenuState.view(nil, keys)
			expect(v.backdrop).toBe(false)
			for _, key in keys do
				expect(v.cards[key]).toBe(false)
				expect(v.nav[key]).toBe(false)
			end
			-- the backdrop would cover the window: that is exactly what must not show when idle
			expect(entry.screen.panel.w > 0 and entry.screen.panel.h > 0).toBe(true)
		end)
	end
	it("an open menu shows the backdrop and only its own card", function()
		for _, open in keys do
			local v = MenuState.view(open, keys)
			expect(v.backdrop).toBe(true)
			for _, key in keys do
				expect(v.cards[key]).toBe(key == open)
			end
		end
	end)
end)

describe("top-centre notices vs open overlays", function()
	it("every notice shows only with no menu open", function()
		expect(MenuState.noticesVisible(nil)).toBe(true)
		for _, key in keys do
			expect(MenuState.noticesVisible(key)).toBe(false)
		end
	end)
	it("the daily popup and the open bag panel hide them too", function()
		expect(MenuState.noticesVisible(nil, false, false)).toBe(true)
		expect(MenuState.noticesVisible(nil, true, false)).toBe(false)
		expect(MenuState.noticesVisible(nil, false, true)).toBe(false)
	end)
end)

describe("tutorial card vs open menu and daily popup", function()
	it("shows only with no menu and no daily popup open", function()
		expect(MenuState.tutorialShown(nil, false)).toBe(true)
		expect(MenuState.tutorialShown(nil, true)).toBe(false)
		for _, key in keys do
			expect(MenuState.tutorialShown(key, false)).toBe(false)
			expect(MenuState.tutorialShown(key, true)).toBe(false)
		end
	end)
	it("the welcome-back card (a menu key) already hides it", function()
		expect(MenuState.tutorialShown("Welcome", false)).toBe(false)
	end)
	it("the open bag panel hides it too", function()
		expect(MenuState.tutorialShown(nil, false, false)).toBe(true)
		expect(MenuState.tutorialShown(nil, false, true)).toBe(false)
		expect(MenuState.tutorialShown(nil, true, true)).toBe(false)
	end)
end)
