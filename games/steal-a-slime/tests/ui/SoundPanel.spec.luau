--!strict
-- FEATURES.Audio: the Sound card is a normal menu opened from a speaker icon
-- in the top-right slot (Layout.screen .sound). Every layout rule must stay
-- green at the five gate sizes (raw and under the 58 px top bar), and the
-- card must hold its rows.
local Icons = require("../../src/ui/Icons")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local TOPBAR = 58

local function viewports(): { { name: string, w: number, h: number } }
	local out = {}
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		table.insert(out, vp)
		table.insert(out, { name = `{vp.w}x{vp.h - TOPBAR}`, w = vp.w, h = vp.h - TOPBAR })
	end
	return out
end

-- Only the Sound lines of the full rule set: LayoutGate already holds the rest (and its known findings).
local function gate(label: string, screen: Layout.Screen): string
	local out = {}
	for _, line in string.split(LayoutAssert.standard(label, screen).report(), "\n") do
		if string.find(line, "Sound", 1, true) then
			table.insert(out, line)
		end
	end
	return table.concat(out, "\n")
end

describe("Sound button and card", function()
	for _, vp in viewports() do
		it(`{vp.name}: the button and card clear nav, HUD, cards and toasts; text fits`, function()
			for _, collapsed in { true, false } do
				local screen = Layout.screen(vp.w, vp.h, { navCollapsed = collapsed })
				expect(gate(`[{vp.name} collapsed={collapsed}]`, screen)).toBe("")
			end
		end)
	end
	it("the Sound button is the slot a menu's X would use", function()
		local screen = Layout.screen(1920, 1080)
		expect(screen.sound.w).toBe(Layout.PANEL_CHROME.close)
		expect(screen.sound.h).toBe(Layout.PANEL_CHROME.close)
	end)
	it("the card is content-sized and fits every gate size", function()
		expect(Layout.cardHeight(196)).toBe(Layout.MENU_HEIGHTS.Sound)
		for _, vp in viewports() do
			local screen = Layout.screen(vp.w, vp.h)
			local r = Layout.panelFor(screen, "Sound", 196)
			expect(Layout.fitsInViewport(r, screen.width, screen.height)).toBe(true)
			expect(Layout.overlaps(r, screen.nav)).toBe(false)
			expect(Layout.panelBody(r).w >= 240).toBe(true)
		end
	end)
	it("the icons are the proven emoji", function()
		expect(Icons.SOUND_ON).toBe("🔊")
		expect(Icons.SOUND_OFF).toBe("🔇")
	end)
end)

local function find(root: any, name: string): any
	for _, child in root:GetDescendants() do
		if child.Name == name then
			return child
		end
	end
	return nil
end

describe("Sound panel", function()
	local state = { muted = false, sfx = 0.5, music = 0.25 }
	local controller = {
		settings = function()
			return state
		end,
		setMuted = function() end,
		setVolume = function() end,
		play = function() end,
	}
	it("shows the mute toggle and both sliders with their percent", function()
		local Sound = UiHarness.ui("Panels/Sound")
		local panel = Sound.new(UiHarness.root(), controller)
		expect(panel.frame.Visible).toBe(false)
		expect(find(panel.frame, "Mute").Text).toBe(Sound.muteText(false))
		expect(find(find(panel.frame, "music"), "Percent").Text).toBe("25%")
		expect(find(find(panel.frame, "sfx"), "Percent").Text).toBe("50%")
		expect(find(panel.frame, "Title").Text).toBe(Sound.TITLE)
	end)
	it("refresh follows a muted setting", function()
		local Sound = UiHarness.ui("Panels/Sound")
		local panel = Sound.new(UiHarness.root(), controller)
		state = { muted = true, sfx = 1, music = 0 }
		panel.refresh()
		expect(find(panel.frame, "Mute").Text).toBe(Sound.muteText(true))
		expect(find(find(panel.frame, "sfx"), "Percent").Text).toBe("100%")
		expect(find(find(panel.frame, "music"), "Percent").Text).toBe("0%")
	end)
end)
