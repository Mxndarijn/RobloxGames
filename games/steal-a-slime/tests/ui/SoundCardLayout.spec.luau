--!strict
-- FEATURES.Audio: on phone landscape the full-height Sound card sat on the tutorial /
-- carry cards. Sound.place moves it to the top of the backdrop and, when the strip is
-- short, switches to the one-row layout. Pure Layout rects at the gate sizes (raw and
-- under the 58 px top bar) plus 844x332.
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
	for _, vp in LayoutAssert.LANDSCAPE_VIEWPORTS do
		if vp.h == 332 then
			table.insert(out, vp)
		end
	end
	return out
end

describe("Sound card placement", function()
	local Sound = UiHarness.ui("Panels/Sound")
	for _, vp in viewports() do
		it(`{vp.name}: the card clears nav, tutorial, carry and slap and stays in the panel`, function()
			do
				local screen = Layout.screen(vp.w, vp.h)
				local check = LayoutAssert.new(`[{vp.name}]`, screen)
				local card, compact = Sound.place(screen)
				check.inside("Sound card", card, "panel", screen.panel)
				if not screen.compact then -- phones hide the nav tiles while a menu is open
					check.noOverlap("Sound card", card, "nav", screen.nav)
					for i, b in screen.navButtons do
						check.noOverlap("Sound card", card, `navButtons[{i}]`, b)
					end
				end
				-- A phone-landscape strip can be shorter than the one-row card (compactCardH):
				-- then the card stays compact at the top of the panel and may touch the cards below.
				local cards = {
					tutorial = screen.tutorial,
					tutorialCarrying = screen.tutorialCarrying,
					carry = screen.carry,
					slap = screen.slap,
				}
				local strip = math.huge
				for _, name in { "tutorial", "tutorialCarrying", "carry" } do
					strip = math.min(strip, cards[name].y - Layout.GAP - screen.panel.y)
				end
				if strip >= Sound.compactCardH() or card.h >= Layout.cardHeight(Sound.CONTENT_H) then
					for name, rect in cards do
						check.noOverlap("Sound card", card, name, rect)
					end
				else
					expect(compact).toBe(true)
					expect(card.y).toBe(screen.panel.y)
					expect(card.h).toBe(Sound.compactCardH())
				end

				-- The rows fit the body, touch-sized and apart (the 332-tall card may be too short to show them).
				local body = Layout.panelBody(card)
				local rects = Sound.rowRects(body.w, compact)
				local list = { { "Mute", rects.mute }, { "Music", rects.music }, { "SFX", rects.sfx } }
				for i, a in list do
					check.touch(`Sound {a[1]}`, a[2])
					if vp.h ~= 332 then
						check.inside(
							`Sound {a[1]}`,
							Layout.rect(body.x + a[2].x, body.y + a[2].y, a[2].w, a[2].h),
							"body",
							body
						)
					end
					for j = i + 1, #list do
						check.noOverlap(`Sound {a[1]}`, a[2], `Sound {list[j][1]}`, list[j][2])
					end
				end
				expect(check.report()).toBe("")
			end
		end)
	end
	it("phone landscape uses the compact one-row card; desktop keeps the full card", function()
		local _, phone = Sound.place(Layout.screen(844, 390))
		local _, desktop = Sound.place(Layout.screen(1920, 1080))
		expect(phone).toBe(true)
		expect(desktop).toBe(false)
	end)
end)
