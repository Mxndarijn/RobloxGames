--!strict
--[[
	Plot panel: every slime on the plot with tier, income and sell price.
	Buttons: Sell(slimeId) (two clicks), Favorite(slimeId) / Favorite(nil).
	Rows being stolen turn red and show the thief.
]]

local UI = script.Parent.Parent
local Format = require(UI.Format)
local Icons = require(UI.Icons)
local Selection = require(UI.Selection)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Plot = {}

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
			Size = UDim2.new(1, -230, 0, 20),
			Position = UDim2.fromOffset(52, 8),
			Parent = frame,
		})
		local sub = Widgets.label({
			Name = "Sub",
			TextSize = 13,
			TextColor3 = Theme.Muted,
			Size = UDim2.new(1, -230, 0, 18),
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
		local sell = Widgets.confirmButton(
			{
				Name = "Sell",
				Text = "Sell",
				TextSize = 13,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(104, 36),
			},
			Theme.Bad,
			"Sure?",
			function()
				ctx.send("Sell", id)
			end
		)
		sell.instance.Parent = frame
		return { instance = frame, swatch = swatch, name = name, sub = sub, fav = fav, sell = sell }
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
		if view.stolenBy ~= nil then
			row.instance.BackgroundColor3 = Color3.fromRGB(120, 40, 55)
			row.sub.Text = `🚨 {ctx.playerName(view.stolenBy)} is stealing it!`
			row.sub.TextColor3 = Theme.Warn
			row.sell.instance.Visible = false
		else
			row.instance.BackgroundColor3 = if isFav then Color3.fromRGB(78, 70, 40) else Theme.Row
			row.sub.Text = `💰 {Format.formatRate(view.income)}`
			row.sub.TextColor3 = Theme.Muted
			row.sell.instance.Visible = true
		end
	end

	local rows = Widgets.keyedList(list, function(view: any)
		return view.slime.id
	end, makeRow, updateRow)

	local self = { frame = panel.frame, close = panel.close }

	function self.update(state: any)
		favoriteId = state.favoriteId
		local count = #state.slimes
		header.Text = `🟢 {count}/{state.padsUnlocked} pads · 💰 {Format.formatRate(state.incomePerSec)}`
		empty.Visible = count == 0
		rows.sync(Selection.sorted(state.slimes, favoriteId))
	end

	return self
end

return Plot
