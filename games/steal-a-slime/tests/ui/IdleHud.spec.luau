--!strict
-- v28 blocker (6b115fc frames): a large translucent dark rounded rectangle covered the screen with no
-- menu open, the MenuBackdrop left Visible after a card was hidden from outside. With no menu open
-- (idle HUD) no backdrop / card / nav highlight may show, at the five gate viewports.
local fs = require("@lune/fs")

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

local src = fs.readFile("src/ui/init.client.luau")
local function has(needle: string): boolean
	return string.find(src, needle, 1, true) ~= nil
end

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
	it("a card hidden from outside closes the menu (backdrop cannot outlive its card)", function()
		expect(MenuState.cardHidden("Shop", "Shop", false)).toBe(true)
		expect(MenuState.cardHidden("Shop", "Dex", false)).toBe(false)
		expect(MenuState.cardHidden("Shop", "Shop", true)).toBe(false)
		expect(MenuState.cardHidden(nil, "Shop", false)).toBe(false)
	end)
	it("init.client starts closed, drives the backdrop only from syncMenus and watches card Visible", function()
		expect(has('Name = "MenuBackdrop"')).toBe(true)
		expect(has("Visible = false,\n\tParent = gui,\n}) :: TextButton")).toBe(true)
		local _, sets = string.gsub(src, "backdrop%.Visible =", "")
		expect(sets).toBe(1)
		expect(has("backdrop.Visible = visibleKey ~= nil")).toBe(true)
		expect(has("\nsetOpen(nil)\n")).toBe(true)
		expect(has('entry.panel.frame:GetPropertyChangedSignal("Visible")')).toBe(true)
	end)
end)

describe("top-centre banners vs open menu", function()
	it("every banner shows only with no menu open", function()
		expect(MenuState.bannersVisible(nil)).toBe(true)
		for _, key in keys do
			expect(MenuState.bannersVisible(key)).toBe(false)
		end
	end)
	it("init.client feeds the open key to the HUD and Hud hides the whole banner stack on it", function()
		expect(has("hud.setMenuOpen(not MenuState.bannersVisible(visibleKey))")).toBe(true)
		local hudSrc = fs.readFile("src/ui/Hud.luau")
		expect(string.find(hudSrc, "banners.Visible = not menuOpen", 1, true) ~= nil).toBe(true)
	end)
end)
