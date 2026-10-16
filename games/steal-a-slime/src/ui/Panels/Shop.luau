--!strict
--[[
	Shop panel: the ONE shop menu (v28). Opened from the nav, the HUD Shop
	button or "Open Shop" (E) at the ShopStand (init.client, ShopPrompt).
	Lists every ShopCatalog item in one scroll list: lock time, lock
	upgrades, the Speed Coil and the v13 upgrades (Slime Snacks, Strong
	Arms, ...). Each row is an icon badge (level chip under it), the name, a short
	(at most two-line) description and a price button that calls `Request(item.action, ...item.args)`.
	Items whose action isn't in Remotes.ACTIONS yet show "Coming soon".
]]

local UI = script.Parent.Parent
local Format = require(UI.Format)
local ItemIconView = require(UI.ItemIconView)
local ItemIcons = require(UI.ItemIcons)
local Layout = require(UI.Layout)
local ShopCatalog = require(UI.ShopCatalog)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Shop = {}

-- Row geometry (design px): Layout.BUTTON tall price button, ROW-high rows.
Shop.ROW = 68
Shop.BADGE = 48
Shop.BUY_W = 110
Shop.CASH_H = 26
Shop.NAME_H = 22
Shop.DESC_H = 32

function Shop.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "ShopPanel", "Shop", "🛒", Color3.fromRGB(70, 160, 90))

	local cash = Widgets.label({
		Name = "Cash",
		Font = Theme.Font,
		TextSize = 18,
		TextColor3 = Theme.Gold,
		Size = UDim2.new(1, 0, 0, Shop.CASH_H - 4),
		Parent = panel.body,
	})

	local list = Widgets.scrollList({
		Name = "List",
		Position = UDim2.fromOffset(0, Shop.CASH_H),
		Size = UDim2.new(1, 0, 1, -Shop.CASH_H),
		Parent = panel.body,
	}, 6)

	local isOpen = false
	local icons: { [string]: any } = {}
	local rows = Widgets.keyedList(list, function(view: ShopCatalog.ItemView)
		return view.item.id
	end, function(view: ShopCatalog.ItemView)
		local item = view.item
		local frame = create("Frame", {
			Name = item.id,
			Size = UDim2.new(1, -10, 0, Shop.ROW),
			BackgroundColor3 = Theme.Row,
		}, { Widgets.corner(12) })
		local icon = ItemIconView.new({
			Name = "Icon",
			Id = item.id,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
			Size = Shop.BADGE,
			Parent = frame,
		}, ItemIcons.of(ctx))
		icon.setActive(isOpen)
		icons[item.id] = icon
		local level = Widgets.label({
			Name = "Level",
			Font = Theme.Font,
			TextSize = 11,
			TextColor3 = Theme.Gold,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.3,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0, 8 + Shop.BADGE / 2, 1, -1),
			Size = UDim2.fromOffset(Shop.BADGE + 8, 14),
			ZIndex = 2,
			Parent = frame,
		})
		local textX = 8 + Shop.BADGE + 10
		local textW = -(textX + Shop.BUY_W + 16)
		local name = Widgets.label({
			Name = "ItemName",
			Font = Theme.Font,
			TextSize = 17,
			Text = item.name,
			Size = UDim2.new(1, textW, 0, Shop.NAME_H),
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
			Size = UDim2.new(1, textW, 0, Shop.DESC_H), -- two lines on a phone
			Position = UDim2.fromOffset(textX, 6 + Shop.NAME_H + 2),
			Parent = frame,
		})
		local current = view
		local buy = Widgets.holdButton(
			{
				Name = "Buy",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(Shop.BUY_W, Layout.BUTTON),
				TextSize = 16,
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
		return {
			instance = frame,
			icon = icon,
			level = level,
			name = name,
			desc = desc,
			buy = buy,
			setView = function(v: ShopCatalog.ItemView)
				current = v
			end,
		}
	end, function(row: any, view: ShopCatalog.ItemView)
		row.setView(view)
		row.level.Text = view.levelText or ""
		row.desc.Text = view.description
		-- Frame colour: gold when maxed / owned, green when you can buy it.
		row.icon.setFrame(if view.maxed then Theme.Gold elseif view.enabled then Theme.Good else nil)
		row.buy.setText(view.buttonText)
		row.buy.setEnabled(view.enabled)
	end)

	local self = { frame = panel.frame, close = panel.close }

	-- Model icons only render while the shop is open.
	function self.setOpen(open: boolean)
		isOpen = open
		for _, icon in icons do
			icon.setActive(open)
		end
	end

	function self.update(state: any)
		cash.Text = `💰 {Format.formatCash(if type(state.cash) == "number" then state.cash else 0)}`
		rows.sync(ShopCatalog.views(state, ctx.actions, ctx.Config))
	end

	return self
end

return Shop
