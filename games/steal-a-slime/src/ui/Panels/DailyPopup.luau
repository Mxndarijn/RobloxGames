--!strict
--[[
	Daily reward popup: a centred modal card (the shared Widgets.panel frame) with the streak
	track, today's amount and Claim (`Request("Daily")`). When the streak broke, a "Keep my streak" Robux button
	(ExclusiveShopView.streakQuickBuy) shares Claim's row. Opens by itself when a claim becomes
	available and the tutorial is done (PopupQueue, init.client) and from the HUD Daily button.
	Once the server reports it claimed, it shows "Claimed" and closes.
]]

local UI = script.Parent.Parent
local Daily = require(UI.Daily)
local ExclusiveShopView = require(UI.ExclusiveShopView)
local Format = require(UI.Format)
local ItemIconView = require(UI.ItemIconView)
local ItemIcons = require(UI.ItemIcons)
local Layout = require(UI.Layout)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local DailyPopup = {}

-- Body rows top to bottom (design px; the body is Layout.panelBody of a Layout.DAILY card).
-- Claim is pinned to the body's bottom edge.
DailyPopup.ROWS = table.freeze({
	top = { y = 0, h = 26, size = 15, chipSize = Layout.MIN_TEXT }, -- streak line + "Come back tomorrow" chip
	track = { y = 34, h = 70 },
	amount = { y = 110, h = 46, size = 40 },
	claimSize = 22,
})
-- One tile per streak day; the last (cap) day is LAST_WEIGHT times wider with a bigger pile.
DailyPopup.TILE = table.freeze({
	gap = 6,
	lastWeight = 1.6,
	labelY = 4,
	labelH = 17,
	labelSize = Layout.MIN_TEXT,
	lastLabelSize = 14,
	iconY = 22,
	icon = 24,
	lastIcon = 30,
	amountH = 16,
	amountInset = 5, -- amount line above the tile's bottom edge
	amountSize = Layout.MIN_TEXT,
	lastAmountSize = 15,
	minAmountSize = Layout.MIN_TEXT,
})
-- Share of the top line the chip may take; the streak line gets the rest.
DailyPopup.CHIP_SHARE = 0.58

-- The tile label: "Day N" for today and the last day, the bare number otherwise, empty once claimed (the
-- tile's check shows there instead).
function DailyPopup.dayLabel(day: number, state: string, cap: number): string
	if state == "claimed" then
		return ""
	end
	return if state == "today" or day == cap then `Day {day}` else tostring(day)
end

function DailyPopup.new(parent: Instance, ctx: any)
	local cap: number = ctx.Config.DAILY_STREAK_CAP or 7
	local rows = DailyPopup.ROWS
	local tile = DailyPopup.TILE
	local icons = ItemIcons.of(ctx)

	local backdrop = Widgets.backdrop({
		Name = "DailyPopup",
		Size = UDim2.fromScale(1, 1),
		ZIndex = Layout.ZINDEX.Daily, -- under the tutorial card
		Parent = parent,
	})

	local panel = Widgets.panel(backdrop, "Card", "Daily reward", "📅")
	local card = panel.frame
	card.Visible = true -- the backdrop shows and hides the popup
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(Layout.DAILY.w, Layout.DAILY.h)
	local body = panel.body

	local streakLine = Widgets.label({
		Name = "Streak",
		TextSize = rows.top.size,
		TextColor3 = Theme.Muted,
		Position = UDim2.fromOffset(0, rows.top.y),
		Size = UDim2.new(1 - DailyPopup.CHIP_SHARE, -tile.gap, 0, rows.top.h),
		Parent = body,
	})
	local chip = Widgets.chip({
		Name = "Tomorrow",
		TextSize = rows.top.chipSize,
		TextColor3 = Theme.Muted,
		TextScaled = true,
		AutomaticSize = Enum.AutomaticSize.None,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, rows.top.y),
		Size = UDim2.new(DailyPopup.CHIP_SHARE, 0, 0, rows.top.h),
		Visible = false,
		Parent = body,
	})
	create("UITextSizeConstraint", {
		MinTextSize = tile.minAmountSize,
		MaxTextSize = rows.top.chipSize,
		Parent = chip,
	})

	local weightSum = (cap - 1) + tile.lastWeight
	local track = create("Frame", {
		Name = "Track",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, rows.track.y),
		Size = UDim2.new(1, 0, 0, rows.track.h),
		Parent = body,
	}, { Widgets.list(Enum.FillDirection.Horizontal, tile.gap, Enum.HorizontalAlignment.Center) })
	type Tile = { frame: Frame, stroke: UIStroke, label: TextLabel, amount: TextLabel }
	-- A claimed tile's check, where its day label was (built the first time the day is claimed).
	local CLAIMED = table.freeze({
		Name = "Claimed",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, tile.labelY),
	})
	local tiles: { Tile } = {}
	for day = 1, cap do
		local last = day == cap
		local weight = if last then tile.lastWeight else 1
		local frame = Widgets.rowFrame({
			Name = `Day{day}`,
			LayoutOrder = day,
			Size = UDim2.new(weight / weightSum, -tile.gap, 1, 0),
			Parent = track,
		})
		Widgets.shade(frame)
		local label = Widgets.label({
			Name = "DayLabel",
			Text = DailyPopup.dayLabel(day, "upcoming", cap),
			Font = Theme.Font,
			TextSize = if last then tile.lastLabelSize else tile.labelSize,
			TextColor3 = Theme.Muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.None,
			Size = UDim2.new(1, 0, 0, tile.labelH),
			Position = UDim2.fromOffset(0, tile.labelY),
			Parent = frame,
		})
		local iconSize = if last then tile.lastIcon else tile.icon
		ItemIconView.new({
			Name = `Day{day}Icon`,
			Id = "Cash",
			Size = iconSize,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, tile.iconY + (tile.icon - iconSize) / 2),
			Parent = frame,
		}, icons).setActive(true)
		local amount = Widgets.label({
			Name = "DayAmount",
			Font = Theme.Font,
			TextSize = if last then tile.lastAmountSize else tile.amountSize,
			TextScaled = true,
			TextColor3 = Theme.Gold,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, -4, 0, tile.amountH),
			Position = UDim2.new(0, 2, 1, -(tile.amountH + tile.amountInset)),
			Parent = frame,
		})
		create("UITextSizeConstraint", {
			MinTextSize = tile.minAmountSize,
			MaxTextSize = if last then tile.lastAmountSize else tile.amountSize,
			Parent = amount,
		})
		tiles[day] = {
			frame = frame,
			stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke,
			label = label,
			amount = amount,
		}
	end

	local amount = Widgets.label({
		Name = "Amount",
		Font = Theme.Font,
		TextSize = rows.amount.size,
		TextColor3 = Theme.Gold,
		TextStrokeColor3 = Theme.Ink,
		TextStrokeTransparency = 0,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, rows.amount.y),
		Size = UDim2.new(1, 0, 0, rows.amount.h),
		Parent = body,
	})

	local claim = Widgets.button(
		{
			Name = "Claim",
			Text = "Claim",
			TextSize = rows.claimSize,
			Position = UDim2.new(0, 0, 1, -Layout.BUTTON),
			Size = UDim2.new(1, 0, 0, Layout.BUTTON),
		},
		Theme.Gold,
		function()
			ctx.send("Daily")
		end
	)
	claim.instance.Parent = body

	-- "Keep my streak · R$25": half of Claim's row while State says the streak broke.
	local keepGap = 8
	local latestState: any = nil
	local keep = Widgets.button(
		{
			Name = "KeepStreak",
			TextSize = rows.claimSize,
			Position = UDim2.new(0.5, keepGap / 2, 1, -Layout.BUTTON),
			Size = UDim2.new(0.5, -keepGap / 2, 0, Layout.BUTTON),
			Visible = false,
		},
		Theme.Plum,
		function()
			local q = ExclusiveShopView.streakQuickBuy(latestState, ctx.Config)
			if q and q.mode == "buy" and q.purchase and ctx.purchase then
				ctx.purchase.prompt(q.purchase)
			end
		end
	)
	keep.instance.Parent = body

	local self = { frame = backdrop }

	panel.close.Activated:Connect(function()
		self.close()
	end)

	local closeToken = 0

	function self.open()
		closeToken += 1
		backdrop.Visible = true
	end

	function self.close()
		closeToken += 1
		backdrop.Visible = false
	end

	-- Card size from Layout.screen (narrower on small screens).
	-- `guiInset` (GuiService:GetGuiInset) lets the dim reach under the Roblox top bar, like the menu backdrop.
	function self.layout(screen: Layout.Screen, guiInset: Vector2?)
		local back = Layout.backdrop(screen, if guiInset then guiInset.X else 0, if guiInset then guiInset.Y else 0)
		backdrop.Position = UDim2.fromOffset(back.x, back.y)
		backdrop.Size = UDim2.fromOffset(back.w, back.h)
		card.Size = UDim2.fromOffset(screen.daily.w, screen.daily.h)
	end

	function self.isOpen(): boolean
		return backdrop.Visible
	end

	local wasAvailable: boolean? = nil

	function self.update(state: any)
		local daily = state.daily
		if type(daily) ~= "table" then
			return
		end
		local available = daily.available == true
		local base: number = ctx.Config.DAILY_BASE or 0
		local mult: number = state.rebirthMultiplier or 1
		local day = Daily.dayOf(daily, base, mult, cap)
		for _, c in Daily.track(day, cap, available) do
			local t = tiles[c.day]
			if t then
				local today = c.state == "today"
				local fill = if today then Theme.Gold else Theme.Row
				t.frame.BackgroundColor3 = fill
				t.stroke.Thickness = if today then Widgets.KIT.stroke else Widgets.KIT.rowStroke
				t.label.Text = DailyPopup.dayLabel(c.day, c.state, cap)
				Widgets.showCheck(t.frame, c.state == "claimed", tile.labelH, CLAIMED)
				t.amount.Text = Format.formatCash(Daily.reward(c.day, base, mult))
				if today then
					Widgets.inkOn(t.label, fill)
					Widgets.inkOn(t.amount, fill)
				else
					t.label.TextColor3 = if c.state == "claimed" then Theme.Good else Theme.Muted
					t.amount.TextColor3 = if c.state == "claimed" then Theme.Muted else Theme.Gold
				end
			end
		end
		streakLine.Text = if available
			then `Day {day} of your streak`
			else `Streak: {daily.streak} day{if daily.streak == 1 then "" else "s"}`
		local tomorrow = if base > 0 then Daily.reward(math.min(day + 1, cap), base, mult) else 0
		chip.Text = `Come back tomorrow for {Format.formatCash(tomorrow)}`
		chip.Visible = tomorrow > 0
		amount.Text = if available then `+{Format.formatCash(daily.amount)}` else "Claimed"
		claim.setEnabled(available)
		claim.setText(if available then "Claim" else "Claimed")
		latestState = state
		local q = if available then ExclusiveShopView.streakQuickBuy(state, ctx.Config) else nil
		keep.instance.Visible = q ~= nil
		if q then
			keep.setText(q.text)
			keep.setEnabled(q.mode == "buy" and ctx.purchase ~= nil)
		end
		claim.instance.Size = if q
			then UDim2.new(0.5, -keepGap / 2, 0, Layout.BUTTON)
			else UDim2.new(1, 0, 0, Layout.BUTTON)

		if wasAvailable == true and not available and backdrop.Visible then
			-- Just claimed: let the "Claimed!" state show, then close.
			closeToken += 1
			local token = closeToken
			task.delay(1.5, function()
				if token == closeToken then
					backdrop.Visible = false
				end
			end)
		end
		wasAvailable = available
	end

	Widgets.closeOnTapOutside(backdrop, function()
		return { card }
	end, function()
		self.close()
	end)

	return self
end

return DailyPopup
