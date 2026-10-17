--!strict
--[[
	Sound card geometry (pure, no Instances): the body rows, and where the card
	sits on a Layout.Screen so it never lands under the tutorial or carry cards
	(Panels/Sound builds the Instances from these; tests/ui/SoundCardLayout.spec).
]]

local Layout = if script then require(script.Parent.Layout) else require("./Layout")

type Rect = Layout.Rect

local Card = {}

-- Body rows top to bottom (design px; the body is Layout.panelBody of the
-- Sound card). Slider row = name line + touch track.
Card.ROWS = table.freeze({
	mute = { y = 0, h = Layout.BUTTON },
	music = { y = 68, h = 60 },
	sfx = { y = 136, h = 60 },
})
Card.NAME_H = 24
Card.CONTENT_H = 196 -- sfx.y + sfx.h

-- Compact card (phone landscape, where the bottom cards leave a short strip
-- under the HUD): the three rows side by side, one row tall.
Card.COMPACT_H = 60
Card.COMPACT_MIN_W = 480

-- Row boxes inside the body (design px) and the canvas height they need.
function Card.rowRects(bodyW: number, compact: boolean): ({ mute: Rect, music: Rect, sfx: Rect }, number)
	local R = Card.ROWS
	if not compact then
		return {
			mute = Layout.rect(0, R.mute.y, bodyW, R.mute.h),
			music = Layout.rect(0, R.music.y, bodyW, R.music.h),
			sfx = Layout.rect(0, R.sfx.y, bodyW, R.sfx.h),
		},
			Card.CONTENT_H
	end
	local gap = Layout.GAP
	local w = math.floor((bodyW - gap * 2) / 3)
	return {
		mute = Layout.rect(0, 0, w, R.mute.h),
		music = Layout.rect(w + gap, 0, w, R.music.h),
		sfx = Layout.rect((w + gap) * 2, 0, bodyW - (w + gap) * 2, R.sfx.h),
	},
		Card.COMPACT_H
end

-- The card's box on `screen`: the usual centred card, unless it would sit under
-- the tutorial or carry cards as idle-placed (phone landscape; the lifted
-- carrying tutorial is hidden while a menu is open, MenuState.tutorialVisible): then at the top of the menu
-- area, compact (one row) and no lower than the cards, scrolling if still short.
function Card.place(screen: Layout.Screen): (Rect, boolean)
	local full = Layout.panelFor(screen, "Sound", Card.CONTENT_H)
	local ceiling = math.huge
	for _, other in { screen.tutorial, screen.carry } do
		if Layout.overlaps(full, other) then
			ceiling = math.min(ceiling, other.y - Layout.GAP)
		end
	end
	if ceiling == math.huge then
		return full, false
	end
	local compact = full.w >= Card.COMPACT_MIN_W
	local want = if compact then Layout.cardHeight(Card.COMPACT_H) else full.h
	local y = screen.panel.y
	return Layout.rect(full.x, y, full.w, math.max(math.min(want, ceiling - y), 0)), compact
end

return Card
