--!strict
--[[
	Leaderboard panel: the five Hall of Fame boards (Leaderboards.BOARDS), readable from anywhere.

	A row of five tabs (one per board, in BOARDS order; the shown one wears its board's accent colour, the
	others the secondary Info jelly), the board's title, then up to ten rows in a scroll list: rank "#k"
	(gold, silver and bronze tints for the top three), the player's name and the value (Leaderboards.format:
	gold "$1.5K" on cash boards, plain "1.5K" on counts). The local player's row is the highlighted BgLight
	row with a mint name. An empty board shows one muted line. Pinned to the bottom, the "You" line: your
	rank and value when you are in the top ten, else your value from State.boards.

	`setBoard` keeps the latest `Leaderboard` payload per stat (init.client forwards every one) and redraws
	when that tab is shown; `update(state)` reads State.boards. The text rules (`rows`, `youText`) are pure.
]]

local UI = script.Parent.Parent
local Layout = require(UI.Layout)
local Leaderboards = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Leaderboards"))
local Widgets = require(UI.Widgets)
local WorldLeaderboard = require(UI.WorldLeaderboard)

local Theme = Widgets.Theme
local create = Widgets.create

local LeaderboardPanel = {}

LeaderboardPanel.DEFAULT = "TotalEarned"
LeaderboardPanel.MAX_ROWS = WorldLeaderboard.MAX_ROWS
LeaderboardPanel.EMPTY = "No entries yet"
LeaderboardPanel.LOADING = "Loading the board"

-- Short tab labels by stat (the board titles are too long for five tabs across a phone card).
LeaderboardPanel.TABS = table.freeze({
	Dex = "SlimeDex",
	WeeklyEarned = "Weekly",
	TotalEarned = "Earners",
	Steals = "Steals",
	Merges = "Merges",
})

-- Body parts top to bottom (design px; the body is Layout.panelBody of the card).
LeaderboardPanel.ROWS = table.freeze({
	tabs = table.freeze({ y = 0, h = Layout.MIN_TOUCH_DESIGN, gap = 6, size = 15 }),
	title = table.freeze({ y = Layout.MIN_TOUCH_DESIGN + 8, h = 26, size = 20 }),
	listTop = Layout.MIN_TOUCH_DESIGN + 8 + 26 + 6,
	row = table.freeze({ h = 40, gap = 6, pad = 12, rankW = 44, rank = 17, name = 16, value = 17, valueW = 130 }),
	empty = table.freeze({ h = 30, size = Layout.MIN_TEXT }),
	footer = table.freeze({ h = 34, gap = 8, size = 17 }),
})

export type Row = { rank: number, rankText: string, name: string, value: string, isMe: boolean }

-- A board payload -> at most MAX_ROWS display rows, by rank, the local player's marked.
function LeaderboardPanel.rows(board: any, myUserId: number?): { Row }
	local out: { Row } = {}
	for _, row in WorldLeaderboard.rows(board, myUserId, LeaderboardPanel.MAX_ROWS) do
		table.insert(out, {
			rank = row.rank,
			rankText = `#{row.rank}`,
			name = row.name,
			value = row.value,
			isMe = row.isMe,
		})
	end
	return out
end

-- The footer line: "You: #3  $1.5K" in the top ten, "You: #48  $90" or "You: #1000+  $90" outside it (State.boardRanks),
-- "You: $90" before the first ranking, "You: no score yet" while State has no value for the board.
function LeaderboardPanel.youText(rows: { Row }, stat: any, myValue: any, myRank: any): string
	for _, row in rows do
		if row.isMe then
			return `You: {row.rankText}  {row.value}`
		end
	end
	if type(myValue) ~= "number" or myValue ~= myValue then
		return "You: no score yet"
	end
	local rank = Leaderboards.rankText(myRank)
	local value = Leaderboards.format(stat, myValue)
	return if rank then `You: {rank}  {value}` else `You: {value}`
end

-- Rank text colour: gold, silver and bronze tints for the top three, Muted below.
local MEDALS = table.freeze({ Theme.Gold, Theme.Silver, Theme.Bronze })
function LeaderboardPanel.rankColor(rank: number): Color3
	return MEDALS[rank] or Theme.Muted
end

local function localUserId(ctx: any): number?
	if type(ctx) == "table" and type(ctx.userId) == "number" then
		return ctx.userId
	end
	local player = (game:GetService("Players") :: any).LocalPlayer
	return if player then player.UserId else nil
end

function LeaderboardPanel.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "LeaderboardPanel", "Leaderboards", "🏆")
	local R = LeaderboardPanel.ROWS
	local myUserId = localUserId(ctx)
	local selected: string = LeaderboardPanel.DEFAULT
	local payloads: { [string]: any } = {}
	local mine: { [string]: any } = {}
	local ranks: { [string]: any } = {} -- State.boardRanks

	-- Tabs: five equal jelly buttons across the body, `gap` apart; the last one ends on the body's right edge.
	local count = #Leaderboards.BOARDS
	local tabs: { [string]: any } = {}
	local render: () -> ()
	for i, def in Leaderboards.BOARDS do
		local stat = def.stat
		local left = math.floor((i - 1) * R.tabs.gap / count)
		local right = if i == count then 0 else math.floor(i * R.tabs.gap / count) - R.tabs.gap
		local tab = Widgets.button(
			{
				Name = `Tab_{stat}`,
				Text = LeaderboardPanel.TABS[stat] or def.title,
				TextSize = R.tabs.size,
				Position = UDim2.new((i - 1) / count, left, 0, R.tabs.y),
				Size = UDim2.new(1 / count, right - left, 0, R.tabs.h),
			},
			Theme.Info,
			function()
				selected = stat
				render()
			end
		)
		tab.instance.Parent = panel.body
		tabs[stat] = tab
	end

	local title = Widgets.label({
		Name = "BoardTitle",
		Font = Theme.Font,
		TextSize = R.title.size,
		TextColor3 = Theme.Text,
		Position = UDim2.fromOffset(2, R.title.y),
		Size = UDim2.new(1, -2, 0, R.title.h),
		Parent = panel.body,
	})

	local footerH = R.footer.gap + R.footer.h
	local list = Widgets.scrollList({
		Name = "List",
		Position = UDim2.fromOffset(0, R.listTop),
		Size = UDim2.new(1, 0, 1, -(R.listTop + footerH)),
		Parent = panel.body,
	}, R.row.gap)

	local empty = Widgets.label({
		Name = "Empty",
		Text = LeaderboardPanel.EMPTY,
		TextSize = R.empty.size,
		TextColor3 = Theme.Muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, R.empty.h),
		LayoutOrder = 0,
		Parent = list,
	})

	-- The "You" line, pinned to the bottom (Widgets.contentHeight reserves it under the list).
	local footer = create("Frame", {
		Name = "Footer",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 1, -footerH),
		Size = UDim2.new(1, 0, 0, footerH),
		Parent = panel.body,
	})
	local you = Widgets.status({
		Name = "You",
		TextSize = R.footer.size,
		TextColor3 = Theme.Text,
		Position = UDim2.fromOffset(0, R.footer.gap),
		Size = UDim2.new(1, 0, 0, R.footer.h),
		Parent = footer,
	})

	local rows = Widgets.keyedList(list, function(row: Row)
		return tostring(row.rank)
	end, function(row: Row)
		local frame = Widgets.rowFrame({
			Name = `Row_{row.rank}`,
			Size = UDim2.new(1, 0, 0, R.row.h),
		})
		local rank = Widgets.label({
			Name = "Rank",
			Font = Theme.Font,
			TextSize = R.row.rank,
			Position = UDim2.fromOffset(R.row.pad, 0),
			Size = UDim2.new(0, R.row.rankW, 1, 0),
			Parent = frame,
		})
		local nameX = R.row.pad + R.row.rankW
		local name = Widgets.label({
			Name = "Name",
			Font = Theme.Font,
			TextSize = R.row.name,
			Position = UDim2.fromOffset(nameX, 0),
			Size = UDim2.new(1, -(nameX + R.row.valueW + R.row.pad * 2), 1, 0),
			Parent = frame,
		})
		local value = Widgets.label({
			Name = "Value",
			Font = Theme.Font,
			TextSize = R.row.value,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -R.row.pad, 0, 0),
			Size = UDim2.new(0, R.row.valueW, 1, 0),
			Parent = frame,
		})
		return { instance = frame, rank = rank, name = name, value = value }
	end, function(view: any, row: Row)
		view.instance.BackgroundColor3 = if row.isMe then Theme.BgLight else Theme.Row
		view.rank.Text = row.rankText
		view.rank.TextColor3 = LeaderboardPanel.rankColor(row.rank)
		view.name.Text = row.name
		view.name.TextColor3 = if row.isMe then Theme.Good else Theme.Text
		view.value.Text = row.value
		local def = Leaderboards.get(selected)
		view.value.TextColor3 = if def and def.cash then Theme.Gold else Theme.Text
	end)

	function render()
		local def = Leaderboards.get(selected)
		for stat, tab in tabs do
			local on = stat == selected
			local board = Leaderboards.get(stat)
			tab.setColor(if on and board then Widgets.color3(board.accent) else Theme.Info)
			tab.instance:SetAttribute("Selected", on)
		end
		title.Text = if def then def.title else ""
		local payload = payloads[selected]
		local shown = LeaderboardPanel.rows(payload, myUserId)
		empty.Visible = #shown == 0
		empty.Text = if payload == nil then LeaderboardPanel.LOADING else LeaderboardPanel.EMPTY
		rows.sync(shown)
		you.Text = LeaderboardPanel.youText(shown, selected, mine[selected], ranks[selected])
	end

	local self = { frame = panel.frame, close = panel.close }

	-- Keeps the latest payload of its board; redraws when that board is shown.
	function self.setBoard(board: any)
		if type(board) ~= "table" or Leaderboards.get(board.stat) == nil then
			return
		end
		payloads[board.stat] = board
		if board.stat == selected then
			render()
		end
	end

	function self.update(state: any)
		mine = if type(state) == "table" and type(state.boards) == "table" then state.boards else {}
		ranks = if type(state) == "table" and type(state.boardRanks) == "table" then state.boardRanks else {}
		render()
	end

	-- The board shown (a stat); for the tabs and tests.
	function self.select(stat: string)
		if Leaderboards.get(stat) then
			selected = stat
			render()
		end
	end

	render()
	return self
end

return LeaderboardPanel
