--!strict
--[[
	The welcome back / daily reward card (contract/welcome-back.md): one content-sized menu card, not in the nav.
	WelcomeBack.view decides what shows for the mode the card opened in (`setMode`: "join" for the join report,
	"daily" for a new daily claim or Goals "Open"): a cash row, the daily row with one tile per streak day, a
	growth row, the Robux offers ("Double it", "Keep my streak") and one main button pinned to the bottom.

	The main button claims the daily reward (`Request("Daily")`) while one is ready, else it only closes the card.
	After a claim it reads "Claimed" and closes the card CLAIMED_CLOSE seconds later, unless another menu took its
	place. Closed like every menu too (X, Esc, B, tap outside).
	When the screen clamps the card, the rows scroll above the pinned button. On a landscape phone (`short`) the
	offers sit in the rows they belong to and the growth line joins the cash row, so the card stays short.
]]

local UI = script.Parent.Parent
local Daily = require(UI.Daily)
local ExclusiveShopView = require(UI.ExclusiveShopView)
local ItemIconView = require(UI.ItemIconView)
local ItemIcons = require(UI.ItemIcons)
local Layout = require(UI.Layout)
local WelcomeBack = require(UI.WelcomeBack)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Welcome = {}

-- Design px. A plain row: icon, a name and a description under it.
Welcome.ROW = table.freeze({
	h = 76,
	gap = 10,
	icon = 52,
	pad = 10, -- icon inset from the row's left edge
	textX = 74, -- pad + icon + 12
	right = 12,
	nameY = 10,
	nameH = 24,
	nameSize = 20,
	descY = 34,
	descH = 36, -- two lines: the description wraps
	descSize = 15,
})
-- The daily row: the same head as a plain row, the track of day tiles under it.
Welcome.DAILY = table.freeze({ h = 156, trackY = 72, trackH = 72, trackInset = 10, amountW = 96 })
-- One tile per day of State.daily.track; the last one (always a skin day) is LAST_WEIGHT times wider with a bigger icon.
Welcome.TILE = table.freeze({
	gap = 6,
	lastWeight = 1.5,
	labelY = 4,
	labelH = 17,
	labelSize = Layout.MIN_TEXT,
	iconY = 22,
	icon = 24,
	lastIcon = 30,
	amountH = 17,
	amountInset = 5,
	amountSize = Layout.MIN_TEXT,
	lastAmountSize = 15,
})
-- A landscape phone (Layout.screen `short`): tighter rows and gaps, so the card fits without scrolling.
Welcome.SHORT = table.freeze({ rowH = 70, nameY = 8, descY = 32, dailyH = 144, trackY = 60, gap = 6, actionGap = 8 })
-- The Robux offers: a row of two under the list, or (short screens) one at the right of its row.
Welcome.OFFERS = table.freeze({ h = Layout.MIN_TOUCH_DESIGN, gap = 10, size = 17, inlineW = 212 })
Welcome.ACTION_SIZE = 22
Welcome.ACTION_GAP = 12 -- between the last row and the pinned main button
Welcome.CLAIMED_CLOSE = 1.5

type Row = { frame: Frame, pic: any, name: TextLabel, desc: TextLabel }
type Tile = { frame: Frame, stroke: UIStroke, label: TextLabel, amount: TextLabel, icon: any }

function Welcome.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "WelcomePanel", "Welcome back", "👋") -- WelcomeBack.view sets the mode's title
	local body = panel.body
	local row = Welcome.ROW
	local tileSpec = Welcome.TILE
	local offers = Welcome.OFFERS
	local icons = ItemIcons.of(ctx)
	local count = Daily.TRACK

	-- Everything but the main button; its canvas is set in update to the rows' bottom plus ACTION_GAP.
	local content = Widgets.scroll({
		Name = "Content",
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		Size = UDim2.new(1, 0, 1, -Layout.BUTTON),
		Parent = body,
	})

	local function makeRow(name: string, h: number, icon: string): Row
		local frame = Widgets.rowFrame({ Name = name, Size = UDim2.new(1, 0, 0, h), Parent = content })
		local pic = ItemIconView.new({
			Name = "Pic",
			Id = icon,
			Size = row.icon,
			Position = UDim2.fromOffset(row.pad, (row.h - row.icon) / 2),
			Parent = frame,
		}, icons)
		pic.setActive(true)
		local nameLabel = Widgets.label({
			Name = "Name",
			Font = Theme.Font,
			TextSize = row.nameSize,
			Position = UDim2.fromOffset(row.textX, row.nameY),
			Size = UDim2.new(1, -(row.textX + row.right), 0, row.nameH),
			Parent = frame,
		})
		local desc = Widgets.label({
			Name = "Desc",
			TextSize = row.descSize,
			TextColor3 = Theme.Muted,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(row.textX, row.descY),
			Size = UDim2.new(1, -(row.textX + row.right), 0, row.descH),
			Parent = frame,
		})
		return { frame = frame, pic = pic, name = nameLabel, desc = desc }
	end

	local cashRow = makeRow("CashRow", row.h, "Cash")
	cashRow.name.TextColor3 = Theme.Gold
	cashRow.name.TextStrokeColor3 = Theme.Ink
	cashRow.name.TextStrokeTransparency = 0
	local dailyRow = makeRow("DailyRow", Welcome.DAILY.h, "Daily")
	local growthRow = makeRow("GrowthRow", row.h, "Goal_Pads")

	-- Today's amount, right of the daily row's name.
	local dailyAmount = Widgets.label({
		Name = "Amount",
		Font = Theme.Font,
		TextSize = row.nameSize,
		TextColor3 = Theme.Gold,
		TextStrokeColor3 = Theme.Ink,
		TextStrokeTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -row.right, 0, row.nameY),
		Size = UDim2.fromOffset(Welcome.DAILY.amountW, row.nameH),
		Parent = dailyRow.frame,
	})

	local inset = Welcome.DAILY.trackInset
	local track = create("Frame", {
		Name = "Track",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(inset, Welcome.DAILY.trackY),
		Size = UDim2.new(1, -inset * 2, 0, Welcome.DAILY.trackH),
		Parent = dailyRow.frame,
	}, { Widgets.list(Enum.FillDirection.Horizontal, tileSpec.gap, Enum.HorizontalAlignment.Center) })
	local weightSum = (count - 1) + tileSpec.lastWeight
	-- A claimed tile's check, where its day label was (built the first time the day is claimed).
	local CLAIMED = table.freeze({
		Name = "Claimed",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, tileSpec.labelY),
	})
	local tiles: { Tile } = {}
	for slot = 1, count do
		local last = slot == count
		local frame = Widgets.rowFrame({
			Name = `Day{slot}`,
			LayoutOrder = slot,
			Size = UDim2.new((if last then tileSpec.lastWeight else 1) / weightSum, -tileSpec.gap, 1, 0),
			Parent = track,
		})
		Widgets.shade(frame)
		local label = Widgets.label({
			Name = "DayLabel",
			Font = Theme.Font,
			TextSize = tileSpec.labelSize,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.None,
			Size = UDim2.new(1, 0, 0, tileSpec.labelH),
			Position = UDim2.fromOffset(0, tileSpec.labelY),
			Parent = frame,
		})
		local iconSize = if last then tileSpec.lastIcon else tileSpec.icon
		local icon = ItemIconView.new({
			Name = `Day{slot}Icon`,
			Id = "Cash",
			Size = iconSize,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, tileSpec.iconY + (tileSpec.icon - iconSize) / 2),
			Parent = frame,
		}, icons)
		icon.setActive(true)
		local amount = Widgets.label({
			Name = "DayAmount",
			Font = Theme.Font,
			TextSize = if last then tileSpec.lastAmountSize else tileSpec.amountSize,
			TextScaled = true,
			TextColor3 = Theme.Gold,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, -4, 0, tileSpec.amountH),
			Position = UDim2.new(0, 2, 1, -(tileSpec.amountH + tileSpec.amountInset)),
			Parent = frame,
		})
		create("UITextSizeConstraint", {
			MinTextSize = Layout.MIN_TEXT,
			MaxTextSize = if last then tileSpec.lastAmountSize else tileSpec.amountSize,
			Parent = amount,
		})
		tiles[slot] = {
			frame = frame,
			stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke,
			label = label,
			amount = amount,
			icon = icon,
		}
	end

	-- The Robux offers, built the first time one is offered (never with the shop off). Each opens Roblox's
	-- prompt; the server pays.
	local latestState: any = nil
	local offerRow = create("Frame", {
		Name = "Offers",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, offers.h),
		Parent = content,
	})
	local made: { [string]: Widgets.Button } = {}
	local function offerButton(name: string, quickBuy: (any, any) -> any): Widgets.Button
		if made[name] then
			return made[name]
		end
		local b = Widgets.button(
			{
				Name = name,
				Text = "",
				TextSize = offers.size,
				TextScaled = true,
				Visible = false,
				Size = UDim2.new(0.5, -offers.gap / 2, 0, offers.h),
			},
			Theme.Info,
			function()
				local q = quickBuy(latestState, ctx.Config)
				if q and q.mode == "buy" and q.purchase and ctx.purchase then
					ctx.purchase.prompt(q.purchase)
				end
			end
		)
		create(
			"UITextSizeConstraint",
			{ MinTextSize = Layout.MIN_TEXT, MaxTextSize = offers.size, Parent = b.instance }
		)
		b.instance.Parent = offerRow
		made[name] = b
		return b
	end

	local mode: WelcomeBack.Mode = "daily"
	local actionKind: "claim" | "close" = "close"
	local action = Widgets.button(
		{
			Name = "Action",
			Text = "",
			TextSize = Welcome.ACTION_SIZE,
			Position = UDim2.new(0, 0, 1, -Layout.BUTTON),
			Size = UDim2.new(1, 0, 0, Layout.BUTTON),
		},
		Theme.Gold,
		function()
			if actionKind == "claim" then
				ctx.send("Daily")
			else
				ctx.togglePanel("Welcome")
			end
		end
	)
	action.instance.Parent = body

	local self = { frame = panel.frame, close = panel.close }

	-- The claim just went through while the card was open: "Claimed" until it closes.
	local claimedToken = 0
	local claimedShown = false
	local lastAvailable: boolean? = nil
	local short = false

	-- Each open or close starts fresh: back at the top, no claim state from the last open, no pending auto-close.
	-- init.client calls this from syncMenus before the open-time update, so no deferred signal can undo it.
	function self.setOpen(isOpen: boolean)
		claimedToken += 1
		claimedShown = false
		lastAvailable = nil
		if isOpen then
			content.CanvasPosition = Vector2.zero
		end
	end

	-- Why the card opens: "join" (the join report) or "daily". Set before it opens.
	function self.setMode(m: WelcomeBack.Mode)
		mode = m
	end

	-- Row heights, text offsets and gaps for the current screen (Welcome.SHORT on a landscape phone).
	type Metrics = {
		rowH: number,
		nameY: number,
		descY: number,
		dailyH: number,
		trackY: number,
		gap: number,
		actionGap: number,
	}
	local NORMAL: Metrics = {
		rowH = row.h,
		nameY = row.nameY,
		descY = row.descY,
		dailyH = Welcome.DAILY.h,
		trackY = Welcome.DAILY.trackY,
		gap = row.gap,
		actionGap = Welcome.ACTION_GAP,
	}
	local metrics: Metrics = NORMAL
	local function applyMetrics()
		metrics = if short then Welcome.SHORT :: any else NORMAL
		for _, r in { cashRow, dailyRow, growthRow } do
			r.name.Position = UDim2.fromOffset(row.textX, metrics.nameY)
			r.desc.Position = UDim2.fromOffset(row.textX, metrics.descY)
			r.pic.instance.Position = UDim2.fromOffset(row.pad, (metrics.rowH - row.icon) / 2)
		end
		cashRow.frame.Size = UDim2.new(1, 0, 0, metrics.rowH)
		growthRow.frame.Size = UDim2.new(1, 0, 0, metrics.rowH)
		dailyRow.frame.Size = UDim2.new(1, 0, 0, metrics.dailyH)
		dailyAmount.Position = UDim2.new(1, -row.right, 0, metrics.nameY)
		track.Position = UDim2.fromOffset(inset, metrics.trackY)
	end

	-- Shows the offer `name` for quick-buy `q` (hides it for nil): in `inRow` at its right, or in the offers row at
	-- `x` (0 = left, 0.5 = right half) and `width`.
	local function showOffer(name: string, quickBuy: (any, any) -> any, q: any, inRow: Row?, x: number, width: UDim2)
		if q == nil then
			if made[name] then
				made[name].instance.Visible = false
			end
			return
		end
		local b = offerButton(name, quickBuy)
		b.instance.Visible = true
		b.setText(q.text)
		b.setEnabled(q.mode == "buy" and ctx.purchase ~= nil)
		if inRow then
			b.instance.Parent = inRow.frame
			b.instance.AnchorPoint = Vector2.new(1, 0.5)
			b.instance.Position = UDim2.new(1, -row.right, 0, metrics.rowH / 2)
			b.instance.Size = UDim2.fromOffset(offers.inlineW, offers.h)
		else
			b.instance.Parent = offerRow
			b.instance.AnchorPoint = Vector2.zero
			b.instance.Position = UDim2.new(x, if x > 0 then offers.gap / 2 else 0, 0, 0)
			b.instance.Size = width
		end
	end

	-- Name / description width for a row with `side` px taken at its right (an amount or an inline offer).
	local function fitText(r: Row, side: number)
		local reserve = row.textX + row.right + (if side > 0 then side + offers.gap else 0)
		r.name.Size = UDim2.new(1, -reserve, 0, row.nameH)
		r.desc.Size = UDim2.new(1, -reserve, 0, row.descH)
	end

	function self.update(state: any)
		latestState = state
		local view = WelcomeBack.view(state, mode, ctx.Config)
		if view == nil then
			return
		end
		panel.title.Text = view.title
		panel.icon.Text = view.icon

		-- Just claimed while open: keep "Claimed" up, then close (unless another menu replaced the card).
		local available = view.action.kind == "claim"
		if lastAvailable == true and not available and panel.frame.Visible and not claimedShown then
			claimedShown = true
			claimedToken += 1
			local token = claimedToken
			task.delay(Welcome.CLAIMED_CLOSE, function()
				if token == claimedToken and panel.frame.Visible then
					ctx.togglePanel("Welcome")
				end
			end)
		end
		lastAvailable = available

		local q2 = if view.cash then ExclusiveShopView.doubleQuickBuy(state, ctx.Config) else nil
		local q3 = if view.daily and view.daily.amount then ExclusiveShopView.streakQuickBuy(state, ctx.Config) else nil

		local y = 0
		local function place(r: Row, show: boolean, h: number)
			r.frame.Visible = show
			if show then
				r.frame.Position = UDim2.fromOffset(0, y)
				y += h + metrics.gap
			end
		end

		-- Cash row (join only); on a short screen the growth line joins it.
		local growth = view.growth
		local cash = view.cash
		if cash then
			cashRow.name.Text = cash.name
			cashRow.desc.Text = if short and growth then `{cash.desc}. {growth.name}.` else cash.desc
		end
		place(cashRow, cash ~= nil, metrics.rowH)

		local daily = view.daily
		if daily then
			dailyRow.name.Text = daily.name
			dailyRow.desc.Text = daily.status
			dailyAmount.Text = daily.amount or ""
			dailyAmount.Visible = daily.amountShown
			for slot, t in daily.tiles do
				local tile = tiles[slot]
				if tile then
					tile.icon.set(t.icon)
					local today = t.state == "today"
					local fill = if today then Theme.Gold else Theme.Row
					tile.frame.BackgroundColor3 = fill
					tile.stroke.Thickness = if today then Widgets.KIT.stroke else Widgets.KIT.rowStroke
					tile.label.Text = t.label
					tile.amount.Text = t.amount
					Widgets.showCheck(tile.frame, t.state == "claimed", tileSpec.labelH, CLAIMED)
					if today then
						Widgets.inkOn(tile.label, fill)
						Widgets.inkOn(tile.amount, fill)
					else
						tile.label.TextColor3 = Theme.Muted
						tile.label.TextStrokeTransparency = 1
						tile.amount.TextColor3 = if t.state == "claimed" then Theme.Muted else Theme.Gold
						tile.amount.TextStrokeTransparency = 1
					end
				end
			end
		end
		place(dailyRow, daily ~= nil, metrics.dailyH)

		if growth then
			growthRow.name.Text = growth.name
			growthRow.desc.Text = growth.desc
		end
		place(growthRow, growth ~= nil and not short, metrics.rowH)

		-- Offers: inline in their rows on a short screen, else a row of two (or one, full width) under the list.
		local both = q2 ~= nil and q3 ~= nil
		local width = if both then UDim2.new(0.5, -offers.gap / 2, 0, offers.h) else UDim2.new(1, 0, 0, offers.h)
		showOffer("DoubleIt", ExclusiveShopView.doubleQuickBuy, q2, if short then cashRow else nil, 0, width)
		showOffer(
			"KeepStreak",
			ExclusiveShopView.streakQuickBuy,
			q3,
			if short then dailyRow else nil,
			if both then 0.5 else 0,
			width
		)
		fitText(cashRow, if short and q2 then offers.inlineW else 0)
		fitText(
			dailyRow,
			if short and q3 then offers.inlineW else (if daily and daily.amountShown then Welcome.DAILY.amountW else 0)
		)
		if short and q3 then
			dailyAmount.Visible = false -- the Claim button names the amount
		end
		local offersBelow = not short and (q2 ~= nil or q3 ~= nil)
		offerRow.Visible = offersBelow
		if offersBelow then
			offerRow.Position = UDim2.fromOffset(0, y)
			y += offers.h + metrics.gap
		end

		-- The main button: Claim (gold), Got it (mint), or a "Claimed" well after a claim.
		if claimedShown then
			actionKind = "close"
			action.setText("Claimed")
			action.setEnabled(false)
		else
			actionKind = view.action.kind
			action.setColor(if actionKind == "claim" then Theme.Gold else Theme.Accent)
			action.setText(view.action.text)
			action.setEnabled(true)
		end

		content.CanvasSize = UDim2.fromOffset(0, math.max(0, y - metrics.gap) + metrics.actionGap)
	end

	-- A landscape phone (Layout.screen `short`) puts the offers in their rows: re-flow and re-size the card once.
	function self.layout(_: Layout.Rect, s: Layout.Screen)
		if s.short ~= short then
			short = s.short
			applyMetrics()
			if latestState then
				self.update(latestState)
				if ctx.relayout then
					ctx.relayout()
				end
			end
		end
	end

	return self
end

return Welcome
