--!strict
--[[
	Hud

	Always-visible top bar (H1 HUD, see HudClusters / Layout.moneyCluster): a large lock block (LockHud) +
	Lock button, Buy-next-pad and Daily (opens the daily popup). Items are placed from Layout.hud (one
	row on desktop, two on a phone, one on a landscape phone; `layout(screen)` from init.client). A stack
	of banners below it (hidden ones collapse): "your slime is being stolen", the Mystery Egg hatch, the
	events board and a "plot full" hint. Bottom-left: the money plate with the income/s and rebirths chips;
	bottom-right: status icons with timers (Slime Rain from the workspace RainActive / RainEndsAt /
	RainNextAt attributes, else State.rain; the live server modifier; the friend boost). No boss, rare-drop
	or weekend notices any more.
]]

local EggReveal = require(script.Parent.EggReveal)
local EventsBoard = require(script.Parent.EventsBoard)
local HudClusters = require(script.Parent.HudClusters)
local ItemIconView = require(script.Parent.ItemIconView)
local ItemIcons = require(script.Parent.ItemIcons)
local Layout = require(script.Parent.Layout)
local LockHud = require(script.Parent.LockHud)
local RainTimer = require(script.Parent.RainTimer)
local Tutorial = require(script.Parent.Tutorial)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Hud = {}

-- A small rounded plate with an item icon at its left and a bold value label.
local function plate(parent: Instance, name: string, iconId: string, color: Color3, registry: any)
	local frame = create("Frame", {
		Name = name,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.05,
		Parent = parent,
	}, { Widgets.corner(10), Widgets.stroke(Color3.fromRGB(10, 10, 20), 2) })
	local icon = ItemIconView.new({
		Name = "Icon",
		Id = iconId,
		Size = 20,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Parent = frame,
	}, registry)
	icon.setActive(true)
	local value = Widgets.label({
		Name = "Value",
		Text = "-",
		Font = Theme.Font,
		TextSize = 13,
		TextStrokeTransparency = 0.6,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.new(1, -30, 1, 0),
		Position = UDim2.fromOffset(28, 0),
		Parent = frame,
	})
	return frame, icon, value
end

-- Banners wrap and grow taller instead of truncating (v15: the boss
-- countdown was cut off).
local function banner(parent: Instance, name: string, color: Color3, order: number): TextLabel
	local label = Widgets.label({
		Name = name,
		Visible = false,
		LayoutOrder = order,
		BackgroundTransparency = 0.1,
		BackgroundColor3 = color,
		Font = Theme.Font,
		TextSize = 18,
		TextStrokeTransparency = 0.5,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.new(1, 0, 0, 34), -- the Banners frame width (Layout: narrower on phones)
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	})
	Widgets.corner(8).Parent = label
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		Parent = label,
	})
	return label
end

local LOCK_COLORS = {
	locked = Color3.fromRGB(40, 140, 80),
	low = Color3.fromRGB(220, 150, 30),
	open = Color3.fromRGB(200, 50, 70),
}

function Hud.new(parent: Instance, ctx: any)
	local bar = create("Frame", {
		Name = "Hud",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Layout.TOP),
		Size = UDim2.fromOffset(0, 72),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.1,
		Parent = parent,
	}, { Widgets.corner(12) })

	-- Layout.HUD_ITEMS name -> its frame / button in the bar.
	local items: { [string]: GuiObject } = {}
	local registry = ItemIcons.of(ctx)

	-- Bottom-left cluster (Layout.moneyCluster): coin + big amount, income/s and rebirths chips under it.
	local moneyRoot = create("Frame", {
		Name = "Money",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(Layout.MONEY.w, Layout.moneyHeight(false)),
		Parent = parent,
	})
	local cashPlate = create("Frame", {
		Name = "Cash",
		BackgroundColor3 = Color3.fromRGB(58, 36, 110),
		Parent = moneyRoot,
	}, { Widgets.corner(14), Widgets.stroke(Color3.fromRGB(10, 10, 20), 2) })
	local COIN = Layout.MONEY.icon
	local cashLabel = Widgets.label({
		Name = "Value",
		Text = "-",
		Font = Theme.Font,
		TextSize = 26,
		TextStrokeTransparency = 0.5,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.new(1, -(COIN + 18), 1, 0),
		Position = UDim2.fromOffset(COIN + 12, 0),
		Parent = cashPlate,
	})
	local coin = ItemIconView.new({
		Name = "Icon",
		Id = HudClusters.ICONS.Cash,
		Size = COIN,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Parent = cashPlate,
	}, registry)
	coin.setActive(true)
	local incomeChip, _, incomeLabel =
		plate(moneyRoot, "Income", HudClusters.ICONS.Income, Color3.fromRGB(40, 120, 70), registry)
	local rebirthChip, _, rebirthLabel =
		plate(moneyRoot, "Rebirths", HudClusters.ICONS.Rebirths, Color3.fromRGB(70, 50, 140), registry)

	-- Bottom-right cluster (Layout.statusCluster): one pooled slot per HudClusters id, icon + timer under it.
	local statusRoot = create("Frame", {
		Name = "Status",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(Layout.statusWidth(), Layout.STATUS.h),
		Parent = parent,
	})
	local statusSlots: { [string]: { frame: Frame, icon: any, label: TextLabel } } = {}
	for _, id in HudClusters.STATUS_IDS do
		local frame = create("Frame", {
			Name = id,
			Visible = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(Layout.STATUS.slot, Layout.STATUS.h),
			Parent = statusRoot,
		})
		local icon = ItemIconView.new({
			Name = "Icon",
			Size = Layout.STATUS.icon,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Parent = frame,
		}, registry)
		local label = Widgets.label({
			Name = "Timer",
			Font = Theme.Font,
			TextSize = 13,
			TextStrokeTransparency = 0.4,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.None,
			Size = UDim2.new(1, 0, 0, 18),
			Position = UDim2.fromOffset(0, Layout.STATUS.icon + 4),
			Parent = frame,
		})
		statusSlots[id] = { frame = frame, icon = icon, label = label }
	end

	-- Lock block: the most important safety signal, so big and coloured.
	local lockBox = create("Frame", {
		Name = "LockStatus",
		Size = UDim2.fromOffset(200, 56),
		BackgroundColor3 = LOCK_COLORS.open,
		Parent = bar,
	}, { Widgets.corner(10), Widgets.stroke(Color3.new(1, 1, 1), 2) })
	local lockTitle = Widgets.label({
		Name = "Title",
		Text = "-",
		Font = Theme.Font,
		TextSize = 20,
		TextStrokeTransparency = 0.4,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -8, 0, 24),
		Position = UDim2.fromOffset(4, 4),
		Parent = lockBox,
	})
	local lockSub = Widgets.label({
		Name = "Sub",
		Text = "",
		Font = Theme.Font,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -8, 0, 14),
		Position = UDim2.fromOffset(4, 28),
		Parent = lockBox,
	})
	local _, setLockBar = Widgets.bar(lockBox, Color3.new(1, 1, 1), UDim2.new(1, -16, 0, 6), UDim2.new(0, 8, 1, -10))
	items.LockStatus = lockBox

	local lockBtn = Widgets.holdButton(
		{ Name = "Lock", Text = "Lock", Size = UDim2.fromOffset(130, Layout.BUTTON), TextSize = 16 },
		Theme.Info,
		function()
			ctx.send("Lock")
		end,
		ctx.Config.HOLD_CONFIRM_SECONDS
	)
	lockBtn.instance.Parent = bar
	-- The Lock gear's item icon in the button's left padding (LockHud text drops its lock emoji).
	local LOCK_ICON = 24
	create("UIPadding", { PaddingLeft = UDim.new(0, LOCK_ICON + 6), Parent = lockBtn.instance })
	ItemIconView.new({
		Name = "LockIcon",
		Id = "Lock",
		Size = LOCK_ICON,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -(LOCK_ICON + 4), 0.5, 0),
		Parent = lockBtn.instance,
	}, ItemIcons.of(ctx)).setActive(true)
	items.Lock = lockBtn.instance

	local padBtn = Widgets.holdButton(
		{ Name = "BuyPad", Text = "Buy next pad", Size = UDim2.fromOffset(160, Layout.BUTTON), TextSize = 15 },
		Theme.Good,
		function()
			ctx.send("BuyPad")
		end,
		ctx.Config.HOLD_CONFIRM_SECONDS
	)
	padBtn.instance.Parent = bar
	items.BuyPad = padBtn.instance

	local dailyBtn = Widgets.button(
		{ Name = "Daily", Text = "Daily", Size = UDim2.fromOffset(120, Layout.BUTTON) },
		Theme.Gold,
		function()
			ctx.openDaily()
		end
	)
	dailyBtn.instance.TextColor3 = Color3.fromRGB(40, 30, 10)
	dailyBtn.instance.Parent = bar
	items.Daily = dailyBtn.instance

	-- Banner stack under the bar; hidden banners take no space.
	local banners = create("Frame", {
		Name = "Banners",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 88),
		Size = UDim2.fromOffset(Layout.BANNER_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = Layout.ZINDEX.Banners,
		Parent = parent,
	}, { Widgets.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center) })
	local steal = banner(banners, "StealAlert", Theme.Bad, 1)
	-- The events board: one icon + text row per event (EventsBoard.rows); rows are pooled, content-sized.
	local board = create("Frame", {
		Name = "EventsBoard",
		Visible = false,
		LayoutOrder = 9,
		BackgroundTransparency = 0.1,
		BackgroundColor3 = Color3.fromRGB(40, 70, 120),
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = Layout.ZINDEX.Banners,
		Parent = banners,
	}, {
		Widgets.corner(8),
		Widgets.list(Enum.FillDirection.Vertical, 3, Enum.HorizontalAlignment.Left),
		create("UIPadding", {
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 4),
		}),
	})
	local BOARD_ICON = 22
	local boardRows: { { frame: Frame, icon: any, label: TextLabel } } = {}
	local function setBoardRows(rows: { EventsBoard.Row }?)
		for i, row in rows or {} do
			local pooled = boardRows[i]
			if not pooled then
				local frame = create("Frame", {
					Name = `Row{i}`,
					LayoutOrder = i,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, BOARD_ICON),
					AutomaticSize = Enum.AutomaticSize.Y,
					ZIndex = Layout.ZINDEX.Banners,
					Parent = board,
				})
				local icon = ItemIconView.new({
					Name = "Icon",
					Id = row.icon,
					Size = BOARD_ICON,
					ZIndex = Layout.ZINDEX.Banners,
					Parent = frame,
				}, ItemIcons.of(ctx))
				icon.setActive(true)
				local label = Widgets.label({
					Name = "Text",
					Font = Theme.Font,
					TextSize = 14,
					TextWrapped = true,
					TextTruncate = Enum.TextTruncate.None,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextStrokeTransparency = 0.5,
					Size = UDim2.new(1, -(BOARD_ICON + 6), 0, BOARD_ICON),
					Position = UDim2.fromOffset(BOARD_ICON + 6, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					ZIndex = Layout.ZINDEX.Banners,
					Parent = frame,
				})
				pooled = { frame = frame, icon = icon, label = label }
				boardRows[i] = pooled
			end
			local entry = pooled :: any
			if entry.frame:GetAttribute("IconId") ~= row.icon then
				entry.frame:SetAttribute("IconId", row.icon)
				entry.icon.set(row.icon)
				entry.icon.setActive(true)
			end
			entry.label.Text = row.text
			entry.frame.Visible = true
		end
		for i = #(rows or {}) + 1, #boardRows do
			boardRows[i].frame.Visible = false
		end
	end
	local egg = banner(banners, "EggReveal", Color3.fromRGB(190, 120, 30), 6)
	egg.TextSize = 17
	-- The Mystery Egg's item icon sits at the banner's left edge (the text drops its egg emoji).
	local EGG_ICON = 28
	local eggPad = egg:FindFirstChildOfClass("UIPadding") :: UIPadding
	eggPad.PaddingLeft = UDim.new(0, 10 + EGG_ICON + 6)
	local eggIcon = ItemIconView.new({
		Name = "EggIcon",
		Id = "MysteryEgg",
		Size = EGG_ICON,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -(EGG_ICON + 6), 0.5, 0),
		Parent = egg,
	}, ItemIcons.of(ctx))
	local hint = banner(banners, "PadHint", Color3.fromRGB(150, 100, 20), 4)
	hint.TextSize = 16

	-- Workspace rain attributes, kept fresh by change signals (read in tick).
	local rainAttrs: RainTimer.Rain? = nil
	local menuOpen = false -- set by init.client via setMenuOpen
	local function readRainAttrs()
		rainAttrs = RainTimer.fromAttributes(
			workspace:GetAttribute("RainActive"),
			workspace:GetAttribute("RainEndsAt"),
			workspace:GetAttribute("RainNextAt")
		)
	end
	readRainAttrs()
	local C = ctx.Constants

	local current: any = nil
	local screen: Layout.Screen? = nil
	local compact = false
	-- HUD item visibility last laid out (Layout.hud skips hidden items).
	local shown: { [string]: boolean } = {}
	local laidOut: Layout.HudLayout? = nil
	local statusSig = "" -- signature of the status slots last drawn

	local function relayout()
		if screen == nil then
			return
		end
		local hud = Layout.hud(screen.width, compact, shown, screen.short)
		laidOut = hud
		bar.Size = UDim2.fromOffset(hud.rect.w, hud.rect.h)
		for name, item in items do
			local r = hud.items[name]
			item.Visible = r ~= nil
			if r then
				item.Position = UDim2.fromOffset(r.x - hud.rect.x, r.y - hud.rect.y)
				item.Size = UDim2.fromOffset(r.w, r.h)
			end
		end
	end

	local function setShown(name: string, visible: boolean)
		if shown[name] ~= visible then
			shown[name] = visible
			relayout()
		end
	end

	local self = {}

	-- Apply a Layout.screen: HUD rows, banner width, compact text sizes.
	function self.layout(s: Layout.Screen)
		screen = s
		compact = s.compact
		lockTitle.TextSize = if compact then 18 else 20
		lockSub.TextSize = if compact then 11 else 12
		lockBtn.instance.TextSize = if compact then 13 else 16
		cashLabel.TextSize = if compact then 22 else 26
		for _, value in { incomeLabel, rebirthLabel } do
			value.TextSize = if compact then 12 else 13 -- "$98.7T/s" fits a phone chip
		end
		-- Whole pixels (a phone's design width is fractional; UDim offsets are integers).
		local function whole(r: Layout.Rect): (number, number, number, number)
			return math.round(r.x), math.round(r.y), math.round(r.w), math.round(r.h)
		end
		local m = s.money
		local mx, my, mw, mh = whole(m.rect)
		moneyRoot.Position = UDim2.fromOffset(mx, my)
		moneyRoot.Size = UDim2.fromOffset(mw, mh)
		for _, entry in { { cashPlate, m.cash }, { incomeChip, m.income }, { rebirthChip, m.rebirths } } do
			local frame, r = entry[1] :: Frame, entry[2] :: Layout.Rect
			frame.Position = UDim2.fromOffset(math.round(r.x - m.rect.x), math.round(r.y - m.rect.y))
			frame.Size = UDim2.fromOffset(math.round(r.w), math.round(r.h))
		end
		local sx, sy, sw, sh = whole(s.status.rect)
		statusRoot.Position = UDim2.fromOffset(sx, sy)
		statusRoot.Size = UDim2.fromOffset(sw, sh)
		statusSig = "" -- re-pack the slots in the new boxes
		banners.Size = UDim2.fromOffset(s.banners.w, 0)
		banners.Position = UDim2.new(0.5, 0, 0, s.banners.y)
		relayout()
		if current then
			self.update(current)
		end
	end

	-- The HUD boxes as shown now (hidden items missing), for the hint ring.
	-- Height of the shown banner stack in layout px (toasts start below it when they share its columns).
	function self.bannerHeight(): number
		return if banners.Visible and screen then banners.AbsoluteSize.Y / screen.scale else 0
	end

	function self.hudLayout(): Layout.HudLayout?
		return laidOut
	end

	function self.update(state: any)
		current = state
		local money = HudClusters.money(state)
		cashLabel.Text = money.cash
		incomeLabel.Text = money.income
		rebirthLabel.Text = money.rebirths

		local pad = LockHud.padButton(state, compact)
		setShown("BuyPad", pad.visible)
		padBtn.setText(pad.text)
		padBtn.setColor(if not pad.enabled then Theme.Disabled elseif pad.urgent then Theme.Warn else Theme.Good)
		hint.Visible = pad.hint ~= nil
		hint.Text = pad.hint or ""

		local daily = LockHud.dailyButton(state.daily, Tutorial.fromState(state) ~= nil, compact)
		setShown("Daily", daily.visible)
		dailyBtn.setText(daily.text)

		-- Steal alert: any of my slimes with stolenBy set.
		local thieves = {}
		for _, view in state.slimes do
			if view.stolenBy ~= nil then
				table.insert(thieves, `{view.slime.name} by {ctx.playerName(view.stolenBy)}`)
			end
		end
		steal.Visible = #thieves > 0
		if #thieves > 0 then
			steal.Text = `STOLEN! {table.concat(thieves, ", ")} - chase & slap!`
		end

		self.tick(ctx.serverNow())
	end

	function self.tick(now: number)
		if current == nil then
			return
		end
		local maxLock = ctx.Config.LOCK_MAX_REMAINING
		local status = LockHud.status(current.lockUntil, now, maxLock, current.lockStartedAt)
		lockTitle.Text = status.title
		lockSub.Text = status.sub
		setLockBar(status.fraction)
		-- Open / ending: blink the block so it can't be missed.
		local blink = status.level ~= "locked" and (now * 2) % 2 < 1
		lockBox.BackgroundColor3 = LOCK_COLORS[status.level]:Lerp(Color3.new(1, 1, 1), if blink then 0.25 else 0)

		local lockView = LockHud.lockButton(current, now, maxLock)
		local lockText = string.gsub(lockView.text, "^🔒 ", "")
		lockBtn.setText((string.gsub(lockText, "^🔓 ", "")))
		lockBtn.setColor(if lockView.enabled then Theme.Info else Theme.Disabled)

		readRainAttrs()
		-- Bottom-right status slots: rebuilt only when a slot's icon / text changes (about 1 Hz for a countdown).
		local slots = HudClusters.status({
			rain = ctx.forcedRain and ctx.forcedRain(now) or RainTimer.resolve(rainAttrs, current.rain),
			modifier = current.modifier,
			modifierEnabled = ctx.Config.FEATURES.CycleModifier == true,
			friends = current.friends,
			friendsEnabled = ctx.Config.FEATURES.FriendBonus == true,
		}, now)
		local parts = {}
		for _, slot in slots do
			table.insert(parts, `{slot.id}|{slot.icon}|{slot.text}|{slot.kind}`)
		end
		local sig = table.concat(parts, ";")
		if sig ~= statusSig then
			statusSig = sig
			for _, entry in statusSlots do
				entry.frame.Visible = false
			end
			for i, slot in slots do
				local entry = statusSlots[slot.id]
				if screen then
					local r = Layout.statusSlot(screen.status, i, #slots)
					entry.frame.Position =
						UDim2.fromOffset(math.round(r.x - screen.status.rect.x), math.round(r.y - screen.status.rect.y))
				end
				if entry.frame:GetAttribute("IconId") ~= slot.icon then
					entry.frame:SetAttribute("IconId", slot.icon)
					entry.icon.set(slot.icon)
					entry.icon.setActive(true)
				end
				entry.label.Text = slot.text
				entry.label.TextColor3 = if slot.kind == "soon" then Theme.Muted else Theme.Text
				entry.frame:SetAttribute("Kind", slot.kind)
				entry.frame.Visible = true
			end
		end

		local eggText =
			EggReveal.banner(current.egg, now, ctx.Config.MYSTERY_EGG_REVEAL_SECONDS, ctx.Genome.displayName)
		egg.Visible = eggText ~= nil
		eggIcon.setActive(eggText ~= nil)
		if eggText then
			egg.Text = string.gsub(eggText, "^🥚 ", "")
		end

		local eventRows = EventsBoard.rows(
			workspace:GetAttribute(C.WEEKLY_EVENT_ATTRIBUTE),
			current.modifier,
			now,
			now,
			ctx.Config.FEATURES.EventsBoard == true
		)
		board.Visible = eventRows ~= nil
		setBoardRows(eventRows)
	end

	-- A menu card open hides the whole banner stack (MenuState.bannersVisible):
	-- no banner can cover a card's title or X.
	function self.setMenuOpen(isOpen: boolean)
		if menuOpen ~= isOpen then
			menuOpen = isOpen
			banners.Visible = not menuOpen
		end
	end

	for _, name in RainTimer.ATTRIBUTES do
		workspace:GetAttributeChangedSignal(name):Connect(function()
			readRainAttrs()
			self.tick(ctx.serverNow())
		end)
	end

	return self
end

return Hud
