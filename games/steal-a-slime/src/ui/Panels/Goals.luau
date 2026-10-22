--!strict
--[[
	Goals panel: the server's goals (`State.goals`, rewards paid automatically) or, on a server without them,
	local goals derived from State (no rewards). See Goals.

	Top line: the payout note and a green "n/m done" chip. The scroll list holds two sections: "Daily quests"
	(with a "Resets in" chip) over highlighted quest rows, then "Milestones" over the goal rows. A row is the
	goal's item icon, its name, a thin green bar and a muted meta line under it (progress and stage left, the
	next target right), and one fixed right slot (Layout.ROW_SLOT): the reward in a sunken Ink well, or for a
	finished quest the gold "Claim $100" button. A finished goal sinks to the bottom of its section, faded,
	with a green "Done" (or "Claimed") well in that slot.
]]

local UI = script.Parent.Parent
local Goals = require(UI.Goals)
local ItemIconView = require(UI.ItemIconView)
local ItemIcons = require(UI.ItemIcons)
local Layout = require(UI.Layout)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local GoalsPanel = {}

GoalsPanel.ICON = 50 -- item icon tile at the row's left

-- Design px and text sizes of the panel's parts.
local ROW = table.freeze({
	h = 74,
	pad = 10,
	gap = 12, -- icon to text, text to the right slot
	name = 17,
	nameY = 8,
	nameH = 20,
	reward = 16, -- the reward well and the Claim button
	barY = 33,
	bar = 10,
	meta = Layout.MIN_TEXT,
	metaY = 49,
	metaH = 17,
	fade = 0.35, -- a finished row's background transparency
	scrollBar = 10,
	listGap = 8,
})

local TOP = table.freeze({
	h = 26,
	gap = 6, -- top line to list
	summaryW = 130, -- room kept for the "n/m done" chip
	note = Layout.MIN_TEXT,
	chip = 15,
	heading = 17,
	headingH = 30,
	resetChip = Layout.MIN_TEXT,
	resetChipH = 24,
})

-- Section order in the list: quests, then goals.
local ORDER = table.freeze({ questHeader = -100, quest = -90, claimedQuest = -60, goalHeader = -10 })

-- What a row's right slot says (Layout.ROW_SLOT).
GoalsPanel.DONE = "✅ Done"
GoalsPanel.CLAIMED = "✅ Claimed"

-- The Claim button's label: the cash it pays ("Claim $100"), or "Claim boost" for a timed boost.
function GoalsPanel.claimText(reward: string, boost: boolean): string
	local cash = string.gsub(reward, "^%+", "")
	if boost or cash == "" then
		return if boost then "Claim boost" else "Claim"
	end
	return `Claim {cash}`
end

local function headingRow(name: string, text: string, order: number): (Frame, TextLabel)
	local frame = create("Frame", {
		Name = name,
		Size = UDim2.new(1, -ROW.scrollBar, 0, TOP.headingH),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	})
	local title = Widgets.label({
		Name = "Title",
		Text = text,
		Font = Theme.Font,
		TextSize = TOP.heading,
		TextColor3 = Theme.Text,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.new(0.5, 0, 0, TOP.heading + 4),
		Parent = frame,
	})
	return frame, title
end

-- A row's parts: icon tile, name, bar and meta line, and the right slot: a sunken Ink well holding the
-- reward (or Done / Claimed once finished).
local function rowParts(frame: Frame, titleName: string, iconId: string, ctx: any): any
	local slot = Layout.ROW_SLOT
	local icon = ItemIconView.new({
		Name = "Icon",
		Id = iconId,
		Size = GoalsPanel.ICON,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, ROW.pad, 0.5, 0),
		Parent = frame,
	}, ItemIcons.of(ctx))
	local textX = ROW.pad + GoalsPanel.ICON + ROW.gap
	local textW = -(textX + ROW.gap + slot.w + ROW.pad)
	local title = Widgets.label({
		Name = titleName,
		Font = Theme.Font,
		TextSize = ROW.name,
		Size = UDim2.new(1, textW, 0, ROW.nameH),
		Position = UDim2.fromOffset(textX, ROW.nameY),
		Parent = frame,
	})
	local reward = Widgets.status({
		Name = "Reward",
		TextSize = ROW.reward,
		TextColor3 = Theme.Gold,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -ROW.pad, 0.5, 0),
		Size = UDim2.fromOffset(slot.w, slot.h),
		Parent = frame,
	})
	local _, setBar = Widgets.bar(frame, Theme.Good, UDim2.new(1, textW, 0, ROW.bar), UDim2.fromOffset(textX, ROW.barY))
	local detail = Widgets.label({
		Name = "Detail",
		TextSize = ROW.meta,
		TextColor3 = Theme.Muted,
		Size = UDim2.new(1, textW, 0, ROW.metaH),
		Position = UDim2.fromOffset(textX, ROW.metaY),
		Parent = frame,
	})
	local nextStep = Widgets.label({
		Name = "NextStep",
		TextSize = ROW.meta,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.None,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(ROW.pad + slot.w + ROW.gap), 0, ROW.metaY),
		Size = UDim2.fromOffset(0, ROW.metaH),
		Parent = frame,
	})
	return {
		instance = frame,
		icon = icon,
		textX = textX,
		textW = textW,
		title = title,
		reward = reward,
		setBar = setBar,
		detail = detail,
		nextStep = nextStep,
	}
end

-- Name, bar, meta line (`nextText` right-aligned beside it) and the faded look of a finished row.
local function paintRow(row: any, name: string, done: boolean, fraction: number, meta: string, nextText: string?)
	row.title.Text = name
	row.title.TextColor3 = if done then Theme.Muted else Theme.Text
	row.setBar(fraction)
	row.detail.Text = meta
	row.nextStep.Text = nextText or ""
	local nextW = if nextText then math.ceil(Layout.lineWidth(nextText, ROW.meta)) + 2 else 0
	row.nextStep.Size = UDim2.fromOffset(nextW, ROW.metaH)
	row.detail.Size = UDim2.new(1, row.textW - (nextW + (if nextW > 0 then 6 else 0)), 0, ROW.metaH)
	row.instance.BackgroundTransparency = if done then ROW.fade else 0
end

-- The right slot's well: the reward in gold, Done / Claimed in green, hidden behind a Claim.
local function setSlot(row: any, text: string?, color: Color3)
	row.reward.Visible = text ~= nil
	row.reward.Text = text or ""
	row.reward.TextColor3 = color
end

function GoalsPanel.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "GoalsPanel", "Goals", "🎯")

	local summary = Widgets.chip({
		Name = "Summary",
		TextSize = TOP.chip,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(0, TOP.h),
		Parent = panel.body, -- on the note line, clear of the X
	}, Theme.Good)
	local note = Widgets.label({
		Name = "Note",
		Text = "Just for fun",
		TextSize = TOP.note,
		TextColor3 = Theme.Muted,
		Size = UDim2.new(1, -TOP.summaryW, 0, TOP.h),
		Parent = panel.body,
	})

	local listTop = TOP.h + TOP.gap
	local list = Widgets.scrollList({
		Name = "List",
		Position = UDim2.fromOffset(0, listTop),
		Size = UDim2.new(1, 0, 1, -listTop),
		Parent = panel.body,
	}, ROW.listGap)

	local rarityNames: { string } = {}
	for i, rarity in ctx.Config.RARITIES do
		rarityNames[i] = rarity.name
	end

	local isOpen = false
	local icons: { [string]: any } = {}

	local function newRowFrame(name: string, fill: Color3): Frame
		return Widgets.rowFrame({
			Name = name,
			Size = UDim2.new(1, -ROW.scrollBar, 0, ROW.h),
			BackgroundColor3 = fill,
		})
	end

	local rows = Widgets.keyedList(list, function(g: Goals.Goal)
		return g.id
	end, function(g: Goals.Goal)
		local row = rowParts(newRowFrame(g.id, Theme.Row), "GoalTitle", ItemIcons.forGoal(ItemIcons.of(ctx), g.id), ctx)
		row.icon.setActive(isOpen)
		icons[g.id] = row.icon
		return row
	end, function(row: any, g: Goals.Goal)
		paintRow(row, g.title, g.done, g.fraction, g.meta or g.detail, g.nextShort)
		if g.done then
			setSlot(row, GoalsPanel.DONE, Theme.Good)
		else
			setSlot(row, g.reward, Theme.Gold)
		end
	end)

	local questRows = Widgets.keyedList(list, function(q: Goals.Quest)
		return q.id
	end, function(q: Goals.Quest)
		local row = rowParts(
			newRowFrame(`Quest_{q.id}`, Theme.BgLight),
			"QuestTitle",
			ItemIcons.forGoal(ItemIcons.of(ctx), q.icon),
			ctx
		)
		row.icon.setActive(isOpen)
		icons[`Quest_{q.id}`] = row.icon
		row.index = q.index
		local slot = Layout.ROW_SLOT
		row.claim = Widgets.button(
			{
				Name = "Claim",
				Text = "Claim",
				TextSize = ROW.reward,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -ROW.pad, 0.5, 0),
				Size = UDim2.fromOffset(slot.w, slot.h),
			},
			Theme.Gold,
			function()
				if ctx.request then
					ctx.request("ClaimQuest", function() end, row.index)
				end
			end
		)
		row.claim.instance.Parent = row.instance
		return row
	end, function(row: any, q: Goals.Quest, index: number)
		row.index = q.index
		paintRow(row, q.title, q.claimed, q.fraction, q.detail, nil)
		local claimable = q.done and not q.claimed
		row.claim.instance.Visible = claimable
		row.claim.setText(GoalsPanel.claimText(q.reward, q.boost))
		if q.claimed then
			setSlot(row, GoalsPanel.CLAIMED, Theme.Good)
		else
			setSlot(row, if claimable then nil else q.reward, Theme.Gold)
		end
		row.instance.LayoutOrder = (if q.claimed then ORDER.claimedQuest else ORDER.quest) + index
	end)

	local questHeader = headingRow("QuestHeader", "Daily quests", ORDER.questHeader)
	local headerReset = Widgets.chip({
		Name = "Reset",
		FontFace = Theme.FontBody,
		TextSize = TOP.resetChip,
		BackgroundColor3 = Theme.Row,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(0, TOP.resetChipH),
		Parent = questHeader,
	}, Theme.Muted)
	local goalHeader = headingRow("GoalHeader", "Milestones", ORDER.goalHeader)

	local self = { frame = panel.frame, close = panel.close }

	function self.setOpen(open: boolean)
		isOpen = open
		for _, icon in icons do
			icon.setActive(open)
		end
	end

	function self.update(state: any)
		local server = Goals.fromServer(state.goals, ctx.Config)
		local goals = server or Goals.derive(state, rarityNames)
		note.Text = if server then "🎁 Rewards pay out on their own" else "Just for fun"
		summary.Text = Goals.summary(goals)
		rows.sync(Goals.sorted(goals))
		local quests, resets = Goals.quests(state.dailyQuests)
		questHeader.Parent = if #quests > 0 then list else nil
		goalHeader.Parent = if #goals > 0 then list else nil
		headerReset.Text = resets
		questRows.sync(Goals.sortedQuests(quests))
		Widgets.restack(list)
	end

	return self
end

return GoalsPanel
