--!strict
--[[
	EventBoardView (Roblox adapter)
	Fills the Upcoming Events board (WorldLayout.EVENT_BOARD: a Hall of Fame board that WorldProps places on the
	grass by the ring path, with the leaderboard frame mesh) with a rainbow title bar and one coloured card per
	EventBoard row (icon, title, detail, countdown; the soonest at the top). `start` waits for the board, then
	refreshes once a second: it rebuilds the cards only when their set or order changes, else it just rewrites the
	text. Server-side, so it replicates to everyone.

	EventBoardView.input(world, now, unix?) -> EventBoard.Input   -- reads the world (no Instances)
	EventBoardView.start(world, now: () -> number)                 -- fills the board and runs the loop
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local EventBoard = if Shared then require(Shared.EventBoard) else require("../shared/EventBoard")
local SlimeRoster = if Shared then require(Shared.SlimeRoster) else require("../shared/SlimeRoster")
local WeeklyEvents = if Shared then require(Shared.WeeklyEvents) else require("../shared/WeeklyEvents")
local WorldLayout = if Shared
	then require(Shared.Parent.Visuals.WorldLayout)
	else require("../visuals/shared/WorldLayout")
local BoardFace = if Shared then require(Shared.Parent.Visuals.BoardFace) else require("../visuals/shared/BoardFace")
local Spawner = if script then require(script.Parent.Spawner) else require("./Spawner")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World

local EventBoardView = {}

EventBoardView.WAIT_SECONDS = 30 -- how long `start` waits for WorldProps to place the board
EventBoardView.MIN_SLOTS = 5 -- cards share the board height as if at least this many were shown
EventBoardView.PILL_WIDTH = 0.29 -- the countdown pill, of the card's padded width
EventBoardView.LIST_HEIGHT = "ListHeight" -- attribute on the card list: its height in canvas px

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
local FACE = { 255, 250, 240 } -- the light face, like the Hall of Fame boards (Props.BOARD_PALETTE.Face)
local WHITE = { 255, 255, 255 }
local INK = { 24, 20, 36 }
local CARD_TEXT = { 62, 40, 26 } -- dark ink on the pale cards (Props.BOARD_PALETTE.Text)

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

-- `c` mixed toward white by `amount` (0 = c, 1 = white): the pale card fills.
local function pale(c: { number }, amount: number): Color3
	local function channel(v: number): number
		return math.clamp(math.floor(v + (255 - v) * amount + 0.5), 0, 255)
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

-- One card for `row` at list position `k` of `count` slots (cleared and rebuilt when the layout changes). `listHeight`
-- is the card list's height in canvas px: the icon tile is square, so the text starts one tile width in.
local function card(list: Frame, row: EventBoard.Row, k: number, count: number, listHeight: number)
	local chrome = BoardFace.CHROME
	local f = Instance.new("Frame")
	f.Name = `Card_{k}`
	f.LayoutOrder = k
	f.Size = UDim2.new(1, 0, 1 / count, -math.ceil(chrome.gutter * (count - 1) / count))
	f.BackgroundColor3 = pale(row.accent, if row.live then 0.45 else 0.72)
	f.BorderSizePixel = 0
	corner(f, 0.25)
	stroke(f, rgb(row.accent), if k == 1 then 5 else 3)
	BoardFace.pad(f, chrome.inset, chrome.insetY)
	local tileSize = math.floor((listHeight - chrome.gutter * (count - 1)) / count - 2 * chrome.insetY)
	-- icon tile
	local tile = Instance.new("Frame")
	tile.Name = "IconTile"
	tile.Size = UDim2.fromOffset(tileSize, tileSize)
	tile.BackgroundColor3 = rgb(row.accent)
	tile.BorderSizePixel = 0
	corner(tile, 0.3)
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
	local textX = tileSize + chrome.inset
	local textW = UDim2.new(1 - EventBoardView.PILL_WIDTH, -(textX + chrome.inset), 0, 0)
	local title = text(f, "Title", row.title, rgb(row.accent, 0.45))
	title.Position = UDim2.fromOffset(textX, 0)
	title.Size = textW + UDim2.fromScale(0, 0.6)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local detail = text(f, "Detail", row.detail, rgb(CARD_TEXT))
	detail.Position = UDim2.new(0, textX, 0.62, 0)
	detail.Size = textW + UDim2.fromScale(0, 0.38)
	detail.TextXAlignment = Enum.TextXAlignment.Left
	-- countdown pill, on the card's right edge
	local pill = Instance.new("Frame")
	pill.Name = "TimePill"
	pill.AnchorPoint = Vector2.new(1, 0)
	pill.Position = UDim2.fromScale(1, 0)
	pill.Size = UDim2.fromScale(EventBoardView.PILL_WIDTH, 1)
	pill.BackgroundColor3 = if row.live then rgb(row.accent) else rgb(INK)
	pill.BorderSizePixel = 0
	pill.Visible = row.time ~= ""
	corner(pill, 0.5)
	stroke(pill, rgb(row.accent), 2)
	BoardFace.pad(pill, chrome.pillInset, 0)
	pill.Parent = f
	local time = text(pill, "Time", row.time, rgb(WHITE), if row.live then 2 else nil)
	time.Position = UDim2.fromScale(0, 0.15)
	time.Size = UDim2.fromScale(1, 0.7)
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
		local listHeight = list:GetAttribute(EventBoardView.LIST_HEIGHT) :: number
		for k, row in rows do
			card(list, row, k, math.max(#rows, EventBoardView.MIN_SLOTS), listHeight)
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

-- The canvas height (px) of the SurfaceGui that `content` sits on: its part's face height x PixelsPerStud.
local function canvasHeight(content: Instance): number
	local gui = content:FindFirstAncestorWhichIsA("SurfaceGui") :: SurfaceGui
	local part = (gui.Adornee or gui.Parent) :: BasePart
	return part.Size.Y * gui.PixelsPerStud
end

-- Replaces the leaderboard rows on the board's face (Content, already padded by Props.leaderboardBoard) with the
-- title bar and the card list. Returns the list.
local function dress(content: Instance): Frame
	local chrome = BoardFace.CHROME
	for _, child in content:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local bg = Instance.new("Frame")
	bg.Name = "Face"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = rgb(FACE)
	bg.BackgroundTransparency = 1 -- Content is the face; this only holds the layout
	bg.BorderSizePixel = 0
	bg.Parent = content
	local header = Instance.new("Frame")
	header.Name = "Header"
	BoardFace.placeHeader(header)
	header.BackgroundColor3 = rgb(WHITE)
	header.BorderSizePixel = 0
	corner(header, 0.3)
	stroke(header, rgb(INK), chrome.headerStroke)
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
	-- The cards, under the title bar's outline and a gutter, down to the face's padding.
	local top = chrome.headerStroke + chrome.gutter
	local list = Instance.new("Frame")
	list.Name = "Cards"
	list.Position = UDim2.new(0, 0, chrome.header, top)
	list.Size = UDim2.new(1, 0, 1 - chrome.header, -top)
	list.BackgroundTransparency = 1
	local face = canvasHeight(content) - 2 * chrome.pad
	list:SetAttribute(EventBoardView.LIST_HEIGHT, face * (1 - chrome.header) - top)
	list.Parent = bg
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, chrome.gutter)
	layout.Parent = list
	return list
end

-- The board's face (the leaderboard SurfaceGui's Content), waiting up to WAIT_SECONDS for WorldProps; nil without it.
local function boardContent(): Instance?
	local name = WorldLayout.EVENT_BOARD.model
	for _ = 1, EventBoardView.WAIT_SECONDS * 2 do
		local model = workspace:FindFirstChild(name, true)
		local content = model and model:FindFirstChild("Content", true)
		if content then
			return content
		end
		task.wait(0.5)
	end
	warn(`[Server] EventBoardView: no {name} board placed`)
	return nil
end

function EventBoardView.start(world: World, now: () -> number)
	task.spawn(function()
		local content = boardContent()
		if not content then
			return
		end
		local list = dress(content)
		local key = nil
		while true do
			local rows = EventBoard.rows(EventBoardView.input(world, now(), os.time()), now())
			local nextKey = EventBoard.layoutKey(rows)
			fill(list, rows, nextKey ~= key)
			key = nextKey
			task.wait(1)
		end
	end)
end

return EventBoardView
