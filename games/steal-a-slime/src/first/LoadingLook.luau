--!strict
-- The join loading screen's look (canvas GooLoading / GooLoadingSkip). It runs from ReplicatedFirst, before
-- ReplicatedStorage.Shared (GooPalette) and PlayerScripts (Widgets.Theme) arrive, so it keeps its own copy of the
-- Goo palette; tests/ui/LoadingLook.spec checks it still matches GooPalette.
return table.freeze({
	bg = Color3.fromRGB(12, 52, 54), -- GooPalette.Bg: the backdrop's top
	bgBottom = Color3.fromRGB(7, 36, 38), -- GooPalette.BgDeep: the backdrop's bottom
	ink = Color3.fromRGB(8, 38, 42), -- GooPalette.Ink: outlines, the bar's tube
	band = Color3.fromRGB(108, 242, 194), -- GooPalette.Mint: the goo, the title, the bar's fill
	bandHi = Color3.fromRGB(230, 255, 246), -- GooPalette.MintHi
	bandLo = Color3.fromRGB(47, 191, 146), -- GooPalette.MintLo
	text = Color3.fromRGB(241, 255, 249), -- GooPalette.Text
	muted = Color3.fromRGB(191, 235, 221), -- GooPalette.Muted
	glass = Color3.fromRGB(216, 255, 241), -- GooPalette.Glass: the Skip button's fill
	font = Enum.Font.FredokaOne, -- Theme.Font
	fontBody = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Bold), -- Theme.FontBody

	-- Text and controls, px, placed from the screen's centre.
	titleSize = 64,
	titleY = -60,
	titleStroke = 3,
	titleDrop = 6, -- the Ink shadow under the title
	labelSize = 20,
	statusY = 52,
	barSize = UDim2.fromOffset(420, 18),
	barY = 12,
	barRing = 0.65, -- transparency of the mint ring round the tube
	skipSize = UDim2.fromOffset(140, 52),
	skipY = 112,
	skipGlass = 0.88, -- transparency of the Skip button's glass
	stroke = 3, -- Ink outlines

	-- The goo across the top: a band, then drips (x across the screen, drop width and neck length as fractions of the
	-- goo's height). The goo is gooShare of the screen tall, but never reaches the title (LoadingScreen.gooHeight).
	gooShare = 0.24,
	gooBand = 0.24,
	gooGap = 16, -- px kept clear between the longest drip and the title
	drips = table.freeze({
		table.freeze({ x = 0.05, w = 0.077, len = 0.24 }),
		table.freeze({ x = 0.144, w = 0.052, len = 0.1 }),
		table.freeze({ x = 0.234, w = 0.094, len = 0.45 }),
		table.freeze({ x = 0.347, w = 0.06, len = 0.17 }),
		table.freeze({ x = 0.442, w = 0.043, len = 0.07 }),
		table.freeze({ x = 0.548, w = 0.086, len = 0.33 }),
		table.freeze({ x = 0.669, w = 0.052, len = 0.14 }),
		table.freeze({ x = 0.764, w = 0.1, len = 0.48 }),
		table.freeze({ x = 0.864, w = 0.06, len = 0.21 }),
		table.freeze({ x = 0.944, w = 0.043, len = 0.09 }),
	}),
	-- Faint goo bubbles low on the screen: x, y as fractions of the screen, size in px.
	bubbles = table.freeze({
		table.freeze({ 0.1, 0.83, 70 }),
		table.freeze({ 0.17, 0.91, 34 }),
		table.freeze({ 0.84, 0.88, 90 }),
		table.freeze({ 0.93, 0.75, 40 }),
		table.freeze({ 0.73, 0.94, 28 }),
	}),
	bubbleTransparency = 0.93,

	fade = 0.6, -- seconds
	displayOrder = 1000,
})
