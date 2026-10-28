--!strict
--[[
	Boss card (top centre, under the HUD banner stack) while `State.boss` has a phase (BossMeterLogic). Read-only:
	hits are Bat swings, grabs the boss's prompt.

	Drawn like the notice cards (StealCards): deep teal glass in a coloured ring (pink while you fight it, gold when
	it is your moment, muted when it got away) with the crown on a round tile at the left. Two lines beside it: the
	title with an Ink timer chip at the right, then the goo meter and its percent (or a name instead) and one Ink pill
	that says what matters now.
]]

local UI = script.Parent.Parent
local BossMeterLogic = require(UI.BossMeterLogic)
local Layout = require(UI.Layout)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local KIT = Widgets.KIT
local create = Widgets.create

local SIZE = table.freeze({
	pad = 10, -- inside the card, every side
	gap = 10, -- between the tile and the lines, and between a line's parts
	tile = 48,
	tileText = 28,
	line1 = 30, -- title and timer
	lineGap = 6,
	line2 = 30, -- meter or name, percent, pill
	title = 22,
	timer = 16,
	timerHeight = 26,
	bar = 14,
	percent = 17,
	percentWidth = 46,
	pill = 15,
	pillWidth = 118,
	pillHeight = 28,
	who = 16,
	stack = 20, -- under the banner stack, the gap between notice cards
})

local HEIGHT = SIZE.pad + SIZE.line1 + SIZE.lineGap + SIZE.line2 + SIZE.pad

-- Ring and tile colour per BossMeterLogic tone; the meter's goo.
local RING = table.freeze({ fight = Theme.Bad, gold = Theme.Gold, mute = Theme.Info })
local GOO = table.freeze({ fight = Theme.Good, gold = Theme.Gold, mute = Theme.Info })
local TILE = table.freeze({ fight = Theme.Bad, gold = Theme.Gold, mute = Theme.Text })
local PILL = table.freeze({
	plain = Theme.Text,
	gold = Theme.Gold,
	pink = Theme.Bad,
	mint = Theme.Good,
	muted = Theme.Muted,
})

local BossMeter = {}

function BossMeter.new(parent: Instance, ctx: any)
	local z = Layout.ZINDEX.Banners
	local frame = create("Frame", {
		Name = "BossMeter",
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Layout.TOP),
		Size = UDim2.fromOffset(Layout.BANNER_WIDTH, HEIGHT),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.05,
		ZIndex = z,
		Parent = parent,
	}, { Widgets.corner(Layout.NOTICE_RADIUS) })
	local ring = Widgets.ring(frame, Theme.Bad, Layout.NOTICE_RADIUS)

	local tile = create("Frame", {
		Name = "IconTile",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, SIZE.pad, 0.5, 0),
		Size = UDim2.fromOffset(SIZE.tile, SIZE.tile),
		BackgroundColor3 = Theme.Bad,
		ZIndex = z,
		Parent = frame,
	}, { Widgets.pill(), Widgets.stroke(Theme.Ink, KIT.rowStroke) })
	local icon = Widgets.label({
		Name = "Icon",
		Text = BossMeterLogic.ICON,
		TextSize = SIZE.tileText,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
		Parent = tile,
	})
	Widgets.centreEmoji(icon, true)

	local leftX = SIZE.pad + SIZE.tile + SIZE.gap
	-- Line 1: the title, the timer chip at the right.
	local line1Y = SIZE.pad + SIZE.line1 / 2
	local timer = Widgets.chip({
		Name = "Timer",
		TextSize = SIZE.timer,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -SIZE.pad - 4, 0, line1Y),
		Size = UDim2.fromOffset(0, SIZE.timerHeight),
		ZIndex = z,
		Parent = frame,
	}, Theme.Gold)
	local title = Widgets.label({
		Name = "Title",
		Font = Theme.Font,
		TextSize = SIZE.title,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(leftX, line1Y),
		Size = UDim2.new(1, -leftX - SIZE.pad - 80, 0, SIZE.title + 4), -- 80: room for the timer chip
		ZIndex = z,
		Parent = frame,
	})

	-- Line 2, right to left: the pill, the percent, then the meter (or the name) fills what is left.
	local midY = SIZE.pad + SIZE.line1 + SIZE.lineGap + SIZE.line2 / 2
	local pill = Widgets.chip({
		Name = "Pill",
		TextSize = SIZE.pill,
		AutomaticSize = Enum.AutomaticSize.None,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -SIZE.pad - 4, 0, midY),
		Size = UDim2.fromOffset(SIZE.pillWidth, SIZE.pillHeight),
		ZIndex = z,
		Parent = frame,
	})
	local pctRight = SIZE.pad + 4 + SIZE.pillWidth + SIZE.gap
	local percent = Widgets.label({
		Name = "Percent",
		Font = Theme.Font,
		TextSize = SIZE.percent,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -pctRight, 0, midY),
		Size = UDim2.fromOffset(SIZE.percentWidth, SIZE.percent + 6),
		ZIndex = z,
		Parent = frame,
	})
	local barRight = pctRight + SIZE.percentWidth + SIZE.gap
	local bar, setBar = Widgets.bar(
		frame,
		Theme.Good,
		UDim2.new(1, -leftX - barRight, 0, SIZE.bar),
		UDim2.fromOffset(leftX, midY - SIZE.bar / 2)
	)
	bar.Name = "Meter"
	bar.ZIndex = z
	local fill = bar:FindFirstChildOfClass("Frame")
	if fill then
		fill.ZIndex = z
	end
	local who = Widgets.label({
		Name = "Who",
		FontFace = Theme.FontBody,
		TextSize = SIZE.who,
		TextColor3 = Theme.Muted,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(leftX, midY),
		Size = UDim2.new(1, -leftX - pctRight, 0, SIZE.who + 6),
		ZIndex = z,
		Parent = frame,
	})

	local boss: any = nil
	local badgesBefore: number? = nil -- the player's boss badges before this fight, for the win's "+1 badge"
	local top = Layout.TOP
	local bannerHeight: () -> number = function()
		return 0
	end

	local self = {}

	-- Top centre under the HUD banner stack (`bannerHeight`, layout px), as wide as the banners.
	function self.layout(screen: Layout.Screen, heightOfBanners: (() -> number)?)
		top = screen.banners.y
		bannerHeight = heightOfBanners or bannerHeight
		frame.Size = UDim2.fromOffset(math.round(screen.banners.w), HEIGHT) -- as wide as the notice cards
	end

	function self.update(state: any)
		boss = state.boss
		local phase = type(boss) == "table" and boss.phase
		if phase ~= "won" and type(boss) == "table" and type(boss.badges) == "number" then
			badgesBefore = boss.badges
		end
		self.tick(ctx.serverNow())
	end

	function self.tick(now: number)
		local view = BossMeterLogic.view(boss, now, badgesBefore)
		frame.Visible = view ~= nil
		if not view then
			return
		end
		local height = bannerHeight()
		frame.Position = UDim2.new(0.5, 0, 0, top + (if height > 0 then height + SIZE.stack else 0))
		ring.Color = RING[view.tone]
		tile.BackgroundColor3 = TILE[view.tone]
		if fill then
			fill.BackgroundColor3 = GOO[view.tone]
		end
		icon.Text = view.icon
		title.Text = view.title
		timer.Text = view.timer or ""
		timer.Visible = view.timer ~= nil
		local meter = view.meter
		bar.Visible = meter ~= nil
		percent.Visible = meter ~= nil
		who.Visible = meter == nil
		if meter then
			setBar(meter)
			percent.Text = `{BossMeterLogic.percent(meter)}%`
		end
		who.Text = view.who or ""
		pill.Text = view.pill
		pill.TextColor3 = PILL[view.pillTone]
	end

	return self
end

return BossMeter
