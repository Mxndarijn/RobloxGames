--!strict
-- FEATURES.Audio: the Sound card (Panels/Card.place) never sits under the nav grid, the tutorial / carry
-- cards, the HUD or the bottom (jump) inset, and shows all three rows with their text at the five gate
-- sizes (phone landscape switches to the one-row compact card). Pure Layout rects, no Instances.
local Card = require("../../src/ui/SoundCardLayout")
local Icons = require("../../src/ui/Icons")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local SLIDERS = {
	{ row = "music", text = "🎵 Music" },
	{ row = "sfx", text = "🔔 SFX" },
}

local function abs(box: Layout.Rect, body: Layout.Rect): Layout.Rect
	return Layout.rect(body.x + box.x, body.y + box.y, box.w, box.h)
end

local viewports = {}
for _, vp in LayoutAssert.GATE_VIEWPORTS do
	table.insert(viewports, vp)
end
for _, vp in LayoutAssert.LANDSCAPE_VIEWPORTS do
	if vp.h == 332 then
		table.insert(viewports, vp) -- under the Roblox top bar: may scroll, must still clear everything
	end
end

describe("Sound card layout", function()
	for _, vp in viewports do
		it(`{vp.name}: clear of nav, tutorial, carry, HUD and the bottom inset`, function()
			for _, collapsed in { true, false } do
				local screen = Layout.screen(vp.w, vp.h, { navCollapsed = collapsed })
				local card = Card.place(screen)
				local check = LayoutAssert.new(`[{vp.name} collapsed={collapsed}]`, screen)
				check.noOverlap("Sound card", card, "nav", screen.nav)
				for i, b in screen.navButtons do
					check.noOverlap("Sound card", card, `nav button {i}`, b)
				end
				check.noOverlap("Sound card", card, "tutorial", screen.tutorial)
				check.noOverlap("Sound card", card, "carry", screen.carry)
				check.noOverlap("Sound card", card, "slap", screen.slap)
				check.noOverlap("Sound card", card, "HUD", screen.hud.rect)
				check.inside("Sound card", card, "menu area", screen.panel)
				expect(check.report()).toBe("")
			end
		end)
		it(`{vp.name}: Mute, Music and SFX are fully visible and their text fits`, function()
			if vp.h == 332 then
				return
			end
			for _, collapsed in { true, false } do
				local screen = Layout.screen(vp.w, vp.h, { navCollapsed = collapsed })
				local card, compact = Card.place(screen)
				local body = Layout.panelBody(card)
				local rects, canvasH = Card.rowRects(body.w, compact)
				expect(canvasH <= body.h).toBe(true)
				local check = LayoutAssert.new(`[{vp.name} collapsed={collapsed}]`, screen)
				for name, box in rects do
					check.inside(`Sound {name}`, abs(box, body), "card body", body)
					check.touch(`Sound {name}`, box)
				end
				check.noOverlap("Sound mute", rects.mute, "music", rects.music)
				check.noOverlap("Sound music", rects.music, "sfx", rects.sfx)
				check.noOverlap("Sound mute", rects.mute, "sfx", rects.sfx)
				for _, muted in { true, false } do
					local text = if muted then `{Icons.SOUND_OFF} Muted` else `{Icons.SOUND_ON} Sound on`
					check.text({
						name = "Sound mute",
						text = text,
						size = 22,
						bold = true,
						w = rects.mute.w,
						h = rects.mute.h,
					})
				end
				for _, def in SLIDERS do
					local box = (rects :: any)[def.row]
					check.text({
						name = def.text,
						text = def.text,
						size = 18,
						bold = true,
						w = box.w * 0.7,
						h = Card.NAME_H,
					})
					check.text({
						name = "percent",
						text = "100%",
						size = 18,
						bold = true,
						w = box.w * 0.3,
						h = Card.NAME_H,
					})
				end
				expect(check.report()).toBe("")
			end
		end)
	end
	it("phone landscape uses the compact one-row card; other sizes keep the full card", function()
		local _, landscape = Card.place(Layout.screen(844, 390))
		expect(landscape).toBe(true)
		for _, vp in { LayoutAssert.GATE_VIEWPORTS[1], LayoutAssert.GATE_VIEWPORTS[3], LayoutAssert.GATE_VIEWPORTS[5] } do
			local screen = Layout.screen(vp.w, vp.h)
			local card, compact = Card.place(screen)
			expect(compact).toBe(false)
			expect(card.h).toBe(Layout.menuHeight("Sound"))
		end
	end)
end)
