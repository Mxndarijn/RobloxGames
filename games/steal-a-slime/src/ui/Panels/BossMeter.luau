--!strict
--[[
	Boss card (top centre, under the HUD banner stack) while `State.boss` has a phase (BossMeterLogic). Read-only:
	hits are Bat swings, grabs the boss's prompt.

	Drawn like the notice cards (StealCards): deep teal glass in a coloured ring (pink while you fight it, gold when
	it is your moment, muted when it got away) with the crown on a round tile at the left. Two lines beside it: the
	title with an Ink timer chip at the right, then the goo meter and its percent (or a name instead) and one Ink pill
	that says what matters now.

	During the boss this is the one card at the top: the steal cards fold into a strip across its top
	(StealCards.strip, "Ann and Bo are stealing your slimes! · Chase them") in the card kind's colour. An open overlay
	(menu card, daily popup, bag panel) hides the card (`setMenuOpen`).
]]

local UI = script.Parent.Parent
local BossMeterLogic = require(UI.BossMeterLogic)
local Layout = require(UI.Layout)
local StealCards = require(UI.StealCards)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme

local N = Layout.NOTICE_CARD
local SIZE = table.freeze({
	pad = N.pad + 2, -- inside the card, every side (two lines need a little more room than one)
	line1 = 30, -- title and timer
	lineGap = 6,
	line2 = 30, -- meter or name, percent, pill
	timer = 16,
	timerHeight = 26,
	bar = 14,
	percent = 17,
	percentWidth = 46,
	pill = 15,
	pillWidth = 118,
	pillHeight = 28,
	strip = 30, -- the alarm strip across the top
	stripText = 17,
	stripPad = 10, -- text inset inside the strip
	stripRadius = 10,
})

local HEIGHT = SIZE.pad + SIZE.line1 + SIZE.lineGap + SIZE.line2 + SIZE.pad
local STRIP_HEIGHT = SIZE.pad + SIZE.strip -- what the strip adds on top (the body keeps its own top pad)

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

-- `steals` (optional): the HUD's StealCards, folded into the alarm strip while the card shows.
function BossMeter.new(parent: Instance, ctx: any, steals: StealCards.StealCards?)
	local z = Layout.ZINDEX.Banners
	local frame, ring = Widgets.noticeCard({
		Name = "BossMeter",
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Layout.TOP),
		Size = UDim2.fromOffset(Layout.BANNER_WIDTH, HEIGHT),
		ZIndex = z,
		Parent = parent,
	}, Theme.Bad)
	-- The boss rows; they move down under the alarm strip when it shows.
	local body = Widgets.create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, HEIGHT),
		ZIndex = z,
		Parent = frame,
	})
	local strip = Widgets.create("Frame", {
		Name = "StealStrip",
		Visible = false,
		BackgroundColor3 = Theme.Bad,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(SIZE.pad, SIZE.pad),
		Size = UDim2.new(1, -2 * SIZE.pad, 0, SIZE.strip),
		ZIndex = z,
		Parent = frame,
	}, { Widgets.corner(SIZE.stripRadius), Widgets.stroke(Theme.Ink, Widgets.KIT.rowStroke) })
	local stripText = Widgets.label({
		Name = "StealText",
		Font = Theme.Font,
		TextSize = SIZE.stripText,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(SIZE.stripPad, 0),
		Size = UDim2.new(1, -2 * SIZE.stripPad, 1, 0),
		ZIndex = z,
		Parent = strip,
	})
	-- The round crown tile; the icon is the tile's own text.
	local tile = Widgets.noticeIcon({
		Name = "IconTile",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, SIZE.pad, 0.5, 0),
		ZIndex = z,
		Parent = body,
	}, BossMeterLogic.ICON, Theme.Bad)
	local icon = tile

	local leftX = SIZE.pad + N.icon + N.gap
	-- Line 1: the title, the timer chip at the right.
	local line1Y = SIZE.pad + SIZE.line1 / 2
	local timer = Widgets.chip({
		Name = "Timer",
		TextSize = SIZE.timer,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -SIZE.pad - 4, 0, line1Y),
		Size = UDim2.fromOffset(0, SIZE.timerHeight),
		ZIndex = z,
		Parent = body,
	}, Theme.Gold)
	local title = Widgets.label({
		Name = "Title",
		Font = Theme.Font,
		TextSize = N.title,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(leftX, line1Y),
		Size = UDim2.new(1, -leftX - SIZE.pad - 80, 0, N.title + 4), -- 80: room for the timer chip
		ZIndex = z,
		Parent = body,
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
		Parent = body,
	})
	local pctRight = SIZE.pad + 4 + SIZE.pillWidth + N.gap
	local percent = Widgets.label({
		Name = "Percent",
		Font = Theme.Font,
		TextSize = SIZE.percent,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -pctRight, 0, midY),
		Size = UDim2.fromOffset(SIZE.percentWidth, SIZE.percent + 6),
		ZIndex = z,
		Parent = body,
	})
	local barRight = pctRight + SIZE.percentWidth + N.gap
	local bar, setBar = Widgets.bar(
		body,
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
		TextSize = N.sub,
		TextColor3 = Theme.Muted,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(leftX, midY),
		Size = UDim2.new(1, -leftX - pctRight, 0, N.sub + 6),
		ZIndex = z,
		Parent = body,
	})

	local boss: any = nil
	local badgesBefore: number? = nil -- the player's boss badges before this fight, for the win's "+1 badge"
	local top = Layout.TOP
	local width = Layout.BANNER_WIDTH
	local hidden = false -- an overlay is open
	local bannerHeight: () -> number = function()
		return 0
	end

	local self = {}

	-- Top centre under the HUD banner stack (`bannerHeight`, layout px), as wide as the banners.
	function self.layout(screen: Layout.Screen, heightOfBanners: (() -> number)?)
		top = screen.banners.y
		bannerHeight = heightOfBanners or bannerHeight
		width = math.round(screen.banners.w) -- as wide as the notice cards
		frame.Size = UDim2.fromOffset(width, frame.Size.Y.Offset)
	end

	-- The strip's line: the hint goes when the whole line would not fit.
	local function stripLine(view: any): string
		local glyph = StealCards.ICON[view.kind]
		local line = `{glyph} {view.text}`
		if view.hint then
			local full = `{line} · {view.hint}`
			local room = width - 2 * SIZE.pad - 2 * SIZE.stripPad
			if Layout.lineWidth(full, SIZE.stripText, true) <= room then
				return full
			end
		end
		return line
	end

	-- An open overlay (MenuState.noticesVisible) hides the card; closing it brings it back.
	function self.setMenuOpen(isOpen: boolean)
		if hidden ~= isOpen then
			hidden = isOpen
			self.tick(ctx.serverNow())
		end
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
		if steals then
			steals.setFolded(view ~= nil)
		end
		frame.Visible = view ~= nil and not hidden
		if not view then
			return
		end
		local alarm = if steals then steals.strip(now) else nil
		strip.Visible = alarm ~= nil
		if alarm then
			local color = StealCards.COLOR[alarm.kind]
			strip.BackgroundColor3 = color
			stripText.Text = stripLine(alarm)
			Widgets.inkOn(stripText, color)
		end
		local lift = if alarm then STRIP_HEIGHT else 0
		body.Position = UDim2.fromOffset(0, lift)
		frame.Size = UDim2.fromOffset(width, HEIGHT + lift)
		local height = bannerHeight()
		frame.Position = UDim2.new(0.5, 0, 0, top + (if height > 0 then height + N.stack else 0))
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
