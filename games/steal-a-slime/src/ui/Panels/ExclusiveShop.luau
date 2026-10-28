--!strict
--[[
	Exclusive shop (contract/exclusive-shop.md §8; the approved mockup docs/exclusive-shop-ui-mockup.html,
	direction A with B's stage). Opens from the carousel's ShopPrompt (the server sets OpenShop = "ExclusiveShop";
	on Featured), from the Skins menu's "Exclusive shop" button (on that seat) and from the Item shop's Luck Potion
	"Details". Not in the nav.

	Tabs on top (Featured, Clouds, Perks, Boosts: Config.EXCLUSIVE_SHOP.tabs), a grid of cards under them (the
	item's icon, its name and a chip: the Robux price, Owned or Equipped) and the selected card's pane on the right:
	the big icon on the carousel's stage, the name, one line on what it does, the price and one button. On a narrow
	body (a phone held upright) the pane is a bottom sheet that slides up when a card is tapped; its X or another
	tab closes it. ExclusiveShopView decides every text and state; this module only lays them out.

	Buy hands the item's Purchase to ctx.purchase (the PurchasePrompt adapter): Roblox's own prompt is the confirm step,
	and the button turns into a "Waiting for Roblox" well until the prompt closes. The panel never grants: once
	State.exclusiveShop says the seat is owned, the pane shows "Bought" with Equip (Request EquipPetSeat). An item
	without a Roblox id yet shows its price and a disabled "Not on sale yet". The server Luck Potion (Boosts) shows
	only where paid random items are allowed and has a "Details" button with its effect and the fountain odds
	without and with it. Without State.exclusiveShop (FEATURES.ExclusiveShop off) the card is one closed line.
]]

local UI = script.Parent.Parent
local ExclusiveShopView = require(UI.ExclusiveShopView)
local ItemIconView = require(UI.ItemIconView)
local ItemIcons = require(UI.ItemIcons)
local Layout = require(UI.Layout)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local KIT = Widgets.KIT
local create = Widgets.create

local ExclusiveShop = {}

ExclusiveShop.STYLE = table.freeze({
	tabH = Layout.MIN_TOUCH_DESIGN,
	tabMaxW = 116,
	tabGap = 6,
	tabText = 17,
	chip = 15,
	chipH = 26,
	gap = 10,
	-- grid
	sheetBelow = 480, -- a body narrower than this shows the pane as a bottom sheet
	paneShare = 0.44, -- of the body width, beside the grid
	paneMin = 200,
	paneMax = 240,
	scrollBar = 8,
	columnsMax = 3,
	cardMin = 80,
	cardGap = 8,
	cardPad = 6,
	iconMax = 96,
	name = Layout.MIN_TEXT,
	nameH = 34, -- two lines
	tag = Layout.MIN_TEXT,
	tagH = 22,
	tagPad = 4, -- each side of a card's chip text
	selectStroke = 3,
	-- pane
	pad = 10,
	stageMin = 110,
	stageMax = 150,
	stageShare = 0.62, -- stage height per pane width
	pole = 10,
	turnShare = 0.76, -- turntable width per stage width
	turnH = 0.22, -- turntable height per stage height
	medalRing = 4,
	title = 20,
	text = Layout.MIN_TEXT,
	price = 18,
	priceH = 24,
	button = Layout.MIN_TOUCH_DESIGN,
	buttonText = 17,
	boughtText = 22,
	oddsPad = 8,
	oddsRadius = 14,
	oddsRowH = 18,
	sheetShare = 0.72, -- sheet height per body height under the tabs
	sheetMin = 240,
	sheetX = Layout.MIN_TOUCH_DESIGN,
})

local STYLE = ExclusiveShop.STYLE

-- How many card columns fit `inner` px of grid and how wide each card is (pure; tests).
function ExclusiveShop.grid(inner: number): (number, number)
	local columns =
		math.clamp(math.floor((inner + STYLE.cardGap) / (STYLE.cardMin + STYLE.cardGap)), 1, STYLE.columnsMax)
	return columns, math.floor((inner - STYLE.cardGap * (columns - 1)) / columns)
end

-- A card's icon size and height for a card `cardW` wide (pure; tests).
function ExclusiveShop.card(cardW: number): (number, number)
	local icon = math.min(cardW - STYLE.cardPad * 2, STYLE.iconMax)
	return icon, STYLE.cardPad + icon + 4 + STYLE.nameH + 4 + STYLE.tagH + STYLE.cardPad + 2
end

-- True when a body `bodyW` wide shows the pane as a bottom sheet.
function ExclusiveShop.sheetMode(bodyW: number): boolean
	return bodyW < STYLE.sheetBelow
end

function ExclusiveShop.new(parent: Instance, ctx: any)
	local Config = ctx.Config
	local panel = Widgets.panel(parent, "ExclusiveShopPanel", "Exclusive shop", "🎠")
	local c = Layout.PANEL_CHROME
	local icons = ItemIcons.of(ctx);
	(panel.icon.Parent :: Frame).BackgroundColor3 = Theme.Gold

	local summary = Widgets.chip({
		Name = "Summary",
		TextSize = STYLE.chip,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(c.close + c.closeInset * 2), 0, c.closeInset + c.close // 2),
		Size = UDim2.fromOffset(0, STYLE.chipH),
		Visible = false,
		ZIndex = 2,
		Parent = panel.frame,
	}, Theme.Text)

	-- The body hangs off `content`, which joins the card the first time it opens with a State (a menu nobody
	-- opened costs only its chrome). As tall as the full body, so this list menu fills the window.
	local fullH = Layout.menuHeight("ExclusiveShop") - c.header - c.pad
	local content = create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(Layout.MENU_WIDTH, fullH),
	})
	local function attach()
		if content.Parent == nil then
			content.Parent = panel.body
		end
	end

	local empty = Widgets.label({
		Name = "Empty",
		Text = ExclusiveShopView.EMPTY,
		TextColor3 = Theme.Muted,
		TextSize = Layout.MIN_TEXT,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.new(1, 0, 0, 40),
		Visible = false,
		Parent = content,
	})
	local grid = Widgets.scroll({
		Name = "Grid",
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		ScrollBarThickness = 6,
		Parent = content,
	})
	local pane = Widgets.scroll({
		Name = "Pane",
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Row,
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		ScrollBarThickness = 4,
		Parent = content,
	})
	Widgets.corner(KIT.rowRadius).Parent = pane
	local paneStroke = Widgets.stroke(Theme.Ink, KIT.rowStroke)
	paneStroke.Parent = pane

	local open = false
	local latest: any = nil
	local tab = "Featured"
	local selected: string? = nil
	local sheetOpen = false
	local detailsOpen = false
	local waiting: string? = nil -- the card whose Roblox prompt is open
	local bought: { [string]: boolean } = {} -- cards bought while this client watched
	local ownedBefore: { [string]: boolean }? = nil
	local target: string? = nil -- show(): the card the next open lands on
	local targetDetails = false -- show(): with its Details open
	local bodyW, bodyH = Layout.MENU_WIDTH - c.pad * 2, fullH
	local repaint: () -> ()

	---------------------------------------------------------------- tabs
	local tabButtons: { [string]: Widgets.Button } = {}
	for _, key in Config.EXCLUSIVE_SHOP.tabs do
		local button = Widgets.button(
			{
				Name = `Tab_{key}`,
				Text = key,
				TextSize = STYLE.tabText,
				Size = UDim2.fromOffset(STYLE.tabMaxW, STYLE.tabH),
				Visible = false,
			},
			Theme.Info,
			function()
				tab = key
				sheetOpen = false
				detailsOpen = false
				repaint()
			end
		)
		button.instance.Parent = content
		tabButtons[key] = button
	end

	---------------------------------------------------------------- geometry
	local function wide(): boolean
		return not ExclusiveShop.sheetMode(bodyW)
	end
	local function paneWidth(): number
		return if wide() then math.clamp(math.floor(bodyW * STYLE.paneShare), STYLE.paneMin, STYLE.paneMax) else bodyW
	end
	local function gridWidth(): number
		return if wide() then bodyW - paneWidth() - STYLE.gap else bodyW
	end
	local function cardWidth(): (number, number)
		return ExclusiveShop.grid(gridWidth() - STYLE.scrollBar)
	end

	local sheetClose: TextButton

	local function placeBody()
		local tabs = Config.EXCLUSIVE_SHOP.tabs
		local n = #tabs
		local tabW = math.min(STYLE.tabMaxW, math.floor((bodyW - STYLE.tabGap * (n - 1)) / n))
		for i, key in tabs do
			local b = tabButtons[key].instance
			b.Position = UDim2.fromOffset((i - 1) * (tabW + STYLE.tabGap), 0)
			b.Size = UDim2.fromOffset(tabW, STYLE.tabH)
		end
		local top = STYLE.tabH + STYLE.gap
		local h = math.max(bodyH - top, 0)
		empty.Position = UDim2.fromOffset(0, top)
		empty.Size = UDim2.fromOffset(bodyW, 40)
		grid.Position = UDim2.fromOffset(0, top)
		grid.Size = UDim2.fromOffset(gridWidth(), h)
		if wide() then
			pane.Position = UDim2.fromOffset(gridWidth() + STYLE.gap, top)
			pane.Size = UDim2.fromOffset(paneWidth(), h)
			paneStroke.Thickness = KIT.rowStroke
		else
			local sheetH = math.min(h, math.max(STYLE.sheetMin, math.floor(h * STYLE.sheetShare)))
			pane.Position = UDim2.fromOffset(0, top + h - sheetH)
			pane.Size = UDim2.fromOffset(bodyW, sheetH)
			paneStroke.Thickness = KIT.stroke
			sheetClose.Position = UDim2.fromOffset(bodyW - STYLE.sheetX - 6, top + h - sheetH + 6)
		end
		sheetClose.Size = UDim2.fromOffset(STYLE.sheetX, STYLE.sheetX)
	end

	---------------------------------------------------------------- cards
	local function makeCard(card: ExclusiveShopView.Card): any
		local frame = create("TextButton", {
			Name = card.key,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Row,
			BorderSizePixel = 0,
		}, { Widgets.corner(KIT.rowRadius) :: Instance }) :: TextButton
		local stroke = Widgets.stroke(Theme.Ink, KIT.rowStroke)
		stroke.Parent = frame
		local well = create("Frame", {
			Name = "IconWell",
			BackgroundColor3 = Theme.BgLight,
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = frame,
		}, { Widgets.corner(KIT.radius) :: Instance, Widgets.stroke(Theme.Ink, KIT.rowStroke) })
		local icon = ItemIconView.new({ Name = "CardIcon", Id = card.icon, Size = STYLE.iconMax, Parent = well }, icons)
		local name = Widgets.label({
			Name = "CardName",
			Font = Theme.Font,
			TextSize = STYLE.name,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			Parent = frame,
		})
		local tag = Widgets.chip({
			Name = "Tag",
			TextSize = STYLE.tag,
			AutomaticSize = Enum.AutomaticSize.None,
			TextTruncate = Enum.TextTruncate.AtEnd,
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = frame,
		})
		local tagPad = tag:FindFirstChildOfClass("UIPadding") :: UIPadding
		tagPad.PaddingLeft = UDim.new(0, STYLE.tagPad)
		tagPad.PaddingRight = UDim.new(0, STYLE.tagPad)
		frame.Activated:Connect(function()
			local key = frame:GetAttribute("Key")
			if type(key) == "string" then
				if selected ~= key then
					detailsOpen = false
				end
				selected = key
				sheetOpen = true
				repaint()
			end
		end)
		return { instance = frame, stroke = stroke, well = well, icon = icon, name = name, tag = tag }
	end

	local function updateCard(r: any, card: ExclusiveShopView.Card, index: number)
		local columns, cardW = cardWidth()
		local iconSize, cardH = ExclusiveShop.card(cardW)
		local col, row = (index - 1) % columns, (index - 1) // columns
		local on = card.key == selected and (wide() or sheetOpen)
		r.instance.Position = UDim2.fromOffset(col * (cardW + STYLE.cardGap), row * (cardH + STYLE.cardGap) + 2)
		r.instance.Size = UDim2.fromOffset(cardW, cardH)
		r.instance:SetAttribute("Key", card.key)
		r.instance:SetAttribute("State", card.state)
		r.instance:SetAttribute("Selected", on)
		r.instance.BackgroundColor3 = if on then Theme.BgLight else Theme.Row
		r.stroke.Color = if on or card.state == "equipped" then Theme.Good else Theme.Ink
		r.stroke.Thickness = if on then STYLE.selectStroke else KIT.rowStroke
		r.well.Position = UDim2.new(0.5, 0, 0, STYLE.cardPad)
		r.well.Size = UDim2.fromOffset(iconSize, iconSize)
		r.icon.instance.Size = UDim2.fromOffset(iconSize, iconSize)
		if r.instance:GetAttribute("Icon") ~= card.icon then
			r.instance:SetAttribute("Icon", card.icon)
			r.icon.set(card.icon)
		end
		r.icon.setActive(open)
		local y = STYLE.cardPad + iconSize + 4
		r.name.Text = card.title
		r.name.Position = UDim2.fromOffset(4, y)
		r.name.Size = UDim2.fromOffset(cardW - 8, STYLE.nameH)
		y += STYLE.nameH + 4
		r.tag.Text = card.tag
		r.tag.Position = UDim2.new(0.5, 0, 0, y)
		r.tag.Size = UDim2.fromOffset(cardW - 12, STYLE.tagH)
		r.tag.TextColor3 = if card.state == "equipped"
			then Theme.Good
			elseif card.state == "owned" or card.state == "info" then Theme.Muted
			else Theme.Text
	end

	local cards = Widgets.keyedList(grid, function(card: ExclusiveShopView.Card)
		return card.key
	end, makeCard, updateCard)

	---------------------------------------------------------------- pane
	local stage = create("Frame", {
		Name = "Stage",
		BackgroundColor3 = Theme.Plum,
		ClipsDescendants = true,
		Parent = pane,
	}, { Widgets.corner(KIT.rowRadius) :: Instance, Widgets.stroke(Theme.Ink, KIT.rowStroke) })
	local pole = create("Frame", {
		Name = "Pole",
		BackgroundColor3 = Theme.Gold,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = stage,
	}, { Widgets.stroke(Theme.Ink, KIT.rowStroke) })
	local turntable = create("Frame", {
		Name = "Turntable",
		BackgroundColor3 = Theme.Butter,
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = stage,
	}, { Widgets.pill() :: Instance, Widgets.stroke(Theme.Ink, KIT.stroke) })
	local medal = create("Frame", {
		Name = "Medal",
		BackgroundColor3 = Theme.BgLight,
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = stage,
	}, { Widgets.pill() :: Instance, Widgets.stroke(Theme.Gold, STYLE.medalRing) })
	local bigIcon = ItemIconView.new({
		Name = "BigIcon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = STYLE.stageMax,
		Parent = medal,
	}, icons)

	local function paneLabel(name: string, size: number, color: Color3, font: any): TextLabel
		return Widgets.label({
			Name = name,
			[Widgets.fontKey(font)] = font,
			TextSize = size,
			TextColor3 = color,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = pane,
		})
	end
	local boughtTitle = paneLabel("BoughtTitle", STYLE.boughtText, Theme.Good, Theme.Font)
	boughtTitle.Text = ExclusiveShopView.BOUGHT
	local exclusiveTag = Widgets.chip({
		Name = "Exclusive",
		Text = ExclusiveShopView.EXCLUSIVE,
		TextSize = STYLE.tag,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(0, STYLE.tagH),
		Parent = pane,
	}, Theme.Gold)
	local paneTitle = paneLabel("PaneTitle", STYLE.title, Theme.Text, Theme.Font)
	local paneText = paneLabel("PaneText", STYLE.text, Theme.Muted, Theme.FontBody)
	local price = paneLabel("Price", STYLE.price, Theme.Text, Theme.Font)

	local detailsButton = Widgets.button(
		{
			Name = "Details",
			Text = ExclusiveShopView.DETAILS,
			TextSize = STYLE.buttonText,
			Size = UDim2.fromOffset(0, STYLE.button),
		},
		Theme.Info,
		function()
			detailsOpen = not detailsOpen
			repaint()
		end
	)
	detailsButton.instance.Parent = pane

	-- The potion's effect and odds, built on first Details.
	local odds: Frame? = nil
	local function oddsBox(rows: { ExclusiveShopView.OddsRow }, effect: { string }): Frame
		if odds then
			return odds
		end
		local box = create("Frame", {
			Name = "Odds",
			BackgroundColor3 = Theme.Ink,
			BackgroundTransparency = 0.45,
			Parent = pane,
		}, { Widgets.corner(STYLE.oddsRadius) :: Instance })
		local function cell(name: string, text: string, color: Color3, align: Enum.TextXAlignment): TextLabel
			return Widgets.label({
				Name = name,
				Text = text,
				Font = Theme.Font,
				TextSize = STYLE.text,
				TextColor3 = color,
				TextXAlignment = align,
				Parent = box,
			})
		end
		for i, line in effect do
			cell(`Effect{i}`, line, Theme.Text, Enum.TextXAlignment.Left)
		end
		cell("HeadName", "Rarity", Theme.Muted, Enum.TextXAlignment.Left)
		cell("HeadBase", "Now", Theme.Muted, Enum.TextXAlignment.Right)
		cell("HeadBoost", "Potion", Theme.Good, Enum.TextXAlignment.Right)
		for i, row in rows do
			local rgb = Config.RARITIES[row.tier] and Config.RARITIES[row.tier].color
			cell(`Name{i}`, row.name, Widgets.color3(rgb), Enum.TextXAlignment.Left)
			cell(`Base{i}`, row.base, Theme.Text, Enum.TextXAlignment.Right)
			cell(`Boost{i}`, row.boosted, Theme.Good, Enum.TextXAlignment.Right)
		end
		local note = cell("Note", ExclusiveShopView.ODDS_NOTE, Theme.Muted, Enum.TextXAlignment.Left)
		note.FontFace = Theme.FontBody
		note.TextWrapped = true
		note.TextTruncate = Enum.TextTruncate.None
		note.TextYAlignment = Enum.TextYAlignment.Top
		odds = box
		return box
	end

	-- Lays the odds box out `inner` px wide; returns its height.
	local function placeOdds(box: Frame, rows: number, effects: number, inner: number): number
		local w = inner - STYLE.oddsPad * 2
		local y = STYLE.oddsPad
		for i = 1, effects do
			local l = box:FindFirstChild(`Effect{i}`) :: TextLabel
			l.Position = UDim2.fromOffset(STYLE.oddsPad, y)
			l.Size = UDim2.fromOffset(w, STYLE.oddsRowH)
			y += STYLE.oddsRowH + 2
		end
		y += 4
		local numW = math.floor(w * 0.28)
		local function row(prefix: { string }, at: number)
			local n = box:FindFirstChild(prefix[1]) :: TextLabel
			local b = box:FindFirstChild(prefix[2]) :: TextLabel
			local p = box:FindFirstChild(prefix[3]) :: TextLabel
			n.Position = UDim2.fromOffset(STYLE.oddsPad, at)
			n.Size = UDim2.fromOffset(w - numW * 2, STYLE.oddsRowH)
			b.Position = UDim2.fromOffset(STYLE.oddsPad + w - numW * 2, at)
			b.Size = UDim2.fromOffset(numW, STYLE.oddsRowH)
			p.Position = UDim2.fromOffset(STYLE.oddsPad + w - numW, at)
			p.Size = UDim2.fromOffset(numW, STYLE.oddsRowH)
		end
		row({ "HeadName", "HeadBase", "HeadBoost" }, y)
		y += STYLE.oddsRowH + 2
		for i = 1, rows do
			row({ `Name{i}`, `Base{i}`, `Boost{i}` }, y)
			y += STYLE.oddsRowH + 2
		end
		local note = box:FindFirstChild("Note") :: TextLabel
		local noteH = math.ceil(Layout.wrappedHeight(ExclusiveShopView.ODDS_NOTE, STYLE.text, w))
		note.Position = UDim2.fromOffset(STYLE.oddsPad, y + 4)
		note.Size = UDim2.fromOffset(w, noteH)
		return y + 4 + noteH + STYLE.oddsPad
	end

	local function buy(detail: ExclusiveShopView.Detail)
		local p = detail.action.purchase
		if p and ctx.purchase and ctx.purchase.prompt(p) then
			waiting = detail.key
			repaint()
		end
	end

	local current: ExclusiveShopView.Detail? = nil
	local buyButton = Widgets.button(
		{
			Name = "Buy",
			TextSize = STYLE.buttonText,
			Size = UDim2.fromOffset(0, STYLE.button),
		},
		Theme.Accent,
		function()
			if current and current.action.kind == "buy" then
				buy(current)
			end
		end
	)
	buyButton.instance.Parent = pane
	local equipButton = Widgets.button(
		{
			Name = "Equip",
			Text = ExclusiveShopView.EQUIP,
			TextSize = STYLE.buttonText,
			Size = UDim2.fromOffset(0, STYLE.button),
		},
		Theme.Accent,
		function()
			if current and current.kind == "seat" and ctx.request then
				ctx.request("EquipPetSeat", function() end, current.id)
			end
		end
	)
	equipButton.instance.Parent = pane
	local well = Widgets.status({
		Name = "Well",
		TextSize = STYLE.buttonText,
		Size = UDim2.fromOffset(0, STYLE.button),
		Parent = pane,
	})

	sheetClose = create("TextButton", {
		Name = "SheetClose",
		Text = "X",
		Font = Theme.Font,
		TextSize = 22,
		TextColor3 = Theme.Text,
		TextStrokeColor3 = Theme.Ink,
		TextStrokeTransparency = 0,
		BackgroundColor3 = Theme.Bad,
		AutoButtonColor = true,
		Visible = false,
		Parent = content,
	}, { Widgets.pill() :: Instance, Widgets.stroke(Theme.Ink, KIT.stroke) }) :: TextButton
	Widgets.shade(sheetClose)
	sheetClose.Activated:Connect(function()
		sheetOpen = false
		repaint()
	end)

	local function paintPane(detail: ExclusiveShopView.Detail?)
		current = detail
		local shown = detail ~= nil and (wide() or sheetOpen)
		pane.Visible = shown
		sheetClose.Visible = shown and not wide()
		if detail == nil or not shown then
			return
		end
		local w = pane.Size.X.Offset
		local inner = math.max(w - STYLE.pad * 2, 1)
		-- the sheet's X sits over the pane's top-right corner: the stage stops short of it
		local stageW = if wide() then inner else math.max(inner - STYLE.sheetX - 4, 1)
		local y = STYLE.pad
		local stageH = math.clamp(math.floor(inner * STYLE.stageShare), STYLE.stageMin, STYLE.stageMax)
		stage.Position = UDim2.fromOffset(STYLE.pad, y)
		stage.Size = UDim2.fromOffset(stageW, stageH)
		local turnH = math.floor(stageH * STYLE.turnH)
		turntable.Size = UDim2.fromOffset(math.floor(stageW * STYLE.turnShare), turnH)
		turntable.Position = UDim2.new(0.5, 0, 0, stageH - turnH - 6)
		local medalSize = stageH - turnH // 2 - 30
		local medalY = math.max(stageH - turnH - 6 - medalSize + turnH // 2, 14)
		medal.Size = UDim2.fromOffset(medalSize, medalSize)
		medal.Position = UDim2.new(0.5, 0, 0, medalY)
		pole.Size = UDim2.fromOffset(STYLE.pole, medalY)
		pole.Position = UDim2.fromScale(0.5, 0)
		local iconSize = medalSize - STYLE.medalRing * 2 - 6
		bigIcon.instance.Size = UDim2.fromOffset(iconSize, iconSize)
		if medal:GetAttribute("Icon") ~= detail.icon then
			medal:SetAttribute("Icon", detail.icon)
			bigIcon.set(detail.icon)
		end
		bigIcon.setActive(open)
		y += stageH + 8

		local function put(label: TextLabel, size: number, text: string, bold: boolean, gapAfter: number)
			label.Text = text
			label.Visible = text ~= ""
			if text ~= "" then
				local h = math.ceil(Layout.wrappedHeight(text, size, inner, bold))
				label.Position = UDim2.fromOffset(STYLE.pad, y)
				label.Size = UDim2.fromOffset(inner, h)
				y += h + gapAfter
			end
		end
		local isBought = bought[detail.key] == true and (detail.state == "owned" or detail.state == "equipped")
		boughtTitle.Visible = isBought
		if isBought then
			put(boughtTitle, STYLE.boughtText, ExclusiveShopView.BOUGHT, true, 2)
		end
		exclusiveTag.Visible = detail.exclusive
		if detail.exclusive then
			exclusiveTag.Position = UDim2.new(0.5, 0, 0, y)
			y += STYLE.tagH + 6
		end
		put(paneTitle, STYLE.title, detail.title, true, 4)
		local text = if isBought and detail.kind == "seat" then ExclusiveShopView.BOUGHT_SEAT else detail.text
		put(paneText, STYLE.text, text, false, 6)
		local showPrice = detail.priceText ~= "" and (detail.state == "buy" or detail.state == "offsale")
		put(price, STYLE.price, if showPrice then detail.priceText else "", true, 6)

		local hasOdds = detail.odds ~= nil and detail.effect ~= nil
		detailsButton.instance.Visible = hasOdds
		if odds then
			odds.Visible = false
		end
		if hasOdds then
			detailsButton.setText(if detailsOpen then ExclusiveShopView.HIDE_DETAILS else ExclusiveShopView.DETAILS)
			detailsButton.instance.Position = UDim2.fromOffset(STYLE.pad, y)
			detailsButton.instance.Size = UDim2.fromOffset(inner, STYLE.button)
			y += STYLE.button + 8
			if detailsOpen then
				local rows, effect = detail.odds :: { ExclusiveShopView.OddsRow }, detail.effect :: { string }
				local box = oddsBox(rows, effect)
				box.Visible = true
				local h = placeOdds(box, #rows, #effect, inner)
				box.Position = UDim2.fromOffset(STYLE.pad, y)
				box.Size = UDim2.fromOffset(inner, h)
				y += h + 8
			end
		end

		local action = detail.action
		local isWaiting = waiting == detail.key and action.kind == "buy"
		buyButton.instance.Visible = not isWaiting and (action.kind == "buy" or action.kind == "offsale")
		buyButton.setEnabled(action.kind == "buy" and ctx.purchase ~= nil)
		buyButton.setText(action.text)
		equipButton.instance.Visible = action.kind == "equip"
		well.Visible = isWaiting or action.kind == "well"
		well.Text = if isWaiting then ExclusiveShopView.WAITING else action.text
		well.TextColor3 = if detail.state == "equipped" then Theme.Good else Theme.Muted
		for _, inst in { buyButton.instance :: GuiObject, equipButton.instance, well } do
			inst.Position = UDim2.fromOffset(STYLE.pad, y)
			inst.Size = UDim2.fromOffset(inner, STYLE.button)
		end
		y += STYLE.button + STYLE.pad
		pane.CanvasSize = UDim2.fromOffset(0, y)
	end

	---------------------------------------------------------------- state
	-- Every card key this player owns, to spot the ones bought while the shop watches.
	local function ownedKeys(shop: any): { [string]: boolean }
		local out: { [string]: boolean } = {}
		for id, own in (if type(shop.owned) == "table" then shop.owned else {}) :: { [string]: any } do
			if own == true then
				out[`seat:{id}`] = true
			end
		end
		for key, own in (if type(shop.passes) == "table" then shop.passes else {}) :: { [string]: any } do
			if own == true then
				out[`pass:{key}`] = true
			end
		end
		if shop.starterClaimed == true then
			out["product:StarterBundle"] = true
		end
		return out
	end

	local function watchBought(state: any)
		local shop = if type(state) == "table" then state.exclusiveShop else nil
		if type(shop) ~= "table" then
			return
		end
		local now = ownedKeys(shop)
		local before = ownedBefore
		ownedBefore = now
		if before == nil then
			return
		end
		for key in now do
			if not before[key] then
				bought[key] = true
				if waiting == key then
					waiting = nil
				end
			end
		end
		-- The bundle leaves Featured once claimed: show the seat it gave, bought, on Clouds.
		if now["product:StarterBundle"] and not before["product:StarterBundle"] then
			if waiting == "product:StarterBundle" then
				waiting = nil
			end
			if selected == "product:StarterBundle" then
				local seats = Config.EXCLUSIVE_SHOP.products.StarterBundle.grant.seats
				if seats and seats[1] then
					tab = "Clouds"
					selected = `seat:{seats[1]}`
					bought[selected] = true
				end
			end
		end
	end

	function repaint()
		local tabs = ExclusiveShopView.tabs(latest, Config)
		local on = #tabs > 0
		for key, button in tabButtons do
			button.instance.Visible = on
			button.setColor(if key == tab then Theme.Accent else Theme.Info)
			button.instance:SetAttribute("Selected", key == tab)
		end
		if not on then
			empty.Text = ExclusiveShopView.EMPTY
			empty.Visible = true
			empty.Position = UDim2.fromOffset(0, 0)
			grid.Visible = false
			pane.Visible = false
			sheetClose.Visible = false
			summary.Visible = false
			if open then
				attach()
			end
			return
		end
		empty.Position = UDim2.fromOffset(0, STYLE.tabH + STYLE.gap)
		local list = ExclusiveShopView.cards(tab, latest, Config)
		selected = ExclusiveShopView.firstSelected(list, selected)
		summary.Visible = tab == "Clouds"
		summary.Text = ExclusiveShopView.ownedSummary(latest, Config)
		empty.Text = ExclusiveShopView.EMPTY_TAB
		empty.Visible = #list == 0
		grid.Visible = #list > 0
		if not open then
			return
		end
		attach()
		cards.sync(list)
		local columns, cardW = cardWidth()
		local _, cardH = ExclusiveShop.card(cardW)
		local lines = math.ceil(#list / columns)
		grid.CanvasSize = UDim2.fromOffset(0, lines * cardH + math.max(lines - 1, 0) * STYLE.cardGap + 6)
		paintPane(if selected then ExclusiveShopView.detail(selected, latest, Config) else nil)
	end

	if ctx.purchase and ctx.purchase.onClosed then
		ctx.purchase.onClosed(function()
			if waiting then
				waiting = nil
				repaint()
			end
		end)
	end

	local self = { frame = panel.frame, close = panel.close }

	-- The card the next open lands on ("seat:storm_cloud", "product:ServerLuckPotion"), on its tab with the
	-- pane (or sheet) up, `withDetails` with its odds open; nil = Featured. Call before setOpen.
	function self.show(key: string?, withDetails: boolean?)
		target = key
		targetDetails = withDetails == true
	end

	function self.setOpen(isOpen: boolean)
		if isOpen and not open then
			local key = target
			target = nil
			tab = if key then ExclusiveShopView.tabOf(key) else "Featured"
			selected = key
			sheetOpen = key ~= nil
			detailsOpen = key ~= nil and targetDetails
			targetDetails = false
		end
		if not isOpen then
			waiting = nil
			if open and ctx.exclusiveShopHidden then
				ctx.exclusiveShopHidden() -- opened at the carousel: the server closes its side too
			end
		end
		open = isOpen
		for _, r in cards.rows do
			r.icon.setActive(isOpen)
		end
		bigIcon.setActive(isOpen)
		repaint()
	end

	function self.layout(r: Layout.Rect)
		local body = Layout.panelBody(r)
		bodyW, bodyH = math.floor(body.w), math.floor(body.h)
		content.Size = UDim2.fromOffset(bodyW, fullH)
		placeBody()
		repaint()
	end

	function self.update(state: any)
		watchBought(state)
		latest = state
		repaint()
	end

	-- Tests and Studio: the open tab and card, and picking them as a tap does.
	function self.tab(): string
		return tab
	end
	function self.setTab(key: string)
		tab = key
		sheetOpen = false
		detailsOpen = false
		repaint()
	end
	function self.selected(): string?
		return selected
	end
	function self.select(key: string)
		selected = key
		sheetOpen = true
		detailsOpen = false
		repaint()
	end
	function self.sheetOpen(): boolean
		return sheetOpen and not wide()
	end

	placeBody()
	return self
end

return ExclusiveShop
