--!strict
--[[
	WorldLeaderboard

	Fills in-world leaderboard SurfaceGuis from the `Leaderboard` RemoteEvent
	(same board as Panels/Leaderboard). Client-local: each player renders the
	board themselves and their own row is highlighted.

	A SurfaceGui under workspace is a board when it's named "Leaderboard", or
	sits inside a Model named "LeaderboardBoard" (Archer's
	Props.leaderboardBoard: Board > SurfaceGui "BoardGui" > Content > Rows)
	or "Leaderboard". Rows go into its descendant Frame "Rows" if there is
	one, else into a "Rows" frame created to fill the gui. Boards streamed
	in later bind on DescendantAdded. Row frames are "Row_<k>" with Rank /
	Name / Value labels, like Props.fillLeaderboard.

	The pure helpers (`matches`, `rows`) run under Lune
	(tests/ui/WorldLeaderboard.spec.luau); `start` touches Roblox only when called.
]]

local Format = if script then require(script.Parent.Format) else require("./Format")

export type Row = { rank: number, name: string, value: string, isMe: boolean }

local WorldLeaderboard = {}

WorldLeaderboard.MAX_ROWS = 10
WorldLeaderboard.GUI_NAMES = table.freeze({ "Leaderboard" })
WorldLeaderboard.MODEL_NAMES = table.freeze({ "LeaderboardBoard", "Leaderboard" })
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
			value = Format.formatCash(if type(entry.value) == "number" then entry.value else 0),
			isMe = myUserId ~= nil and entry.userId == myUserId,
		})
	end
	return out
end

-- Roblox side ---------------------------------------------------------------

-- Text colours (RGB) on the board skin's cream face; the same values as Props.BOARD_PALETTE (a spec keeps them equal).
WorldLeaderboard.PALETTE = table.freeze({
	RowAlt = table.freeze({ 238, 218, 182 }),
	Me = table.freeze({ 179, 231, 191 }),
	Text = table.freeze({ 60, 38, 22 }),
	Muted = table.freeze({ 110, 84, 62 }),
	Value = table.freeze({ 22, 104, 54 }),
	Rank = table.freeze({ table.freeze({ 128, 84, 6 }), table.freeze({ 84, 88, 98 }), table.freeze({ 150, 72, 30 }) }),
})

-- Built on first use: Color3 doesn't exist under Lune.
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

local function textLabel(parent: Instance, name: string, x: number, width: number, align: Enum.TextXAlignment)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(x, 0)
	label.Size = UDim2.fromScale(width, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = colors().Text
	label.TextXAlignment = align
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = parent
	return label
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
	list.Padding = UDim.new(0.01, 0)
	list.Parent = frame
	frame.Parent = gui
	return frame
end

local function ensureRow(container: Instance, k: number): Frame
	local name = `Row_{k}`
	local row = container:FindFirstChild(name)
	if row and row:IsA("Frame") and row:FindFirstChild("Value") then
		return row
	end
	if row then
		row:Destroy()
	end
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.LayoutOrder = k
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = colors().RowAlt
	frame.Size = UDim2.fromScale(1, 1 / WorldLeaderboard.MAX_ROWS - 0.01)
	textLabel(frame, "Rank", 0.02, 0.13, Enum.TextXAlignment.Left)
	textLabel(frame, "Name", 0.17, 0.5, Enum.TextXAlignment.Left)
	textLabel(frame, "Value", 0.68, 0.3, Enum.TextXAlignment.Right).TextColor3 = colors().Value
	frame.Parent = container
	return frame
end

function WorldLeaderboard.render(gui: SurfaceGui, rows: { Row })
	local container = rowsContainer(gui)
	local shown = math.max(#rows, 1) -- row 1 doubles as the "no entries" line
	for k = 1, WorldLeaderboard.MAX_ROWS do
		local existing = container:FindFirstChild(`Row_{k}`)
		if k > shown then
			if existing and existing:IsA("GuiObject") then
				existing.Visible = false
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
			rank.Text, value.Text = "", ""
			name.Text = "No entries yet"
			name.TextColor3 = colors().Muted
			continue
		end
		-- Plain rows sit straight on the board face; only the stripes and my own row get a fill.
		frame.BackgroundColor3 = if row.isMe then colors().Me else colors().RowAlt
		frame.BackgroundTransparency = if row.isMe or k % 2 == 0 then 0 else 1
		rank.Text = `#{row.rank}`
		rank.TextColor3 = colors().Rank[row.rank] or colors().Text
		name.Text = row.name
		name.TextColor3 = colors().Text
		value.Text = row.value
	end
end

export type Handle = { setBoard: (board: any) -> (), boards: () -> { SurfaceGui } }

-- Binds every board under `root` (now and later) and returns a setter for
-- new Leaderboard payloads.
function WorldLeaderboard.start(root: Instance, myUserId: number): Handle
	local bound: { [SurfaceGui]: boolean } = {}
	local latest: { Row } = {}

	local function consider(inst: Instance)
		if not inst:IsA("SurfaceGui") or bound[inst] then
			return
		end
		local model = inst:FindFirstAncestorWhichIsA("Model")
		if not WorldLeaderboard.matches(inst.ClassName, inst.Name, if model then model.Name else nil) then
			return
		end
		bound[inst] = true
		inst.AncestryChanged:Connect(function()
			if not inst:IsDescendantOf(root) then
				bound[inst] = nil
			end
		end)
		-- Deferred so a freshly streamed-in board's own Rows frame can arrive first.
		task.defer(function()
			if bound[inst] then
				WorldLeaderboard.render(inst, latest)
			end
		end)
	end

	for _, inst in root:GetDescendants() do
		consider(inst)
	end
	root.DescendantAdded:Connect(consider)

	return {
		setBoard = function(board: any)
			latest = WorldLeaderboard.rows(board, myUserId)
			for gui in bound do
				local ok, err = pcall(WorldLeaderboard.render, gui, latest)
				if not ok then
					warn("[UI] world leaderboard render failed:", err)
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
