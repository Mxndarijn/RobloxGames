--!strict
--[[
	CashFly (Roblox view over CashFlyLogic)

	Earned cash bursts out as gold coins (from your character, or the middle of the screen while a menu is open) and
	curves into the coin on the money plate; the plate's number counts up as they land. Spent cash spills a few coins
	out of the plate. A stack of "+$1.2K" / "-$2.5K" rows sits just above the number (CashFlyLogic: max 3, 2 s).

	Everything lives in its own ScreenGui one DisplayOrder above the main UI, so it also shows over the shop menu.
	The money plate is only read (Hud.cashAnchors) and its number set (Hud.setShownCash); nothing on it moves.
	Motion is TweenService only: X and Y tween on two nested frames with different easing, which curves the path
	without a per-frame loop. Coins, trails and rows are pooled and made on first use.

	  CashFly.new(deps) -> { update(state), tick(), layout(screen), setMenuOpen(boolean), destroy() }

	The rows start over the amount; where the nav tiles stand right above the plate (PC) they start right of them.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local CashFlyLogic = require(script.Parent.CashFlyLogic)
local Format = require(script.Parent.Format)
local Layout = require(script.Parent.Layout)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create
local T = CashFlyLogic.TUNING

export type Deps = {
	playerGui: Instance,
	displayOrder: number, -- the main UI's; this layer sits one above
	anchors: () -> (GuiObject, GuiObject), -- Hud.cashAnchors: the plate's coin and its amount label
	setShownCash: (number?) -> (), -- Hud.setShownCash
	reducedMotion: () -> boolean,
}

-- Sizes as shares of the plate's coin / amount, so phones and PC match the plate.
local LOOK = table.freeze({
	coin = 0.42, -- flying coin diameter / plate coin height
	trail = 0.7, -- the trailing ghost coin, of a flying coin
	trailLag = 0.05, -- seconds the ghost follows behind
	trailFade = 0.5,
	popMin = 22, -- burst radius around the source, px at UI scale 1
	popMax = 52,
	popRise = 18,
	stroke = 2,
	ring = 1.7, -- landing ring at its widest / plate coin height
	ringSeconds = 0.3,
	rowText = 0.62, -- row text size / amount label height
	rowGap = 0.04, -- of the row text size
	fadeSeconds = 0.3,
	olderScale = table.freeze({ 1, 0.82, 0.68 }), -- newest first
	olderFade = table.freeze({ 0, 0.4, 0.65 }),
	bump = 1.25,
	navGap = 0.4, -- room between the nav tiles and the rows, of the row step
	plateGap = 0.2, -- room between the newest row and the plate, of the row step
	spendRise = 0.28, -- spilled coins rise this share of the screen height
	spendSeconds = 0.6,
})

type Coin = { root: Frame, lift: Frame, disc: Frame, stroke: UIStroke?, scale: UIScale }
type RowView = { label: TextLabel, scale: UIScale, amount: number }

local function tween(
	inst: Instance,
	seconds: number,
	style: Enum.EasingStyle,
	dir: Enum.EasingDirection,
	goal: any
): Tween
	local t = TweenService:Create(inst, TweenInfo.new(seconds, style, dir), goal)
	t:Play()
	return t
end

local CashFly = {}

function CashFly.new(deps: Deps)
	local gui = create("ScreenGui", {
		Name = "CashFly",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = deps.displayOrder + 1,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = deps.playerGui,
	}) :: ScreenGui
	local root = create("Frame", {
		Name = "Layer",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	}) :: Frame
	local coinLayer = create(
		"Frame",
		{ Name = "Coins", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = root }
	)
	local rowLayer = create(
		"Frame",
		{ Name = "Rows", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = root }
	)

	local model = CashFlyLogic.new()
	local rng = Random.new()
	local menuOpen = false
	local alive = true
	local free: { Coin } = {}
	local freeGhosts: { Coin } = {}
	local rowViews: { [number]: RowView } = {}
	local freeRows: { RowView } = {}
	local nav: { top: number, bottom: number, right: number }? = nil -- the nav tiles, layer px

	-- Layer-local positions (both ScreenGuis use the same inset, so subtracting the layer's corner is enough).
	local function localCenter(obj: GuiObject): Vector2
		return obj.AbsolutePosition + obj.AbsoluteSize / 2 - root.AbsolutePosition
	end

	local function makeCoin(ghost: boolean): Coin
		local rootFrame = create(
			"Frame",
			{ BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), Visible = false, Parent = coinLayer }
		)
		local lift = create("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), Parent = rootFrame })
		local disc = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = if ghost then Theme.GoldDeep else Theme.Gold,
			ZIndex = if ghost then 1 else 2,
			Parent = lift,
		}, { create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		local scale = create("UIScale", { Parent = disc })
		local stroke = nil
		if not ghost then
			stroke = Widgets.stroke(Theme.Ink, LOOK.stroke)
			stroke.Parent = disc
		end
		return { root = rootFrame, lift = lift, disc = disc, stroke = stroke, scale = scale }
	end

	local function takeCoin(ghost: boolean): Coin
		local pool = if ghost then freeGhosts else free
		local c = table.remove(pool) or makeCoin(ghost)
		c.disc.BackgroundTransparency = if ghost then LOOK.trailFade else 0
		if c.stroke then
			c.stroke.Transparency = 0
		end
		return c
	end

	local function release(c: Coin, ghost: boolean)
		c.root.Visible = false
		table.insert(if ghost then freeGhosts else free, c)
	end

	local function place(c: Coin, at: Vector2, size: number, scale: number)
		c.root.Position = UDim2.fromOffset(at.X, 0)
		c.lift.Position = UDim2.fromOffset(0, at.Y)
		c.disc.Size = UDim2.fromOffset(size, size)
		c.scale.Scale = scale
		c.root.Visible = true
	end

	-- One coin: burst to `pop`, then curve to `to` (X eases in-out, Y backs up a little then drops: an arc).
	local function flyCoin(
		c: Coin,
		ghost: boolean,
		from: Vector2,
		pop: Vector2,
		to: Vector2,
		size: number,
		onLand: () -> ()
	)
		place(c, from, size, 0.3)
		local quad, out, inOut, inn =
			Enum.EasingStyle.Quad, Enum.EasingDirection.Out, Enum.EasingDirection.InOut, Enum.EasingDirection.In
		tween(c.root, T.POP_SECONDS, quad, out, { Position = UDim2.fromOffset(pop.X, 0) })
		tween(c.lift, T.POP_SECONDS, quad, out, { Position = UDim2.fromOffset(0, pop.Y) })
		tween(c.scale, T.POP_SECONDS, quad, out, { Scale = 1.1 })
		task.delay(T.POP_SECONDS, function()
			if not alive then
				return
			end
			tween(c.root, T.FLY_SECONDS, quad, inOut, { Position = UDim2.fromOffset(to.X, 0) })
			tween(c.scale, T.FLY_SECONDS, quad, inn, { Scale = 0.65 })
			local drop =
				tween(c.lift, T.FLY_SECONDS, Enum.EasingStyle.Back, inn, { Position = UDim2.fromOffset(0, to.Y) })
			drop.Completed:Once(function()
				release(c, ghost)
				onLand()
			end)
		end)
	end

	local ring: Frame? = nil
	local ringStroke: UIStroke? = nil
	local function landRing(at: Vector2, plate: number)
		if ring == nil then
			ring = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				ZIndex = 3,
				Parent = coinLayer,
			}, { create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
			ringStroke = Widgets.stroke(Theme.Gold, 3);
			(ringStroke :: UIStroke).Parent = ring
		end
		local r, s = ring :: Frame, ringStroke :: UIStroke
		r.Position = UDim2.fromOffset(at.X, at.Y)
		r.Size = UDim2.fromOffset(plate * 0.7, plate * 0.7)
		s.Transparency = 0
		local w = plate * LOOK.ring
		tween(r, LOOK.ringSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Size = UDim2.fromOffset(w, w) })
		tween(s, LOOK.ringSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Transparency = 1 })
	end

	-- Rows ----------------------------------------------------------------------------------------------------
	local function takeRow(): RowView
		local view = table.remove(freeRows)
		if view then
			return view
		end
		local label = Widgets.label({
			Name = "Delta",
			Font = Theme.Font,
			Text = "",
			TextStrokeColor3 = Theme.Ink,
			TextStrokeTransparency = 0,
			TextTruncate = Enum.TextTruncate.None,
			AutomaticSize = Enum.AutomaticSize.X,
			AnchorPoint = Vector2.new(0, 1),
			Size = UDim2.fromOffset(0, 0),
			Parent = rowLayer,
		})
		local scale = create("UIScale", { Parent = label })
		return { label = label, scale = scale, amount = 0 }
	end

	local function renderRows()
		local coinAnchor, amountAnchor = deps.anchors()
		local textSize = math.max(12, math.round(amountAnchor.AbsoluteSize.Y * LOOK.rowText))
		local step = math.round(textSize * (1 + LOOK.rowGap))
		local x = amountAnchor.AbsolutePosition.X - root.AbsolutePosition.X
		local bottom = coinAnchor.AbsolutePosition.Y - root.AbsolutePosition.Y - math.round(step * LOOK.plateGap)
		-- The nav tiles stand right above the plate on PC: the rows step right of them instead of covering them.
		if nav and nav.bottom > bottom - T.ROWS * step and nav.top < bottom and nav.right > x then
			x = nav.right + step * LOOK.navGap
		end
		local seen: { [number]: boolean } = {}
		local n = #model.rows
		for i, row in model.rows do
			seen[row.id] = true
			local age = n - i -- 0 = newest, next to the number
			local view = rowViews[row.id]
			local fresh = view == nil
			if view == nil then
				view = takeRow()
				rowViews[row.id] = view
			end
			local v = view :: RowView
			local label = v.label
			label.TextSize = textSize
			label.Size = UDim2.fromOffset(0, textSize)
			label.TextColor3 = if row.sign > 0 then Theme.Good else Theme.Bad
			label.Text = CashFlyLogic.rowText(row, Format.formatCash)
			local goal = UDim2.fromOffset(x, bottom - age * step)
			local fade = LOOK.olderFade[age + 1] or 1
			local size = LOOK.olderScale[age + 1] or 0.6
			if fresh then
				label.Position = goal + UDim2.fromOffset(0, step * 0.5)
				label.TextTransparency = 1
				label.TextStrokeTransparency = 1
				v.scale.Scale = 0.7
				label.Visible = true
				tween(v.scale, 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = size })
			elseif row.amount ~= v.amount then
				v.scale.Scale = size * LOOK.bump -- a joined amount bumps
				tween(v.scale, 0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Scale = size })
			else
				tween(v.scale, LOOK.fadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, { Scale = size })
			end
			v.amount = row.amount
			tween(label, LOOK.fadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
				Position = goal,
				TextTransparency = fade,
				TextStrokeTransparency = fade,
			})
		end
		for id, view in rowViews do
			if not seen[id] then
				rowViews[id] = nil
				local gone = tween(view.label, LOOK.fadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
					Position = view.label.Position - UDim2.fromOffset(0, step * 0.5),
					TextTransparency = 1,
					TextStrokeTransparency = 1,
				})
				gone.Completed:Once(function()
					if rowViews[id] == nil then
						view.label.Visible = false
						table.insert(freeRows, view)
					end
				end)
			end
		end
	end

	local function syncNumber()
		deps.setShownCash(if CashFlyLogic.counting(model) then CashFlyLogic.shownCash(model) else nil)
	end

	-- Where earned coins start: your character on screen, else (or with a menu open) the middle of the screen.
	local function source(): Vector2
		local size = root.AbsoluteSize
		local middle = Vector2.new(size.X / 2, size.Y * 0.45)
		if menuOpen then
			return middle
		end
		local camera = workspace.CurrentCamera
		local character = Players.LocalPlayer and Players.LocalPlayer.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if camera and hrp and hrp:IsA("BasePart") then
			local p, onScreen = camera:WorldToScreenPoint(hrp.Position)
			local at = Vector2.new(p.X, p.Y) - root.AbsolutePosition
			if onScreen and at.X >= 0 and at.Y >= 0 and at.X <= size.X and at.Y <= size.Y then
				return at
			end
		end
		return middle
	end

	local function startFlight(id: number, coins: number)
		local coinAnchor = deps.anchors()
		local plate = coinAnchor.AbsoluteSize.Y
		local to = localCenter(coinAnchor)
		local from = source()
		local size = math.max(10, plate * LOOK.coin)
		local ui = plate / 60 -- the plate coin is about 60 px at UI scale 1
		for i = 1, coins do
			local angle = rng:NextNumber(0, math.pi * 2)
			local radius = rng:NextNumber(LOOK.popMin, LOOK.popMax) * ui
			local pop = from + Vector2.new(math.cos(angle) * radius, math.sin(angle) * radius - LOOK.popRise * ui)
			local delay = (i - 1) * T.COIN_GAP_SECONDS
			task.delay(delay, function()
				if not alive then
					return
				end
				flyCoin(takeCoin(false), false, from, pop, to, size, function()
					if not alive then
						return
					end
					CashFlyLogic.land(model, id, os.clock())
					landRing(to, plate)
					syncNumber()
					renderRows()
				end)
			end)
			task.delay(delay + LOOK.trailLag, function()
				if alive then
					flyCoin(takeCoin(true), true, from, pop, to, size * LOOK.trail, function() end)
				end
			end)
		end
	end

	local function spill(coins: number)
		local coinAnchor = deps.anchors()
		local plate = coinAnchor.AbsoluteSize.Y
		local from = localCenter(coinAnchor)
		local size = math.max(10, plate * LOOK.coin)
		local rise = root.AbsoluteSize.Y * LOOK.spendRise
		for i = 1, coins do
			local c = takeCoin(false)
			place(c, from, size, 0.8)
			local to = from + Vector2.new(rng:NextNumber(-0.4, 1.2) * rise * 0.6, -rise * rng:NextNumber(0.6, 1))
			task.delay((i - 1) * T.COIN_GAP_SECONDS, function()
				if not alive then
					return
				end
				local secs = LOOK.spendSeconds
				local quad, out = Enum.EasingStyle.Quad, Enum.EasingDirection.Out
				tween(c.root, secs, quad, out, { Position = UDim2.fromOffset(to.X, 0) })
				tween(c.lift, secs, quad, out, { Position = UDim2.fromOffset(0, to.Y) })
				tween(c.disc, secs, quad, Enum.EasingDirection.In, { BackgroundTransparency = 1 })
				local fade = tween(c.stroke :: UIStroke, secs, quad, Enum.EasingDirection.In, { Transparency = 1 })
				fade.Completed:Once(function()
					release(c, false)
				end)
			end)
		end
	end

	local self = {}

	function self.update(state: any)
		if not alive or type(state) ~= "table" then
			return
		end
		local shop = state.exclusiveShop
		local event = CashFlyLogic.observe(model, {
			cash = state.cash,
			rebirths = state.rebirths,
			incomePerSec = state.incomePerSec,
			autoCollect = type(shop) == "table" and type(shop.passes) == "table" and shop.passes.AutoCollect == true,
			reducedMotion = deps.reducedMotion(),
		}, os.clock())
		if event and event.kind == "flight" then
			startFlight(event.id, event.coins)
		elseif event and event.kind == "spend" and not deps.reducedMotion() then
			spill(event.coins)
		end
		syncNumber()
		renderRows()
	end

	-- From the client loop (10 Hz): rows that ran out, the Auto Collect sum, flights that never landed.
	function self.tick()
		if alive and CashFlyLogic.tick(model, os.clock()) then
			syncNumber()
			renderRows()
		end
	end

	-- Applies a Layout.screen (design px; this layer has no UIScale, so they are scaled here).
	function self.layout(s: Layout.Screen)
		local r = s.nav
		nav = { top = r.y * s.scale, bottom = (r.y + r.h) * s.scale, right = (r.x + r.w) * s.scale }
		renderRows()
	end

	function self.setMenuOpen(isOpen: boolean)
		menuOpen = isOpen
	end

	function self.destroy()
		alive = false
		deps.setShownCash(nil)
		gui:Destroy()
	end

	return self
end

return CashFly
