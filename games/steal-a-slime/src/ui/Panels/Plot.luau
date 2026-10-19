--!strict
--[[
	Plot panel: every slime on the plot with its income and sell price.
	Top line: pads in use and income per second as two chips. Each row: a round
	avatar well with the slime's 3D preview (SlimePreview; the rows nearest the
	scroll window, at most SlimePreview.MAX_LIVE, the rest show a colour circle), the name in its rarity colour (Secrets in a rainbow), income
	in gold, the favourite's perk chip, a star toggle and, under the name line,
	Appraise and Sell.
	Buttons: Sell(slimeId) (hold to confirm), Favorite(slimeId) / Favorite(nil),
	Appraise: swaps the list for the Appraise screen (AppraiseView): the slime, its size on a tape from
	Config.MIN_SIZE to MAX_SIZE, the odds that a reroll beats it, and Appraise(slimeId, "size") (hold to
	confirm, one request at a time; greyed out at the biggest size or without the cash); after a reroll a card
	shows was -> now for size and income from the server's answer, and a refusal shows its reason. A slime
	that is stolen or gone closes the screen.
	Rows being stolen turn red and show the thief.
]]

local UI = script.Parent.Parent
local AppraiseView = require(UI.AppraiseView)
local Format = require(UI.Format)
local Icons = require(UI.Icons)
local ItemIconView = require(UI.ItemIconView)
local ItemIcons = require(UI.ItemIcons)
local Layout = require(UI.Layout)
local Selection = require(UI.Selection)
local SlimePreview = require(UI.SlimePreview)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Plot = {}

-- Top line chips (design px).
Plot.HEADER = table.freeze({
	h = 26,
	padsW = 132, -- "🟢 50/50 pads"; the income chip starts after it
	gap = 8,
	listY = 34,
})

-- One slime row (design px). Buttons sit on their own line under the name so long names fit.
Plot.ROW = table.freeze({
	h = 112,
	stolenH = 62, -- no buttons while a thief carries it
	inset = 10, -- row width = list width - inset (room for the scroll bar)
	pad = 10,
	avatar = 46,
	avatarStroke = 3,
	textX = 66,
	nameY = 9,
	nameH = 22,
	nameSize = 18,
	subY = 33,
	subH = 18,
	subSize = 14,
	fav = 40,
	favSize = 26,
	buttonY = 58,
	buttonH = 44,
	appraiseW = 96,
	sellW = 110,
	buttonGap = 6,
	labelSize = 16,
	priceSize = 12,
	chipY = 68,
	chipH = 24,
	chipSize = 13,
	favTint = 0.2, -- favourite row: Row toward Gold
	stolenTint = 0.45, -- row being stolen: Row toward Bad
})

-- Appraise screen (design px): stacked top to bottom by placeAppraise, the result card only after a reroll.
Plot.POPUP = table.freeze({
	well = 84, -- the slime's preview
	wellStroke = 3,
	sizeChipH = 24,
	nameX = 100,
	nameY = 18,
	nameH = 26,
	nameSize = 21,
	incomeY = 48,
	incomeH = 20,
	incomeSize = 15,
	heroH = 96, -- hero block incl. the size chip under the well
	resultH = 76,
	resultBig = 26,
	resultSmall = 13,
	pinH = 28, -- size tag above the tape
	pinW = 52,
	pinSize = 14,
	tapeInset = 26, -- tape ends sit this far in, so the end tags stay inside the card
	tapeH = 22,
	tapeRadius = 8,
	tickW = 2,
	numsH = 18,
	numSize = 12,
	oddsH = 40,
	oddsSize = 14,
	ruleH = 20,
	ruleSize = 13,
	rerollH = 52,
	rerollSize = 20,
	backH = 44,
	backSize = 17,
	statusH = 20, -- a refused reroll's reason, under the button
	statusSize = 14,
	gap = 10,
	answerWait = 8, -- seconds a reroll may wait for the server before the button takes holds again
	resultTint = 0.3, -- result card: Row toward Good / Bad
	tickTransparency = 0.45,
})

-- Secret names: a rainbow over near-white text (a UIGradient multiplies the text colour).
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Theme.Bad),
	ColorSequenceKeypoint.new(0.25, Theme.Warn),
	ColorSequenceKeypoint.new(0.5, Theme.Gold),
	ColorSequenceKeypoint.new(0.75, Theme.Good),
	ColorSequenceKeypoint.new(1, Theme.Info),
})

-- A button caption with its price as a smaller second line (RichText).
local function priced(label: string, price: number): string
	return `{label}<br/><font size="{Plot.ROW.priceSize}">{Format.formatCash(price)}</font>`
end

function Plot.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "PlotPanel", "My Plot", "🏠")
	local head = Plot.HEADER
	local R = Plot.ROW
	local P = Plot.POPUP

	local padsChip = Widgets.chip({
		Name = "Pads",
		Text = "",
		Size = UDim2.fromOffset(0, head.h),
		Parent = panel.body,
	}, Theme.Good)
	local incomeChip = Widgets.chip({
		Name = "Income",
		Text = "",
		Position = UDim2.fromOffset(head.padsW + head.gap, 0),
		Size = UDim2.fromOffset(0, head.h),
		Parent = panel.body,
	}, Theme.Gold)

	local list = Widgets.scrollList({
		Name = "List",
		Position = UDim2.fromOffset(0, head.listY),
		Size = UDim2.new(1, 0, 1, -head.listY),
		Parent = panel.body,
	}, 6)

	local empty = Widgets.label({
		Name = "Empty",
		Text = "No slimes yet! Grab one at the fountain ⛲",
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		Size = UDim2.new(1, -8, 0, 40),
		Parent = list,
	})

	local favoriteId: string? = nil
	local open = false
	local petPerk: any = nil -- State.petPerk: the favourite's passive, shown as a chip on its row
	local latestViews: { [string]: any } = {}

	-- Appraise screen: replaces the list while open. The panel's title and corner tile switch to Appraise, the
	-- slime's preview sits over a size tape from Config.MIN_SIZE to MAX_SIZE (pin = its size, green = sizes a
	-- reroll could beat it with), the odds are spelled out, and after a reroll a card shows was -> now.
	local previewBuilders: SlimePreview.Builders = { species = ctx.buildSpecies, slime = ctx.buildSlime }
	local setAppraise: (id: string?) -> ()
	local cfg = ctx.Config
	local minSize, maxSize = cfg.MIN_SIZE :: number, cfg.MAX_SIZE :: number
	local decimals = cfg.APPRAISE_SIZE_DECIMALS :: number
	local popup = create("Frame", {
		Name = "AppraisePopup",
		Visible = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0), -- placeAppraise sets the height; the card is sized to it
		Parent = panel.body,
	})
	local popupId: string? = nil
	local popupAnswer: any = nil -- the last reroll's Types.Appraisal for this slime; `synced` once State shows it
	local popupError: string? = nil -- a refused reroll's reason
	local pending: number? = nil -- the reroll request in flight
	local requests = 0
	local canReroll = false
	local cash: number? = nil -- State.cash
	local appraiseArt = ItemIconView.new({
		Name = "AppraiseIcon",
		Id = "Appraise",
		Size = Layout.PANEL_CHROME.icon - 12,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = panel.icon.Parent,
	}, ItemIcons.of(ctx))
	appraiseArt.instance.Visible = false

	local heroWell = create("Frame", {
		Name = "Well",
		BackgroundColor3 = Theme.Row:Lerp(Theme.Ink, SlimePreview.WELL_TINT),
		Size = UDim2.fromOffset(P.well, P.well),
		Parent = popup,
	}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }), Widgets.stroke(Theme.Ink, P.wellStroke) })
	local heroPreview = create("ViewportFrame", {
		Name = "Preview",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = heroWell,
	}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	local sizeChip = Widgets.chip({
		Name = "SizeChip",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(P.well // 2, P.well - P.sizeChipH // 2),
		Size = UDim2.fromOffset(0, P.sizeChipH),
		Parent = popup,
	}, Theme.Gold)
	local heroName = Widgets.label({
		Name = "SlimeName",
		Font = Theme.Font,
		TextSize = P.nameSize,
		Position = UDim2.fromOffset(P.nameX, P.nameY),
		Size = UDim2.new(1, -P.nameX, 0, P.nameH),
		Parent = popup,
	})
	local heroRainbow = create("UIGradient", { Name = "Rainbow", Color = RAINBOW, Enabled = false, Parent = heroName })
	local heroIncome = Widgets.label({
		Name = "Income",
		RichText = true,
		TextSize = P.incomeSize,
		TextColor3 = Theme.Muted,
		Position = UDim2.fromOffset(P.nameX, P.incomeY),
		Size = UDim2.new(1, -P.nameX, 0, P.incomeH),
		Parent = popup,
	})

	-- Was -> now after a reroll.
	local resultCard = Widgets.rowFrame({ Name = "Result", Visible = false, Size = UDim2.new(1, 0, 0, P.resultH) })
	resultCard.Parent = popup
	local function resultSide(
		name: string,
		xScale: number,
		align: Enum.TextXAlignment
	): (TextLabel, TextLabel, TextLabel)
		local function line(suffix: string, y: number, h: number, props: { [string]: any }): TextLabel
			props.Name = name .. suffix
			props.TextXAlignment = align
			props.AnchorPoint = Vector2.new(xScale, 0)
			props.Position = UDim2.new(xScale, if xScale == 0 then 12 else -12, 0, y)
			props.Size = UDim2.new(0.4, 0, 0, h)
			props.Parent = resultCard
			return Widgets.label(props)
		end
		local cap = line("Label", 8, 14, { TextSize = P.resultSmall, TextColor3 = Theme.Muted })
		local big = line("Size", 22, 28, { Font = Theme.Font, TextSize = P.resultBig })
		local income = line("Income", 52, 16, { TextSize = P.resultSmall })
		return cap, big, income
	end
	local wasCap, wasSize, wasIncome = resultSide("Was", 0, Enum.TextXAlignment.Left)
	local nowCap, nowSize, nowIncome = resultSide("Now", 1, Enum.TextXAlignment.Right)
	wasCap.Text = "Was"
	nowCap.Text = "Now"
	Widgets.label({
		Name = "Arrow",
		Text = "→",
		Font = Theme.Font,
		TextSize = P.resultBig,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(40, 30),
		Parent = resultCard,
	})

	-- The size tape: gold, a tick every 0.1, the sizes that would beat the current one striped green on the right.
	local tapeBlock = create("Frame", {
		Name = "Tape",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, P.pinH + P.tapeH + P.numsH + 6),
		Parent = popup,
	})
	local tape = create("Frame", {
		Name = "Bar",
		BackgroundColor3 = Theme.Gold,
		Position = UDim2.fromOffset(P.tapeInset, P.pinH),
		Size = UDim2.new(1, -P.tapeInset * 2, 0, P.tapeH),
		Parent = tapeBlock,
	}, { Widgets.corner(P.tapeRadius), Widgets.stroke(Theme.Ink, Widgets.KIT.rowStroke) })
	Widgets.shade(tape)
	local steps = math.floor((maxSize - minSize) / 0.1 + 0.5)
	for i = 1, steps - 1 do
		create("Frame", {
			Name = "Tick",
			BorderSizePixel = 0,
			BackgroundColor3 = Theme.Ink,
			BackgroundTransparency = P.tickTransparency,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(i / steps, 0),
			Size = UDim2.new(0, P.tickW, 1, 0),
			Parent = tape,
		})
	end
	local better = create("Frame", {
		Name = "Better",
		BorderSizePixel = 0,
		BackgroundColor3 = Theme.Good,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0, 1),
		Parent = tape,
	}, { Widgets.corner(P.tapeRadius) })
	for _, v in AppraiseView.ticks(minSize, maxSize) do
		Widgets.label({
			Name = "Num",
			Text = string.format("%.1f", v),
			Font = Theme.Font,
			TextSize = P.numSize,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(AppraiseView.fraction(v, minSize, maxSize), 0, 1, 6),
			Size = UDim2.fromOffset(40, P.numsH),
			Parent = tape,
		})
	end
	-- A pin: a size tag over the tape with a line down through it. `ghost` = the size before the last reroll.
	local function pin(name: string, ghost: boolean): (Frame, TextLabel)
		local holder = create("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.new(0, P.pinW, 1, P.pinH + 6),
			Position = UDim2.fromOffset(0, -P.pinH),
			ZIndex = if ghost then 1 else 2,
			Parent = tape,
		})
		create("Frame", {
			Name = "Line",
			BorderSizePixel = 0,
			BackgroundColor3 = if ghost then Theme.Muted else Theme.Ink,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, P.pinH - 6),
			Size = UDim2.new(0, 4, 1, -(P.pinH - 6)),
			Parent = holder,
		}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		local tag = Widgets.label({
			Name = "Tag",
			Font = Theme.Font,
			TextSize = P.pinSize,
			TextColor3 = if ghost then Theme.Muted else Theme.Ink,
			TextXAlignment = Enum.TextXAlignment.Center,
			BackgroundTransparency = 0,
			BackgroundColor3 = if ghost then Theme.Bg else Theme.Text,
			Size = UDim2.new(1, 0, 0, P.pinH - 6),
			Parent = holder,
		})
		Widgets.corner(8).Parent = tag
		Widgets.stroke(if ghost then Theme.Muted else Theme.Ink, Widgets.KIT.rowStroke).Parent = tag
		return holder, tag
	end
	local ghostPin, ghostTag = pin("WasPin", true)
	local nowPin, nowTag = pin("NowPin", false)

	local odds = Widgets.label({
		Name = "Odds",
		RichText = true,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextSize = P.oddsSize,
		TextColor3 = Theme.Muted,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Ink,
		Size = UDim2.new(1, 0, 0, P.oddsH),
		Parent = popup,
	})
	Widgets.corner(Widgets.KIT.radius).Parent = odds
	create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = odds })
	local rule = Widgets.label({
		Name = "Rule",
		Text = `A reroll picks a new size from {string.format("%.1f", minSize)} to {string.format("%.1f", maxSize)}. Income grows with size.`,
		TextSize = P.ruleSize,
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.new(1, 0, 0, P.ruleH),
		Parent = popup,
	})

	local function popupSlime(): any?
		local view = popupId and latestViews[popupId]
		return view
	end
	local refreshPopup: () -> ()
	local function reroll()
		local id = popupId
		if id == nil or popupSlime() == nil or ctx.ask == nil or pending ~= nil or not canReroll then
			return
		end
		requests += 1
		local token = requests
		pending = token
		popupError = nil
		task.delay(P.answerWait, function()
			if pending == token then
				pending = nil
				if popupId ~= nil then
					refreshPopup()
				end
			end
		end)
		refreshPopup()
		ctx.ask("Appraise", function(result: any)
			if pending == token then
				pending = nil
			end
			if popupId ~= id then
				return
			end
			local a = if type(result) == "table" and result.ok ~= false then result.appraisal else nil
			if type(a) == "table" and a.slimeId == id then
				popupAnswer = table.clone(a)
			else
				popupError = AppraiseView.refusal(if type(result) == "table" then result.message else nil)
			end
			refreshPopup()
		end, id, "size")
	end
	local rerollBtn = Widgets.holdButton({
		Name = "RerollSize",
		Text = "Reroll",
		TextSize = P.rerollSize,
		Size = UDim2.new(1, 0, 0, P.rerollH),
	}, Theme.Good, reroll, cfg.HOLD_CONFIRM_SECONDS)
	rerollBtn.instance.Parent = popup
	local backBtn = Widgets.button(
		{
			Name = "Done",
			Text = "Back to My Plot",
			TextSize = P.backSize,
			Size = UDim2.new(1, 0, 0, P.backH),
		},
		Theme.Info,
		function()
			setAppraise(nil)
		end
	)
	backBtn.instance.Parent = popup
	local status = Widgets.label({
		Name = "Status",
		Visible = false,
		TextSize = P.statusSize,
		TextColor3 = Theme.Bad,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, P.statusH),
		Parent = popup,
	})

	-- Stacks the screen's blocks (the result card only after a reroll) and sizes the popup to them.
	local function placeAppraise()
		local y = P.heroH + P.gap
		local blocks: { GuiObject } = {}
		if resultCard.Visible then
			table.insert(blocks, resultCard)
		end
		table.insert(blocks, tapeBlock)
		table.insert(blocks, odds)
		if rule.Visible then
			table.insert(blocks, rule)
		end
		table.insert(blocks, rerollBtn.instance)
		if status.Visible then
			table.insert(blocks, status)
		end
		table.insert(blocks, backBtn.instance)
		for _, b in blocks do
			b.Position = UDim2.fromOffset(0, y)
			y += b.Size.Y.Offset + P.gap
		end
		local h = y - P.gap
		if popup.Size.Y.Offset ~= h then
			popup.Size = UDim2.new(1, 0, 0, h)
			-- The result card came or went: the card follows without waiting for the next State push.
			if popup.Visible and ctx.relayout then
				ctx.relayout()
			end
		end
	end

	local function colorHex(c: Color3): string
		return `#{c:ToHex()}`
	end

	refreshPopup = function()
		local view = popupSlime()
		if view == nil or view.stolenBy ~= nil then
			setAppraise(nil)
			return
		end
		local slime = view.slime
		local rarity = cfg.RARITIES[slime.tier]
		local isSecret = slime.tier == cfg.SECRET_TIER
		heroName.Text = ctx.Genome.displayName(slime)
		heroName.TextColor3 = if isSecret then Theme.Text elseif rarity then Widgets.color3(rarity.color) else Theme.Text
		heroRainbow.Enabled = isSecret
		-- A reroll's answer can land before the State push with the new size: show the server's answer until
		-- State shows it too (cash in that State is from before the reroll, so the cost is still to come off).
		local a = popupAnswer
		local size, income, cost = slime.size, view.income or 0, view.appraiseCost
		local unpaid = 0
		if a and not a.synced then
			if math.abs(slime.size - a.afterSize) < 0.005 then
				a.synced = true
			else
				size, income, cost, unpaid = a.afterSize, a.incomeAfter, a.costAfter, a.cost
			end
		end
		local r = if a then AppraiseView.result(a) else nil
		local sizeText = AppraiseView.sizeText(size)
		sizeChip.Text = sizeText
		heroIncome.Text = `<font color="{colorHex(Theme.Gold)}">{Format.formatRate(income)}</font> at size {sizeText}`
		SlimePreview.mountSlime(heroPreview, slime, previewBuilders)

		local now = AppraiseView.fraction(size, minSize, maxSize)
		nowPin.Position = UDim2.new(now, 0, 0, -P.pinH)
		nowTag.Text = sizeText
		better.Size = UDim2.fromScale(1 - now, 1)
		better.Visible = now < 1

		local o = AppraiseView.odds(size, minSize, maxSize, decimals)
		odds.Text =
			`<font face="FredokaOne" color="{colorHex(if o.warn then Theme.Warn else Theme.Good)}">{o.chance}</font> {o.detail}`

		local showResult = r ~= nil and math.abs(r.afterSize - size) < 0.005
		resultCard.Visible = showResult
		rule.Visible = not showResult
		ghostPin.Visible = showResult
		if showResult and r then
			local tone = if r.better == true then Theme.Good elseif r.better == false then Theme.Bad else Theme.Text
			resultCard.BackgroundColor3 = if r.better == nil then Theme.Row else Theme.Row:Lerp(tone, P.resultTint)
			wasSize.Text = AppraiseView.sizeText(r.beforeSize)
			wasIncome.Text = Format.formatRate(r.incomeBefore)
			wasIncome.TextColor3 = Theme.Muted
			nowSize.Text = AppraiseView.sizeText(r.afterSize)
			nowSize.TextColor3 = tone
			nowIncome.Text = Format.formatRate(r.incomeAfter)
			nowIncome.TextColor3 = tone
			ghostPin.Position = UDim2.new(AppraiseView.fraction(r.beforeSize, minSize, maxSize), 0, 0, -P.pinH)
			ghostTag.Text = AppraiseView.sizeText(r.beforeSize)
		end
		local biggest = AppraiseView.betterChance(size, minSize, maxSize, decimals) <= 0
		local affordable = cash == nil or cost == nil or cash - unpaid >= cost
		canReroll = pending == nil and not biggest and affordable
		rerollBtn.setEnabled(canReroll)
		local price = if cost then Format.formatCash(cost) else nil
		rerollBtn.setText(
			if pending ~= nil
				then "Rerolling..."
				elseif biggest then "Already the biggest size"
				elseif not affordable and price then `Need {price} to reroll`
				elseif price then `Reroll for {price}`
				else "Reroll"
		)
		status.Visible = popupError ~= nil
		status.Text = popupError or ""
		placeAppraise()
	end

	-- Opens the Appraise screen for slime `id` (nil = back to the list).
	setAppraise = function(id: string?)
		popupId = id
		popupAnswer = nil
		popupError = nil
		local on = id ~= nil
		popup.Visible = on
		list.Visible = not on
		padsChip.Visible = not on
		incomeChip.Visible = not on
		panel.title.Text = if on then "Appraise" else "My Plot"
		panel.icon.Visible = not on
		appraiseArt.instance.Visible = on
		appraiseArt.setActive(on)
		if on then
			refreshPopup()
		else
			SlimePreview.unmountSlime(heroPreview)
		end
		if ctx.relayout then
			ctx.relayout()
		end
	end

	local function makeRow(view: any)
		local id = view.slime.id
		local frame = Widgets.rowFrame({
			Name = id,
			Size = UDim2.new(1, -R.inset, 0, R.h),
		})
		local avatar = create("Frame", {
			Name = "Swatch",
			Size = UDim2.fromOffset(R.avatar, R.avatar),
			Position = UDim2.fromOffset(R.pad, R.pad),
			Parent = frame,
		}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }), Widgets.stroke(Theme.Ink, R.avatarStroke) })
		Widgets.shade(avatar)
		local preview = create("ViewportFrame", {
			Name = "Preview",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			Parent = avatar,
		}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		local textW = -(R.textX + R.pad + R.fav + 8)
		local name = Widgets.label({
			Name = "SlimeName",
			Font = Theme.Font,
			TextSize = R.nameSize,
			Size = UDim2.new(1, textW, 0, R.nameH),
			Position = UDim2.fromOffset(R.textX, R.nameY),
			Parent = frame,
		})
		local rainbow = create("UIGradient", { Name = "Rainbow", Color = RAINBOW, Enabled = false, Parent = name })
		local sub = Widgets.label({
			Name = "Sub",
			TextSize = R.subSize,
			Size = UDim2.new(1, textW, 0, R.subH),
			Position = UDim2.fromOffset(R.textX, R.subY),
			Parent = frame,
		})
		local fav = Widgets.button(
			{
				Name = "Favorite",
				Text = Icons.FAV_ON,
				TextSize = R.favSize,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -R.pad, 0, R.pad),
				Size = UDim2.fromOffset(R.fav, R.fav),
			},
			Theme.Gold,
			function()
				if favoriteId == id then
					ctx.send("Favorite", nil)
				else
					ctx.send("Favorite", id)
				end
			end
		)
		fav.instance.Parent = frame
		local sell = Widgets.holdButton(
			{
				Name = "Sell",
				Text = "Sell",
				RichText = true,
				TextSize = R.labelSize,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -R.pad, 0, R.buttonY),
				Size = UDim2.fromOffset(R.sellW, R.buttonH),
			},
			Theme.Bad,
			function()
				ctx.send("Sell", id)
			end,
			ctx.Config.HOLD_CONFIRM_SECONDS
		)
		sell.instance.Parent = frame
		local appraise = Widgets.button(
			{
				Name = "Appraise",
				Text = "Appraise",
				RichText = true,
				TextSize = R.labelSize,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -(R.pad + R.sellW + R.buttonGap), 0, R.buttonY),
				Size = UDim2.fromOffset(R.appraiseW, R.buttonH),
			},
			Theme.Info,
			function()
				setAppraise(id)
			end
		)
		appraise.instance.Parent = frame
		-- Follow-pet perk chip ("🍀 +5% luck"), only on the favourite row, left of the buttons.
		local chip = Widgets.chip({
			Name = "PerkChip",
			Text = "",
			Visible = false,
			Font = Theme.FontBody,
			TextSize = R.chipSize,
			Position = UDim2.fromOffset(R.textX, R.chipY),
			Size = UDim2.fromOffset(0, R.chipH),
			Parent = frame,
		}, Theme.Good)
		return {
			chip = chip,
			instance = frame,
			swatch = avatar,
			preview = preview,
			name = name,
			rainbow = rainbow,
			sub = sub,
			fav = fav,
			sell = sell,
			appraise = appraise,
		}
	end

	-- The well behind a live preview, the slime's colour circle without one.
	local well = Theme.Row:Lerp(Theme.Ink, SlimePreview.WELL_TINT)
	local function paintAvatar(row: any)
		row.swatch.BackgroundColor3 = if row.preview.Visible then well else Widgets.color3(row.slime.color)
	end

	local function updateRow(row: any, view: any)
		local slime = view.slime
		local rarity = ctx.Config.RARITIES[slime.tier]
		local isFav = slime.id == favoriteId
		local isSecret = slime.tier == ctx.Config.SECRET_TIER
		local stolen = view.stolenBy ~= nil
		row.slime = slime
		paintAvatar(row)
		row.name.Text = (if isFav then `{Icons.FAV_ON} ` else "") .. ctx.Genome.displayName(slime)
		row.name.TextColor3 = if isSecret then Theme.Text elseif rarity then Widgets.color3(rarity.color) else Theme.Text
		row.rainbow.Enabled = isSecret
		-- The star: gold when favourited, a sunken Ink well with a muted star when not (still pressable).
		row.fav.setColor(if isFav then Theme.Gold else Theme.Ink)
		if not isFav then
			row.fav.instance.TextColor3 = Theme.Muted
			row.fav.instance.TextStrokeTransparency = 1
		end
		row.sell.setText(priced("Sell", view.sellPrice))
		local showChip = isFav and petPerk ~= nil and not stolen
		row.chip.Visible = showChip
		if showChip then
			row.chip.Text = `{petPerk.icon} {petPerk.text}`
		end
		row.instance.Size = UDim2.new(1, -R.inset, 0, if stolen then R.stolenH else R.h)
		if stolen then
			row.instance.BackgroundColor3 = Theme.Row:Lerp(Theme.Bad, R.stolenTint)
			row.sub.Text = `🚨 {ctx.playerName(view.stolenBy)} is stealing it!`
			row.sub.Font = Theme.Font
			row.sub.TextColor3 = Theme.Warn
			row.sell.instance.Visible = false
			row.appraise.instance.Visible = false
		else
			row.instance.BackgroundColor3 = if isFav then Theme.Row:Lerp(Theme.Gold, R.favTint) else Theme.Row
			row.sub.Text = Format.formatRate(view.income)
			row.sub.Font = Theme.FontBody
			row.sub.TextColor3 = Theme.Gold
			row.sell.instance.Visible = true
			row.appraise.instance.Visible = view.appraiseCost ~= nil
			if view.appraiseCost then
				row.appraise.setText(priced("Appraise", view.appraiseCost))
			end
		end
	end

	local rows = Widgets.keyedList(list, function(view: any)
		return view.slime.id
	end, makeRow, updateRow)

	-- Live previews for the rows nearest the middle of the scroll window (only while the card is open).
	local function refreshPreviews()
		if not open then
			return
		end
		local chrome = Layout.PANEL_CHROME
		local viewH = math.max(panel.frame.Size.Y.Offset - chrome.header - chrome.pad - head.listY, 0)
		local entries: { SlimePreview.ListEntry } = {}
		for _, row in rows.rows do
			table.insert(entries, {
				viewport = row.preview,
				slime = row.slime,
				y = row.instance.Position.Y.Offset,
				h = row.instance.Size.Y.Offset,
			})
		end
		SlimePreview.syncNearest(entries, list.CanvasPosition.Y + viewH / 2, previewBuilders)
		for _, row in rows.rows do
			paintAvatar(row)
		end
	end
	list:GetPropertyChangedSignal("CanvasPosition"):Connect(refreshPreviews)

	local self = { frame = panel.frame, close = panel.close }

	-- Shows the Appraise screen for one of the plot's slimes (what its Appraise button does).
	function self.openAppraise(id: string)
		if latestViews[id] then
			setAppraise(id)
		end
	end

	function self.setOpen(isOpen: boolean)
		open = isOpen
		if not isOpen and popupId ~= nil then
			setAppraise(nil)
		end
		refreshPreviews()
	end

	function self.update(state: any)
		favoriteId = state.favoriteId
		petPerk = state.petPerk
		cash = state.cash
		latestViews = {}
		for _, view in state.slimes do
			latestViews[view.slime.id] = view
		end
		if popupId ~= nil then
			refreshPopup()
		end
		local count = #state.slimes
		padsChip.Text = `🟢 {count}/{state.padsUnlocked} pads`
		incomeChip.Text = Format.formatRate(state.incomePerSec)
		empty.Visible = count == 0
		rows.sync(Selection.sorted(state.slimes, favoriteId))
		refreshPreviews()
	end

	return self
end

return Plot
