--!strict
--[[
	Hud

	Always-visible top bar: cash, income/sec, rebirths + multiplier, pads,
	a large lock block (LOCKED m:ss / UNLOCKED, see LockHud) + Lock button,
	Buy-next-pad, Shop, Daily (opens the daily popup). Items are placed from
	Layout.hud (one row on desktop, two on a phone, one on a landscape
	phone; `layout(screen)` from init.client). A stack of banners
	below it (hidden ones collapse): "your slime is being stolen", Slime Rain
	(workspace RainActive / RainEndsAt / RainNextAt attributes, else
	State.rain; see RainTimer), the Boss Slime / Legendary+ drops (see
	RareAnnounce) and a
	"plot full" hint.
]]

local CollectionService = game:GetService("CollectionService")

local Format = require(script.Parent.Format)
local Layout = require(script.Parent.Layout)
local LockHud = require(script.Parent.LockHud)
local ModifierBadge = require(script.Parent.ModifierBadge)
local Nav = require(script.Parent.Nav)
local RainTimer = require(script.Parent.RainTimer)
local RareAnnounce = require(script.Parent.RareAnnounce)
local Tutorial = require(script.Parent.Tutorial)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Hud = {}

local function chip(parent: Instance, name: string, caption: string): (Frame, TextLabel)
	local frame = create("Frame", {
		Name = name,
		Size = UDim2.fromOffset(Layout.HUD_ITEMS[name].w, 48),
		BackgroundColor3 = Theme.BgLight,
		Parent = parent,
	}, { Widgets.corner(8) })
	Widgets.label({
		Text = caption,
		TextSize = 11,
		TextColor3 = Theme.Muted,
		Font = Theme.Font,
		Size = UDim2.new(1, -12, 0, 14),
		Position = UDim2.fromOffset(6, 4),
		Parent = frame,
	})
	return frame,
		Widgets.label({
			Name = "Value",
			Text = "-",
			TextSize = 18,
			Font = Theme.Font,
			Size = UDim2.new(1, -12, 0, 24),
			Position = UDim2.fromOffset(6, 20),
			Parent = frame,
		})
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
		Size = UDim2.fromOffset(560, 34),
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
	local cash: TextLabel, income: TextLabel, rebirths: TextLabel, pads: TextLabel
	items.Cash, cash = chip(bar, "Cash", "CASH")
	items.Income, income = chip(bar, "Income", "INCOME")
	items.Rebirths, rebirths = chip(bar, "Rebirths", "REBIRTHS")
	items.Pads, pads = chip(bar, "Pads", "PADS")
	cash.TextColor3 = Theme.Accent

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

	local shopBtn = Widgets.button(
		{ Name = "Shop", Text = "🛒 Shop", Size = UDim2.fromOffset(100, Layout.BUTTON), TextSize = 16 },
		Theme.Warn,
		function()
			ctx.togglePanel("Shop")
		end
	)
	shopBtn.instance.TextColor3 = Color3.fromRGB(40, 30, 10)
	shopBtn.instance.Parent = bar
	items.Shop = shopBtn.instance

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
		ZIndex = Layout.ZINDEX.Banners, -- alerts may cover a full-window menu title
		Parent = parent,
	}, { Widgets.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center) })
	local steal = banner(banners, "StealAlert", Theme.Bad, 1)
	local rare = banner(banners, "RareBanner", Theme.Gold, 2)
	rare.TextColor3 = Color3.fromRGB(40, 30, 10)
	rare.TextStrokeTransparency = 1
	rare.TextSize = 20
	rare.Size = UDim2.new(1, 0, 0, 40)
	Widgets.stroke(Color3.new(1, 1, 1), 2).Parent = rare
	local rain = banner(banners, "RainBanner", Color3.fromRGB(90, 70, 200), 3)
	local modifier = banner(banners, "ModifierBadge", Color3.fromRGB(30, 120, 110), 5)
	modifier.TextSize = 15
	local hint = banner(banners, "PadHint", Color3.fromRGB(150, 100, 20), 4)
	hint.TextSize = 16

	local RAIN_COLORS = { active = Color3.fromRGB(90, 70, 200), soon = Color3.fromRGB(60, 55, 110) }

	-- Workspace rain attributes, kept fresh by change signals (read in tick).
	local rainAttrs: RainTimer.Rain? = nil
	local function readRainAttrs()
		rainAttrs = RainTimer.fromAttributes(
			workspace:GetAttribute("RainActive"),
			workspace:GetAttribute("RainEndsAt"),
			workspace:GetAttribute("RainNextAt")
		)
	end
	readRainAttrs()

	-- Boss Slime: replicated models with the Boss attribute, plus the Notify
	-- heuristic for models that aren't replicated (RareAnnounce header).
	local C = ctx.Constants
	local bossModels: { [Instance]: boolean } = {}
	local notifyBoss: RareAnnounce.Boss? = nil
	local caught: { text: string, untilTime: number }? = nil
	-- Latest Legendary+ drop (workspace RareSpawn* attributes + "Rare" Notify).
	local drop: RareAnnounce.Drop? = nil
	local tierNames: { string } = {}
	for i, rarity in ctx.Config.RARITIES do
		tierNames[i] = rarity.name
	end
	local function readDrop()
		local fresh = RareAnnounce.dropFromAttributes(
			workspace:GetAttribute(C.RARE_SPAWN_TIER_ATTRIBUTE),
			workspace:GetAttribute(C.RARE_SPAWN_AT_ATTRIBUTE)
		)
		if fresh and (drop == nil or fresh.at ~= drop.at) then
			-- Keep Notify text that arrived first for this same drop.
			if drop and drop.text and math.abs(drop.at - fresh.at) < 3 then
				fresh.text = drop.text
			end
			drop = fresh
		end
	end

	local function checkBoss(model: Instance)
		if model.Parent ~= nil and model:GetAttribute(C.BOSS_ATTRIBUTE) == true then
			bossModels[model] = true
		elseif bossModels[model] then
			bossModels[model] = nil
			if notifyBoss and model:GetAttribute("State") == "Carried" then
				notifyBoss.carried = true
			end
		end
	end
	local function watchSlime(model: Instance)
		checkBoss(model)
		model:GetAttributeChangedSignal(C.BOSS_ATTRIBUTE):Connect(function()
			checkBoss(model)
		end)
	end
	for _, model in CollectionService:GetTagged(C.SLIME_TAG) do
		watchSlime(model)
	end
	CollectionService:GetInstanceAddedSignal(C.SLIME_TAG):Connect(watchSlime)
	CollectionService:GetInstanceRemovedSignal(C.SLIME_TAG):Connect(function(model)
		bossModels[model] = nil
	end)

	local function currentBoss(): RareAnnounce.Boss?
		local model = next(bossModels)
		if model == nil then
			return notifyBoss
		end
		local body = model:FindFirstChild("Body")
		local prompt = body and body:FindFirstChild(C.GRAB_PROMPT_NAME)
		local name = if prompt and prompt:IsA("ProximityPrompt")
			then RareAnnounce.nameFromObjectText(prompt.ObjectText)
			else nil
		return {
			name = name or (notifyBoss and notifyBoss.name),
			expiresAt = notifyBoss and notifyBoss.expiresAt,
			carried = model:GetAttribute("State") == "Carried",
		}
	end

	local current: any = nil
	local screen: Layout.Screen? = nil
	local compact = false
	-- HUD item visibility last laid out (Layout.hud skips hidden items).
	local shown: { [string]: boolean } = {}
	local laidOut: Layout.HudLayout? = nil

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
		shown.Shop = not compact
		lockTitle.TextSize = if compact then 18 else 20
		lockSub.TextSize = if compact then 11 else 12
		lockBtn.instance.TextSize = if compact then 13 else 16
		for _, value in { cash, income, rebirths, pads } do
			value.TextSize = if compact then 16 else 18 -- "$98.7T/s" fits a phone chip
		end
		banners.Size = UDim2.fromOffset(s.banners.w, 0)
		banners.Position = UDim2.new(0.5, 0, 0, s.banners.y)
		relayout()
		if current then
			self.update(current)
		end
	end

	-- The HUD boxes as shown now (hidden items missing), for the hint ring.
	function self.hudLayout(): Layout.HudLayout?
		return laidOut
	end

	-- Every Notify goes through here (toasts are handled by init).
	function self.onNotify(text: string, sound: string?)
		local now = ctx.serverNow()
		local kind = RareAnnounce.classify(text, sound)
		if kind == "spawn" then
			notifyBoss = {
				name = RareAnnounce.nameFromNotify(text),
				expiresAt = now + ctx.Config.BOSS_LIFETIME,
				carried = false,
			}
			caught = nil
		elseif kind == "caught" then
			caught = { text = text, untilTime = now + RareAnnounce.CAUGHT_SECONDS }
			notifyBoss = nil
		elseif kind == "drop" then
			if drop and math.abs(now - drop.at) < 3 then
				drop.text = text
			else
				drop = { tier = nil, at = now, text = text }
			end
		end
		self.tick(now)
	end

	function self.update(state: any)
		current = state
		cash.Text = Format.formatCash(state.cash)
		income.Text = Format.formatRate(state.incomePerSec)
		rebirths.Text = `{state.rebirths} {Format.formatMultiplier(state.rebirthMultiplier)}`
		pads.Text = `{state.padsUnlocked}/{state.padsMax}`

		local pad = LockHud.padButton(state, compact)
		setShown("BuyPad", pad.visible)
		padBtn.setText(pad.text)
		padBtn.setColor(if not pad.enabled then Theme.Disabled elseif pad.urgent then Theme.Warn else Theme.Good)
		hint.Visible = pad.hint ~= nil
		hint.Text = pad.hint or ""

		-- Point at the Shop when an upgrade is affordable.
		shopBtn.setText(if Nav.shopAffordable(state) then "🛒 Shop\nUpgrade!" else "🛒 Shop")

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
		lockBtn.setText(lockView.text)
		lockBtn.setColor(if lockView.enabled then Theme.Info else Theme.Disabled)

		local rareInfo = RareAnnounce.banner(currentBoss(), caught, now)
			or RareAnnounce.dropBanner(drop, now, tierNames)
		rare.Visible = rareInfo ~= nil
		if rareInfo then
			rare.Text = rareInfo.text
			local color = Theme.Gold
			if rareInfo.kind == "drop" and drop and drop.tier and ctx.Config.RARITIES[drop.tier] then
				color = Widgets.color3(ctx.Config.RARITIES[drop.tier].color)
			end
			rare.BackgroundColor3 = if rareInfo.kind ~= "caught" and (now * 2) % 2 < 1
				then color:Lerp(Color3.new(1, 1, 1), 0.3)
				else color
		end

		local info = RainTimer.banner(RainTimer.resolve(rainAttrs, current.rain), now, ctx.Config.RAIN_LUCK)
		rain.Visible = info ~= nil
		if info then
			rain.Text = info.text
			rain.BackgroundColor3 = RAIN_COLORS[info.kind]
			rain.TextSize = if info.kind == "active" then 18 else 15
		end

		local modifierText = ModifierBadge.banner(current.modifier, now, ctx.Config.FEATURES.CycleModifier == true)
		modifier.Visible = modifierText ~= nil
		if modifierText then
			modifier.Text = modifierText
		end
	end

	for _, name in { C.RARE_SPAWN_AT_ATTRIBUTE, C.RARE_SPAWN_TIER_ATTRIBUTE } do
		workspace:GetAttributeChangedSignal(name):Connect(function()
			readDrop()
			self.tick(ctx.serverNow())
		end)
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
