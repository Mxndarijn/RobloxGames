--!strict
-- The join loading screen's look. It runs from ReplicatedFirst, before PlayerScripts (and Widgets.Theme)
-- arrive, so it keeps its own copy of the HUD palette; tests/LoadingLook.spec checks it still matches.
return table.freeze({
	bg = Color3.fromRGB(43, 27, 77), -- Theme.Bg
	barBack = Color3.fromRGB(30, 18, 51), -- Theme.Ink: the sunken well under the bar and the skip button
	bar = Color3.fromRGB(126, 217, 87), -- Theme.Good
	text = Color3.fromRGB(246, 241, 255), -- Theme.Text
	muted = Color3.fromRGB(184, 166, 227), -- Theme.Muted
	font = Enum.Font.FredokaOne, -- Theme.Font
	titleSize = 54,
	labelSize = 20,
	barSize = UDim2.fromOffset(360, 14),
	fade = 0.6, -- seconds
	displayOrder = 1000,
})
