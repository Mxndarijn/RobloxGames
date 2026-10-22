--!strict
--[[
	Leaderboard panel from the `Leaderboard` RemoteEvent
	({ stat = "TotalEarned", entries = { rank, userId, name, value } }).
]]

local Players = game:GetService("Players")

local UI = script.Parent.Parent
local Format = require(UI.Format)
local Widgets = require(UI.Widgets)

local Theme = Widgets.Theme
local create = Widgets.create

local Leaderboard = {}

local MEDALS = { "🥇", "🥈", "🥉" }

function Leaderboard.new(parent: Instance, _ctx: any)
	local panel = Widgets.panel(parent, "LeaderboardPanel", "Top earners", "🏆")

	local empty = Widgets.label({
		Name = "Empty",
		Text = "Loading leaderboard...",
		TextColor3 = Theme.Muted,
		Parent = panel.body,
	})

	local list = Widgets.scrollList({ Name = "List", Parent = panel.body }, 4)

	local rows = Widgets.keyedList(list, function(entry: any)
		return tostring(entry.userId)
	end, function(_entry: any)
		local frame = create("Frame", {
			Size = UDim2.new(1, -10, 0, 30),
			BackgroundColor3 = Theme.Row,
		}, { Widgets.corner(6) })
		local rank = Widgets.label({
			Font = Theme.Font,
			Size = UDim2.fromOffset(40, 30),
			Position = UDim2.fromOffset(8, 0),
			Parent = frame,
		})
		local name = Widgets.label({
			Size = UDim2.new(1, -150, 1, 0),
			Position = UDim2.fromOffset(48, 0),
			Parent = frame,
		})
		local value = Widgets.label({
			Font = Theme.Font,
			TextColor3 = Theme.Accent,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 0),
			Size = UDim2.new(0, 96, 1, 0),
			Parent = frame,
		})
		return { instance = frame, rank = rank, name = name, value = value }
	end, function(row: any, entry: any)
		local isMe = Players.LocalPlayer and entry.userId == Players.LocalPlayer.UserId
		row.rank.Text = MEDALS[entry.rank] or `#{entry.rank}`
		row.rank.TextColor3 = if entry.rank <= 3 then Theme.Gold else Theme.Text
		row.name.Text = tostring(entry.name)
		row.value.Text = Format.formatCash(entry.value)
		row.instance.BackgroundColor3 = if isMe then Color3.fromRGB(60, 110, 80) else Theme.Row
	end)

	local self = { frame = panel.frame, close = panel.close }

	function self.setBoard(board: any)
		local entries = if type(board) == "table" and type(board.entries) == "table" then board.entries else {}
		local sorted = table.clone(entries)
		table.sort(sorted, function(a, b)
			return a.rank < b.rank
		end)
		empty.Visible = #sorted == 0
		empty.Text = "No entries yet"
		list.Visible = #sorted > 0
		rows.sync(sorted)
	end

	return self
end

return Leaderboard
