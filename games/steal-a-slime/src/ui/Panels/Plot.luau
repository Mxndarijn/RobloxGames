--!strict
--[[
	Plot panel: every slime on the plot with its income and sell price.
	Top line: pads in use and income per second as two chips. Each row: a round
	colour avatar, the name in its rarity colour (Secrets in a rainbow), income
	in gold, the favourite's perk chip, a star toggle and, under the name line,
	Appraise and Sell.
	Buttons: Sell(slimeId) (hold to confirm), Favorite(slimeId) / Favorite(nil),
	Appraise: opens a popup with the cost; Appraise(slimeId,
	"mutation" | "size") rerolls it and the popup shows before -> after.
	Rows being stolen turn red and show the thief.
]]

local UI = script.Parent.Parent
local Format = require(UI.Format)
local Icons = require(UI.Icons)
local ItemIconView = require(UI.ItemIconView)
local ItemIcons = require(UI.ItemIcons)
local Layout = require(UI.Layout)
local Selection = require(UI.Selection)
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

-- Appraise popup (design px).
Plot.POPUP = table.freeze({
	pad = 8,
	icon = 44,
	titleY = 6,
	titleSize = 18,
	nowY = 34,
	costY = 60,
	beforeY = 92,
	afterY = 118,
	lineH = 24,
	textSize = 15,
	buttonY = 152,
	buttonH = 40,
	buttonSize = 14,
	doneY = 200,
	doneH = 36,
})

-- Secret names: a rainbow over near-white text (a UIGradient multiplies the text colour).
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Theme.Bad),
	ColorSequenceKeypoint.new(0.25, Theme.Warn),
	ColorSequenceKeypoint.new(0.5, Theme.Gold),
	ColorSequenceKeypoint.new(0.75, Theme.Good),
	ColorSequenceKeypoint.new(1, Theme.Info),
})

-- Every mutation of a slime for the labels ("Glow Syrup"), or "None".
local function mutationsText(ctx: any, list: { string }): string
	local shown = ctx.Genome.mutationsDisplay(list)
	return if shown == "" then "None" else shown
end

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
	local petPerk: any = nil -- State.petPerk: the favourite's passive, shown as a chip on its row
	local latestViews: { [string]: any } = {}

	-- Appraise popup: covers the list while open (ZIndexBehavior.Sibling: above the list, its sibling).
	local popup = create("Frame", {
		Name = "AppraisePopup",
		Visible = false,
		BackgroundColor3 = Theme.Bg,
		Size = UDim2.fromScale(1, 1),
		ZIndex = Layout.ZINDEX.Menu,
		Parent = panel.body,
	}, { Widgets.corner(Widgets.KIT.rowRadius), Widgets.stroke(Theme.Ink, Widgets.KIT.rowStroke) })
	local popupId: string? = nil
	local function popupLabel(name: string, y: number, props: { [string]: any }?): TextLabel
		local p = props or {}
		p.Name = name
		p.TextSize = p.TextSize or P.textSize
		p.Size = p.Size or UDim2.new(1, -P.pad * 2, 0, P.lineH)
		p.Position = UDim2.fromOffset(P.pad, y)
		p.Parent = popup
		return Widgets.label(p)
	end
	ItemIconView.new({
		Name = "AppraiseIcon",
		Id = "Appraise",
		Size = P.icon,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -P.pad, 0, 4),
		Parent = popup,
	}, ItemIcons.of(ctx)).setActive(true)
	local besideIcon = -(P.pad * 2 + P.icon + 12)
	local popupTitle = popupLabel(
		"Title",
		P.titleY,
		{ Font = Theme.Font, TextSize = P.titleSize, Size = UDim2.new(1, besideIcon, 0, P.lineH) }
	)
	local popupNow =
		popupLabel("Now", P.nowY, { TextColor3 = Theme.Muted, Size = UDim2.new(1, besideIcon, 0, P.lineH) })
	local popupCost = popupLabel("Cost", P.costY, { Font = Theme.Font, TextColor3 = Theme.Gold })
	local popupBefore = popupLabel("Before", P.beforeY, { Text = "", TextColor3 = Theme.Muted })
	local popupAfter = popupLabel("After", P.afterY, { Font = Theme.Font, Text = "" })
	local function popupSlime(): any?
		local view = popupId and latestViews[popupId]
		return view
	end
	local function reroll(kind: string)
		local id = popupId
		if id == nil or ctx.request == nil then
			return
		end
		ctx.request("Appraise", function(result: any)
			local a = result and result.appraisal
			if not a or a.slimeId ~= id then
				return
			end
			if a.kind == "mutation" then
				popupBefore.Text = `Before: {mutationsText(ctx, a.beforeMutations or { a.beforeMutation })}`
				popupAfter.Text = `After: {mutationsText(ctx, a.afterMutations or { a.afterMutation })}`
			else
				popupBefore.Text = `Before: size {string.format("%.2f", a.beforeSize)}`
				popupAfter.Text = `After: size {string.format("%.2f", a.afterSize)}`
			end
		end, id, kind)
	end
	local function popupButton(name: string, text: string, x: number, color: Color3, onClick: () -> ())
		local btn = Widgets.holdButton({
			Name = name,
			Text = text,
			TextSize = P.buttonSize,
			Position = UDim2.new(x, P.pad, 0, P.buttonY),
			Size = UDim2.new(0.5, -(P.pad + 4), 0, P.buttonH),
		}, color, onClick, ctx.Config.HOLD_CONFIRM_SECONDS)
		btn.instance.Parent = popup
		return btn
	end
	popupButton("RerollMutation", "Reroll mutation", 0, Theme.Info, function()
		reroll("mutation")
	end)
	popupButton("RerollSize", "Reroll size", 0.5, Theme.Info, function()
		reroll("size")
	end)
	local popupClose = Widgets.button(
		{
			Name = "Done",
			Text = "Done",
			TextSize = P.buttonSize,
			Position = UDim2.fromOffset(P.pad, P.doneY),
			Size = UDim2.new(1, -P.pad * 2, 0, P.doneH),
		},
		Theme.BgLight,
		function()
			popupId = nil
			popup.Visible = false
		end
	)
	popupClose.instance.Parent = popup
	local function refreshPopup()
		local view = popupSlime()
		if view == nil then
			popupId = nil
			popup.Visible = false
			return
		end
		local slime = view.slime
		popupTitle.Text = `Appraise {ctx.Genome.displayName(slime)}`
		popupNow.Text =
			`Mutation: {mutationsText(ctx, ctx.Genome.mutationList(slime))} · size {string.format("%.2f", slime.size)}`
		popupCost.Text = `Cost: {Format.formatCash(view.appraiseCost or 0)} per reroll`
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
				popupId = id
				popup.Visible = true
				popupBefore.Text = ""
				popupAfter.Text = ""
				refreshPopup()
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
			name = name,
			rainbow = rainbow,
			sub = sub,
			fav = fav,
			sell = sell,
			appraise = appraise,
		}
	end

	local function updateRow(row: any, view: any)
		local slime = view.slime
		local rarity = ctx.Config.RARITIES[slime.tier]
		local isFav = slime.id == favoriteId
		local isSecret = slime.tier == ctx.Config.SECRET_TIER
		local stolen = view.stolenBy ~= nil
		row.swatch.BackgroundColor3 = Widgets.color3(slime.color)
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

	local self = { frame = panel.frame, close = panel.close }

	function self.update(state: any)
		favoriteId = state.favoriteId
		petPerk = state.petPerk
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
	end

	return self
end

return Plot
