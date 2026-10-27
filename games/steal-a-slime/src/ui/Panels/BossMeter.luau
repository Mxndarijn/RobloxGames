--!strict
--[[
	Boss card (top centre, under the HUD banner stack) while `State.boss` has a phase (BossMeterLogic). Read-only:
	hits are Bat swings, grabs the boss's prompt.

	Drawn in the Goo kit as a notice: deep teal glass with a coloured ring (pink while you fight it, gold when it is
	your moment, muted when it got away) and a band in that colour carrying the title and an Ink timer chip, with two
	goo drips under it. One row below: the crown on a jelly tile, the goo meter and its percent (or a name instead),
	and one Ink pill that says what matters now.
]]

local UI = script.Parent.Parent
local BossMeterLogic = require(UI.BossMeterLogic)
local Layout = require(UI.Layout)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local KIT = Widgets.KIT
local create = Widgets.create

local SIZE = table.freeze({
	width = 460,
	band = 48,
	radius = 28,
	padX = 16, -- left and right inside the card
	bandPadLeft = 20,
	bandPadRight = 12,
	rowTop = 20, -- from the band's bottom to the row: room for the drips
	row = 52,
	bottom = 14,
	gap = 12, -- between the row's parts
	tile = 52,
	tileText = 30,
	title = 24,
	timer = 18,
	timerHeight = 28,
	bar = 18,
	percent = 20,
	percentWidth = 52,
	pill = 17,
	pillWidth = 124,
	pillHeight = 30,
	who = 21,
	stack = 6, -- under the banner stack
})

-- Drips under the band: { x (fraction of the width), drop width, neck length } px; each one's lowest point stays
-- inside SIZE.rowTop, clear of the row.
local DRIPS = table.freeze({
	table.freeze({ 0.63, 12, 12 }),
	table.freeze({ 0.74, 9, 7 }),
})

local HEIGHT = SIZE.band + SIZE.rowTop + SIZE.row + SIZE.bottom

-- Band, ring and tile colour per BossMeterLogic tone; the meter's goo; the jelly tile.
local BAND = table.freeze({ fight = Theme.Bad, gold = Theme.Gold, mute = Theme.Info })
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
		Size = UDim2.fromOffset(SIZE.width, HEIGHT),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.04,
		ZIndex = z,
		Parent = parent,
	}, { Widgets.corner(SIZE.radius) })
	local ring = Widgets.ring(frame, Theme.Bad, SIZE.radius)

	-- The band: rounded on top, square at the bottom (a second strip covers its lower corners).
	local band = create("Frame", {
		Name = "Band",
		BorderSizePixel = 0,
		BackgroundColor3 = Theme.Bad,
		Size = UDim2.new(1, 0, 0, SIZE.band),
		ZIndex = z,
		Parent = frame,
	}, { Widgets.corner(SIZE.radius) })
	local foot = create("Frame", {
		Name = "BandFoot",
		BorderSizePixel = 0,
		BackgroundColor3 = Theme.Bad,
		Size = UDim2.new(1, 0, 0, SIZE.radius),
		Position = UDim2.fromOffset(0, SIZE.band - SIZE.radius),
		ZIndex = z,
		Parent = frame,
	})
	local goo: { Frame } = {}
	for i, d in DRIPS do
		local x, w, hang = d[1], d[2], d[3]
		-- One finger of goo (the Layout.GOO_EDGE recipe): its round top hides in the band.
		table.insert(
			goo,
			create("Frame", {
				Name = "Drip" .. i,
				BorderSizePixel = 0,
				BackgroundColor3 = Theme.Bad,
				Position = UDim2.new(x, 0, 0, SIZE.band - w),
				Size = UDim2.fromOffset(w, hang + w),
				ZIndex = z,
				Parent = frame,
			}, { Widgets.pill() })
		)
	end
	local timer = Widgets.chip({
		Name = "Timer",
		TextSize = SIZE.timer,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -SIZE.bandPadRight, 0, SIZE.band / 2),
		Size = UDim2.fromOffset(0, SIZE.timerHeight),
		ZIndex = z,
		Parent = frame,
	}, Theme.Gold)
	local title = Widgets.label({
		Name = "Title",
		Font = Theme.Font,
		TextSize = SIZE.title,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(SIZE.bandPadLeft, SIZE.band / 2),
		Size = UDim2.new(1, -SIZE.bandPadLeft - SIZE.bandPadRight, 0, SIZE.title + 4),
		ZIndex = z,
		Parent = frame,
	})

	local rowY = SIZE.band + SIZE.rowTop
	local tile = create("Frame", {
		Name = "IconTile",
		Position = UDim2.fromOffset(SIZE.padX, rowY),
		Size = UDim2.fromOffset(SIZE.tile, SIZE.tile),
		BackgroundColor3 = Theme.Bad,
		ZIndex = z,
		Parent = frame,
	}, { Widgets.pill(), Widgets.stroke(Theme.Ink, KIT.stroke) })
	Widgets.shade(tile)
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

	-- Right to left: the pill, the percent, then the meter (or the name) fills what is left.
	local midY = rowY + SIZE.row / 2
	local pill = Widgets.chip({
		Name = "Pill",
		TextSize = SIZE.pill,
		AutomaticSize = Enum.AutomaticSize.None,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -SIZE.padX, 0, midY),
		Size = UDim2.fromOffset(SIZE.pillWidth, SIZE.pillHeight),
		ZIndex = z,
		Parent = frame,
	})
	local pctRight = SIZE.padX + SIZE.pillWidth + SIZE.gap
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
	local leftX = SIZE.padX + SIZE.tile + SIZE.gap
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
		Font = Theme.Font,
		TextSize = SIZE.who,
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
		frame.Size = UDim2.fromOffset(math.min(SIZE.width, math.round(screen.banners.w)), HEIGHT)
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
		local tone = BAND[view.tone]
		ring.Color = tone
		band.BackgroundColor3 = tone
		foot.BackgroundColor3 = tone
		for _, part in goo do
			part.BackgroundColor3 = tone
		end
		tile.BackgroundColor3 = TILE[view.tone]
		if fill then
			fill.BackgroundColor3 = GOO[view.tone]
		end
		icon.Text = view.icon
		title.Text = view.title
		Widgets.inkOn(title, tone)
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
