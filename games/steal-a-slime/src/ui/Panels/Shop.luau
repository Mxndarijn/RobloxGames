--!strict
--[[
	Shop panel: the ONE shop menu (v28) for FEATURES.WorldShops off. Opened from the nav, the HUD Shop
	button or "Open Shop" (E) at the ShopStand (init.client, ShopPrompt).
	Lists every ShopCatalog item in one scroll list: the Speed Coil and the v13 upgrades (Slime Snacks, Strong
	Arms, ...). Each row is built from the same parts as the world shop card (Panels/WorldShop): an icon
	tile with a gold level / stock tag under it, the name, a short (at most two-line) description and on the
	right the green hold Buy that calls `Request(item.action, ...item.args)`, a status well ("✅ Owned",
	"🔒 Rebirth 12") or the gold MAX stamp. Items whose action isn't in Remotes.ACTIONS yet say "Coming soon".
]]

local UI = script.Parent.Parent
local Format = require(UI.Format)
local ItemIconView = require(UI.ItemIconView)
local ItemIcons = require(UI.ItemIcons)
local Layout = require(UI.Layout)
local ShopCatalog = require(UI.ShopCatalog)
local Widgets = require(UI.Widgets)
local WorldShop = require(script.Parent.WorldShop)
local WorldShopLogic = require(UI.WorldShopLogic)

local Theme = Widgets.Theme

local Shop = {}

-- Row geometry (design px): Layout.BUTTON tall price button, ROW-high rows.
Shop.ROW = 68
Shop.BADGE = 48
Shop.BUY_W = 110
Shop.TOP_H = WorldShop.TOP_H
Shop.NAME_H = 22
Shop.DESC_H = 34

local SIZE = WorldShop.SIZE
local EDGE, GAP = WorldShop.EDGE, WorldShop.GAP

function Shop.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "ShopPanel", "Shop", "🛒")

	local cash = Widgets.chip({
		Name = "Cash",
		Size = UDim2.fromOffset(0, SIZE.chipH),
		Parent = panel.body,
	}, Theme.Gold)

	-- Consumables restock countdown (FEATURES.Consumables); only visible while State.consumables exists.
	local restock = Widgets.chip({
		Name = "RestockTimer",
		FontFace = Theme.FontBody,
		TextSize = SIZE.softChip,
		BackgroundColor3 = Theme.Row,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(0, SIZE.chipH),
		Visible = false,
		Parent = panel.body,
	}, Theme.Muted)

	local list = Widgets.scrollList({
		Name = "List",
		Position = UDim2.fromOffset(0, Shop.TOP_H),
		Size = UDim2.new(1, 0, 1, -Shop.TOP_H),
		Parent = panel.body,
	}, 6)

	local textX = EDGE + Shop.BADGE + GAP
	local function textWidth(slotW: number): UDim
		return UDim.new(1, -(textX + slotW + EDGE + GAP))
	end

	local isOpen = false
	local icons: { [string]: any } = {}
	local rows = Widgets.keyedList(list, function(view: ShopCatalog.ItemView)
		return view.item.id
	end, function(view: ShopCatalog.ItemView)
		local item = view.item
		local frame = Widgets.rowFrame({
			Name = item.id,
			Size = UDim2.new(1, -10, 0, Shop.ROW),
		})
		local icon = ItemIconView.new({
			Name = "Icon",
			Id = item.id,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, EDGE, 0.5, 0),
			Size = Shop.BADGE,
			Parent = frame,
		}, ItemIcons.of(ctx))
		icon.setActive(isOpen)
		icons[item.id] = icon
		local current = view
		local buy = Widgets.holdButton(
			{
				Name = "Buy",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -EDGE, 0.5, 0),
				Size = UDim2.fromOffset(Shop.BUY_W, Layout.BUTTON),
				TextSize = SIZE.buy,
			},
			Theme.Good,
			function()
				if current.available and current.enabled then
					ctx.send(item.action, table.unpack(item.args))
				end
			end,
			ctx.Config.HOLD_CONFIRM_SECONDS
		)
		buy.instance.Parent = frame
		-- Level ("Lv 2/5") or stock ("2/3 left") tag hanging off the icon's bottom edge, drawn over the tile.
		local level = WorldShop.tag({
			Name = "Level",
			Text = "",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, EDGE + Shop.BADGE / 2, 0.5, Shop.BADGE / 2),
			ZIndex = icon.instance.ZIndex + 1,
			Visible = false,
			Parent = frame,
		}, SIZE.tag, SIZE.tagH, SIZE.tagPad, SIZE.tagH)
		local name = Widgets.label({
			Name = "ItemName",
			Font = Theme.Font,
			TextSize = WorldShopLogic.NAME_SIZE,
			Text = item.name,
			Size = UDim2.new(textWidth(Shop.BUY_W), UDim.new(0, Shop.NAME_H)),
			Position = UDim2.fromOffset(textX, 6),
			Parent = frame,
		})
		local desc = Widgets.label({
			Name = "Description",
			FontFace = Theme.FontBody,
			TextSize = SIZE.desc,
			TextColor3 = Theme.Muted,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(textWidth(Shop.BUY_W), UDim.new(0, Shop.DESC_H)), -- two lines on a phone
			Position = UDim2.fromOffset(textX, 6 + Shop.NAME_H + 2),
			Parent = frame,
		})
		local status = Widgets.status({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -EDGE, 0.5, 0),
			Size = UDim2.fromOffset(Shop.BUY_W, Layout.BUTTON),
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
			Position = UDim2.new(1, -EDGE, 0.5, 0),
			Visible = false,
			Parent = frame,
		}, SIZE.stamp, SIZE.stampH, SIZE.stampPad, SIZE.stampRadius)
		return {
			instance = frame,
			icon = icon,
			level = level,
			name = name,
			desc = desc,
			buy = buy,
			status = status,
			stamp = stamp,
			setView = function(v: ShopCatalog.ItemView)
				current = v
			end,
		}
	end, function(row: any, view: ShopCatalog.ItemView)
		row.setView(view)
		row.level.Text = view.levelText or ""
		row.level.Size =
			UDim2.fromOffset(math.ceil(Layout.lineWidth(row.level.Text, SIZE.tag, true)) + SIZE.tagPad * 2, SIZE.tagH)
		row.level.Visible = view.levelText ~= nil
		row.desc.Text = view.description
		-- Icon frame: gold when maxed / owned, green when you can buy it.
		row.icon.setFrame(if view.maxed then Theme.Gold elseif view.enabled then Theme.Good else nil)

		local slot = WorldShopLogic.slot(view)
		local slotW = Shop.BUY_W
		row.buy.instance.Visible = slot.kind == "buy"
		row.buy.setText(view.buttonText)
		row.buy.setEnabled(slot.kind == "buy" and view.enabled)
		row.stamp.Visible = slot.kind == "stamp"
		row.status.Visible = slot.kind == "status"
		if slot.kind == "status" then
			slotW = WorldShop.statusWidth(slot)
			row.status.Text = WorldShop.statusText(slot)
			row.status.TextColor3 = if slot.good then Theme.Good else Theme.Muted
			row.status.Size = UDim2.fromOffset(slotW, Layout.BUTTON)
		end
		local w = textWidth(slotW)
		row.name.Size = UDim2.new(w, UDim.new(0, Shop.NAME_H))
		row.desc.Size = UDim2.new(w, UDim.new(0, Shop.DESC_H))
	end)

	local self = { frame = panel.frame, close = panel.close }

	-- Server time at the last snapshot, so the countdown ticks between snapshots.
	local restockAt, serverAt, receivedAt = nil :: number?, 0, 0
	local function showRestock()
		if restockAt then
			restock.Text = ShopCatalog.restockText(restockAt, serverAt + (os.clock() - receivedAt))
		end
	end

	-- Model icons only render while the shop is open.
	local ticking = false
	function self.setOpen(open: boolean)
		isOpen = open
		for _, icon in icons do
			icon.setActive(open)
		end
		-- The restock countdown ticks only while the card is open (update() refreshes it otherwise).
		if open and not ticking then
			ticking = true
			task.spawn(function()
				while isOpen and panel.frame.Parent do
					showRestock()
					task.wait(1)
				end
				ticking = false
			end)
		end
	end

	function self.update(state: any)
		local view = state.consumables
		if type(view) == "table" and type(state.serverTime) == "number" then
			restockAt, serverAt, receivedAt = view.restockAt, state.serverTime, os.clock()
		else
			restockAt = nil
		end
		restock.Visible = restockAt ~= nil
		showRestock()
		cash.Text = `💰 {Format.formatCash(if type(state.cash) == "number" then state.cash else 0)}`
		rows.sync(ShopCatalog.views(state, ctx.actions, ctx.Config))
	end

	return self
end

return Shop
