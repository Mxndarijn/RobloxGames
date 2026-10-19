--!strict
--[[
	Rebirth panel: only the NEXT rebirth, its number in the title. Two
	requirement cards side by side: the cash (cost, a progress bar, what you
	have) and, when the rebirth asks for one, the slime (its picture, name and
	Missing / done mark). Then what it gives (income multiplier, lock time),
	the keeper and either a status line saying what is missing or the Rebirth
	button (state.canRebirth, hold to confirm). Progress.nextRebirth has the
	numbers.
]]

local UI = script.Parent.Parent
local Format = require(UI.Format)
local Layout = require(UI.Layout)
local Progress = require(UI.Progress)
local Selection = require(UI.Selection)
local SlimePreview = require(UI.SlimePreview)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Rebirth = {}

-- Body rows top to bottom (design px; the body is Layout.panelBody of the
-- Rebirth card, MENU_HEIGHTS.Rebirth tall).
Rebirth.ROWS = table.freeze({
	sub = { y = 0, h = 18 }, -- "To rebirth you need both:"
	need = { y = 24, h = 128 }, -- the two requirement cards
	gets = { y = 158, h = 18 }, -- "You get:"
	gives = { y = 180, h = 50 }, -- reward tiles
	keeper = { y = 240, h = 26 },
	button = { y = 276, h = Layout.BUTTON },
	note = { y = 338, h = 18 },
})
Rebirth.CONTENT_H = 356 -- note.y + note.h
Rebirth.SLIME_IMAGE = 52

-- Inside a requirement card (design px).
Rebirth.CARD = table.freeze({
	gap = 8, -- between the two cards
	pad = 12,
	labelY = 10,
	labelH = 18,
	labelSize = 14,
	markInset = 9, -- tick / stamp from the card's top-right corner
	tick = 24,
	stampH = 22,
	stampSize = 13,
	amountY = 32,
	amountH = 34,
	amountSize = 28,
	barY = 72,
	barH = 12,
	imageY = 32,
	nameSize = 19,
	nameH = 24,
	descY = 98,
	descH = 18,
	descSize = 13,
})

-- Reward tiles, keeper chip, status, footer (design px).
Rebirth.TEXT = table.freeze({
	subSize = 14,
	gainSize = 22,
	gainY = 4,
	gainH = 26,
	gainLabelSize = 12,
	gainLabelY = 30,
	gainLabelH = 16,
	keeperSize = 13,
	keeperMaxW = 430, -- under the narrowest gate body (390x844: 439)
	statusSize = 18,
	buttonSize = 22,
	noteSize = 12,
})

-- A green tick in a circle (a drawn check mark, no glyph).
local function tickBadge(name: string, parent: Instance): Frame
	local c = Rebirth.CARD
	local badge = create("Frame", {
		Name = name,
		Visible = false,
		BackgroundColor3 = Theme.Good,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -c.markInset, 0, c.markInset - 2),
		Size = UDim2.fromOffset(c.tick, c.tick),
		Parent = parent,
	}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }), Widgets.stroke(Theme.Ink, Widgets.KIT.rowStroke) })
	-- Short leg (6,12)-(10,16) and long leg (10,16)-(18,8) of a 24 px box, 3 px thick.
	for _, leg in { { 8, 14, 7, 45 }, { 14, 12, 13, -45 } } do
		create("Frame", {
			Name = "Leg",
			BackgroundColor3 = Theme.Ink,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(leg[1] / 24, leg[2] / 24),
			Size = UDim2.fromOffset(leg[3], 3),
			Rotation = leg[4],
			Parent = badge,
		}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	end
	return badge
end

function Rebirth.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "RebirthPanel", "Rebirth", "♻️")
	local rows = Rebirth.ROWS
	local C = Rebirth.CARD
	local T = Rebirth.TEXT
	-- Scrolls only when the card is shorter than the content (landscape
	-- phones); a fixed canvas, nothing in it moves.
	local content = Widgets.scroll({
		Name = "Content",
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		CanvasSize = UDim2.fromOffset(0, Rebirth.CONTENT_H),
		Parent = panel.body,
	})

	local sub = Widgets.label({
		Name = "Sub",
		TextSize = T.subSize,
		TextColor3 = Theme.Muted,
		Position = UDim2.fromOffset(0, rows.sub.y),
		Size = UDim2.new(1, 0, 0, rows.sub.h),
		Parent = content,
	})

	local function cardLabel(text: string, card: Frame)
		Widgets.label({
			Name = "Label",
			Text = text,
			TextSize = C.labelSize,
			TextColor3 = Theme.Muted,
			Position = UDim2.fromOffset(C.pad, C.labelY),
			Size = UDim2.new(1, -(C.pad * 2 + C.tick), 0, C.labelH),
			Parent = card,
		})
	end
	local function cardDesc(name: string, card: Frame): TextLabel
		return Widgets.label({
			Name = name,
			TextSize = C.descSize,
			TextColor3 = Theme.Muted,
			Position = UDim2.fromOffset(C.pad, C.descY),
			Size = UDim2.new(1, -C.pad * 2, 0, C.descH),
			Parent = card,
		})
	end

	-- Cash card: the cost in gold, a bar and what you have.
	local need = Widgets.rowFrame({
		Name = "Need",
		Position = UDim2.fromOffset(0, rows.need.y),
		Size = UDim2.new(0.5, -C.gap / 2, 0, rows.need.h),
		Parent = content,
	})
	cardLabel("Cash", need)
	local cashTick = tickBadge("CashTick", need)
	local cost = Widgets.label({
		Name = "Cost",
		Font = Theme.Font,
		TextSize = C.amountSize,
		TextColor3 = Theme.Gold,
		TextStrokeColor3 = Theme.Ink,
		TextStrokeTransparency = 0,
		Position = UDim2.fromOffset(C.pad, C.amountY),
		Size = UDim2.new(1, -C.pad * 2, 0, C.amountH),
		Parent = need,
	})
	local _, setBar =
		Widgets.bar(need, Theme.Gold, UDim2.new(1, -C.pad * 2, 0, C.barH), UDim2.fromOffset(C.pad, C.barY))
	local have = cardDesc("Have", need)

	-- Slime card: the slime this rebirth also needs. Its picture (the real
	-- slime in a viewport, a dark silhouette while missing), its name, then a
	-- Missing stamp or a tick.
	local slimeCard = Widgets.rowFrame({
		Name = "SlimeNeed",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, rows.need.y),
		Size = UDim2.new(0.5, -C.gap / 2, 0, rows.need.h),
		Parent = content,
	})
	cardLabel("This slime", slimeCard)
	local slimeTick = tickBadge("SlimeTick", slimeCard)
	local slimeState = Widgets.label({
		Name = "SlimeState",
		Text = "Missing",
		Font = Theme.Font,
		TextSize = C.stampSize,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Bad,
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -C.markInset, 0, C.markInset - 2),
		Size = UDim2.fromOffset(0, C.stampH),
		Parent = slimeCard,
	})
	Widgets.inkOn(slimeState, Theme.Bad)
	Widgets.corner(8).Parent = slimeState
	Widgets.stroke(Theme.Ink, Widgets.KIT.rowStroke).Parent = slimeState
	create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = slimeState })
	local imageSize = Rebirth.SLIME_IMAGE
	local slimeImage = create("Frame", {
		Name = "Image",
		Position = UDim2.fromOffset(C.pad, C.imageY),
		Size = UDim2.fromOffset(imageSize, imageSize),
		BackgroundTransparency = 0.55,
		Parent = slimeCard,
	}, { Widgets.corner(Widgets.KIT.radius), Widgets.stroke(Theme.Ink, Widgets.KIT.rowStroke) })
	local slimeView = create("ViewportFrame", {
		Name = "Preview",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = slimeImage,
	})
	local slimeGlyph = Widgets.label({
		Name = "Glyph",
		Text = "?",
		Font = Theme.Font,
		TextSize = C.amountSize,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = Layout.ZINDEX.Menu, -- over the viewport, its sibling
		Size = UDim2.fromScale(1, 1),
		Parent = slimeImage,
	})
	local nameX = C.pad + imageSize + 10
	local slimeName = Widgets.label({
		Name = "SlimeName",
		Font = Theme.Font,
		TextSize = C.nameSize,
		Position = UDim2.fromOffset(nameX, C.imageY + (imageSize - C.nameH) // 2),
		Size = UDim2.new(1, -(nameX + C.pad), 0, C.nameH),
		Parent = slimeCard,
	})
	local slimeDesc = cardDesc("SlimeDesc", slimeCard)

	-- What the next rebirth gives: two Ink tiles, a green number over a muted word.
	local gets = Widgets.label({
		Name = "Gets",
		Text = "You get:",
		TextSize = T.subSize,
		TextColor3 = Theme.Muted,
		Position = UDim2.fromOffset(0, rows.gets.y),
		Size = UDim2.new(1, 0, 0, rows.gets.h),
		Parent = content,
	})
	local function gainTile(name: string, word: string, x: UDim): (Frame, TextLabel)
		local tile = create("Frame", {
			Name = name,
			BackgroundColor3 = Theme.Ink,
			Position = UDim2.new(x, UDim.new(0, rows.gives.y)),
			Size = UDim2.new(0.5, -C.gap / 2, 0, rows.gives.h),
			Parent = content,
		}, { Widgets.corner(Widgets.KIT.radius) })
		local value = Widgets.label({
			Name = "Value",
			Font = Theme.Font,
			TextSize = T.gainSize,
			TextColor3 = Theme.Good,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, T.gainY),
			Size = UDim2.new(1, 0, 0, T.gainH),
			Parent = tile,
		})
		Widgets.label({
			Name = "Word",
			Text = word,
			TextSize = T.gainLabelSize,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, T.gainLabelY),
			Size = UDim2.new(1, 0, 0, T.gainLabelH),
			Parent = tile,
		})
		return tile, value
	end
	local incomeTile, incomeValue = gainTile("Income", "income", UDim.new(0, 0))
	local lockTile, lockValue = gainTile("LockTime", "lock time", UDim.new(0.5, C.gap / 2))

	local keepLine = Widgets.chip({
		Name = "Keeper",
		Font = Theme.FontBody,
		TextSize = T.keeperSize,
		TextColor3 = Theme.Muted,
		BackgroundColor3 = Theme.Row,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(0, rows.keeper.y),
		Size = UDim2.fromOffset(0, rows.keeper.h),
		Parent = content,
	})
	create("UISizeConstraint", { MaxSize = Vector2.new(T.keeperMaxW, math.huge), Parent = keepLine })

	-- Until both requirements are met: a sunken status line saying what is missing, no button.
	local reasonLine = Widgets.status({
		Name = "Reason",
		TextSize = T.statusSize,
		Position = UDim2.fromOffset(0, rows.button.y),
		Size = UDim2.new(1, 0, 0, rows.button.h),
		Parent = content,
	})
	local btn = Widgets.holdButton(
		{
			Name = "RebirthButton",
			Text = "♻️ Rebirth!",
			Visible = false,
			Position = UDim2.fromOffset(0, rows.button.y),
			Size = UDim2.new(1, 0, 0, rows.button.h),
			TextSize = T.buttonSize,
		},
		Theme.Gold,
		function()
			ctx.send("Rebirth")
		end,
		ctx.Config.HOLD_CONFIRM_SECONDS
	)
	btn.instance.Parent = content

	Widgets.label({
		Name = "Note",
		Text = "Resets cash and slimes. Keeps ★ slimes, pads and upgrades.",
		TextSize = T.noteSize,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, rows.note.y),
		Size = UDim2.new(1, 0, 0, rows.note.h),
		Parent = content,
	})

	local self = { frame = panel.frame, close = panel.close }

	function self.update(state: any)
		local nextUp = Progress.nextRebirth(state, ctx.Config)
		local slimeNeed = nextUp.slime
		local cashMet = nextUp.maxed or nextUp.have >= nextUp.cost
		panel.title.Text = if nextUp.maxed then "Rebirth" else `Rebirth {nextUp.rebirth}`
		sub.Text = if nextUp.maxed
			then "All rebirths done!"
			elseif slimeNeed then "To rebirth you need both:"
			else "To rebirth you need:"

		need.Visible = not nextUp.maxed
		need.Size = UDim2.new(if slimeNeed then 0.5 else 1, if slimeNeed then -C.gap / 2 else 0, 0, rows.need.h)
		cashTick.Visible = cashMet
		cost.Text = Format.formatCash(nextUp.cost)
		setBar(nextUp.fraction)
		have.Text = `You have {Format.formatCash(nextUp.have)}`

		gets.Visible = not nextUp.maxed
		incomeTile.Visible = not nextUp.maxed
		lockTile.Visible = not nextUp.maxed
		incomeValue.Text = Format.formatMultiplier(nextUp.multiplier)
		lockValue.Text = `+{nextUp.lockGain}s`

		local fav = Selection.findSlime(state.slimes, state.favoriteId)
		keepLine.Text = `★ Keeps {if fav then ctx.Genome.displayName(fav.slime) else "your best slime"}`

		slimeCard.Visible = slimeNeed ~= nil
		if slimeNeed then
			slimeName.Text = slimeNeed.name
			slimeName.TextColor3 = if slimeNeed.owned then Theme.Text else Theme.Muted
			slimeState.Visible = not slimeNeed.owned
			slimeTick.Visible = slimeNeed.owned
			slimeDesc.Text = if slimeNeed.owned then "You have one" else "Catch or merge one first"
			slimeImage.BackgroundColor3 = Widgets.color3(slimeNeed.color)
			local look = `{slimeNeed.id}:{slimeNeed.owned}`
			if slimeView:GetAttribute("Look") ~= look then
				local opts = { locked = not slimeNeed.owned }
				local ok = false
				if ctx.buildSlime then
					local genome = {
						id = `Rebirth_{slimeNeed.id}`,
						name = slimeNeed.name,
						tier = slimeNeed.tier,
						color = slimeNeed.color,
						size = 1,
						pattern = "Plain",
						eyes = "Round",
						mouth = "Smile",
						species = slimeNeed.id,
					}
					local built, model = pcall(ctx.buildSlime, genome)
					ok = built and model ~= nil and SlimePreview.mountModel(slimeView, model, opts)
				end
				if not ok then
					ok = SlimePreview.mount(slimeView, slimeNeed.color, opts)
				end
				slimeView:SetAttribute("Look", look)
				slimeView.Visible = ok
			end
			slimeGlyph.Visible = not slimeNeed.owned and not slimeView.Visible
		end

		reasonLine.Text = if nextUp.maxed
			then "🏆 All rebirths done"
			elseif
				nextUp.slimeMissing and cashMet
			then `🔒 Get {slimeNeed and slimeNeed.name or "a slime"} to rebirth`
			else `🔒 Need {nextUp.need}`
		reasonLine.Visible = not nextUp.ready
		btn.instance.Visible = nextUp.ready
		btn.setEnabled(nextUp.ready)
	end

	return self
end

return Rebirth
