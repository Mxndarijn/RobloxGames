--!strict
--[[
	Boss card (top centre, under the HUD banner stack) while `State.boss` has a phase: the heads-up, the goo meter
	with your hits, the haul and the result (BossMeterLogic). Read-only: hits are Bat swings, grabs the boss's prompt.
	Drawn in the HUD kit: a purple plate with an ink outline, the phase icon on a chunky tile in the phase colour, a
	stroked title, the time left in an ink chip and an ink-track goo meter.
]]

local UI = script.Parent.Parent
local BossMeterLogic = require(UI.BossMeterLogic)
local Layout = require(UI.Layout)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local KIT = Widgets.KIT
local create = Widgets.create

local SIZE = table.freeze({
	width = 420,
	height = 84,
	pad = 10,
	radius = 18,
	tile = 58,
	tileText = 32,
	title = 20,
	titleHeight = 24,
	detail = 14,
	detailHeight = 18,
	timer = 16,
	timerHeight = 24,
	timerWidth = 64, -- room the title leaves for the chip ("1:05")
	bar = 14,
	gap = 6, -- under the banner stack
})

-- Tile and meter colour per BossMeterLogic tone.
local TONES = table.freeze({
	warn = Theme.Warn,
	fight = Theme.Bad,
	haul = Theme.Gold,
	good = Theme.Good,
	bad = Theme.Info, -- a muted teal: the boss got away, nothing to celebrate
})

local BossMeter = {}

function BossMeter.new(parent: Instance, ctx: any)
	local z = Layout.ZINDEX.Banners
	local frame = create("Frame", {
		Name = "BossMeter",
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Layout.TOP),
		Size = UDim2.fromOffset(SIZE.width, SIZE.height),
		BackgroundColor3 = Theme.Bg,
		ZIndex = z,
		Parent = parent,
	}, { Widgets.corner(SIZE.radius) })
	Widgets.ring(frame, Theme.Bad, SIZE.radius) -- a boss is a danger notice: the pink ring
	local tile = create("Frame", {
		Name = "IconTile",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, SIZE.pad, 0.5, 0),
		Size = UDim2.fromOffset(SIZE.tile, SIZE.tile),
		BackgroundColor3 = Theme.Warn,
		ZIndex = z,
		Parent = frame,
	}, { Widgets.pill(), Widgets.stroke(Theme.Ink, KIT.stroke) })
	Widgets.shade(tile)
	Widgets.shine(tile)
	local icon = Widgets.label({
		Name = "Icon",
		TextSize = SIZE.tileText,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Parent = tile,
	})
	local textX = SIZE.pad * 2 + SIZE.tile
	local timer = Widgets.chip({
		Name = "Timer",
		TextSize = SIZE.timer,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -SIZE.pad, 0, SIZE.pad),
		Size = UDim2.fromOffset(0, SIZE.timerHeight),
		ZIndex = z,
		Parent = frame,
	}, Theme.Gold)
	local title = Widgets.label({
		Name = "Title",
		Font = Theme.Font,
		TextSize = SIZE.title,
		TextStrokeColor3 = Theme.Ink,
		TextStrokeTransparency = 0,
		Size = UDim2.new(1, -textX - SIZE.pad, 0, SIZE.titleHeight),
		Position = UDim2.fromOffset(textX, SIZE.pad),
		ZIndex = z,
		Parent = frame,
	})
	local detail = Widgets.label({
		Name = "Detail",
		TextSize = SIZE.detail,
		TextColor3 = Theme.Muted,
		Size = UDim2.new(1, -textX - SIZE.pad, 0, SIZE.detailHeight),
		Position = UDim2.fromOffset(textX, SIZE.pad + SIZE.titleHeight + 2),
		ZIndex = z,
		Parent = frame,
	})
	local bar, setBar = Widgets.bar(
		frame,
		Theme.Bad,
		UDim2.new(1, -textX - SIZE.pad, 0, SIZE.bar),
		UDim2.new(0, textX, 1, -(SIZE.bar + SIZE.pad))
	)
	bar.Name = "Meter"
	bar.ZIndex = z
	local fill = bar:FindFirstChildOfClass("Frame")
	if fill then
		fill.ZIndex = z
	end

	local boss: any = nil
	local top = Layout.TOP
	local bannerHeight: () -> number = function()
		return 0
	end

	local self = {}

	-- Top centre under the HUD banner stack (`bannerHeight`, layout px), as wide as the banners.
	function self.layout(screen: Layout.Screen, heightOfBanners: (() -> number)?)
		top = screen.banners.y
		bannerHeight = heightOfBanners or bannerHeight
		frame.Size = UDim2.fromOffset(math.min(SIZE.width, math.round(screen.banners.w)), SIZE.height)
	end

	function self.update(state: any)
		boss = state.boss
		self.tick(ctx.serverNow())
	end

	function self.tick(now: number)
		local view = BossMeterLogic.view(boss, now)
		frame.Visible = view ~= nil
		if not view then
			return
		end
		local height = bannerHeight()
		frame.Position = UDim2.new(0.5, 0, 0, top + (if height > 0 then height + SIZE.gap else 0))
		local tone = TONES[view.tone]
		tile.BackgroundColor3 = tone
		if fill then
			fill.BackgroundColor3 = tone
		end
		icon.Text = view.icon
		title.Text = view.title
		detail.Text = view.detail
		timer.Text = view.timer or ""
		timer.Visible = view.timer ~= nil
		local chipRoom = if view.timer then SIZE.timerWidth + SIZE.pad else 0
		title.Size = UDim2.new(1, -textX - SIZE.pad - chipRoom, 0, SIZE.titleHeight)
		setBar(view.meter)
	end

	return self
end

return BossMeter
