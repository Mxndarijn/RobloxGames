--!strict
--[[
	Hud

	Always-visible HUD (H1 / B4, see HudClusters / Layout.moneyCluster): bottom-left the money plate with a
	big coin and amount, the income/s and rebirths chips under it; bottom-right status icons with timers
	in a pill tucked onto each icon's bottom edge (Slime Rain from the workspace RainActive / RainEndsAt /
	RainNextAt attributes, else State.rain; the live server modifier; the friend boost; the ritual's Blessed boost, State.blessed; this week's featured
	event Secret, State.featuredSecret). Hovering an icon with the mouse, or tapping it on touch, opens a tooltip
	(B8: name, what it does, time left); a second tap or a tap elsewhere closes it. A stack of banners at the
	top centre (hidden ones collapse): "your slime is being stolen" and the Mystery Egg hatch. The top bar (lock block, Lock, Buy pad, Daily) is gone (B7), and so are the toasts (B6, init.client).
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

-- Money block palette (Merijn's reference money_block_reference.png): chunky cartoon, bold dark outlines.
local INK = Color3.fromRGB(30, 18, 51) -- outlines, chip text, the "$"
local PILL = Color3.fromRGB(59, 36, 102)
local AMOUNT = Color3.fromRGB(255, 217, 59)
local COIN = Color3.fromRGB(247, 196, 40)
local COIN_SHADE = Color3.fromRGB(196, 135, 14)
local GREEN = Color3.fromRGB(126, 217, 87)
local LILAC = Color3.fromRGB(169, 139, 240)
local BADGE = Color3.fromRGB(43, 27, 77)
local CHUNKY = Enum.Font.FredokaOne

-- A top-light to bottom-dark UIGradient for depth. A UIGradient multiplies the frame's own colour, so the
-- two stops are grey brightness factors (1 = the colour as is), not colours.
local function shade(parent: Instance, top: number, bottom: number)
	create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(top, top, top), Color3.new(bottom, bottom, bottom)),
		Parent = parent,
	})
end

-- A rounded chip (outlined, shaded) that Hud.layout sizes; `label` is its dark chunky text.
local function chip(parent: Instance, name: string, color: Color3)
	local frame = create("Frame", {
		Name = name,
		BackgroundColor3 = color,
		ZIndex = 2,
		Parent = parent,
	}, { Widgets.corner(8) })
	shade(frame, 1, 0.82)
	local stroke = Widgets.stroke(INK, 3)
	stroke.Parent = frame
	local value = Widgets.label({
		Name = "Value",
		Text = "-",
		Font = CHUNKY,
		TextColor3 = INK,
		TextSize = Layout.MONEY.chipSize,
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = 3,
		Parent = frame,
	})
	return frame, value, stroke
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

	-- Bottom-left cluster (Layout.moneyCluster, the reference money block): a round gold coin over the left end
	-- of a long dark purple pill with the amount; under it the green income/s chip (with a tab pointing down)
	-- and the wider lilac rebirths chip (emblem, count, "xN" badge) tucked up under the pill's bottom edge.
	local moneyRoot = create("Frame", {
		Name = "Money",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(Layout.MONEY.w, Layout.moneyHeight(false)),
		Parent = parent,
	})
	local cashPlate = create("Frame", {
		Name = "Cash",
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = moneyRoot,
	})
	local pill = create("Frame", {
		Name = "Pill",
		BackgroundColor3 = PILL,
		Parent = cashPlate,
	}, { create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	shade(pill, 1, 0.8)
	local pillStroke = Widgets.stroke(INK, 4)
	pillStroke.Parent = pill
	local cashLabel = Widgets.label({
		Name = "Value",
		Text = "-",
		Font = CHUNKY,
		TextColor3 = AMOUNT,
		TextSize = Layout.MONEY.amountSize,
		TextStrokeColor3 = INK,
		TextStrokeTransparency = 0,
		TextTruncate = Enum.TextTruncate.None,
		ZIndex = 2,
		Parent = cashPlate,
	})
	-- No coin picture exists (the "Cash" icon is a pile), so the coin is drawn: a darker disc under the face
	-- gives the 3D edge, the face has a lighter top, a ring and the dark "$".
	local coin = create("Frame", {
		Name = "Icon",
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = cashPlate,
	})
	local coinEdge = create("Frame", {
		Name = "Edge",
		BackgroundColor3 = COIN_SHADE,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = coin,
	}, { create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local coinEdgeStroke = Widgets.stroke(INK, 4)
	coinEdgeStroke.Parent = coinEdge
	local coinFace = create("Frame", {
		Name = "Face",
		BackgroundColor3 = COIN,
		ZIndex = 4,
		Parent = coin,
	}, { create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	shade(coinFace, 1, 0.88)
	local coinRing = create("Frame", {
		Name = "Ring",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.72, 0.72),
		ZIndex = 5,
		Parent = coinFace,
	}, { create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	Widgets.stroke(COIN_SHADE, 2).Parent = coinRing
	local coinSign = Widgets.label({
		Name = "Sign",
		Text = "$",
		Font = CHUNKY,
		TextColor3 = INK,
		TextSize = 40,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
		Parent = coinFace,
	})
	local incomeTab = create("Frame", {
		Name = "IncomeTab",
		BackgroundColor3 = GREEN,
		ZIndex = 1,
		Parent = moneyRoot,
	}, { create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	local incomeTabStroke = Widgets.stroke(INK, 3)
	incomeTabStroke.Parent = incomeTab
	local incomeChip, incomeLabel, incomeStroke = chip(moneyRoot, "Income", GREEN)
	local rebirthChip, rebirthLabel, rebirthStroke = chip(moneyRoot, "Rebirths", LILAC)
	incomeLabel.TextXAlignment = Enum.TextXAlignment.Center
	-- The rebirth emblem: no tile, filling the chip's height at its left end.
	local rebirthIcon = ItemIconView.new({
		Name = "Icon",
		Id = HudClusters.ICONS.Rebirths,
		Size = 20,
		Bare = true,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		ZIndex = 3,
		Parent = rebirthChip,
	}, registry)
	rebirthLabel.TextXAlignment = Enum.TextXAlignment.Center
	rebirthIcon.setActive(true)
	local badge = create("Frame", {
		Name = "Multiplier",
		BackgroundColor3 = BADGE,
		AnchorPoint = Vector2.new(1, 0.5),
		ZIndex = 3,
		Parent = rebirthChip,
	}, { Widgets.corner(6) })
	local badgeStroke = Widgets.stroke(INK, 2)
	badgeStroke.Parent = badge
	local badgeLabel = Widgets.label({
		Name = "Value",
		Text = "x1",
		Font = CHUNKY,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = badge,
	})

	-- Bottom-right cluster (Layout.statusCluster): one pooled slot per HudClusters id, icon + timer pill on its
	-- bottom edge (Layout.statusMetrics; the pill is created after the icon, so it draws over it).
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
		local sm = Layout.statusMetrics(false)
		local label = Widgets.label({
			Name = "Timer",
			Font = Theme.Font,
			TextSize = sm.textSize,
			TextStrokeTransparency = 0.6,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.None,
			BackgroundColor3 = Theme.Bg,
			BackgroundTransparency = 0.12,
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromOffset(sm.slot, sm.pill),
			Position = UDim2.new(0.5, 0, 0, sm.icon - sm.overlap),
			Parent = frame,
		})
		create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = label })
		Widgets.stroke(Theme.BgLight, 1.5).Parent = label
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
	local statusTight = false -- the status slots use Layout.STATUS_TIGHT sizes
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
		local tight = s.tight
		local T = Layout.MONEY_TIGHT
		cashLabel.TextSize = if tight then T.amountSize elseif compact then M.camountSize else M.amountSize
		local chipText = if tight then T.chipSize elseif compact then M.cchipSize else M.chipSize
		incomeLabel.TextSize = chipText -- "$98.7T/s" fits a phone chip
		local rb = Layout.moneyRebirth(compact, tight)
		rebirthLabel.TextSize = rb.countSize
		badgeLabel.TextSize = rb.badgeSize
		-- Whole pixels (a phone's design width is fractional; UDim offsets are integers).
		local function whole(r: Layout.Rect): (number, number, number, number)
			return math.round(r.x), math.round(r.y), math.round(r.w), math.round(r.h)
		end
		local m = s.money
		local mx, my, mw, mh = whole(m.rect)
		moneyRoot.Position = UDim2.fromOffset(mx, my)
		moneyRoot.Size = UDim2.fromOffset(mw, mh)
		-- Outline weights scale down with the block: 4 PC, 3 phone, 2 tight.
		local line = if tight then 2 elseif compact then 3 else 4
		local chipLine = if tight then 2 else 3
		for _, stroke in { pillStroke, coinEdgeStroke } do
			stroke.Thickness = line
		end
		for _, stroke in { incomeStroke, rebirthStroke, incomeTabStroke } do
			stroke.Thickness = chipLine
		end
		badgeStroke.Thickness = if tight then 1 else 2
		-- Coin + pill zone: the coin (full height) at the left, the pill a little shorter, starting mid-coin.
		local _, _, cw, d = whole(m.cash)
		cashPlate.Position = UDim2.fromOffset(0, math.round(m.cash.y - m.rect.y))
		cashPlate.Size = UDim2.fromOffset(cw, d)
		local pad = math.round(d * 0.08)
		pill.Position = UDim2.fromOffset(math.round(d / 2), pad)
		pill.Size = UDim2.fromOffset(cw - math.round(d / 2), d - 2 * pad)
		coin.Position = UDim2.fromOffset(0, 0)
		coin.Size = UDim2.fromOffset(d, d)
		coinFace.Size = UDim2.new(1, 0, 1, -math.max(2, math.round(d * 0.06)))
		coinSign.TextSize = math.round(d * 0.46)
		local left, width = Layout.moneyTextBox(m.cash, "cash", compact, tight)
		cashLabel.Position = UDim2.fromOffset(left, pad)
		cashLabel.Size = UDim2.fromOffset(width, d - 2 * pad)
		for _, entry in
			{
				{ incomeChip, m.income, incomeLabel, "income" },
				{ rebirthChip, m.rebirths, rebirthLabel, "rebirths" },
			}
		do
			local frame, r = entry[1] :: Frame, entry[2] :: Layout.Rect
			frame.Position = UDim2.fromOffset(math.round(r.x - m.rect.x), math.round(r.y - m.rect.y))
			frame.Size = UDim2.fromOffset(math.round(r.w), math.round(r.h))
			local cl = frame:FindFirstChildOfClass("UICorner")
			if cl then
				cl.CornerRadius = UDim.new(0, math.max(4, math.round(r.h * 0.3)))
			end
			local tleft, twidth = Layout.moneyTextBox(r, entry[4] :: "income" | "rebirths", compact, tight)
			local label = entry[3] :: TextLabel
			label.Position = UDim2.fromOffset(tleft, 0)
			label.Size = UDim2.fromOffset(twidth, math.round(r.h))
		end
		-- The tab pointing down under the income chip: a small pill, half hidden behind the chip.
		local tabH = if tight then T.tab else if compact then M.ctab else M.tab
		local tabW = math.round(m.income.h * 0.5)
		incomeTab.Size = UDim2.fromOffset(tabW, tabH * 2)
		incomeTab.Position = UDim2.fromOffset(
			math.round(m.income.x - m.rect.x + m.income.w * 0.22),
			math.round(m.income.y - m.rect.y + m.income.h - tabH)
		)
		rebirthIcon.instance.Size = UDim2.fromOffset(rb.emblem, rb.emblem)
		local badgeW = Layout.moneyBadgeWidth(m.rebirths.h)
		badge.Size = UDim2.fromOffset(badgeW, math.round(m.rebirths.h * 0.72))
		badge.Position = UDim2.new(1, -5, 0.5, 0)
		local sx, sy, sw, sh = whole(s.status.rect)
		statusRoot.Position = UDim2.fromOffset(sx, sy)
		statusRoot.Size = UDim2.fromOffset(sw, sh)
		local sm = Layout.statusMetrics(compact, tight)
		statusTight = tight
		for _, entry in statusSlots do
			entry.frame.Size = UDim2.fromOffset(sm.slot, Layout.statusHeight(compact, tight))
			entry.icon.instance.Size = UDim2.fromOffset(sm.icon, sm.icon)
			entry.label.TextSize = sm.textSize
			entry.label.Size = UDim2.fromOffset(Layout.statusPillWidth(entry.label.Text, compact, tight), sm.pill)
			entry.label.Position = UDim2.new(0.5, 0, 0, sm.icon - sm.overlap)
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
		-- The coin carries the "$", so the amount shows without it; the income chip reads "+5.93M/s".
		cashLabel.Text = (string.gsub(money.cash, "^%$", ""))
		incomeLabel.Text = (string.gsub(money.income, "^%$", "+"))
		rebirthLabel.Text = money.rebirthCount
		badgeLabel.Text = money.multiplier

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
			blessed = current.blessed,
			featuredSecret = current.featuredSecret,
			shieldUntil = if ctx.shieldUntil then ctx.shieldUntil() else nil,
		}, now, Layout.STATUS.count)
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
				entry.label.Size =
					UDim2.fromOffset(Layout.statusPillWidth(slot.text, compact, statusTight), entry.label.Size.Y.Offset)
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

	-- Studio only (PC watcher shot): opens the tooltip of a status slot id (HudClusters.STATUS_IDS); nil closes.
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
