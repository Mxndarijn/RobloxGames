--!strict
--[[
	RitualView (Roblox adapter, FEATURES.CoopRitual, CONTRACT.md §13)

	Builds the plaza ritual circle from plain parts (a flat disc, one glowing spot disc per required
	player (Config.RITUAL.SPOTS = MIN_PLAYERS), a hovering orb with the Goo ritual label) under workspace.Map.RitualCircle, and keeps it in sync
	with the Ritual state: spots glow green while someone stands on them, the sign reads
	"n/2 players", then "Hold still! 5s", then "Ritual resting 3:20". The client effects
	(visuals/client/RitualFx) read the attributes it sets: Phase, ChargeEndsAt and ReadyAt on the model,
	Taken on each spot (the RITUAL_* names in Constants). Also reads the players'
	HumanoidRootPart positions for RitualService.step. Everything is decor: anchored, no collision,
	no queries. Holds no gameplay rules.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)
local GooPalette = require(ReplicatedStorage.Shared.GooPalette)
local Ritual = require(ReplicatedStorage.Shared.Ritual)
local RitualLook = require(ReplicatedStorage.Visuals.RitualLook)

local RitualView = {}

RitualView.MODEL_NAME = "RitualCircle"

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local IDLE = rgb(RitualLook.COLORS.idle)
local TAKEN = rgb(RitualLook.COLORS.taken)
local CHARGE = rgb(RitualLook.COLORS.charge)
local REST = rgb(RitualLook.COLORS.rest)

local spotParts: { BasePart } = {}
local built: Model? = nil
local orb: BasePart? = nil
local title: TextLabel? = nil
local line: TextLabel? = nil

local function decor(part: BasePart, color: Color3, material: Enum.Material)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

-- A flat disc whose face points up (a Cylinder's axis is its X; roll it 90 degrees).
local function disc(
	name: string,
	parent: Instance,
	x: number,
	y: number,
	z: number,
	radius: number,
	height: number
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(height, radius * 2, radius * 2)
	part.CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(90))
	part.Parent = parent
	return part
end

-- The orb's label (canvas GooWorldSigns "Ritual label"): the phase in outlined white Fredoka, the count or the
-- timer on a flat Ink pill with a mint edge under it. Pixel-sized so it reads from across the plaza.
RitualView.LABEL = table.freeze({ w = 300, h = 96, title = 34, titleSize = 30, line = 32, lineSize = 20, gap = 8 })

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number, contextual: boolean)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency
	s.ApplyStrokeMode = if contextual then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
end

local function buildLabel(gui: BillboardGui): (TextLabel, TextLabel)
	local L = RitualView.LABEL
	local head = Instance.new("TextLabel")
	head.Name = "Title"
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, L.title)
	head.Font = Enum.Font.FredokaOne
	head.TextSize = L.titleSize
	head.TextColor3 = rgb(GooPalette.White)
	stroke(head, rgb(GooPalette.Ink), 2.5, 0, true)
	head.Parent = gui
	local pill = Instance.new("TextLabel")
	pill.Name = "Line"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, L.title + L.gap)
	pill.Size = UDim2.fromOffset(0, L.line)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.BackgroundColor3 = rgb(GooPalette.Ink)
	pill.Font = Enum.Font.FredokaOne
	pill.TextSize = L.lineSize
	pill.TextColor3 = rgb(GooPalette.Mint)
	corner(pill, UDim.new(1, 0))
	stroke(pill, rgb(GooPalette.Mint), 2, 0.55, false)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = pill
	pill.Parent = gui
	return head, pill
end

-- Creates the circle once (a copy already in workspace is reused). Returns the model, or nil when off.
function RitualView.setup(): Model?
	if not Config.FEATURES.CoopRitual then
		return nil
	end
	local parent = workspace:FindFirstChild(Constants.MAP_FOLDER) or workspace
	local existing = workspace:FindFirstChild(RitualView.MODEL_NAME, true)
	if existing then
		existing:Destroy()
	end
	local r = Config.RITUAL
	local cx, cz = Ritual.centre()
	local model = Instance.new("Model")
	model.Name = RitualView.MODEL_NAME

	local base = disc("Base", model, cx, 0.12, cz, r.CIRCLE_RADIUS, 0.24)
	decor(base, Color3.fromRGB(86, 62, 150), Enum.Material.SmoothPlastic)
	local ring = disc("Ring", model, cx, 0.2, cz, r.CIRCLE_RADIUS - 0.7, 0.2)
	decor(ring, Color3.fromRGB(120, 96, 200), Enum.Material.SmoothPlastic)
	local inner = disc("Inner", model, cx, 0.3, cz, r.CIRCLE_RADIUS - 1.6, 0.2)
	decor(inner, Color3.fromRGB(86, 62, 150), Enum.Material.SmoothPlastic)

	table.clear(spotParts)
	for i, spot in Ritual.spots() do
		local part = disc(`Spot_{i}`, model, spot[1], 0.42, spot[2], r.STAND_RADIUS * 0.8, 0.2)
		decor(part, IDLE, Enum.Material.Neon)
		table.insert(spotParts, part)
	end

	local core = Instance.new("Part")
	core.Name = "Orb"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(2.6, 2.6, 2.6)
	core.Position = Vector3.new(cx, 4.2, cz)
	decor(core, IDLE, Enum.Material.Neon)
	core.Parent = model
	orb = core

	local gui = Instance.new("BillboardGui")
	gui.Name = "RitualSign"
	gui.Adornee = core
	gui.Size = UDim2.fromOffset(RitualView.LABEL.w, RitualView.LABEL.h)
	gui.SizeOffset = Vector2.new(0, 0.5) -- the label's bottom edge sits over the orb
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
	gui.MaxDistance = 140
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Parent = core
	title, line = buildLabel(gui)

	-- One small board at the circle edge, facing the plaza, that explains the rule (text from Config).
	local sx, sz = Ritual.signSpot()
	local board = Instance.new("Part")
	board.Name = "RuleSign"
	board.Size = Vector3.new(6, 1.8, 0.3)
	-- lookAt points the front (-Z) face at the fountain axis
	board.CFrame = CFrame.lookAt(Vector3.new(sx, 1, sz), Vector3.new(0, 1, 0))
	decor(board, rgb(GooPalette.Ink), Enum.Material.SmoothPlastic)
	board.Parent = model
	local face = Instance.new("SurfaceGui")
	face.Name = "RuleText"
	face.Face = Enum.NormalId.Front
	face.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	face.PixelsPerStud = 50
	face.LightInfluence = 0
	face.Parent = board
	-- A glass card with the rule in Nunito, like the canvas's rule card under the ritual label.
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = rgb(GooPalette.Bg)
	card.BorderSizePixel = 0
	corner(card, UDim.new(0.3, 0))
	stroke(card, rgb(GooPalette.Ink), 4, 0, false)
	card.Parent = face
	local rule = Instance.new("TextLabel")
	rule.Name = "Rule"
	rule.BackgroundTransparency = 1
	rule.Position = UDim2.fromScale(0.06, 0.12)
	rule.Size = UDim2.fromScale(0.88, 0.76)
	rule.FontFace = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Bold)
	rule.TextScaled = true
	rule.TextWrapped = true
	rule.TextColor3 = rgb(GooPalette.Text)
	rule.Text = Ritual.signText()
	rule.Parent = card

	model:SetAttribute(Constants.RITUAL_PHASE_ATTRIBUTE, "Idle")
	model.Parent = parent
	built = model
	return model
end

-- Pushes the Ritual state onto the parts: spot glow, orb colour and the sign text.
function RitualView.update(state: Ritual.State, now: number)
	local model = built
	if not model then
		return
	end
	local resting = state.phase == "Cooldown"
	local tint = if resting then REST elseif state.phase == "Charging" then CHARGE else IDLE
	for i, part in spotParts do
		local taken = state.spotUsers[i] ~= nil
		part.Color = if resting then REST elseif taken then TAKEN else IDLE
		part.Transparency = if resting then 0.55 elseif taken then 0 else 0.25
		part:SetAttribute(Constants.RITUAL_TAKEN_ATTRIBUTE, taken and not resting)
	end
	if orb then
		orb.Color = tint
	end
	local top, bottom = Ritual.label(state, now)
	if title then
		title.Text = top
	end
	if line then
		line.Text = bottom
	end
	model:SetAttribute(Constants.RITUAL_PHASE_ATTRIBUTE, state.phase)
	model:SetAttribute(
		Constants.RITUAL_CHARGE_ENDS_ATTRIBUTE,
		if state.phase == "Charging" then state.chargeEndsAt else nil
	)
	model:SetAttribute(Constants.RITUAL_READY_AT_ATTRIBUTE, if resting then state.readyAt else nil)
	model:SetAttribute("Players", state.count)
end

-- Where each player's root part is (x, y, z); players without a character are left out.
function RitualView.positions(): { Ritual.Candidate }
	local out: { Ritual.Candidate } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local p = root.Position
			table.insert(out, { userId = player.UserId, x = p.X, y = p.Y, z = p.Z })
		end
	end
	return out
end

return RitualView
