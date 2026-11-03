--!strict
--[[
	ObbyBoardView (Roblox adapter, contract/obby.md §7)

	The course board's store, loop and world board. Holds no rules (server/ObbyBoard).

	  * `store(memoryMode)` picks the backend at boot: the in-memory board (PeriodBoard.memoryStore: this server only)
	    when workspace DataStoreMode = "Memory", in Studio, or when MemoryStoreService can't open a sorted map; else
	    the shared MemoryStore (shared/luau MemoryStoreBoard). Tests and cloud scripts never touch the live board.
	  * `start(world, ctx, now)` puts an ObbyBoard.State on `world.obbyBoard`, builds the board by the portal and
	    runs the loop once a second: follow the course (ObbyBoard.sync), send queued writes (flush), read the board
	    every OBBY.BOARD.REFRESH seconds and at once on a new course (refresh), keep workspace ObbyBoardStatus
	    ("Ok" | "Memory" | "Error", a warn on each bad change) and repaint the board (its countdown every second).
	The board is a Hall of Fame board (Props.leaderboardBoard with its phoenix_top_earners_board skin) re-dressed
	with a course line and a footer: "FASTEST RUNS", "Course #N · new course in m:ss", the top OBBY.BOARD.SIZE,
	the viewer's own "You" line (filled by each client, ui/ObbyHud) and the last course's #1. A SurfaceGui
	(landmark, guides/roblox-world-labels.md): MaxDistance 200; at scale 0.8 the row text is ~0.55 studs (reads
	from ~11 studs on a phone, ~20 on 720p), the title ~1 stud.
]]

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BoardFace = require(ReplicatedStorage.Visuals.BoardFace)
local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)
local MemoryStoreBoard = require(ReplicatedStorage.Lib.ranking.MemoryStoreBoard)
local ObbyBoard = require(script.Parent.ObbyBoard)
local ObbyView = require(script.Parent.ObbyView)
local PeriodBoard = require(ReplicatedStorage.Lib.ranking.PeriodBoard)
local World = require(script.Parent.World)
local WorldLayout = require(ReplicatedStorage.Visuals.WorldLayout)
local WorldProps = require(script.Parent.WorldProps)

local BOARD = Config.OBBY.BOARD

local ObbyBoardView = {}

-- The board face's layout, as fractions of the padded face (BoardFace.CHROME holds the px spacing).
ObbyBoardView.FACE = table.freeze({
	title = "FASTEST RUNS",
	accent = table.freeze({ 20, 116, 108 }), -- goo teal title bar; white title text on it stays >= 4.5:1
	mesh = "phoenix_top_earners_board", -- the Hall of Fame board frame
	maxDistance = 200, -- landmark sign, like the portal sign
	header = 0.2, -- title bar: the title over the course line
	titleY = 0.06,
	titleH = 0.54,
	subY = 0.6,
	subH = 0.34,
	you = 0.085, -- the viewer's own line (ui/ObbyHud)
	footer = 0.07, -- "Last course: ..." / "Board offline"
})

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- The Hall of Fame board builder and its palette (visuals/shared/Props).
local function Props(): any
	return require(ReplicatedStorage.Visuals.Props) :: any
end

-- The board's backend: the store and the mode it runs in.
function ObbyBoardView.store(memoryMode: boolean): (PeriodBoard.Store, ObbyBoard.Mode)
	if memoryMode or RunService:IsStudio() then
		return PeriodBoard.memoryStore(os.clock), "Memory"
	end
	local ok, err = pcall(function()
		return MemoryStoreService:GetSortedMap("ObbyBoardProbe")
	end)
	if not ok then
		warn(`[Server] ObbyBoardStatus = Memory: MemoryStore unavailable ({err}); the board ranks this server only`)
		return PeriodBoard.memoryStore(os.clock), "Memory"
	end
	return MemoryStoreBoard.new(MemoryStoreService), "Ok"
end

local function setStatus(status: string, reason: string?)
	if workspace:GetAttribute(Constants.OBBY_BOARD_STATUS) == status then
		return
	end
	workspace:SetAttribute(Constants.OBBY_BOARD_STATUS, status)
	if status == "Error" then
		warn(`[Server] ObbyBoardStatus = Error: {reason or "?"}`)
	end
end

local function nameOf(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	return if player then player.DisplayName else "?"
end

local function label(parent: Instance, name: string, text: string, color: Color3, outline: number?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = color
	t.Text = text
	if outline then
		local s = Instance.new("UIStroke")
		s.Color = rgb(Props().BOARD_INK)
		s.Thickness = outline
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		s.Parent = t
	end
	t.Parent = parent
	return t
end

-- Re-dresses the Hall of Fame face for the course: a taller title bar with the course line, the row cards, the
-- "You" line and the footer.
local function dress(content: Instance)
	local F = ObbyBoardView.FACE
	local chrome = BoardFace.CHROME
	local palette = Props().BOARD_PALETTE
	local stroke, gutter = chrome.headerStroke, chrome.gutter
	local header = content:FindFirstChild("Header") :: Frame
	header.Position = UDim2.fromOffset(stroke, stroke)
	header.Size = UDim2.new(1, -2 * stroke, F.header, -stroke)
	local title = header:FindFirstChild("Title") :: TextLabel
	title.Position = UDim2.fromScale(0.04, F.titleY)
	title.Size = UDim2.fromScale(0.92, F.titleH)
	local sub = label(header, "Course", "", Color3.new(1, 1, 1), 3)
	sub.Position = UDim2.fromScale(0.04, F.subY)
	sub.Size = UDim2.fromScale(0.92, F.subH)
	local rows = content:FindFirstChild("Rows") :: Frame
	rows.Position = UDim2.new(0, 0, F.header, stroke + gutter)
	rows.Size = UDim2.new(1, 0, 1 - F.header - F.you - F.footer, -(stroke + gutter + 2 * chrome.youGap))
	for k = 1, BOARD.SIZE do
		local row = BoardFace.row(k, BOARD.SIZE, palette)
		row.Visible = false
		row.Parent = rows
	end
	local you = content:FindFirstChild("You") :: Frame
	you.Position = UDim2.new(0, 0, 1 - F.footer - F.you, -chrome.youGap)
	you.Size = UDim2.fromScale(1, F.you)
	local footer = label(content, "Footer", "", rgb(palette.Muted))
	footer.Position = UDim2.fromScale(0, 1 - F.footer)
	footer.Size = UDim2.fromScale(1, F.footer)
end

-- Builds workspace.Obby.Board by the portal (once). Returns it, nil when the props can't be built.
function ObbyBoardView.build(): Model?
	local folder = workspace:FindFirstChild(Constants.OBBY_FOLDER)
	if not folder then
		return nil
	end
	local existing = folder:FindFirstChild(Constants.OBBY_BOARD)
	if existing and existing:IsA("Model") then
		return existing
	end
	local F = ObbyBoardView.FACE
	local model = Props().leaderboardBoard({ model = Constants.OBBY_BOARD, title = F.title, accent = F.accent })
	local gui = model:FindFirstChild("BoardGui", true) :: SurfaceGui
	gui.MaxDistance = F.maxDistance
	dress(gui:FindFirstChild("Content") :: Instance)
	local layout = WorldLayout.OBBY.board
	model:ScaleTo(layout.scale)
	local foot, yaw = WorldLayout.obbyBoard()
	local ground = ObbyView.place().portal[2]
	local a = math.rad(yaw)
	local at = Vector3.new(foot[1], ground, foot[3])
	model:PivotTo(CFrame.lookAt(at, at + Vector3.new(math.sin(a), 0, math.cos(a)))) -- the face (-Z) looks along yaw
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	model:SetAttribute("MeshAsset", F.mesh)
	local size = WorldProps.meshSize(WorldLayout, F.mesh, model)
	if size then
		model:SetAttribute("MeshSize", size)
	end
	model.Parent = folder
	return model
end

-- Writes the board's text; unused row cards hide. The top three keep their medal cards, an empty board shows
-- one plain line.
local function fill(model: Model, view: ObbyBoard.BoardView)
	local P = Props()
	local content = model:FindFirstChild("Content", true)
	if not content then
		return
	end
	local function set(inst: Instance?, text: string)
		if inst and inst:IsA("TextLabel") and inst.Text ~= text then
			inst.Text = text
		end
	end
	local header = content:FindFirstChild("Header")
	set(header and header:FindFirstChild("Course"), view.sub)
	local footer = content:FindFirstChild("Footer")
	set(footer, view.footer or "")
	local rows = content:FindFirstChild("Rows")
	local empty = #view.rows == 1 and view.rows[1].rank == ""
	for k = 1, BOARD.SIZE do
		local frame = rows and rows:FindFirstChild(`Row_{k}`)
		if frame and frame:IsA("Frame") then
			local row = view.rows[k]
			frame.Visible = row ~= nil
			if row then
				set(frame:FindFirstChild("Rank"), row.rank)
				set(frame:FindFirstChild("Name"), row.name)
				set(frame:FindFirstChild("Value"), row.value)
				local medal = if empty then nil else P.MEDAL_FILL[k]
				local fillColor = rgb(medal or P.BOARD_PALETTE.RowAlt)
				if frame:GetAttribute("BaseFill") ~= fillColor then
					frame:SetAttribute("BaseFill", fillColor) -- ui/ObbyHud puts this back after the viewer's own tint
					frame.BackgroundColor3 = fillColor
				end
				local edge = frame:FindFirstChildOfClass("UIStroke")
				if medal and not edge then
					local made = Instance.new("UIStroke")
					made.Thickness = 2
					made.Color = rgb(P.BOARD_PALETTE.Rank[k])
					made.Parent = frame
					edge = made
				end
				if edge then
					edge.Enabled = medal ~= nil
				end
			end
		end
	end
end

-- Runs the board on the store in `ctx.obbyBoardStore` (picked by `store`; `mode` says which it is).
function ObbyBoardView.start(world: World.World, ctx: { obbyBoardStore: any? }, mode: ObbyBoard.Mode, now: () -> number)
	local store = ctx.obbyBoardStore :: PeriodBoard.Store?
	if not store then
		return
	end
	local state = ObbyBoard.new(mode, nameOf)
	world.obbyBoard = state
	setStatus(state.status)
	local model = ObbyBoardView.build()
	task.spawn(function()
		local readAt = -math.huge
		local readSlot: number? = nil
		while true do
			local t = now()
			if world.obby then
				ObbyBoard.sync(state, world.obby)
			end
			if #state.pending > 0 then
				for _, err in ObbyBoard.flush(state, store, t, task.wait) do
					warn(`[Server] obby board write failed: {err}`)
				end
			end
			local course = state.course
			if course and (t - readAt >= BOARD.REFRESH or readSlot ~= course.slot) then
				readAt, readSlot = t, course.slot
				local ok, err = ObbyBoard.refresh(state, store, world, now())
				if not ok then
					warn(`[Server] obby board read failed: {err}`)
				end
			end
			setStatus(state.status, "a board read or write failed")
			if model and model.Parent then
				local view = ObbyBoard.boardView(state, world, now())
				local filled, err = pcall(function()
					fill(model :: Model, view)
				end)
				if not filled then
					warn(`[Server] obby board fill failed: {err}`)
				end
			end
			task.wait(1)
		end
	end)
end

return ObbyBoardView
