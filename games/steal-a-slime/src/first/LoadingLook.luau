--!strict
-- The join loading screen's look. It runs from ReplicatedFirst, before PlayerScripts (and Widgets.Theme)
-- arrive, so it keeps its own copy of the Goo palette; tests/LoadingLook.spec checks it still matches.
return table.freeze({
	bg = Color3.fromRGB(12, 52, 54), -- Theme.Bg
	barBack = Color3.fromRGB(8, 38, 42), -- Theme.Ink: the sunken well under the bar and the skip button
	bar = Color3.fromRGB(108, 242, 194), -- Theme.Good
	text = Color3.fromRGB(241, 255, 249), -- Theme.Text
	muted = Color3.fromRGB(191, 235, 221), -- Theme.Muted
	font = Enum.Font.FredokaOne, -- Theme.Font
	titleSize = 54,
	labelSize = 20,
	barSize = UDim2.fromOffset(360, 14),
	fade = 0.6, -- seconds
	displayOrder = 1000,
})
