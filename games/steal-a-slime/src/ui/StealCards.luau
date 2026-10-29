--!strict
--[[
	StealCards (client, contract/notice-cards.md): the cards in the top banner stack. The owner's steal alarm
	("Ann is stealing your slime!" / "Ann and 2 others are stealing your slimes!", then "Ann has stolen one of your
	slimes"), and the notices: bonked, slime back
	home, base locked. Timed cards drain a bar along their bottom edge; a "+N more" chip counts what does not fit.
	The ring says what it is: pink danger, mint good news, gold guidance. Which cards show is StealCardsLogic;
	this module only draws them. While the boss card shows (`setFolded`), the cards fold into its alarm strip
	(`strip`) instead of stacking above it.
]]

local TweenService = game:GetService("TweenService")

local Layout = require(script.Parent.Layout)
local StealCardsLogic = require(script.Parent.StealCardsLogic)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local N = Layout.NOTICE_CARD
local SIZE = table.freeze({
	more = 18,
	bar = 4,
})

local ICON = table.freeze({ stealing = "🚨", stolen = "💔", bonked = "💥", home = "💚", locked = "🔒" })
local COLOR = table.freeze({
	stealing = Theme.Bad,
	stolen = Theme.Bad,
	bonked = Theme.Bad,
	home = Theme.Good,
	locked = Theme.Gold,
})

local StealCards = {}

export type StealCards = {
	frame: Frame,
	update: (state: any, now: number) -> (),
	tick: (now: number) -> (),
	setFolded: (folded: boolean) -> (),
	strip: (now: number) -> StealCardsLogic.Strip?,
}

-- Icon and colour per card kind, for the boss card's alarm strip.
StealCards.ICON = ICON
StealCards.COLOR = COLOR

local function nameMarkup(name: string): string
	local safe = string.gsub(string.gsub(string.gsub(name, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")
	return `<font color="#{Theme.Bad:ToHex()}">{safe}</font>`
end

local function buildCard(parent: Instance, order: number): any
	local card, ring = Widgets.noticeCard({
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, Theme.Bad)
	local row = create("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = card,
	}, {
		create("UIPadding", {
			PaddingLeft = UDim.new(0, N.pad),
			PaddingRight = UDim.new(0, N.pad + 4),
			PaddingTop = UDim.new(0, N.pad),
			PaddingBottom = UDim.new(0, N.pad),
		}),
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, N.gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local icon = Widgets.noticeIcon({ LayoutOrder = 1, Parent = row }, ICON.stealing, Theme.Bad)
	local column = create("Frame", {
		Name = "Text",
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -(N.icon + N.gap), 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = row,
	}, { Widgets.list(Enum.FillDirection.Vertical, 0, Enum.HorizontalAlignment.Left) })
	local title = Widgets.label({
		Name = "Title",
		LayoutOrder = 1,
		Font = Theme.Font,
		TextSize = N.title,
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
		TextSize = N.sub,
		TextColor3 = Theme.Muted,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = column,
	})
	-- A timed card's time left: a line in the ring's colour along the bottom edge that drains to the left.
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
	return { card = card, ring = ring, icon = icon, title = title, sub = sub, bar = bar, barWidth = bar.Size }
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
	}, { Widgets.list(Enum.FillDirection.Vertical, N.stack, Enum.HorizontalAlignment.Center) })

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
	local folded = false

	local function render(now: number)
		if folded then
			frame.Visible = false
			shownSig = ""
			return
		end
		local cards, hidden = StealCardsLogic.cards(memory, now)
		local names: { string } = {}
		local subs: { string? } = {}
		local parts = {}
		for i, card in cards do
			local who = if card.thief then ctx.playerName(card.thief) else card.name or "someone"
			names[i] = who
			-- Several cards: only the first keeps its hint line, so the stack stays short.
			subs[i] = if i == 1 then StealCardsLogic.subtitle(card, who, now) else nil
			local crew = if card.thieves then table.concat(card.thieves, ",") else ""
			table.insert(parts, `{card.kind}:{who}:{crew}:{card.startedAt or ""}:{subs[i] or ""}`)
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
				local color = COLOR[card.kind]
				slot.ring.Color = color
				slot.icon.BackgroundColor3 = color
				slot.bar.BackgroundColor3 = color
				slot.icon.Text = ICON[card.kind]
				local thieves = card.thieves
				slot.title.Text = if thieves and #thieves > 1
					then StealCardsLogic.thievesText(
						nameMarkup(names[i]),
						nameMarkup(ctx.playerName(thieves[2])),
						#thieves
					)
					else StealCardsLogic.title(card, nameMarkup(names[i]))
				local sub = subs[i]
				slot.sub.Text = sub or ""
				slot.sub.Visible = sub ~= nil
				local timed = card.endsAt ~= nil and card.startedAt ~= nil
				slot.bar.Visible = timed
				if timed then
					local total = math.max((card.endsAt :: number) - (card.startedAt :: number), 0.01)
					local left = math.clamp((card.endsAt :: number) - now, 0, total)
					local full = slot.barWidth
					slot.bar.Size = UDim2.new(
						full.X.Scale * left / total,
						full.X.Offset * left / total,
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
		memory = StealCardsLogic.observe(memory, state, now)
		render(now)
	end
	function self.tick(now: number)
		render(now)
	end
	-- The boss card is up: the cards hide and the boss card shows `strip` instead (and back when it goes).
	function self.setFolded(isFolded: boolean)
		if folded ~= isFolded then
			folded = isFolded
			render(ctx.serverNow())
		end
	end
	function self.strip(now: number): StealCardsLogic.Strip?
		return StealCardsLogic.strip(memory, now, ctx.playerName)
	end
	return self
end

return StealCards
