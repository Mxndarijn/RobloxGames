--!strict
--[[
	Welcome-back card: what happened while the player was away and one Collect button. Opened by
	the PopupQueue after a long absence (init.client), closed like every menu (Collect, X, Esc, B,
	tap outside). Not in the nav. The cash was already paid at join, so Collect only closes it.

	WelcomeBack.view decides which rows show, in which order and with which icon. The cash row is
	the headline (a big gold amount under the away time); the others are cards with a name, a short
	description and, for the daily reward, its amount or, for the next goal, a progress bar.
	A "Double it · R$49" button sits under the amount while that payout can still be
	doubled (ExclusiveShopView.doubleQuickBuy); it opens Roblox's prompt, the server pays.
	Content-sized: the card is as tall as its rows plus the button. When the screen clamps the card (a
	landscape phone), the away line, the amount and the rows scroll above Collect, which stays pinned
	to the bottom.
]]

local UI = script.Parent.Parent
local ExclusiveShopView = require(UI.ExclusiveShopView)
local Format = require(UI.Format)
local ItemIconView = require(UI.ItemIconView)
local ItemIcons = require(UI.ItemIcons)
local Layout = require(UI.Layout)
local WelcomeBack = require(UI.WelcomeBack)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme

local Welcome = {}

-- Design px, top to bottom. The cards start at `rowsAt`, or at `rowsAtNoCash` when nothing was
-- earned and the gold headline hides.
Welcome.ROWS = table.freeze({
	away = { y = 0, h = 22, size = 16 },
	earned = { y = 22, h = 52, size = 44 },
	rowsAt = 82,
	rowsAtNoCash = 30,
	collectGap = 12,
})
Welcome.ROW_H = 60
Welcome.GAP = 8
Welcome.ICON = 44
Welcome.CARD = table.freeze({
	pad = 8, -- icon inset from the card's left edge
	textX = 62, -- name / description / bar start (pad + ICON + 10)
	right = 12, -- inset of the amount / count from the card's right edge
	nameY = 8,
	nameH = 22,
	nameSize = 18,
	descY = 31,
	descH = 18,
	descSize = 14,
	amountW = 110,
	amountH = 24,
	amountSize = 20,
	countW = 84,
	countSize = 15,
	barY = 36,
	barH = 10,
	sideGap = 8, -- between the name and the amount / count on its right
})
Welcome.COLLECT_SIZE = 22
Welcome.DOUBLE = table.freeze({ w = 240, h = Layout.MIN_TOUCH_DESIGN, size = 18, gap = 8 })

local function plural(n: number, word: string): string
	return `{n} {word}{if n == 1 then "" else "s"}`
end

local function firstOpenGoal(state: any): any
	if type(state.goals) ~= "table" then
		return nil
	end
	for _, goal in state.goals do
		if not goal.done then
			return goal
		end
	end
	return nil
end

export type Card = { name: string, desc: string, amount: string?, progress: number?, count: string? }

-- What one non-cash card shows, from the same State fields WelcomeBack.view reads (pure).
function Welcome.card(rowName: string, state: any): Card
	if rowName == "Growth" then
		local grown = state.welcomeBack.grown
		if grown > 0 then
			return { name = `{plural(grown, "slime")} grew`, desc = "on your pads while you were gone" }
		end
		return { name = "All grown", desc = "Your slimes are fully grown" }
	elseif rowName == "Daily" then
		local daily = state.daily
		if daily.available then
			return {
				name = "Daily reward ready",
				desc = "Claim it after this",
				amount = Format.formatCash(daily.amount),
			}
		end
		return { name = `Daily streak: {plural(daily.streak, "day")}`, desc = "Come back tomorrow for more" }
	elseif rowName == "Goal" then
		local goal = firstOpenGoal(state)
		if goal then
			local target = goal.target or goal.progress
			local done = math.min(goal.progress, target)
			return {
				name = goal.title,
				desc = "",
				progress = if target > 0 then done / target else 0,
				count = `{done}/{goal.target or 0}`,
			}
		end
	end
	return { name = rowName, desc = "" }
end

-- "You were away for 5h 30m and earned" over the headline; no "and earned" when nothing was (pure).
function Welcome.awayLine(report: any): string
	local away = `You were away for {WelcomeBack.awayText(report.away)}`
	return if report.cash > 0 then `{away} and earned` else away
end

function Welcome.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "WelcomePanel", "Welcome back", "👋")
	local body = panel.body
	local layout = Welcome.ROWS
	local card = Welcome.CARD

	-- Everything but Collect; its canvas is set in update to the rows' bottom plus the gap above Collect.
	local content = Widgets.scroll({
		Name = "Content",
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		Size = UDim2.new(1, 0, 1, -Layout.BUTTON),
		Parent = body,
	})

	local away = Widgets.label({
		Name = "Away",
		TextSize = layout.away.size,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, layout.away.y),
		Size = UDim2.new(1, 0, 0, layout.away.h),
		Parent = content,
	})
	local earned = Widgets.label({
		Name = "Earned",
		Font = Theme.Font,
		TextSize = layout.earned.size,
		TextColor3 = Theme.Gold,
		TextStrokeColor3 = Theme.Ink,
		TextStrokeTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, layout.earned.y),
		Size = UDim2.new(1, 0, 0, layout.earned.h),
		Parent = content,
	})

	-- Row{i} shows view.rows[i]; row 1 (cash) is the headline above, so the cards are rows 2..MAX_ROWS.
	local icons = ItemIcons.of(ctx)
	type Row = {
		frame: Frame,
		pic: any,
		name: TextLabel,
		desc: TextLabel,
		amount: TextLabel,
		count: TextLabel,
		bar: Frame,
		setBar: (number) -> (),
	}
	local rows: { [number]: Row } = {}
	for i = 2, WelcomeBack.MAX_ROWS do
		local frame = Widgets.rowFrame({
			Name = `Row{i}`,
			Size = UDim2.new(1, 0, 0, Welcome.ROW_H),
			Parent = content,
		})
		local pic = ItemIconView.new({
			Name = "Pic",
			Size = Welcome.ICON,
			Position = UDim2.new(0, card.pad, 0.5, -Welcome.ICON / 2),
			Parent = frame,
		}, icons)
		local name = Widgets.label({
			Name = "Name",
			Font = Theme.Font,
			TextSize = card.nameSize,
			Position = UDim2.fromOffset(card.textX, card.nameY),
			Size = UDim2.new(1, -(card.textX + card.right), 0, card.nameH),
			Parent = frame,
		})
		local desc = Widgets.label({
			Name = "Desc",
			TextSize = card.descSize,
			TextColor3 = Theme.Muted,
			Position = UDim2.fromOffset(card.textX, card.descY),
			Size = UDim2.new(1, -(card.textX + card.right), 0, card.descH),
			Parent = frame,
		})
		local amount = Widgets.label({
			Name = "Amount",
			Font = Theme.Font,
			TextSize = card.amountSize,
			TextColor3 = Theme.Gold,
			TextStrokeColor3 = Theme.Ink,
			TextStrokeTransparency = 0,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -card.right, 0.5, 0),
			Size = UDim2.fromOffset(card.amountW, card.amountH),
			Visible = false,
			Parent = frame,
		})
		local count = Widgets.label({
			Name = "Count",
			Font = Theme.Font,
			TextSize = card.countSize,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -card.right, 0, card.nameY),
			Size = UDim2.fromOffset(card.countW, card.nameH),
			Visible = false,
			Parent = frame,
		})
		local bar, setBar = Widgets.bar(
			frame,
			Theme.Good,
			UDim2.new(1, -(card.textX + card.right), 0, card.barH),
			UDim2.fromOffset(card.textX, card.barY)
		)
		bar.Name = "Bar"
		bar.Visible = false
		rows[i] = {
			frame = frame,
			pic = pic,
			name = name,
			desc = desc,
			amount = amount,
			count = count,
			bar = bar,
			setBar = setBar,
		}
	end

	local collect = Widgets.button(
		{
			Name = "Collect",
			Text = "Collect",
			TextSize = Welcome.COLLECT_SIZE,
			Position = UDim2.new(0, 0, 1, -Layout.BUTTON),
			Size = UDim2.new(1, 0, 0, Layout.BUTTON),
		},
		Theme.Gold,
		function()
			ctx.togglePanel("Welcome")
		end
	)
	collect.instance.Parent = body

	-- "Double it", built the first time a payout can be doubled (never with the shop off).
	local double: Widgets.Button? = nil
	local doubleBuy: ExclusiveShopView.QuickBuy? = nil
	local function doubleButton(): Widgets.Button
		if double then
			return double
		end
		local d = Welcome.DOUBLE
		local made = Widgets.button(
			{
				Name = "DoubleIt",
				Text = "",
				TextSize = d.size,
				AnchorPoint = Vector2.new(0.5, 0),
				Size = UDim2.fromOffset(d.w, d.h),
			},
			Theme.Accent,
			function()
				local q = doubleBuy
				if q and q.mode == "buy" and q.purchase and ctx.purchase then
					ctx.purchase.prompt(q.purchase)
				end
			end
		)
		made.instance.Parent = content
		double = made
		return made
	end

	local self = { frame = panel.frame, close = panel.close }

	-- Each time the card opens it starts at the top (the away line and the amount), wherever it was left.
	panel.frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if panel.frame.Visible then
			content.CanvasPosition = Vector2.zero
		end
	end)

	-- Cards hide when the view has fewer rows (no daily / every goal done): the card shrinks with them.
	function self.update(state: any)
		local view = WelcomeBack.view(state)
		if view == nil then
			return
		end
		local report = state.welcomeBack
		local hasCash = report.cash > 0
		away.Text = Welcome.awayLine(report)
		earned.Text = `+{Format.formatCash(report.cash)}`
		earned.Visible = hasCash
		local y = if hasCash then layout.rowsAt else layout.rowsAtNoCash
		local q = if hasCash then ExclusiveShopView.doubleQuickBuy(state, ctx.Config) else nil
		doubleBuy = q
		if q then
			local b = doubleButton()
			b.instance.Visible = true
			b.instance.Position = UDim2.new(0.5, 0, 0, y - Welcome.DOUBLE.gap)
			b.setText(q.text)
			b.setEnabled(q.mode == "buy" and ctx.purchase ~= nil)
			y += Welcome.DOUBLE.h + Welcome.DOUBLE.gap
		elseif double then
			double.instance.Visible = false
		end
		local bottom = y
		for i = 2, WelcomeBack.MAX_ROWS do
			local row = rows[i]
			local data = view.rows[i]
			row.frame.Visible = data ~= nil
			if data then
				local info = Welcome.card(data.name, state)
				row.frame.Position = UDim2.fromOffset(0, y)
				bottom = y + Welcome.ROW_H
				y = bottom + Welcome.GAP
				row.pic.set(data.icon)
				row.pic.setActive(true)
				row.name.Text = info.name
				row.desc.Text = info.desc
				row.desc.Visible = info.desc ~= ""
				row.amount.Text = info.amount or ""
				row.amount.Visible = info.amount ~= nil
				row.count.Text = info.count or ""
				row.count.Visible = info.count ~= nil
				row.bar.Visible = info.progress ~= nil
				row.setBar(info.progress or 0)
				local side = if info.amount then card.amountW elseif info.count then card.countW else 0
				local reserve = card.textX + card.right + (if side > 0 then side + card.sideGap else 0)
				row.name.Size = UDim2.new(1, -reserve, 0, card.nameH)
				row.desc.Size = UDim2.new(1, -reserve, 0, card.descH)
			end
		end
		content.CanvasSize = UDim2.fromOffset(0, bottom + layout.collectGap)
	end

	return self
end

return Welcome
