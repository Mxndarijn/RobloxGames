--!strict
--[[
	Boss card (top centre, under the HUD banner stack) while `State.boss` has a phase: the heads-up, the goo meter
	with your hits, the haul and the result (BossMeterLogic). Read-only: hits are Bat swings, grabs the boss's prompt.
]]

local UI = script.Parent.Parent
local BossMeterLogic = require(UI.BossMeterLogic)
local Layout = require(UI.Layout)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local SIZE = table.freeze({
	width = 420,
	height = 74,
	pad = 10,
	title = 18,
	detail = 14,
	timerWidth = 60,
	bar = 10,
	gap = 6, -- under the banner stack
})

local TONES = table.freeze({
	warn = Theme.Warn,
	fight = Theme.Bad,
	haul = Theme.Gold,
	good = Theme.Good,
	bad = Theme.Muted,
})

local BossMeter = {}

function BossMeter.new(parent: Instance, ctx: any)
	local border = Widgets.stroke(Theme.Warn, 2)
	local frame = create("Frame", {
		Name = "BossMeter",
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Layout.TOP),
		Size = UDim2.fromOffset(SIZE.width, SIZE.height),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.1,
		ZIndex = Layout.ZINDEX.Banners,
		Parent = parent,
	}, { Widgets.corner(12), border })
	local title = Widgets.label({
		Name = "Title",
		Font = Theme.Font,
		TextSize = SIZE.title,
		Size = UDim2.new(1, -(SIZE.pad * 2 + SIZE.timerWidth), 0, 22),
		Position = UDim2.fromOffset(SIZE.pad, 6),
		ZIndex = Layout.ZINDEX.Banners,
		Parent = frame,
	})
	local timer = Widgets.label({
		Name = "Timer",
		Font = Theme.Font,
		TextSize = SIZE.title,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(SIZE.timerWidth, 22),
		Position = UDim2.new(1, -SIZE.pad, 0, 6),
		ZIndex = Layout.ZINDEX.Banners,
		Parent = frame,
	})
	local detail = Widgets.label({
		Name = "Detail",
		TextSize = SIZE.detail,
		TextColor3 = Theme.Muted,
		Size = UDim2.new(1, -SIZE.pad * 2, 0, 18),
		Position = UDim2.fromOffset(SIZE.pad, 30),
		ZIndex = Layout.ZINDEX.Banners,
		Parent = frame,
	})
	local bar, setBar = Widgets.bar(
		frame,
		Theme.Bad,
		UDim2.new(1, -SIZE.pad * 2, 0, SIZE.bar),
		UDim2.new(0, SIZE.pad, 1, -(SIZE.bar + SIZE.pad))
	)
	bar.Name = "Meter"
	bar.ZIndex = Layout.ZINDEX.Banners
	local fill = bar:FindFirstChildOfClass("Frame")
	if fill then
		fill.ZIndex = Layout.ZINDEX.Banners
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
		border.Color = tone
		if fill then
			fill.BackgroundColor3 = tone
		end
		title.Text = view.title
		detail.Text = view.detail
		timer.Text = view.timer or ""
		setBar(view.meter)
	end

	return self
end

return BossMeter
