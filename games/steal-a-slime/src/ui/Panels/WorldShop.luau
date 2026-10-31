--!strict
--[[
	World shop panel (CONTRACT.md §27): the card of ONE in-world shop, "Item Shop" or
	"Upgrade Shop". The server opens it at the stand's ShopPrompt (ShopEvent Open / attribute OpenShop);
	init.client calls setShop(shopId) and shows the card like every other menu (setOpen("WorldShop"), X,
	backdrop, Esc / B). What it draws comes from WorldShopLogic.view (Shared.Shops + the live State); a Buy
	hold calls Request("ShopBuy", shopId, itemId). Cash and rebirths are not repeated here: the HUD shows them.

	The Item Shop has tabs (Items / PvP / Fun, a gold dot on a tab with something to buy now); the Upgrade
	Shop has none. Section labels group the rows ("Potions and totems" carries the restock countdown). A row
	is the icon tile (a gold stock tag under it for restocking items and traps), the name, a two-line
	description, level pips (a bar past PIP_MAX levels) for leveled upgrades, and on the right
	WorldShopLogic.slot: the green hold-to-buy button, a sunken status well ("Owned" with the game's check,
	"🔒 Rebirth 12 / to unlock") or the gold MAX stamp. Thin rows (maxed, owned, not yet unlocked) take one line.
	Each PvP line is one ladder card: its title, one button per tier (owned green, locked dark, the tier on
	show gold; tapping one shows it) over the row of that tier. Fun items are a three-column grid of tiles.
	Where paid random items are allowed, the Luck Potion row carries Details and "Buy for the server · R$79"
	(ExclusiveShopView.potionQuickBuy) under it; Details opens the Exclusive shop on the potion with its odds.
]]

local UI = script.Parent.Parent
local ExclusiveShopView = require(UI.ExclusiveShopView)
local GooIcons = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("GooIcons"))
local ItemIconView = require(UI.ItemIconView)
local ItemIcons = require(UI.ItemIcons)
local Layout = require(UI.Layout)
local ShopCatalog = require(UI.ShopCatalog)
local Widgets = require(UI.Widgets)
local WorldShopLogic = require(UI.WorldShopLogic)

local Theme = Widgets.Theme
local KIT = Widgets.KIT
local create = Widgets.create

local WorldShop = {}

-- Row geometry (design px). BADGE / BUY_W / DESC_H and the text sizes match LayoutAssert.worldShopTexts.
WorldShop.ROW = 68
WorldShop.ROW_LEVELS = 80 -- a leveled upgrade: the pips sit under the two description lines
WorldShop.ROW_THIN = 48 -- maxed, owned or not yet unlocked: name over one line
WorldShop.BADGE = 48
WorldShop.BADGE_THIN = 32
WorldShop.BUY_W = 170 -- fits "Need $987.6Qa more"; narrower than Layout.ROW_SLOT so a phone row keeps room for two lines of text
WorldShop.THIN_SLOT_H = 36 -- the status well of a thin row
WorldShop.NAME_H = 22
WorldShop.DESC_H = 34
WorldShop.DESC_THIN_H = 18
WorldShop.EDGE = 8 -- row edge to the icon and to the right slot
WorldShop.GAP = 10 -- icon to text, text to the right slot
WorldShop.PIP_MAX = 10 -- more levels than this draw a bar instead of pips
WorldShop.TAB_H = Layout.MIN_TOUCH_DESIGN
WorldShop.TAB_GAP = 6
WorldShop.TOP_GAP = 8 -- tabs to the list
WorldShop.LABEL_H = 24 -- a section label
WorldShop.STEP = Layout.MIN_TOUCH_DESIGN -- a ladder tier button (a thumb target)
WorldShop.STEP_GAP = 4
WorldShop.LADDER_HEAD = 8 + Layout.MIN_TOUCH_DESIGN -- ladder title and tier buttons over its row
WorldShop.GRID_COLS = 3
WorldShop.GRID_GAP = 6
WorldShop.TILE_NAME_H = 36 -- a tile's name: up to two lines
WorldShop.TILE_H = 8 + 48 + 4 + 36 + 4 + Layout.BUTTON + 8 -- icon, name, Buy
WorldShop.STRIP_H = Layout.BUTTON + 8 -- the server potion buttons under the Luck Potion row
-- The Robux "buy for the server" buttons inside the cash Luck Potion row.
WorldShop.SERVER_POTION = table.freeze({
	id = "LuckPotion", -- the cash row that carries them
	detailsW = 120,
})

WorldShop.SIZE = table.freeze({
	desc = Layout.MIN_TEXT,
	buy = 16,
	tab = 17,
	dot = 14,
	label = 16,
	aside = Layout.MIN_TEXT, -- the restock countdown beside its label
	ladderTitle = 17,
	step = 16,
	tileName = 15,
	tag = Layout.MIN_TEXT, -- the gold stock tag under the icon
	tagH = 18,
	tagPad = 6,
	pipH = 6,
	pipGap = 4,
	pipInset = 7, -- pips' bottom above the row's bottom
	status = 15,
	statusSub = Layout.MIN_TEXT, -- "to unlock" under a locked well's main line
	statusPad = 10, -- each side of a status well's widest line
	stamp = Layout.MIN_TEXT,
	stampH = 24,
	stampPad = 8,
	stampRadius = 8,
})

-- Per shop: the corner icon (an emoji, or `drawn` = a GooIcons drawing in Ink) and its tile colour; the title
-- comes from WorldShopLogic.
WorldShop.ICON = table.freeze({
	ItemShop = table.freeze({ text = "🛒" }),
	UpgradeShop = table.freeze({ drawn = "upArrow", tile = "Gold" }),
})

local ICON_DEPS = { Instance = Instance, UDim = UDim, UDim2 = UDim2, Vector2 = Vector2 }

local SIZE = WorldShop.SIZE

-- Width (design px) of a status well: at least the Buy button, wider when its text needs it ("Rebirth 120").
function WorldShop.statusWidth(slot: WorldShopLogic.Slot): number
	local w = Layout.lineWidth(slot.text, SIZE.status, true)
	if slot.check then
		w += Widgets.checkRoom(SIZE.status)
	end
	if slot.sub then
		w = math.max(w, Layout.lineWidth(slot.sub, SIZE.statusSub))
	end
	return math.max(WorldShop.BUY_W, math.ceil(w) + SIZE.statusPad * 2)
end

-- The status well's text: one line, or the main line over a small body-font line.
function WorldShop.statusText(slot: WorldShopLogic.Slot): string
	if slot.sub then
		return `{slot.text}\n<font family="{Theme.FontBody.Family}" weight="bold" size="{SIZE.statusSub}">{slot.sub}</font>`
	end
	return slot.text
end

-- A small bright tag with ink text and outline (stock tag, MAX stamp), sized to its text.
function WorldShop.tag(props: { [string]: any }, size: number, height: number, pad: number, radius: number): TextLabel
	local base = {
		Font = Theme.Font,
		TextSize = size,
		TextColor3 = Theme.Ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Gold,
		Size = UDim2.fromOffset(math.ceil(Layout.lineWidth(props.Text or "", size, true)) + pad * 2, height),
	}
	for k, v in props do
		base[k] = v
	end
	local label = Widgets.label(base)
	Widgets.corner(radius).Parent = label
	Widgets.stroke(Theme.Ink, KIT.rowStroke).Parent = label
	return label
end

-- One pip per level, filled gold up to `level`, placed by scale so they lay out while the card is hidden.
local function setPips(holder: Frame, level: number, maxLevel: number)
	local n = math.max(maxLevel, 0)
	if #holder:GetChildren() ~= n then
		holder:ClearAllChildren()
		for i = 1, n do
			create("Frame", {
				Name = `Pip{i}`,
				BorderSizePixel = 0,
				BackgroundColor3 = Theme.Ink,
				Position = UDim2.new((i - 1) / n, math.round((i - 1) * SIZE.pipGap / n), 0, 0),
				Size = UDim2.new(1 / n, -math.round(SIZE.pipGap * (n - 1) / n), 1, 0),
				Parent = holder,
			}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		end
	end
	for i = 1, n do
		local pip = holder:FindFirstChild(`Pip{i}`) :: Frame?
		if pip then
			pip.BackgroundColor3 = if i <= level then Theme.Gold else Theme.Ink
			pip:SetAttribute("On", i <= level)
		end
	end
end

-- A small round gold dot (a tab with something to buy), ink-outlined.
local function newDot(parent: Instance): Frame
	return create("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -SIZE.dot // 2, 0, SIZE.dot // 2),
		Size = UDim2.fromOffset(SIZE.dot, SIZE.dot),
		BackgroundColor3 = Theme.Gold,
		BorderSizePixel = 0,
		Visible = false,
		Parent = parent,
	}, { Widgets.pill(), Widgets.stroke(Theme.Ink, KIT.rowStroke) }) :: Frame
end

-- The meter of a leveled upgrade with more levels than fit as pips: an Ink track with a gold fill.
local function newBar(parent: Instance, position: UDim2, size: UDim2): Frame
	local track = create("Frame", {
		Name = "LevelBar",
		BackgroundColor3 = Theme.Ink,
		BorderSizePixel = 0,
		Position = position,
		Size = size,
		Parent = parent,
	}, { Widgets.pill() }) :: Frame
	create("Frame", {
		Name = "Fill",
		BackgroundColor3 = Theme.Gold,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = track,
	}, { Widgets.pill() })
	return track
end

type RowOpts = { thin: boolean?, strip: boolean?, bare: boolean?, onBuy: ((WorldShopLogic.Row) -> ())? }

function WorldShop.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "WorldShopPanel", "Shop", WorldShop.ICON.ItemShop.text)
	local tile = panel.icon.Parent :: Frame
	local arrow = GooIcons.upArrow(panel.icon, ICON_DEPS, Theme.Ink, panel.icon.ZIndex)
	arrow.Visible = false

	local shopId: string? = nil
	local isOpen = false
	local tab: string? = nil -- Item Shop tab on show (nil = the first)
	local picks: { [string]: number } = {} -- ladder line -> the tier the player tapped
	local lastState: any = nil
	local restockAt = nil :: number?
	local restockLabel: TextLabel? = nil
	local serverQuick: ExclusiveShopView.QuickBuy? = nil
	local icons: { any } = {}
	local refresh: () -> ()

	local function icon(props: { [string]: any }): any
		local view = ItemIconView.new(props, ItemIcons.of(ctx))
		view.setActive(isOpen)
		table.insert(icons, view)
		return view
	end

	local list = Widgets.scrollList({ Name = "List", Size = UDim2.fromScale(1, 1), Parent = panel.body }, 6)

	-- Item Shop tabs: shared width, the one on show in Accent, a gold dot on the others with something to buy.
	local tabBar = create("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, WorldShop.TAB_H),
		Visible = false,
		Parent = panel.body,
	})
	local tabButtons: { [string]: { button: Widgets.Button, dot: Frame } } = {}
	for _, def in WorldShopLogic.TABS do
		local button = Widgets.button(
			{
				Name = `Tab_{def.id}`,
				Text = def.label,
				TextSize = SIZE.tab,
				Size = UDim2.fromOffset(0, WorldShop.TAB_H),
			},
			Theme.Info,
			function()
				if tab ~= def.id then
					tab = def.id
					list.CanvasPosition = Vector2.zero
					refresh()
				end
			end
		)
		button.instance.Parent = tabBar
		tabButtons[def.id] = { button = button, dot = newDot(button.instance) }
	end

	local function placeTabs(tabs: { WorldShopLogic.Tab }, current: string?)
		local shown = #tabs > 1
		tabBar.Visible = shown
		local top = if shown then WorldShop.TAB_H + WorldShop.TOP_GAP else 0
		list.Position = UDim2.fromOffset(0, top)
		list.Size = UDim2.new(1, 0, 1, -top)
		local k = #tabs
		local index: { [string]: number } = {}
		for i, t in tabs do
			index[t.id] = i
		end
		for id, b in tabButtons do
			local i = index[id]
			b.button.instance.Visible = shown and i ~= nil
			if i then
				local gap = WorldShop.TAB_GAP
				b.button.instance.Position = UDim2.new((i - 1) / k, math.round((i - 1) * gap / k), 0, 0)
				b.button.instance.Size = UDim2.new(1 / k, -math.round(gap * (k - 1) / k), 0, WorldShop.TAB_H)
				b.button.setColor(if id == current then Theme.Accent else Theme.Info)
				b.dot.Visible = tabs[i].dot and id ~= current
			end
		end
	end

	local textX = WorldShop.EDGE + WorldShop.BADGE + WorldShop.GAP
	local thinX = WorldShop.EDGE + WorldShop.BADGE_THIN + WorldShop.GAP

	-- One item row. `thin` = one line (maxed / owned / not yet unlocked), `strip` = the Robux server potion
	-- buttons under it, `bare` = no fill or outline (inside a ladder card).
	local function makeRow(view: WorldShopLogic.Row, opts: RowOpts): any
		local thin = opts.thin == true
		local leveled = view.maxLevel ~= nil and not thin
		local mainH = if thin then WorldShop.ROW_THIN elseif leveled then WorldShop.ROW_LEVELS else WorldShop.ROW
		local badge = if thin then WorldShop.BADGE_THIN else WorldShop.BADGE
		local x = if thin then thinX else textX
		local slotH = if thin then WorldShop.THIN_SLOT_H else Layout.BUTTON
		local function textWidth(slotW: number): UDim
			return UDim.new(1, -(x + slotW + WorldShop.EDGE + WorldShop.GAP))
		end
		local frame = Widgets.rowFrame({
			Name = view.id,
			Size = UDim2.new(1, 0, 0, mainH + (if opts.strip then WorldShop.STRIP_H else 0)),
		})
		if opts.bare then
			frame.BackgroundTransparency = 1
			local stroke = frame:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Enabled = false
			end
		end
		local itemIcon = icon({
			Name = "Icon",
			Id = view.icon,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(WorldShop.EDGE, mainH // 2),
			Size = badge,
			Parent = frame,
		})
		-- Stock tag hanging off the icon's bottom edge, drawn over the tile.
		local stock = WorldShop.tag({
			Name = "Stock",
			Text = "",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(WorldShop.EDGE + badge // 2, mainH // 2 + badge // 2),
			ZIndex = itemIcon.instance.ZIndex + 1,
			Visible = false,
			Parent = frame,
		}, SIZE.tag, SIZE.tagH, SIZE.tagPad, SIZE.tagH)
		local descH = if thin then WorldShop.DESC_THIN_H else WorldShop.DESC_H
		local nameY = if thin then (mainH - WorldShop.NAME_H - descH) // 2 else 6
		local name = Widgets.label({
			Name = "ItemName",
			Font = Theme.Font,
			TextSize = WorldShopLogic.nameSize(view.name),
			Text = view.name,
			Size = UDim2.new(textWidth(WorldShop.BUY_W), UDim.new(0, WorldShop.NAME_H)),
			Position = UDim2.fromOffset(x, nameY),
			Parent = frame,
		})
		local desc = Widgets.label({
			Name = "Description",
			FontFace = Theme.FontBody,
			TextSize = SIZE.desc,
			TextColor3 = Theme.Muted,
			TextWrapped = not thin,
			TextTruncate = Enum.TextTruncate.None,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(textWidth(WorldShop.BUY_W), UDim.new(0, descH)), -- two lines on a phone, one when thin
			Position = UDim2.fromOffset(x, nameY + WorldShop.NAME_H + (if thin then 0 else 2)),
			Parent = frame,
		})
		local meterPos = UDim2.fromOffset(x, mainH - (SIZE.pipH + SIZE.pipInset))
		local meterSize = UDim2.new(textWidth(WorldShop.BUY_W), UDim.new(0, SIZE.pipH))
		local pips: Frame? = nil
		local bar: Frame? = nil
		if leveled and (view.maxLevel :: number) > WorldShop.PIP_MAX then
			bar = newBar(frame, meterPos, meterSize)
		elseif leveled then
			pips = create("Frame", {
				Name = "Levels",
				BackgroundTransparency = 1,
				Position = meterPos,
				Size = meterSize,
				Parent = frame,
			}) :: Frame
		end
		local current = view
		local slotCentre = UDim2.new(1, -WorldShop.EDGE, 0, mainH // 2)
		local buy = Widgets.holdButton(
			{
				Name = "Buy",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = slotCentre,
				Size = UDim2.fromOffset(WorldShop.BUY_W, Layout.BUTTON),
				TextSize = SIZE.buy,
			},
			Theme.Good,
			function()
				if current.enabled then
					ctx.send("ShopBuy", table.unpack(WorldShopLogic.buyArgs(current), 1, 2))
					if opts.onBuy then
						opts.onBuy(current)
					end
				end
			end,
			ctx.Config.HOLD_CONFIRM_SECONDS
		)
		buy.instance.Parent = frame
		local status = Widgets.status({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = slotCentre,
			Size = UDim2.fromOffset(WorldShop.BUY_W, slotH),
			TextSize = SIZE.status,
			TextWrapped = false,
			RichText = true,
			Visible = false,
			Parent = frame,
		})
		local stamp = WorldShop.tag({
			Name = "MaxStamp",
			Text = "Max",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = slotCentre,
			Visible = false,
			Parent = frame,
		}, SIZE.stamp, SIZE.stampH, SIZE.stampPad, SIZE.stampRadius)
		-- The Robux "for the whole server" buttons under the cash Luck Potion.
		local stripBuy: Widgets.Button? = nil
		if opts.strip then
			local details = Widgets.button(
				{
					Name = "Details",
					Text = ExclusiveShopView.DETAILS,
					TextSize = SIZE.buy,
					Position = UDim2.fromOffset(WorldShop.EDGE, mainH),
					Size = UDim2.fromOffset(WorldShop.SERVER_POTION.detailsW, Layout.BUTTON),
				},
				Theme.Info,
				function()
					if ctx.openExclusiveShop then
						ctx.openExclusiveShop("product:ServerLuckPotion", true)
					end
				end
			)
			details.instance.Parent = frame
			local robux = Widgets.button(
				{
					Name = "ServerBuy",
					Text = "",
					TextSize = SIZE.buy,
					Position = UDim2.fromOffset(WorldShop.EDGE * 2 + WorldShop.SERVER_POTION.detailsW, mainH),
					Size = UDim2.new(1, -(WorldShop.EDGE * 3 + WorldShop.SERVER_POTION.detailsW), 0, Layout.BUTTON),
				},
				Theme.Accent,
				function()
					local q = serverQuick
					if q and q.mode == "buy" and q.purchase and ctx.purchase then
						ctx.purchase.prompt(q.purchase)
					end
				end
			)
			robux.instance.Parent = frame
			stripBuy = robux
		end
		return {
			instance = frame,
			icon = itemIcon,
			stock = stock,
			name = name,
			desc = desc,
			pips = pips,
			bar = bar,
			buy = buy,
			status = status,
			stamp = stamp,
			stripBuy = stripBuy,
			textWidth = textWidth,
			slotH = slotH,
			setView = function(v: WorldShopLogic.Row)
				current = v
			end,
		}
	end

	local function updateRow(row: any, view: WorldShopLogic.Row)
		row.setView(view)
		row.instance.Name = view.id
		row.icon.set(view.icon)
		row.name.Text = view.name
		row.name.TextSize = WorldShopLogic.nameSize(view.name)
		row.desc.Text = view.description
		row.stock.Text = view.stockText or ""
		row.stock.Size =
			UDim2.fromOffset(math.ceil(Layout.lineWidth(row.stock.Text, SIZE.tag, true)) + SIZE.tagPad * 2, SIZE.tagH)
		row.stock.Visible = view.stockText ~= nil
		if row.pips then
			setPips(row.pips, view.level or 0, view.maxLevel or 0)
		end
		if row.bar then
			local fill = row.bar:FindFirstChild("Fill") :: Frame
			local max = math.max(view.maxLevel or 1, 1)
			fill.Size = UDim2.fromScale(math.clamp((view.level or 0) / max, 0, 1), 1)
		end
		-- The one upgrade you can buy now stands out.
		if row.instance.BackgroundTransparency < 1 then
			row.instance.BackgroundColor3 = if (row.pips or row.bar)
					and view.status == "buy"
					and view.enabled
				then Theme.BgLight
				else Theme.Row
		end
		-- Icon frame: gold when maxed / owned, green when you can buy it.
		local done = view.status == "maxed" or view.status == "owned"
		row.icon.setFrame(if done then Theme.Gold elseif view.enabled then Theme.Good else nil)

		local slot = WorldShopLogic.slot(view)
		local slotW = WorldShop.BUY_W
		row.buy.instance.Visible = slot.kind == "buy"
		row.buy.setText(view.buttonText)
		row.buy.setEnabled(slot.kind == "buy" and view.enabled)
		row.stamp.Visible = slot.kind == "stamp"
		row.status.Visible = slot.kind == "status"
		if slot.kind == "status" then
			slotW = WorldShop.statusWidth(slot)
			row.status.Text = WorldShop.statusText(slot)
			row.status.TextColor3 = if slot.good then Theme.Good else Theme.Muted
			row.status.Size = UDim2.fromOffset(slotW, row.slotH)
		end
		Widgets.setStatusCheck(row.status, slot.kind == "status" and slot.check == true)
		local w = row.textWidth(slotW)
		row.name.Size = UDim2.new(w, UDim.new(0, WorldShop.NAME_H))
		row.desc.Size = UDim2.new(w, UDim.new(0, row.desc.Size.Y.Offset))
		for _, meter in { row.pips, row.bar } do
			meter.Size = UDim2.new(w, UDim.new(0, SIZE.pipH))
		end
		if row.stripBuy then
			local q = serverQuick
			row.stripBuy.setText(if q then q.text else "")
			row.stripBuy.setEnabled(q ~= nil and q.mode == "buy" and ctx.purchase ~= nil)
		end
	end

	-- Section label: the name on the left, an optional gold note on the right (the restock countdown).
	local function makeLabel(entry: WorldShopLogic.Entry): any
		local frame = create("Frame", {
			Name = entry.key,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, WorldShop.LABEL_H),
		})
		local text = Widgets.label({
			Name = "Label",
			Font = Theme.Font,
			TextSize = SIZE.label,
			TextColor3 = Theme.Accent,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			Position = UDim2.fromOffset(4, 0),
			Size = UDim2.new(1, -8, 1, 0),
			Parent = frame,
		})
		local aside = Widgets.label({
			Name = if entry.aside == "restock" then "RestockTimer" else "Aside",
			FontFace = Theme.FontBody,
			TextSize = SIZE.aside,
			TextColor3 = Theme.Gold,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -4, 0, 0),
			Size = UDim2.fromScale(0.5, 1),
			Visible = entry.aside ~= nil,
			Parent = frame,
		})
		if entry.aside == "restock" then
			restockLabel = aside
		end
		return { instance = frame, text = text }
	end

	-- A PvP line: its title and one tier button per tier, over the row of the tier on show.
	local function makeLadder(entry: WorldShopLogic.Entry): any
		local ladder = entry.ladder :: WorldShopLogic.Ladder
		local frame = Widgets.rowFrame({
			Name = `Ladder_{ladder.line}`,
			Size = UDim2.new(1, 0, 0, WorldShop.LADDER_HEAD + WorldShop.ROW),
		})
		local title = Widgets.label({
			Name = "LineTitle",
			Font = Theme.Font,
			TextSize = SIZE.ladderTitle,
			Text = ladder.title,
			Position = UDim2.fromOffset(WorldShop.EDGE + 4, WorldShop.EDGE),
			Size = UDim2.fromOffset(0, WorldShop.STEP),
			Parent = frame,
		})
		local steps = create("Frame", {
			Name = "Steps",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -WorldShop.EDGE, 0, WorldShop.EDGE),
			Size = UDim2.fromOffset(0, WorldShop.STEP),
			Parent = frame,
		})
		local line = ladder.line
		local inner = makeRow(ladder.row, {
			bare = true,
			onBuy = function()
				picks[line] = nil -- after a buy the card picks again (the next tier up)
			end,
		})
		inner.instance.Position = UDim2.fromOffset(0, WorldShop.LADDER_HEAD)
		inner.instance.Parent = frame
		return { instance = frame, title = title, steps = steps, buttons = {}, tiers = {}, inner = inner, line = line }
	end

	local STEP_COLOR = { owned = Theme.Good, open = Theme.Info, locked = Theme.Disabled }

	local function updateLadder(card: any, entry: WorldShopLogic.Entry)
		local ladder = entry.ladder :: WorldShopLogic.Ladder
		local n = #ladder.steps
		local stepsW = n * WorldShop.STEP + (n - 1) * WorldShop.STEP_GAP
		card.steps.Size = UDim2.fromOffset(stepsW, WorldShop.STEP)
		-- The title takes what the tier buttons leave.
		card.title.Size = UDim2.new(1, -(stepsW + WorldShop.EDGE * 3 + 4), 0, WorldShop.STEP)
		for i, step in ladder.steps do
			card.tiers[i] = step.tier
			local button = card.buttons[i]
			if button == nil then
				button = Widgets.button(
					{
						Name = `Step{i}`,
						Text = "",
						TextSize = SIZE.step,
						Position = UDim2.fromOffset((i - 1) * (WorldShop.STEP + WorldShop.STEP_GAP), 0),
						Size = UDim2.fromOffset(WorldShop.STEP, WorldShop.STEP),
					},
					Theme.Info,
					function()
						picks[card.line] = card.tiers[i]
						refresh()
					end
				)
				button.instance.Parent = card.steps
				card.buttons[i] = button
			end
			button.instance.Visible = true
			button.setText(if step.state == "locked" then `🔒{step.tier}` else tostring(step.tier))
			button.setColor(if step.selected then Theme.Gold else (STEP_COLOR :: any)[step.state])
			button.instance:SetAttribute("Tier", step.tier)
			button.instance:SetAttribute("State", step.state)
			button.instance:SetAttribute("Selected", step.selected)
		end
		for i = n + 1, #card.buttons do
			card.buttons[i].instance.Visible = false
		end
		updateRow(card.inner, ladder.row)
	end

	-- Fun items: tiles with the icon, the name and a price-only hold Buy or the state well.
	local function makeTile(view: WorldShopLogic.Row): any
		local frame = Widgets.rowFrame({ Name = view.id })
		local tileIcon = icon({
			Name = "Icon",
			Id = view.icon,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, WorldShop.EDGE),
			Size = WorldShop.BADGE,
			Parent = frame,
		})
		local name = Widgets.label({
			Name = "ItemName",
			Font = Theme.Font,
			TextSize = SIZE.tileName,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			Position = UDim2.fromOffset(4, WorldShop.EDGE + WorldShop.BADGE + 4),
			Size = UDim2.new(1, -8, 0, WorldShop.TILE_NAME_H),
			Parent = frame,
		})
		local current = view
		local slotPos = UDim2.new(0, WorldShop.EDGE, 1, -(WorldShop.EDGE + Layout.BUTTON))
		local slotSize = UDim2.new(1, -WorldShop.EDGE * 2, 0, Layout.BUTTON)
		local buy = Widgets.holdButton(
			{
				Name = "Buy",
				Position = slotPos,
				Size = slotSize,
				TextSize = SIZE.buy,
			},
			Theme.Good,
			function()
				if current.enabled then
					ctx.send("ShopBuy", table.unpack(WorldShopLogic.buyArgs(current), 1, 2))
				end
			end,
			ctx.Config.HOLD_CONFIRM_SECONDS
		)
		buy.instance.Parent = frame
		local status = Widgets.status({
			Position = slotPos,
			Size = slotSize,
			TextSize = SIZE.status,
			TextWrapped = false,
			RichText = true,
			Visible = false,
			Parent = frame,
		})
		return {
			instance = frame,
			icon = tileIcon,
			name = name,
			buy = buy,
			status = status,
			setView = function(v: WorldShopLogic.Row)
				current = v
			end,
		}
	end

	local function updateTile(t: any, view: WorldShopLogic.Row)
		t.setView(view)
		t.icon.set(view.icon)
		t.name.Text = view.name
		local done = view.status == "maxed" or view.status == "owned"
		t.icon.setFrame(if done then Theme.Gold elseif view.enabled then Theme.Good else nil)
		local slot = WorldShopLogic.slot(view)
		t.buy.instance.Visible = slot.kind == "buy"
		t.buy.setText(view.buttonText)
		t.buy.setEnabled(slot.kind == "buy" and view.enabled)
		t.status.Visible = slot.kind ~= "buy"
		t.status.Text = if slot.kind == "buy" then "" else WorldShop.statusText(slot)
		t.status.TextColor3 = if slot.good then Theme.Good else Theme.Muted
		Widgets.setStatusCheck(t.status, slot.kind == "status" and slot.check == true)
	end

	local function makeGrid(): any
		local frame = create("Frame", { Name = "FunGrid", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0) })
		local cols = WorldShop.GRID_COLS
		local gap = WorldShop.GRID_GAP
		create("UIGridLayout", {
			CellPadding = UDim2.fromOffset(gap, gap),
			CellSize = UDim2.new(1 / cols, -math.ceil(gap * (cols - 1) / cols), 0, WorldShop.TILE_H),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = frame,
		})
		return { instance = frame, tiles = {} }
	end

	local function updateGrid(grid: any, entry: WorldShopLogic.Entry)
		local tiles = entry.tiles or {}
		local seen = {}
		for i, view in tiles do
			seen[view.id] = true
			local t = grid.tiles[view.id]
			if t == nil then
				t = makeTile(view)
				t.instance.Parent = grid.instance
				grid.tiles[view.id] = t
			end
			t.instance.LayoutOrder = i
			updateTile(t, view)
		end
		for id, t in grid.tiles do
			if not seen[id] then
				t.instance:Destroy()
				grid.tiles[id] = nil
			end
		end
		local rowsN = math.ceil(#tiles / WorldShop.GRID_COLS)
		local h = math.max(rowsN * WorldShop.TILE_H + (rowsN - 1) * WorldShop.GRID_GAP, 0)
		grid.instance.Size = UDim2.new(1, 0, 0, h)
	end

	local sp = WorldShop.SERVER_POTION
	local function stripped(entry: WorldShopLogic.Entry): boolean
		return entry.kind == "row" and serverQuick ~= nil and entry.row ~= nil and entry.row.id == sp.id
	end

	local entries = Widgets.keyedList(list, function(entry: WorldShopLogic.Entry)
		return `{shopId}_{entry.key}{if stripped(entry) then "_sp" else ""}`
	end, function(entry: WorldShopLogic.Entry)
		if entry.kind == "label" then
			return makeLabel(entry)
		elseif entry.kind == "ladder" then
			return makeLadder(entry)
		elseif entry.kind == "grid" then
			return makeGrid()
		end
		return makeRow(entry.row :: WorldShopLogic.Row, { thin = entry.thin, strip = stripped(entry) })
	end, function(item: any, entry: WorldShopLogic.Entry)
		if entry.kind == "label" then
			item.text.Text = entry.text or ""
		elseif entry.kind == "ladder" then
			updateLadder(item, entry)
		elseif entry.kind == "grid" then
			updateGrid(item, entry)
		else
			updateRow(item, entry.row :: WorldShopLogic.Row)
		end
	end)

	local self = { frame = panel.frame, close = panel.close }

	-- The restock countdown follows the server clock; init.client's 10 Hz tick drives it while the card is open.
	local function showRestock()
		local label = restockLabel
		if label and label.Parent and restockAt then
			label.Text = ShopCatalog.restockText(restockAt, ctx.serverNow())
		end
	end

	refresh = function()
		local id = shopId
		if id == nil or lastState == nil then
			return
		end
		local state = lastState
		restockAt = WorldShopLogic.restockAt(id, state, ctx.Config.FEATURES)
		local v =
			WorldShopLogic.view(id, state, ctx.actions, ctx.Config.FEATURES, ctx.Config, { tab = tab, picks = picks })
		tab = v.tab
		placeTabs(v.tabs, v.tab)
		serverQuick = ExclusiveShopView.potionQuickBuy(state, ctx.Config)
		entries.sync(v.entries)
		showRestock()
		-- Forget the icons of rows that went away.
		for i = #icons, 1, -1 do
			if icons[i].instance.Parent == nil then
				table.remove(icons, i)
			end
		end
	end

	-- Which shop the card shows (title, corner icon, entries). Called before the card opens; every open starts
	-- on the first tab with no tier picked.
	function self.setShop(id: string)
		shopId = id
		tab = nil
		picks = {}
		panel.title.Text = WorldShopLogic.title(id)
		local look = (WorldShop.ICON :: any)[id] or WorldShop.ICON.ItemShop
		panel.icon.Text = look.text or ""
		arrow.Visible = look.drawn == "upArrow"
		tile.BackgroundColor3 = (Theme :: any)[look.tile or "Text"]
		list.CanvasPosition = Vector2.zero
		refresh()
	end

	function self.shop(): string?
		return shopId
	end

	-- The Item Shop tab on show, and showing another one (an unknown id shows the first tab).
	function self.tab(): string?
		return tab
	end

	function self.setTab(id: string)
		tab = id
		list.CanvasPosition = Vector2.zero
		refresh()
	end

	-- Model icons only render while the shop is open.
	function self.setOpen(open: boolean)
		isOpen = open
		for _, view in icons do
			view.setActive(open)
		end
		-- Hidden by anything (X, backdrop, Esc / B, another menu): the server still has the shop open.
		if not open and ctx.worldShop then
			ctx.worldShop.onHidden()
		end
	end

	function self.tick()
		if isOpen then
			showRestock()
		end
	end

	function self.update(state: any)
		lastState = state
		refresh()
	end

	return self
end

return WorldShop
