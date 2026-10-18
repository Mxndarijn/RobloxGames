--!strict
--[[
	World shop panel (FEATURES.WorldShops, CONTRACT.md §27): the card of ONE in-world shop, "Item Shop" or
	"Upgrade Shop". The server opens it at the stand's ShopPrompt (ShopEvent Open / attribute OpenShop);
	init.client calls setShop(shopId) and shows the card like every other menu (setOpen("WorldShop"), X,
	backdrop, Esc / B). Rows come from WorldShopLogic.rows (Shared.Shops + the live State); a Buy hold calls
	Request("ShopBuy", shopId, itemId). Same row geometry as the old combined Panels/Shop, which stays
	for FEATURES.WorldShops off.
]]

local UI = script.Parent.Parent
local Format = require(UI.Format)
local ItemIconView = require(UI.ItemIconView)
local ItemIcons = require(UI.ItemIcons)
local Layout = require(UI.Layout)
local ShopCatalog = require(UI.ShopCatalog)
local Widgets = require(UI.Widgets)
local WorldShopLogic = require(UI.WorldShopLogic)

local Theme = Widgets.Theme
local create = Widgets.create

local WorldShop = {}

-- Row geometry (design px), the same as the old Shop panel so LayoutAssert.shopTexts covers both.
WorldShop.ROW = 68
WorldShop.BADGE = 48
WorldShop.BUY_W = 110
WorldShop.CASH_H = 26
WorldShop.NAME_H = 22
WorldShop.DESC_H = 32
WorldShop.BAR_H = 4 -- the Upgrade Shop's level bar under the description

-- Each shop has its own look so they read apart at a glance: a green market (Item Shop) and a blue workshop with
-- level bars (Upgrade Shop).
WorldShop.STYLE = table.freeze({
	ItemShop = table.freeze({
		icon = "🛒",
		accent = Theme.ItemShop,
		bg = Theme.ItemShopBg,
		row = Theme.ItemShopRow,
		buy = Theme.Good,
		tagline = Theme.Accent,
		levelBar = false,
	}),
	UpgradeShop = table.freeze({
		icon = "⬆️",
		accent = Theme.UpgradeShop,
		bg = Theme.UpgradeShopBg,
		row = Theme.UpgradeShopRow,
		buy = Theme.Info,
		tagline = Theme.Gold,
		levelBar = true,
	}),
})

local function styleOf(shopId: string?): any
	return (WorldShop.STYLE :: any)[shopId or ""] or WorldShop.STYLE.ItemShop
end

function WorldShop.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "WorldShopPanel", "Shop", "🛒", Theme.ItemShop)

	local cash = Widgets.label({
		Name = "Cash",
		Font = Theme.Font,
		TextSize = 18,
		TextColor3 = Theme.Gold,
		Size = UDim2.new(1, 0, 0, WorldShop.CASH_H - 4),
		Parent = panel.body,
	})

	-- Consumables restock countdown (Item Shop, FEATURES.Consumables).
	local restock = Widgets.label({
		Name = "RestockTimer",
		Font = Theme.Font,
		TextSize = 14,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.new(0.5, 0, 0, WorldShop.CASH_H - 4),
		Visible = false,
		Parent = panel.body,
	})

	-- What kind of shop this is; shares the restock timer's spot (the timer wins while it shows).
	local tagline = Widgets.label({
		Name = "Tagline",
		Font = Theme.Font,
		TextSize = 14,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.new(0.5, 0, 0, WorldShop.CASH_H - 4),
		Parent = panel.body,
	})

	local list = Widgets.scrollList({
		Name = "List",
		Position = UDim2.fromOffset(0, WorldShop.CASH_H),
		Size = UDim2.new(1, 0, 1, -WorldShop.CASH_H),
		Parent = panel.body,
	}, 6)

	local shopId: string? = nil
	local isOpen = false
	local icons: { [string]: any } = {}
	local rows = Widgets.keyedList(list, function(view: WorldShopLogic.Row)
		return `{view.shopId}_{view.id}`
	end, function(view: WorldShopLogic.Row)
		local style = styleOf(view.shopId)
		local frame = create("Frame", {
			Name = view.id,
			Size = UDim2.new(1, -10, 0, WorldShop.ROW),
			BackgroundColor3 = style.row,
		}, { Widgets.corner(12), Widgets.stroke(style.accent, 1) })
		local icon = ItemIconView.new({
			Name = "Icon",
			Id = view.icon,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
			Size = WorldShop.BADGE,
			Parent = frame,
		}, ItemIcons.of(ctx))
		icon.setActive(isOpen)
		icons[view.id] = icon
		local level = Widgets.label({
			Name = "Level",
			Font = Theme.Font,
			TextSize = 11,
			TextColor3 = Theme.Gold,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.3,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0, 8 + WorldShop.BADGE / 2, 1, -1),
			Size = UDim2.fromOffset(WorldShop.BADGE + 8, 14),
			ZIndex = 2,
			Parent = frame,
		})
		local textX = 8 + WorldShop.BADGE + 10
		local textW = -(textX + WorldShop.BUY_W + 16)
		local name = Widgets.label({
			Name = "ItemName",
			Font = Theme.Font,
			TextSize = WorldShopLogic.nameSize(view.name),
			Text = view.name,
			Size = UDim2.new(1, textW, 0, WorldShop.NAME_H),
			Position = UDim2.fromOffset(textX, 6),
			Parent = frame,
		})
		local desc = Widgets.label({
			Name = "Description",
			TextSize = 13,
			TextColor3 = Theme.Muted,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, textW, 0, WorldShop.DESC_H), -- two lines on a phone
			Position = UDim2.fromOffset(textX, 6 + WorldShop.NAME_H + 2),
			Parent = frame,
		})
		-- Level bar (Upgrade Shop): how far this upgrade is towards its max level.
		local bar, barFill = nil :: Frame?, nil :: Frame?
		if style.levelBar then
			bar = create("Frame", {
				Name = "LevelBar",
				BorderSizePixel = 0,
				BackgroundColor3 = Theme.Bg,
				Position = UDim2.new(0, textX, 1, -(WorldShop.BAR_H + 3)),
				Size = UDim2.new(1, textW, 0, WorldShop.BAR_H),
				Visible = false,
				Parent = frame,
			}, { Widgets.corner(2) })
			barFill = create("Frame", {
				Name = "Fill",
				BorderSizePixel = 0,
				BackgroundColor3 = style.accent,
				Size = UDim2.fromScale(0, 1),
				Parent = bar,
			}, { Widgets.corner(2) })
		end
		local current = view
		local buy = Widgets.holdButton(
			{
				Name = "Buy",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(WorldShop.BUY_W, Layout.BUTTON),
				TextSize = 16,
			},
			style.buy,
			function()
				if current.enabled then
					ctx.send("ShopBuy", table.unpack(WorldShopLogic.buyArgs(current), 1, 2))
				end
			end,
			ctx.Config.HOLD_CONFIRM_SECONDS
		)
		buy.instance.Parent = frame
		return {
			instance = frame,
			icon = icon,
			level = level,
			name = name,
			desc = desc,
			bar = bar,
			barFill = barFill,
			buy = buy,
			setView = function(v: WorldShopLogic.Row)
				current = v
			end,
		}
	end, function(row: any, view: WorldShopLogic.Row)
		row.setView(view)
		row.name.Text = view.name
		row.name.TextSize = WorldShopLogic.nameSize(view.name)
		row.level.Text = view.levelText or ""
		row.desc.Text = view.description
		if row.bar and row.barFill then
			row.bar.Visible = view.progress ~= nil
			row.barFill.Size = UDim2.fromScale(view.progress or 0, 1)
			row.barFill.BackgroundColor3 = if (view.progress or 0) >= 1 then Theme.Gold else styleOf(view.shopId).accent
		end
		-- Frame colour: gold when maxed / owned, green when you can buy it.
		local done = view.status == "maxed" or view.status == "owned"
		row.icon.setFrame(if done then Theme.Gold elseif view.enabled then Theme.Good else nil)
		row.buy.setText(view.buttonText)
		row.buy.setEnabled(view.enabled)
	end)

	local self = { frame = panel.frame, close = panel.close }

	-- The restock countdown follows the server clock; init.client's 10 Hz tick drives it while the card is open.
	local restockAt = nil :: number?
	local function showRestock()
		if restockAt then
			restock.Text = ShopCatalog.restockText(restockAt, ctx.serverNow())
		end
	end

	local lastState: any = nil
	local function refresh()
		local id = shopId
		if id == nil or lastState == nil then
			return
		end
		local state = lastState
		restockAt = WorldShopLogic.restockAt(id, state, ctx.Config.FEATURES)
		restock.Visible = restockAt ~= nil
		tagline.Visible = restockAt == nil
		showRestock()
		cash.Text = `💰 {Format.formatCash(if type(state.cash) == "number" then state.cash else 0)}`
		rows.sync(WorldShopLogic.rows(id, state, ctx.actions, ctx.Config.FEATURES, ctx.Config))
	end

	-- Which shop the card shows (title, colours, tagline, rows). Called before the card opens.
	function self.setShop(id: string)
		shopId = id
		local style = styleOf(id)
		panel.title.Text = WorldShopLogic.title(id)
		panel.icon.Text = style.icon
		panel.frame.BackgroundColor3 = style.bg
		local band = panel.frame:FindFirstChild("Band")
		if band and band:IsA("Frame") then
			band.BackgroundColor3 = style.accent
		end
		local outline = panel.frame:FindFirstChildOfClass("UIStroke")
		if outline then
			outline.Color = style.accent
		end
		tagline.Text = WorldShopLogic.tagline(id)
		tagline.TextColor3 = style.tagline
		refresh()
	end

	function self.shop(): string?
		return shopId
	end

	-- Model icons only render while the shop is open.
	function self.setOpen(open: boolean)
		isOpen = open
		for _, icon in icons do
			icon.setActive(open)
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
