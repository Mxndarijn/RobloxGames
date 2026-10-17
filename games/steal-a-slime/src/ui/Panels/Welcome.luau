--!strict
--[[
	Welcome-back card (v20, FEATURES.WelcomeBack): what happened while the player was away
	(WelcomeBack.view) and one Collect button. Opened by the PopupQueue after a long absence
	(init.client), closed like every menu (Collect, X, Esc, B, tap outside). Not in the nav.
	The cash was already paid at join, so Collect only closes it. Content-sized: the card is as
	tall as its rows plus the button.
]]

local UI = script.Parent.Parent
local ItemIconView = require(UI.ItemIconView)
local ItemIcons = require(UI.ItemIcons)
local Layout = require(UI.Layout)
local WelcomeBack = require(UI.WelcomeBack)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme

local Welcome = {}

Welcome.ROW_H = 56
Welcome.GAP = 8
Welcome.ICON = 40
Welcome.HEAD_H = 28
Welcome.BUTTON_W = 220

function Welcome.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "WelcomePanel", "Welcome back!", "👋", Color3.fromRGB(255, 190, 60))
	local body = panel.body

	local away = Widgets.label({
		Name = "Away",
		TextSize = 17,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, Welcome.HEAD_H),
		Parent = body,
	})

	local icons = ItemIcons.of(ctx)
	local rows: { Frame } = {}
	local texts: { TextLabel } = {}
	local pics: { any } = {}
	for i = 1, WelcomeBack.MAX_ROWS do
		local row = Widgets.create("Frame", {
			Name = `Row{i}`,
			BackgroundColor3 = Theme.Row,
			Position = UDim2.fromOffset(0, Welcome.HEAD_H + Welcome.GAP + (i - 1) * (Welcome.ROW_H + Welcome.GAP)),
			Size = UDim2.new(1, 0, 0, Welcome.ROW_H),
			Parent = body,
		}, { Widgets.corner(12) })
		pics[i] = ItemIconView.new({
			Name = "Pic",
			Size = Welcome.ICON,
			Position = UDim2.new(0, 10, 0.5, -Welcome.ICON / 2),
			Parent = row,
		}, icons)
		texts[i] = Widgets.label({
			Name = "Text",
			TextSize = 18,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			Position = UDim2.fromOffset(Welcome.ICON + 22, 0),
			Size = UDim2.new(1, -(Welcome.ICON + 32), 1, 0),
			Parent = row,
		})
		rows[i] = row
	end

	local collectY = Welcome.HEAD_H + Welcome.GAP + WelcomeBack.MAX_ROWS * (Welcome.ROW_H + Welcome.GAP) + 4
	local collect = Widgets.button(
		{
			Name = "Collect",
			Text = "Collect!",
			TextSize = 22,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, collectY),
			Size = UDim2.fromOffset(Welcome.BUTTON_W, Layout.BUTTON),
		},
		Theme.Gold,
		function()
			ctx.togglePanel("Welcome")
		end
	)
	collect.instance.TextColor3 = Color3.fromRGB(40, 30, 10)
	collect.instance.Parent = body

	local self = { frame = panel.frame, close = panel.close }

	-- Rows hide when the State has fewer (no daily / every goal done): the card shrinks with them.
	function self.update(state: any)
		local view = WelcomeBack.view(state)
		if view == nil then
			return
		end
		away.Text = view.away
		for i = 1, WelcomeBack.MAX_ROWS do
			local data = view.rows[i]
			rows[i].Visible = data ~= nil
			if data then
				texts[i].Text = data.text
				pics[i].set(data.icon)
				pics[i].setActive(true)
			end
		end
		collect.instance.Position =
			UDim2.new(0.5, 0, 0, Welcome.HEAD_H + Welcome.GAP + #view.rows * (Welcome.ROW_H + Welcome.GAP) + 4)
	end

	return self
end

return Welcome
