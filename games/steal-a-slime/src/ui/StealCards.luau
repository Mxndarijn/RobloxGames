--!strict
--[[
	StealCards (client): the owner's steal alarm in the top banner stack. A pink-ringed card per thief
	("Ann is stealing your slime!"), a short "Ann has stolen one of your slimes" card with a draining bar
	after a theft, and a "+N more" chip past StealCardsLogic.MAX_CARDS. Which cards show is
	StealCardsLogic; this module only draws them.
]]

local TweenService = game:GetService("TweenService")

local Layout = require(script.Parent.Layout)
local StealCardsLogic = require(script.Parent.StealCardsLogic)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local SIZE = table.freeze({
	icon = 44,
	title = 22,
	sub = 16,
	more = 18,
	pad = 8,
	gap = 10,
	bar = 4,
	stack = 20, -- between cards; the Ink ring takes 3 px of it on each side
})

local ICON = table.freeze({ stealing = "🚨", stolen = "💔" })

local StealCards = {}

export type StealCards = {
	frame: Frame,
	update: (state: any, now: number) -> (),
	tick: (now: number) -> (),
}

local function nameMarkup(name: string): string
	local safe = string.gsub(string.gsub(string.gsub(name, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")
	return `<font color="#{Theme.Bad:ToHex()}">{safe}</font>`
end

local function buildCard(parent: Instance, order: number): any
	local card = create("Frame", {
		Name = "Card",
		LayoutOrder = order,
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.05,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ClipsDescendants = false,
		Parent = parent,
	}, {
		Widgets.corner(Layout.NOTICE_RADIUS),
	})
	-- No UIPadding on the card itself: it would pull the Ink ring (a child frame) inside the pink one.
	Widgets.ring(card, Theme.Bad, Layout.NOTICE_RADIUS)
	local row = create("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = card,
	}, {
		create("UIPadding", {
			PaddingLeft = UDim.new(0, SIZE.pad),
			PaddingRight = UDim.new(0, SIZE.pad + 4),
			PaddingTop = UDim.new(0, SIZE.pad),
			PaddingBottom = UDim.new(0, SIZE.pad),
		}),
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, SIZE.gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local icon = Widgets.iconBadge({ LayoutOrder = 1, Parent = row }, ICON.stealing, Theme.Bad, SIZE.icon)
	local iconCorner = icon:FindFirstChildOfClass("UICorner") :: UICorner
	iconCorner.CornerRadius = UDim.new(0.5, 0) -- a round badge
	icon.TextSize = math.floor(SIZE.icon * 0.7)
	local column = create("Frame", {
		Name = "Text",
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -(SIZE.icon + SIZE.gap), 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = row,
	}, { Widgets.list(Enum.FillDirection.Vertical, 0, Enum.HorizontalAlignment.Left) })
	local title = Widgets.label({
		Name = "Title",
		LayoutOrder = 1,
		Font = Theme.Font,
		TextSize = SIZE.title,
		RichText = true,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = column,
	})
	local sub = Widgets.label({
		Name = "Sub",
		LayoutOrder = 2,
		FontFace = Theme.FontBody,
		TextSize = SIZE.sub,
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = column,
	})
	-- The "stolen" card's time left: a pink line along the bottom edge that drains to the left.
	local bar = create("Frame", {
		Name = "Timer",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, Layout.NOTICE_RADIUS, 1, -1),
		Size = UDim2.new(1, -2 * Layout.NOTICE_RADIUS, 0, SIZE.bar),
		BackgroundColor3 = Theme.Bad,
		BorderSizePixel = 0,
		Visible = false,
		Parent = card,
	}, { Widgets.pill() })
	return { card = card, icon = icon, title = title, sub = sub, bar = bar, barWidth = bar.Size }
end

function StealCards.new(parent: Instance, ctx: any, order: number): StealCards
	local frame = create("Frame", {
		Name = "StealAlert",
		LayoutOrder = order,
		Visible = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, { Widgets.list(Enum.FillDirection.Vertical, SIZE.stack, Enum.HorizontalAlignment.Center) })

	-- The cards and the chip are built on the first theft, so a quiet HUD holds only this empty frame.
	local slots = {}
	local more: TextLabel? = nil
	local function build(): TextLabel
		if more then
			return more
		end
		for i = 1, StealCardsLogic.MAX_CARDS do
			slots[i] = buildCard(frame, i)
		end
		local chip = Widgets.label({
			Name = "More",
			LayoutOrder = StealCardsLogic.MAX_CARDS + 1,
			Visible = false,
			Font = Theme.Font,
			TextSize = SIZE.more,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.None,
			BackgroundTransparency = 0,
			BackgroundColor3 = Theme.Bad,
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			Parent = frame,
		}, {
			Widgets.pill(),
			Widgets.stroke(Theme.Ink, Widgets.KIT.rowStroke),
			create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
		})
		Widgets.inkOn(chip, Theme.Bad)
		more = chip
		return chip
	end

	local memory = StealCardsLogic.new()
	local shownSig = ""

	local function render(now: number)
		local cards, hidden = StealCardsLogic.cards(memory, now)
		local parts = {}
		for _, card in cards do
			table.insert(parts, `{card.kind}:{card.thief}:{card.startedAt or ""}`)
		end
		local sig = `{table.concat(parts, ";")}|{hidden}`
		if sig == shownSig then
			return
		end
		shownSig = sig
		if #cards == 0 and more == nil then
			frame.Visible = false
			return
		end
		local chip = build()
		for i, slot in slots do
			local card = cards[i]
			slot.card.Visible = card ~= nil
			if card then
				slot.icon.Text = ICON[card.kind]
				slot.title.Text = StealCardsLogic.title(card, nameMarkup(ctx.playerName(card.thief)))
				-- Several cards: only the first keeps its hint line, so the stack stays short.
				local sub = if i == 1 then StealCardsLogic.subtitle(card) else nil
				slot.sub.Text = sub or ""
				slot.sub.Visible = sub ~= nil
				local timed = card.kind == "stolen"
				slot.bar.Visible = timed
				if timed then
					local left = math.clamp(
						(card.startedAt :: number) + StealCardsLogic.STOLEN_SECONDS - now,
						0,
						StealCardsLogic.STOLEN_SECONDS
					)
					local full = slot.barWidth
					slot.bar.Size = UDim2.new(
						full.X.Scale * left / StealCardsLogic.STOLEN_SECONDS,
						full.X.Offset * left / StealCardsLogic.STOLEN_SECONDS,
						full.Y.Scale,
						full.Y.Offset
					)
					TweenService:Create(
						slot.bar,
						TweenInfo.new(left, Enum.EasingStyle.Linear),
						{ Size = UDim2.new(0, 0, full.Y.Scale, full.Y.Offset) }
					):Play()
				end
			end
		end
		local moreText = StealCardsLogic.moreText(hidden)
		chip.Text = moreText or ""
		chip.Visible = moreText ~= nil
		frame.Visible = #cards > 0
	end

	local self = {} :: StealCards
	self.frame = frame
	function self.update(state: any, now: number)
		memory = StealCardsLogic.observe(memory, state.slimes, now)
		render(now)
	end
	function self.tick(now: number)
		render(now)
	end
	return self
end

return StealCards
