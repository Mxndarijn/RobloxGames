--!strict
--[[
	Plot panel: the card a slime's in-world Manage prompt opens (SlimeManage): that one slime's row, `focus(id)`.
	Unfocused (Studio's PcwOpen) it lists every slime on the plot with its income and sell price.
	A focused slime that is sold, merged or gone closes the card.
	Top line: pads in use and income per second as two chips. Each row: a round
	avatar well with the slime's 3D preview (SlimePreview; the rows nearest the
	scroll window, at most SlimePreview.MAX_LIVE, the rest show a colour circle), the name in its rarity colour (Secrets in a rainbow), income
	in gold, the favourite's perk chip, a star toggle and, under the name line, Sell.
	Buttons: Sell(slimeId) (hold to confirm), Favorite(slimeId) / Favorite(nil).
	Rows being stolen turn red and show the thief. A Mystery Egg row shows its hatch time instead of income, no
	star and no 3D preview; when the egg is ready, a Hatch button (HatchEgg(slimeId), hold to confirm) sits left
	of Sell.
]]

local UI = script.Parent.Parent
local Format = require(UI.Format)
local Icons = require(UI.Icons)
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
	hatchW = 96,
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
	local focusId: string? = nil -- the one slime the card shows; nil = the whole plot
	local lastState: any = nil
	local open = false
	local petPerk: any = nil -- State.petPerk: the favourite's passive, shown as a chip on its row
	local latestViews: { [string]: any } = {}

	local previewBuilders: SlimePreview.Builders = { species = ctx.buildSpecies, slime = ctx.buildSlime }

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
		-- A Mystery Egg row: Hatch, left of Sell, while the egg is ready (contract/mystery-egg.md).
		local hatch = Widgets.holdButton(
			{
				Name = "Hatch",
				Text = "Hatch!",
				TextSize = R.labelSize,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -(R.pad + R.sellW + R.buttonGap), 0, R.buttonY),
				Size = UDim2.fromOffset(R.hatchW, R.buttonH),
				Visible = false,
			},
			Theme.Good,
			function()
				ctx.send("HatchEgg", id)
			end,
			ctx.Config.HOLD_CONFIRM_SECONDS
		)
		hatch.instance.Parent = frame
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
			hatch = hatch,
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
		local isEgg = slime.egg ~= nil
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
		row.fav.instance.Visible = not isEgg
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
			row.hatch.instance.Visible = false
		elseif isEgg then
			local hatchAt = slime.egg.hatchAt
			local left = if hatchAt then hatchAt - ctx.serverNow() else nil
			local ready = left ~= nil and left <= 0
			row.instance.BackgroundColor3 = if ready then Theme.Row:Lerp(Theme.Good, R.favTint) else Theme.Row
			row.sub.Text = if ready
				then "🥚 Ready to hatch!"
				elseif left then `🥚 Hatches in {math.max(1, math.ceil(left / 60))} min`
				else "🥚 Incubating"
			row.sub.Font = Theme.FontBody
			row.sub.TextColor3 = if ready then Theme.Good else Theme.Muted
			row.sell.instance.Visible = true
			row.hatch.instance.Visible = ready
		else
			row.hatch.instance.Visible = false
			row.instance.BackgroundColor3 = if isFav then Theme.Row:Lerp(Theme.Gold, R.favTint) else Theme.Row
			row.sub.Text = Format.formatRate(view.income)
			row.sub.Font = Theme.FontBody
			row.sub.TextColor3 = Theme.Gold
			row.sell.instance.Visible = true
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
			if row.slime.egg then
				continue -- an egg keeps its colour circle: a slime preview would give away nothing true
			end
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

	function self.setOpen(isOpen: boolean)
		open = isOpen
		if not isOpen then
			focusId = nil
			panel.title.Text = "My Plot"
		end
		refreshPreviews()
	end

	-- Shows only slime `id` (nil = every slime) and redraws from the last State.
	function self.focus(id: string?)
		focusId = id
		panel.title.Text = if id then "My Slime" else "My Plot"
		if lastState then
			self.update(lastState)
		end
	end

	function self.update(state: any)
		lastState = state
		favoriteId = state.favoriteId
		petPerk = state.petPerk
		latestViews = {}
		for _, view in state.slimes do
			latestViews[view.slime.id] = view
		end
		local count = #state.slimes
		padsChip.Text = `🟢 {count}/{state.padsUnlocked} pads`
		incomeChip.Text = Format.formatRate(state.incomePerSec)
		local focused = focusId and latestViews[focusId]
		if focusId and not focused then
			focusId = nil
			panel.title.Text = "My Plot"
			if open then
				panel.frame.Visible = false -- the slime left the plot: nothing left to manage here
			end
		end
		empty.Visible = count == 0
		rows.sync(if focused then { focused } else Selection.sorted(state.slimes, favoriteId))
		refreshPreviews()
	end

	return self
end

return Plot
