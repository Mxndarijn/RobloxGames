--!strict
--[[
	Plot panel: every slime on the plot with tier, income and sell price.
	Buttons: Sell(slimeId) (hold to confirm), Favorite(slimeId) / Favorite(nil),
	Appraise (FEATURES.Appraise): opens a popup with the cost; Appraise(slimeId,
	"mutation" | "size") rerolls it and the popup shows before -> after.
	Rows being stolen turn red and show the thief.
]]

local UI = script.Parent.Parent
local Format = require(UI.Format)
local Icons = require(UI.Icons)
local ItemIconView = require(UI.ItemIconView)
local ItemIcons = require(UI.ItemIcons)
local Selection = require(UI.Selection)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Plot = {}

-- Every mutation of a slime for the labels ("Glow Syrup"), or "None".
local function mutationsText(ctx: any, list: { string }): string
	local shown = ctx.Genome.mutationsDisplay(list)
	return if shown == "" then "None" else shown
end

function Plot.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "PlotPanel", "My Plot", "🏠", Color3.fromRGB(70, 130, 220))

	local header = Widgets.label({
		Name = "Header",
		Text = "",
		TextColor3 = Theme.Muted,
		Size = UDim2.new(1, 0, 0, 20),
		Parent = panel.body,
	})

	local list = Widgets.scrollList({
		Name = "List",
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 1, -26),
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

	-- Appraise popup: covers the list while open.
	local popup = create("Frame", {
		Name = "AppraisePopup",
		Visible = false,
		BackgroundColor3 = Theme.Bg,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
		Parent = panel.body,
	}, { Widgets.corner(10) })
	local popupId: string? = nil
	local function popupLabel(name: string, y: number, props: { [string]: any }?): TextLabel
		local p = props or {}
		p.Name = name
		p.Size = p.Size or UDim2.new(1, -16, 0, 24)
		p.Position = UDim2.fromOffset(8, y)
		p.ZIndex = 21
		p.Parent = popup
		return Widgets.label(p)
	end
	ItemIconView.new({
		Name = "AppraiseIcon",
		Id = "Appraise",
		Size = 44,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 4),
		ZIndex = 21,
		Parent = popup,
	}, ItemIcons.of(ctx)).setActive(true)
	local popupTitle = popupLabel("Title", 6, { Font = Theme.Font, TextSize = 18, Size = UDim2.new(1, -64, 0, 24) })
	local popupNow = popupLabel("Now", 34, { TextColor3 = Theme.Muted, Size = UDim2.new(1, -64, 0, 24) })
	local popupCost = popupLabel("Cost", 60, { TextColor3 = Theme.Gold })
	local popupBefore = popupLabel("Before", 92, { Text = "" })
	local popupAfter = popupLabel("After", 118, { Font = Theme.Font, Text = "" })
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
			TextSize = 14,
			Position = UDim2.new(x, 8, 0, 152),
			Size = UDim2.new(0.5, -12, 0, 36),
			ZIndex = 21,
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
			TextSize = 14,
			Position = UDim2.fromOffset(8, 196),
			Size = UDim2.new(1, -16, 0, 32),
			ZIndex = 21,
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
		popupCost.Text = `Cost: 💰 {Format.formatCash(view.appraiseCost or 0)} per reroll`
	end

	local function makeRow(view: any)
		local id = view.slime.id
		local frame = create("Frame", {
			Name = id,
			Size = UDim2.new(1, -10, 0, 56),
			BackgroundColor3 = Theme.Row,
		}, { Widgets.corner(8) })
		local swatch = create("Frame", {
			Name = "Swatch",
			Size = UDim2.fromOffset(36, 36),
			Position = UDim2.fromOffset(8, 10),
			Parent = frame,
		}, { Widgets.corner(18) })
		local name = Widgets.label({
			Name = "SlimeName",
			Font = Theme.Font,
			Size = UDim2.new(1, -330, 0, 20),
			Position = UDim2.fromOffset(52, 8),
			Parent = frame,
		})
		local sub = Widgets.label({
			Name = "Sub",
			TextSize = 13,
			TextColor3 = Theme.Muted,
			Size = UDim2.new(1, -330, 0, 18),
			Position = UDim2.fromOffset(52, 30),
			Parent = frame,
		})
		local fav = Widgets.button(
			{
				Name = "Favorite",
				Text = Icons.FAV_OFF,
				TextSize = 20,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -120, 0.5, 0),
				Size = UDim2.fromOffset(40, 36),
			},
			Theme.BgLight,
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
				TextSize = 13,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(104, 36),
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
				TextSize = 12,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -166, 0.5, 0),
				Size = UDim2.fromOffset(84, 36),
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
		-- Follow-pet perk chip ("🍀 +5% luck"), only on the favourite row (which grows to fit it).
		local chip = create("Frame", {
			Name = "PerkChip",
			Visible = false,
			Position = UDim2.fromOffset(52, 54),
			Size = UDim2.fromOffset(150, 20),
			BackgroundColor3 = Color3.fromRGB(60, 52, 24),
			Parent = frame,
		}, { Widgets.corner(10) })
		local chipText = Widgets.label({
			Name = "Text",
			Text = "",
			TextSize = 13,
			TextColor3 = Theme.Gold,
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.new(1, -12, 1, 0),
			Parent = chip,
		})
		return {
			chip = chip,
			chipText = chipText,
			instance = frame,
			swatch = swatch,
			name = name,
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
		row.swatch.BackgroundColor3 = Widgets.color3(slime.color)
		row.name.Text = (if isFav then "★ " else "") .. ctx.Genome.displayName(slime)
		row.name.TextColor3 = if rarity then Widgets.color3(rarity.color) else Theme.Text
		row.fav.setText(if isFav then Icons.FAV_ON else Icons.FAV_OFF)
		row.fav.setColor(if isFav then Theme.Gold else Theme.BgLight)
		row.sell.setText(`💰 {Format.formatCash(view.sellPrice)}`)
		local showChip = isFav and petPerk ~= nil
		row.chip.Visible = showChip
		row.instance.Size = UDim2.new(1, -10, 0, if showChip then 80 else 56)
		if showChip then
			row.chipText.Text = `{petPerk.icon} {petPerk.text}`
		end
		if view.stolenBy ~= nil then
			row.instance.BackgroundColor3 = Color3.fromRGB(120, 40, 55)
			row.sub.Text = `🚨 {ctx.playerName(view.stolenBy)} is stealing it!`
			row.sub.TextColor3 = Theme.Warn
			row.sell.instance.Visible = false
			row.appraise.instance.Visible = false
		else
			row.instance.BackgroundColor3 = if isFav then Color3.fromRGB(78, 70, 40) else Theme.Row
			row.sub.Text = `💰 {Format.formatRate(view.income)}`
			row.sub.TextColor3 = Theme.Muted
			row.sell.instance.Visible = true
			row.appraise.instance.Visible = view.appraiseCost ~= nil
			if view.appraiseCost then
				row.appraise.setText(`Appraise\n💰 {Format.formatCash(view.appraiseCost)}`)
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
		header.Text = `🟢 {count}/{state.padsUnlocked} pads · 💰 {Format.formatRate(state.incomePerSec)}`
		empty.Visible = count == 0
		rows.sync(Selection.sorted(state.slimes, favoriteId))
	end

	return self
end

return Plot
