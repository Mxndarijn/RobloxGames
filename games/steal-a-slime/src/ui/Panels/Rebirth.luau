--!strict
--[[
	Rebirth panel: only the NEXT rebirth, its number in the title. Two
	requirement cards side by side: the cash (cost, a progress bar, what you
	have) and the slimes the rebirth uses up: one slime gets its picture, name
	and Missing / done mark, two or three get one small row each (picture,
	name, a tick once owned). Then what it gives (income multiplier, lock time),
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
	-- Two or three slimes: one row each under the label.
	listY = 32,
	listRowH = 30,
	listImage = 26,
	listNameSize = 15,
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

-- "Zap", "Zap and Imp", "Zap, Imp and Octo".
local function missingNames(list: { Progress.SlimeNeed }): string
	local names = {}
	for _, need in list do
		table.insert(names, need.name)
	end
	if #names <= 1 then
		return names[1] or "a slime"
	end
	return `{table.concat(names, ", ", 1, #names - 1)} and {names[#names]}`
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

	local function cardLabel(text: string, card: Frame): TextLabel
		return Widgets.label({
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
	local slimeLabel = cardLabel("This slime", slimeCard)
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
	local single: { GuiObject } = { slimeImage, slimeName, slimeDesc }

	-- Two or three slimes: a row each (small picture, name, a tick once owned), made the first time one is shown.
	type ListRow = {
		frame: Frame,
		image: Frame,
		view: ViewportFrame,
		glyph: TextLabel,
		name: TextLabel,
		tick: Frame,
	}
	local listRows: { ListRow } = {}
	local function listRow(i: number): ListRow
		if listRows[i] then
			return listRows[i]
		end
		local row = create("Frame", {
			Name = `Need{i}`,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(C.pad, C.listY + (i - 1) * C.listRowH),
			Size = UDim2.new(1, -C.pad * 2, 0, C.listRowH),
			Parent = slimeCard,
		})
		local image = create("Frame", {
			Name = "Image",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(C.listImage, C.listImage),
			BackgroundTransparency = 0.55,
			Parent = row,
		}, { Widgets.corner(Widgets.KIT.radius), Widgets.stroke(Theme.Ink, Widgets.KIT.rowStroke) })
		local view = create("ViewportFrame", {
			Name = "Preview",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			Parent = image,
		})
		local glyph = Widgets.label({
			Name = "Glyph",
			Text = "?",
			Font = Theme.Font,
			TextSize = C.listNameSize,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = Layout.ZINDEX.Menu, -- over the viewport, its sibling
			Size = UDim2.fromScale(1, 1),
			Parent = image,
		})
		local rowNameX = C.listImage + 8
		local name = Widgets.label({
			Name = "SlimeName",
			Font = Theme.Font,
			TextSize = C.listNameSize,
			Position = UDim2.fromOffset(rowNameX, 0),
			Size = UDim2.new(1, -(rowNameX + C.tick + 4), 1, 0),
			Parent = row,
		})
		local tick = tickBadge("Tick", row)
		tick.AnchorPoint = Vector2.new(1, 0.5)
		tick.Position = UDim2.fromScale(1, 0.5)
		listRows[i] = { frame = row, image = image, view = view, glyph = glyph, name = name, tick = tick }
		return listRows[i]
	end

	-- Puts `need`'s slime into `view` (the real model, else a coloured blob; dark while missing).
	local function showSlime(view: ViewportFrame, glyph: TextLabel, slime: Progress.SlimeNeed)
		local look = `{slime.id}:{slime.owned}`
		if view:GetAttribute("Look") ~= look then
			local opts = { locked = not slime.owned }
			local ok = false
			if ctx.buildSlime then
				local genome = {
					id = `Rebirth_{slime.id}`,
					name = slime.name,
					tier = slime.tier,
					color = slime.color,
					size = 1,
					pattern = "Plain",
					eyes = "Round",
					mouth = "Smile",
					species = slime.id,
				}
				local built, model = pcall(ctx.buildSlime, genome)
				ok = built and model ~= nil and SlimePreview.mountModel(view, model, opts)
			end
			if not ok then
				ok = SlimePreview.mount(view, slime.color, opts)
			end
			view:SetAttribute("Look", look)
			view.Visible = ok
		end
		glyph.Visible = not slime.owned and not view.Visible
	end

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
		Text = "Uses up the slimes above. Keeps ★ slimes, pads and upgrades.",
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
		local needs = nextUp.slimes
		local hasSlimes = #needs > 0
		local cashMet = nextUp.maxed or nextUp.have >= nextUp.cost
		panel.title.Text = if nextUp.maxed then "Rebirth" else `Rebirth {nextUp.rebirth}`
		sub.Text = if nextUp.maxed
			then "All rebirths done!"
			elseif hasSlimes then "To rebirth you need both:"
			else "To rebirth you need:"

		need.Visible = not nextUp.maxed
		need.Size = UDim2.new(if hasSlimes then 0.5 else 1, if hasSlimes then -C.gap / 2 else 0, 0, rows.need.h)
		cashTick.Visible = cashMet
		cost.Text = Format.formatCash(nextUp.cost)
		setBar(nextUp.fraction)
		have.Text = `You have {Format.formatCash(nextUp.have)}`

		gets.Visible = not nextUp.maxed
		incomeTile.Visible = not nextUp.maxed
		lockTile.Visible = not nextUp.maxed
		incomeValue.Text = Format.formatMultiplier(nextUp.multiplier)
		lockValue.Text = if nextUp.lockGain > 0 then `+{nextUp.lockGain}s` else "Max"

		local fav = Selection.findSlime(state.slimes, state.favoriteId)
		keepLine.Text = `★ Keeps {if fav then ctx.Genome.displayName(fav.slime) else "your best slime"}`

		slimeCard.Visible = hasSlimes
		if hasSlimes then
			local allOwned = #nextUp.missing == 0
			local one = #needs == 1
			slimeLabel.Text = if one then "This slime" else "These slimes"
			slimeState.Visible = not allOwned
			slimeTick.Visible = allOwned
			for _, item in single do
				item.Visible = one
			end
			if one then
				local slimeNeed = needs[1]
				slimeName.Text = slimeNeed.name
				slimeName.TextColor3 = if slimeNeed.owned then Theme.Text else Theme.Muted
				slimeDesc.Text = if slimeNeed.owned then "Used up on rebirth" else "Catch or merge one first"
				slimeImage.BackgroundColor3 = Widgets.color3(slimeNeed.color)
				showSlime(slimeView, slimeGlyph, slimeNeed)
			end
			for i = 1, 3 do
				local slimeNeed = if one then nil else needs[i]
				if slimeNeed then
					local row = listRow(i)
					row.frame.Visible = true
					row.name.Text = slimeNeed.name
					row.name.TextColor3 = if slimeNeed.owned then Theme.Text else Theme.Muted
					row.tick.Visible = slimeNeed.owned
					row.image.BackgroundColor3 = Widgets.color3(slimeNeed.color)
					showSlime(row.view, row.glyph, slimeNeed)
				elseif listRows[i] then
					listRows[i].frame.Visible = false
				end
			end
		end

		reasonLine.Text = if nextUp.maxed
			then "🏆 All rebirths done"
			elseif #nextUp.missing > 0 and cashMet then `🔒 Get {missingNames(nextUp.missing)} to rebirth`
			else `🔒 Need {nextUp.need}`
		reasonLine.Visible = not nextUp.ready
		btn.instance.Visible = nextUp.ready
		btn.setEnabled(nextUp.ready)
	end

	return self
end

return Rebirth
