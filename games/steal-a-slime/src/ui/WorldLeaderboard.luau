--!strict
--[[
	WorldLeaderboard

	Fills in-world leaderboard SurfaceGuis from the `Leaderboard` RemoteEvent.
	Client-local: each player renders the
	board themselves and their own row is highlighted.

	Each payload is one board (`stat`, Leaderboards.BOARDS). A SurfaceGui under workspace is a board when it's
	named "Leaderboard", or sits inside one of the Hall of Fame board Models (Props.leaderboardBoard: Board >
	SurfaceGui "BoardGui" > Content > Rows) or a Model named "Leaderboard". It shows the stat in its Model's
	LeaderboardStat attribute (else the board its Model name belongs to, else Top Earners). Rows go into its descendant Frame "Rows" if there is
	one, else into a "Rows" frame created to fill the gui. Boards streamed
	in later bind on DescendantAdded. Row frames are "Row_<k>" with Rank /
	Name / Value labels, like Props.fillLeaderboard: rounded cards on the light face, the top three tinted
	(`rowStyle`).

	The pure helpers (`matches`, `rows`) run under Lune
	(tests/ui/WorldLeaderboard.spec.luau); `start` touches Roblox only when called.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Leaderboards = if Shared then require(Shared.Leaderboards) else require("../shared/Leaderboards")
local Visuals = if script then (game:GetService("ReplicatedStorage") :: any).Visuals else nil
local BoardFace = if Visuals then require(Visuals.BoardFace) else require("../visuals/shared/BoardFace")

export type Row = { rank: number, name: string, value: string, isMe: boolean }

local WorldLeaderboard = {}

WorldLeaderboard.MAX_ROWS = Config.LEADERBOARD_SIZE
WorldLeaderboard.GUI_NAMES = table.freeze({ "Leaderboard" })
local modelNames = { "Leaderboard" }
for _, def in Leaderboards.BOARDS do
	table.insert(modelNames, def.model)
end
WorldLeaderboard.MODEL_NAMES = table.freeze(modelNames)
WorldLeaderboard.ROWS_NAME = "Rows"

function WorldLeaderboard.matches(className: string, name: string, modelName: string?): boolean
	if className ~= "SurfaceGui" then
		return false
	end
	if table.find(WorldLeaderboard.GUI_NAMES, name) then
		return true
	end
	return modelName ~= nil and table.find(WorldLeaderboard.MODEL_NAMES, modelName) ~= nil
end

-- Board payload -> at most `max` display rows, sorted by rank. Bad payloads -> {}.
function WorldLeaderboard.rows(board: any, myUserId: number?, max: number?): { Row }
	local entries = if type(board) == "table" and type(board.entries) == "table" then board.entries else {}
	local stat = if type(board) == "table" then board.stat else nil
	local valid = {}
	for _, entry in entries do
		if type(entry) == "table" and type(entry.rank) == "number" then
			table.insert(valid, entry)
		end
	end
	table.sort(valid, function(a, b)
		return a.rank < b.rank
	end)
	local out: { Row } = {}
	for i, entry in valid do
		if i > (max or WorldLeaderboard.MAX_ROWS) then
			break
		end
		table.insert(out, {
			rank = entry.rank,
			name = tostring(entry.name or "?"),
			value = Leaderboards.format(stat, if type(entry.value) == "number" then entry.value else 0),
			isMe = myUserId ~= nil and entry.userId == myUserId,
		})
	end
	return out
end

-- The "You" line's label: "You #48" with my rank (State.boardRanks), "You" before the first ranking.
function WorldLeaderboard.youLabel(myRank: any): string
	local rank = Leaderboards.rankText(myRank)
	return if rank then `You {rank}` else "You"
end

-- The "You" line under a board's top 10: my value as the board shows it, or nil when I am in the rows already or
-- my value is unknown.
function WorldLeaderboard.youText(rows: { Row }, stat: any, myValue: any): string?
	for _, row in rows do
		if row.isMe then
			return nil
		end
	end
	if type(myValue) ~= "number" or myValue ~= myValue then
		return nil
	end
	return Leaderboards.format(stat, myValue)
end

-- Roblox side ---------------------------------------------------------------

-- Board colours (RGB) on the light face, like the Upcoming Events board; the same values as Props.BOARD_PALETTE
-- (a spec keeps them equal).
WorldLeaderboard.PALETTE = table.freeze({
	RowAlt = table.freeze({ 244, 232, 208 }),
	Me = table.freeze({ 179, 231, 191 }),
	Text = table.freeze({ 62, 40, 26 }),
	Muted = table.freeze({ 138, 106, 74 }),
	Value = table.freeze({ 24, 104, 56 }),
	Rank = table.freeze({ table.freeze({ 138, 88, 0 }), table.freeze({ 96, 102, 112 }), table.freeze({ 150, 73, 30 }) }),
})
-- The top three row cards: pale gold, silver and bronze (Props.MEDAL_FILL).
WorldLeaderboard.MEDAL_FILL = table.freeze({
	table.freeze({ 255, 226, 140 }),
	table.freeze({ 225, 230, 240 }),
	table.freeze({ 246, 204, 170 }),
})

-- A row card's fill and edge (RGB, nil = no edge): my row mint, the top three pale gold / silver / bronze with an
-- edge in their rank colour, the rest plain cards.
function WorldLeaderboard.rowStyle(rank: number, isMe: boolean): ({ number }, { number }?)
	local p = WorldLeaderboard.PALETTE
	if isMe then
		return p.Me, p.Value
	end
	local medal = WorldLeaderboard.MEDAL_FILL[rank]
	if medal then
		return medal, p.Rank[rank]
	end
	return p.RowAlt, nil
end

-- Built on first use: Color3 doesn't exist under Lune.
local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local COLORS: any = nil
local function colors(): any
	if COLORS == nil then
		local function c(t: { number }): Color3
			return Color3.fromRGB(t[1], t[2], t[3])
		end
		local p = WorldLeaderboard.PALETTE
		COLORS = {
			RowAlt = c(p.RowAlt),
			Me = c(p.Me),
			Text = c(p.Text),
			Muted = c(p.Muted),
			Value = c(p.Value),
			Rank = { c(p.Rank[1]), c(p.Rank[2]), c(p.Rank[3]) },
		}
	end
	return COLORS
end

-- Prefers the board's own "Rows" frame; ours (attribute OWN_ROWS) is only a
-- fallback and is dropped once the real one replicates in.
local OWN_ROWS = "UIRows"
local function rowsContainer(gui: SurfaceGui): Instance
	local own: Instance? = nil
	for _, inst in gui:GetDescendants() do
		if inst.Name == WorldLeaderboard.ROWS_NAME and inst:IsA("GuiObject") then
			if inst:GetAttribute(OWN_ROWS) then
				own = inst
			else
				if own then
					own:Destroy()
				end
				for _, other in gui:GetChildren() do
					if other ~= inst and other:GetAttribute(OWN_ROWS) then
						other:Destroy()
					end
				end
				return inst
			end
		end
	end
	if own then
		return own
	end
	local frame = Instance.new("Frame")
	frame.Name = WorldLeaderboard.ROWS_NAME
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame:SetAttribute(OWN_ROWS, true)
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, BoardFace.CHROME.rowGap)
	list.Parent = frame
	frame.Parent = gui
	return frame
end

-- Rows this client built (attribute OWN_ROW), as opposed to the server's (Props.fillLeaderboard).
WorldLeaderboard.OWN_ROW = "ClientRow"

-- Row_<k> of `container`: the server's row when it has one (any row of ours by that name is dropped, so no rank
-- shows twice), else ours, else a new one of ours. Every row comes from BoardFace.row, so they all look the same.
local function ensureRow(container: Instance, k: number): Frame
	local name = `Row_{k}`
	local server: Frame?, own: Frame? = nil, nil
	for _, child in container:GetChildren() do
		if child.Name ~= name then
			continue
		end
		if not (child:IsA("Frame") and child:FindFirstChild("Value")) then
			-- incomplete: ours goes, a server row still arriving stays hidden until it has its labels
			if child:GetAttribute(WorldLeaderboard.OWN_ROW) then
				child:Destroy()
			elseif child:IsA("GuiObject") then
				child.Visible = false
			end
		elseif child:GetAttribute(WorldLeaderboard.OWN_ROW) then
			if own then
				child:Destroy()
			else
				own = child :: Frame
			end
		elseif server then
			child:Destroy()
		else
			server = child :: Frame
		end
	end
	if server then
		if own then
			own:Destroy()
		end
		return server
	end
	if own then
		return own
	end
	local frame = BoardFace.row(k, WorldLeaderboard.MAX_ROWS, WorldLeaderboard.PALETTE)
	frame:SetAttribute(WorldLeaderboard.OWN_ROW, true)
	frame.Parent = container
	return frame
end

function WorldLeaderboard.render(gui: SurfaceGui, rows: { Row })
	local container = rowsContainer(gui)
	local shown = math.max(#rows, 1) -- row 1 doubles as the "no entries" line
	for k = 1, WorldLeaderboard.MAX_ROWS do
		if k > shown then
			for _, child in container:GetChildren() do
				if child.Name == `Row_{k}` and child:IsA("GuiObject") then
					child.Visible = false
				end
			end
			continue
		end
		local frame = ensureRow(container, k)
		frame.Visible = true
		local rank = frame:FindFirstChild("Rank") :: TextLabel
		local name = frame:FindFirstChild("Name") :: TextLabel
		local value = frame:FindFirstChild("Value") :: TextLabel
		local row = rows[k]
		if row == nil then
			frame.BackgroundTransparency = 1
			local edge = frame:FindFirstChild("Edge")
			if edge and edge:IsA("UIStroke") then
				edge.Enabled = false
			end
			rank.Text, value.Text = "", ""
			name.Text = "No entries yet"
			name.TextColor3 = colors().Muted
			continue
		end
		local fill, edge = WorldLeaderboard.rowStyle(row.rank, row.isMe)
		frame.BackgroundColor3 = rgb(fill)
		frame.BackgroundTransparency = 0
		local stroke = frame:FindFirstChild("Edge") :: UIStroke?
		if edge and not stroke then
			local s = Instance.new("UIStroke")
			s.Name = "Edge"
			s.Thickness = 2
			s.Parent = frame
			stroke = s
		end
		if stroke then
			stroke.Enabled = edge ~= nil
			if edge then
				stroke.Color = rgb(edge)
			end
		end
		rank.Text = `#{row.rank}`
		rank.TextColor3 = colors().Rank[row.rank] or colors().Text
		name.Text = row.name
		name.TextColor3 = colors().Text
		value.Text = row.value
	end
end

-- Fills (or hides) the board's "You" frame (Props.leaderboardBoard) with `text` and the `label` before it.
function WorldLeaderboard.renderYou(gui: SurfaceGui, text: string?, label: string?)
	local you = gui:FindFirstChild("You", true)
	if not (you and you:IsA("GuiObject")) then
		return
	end
	you.Visible = text ~= nil
	local value = you:FindFirstChild("Value")
	if text and value and value:IsA("TextLabel") then
		value.Text = text
	end
	local name = you:FindFirstChild("Name")
	if label and name and name:IsA("TextLabel") then
		name.Text = label
	end
end

export type Handle = {
	setBoard: (board: any) -> (),
	setMine: (boards: any, ranks: any) -> (),
	boards: () -> { SurfaceGui },
}

-- Binds every board under `root` (now and later) and returns a setter for
-- new Leaderboard payloads.
-- The stat a bound board shows: its Model's LeaderboardStat attribute, else its Model name's board, else the
-- podium board (Top Earners).
function WorldLeaderboard.statOf(model: Instance?): string
	local stat = if model then model:GetAttribute("LeaderboardStat") else nil
	if Leaderboards.get(stat) then
		return stat :: string
	end
	local def = if model then Leaderboards.forModel(model.Name) else nil
	return (def or Leaderboards.podium()).stat
end

function WorldLeaderboard.start(root: Instance, myUserId: number): Handle
	local bound: { [SurfaceGui]: string } = {} -- gui -> stat
	local latest: { [string]: { Row } } = {}
	local mine: { [string]: number } = {} -- my own value per stat (State.boards)
	local myRanks: { [string]: number } = {} -- my rank per stat (State.boardRanks)

	local function showYou(gui: SurfaceGui, stat: string)
		local text = WorldLeaderboard.youText(latest[stat] or {}, stat, mine[stat])
		local label = WorldLeaderboard.youLabel(myRanks[stat])
		local ok, err = pcall(function()
			WorldLeaderboard.renderYou(gui, text, label)
		end)
		if not ok then
			warn("[UI] world leaderboard You line failed:", err)
		end
	end

	local function consider(inst: Instance)
		if not inst:IsA("SurfaceGui") or bound[inst] then
			return
		end
		local model = inst:FindFirstAncestorWhichIsA("Model")
		if not WorldLeaderboard.matches(inst.ClassName, inst.Name, if model then model.Name else nil) then
			return
		end
		bound[inst] = WorldLeaderboard.statOf(model)
		inst.AncestryChanged:Connect(function()
			if not inst:IsDescendantOf(root) then
				bound[inst] = nil
			end
		end)
		-- Deferred so a freshly streamed-in board's own Rows frame can arrive first.
		local pending = false
		local function redraw()
			if pending then
				return
			end
			pending = true
			task.defer(function()
				pending = false
				local stat = bound[inst]
				if stat then
					WorldLeaderboard.render(inst, latest[stat] or {})
					showYou(inst, stat)
				end
			end)
		end
		redraw()
		-- A server row that arrives after ours replaces ours (ensureRow), so no rank shows twice.
		-- Also when a server row's Value label lands after the row itself (ensureRow hid it until then).
		inst.DescendantAdded:Connect(function(d)
			local row = if d.Name == "Value" then d.Parent else d
			if
				row
				and row:IsA("Frame")
				and string.match(row.Name, "^Row_%d+$")
				and not row:GetAttribute(WorldLeaderboard.OWN_ROW)
			then
				redraw()
			end
		end)
	end

	for _, inst in root:GetDescendants() do
		consider(inst)
	end
	root.DescendantAdded:Connect(consider)

	return {
		setBoard = function(board: any)
			local def = Leaderboards.get(type(board) == "table" and board.stat)
			if not def then
				return
			end
			local rows = WorldLeaderboard.rows(board, myUserId)
			latest[def.stat] = rows
			for gui, stat in bound do
				if stat == def.stat then
					local ok, err = pcall(WorldLeaderboard.render, gui, rows)
					if not ok then
						warn("[UI] world leaderboard render failed:", err)
					end
					showYou(gui, stat)
				end
			end
		end,
		setMine = function(boards: any, ranks: any)
			if type(boards) ~= "table" then
				return
			end
			local changed = false
			if type(ranks) == "table" then
				for _, def in Leaderboards.BOARDS do
					if myRanks[def.stat] ~= ranks[def.stat] then
						myRanks[def.stat] = ranks[def.stat]
						changed = true
					end
				end
			end
			for _, def in Leaderboards.BOARDS do
				local value = boards[def.stat]
				if type(value) == "number" and mine[def.stat] ~= value then
					mine[def.stat] = value
					changed = true
				end
			end
			if changed then
				for gui, stat in bound do
					showYou(gui, stat)
				end
			end
		end,
		boards = function()
			local out = {}
			for gui in bound do
				table.insert(out, gui)
			end
			return out
		end,
	}
end

return table.freeze(WorldLeaderboard)
