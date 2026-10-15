--!strict
--[[
	Shop panel: lock time, lock upgrades, the Speed Coil and the v13 upgrades
	(Slime Snacks, Strong Arms, ...) from ShopCatalog.
	Each Buy calls `Request(item.action, ...item.args)`. Items whose action
	isn't in Remotes.ACTIONS yet show "Coming soon" (UI-CONTRACT-GAPS.md).
]]

local UI = script.Parent.Parent
local Layout = require(UI.Layout)
local ShopCatalog = require(UI.ShopCatalog)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Shop = {}

function Shop.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "ShopPanel", "Shop")

	local list = Widgets.scrollList({ Name = "List", Parent = panel.body }, 6)

	local rows = Widgets.keyedList(list, function(view: ShopCatalog.ItemView)
		return view.item.id
	end, function(view: ShopCatalog.ItemView)
		local item = view.item
		local frame = create("Frame", {
			Name = item.id,
			Size = UDim2.new(1, -10, 0, 84), -- 3 description lines
			BackgroundColor3 = Theme.Row,
		}, { Widgets.corner(8) })
		local name = Widgets.label({
			Name = "ItemName",
			Font = Theme.Font,
			Text = item.name,
			Size = UDim2.new(1, -140, 0, 20),
			Position = UDim2.fromOffset(10, 6),
			Parent = frame,
		})
		local level = Widgets.label({
			Name = "Level",
			TextSize = 13,
			TextColor3 = Theme.Gold,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -128, 0, 8),
			Size = UDim2.fromOffset(60, 18),
			Parent = frame,
		})
		local desc = Widgets.label({
			Name = "Description",
			TextSize = 13,
			TextColor3 = Theme.Muted,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, -140, 0, 50),
			Position = UDim2.fromOffset(10, 28),
			Parent = frame,
		})
		local current = view
		local buy = Widgets.button(
			{
				Name = "Buy",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(110, Layout.BUTTON),
			},
			Theme.Good,
			function()
				if current.available and current.enabled then
					ctx.send(item.action, table.unpack(item.args))
				end
			end
		)
		buy.instance.Parent = frame
		return {
			instance = frame,
			name = name,
			level = level,
			desc = desc,
			buy = buy,
			setView = function(v: ShopCatalog.ItemView)
				current = v
			end,
		}
	end, function(row: any, view: ShopCatalog.ItemView)
		row.setView(view)
		row.desc.Text = view.description
		row.level.Text = view.levelText or ""
		row.buy.setText(view.buttonText)
		row.buy.setEnabled(view.enabled)
	end)

	local self = { frame = panel.frame, close = panel.close }

	function self.update(state: any)
		rows.sync(ShopCatalog.views(state, ctx.actions, ctx.Config))
	end

	return self
end

return Shop
