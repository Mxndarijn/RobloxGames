--!strict
--[[
	Goals panel: the server's goals (`State.goals`, rewards paid
	automatically) or, on a server without them, local goals derived from
	State (no rewards). See Goals. Each row: title, detail, progress bar;
	done rows are ticked and sorted last.
]]

local UI = script.Parent.Parent
local Goals = require(UI.Goals)
local ItemIconView = require(UI.ItemIconView)
local ItemIcons = require(UI.ItemIcons)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local GoalsPanel = {}

GoalsPanel.ICON = 40 -- item icon at the row's left (row is 72 tall)

function GoalsPanel.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "GoalsPanel", "Goals", "🎯", Color3.fromRGB(220, 110, 70))

	local summary = Widgets.label({
		Name = "Summary",
		Font = Theme.Font,
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(120, 18),
		Parent = panel.body, -- on the note line, clear of the X
	})
	local note = Widgets.label({
		Name = "Note",
		Text = "Just for fun",
		TextSize = 13,
		TextColor3 = Theme.Muted,
		Size = UDim2.new(1, -124, 0, 18),
		Parent = panel.body,
	})

	local list = Widgets.scrollList({
		Name = "List",
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 1, -24),
		Parent = panel.body,
	}, 6)

	local rarityNames: { string } = {}
	for i, rarity in ctx.Config.RARITIES do
		rarityNames[i] = rarity.name
	end

	local isOpen = false
	local icons: { [string]: any } = {}
	local rows = Widgets.keyedList(list, function(g: Goals.Goal)
		return g.id
	end, function(g: Goals.Goal)
		local frame = create("Frame", {
			Name = g.id,
			Size = UDim2.new(1, -10, 0, 72),
			BackgroundColor3 = Theme.Row,
		}, { Widgets.corner(8) })
		local icon = ItemIconView.new({
			Name = "Icon",
			Id = ItemIcons.forGoal(ItemIcons.of(ctx), g.id),
			Size = GoalsPanel.ICON,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
			Parent = frame,
		}, ItemIcons.of(ctx))
		icon.setActive(isOpen)
		icons[g.id] = icon
		local textX = 8 + GoalsPanel.ICON + 8
		local title = Widgets.label({
			Name = "GoalTitle",
			Font = Theme.Font,
			Size = UDim2.new(1, -(textX + 10), 0, 20),
			Position = UDim2.fromOffset(textX, 6),
			Parent = frame,
		})
		local detail = Widgets.label({
			Name = "Detail",
			TextSize = 13,
			TextColor3 = Theme.Muted,
			Size = UDim2.new(1, -(textX + 10), 0, 16),
			Position = UDim2.fromOffset(textX, 26),
			Parent = frame,
		})
		local nextStep = Widgets.label({
			Name = "NextStep",
			TextSize = 12,
			TextColor3 = Theme.Muted,
			Size = UDim2.new(1, -(textX + 10), 0, 14),
			Position = UDim2.fromOffset(textX, 42),
			Parent = frame,
		})
		local _, setBar =
			Widgets.bar(frame, Theme.Accent, UDim2.new(1, -(textX + 10), 0, 6), UDim2.new(0, textX, 1, -12))
		return { instance = frame, title = title, detail = detail, nextStep = nextStep, setBar = setBar }
	end, function(row: any, g: Goals.Goal)
		row.title.Text = (if g.done then "✅ " else "") .. g.title
		row.title.TextColor3 = if g.done then Theme.Muted else Theme.Text
		row.detail.Text = g.detail
		row.nextStep.Text = g.next or ""
		row.setBar(g.fraction)
		row.instance.BackgroundColor3 = if g.done then Theme.BgLight else Theme.Row
	end)

	-- Daily quest cards sit above the goals (LayoutOrder < 0): a header line, then one card per quest.
	local questRows = Widgets.keyedList(list, function(q: Goals.Quest)
		return q.id
	end, function(q: Goals.Quest)
		local frame = create("Frame", {
			Name = `Quest_{q.id}`,
			Size = UDim2.new(1, -10, 0, 64),
			BackgroundColor3 = Theme.Row,
		}, { Widgets.corner(8) })
		local icon = ItemIconView.new({
			Name = "Icon",
			Id = ItemIcons.forGoal(ItemIcons.of(ctx), q.icon),
			Size = GoalsPanel.ICON,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 8, 0.5, 0),
			Parent = frame,
		}, ItemIcons.of(ctx))
		icon.setActive(isOpen)
		icons[`Quest_{q.id}`] = icon
		local textX = 8 + GoalsPanel.ICON + 8
		local right = 86 -- room for the Claim button
		local title = Widgets.label({
			Name = "QuestTitle",
			Font = Theme.Font,
			Size = UDim2.new(1, -(textX + right), 0, 20),
			Position = UDim2.fromOffset(textX, 6),
			Parent = frame,
		})
		local detail = Widgets.label({
			Name = "Detail",
			TextSize = 13,
			TextColor3 = Theme.Muted,
			Size = UDim2.new(1, -(textX + right), 0, 16),
			Position = UDim2.fromOffset(textX, 26),
			Parent = frame,
		})
		local _, setBar =
			Widgets.bar(frame, Theme.Accent, UDim2.new(1, -(textX + right), 0, 6), UDim2.new(0, textX, 1, -12))
		local row: any = { instance = frame, title = title, detail = detail, setBar = setBar, index = q.index }
		row.claim = Widgets.button(
			{
				Name = "Claim",
				Text = "Claim",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(70, 32),
			},
			Theme.Good,
			function()
				if ctx.request then
					ctx.request("ClaimQuest", function() end, row.index)
				end
			end
		)
		row.claim.instance.Parent = frame
		return row
	end, function(row: any, q: Goals.Quest)
		row.index = q.index
		row.title.Text = (if q.claimed then "✅ " else "⭐ ") .. q.title
		row.title.TextColor3 = if q.claimed then Theme.Muted else Theme.Text
		row.detail.Text = `{q.detail} · {q.reward}`
		row.setBar(q.fraction)
		row.instance.BackgroundColor3 = if q.claimed then Theme.BgLight else Theme.Row
		row.instance.LayoutOrder = q.index - 10
		row.claim.instance.Visible = q.done and not q.claimed
	end)
	local header = create("Frame", {
		Name = "QuestHeader",
		Size = UDim2.new(1, -10, 0, 22),
		BackgroundTransparency = 1,
		LayoutOrder = -20,
	})
	Widgets.label({
		Name = "Title",
		Text = "Daily quests",
		Font = Theme.Font,
		TextColor3 = Theme.Accent,
		Size = UDim2.fromScale(0.5, 1),
		Parent = header,
	})
	local headerReset = Widgets.label({
		Name = "Reset",
		TextSize = 13,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.5, 1),
		Parent = header,
	})

	local self = { frame = panel.frame, close = panel.close }

	function self.setOpen(open: boolean)
		isOpen = open
		for _, icon in icons do
			icon.setActive(open)
		end
	end

	function self.update(state: any)
		local server = Goals.fromServer(state.goals)
		local goals = server or Goals.derive(state, rarityNames)
		note.Text = if server then "🎁 Rewards pay out automatically" else "Just for fun"
		summary.Text = Goals.summary(goals)
		rows.sync(Goals.sorted(goals))
		local quests, resets = Goals.quests(state.dailyQuests)
		header.Parent = if #quests > 0 then list else nil
		headerReset.Text = resets
		questRows.sync(quests)
		Widgets.restack(list)
	end

	return self
end

return GoalsPanel
