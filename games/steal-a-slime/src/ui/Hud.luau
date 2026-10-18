--!strict
--[[
	Hud

	Always-visible HUD (H1 / B4, see HudClusters / Layout.moneyCluster): bottom-left the money plate with a
	big coin and amount, the income/s and rebirths chips under it; bottom-right status icons with timers
	(Slime Rain from the workspace RainActive / RainEndsAt / RainNextAt attributes, else State.rain; the live
	server modifier; the friend boost). Hovering an icon with the mouse, or tapping it on touch, opens a tooltip
	(B8: name, what it does, time left); a second tap or a tap elsewhere closes it. A stack of banners at the
	top centre (hidden ones collapse): "your slime is being stolen", the Mystery Egg hatch and the events
	board. The top bar (lock block, Lock, Buy pad, Daily) is gone (B7), and so are the toasts (B6, init.client).
	`layout(screen)` from init.client places everything. No boss, rare-drop or weekend notices any more.
]]

local EggReveal = require(script.Parent.EggReveal)
local HudClusters = require(script.Parent.HudClusters)
local ItemIconView = require(script.Parent.ItemIconView)
local ItemIcons = require(script.Parent.ItemIcons)
local Layout = require(script.Parent.Layout)
local RainTimer = require(script.Parent.RainTimer)
local Widgets = require(script.Parent.Widgets)

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Theme = Widgets.Theme
local create = Widgets.create

local Hud = {}

-- A small rounded plate with an item icon at its left and a bold value label (sized by Hud.layout).
local function plate(parent: Instance, name: string, iconId: string, color: Color3, registry: any)
	local frame = create("Frame", {
		Name = name,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.05,
		Parent = parent,
	}, { Widgets.corner(12), Widgets.stroke(Color3.fromRGB(10, 10, 20), 2) })
	local icon = ItemIconView.new({
		Name = "Icon",
		Id = iconId,
		Size = 20,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Parent = frame,
	}, registry)
	icon.setActive(true)
	local value = Widgets.label({
		Name = "Value",
		Text = "-",
		Font = Theme.Font,
		TextSize = Layout.MONEY.chipSize,
		TextStrokeTransparency = 0.6,
		TextTruncate = Enum.TextTruncate.None,
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

function Hud.new(parent: Instance, ctx: any)
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
	}, { Widgets.corner(16), Widgets.stroke(Color3.fromRGB(10, 10, 20), 3) })
	local cashLabel = Widgets.label({
		Name = "Value",
		Text = "-",
		Font = Theme.Font,
		TextSize = Layout.MONEY.amountSize,
		TextStrokeTransparency = 0.4,
		TextTruncate = Enum.TextTruncate.None,
		Parent = cashPlate,
	})
	local coin = ItemIconView.new({
		Name = "Icon",
		Id = HudClusters.ICONS.Cash,
		Size = Layout.MONEY.icon,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Parent = cashPlate,
	}, registry)
	coin.setActive(true)
	local incomeChip, incomeIcon, incomeLabel =
		plate(moneyRoot, "Income", HudClusters.ICONS.Income, Color3.fromRGB(40, 120, 70), registry)
	local rebirthChip, rebirthIcon, rebirthLabel =
		plate(moneyRoot, "Rebirths", HudClusters.ICONS.Rebirths, Color3.fromRGB(70, 50, 140), registry)

	-- Bottom-right cluster (Layout.statusCluster): one pooled slot per HudClusters id, icon + timer under it.
	-- A slot is a button: hover / tap opens its tooltip.
	local statusRoot = create("Frame", {
		Name = "Status",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(Layout.statusWidth(false), Layout.statusHeight(false)),
		Parent = parent,
	})
	type Slot = { frame: TextButton, icon: any, label: TextLabel }
	local statusSlots: { [string]: Slot } = {}
	local shownSlots: { HudClusters.Slot } = {}
	for _, id in HudClusters.STATUS_IDS do
		local frame = create("TextButton", {
			Name = id,
			Visible = false,
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(Layout.STATUS.slot, Layout.statusHeight(false)),
			Parent = statusRoot,
		}) :: TextButton
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
			TextSize = Layout.STATUS.labelSize,
			TextStrokeTransparency = 0.2,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.None,
			Size = UDim2.new(1, 0, 0, Layout.STATUS.label),
			Position = UDim2.fromOffset(0, Layout.STATUS.icon + Layout.STATUS.labelGap),
			Parent = frame,
		})
		statusSlots[id] = { frame = frame, icon = icon, label = label }
	end

	-- Status tooltip (B8): name, effect and the live time left, over the open slot.
	local tip = create("Frame", {
		Name = "Tooltip",
		Visible = false,
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.04,
		ZIndex = Layout.ZINDEX.Banners,
		Parent = parent,
	}, { Widgets.corner(10), Widgets.stroke(Theme.Gold, 2) })
	local function tipLabel(name: string, size: number, color: Color3, font: Enum.Font): TextLabel
		return Widgets.label({
			Name = name,
			Font = font,
			TextSize = size,
			TextColor3 = color,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = Layout.ZINDEX.Banners,
			Parent = tip,
		})
	end
	local tipTitle = tipLabel("Title", Layout.TOOLTIP.titleSize, Theme.Gold, Theme.Font)
	local tipBody = tipLabel("Body", Layout.TOOLTIP.bodySize, Theme.Text, Theme.FontBody)
	local tipTime = tipLabel("Time", Layout.TOOLTIP.timeSize, Theme.Accent, Theme.Font)

	-- Banner stack at the top centre; hidden banners take no space.
	local banners = create("Frame", {
		Name = "Banners",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Layout.TOP),
		Size = UDim2.fromOffset(Layout.BANNER_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = Layout.ZINDEX.Banners,
		Parent = parent,
	}, { Widgets.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center) })
	local steal = banner(banners, "StealAlert", Theme.Bad, 1)
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
	}, registry)

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
	local current: any = nil
	local screen: Layout.Screen? = nil
	local compact = false
	local statusSig = "" -- signature of the status slots last drawn
	local tipId: string? = nil -- the status slot whose tooltip is open
	local slotRects: { [string]: Layout.Rect } = {} -- shown slots' boxes in design px, for the tap-elsewhere test

	local self = {}

	local function touchInput(): boolean
		return UserInputService:GetLastInputType() == Enum.UserInputType.Touch
	end

	-- Draws (or hides) the tooltip for `tipId` with the live timer; called on every open / close and tick.
	local function refreshTooltip()
		local slot: HudClusters.Slot? = nil
		for _, candidate in shownSlots do
			if candidate.id == tipId then
				slot = candidate
			end
		end
		if slot == nil or screen == nil or menuOpen then
			tip.Visible = false
			if slot == nil then
				tipId = nil
			end
			return
		end
		local text = HudClusters.tooltip(slot)
		local w, h, lines = Layout.tooltipBox(compact, text.title, text.body, text.time)
		local r = Layout.tooltipRect(screen, slotRects[slot.id], w, h)
		local t = Layout.TOOLTIP
		tip.Position = UDim2.fromOffset(math.round(r.x), math.round(r.y))
		tip.Size = UDim2.fromOffset(math.round(r.w), math.round(r.h))
		local inner = r.w - t.pad * 2
		local y = t.pad
		local rows: { { label: TextLabel, content: string, height: number } } = {
			{ label = tipTitle, content = text.title, height = lines.titleH },
			{ label = tipBody, content = text.body, height = lines.bodyH },
			{ label = tipTime, content = text.time, height = lines.timeH },
		}
		for _, row in rows do
			row.label.Text = row.content
			row.label.Position = UDim2.fromOffset(t.pad, y)
			row.label.Size = UDim2.fromOffset(inner, row.height)
			y += row.height + t.line
		end
		tipBody.TextSize = if compact then t.cbodySize else t.bodySize
		tip.Visible = true
	end

	local function setTooltip(id: string?)
		if id ~= tipId then
			tipId = id
			refreshTooltip()
		end
	end

	for id, entry in statusSlots do
		entry.frame.MouseEnter:Connect(function()
			setTooltip(HudClusters.nextTooltip(tipId, "hover", id, touchInput()))
		end)
		entry.frame.MouseLeave:Connect(function()
			setTooltip(HudClusters.nextTooltip(tipId, "leave", id, touchInput()))
		end)
		entry.frame.Activated:Connect(function()
			setTooltip(HudClusters.nextTooltip(tipId, "tap", id, touchInput()))
		end)
	end

	-- A press anywhere but on the open icon closes the tooltip (a tap on the icon itself is its Activated).
	UserInputService.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if tipId == nil or (kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch) then
			return
		end
		local s = screen
		local hit: string? = nil
		if s then
			local inset = GuiService:GetGuiInset()
			local x = (input.Position.X - inset.X) / s.scale
			local y = (input.Position.Y - inset.Y) / s.scale
			for id, r in slotRects do
				if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
					hit = id
				end
			end
		end
		setTooltip(HudClusters.nextTooltip(tipId, "press", hit, touchInput()))
	end)

	-- Apply a Layout.screen: the clusters' boxes, banner width, compact text sizes.
	function self.layout(s: Layout.Screen)
		screen = s
		compact = s.compact
		local M = Layout.MONEY
		cashLabel.TextSize = if compact then M.camountSize else M.amountSize
		for _, value in { incomeLabel, rebirthLabel } do
			value.TextSize = if compact then M.cchipSize else M.chipSize -- "$98.7T/s" fits a phone chip
		end
		local coinSize = if compact then M.cicon else M.icon
		coin.instance.Size = UDim2.fromOffset(coinSize, coinSize)
		-- Whole pixels (a phone's design width is fractional; UDim offsets are integers).
		local function whole(r: Layout.Rect): (number, number, number, number)
			return math.round(r.x), math.round(r.y), math.round(r.w), math.round(r.h)
		end
		local m = s.money
		local mx, my, mw, mh = whole(m.rect)
		moneyRoot.Position = UDim2.fromOffset(mx, my)
		moneyRoot.Size = UDim2.fromOffset(mw, mh)
		for _, entry in
			{
				{ cashPlate, m.cash, cashLabel, true },
				{ incomeChip, m.income, incomeLabel, false },
				{ rebirthChip, m.rebirths, rebirthLabel, false },
			}
		do
			local frame, r = entry[1] :: Frame, entry[2] :: Layout.Rect
			frame.Position = UDim2.fromOffset(math.round(r.x - m.rect.x), math.round(r.y - m.rect.y))
			frame.Size = UDim2.fromOffset(math.round(r.w), math.round(r.h))
			local left, width = Layout.moneyTextBox(r, entry[4] :: boolean, compact)
			local label = entry[3] :: TextLabel
			label.Position = UDim2.fromOffset(left, 0)
			label.Size = UDim2.fromOffset(width, math.round(r.h))
		end
		for _, icon in { incomeIcon, rebirthIcon } do
			local size = m.income.h - 6
			icon.instance.Size = UDim2.fromOffset(size, size)
		end
		local sx, sy, sw, sh = whole(s.status.rect)
		statusRoot.Position = UDim2.fromOffset(sx, sy)
		statusRoot.Size = UDim2.fromOffset(sw, sh)
		local S = Layout.STATUS
		local iconSize = if compact then S.cicon else S.icon
		for _, entry in statusSlots do
			entry.frame.Size = UDim2.fromOffset(Layout.statusSlotWidth(compact), s.status.rect.h)
			entry.icon.instance.Size = UDim2.fromOffset(iconSize, iconSize)
			entry.label.TextSize = if compact then S.clabelSize else S.labelSize
			entry.label.Size = UDim2.new(1, 0, 0, if compact then S.clabel else S.label)
			entry.label.Position = UDim2.fromOffset(0, iconSize + S.labelGap)
		end
		statusSig = "" -- re-pack the slots in the new boxes
		banners.Size = UDim2.fromOffset(math.round(s.banners.w), 0)
		banners.Position = UDim2.new(0.5, 0, 0, s.banners.y)
		if current then
			self.update(current)
		end
	end

	-- Height of the shown banner stack in layout px (the steal-alert arrow keeps under it).
	function self.bannerHeight(): number
		return if banners.Visible and screen then banners.AbsoluteSize.Y / screen.scale else 0
	end

	function self.update(state: any)
		current = state
		local money = HudClusters.money(state)
		cashLabel.Text = money.cash
		incomeLabel.Text = money.income
		rebirthLabel.Text = money.rebirths

		-- Steal alert: any of my slimes with stolenBy set.
		local thieves = {}
		for _, view in state.slimes do
			if view.stolenBy ~= nil then
				table.insert(thieves, `{view.slime.name} by {ctx.playerName(view.stolenBy)}`)
			end
		end
		steal.Visible = #thieves > 0
		if #thieves > 0 then
			steal.Text = `STOLEN! {table.concat(thieves, ", ")} - chase & hit them with your bat!`
		end

		self.tick(ctx.serverNow())
	end

	function self.tick(now: number)
		if current == nil then
			return
		end
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
			shownSlots = slots
			slotRects = {}
			for _, entry in statusSlots do
				entry.frame.Visible = false
			end
			for i, slot in slots do
				local entry = statusSlots[slot.id]
				if screen then
					local r = Layout.statusSlot(screen.status, i, #slots)
					slotRects[slot.id] = r
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
			refreshTooltip() -- the open slot's timer, or closed when its slot is gone
		end

		local eggText =
			EggReveal.banner(current.egg, now, ctx.Config.MYSTERY_EGG_REVEAL_SECONDS, ctx.Genome.displayName)
		egg.Visible = eggText ~= nil
		eggIcon.setActive(eggText ~= nil)
		if eggText then
			egg.Text = string.gsub(eggText, "^🥚 ", "")
		end
	end

	-- Studio only (PC watcher shot): opens the tooltip of a status slot id ("Rain" | "Event" | "Friend"); nil closes.
	function self.showTooltip(id: string?)
		setTooltip(id)
	end

	-- A menu card open hides the whole banner stack (MenuState.bannersVisible) and the tooltip:
	-- nothing can cover a card's title or X.
	function self.setMenuOpen(isOpen: boolean)
		if menuOpen ~= isOpen then
			menuOpen = isOpen
			banners.Visible = not menuOpen
			if menuOpen then
				tipId = nil
			end
			refreshTooltip()
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
