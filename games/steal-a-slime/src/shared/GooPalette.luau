--!strict
--[[
	GooPalette (pure)

	The Goo look's colours as { r, g, b } (0..255), the one place they are written. The HUD's Widgets.Theme,
	the server's world signs (PlotSigns, RitualView, PodiumRigs), the world props (visuals Props) and the
	client markers all read them from here. The loading screen runs before Shared replicates, so
	first/LoadingLook keeps a copy that tests/ui/LoadingLook.spec checks against this table.
]]

export type RGB = { number }

local function rgb(r: number, g: number, b: number): RGB
	return table.freeze({ r, g, b })
end

return table.freeze({
	Ink = rgb(8, 38, 42), -- every outline, dark text on bright jelly, sunken wells
	Bg = rgb(12, 52, 54), -- glass panel body
	BgDeep = rgb(7, 36, 38), -- the bottom of the loading screen's backdrop
	Row = rgb(28, 72, 73), -- rows and cards on the glass
	BgLight = rgb(40, 96, 96), -- highlighted rows
	Glass = rgb(216, 255, 241), -- a glass row on a card, drawn at GLASS_TRANSPARENCY
	Mint = rgb(108, 242, 194), -- bands, main actions, income, progress
	MintHi = rgb(230, 255, 246), -- the top of a mint jelly
	MintLo = rgb(47, 191, 146), -- the bottom of a mint jelly
	Text = rgb(241, 255, 249),
	Muted = rgb(191, 235, 221),
	MutedWell = rgb(166, 227, 210), -- text in wells and on empty signs
	Bad = rgb(238, 84, 118), -- danger pink
	Info = rgb(56, 120, 112),
	Warn = rgb(255, 190, 60),
	Gold = rgb(255, 210, 63),
	GoldHi = rgb(255, 244, 194), -- the top of a gold jelly
	GoldDeep = rgb(224, 168, 18), -- the coin's edge and ring, the bottom of a gold jelly
	Silver = rgb(206, 216, 232), -- second place on a leaderboard
	Bronze = rgb(232, 150, 92), -- third place on a leaderboard
	Wood = rgb(138, 90, 52), -- a plank under a goo band
	White = rgb(255, 255, 255),
	GLASS_TRANSPARENCY = 0.91,
})
