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
	slime = Color3.fromRGB(255, 210, 63), -- GooPalette.Gold: the slime riding the bar
	slimeHi = Color3.fromRGB(255, 244, 194), -- GooPalette.GoldHi: the top of the slime's jelly
	slimeLo = Color3.fromRGB(224, 168, 18), -- GooPalette.GoldDeep: the bottom of the slime's jelly
	white = Color3.fromRGB(255, 255, 255), -- GooPalette.White: the bar's shine, the slime's highlight
	font = Enum.Font.FredokaOne, -- Theme.Font
	fontBody = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Bold), -- Theme.FontBody

	-- Text and controls, px, placed from the screen's centre.
	titleSize = 64,
	titleY = -70,
	titleStroke = 3,
	titleDrop = 6, -- the Ink shadow under the title
	labelSize = 20,
	statusY = 76,
	barSize = UDim2.fromOffset(420, 18),
	barY = 36,
	barRing = 0.65, -- transparency of the mint ring round the tube
	skipSize = UDim2.fromOffset(140, 52),
	skipY = 136,
	skipGlass = 0.88, -- transparency of the Skip button's glass
	stroke = 3, -- Ink outlines

	-- The goo across the top: a band, then drips (x across the screen, width and how far it hangs under the band as
	-- fractions of the goo's height). Each drip is one finger of goo with a round end. The goo is gooShare of the
	-- screen tall, but never reaches the title (LoadingScreen.gooHeight).
	gooShare = 0.24,
	gooBand = 0.24,
	gooGap = 16, -- px kept clear between the longest drip and the title
	drips = table.freeze({
		table.freeze({ x = 0.08, w = 0.11, hang = 0.28 }),
		table.freeze({ x = 0.24, w = 0.13, hang = 0.48 }),
		table.freeze({ x = 0.41, w = 0.09, hang = 0.16 }),
		table.freeze({ x = 0.57, w = 0.12, hang = 0.36 }),
		table.freeze({ x = 0.75, w = 0.14, hang = 0.52 }),
		table.freeze({ x = 0.91, w = 0.09, hang = 0.2 }),
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

	-- Motion, all of it off under Roblox's Reduced Motion. Periods in seconds.
	sway = 0.12, -- each drip grows and shrinks by this share of its hang
	swayPeriods = table.freeze({ 3.2, 2.6, 3.8, 3.0, 2.9, 3.4 }), -- one per drip
	drops = table.freeze({ -- a drop that forms at a drip's end and falls off the screen, behind the text
		table.freeze({ drip = 1, every = 4.5, delay = 0 }),
		table.freeze({ drip = 6, every = 5.2, delay = 2.3 }),
	}),
	dropSize = 16, -- px
	dropFall = 0.4, -- share of each cycle the drop spends falling (the rest it is still forming, unseen)
	bubbleRise = 0.2, -- share of the screen height a bubble rises before it fades and starts again
	bubblePeriod = 9, -- seconds for the first bubble's rise; each next one takes 1.3 s longer
	shinePeriod = 1.6, -- seconds for the shine to cross the bar's fill
	shineTransparency = 0.5, -- at the shine's brightest

	-- The slime hopping along the tip of the bar (px). It stays clear of the title (LoadingScreen.riderTop).
	riderSize = Vector2.new(48, 34),
	riderHop = 12, -- px it leaps
	riderPeriod = 0.55, -- seconds per hop
	riderSquash = 0.12, -- wider and flatter by this share when it lands
	riderLift = 2, -- px it sits above the bar

	fade = 0.6, -- seconds
	displayOrder = 1000,
})
