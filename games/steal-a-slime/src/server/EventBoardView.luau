--!strict
--[[
	EventBoardView (Roblox adapter)
	The Upcoming Events wall at the fountain (WorldLayout.EVENT_BOARD): a wooden board on two posts facing the
	fountain, with a rainbow title bar and one coloured card per EventBoard row on both faces (icon, title, detail,
	countdown; the soonest at the top). `start` builds it and refreshes once a second: it rebuilds the cards only
	when their set or order changes, else it just rewrites the text. Server-side, so it replicates to everyone.

	EventBoardView.input(world, now, unix?) -> EventBoard.Input   -- reads the world (no Instances)
	EventBoardView.start(world, now: () -> number)                 -- builds the wall and runs the loop
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local EventBoard = if Shared then require(Shared.EventBoard) else require("../shared/EventBoard")
local SlimeRoster = if Shared then require(Shared.SlimeRoster) else require("../shared/SlimeRoster")
local WeeklyEvents = if Shared then require(Shared.WeeklyEvents) else require("../shared/WeeklyEvents")
local WorldLayout = if Shared
	then require(Shared.Parent.Visuals.WorldLayout)
	else require("../visuals/shared/WorldLayout")
local Spawner = if script then require(script.Parent.Spawner) else require("./Spawner")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World

local EventBoardView = {}

EventBoardView.NAME = "EventBoard"
EventBoardView.PIXELS_PER_STUD = 40
EventBoardView.POST = 0.9 -- post width (studs)
EventBoardView.RIM = 0.5 -- wooden frame around the face (studs)
EventBoardView.MIN_SLOTS = 5 -- cards share the board height as if at least this many were shown

-- Card icons: an uploaded image (ui/ItemIcons ids) or a glyph. Keys are EventBoard row icons.
EventBoardView.ICONS = table.freeze({
	boss = "👑", -- same as the boss HUD (BossMeterLogic.ICON)
	rain = "rbxassetid://85475866363499", -- Event_rain
	legendary = "rbxassetid://92898240575380", -- Badge_FirstLegendary
	mythic = "🔮",
	event = "rbxassetid://130491704533609", -- Boost_Weekend
	weatherClear = "☀️",
	weatherRain = "🌧️",
	weatherSnow = "❄️",
	weatherStarfall = "🌠",
} :: { [string]: string })

-- Colours (RGB; Color3 is built at use, so the pure tests can require this module).
local WOOD = { 122, 82, 54 }
local WOOD_DARK = { 84, 56, 40 }
local FACE = { 28, 30, 48 }
local WHITE = { 255, 255, 255 }
local INK = { 24, 20, 36 }
local CARD_TEXT = { 235, 235, 245 }

-- What the sign shows now, from the world state.
function EventBoardView.input(world: World, now: number, unix: number?): EventBoard.Input
	local fight = if world.boss then world.boss.fight else nil
	local boss = if fight then SlimeRoster.get(fight.species) else nil
	local warning = fight ~= nil and fight.phase == "warning"
	local raining, rainEndsAt, rainAt = Spawner.rain(world, now)
	local weather = world.weather
	local event, eventEndsAt = nil, nil
	if world.adminEvent then
		event, eventEndsAt = world.adminEvent.def.label, world.adminEvent.endsAt
	elseif unix and WeeklyEvents.enabled() then
		local running = WeeklyEvents.current(unix)[1]
		if running then
			event = running.label
		end
	end
	return {
		bossHere = if boss and not warning then boss.name else nil,
		bossAt = if warning then (fight :: any).endsAt elseif boss then nil else world.nextBossAt,
		rainEndsAt = if raining then rainEndsAt else nil,
		rainAt = if raining then nil else rainAt,
		weather = if weather then weather.id else nil,
		weatherChangeAt = if weather then weather.changeAt else nil,
		legendaryIn = Spawner.guaranteeIn(world, 5, now),
		mythicIn = Spawner.guaranteeIn(world, 6, now),
		event = event,
		eventEndsAt = eventEndsAt,
	}
end

local function rgb(c: { number }, scale: number?): Color3
	local s = scale or 1
	local function channel(v: number): number
		return math.clamp(math.floor(v * s + 0.5), 0, 255)
	end
	return Color3.fromRGB(channel(c[1]), channel(c[2]), channel(c[3]))
end

local function corner(parent: Instance, scale: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
end

local function text(parent: Instance, name: string, value: string, color: Color3, outline: number?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = color
	t.Text = value
	if outline then
		local s = Instance.new("UIStroke")
		s.Color = rgb(INK)
		s.Thickness = outline
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		s.Parent = t
	end
	t.Parent = parent
	return t
end

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanTouch = false
	p.Material = Enum.Material.WoodPlanks
	p.Color = color
	p.Size = size
	p.CFrame = cframe
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- One card for `row` at list position `k` of `count` slots (cleared and rebuilt when the layout changes).
local function card(list: Frame, row: EventBoard.Row, k: number, count: number)
	local f = Instance.new("Frame")
	f.Name = `Card_{k}`
	f.LayoutOrder = k
	f.Size = UDim2.fromScale(1, 1 / count - 0.02)
	f.BackgroundColor3 = rgb(row.accent, if row.live then 0.55 else 0.32)
	f.BorderSizePixel = 0
	corner(f, 0.25)
	stroke(f, rgb(row.accent), if k == 1 then 5 else 3)
	-- icon tile
	local tile = Instance.new("Frame")
	tile.Name = "IconTile"
	tile.Position = UDim2.fromScale(0.012, 0.08)
	tile.Size = UDim2.fromScale(0.1, 0.84)
	tile.BackgroundColor3 = rgb(row.accent)
	tile.BorderSizePixel = 0
	corner(tile, 0.3)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = tile
	tile.Parent = f
	local icon = EventBoardView.ICONS[row.icon] or "✨"
	if string.sub(icon, 1, 13) == "rbxassetid://" then
		local img = Instance.new("ImageLabel")
		img.Name = "Icon"
		img.BackgroundTransparency = 1
		img.Image = icon
		img.Position = UDim2.fromScale(0.06, 0.06)
		img.Size = UDim2.fromScale(0.88, 0.88)
		img.Parent = tile
	else
		local glyph = text(tile, "Icon", icon, rgb(WHITE))
		glyph.Position = UDim2.fromScale(0.12, 0.12)
		glyph.Size = UDim2.fromScale(0.76, 0.76)
	end
	local title = text(f, "Title", row.title, rgb(row.accent, 1.25), 2)
	title.Position = UDim2.fromScale(0.15, 0.06)
	title.Size = UDim2.fromScale(0.52, 0.52)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local detail = text(f, "Detail", row.detail, rgb(CARD_TEXT))
	detail.Position = UDim2.fromScale(0.15, 0.58)
	detail.Size = UDim2.fromScale(0.52, 0.34)
	detail.TextXAlignment = Enum.TextXAlignment.Left
	-- countdown pill
	local pill = Instance.new("Frame")
	pill.Name = "TimePill"
	pill.Position = UDim2.fromScale(0.69, 0.14)
	pill.Size = UDim2.fromScale(0.295, 0.72)
	pill.BackgroundColor3 = if row.live then rgb(row.accent) else rgb(INK)
	pill.BorderSizePixel = 0
	pill.Visible = row.time ~= ""
	corner(pill, 0.5)
	stroke(pill, rgb(row.accent), 2)
	pill.Parent = f
	local time = text(pill, "Time", row.time, rgb(WHITE), if row.live then 2 else nil)
	time.Position = UDim2.fromScale(0.06, 0.1)
	time.Size = UDim2.fromScale(0.88, 0.8)
	f.Parent = list
end

-- Writes `rows` into one face's list: rebuilds when `rebuild`, else only updates text.
local function fill(list: Frame, rows: { EventBoard.Row }, rebuild: boolean)
	if rebuild then
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for k, row in rows do
			card(list, row, k, math.max(#rows, EventBoardView.MIN_SLOTS))
		end
		return
	end
	for k, row in rows do
		local f = list:FindFirstChild(`Card_{k}`)
		if f then
			for field, value in { Title = row.title, Detail = row.detail } :: { [string]: string } do
				local label = f:FindFirstChild(field)
				if label and label:IsA("TextLabel") and label.Text ~= value then
					label.Text = value
				end
			end
			local pill = f:FindFirstChild("TimePill")
			local time = pill and pill:FindFirstChild("Time")
			if pill and pill:IsA("Frame") then
				pill.Visible = row.time ~= ""
			end
			if time and time:IsA("TextLabel") and time.Text ~= row.time then
				time.Text = row.time
			end
		end
	end
end

-- One face's SurfaceGui: the rainbow title bar and the card list. Returns the list.
local function face(board: Part, side: Enum.NormalId): Frame
	local gui = Instance.new("SurfaceGui")
	gui.Name = `BoardGui{side.Name}`
	gui.Face = side
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = EventBoardView.PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.Parent = board
	local bg = Instance.new("Frame")
	bg.Name = "Face"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = rgb(FACE)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.03, 0)
	pad.PaddingBottom = UDim.new(0.03, 0)
	pad.PaddingLeft = UDim.new(0.025, 0)
	pad.PaddingRight = UDim.new(0.025, 0)
	pad.Parent = bg
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.fromScale(1, 0.15)
	header.BackgroundColor3 = rgb(WHITE)
	header.BorderSizePixel = 0
	corner(header, 0.3)
	stroke(header, rgb(INK), 4)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 92, 120)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 176, 60)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 220, 120)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(70, 170, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 110, 255)),
	})
	gradient.Parent = header
	header.Parent = bg
	local title = text(header, "Title", string.upper(EventBoard.TITLE), rgb(WHITE), 4)
	title.Position = UDim2.fromScale(0.04, 0.1)
	title.Size = UDim2.fromScale(0.92, 0.8)
	local list = Instance.new("Frame")
	list.Name = "Cards"
	list.Position = UDim2.fromScale(0, 0.19)
	list.Size = UDim2.fromScale(1, 0.81)
	list.BackgroundTransparency = 1
	list.Parent = bg
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.02, 0)
	layout.Parent = list
	return list
end

-- The wall Model: posts, a wooden frame, a top beam and the board with both faces. Returns the card lists.
local function build(parent: Instance): { Frame }
	local spot = WorldLayout.EVENT_BOARD
	local x, z = WorldLayout.eventBoardSpot()
	local w, h, t = spot.width, spot.height, spot.thickness
	local centreY = spot.lift + h / 2
	local root = CFrame.lookAt(Vector3.new(x, centreY, z), Vector3.new(0, centreY, 0)) -- Front looks at the fountain
	local model = Instance.new("Model")
	model.Name = EventBoardView.NAME
	local rim, post = EventBoardView.RIM, EventBoardView.POST
	local frame = part(model, "Frame", Vector3.new(w + rim * 2, h + rim * 2, t), root, rgb(WOOD_DARK))
	frame.CanCollide = true
	local board = part(model, "Board", Vector3.new(w, h, t + 0.1), root, rgb(FACE))
	board.Material = Enum.Material.SmoothPlastic
	board.CanCollide = false
	local beam = part(
		model,
		"Beam",
		Vector3.new(w + rim * 2 + 1.2, 0.8, t + 0.6),
		root * CFrame.new(0, h / 2 + rim + 0.4, 0),
		rgb(WOOD)
	)
	beam.CanCollide = false
	local postHeight = centreY + h / 2 + rim
	for side, dx in { L = -(w / 2 + rim + post / 2), R = w / 2 + rim + post / 2 } do
		local p = part(
			model,
			`Post{side}`,
			Vector3.new(post, postHeight, post),
			root * CFrame.new(dx, postHeight / 2 - centreY, 0),
			rgb(WOOD)
		)
		p.CanCollide = true
	end
	model.PrimaryPart = board
	local lists = { face(board, Enum.NormalId.Front), face(board, Enum.NormalId.Back) }
	model.Parent = parent
	return lists
end

function EventBoardView.start(world: World, now: () -> number)
	local lists = build(workspace)
	task.spawn(function()
		local key = nil
		while true do
			local rows = EventBoard.rows(EventBoardView.input(world, now(), os.time()), now())
			local nextKey = EventBoard.layoutKey(rows)
			for _, list in lists do
				fill(list, rows, nextKey ~= key)
			end
			key = nextKey
			task.wait(1)
		end
	end)
end

return EventBoardView
