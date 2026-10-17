--!strict
--[[
	RitualView (Roblox adapter, FEATURES.CoopRitual, CONTRACT.md §13)

	Builds the plaza ritual circle from plain parts (a flat disc, one glowing spot disc per required
	player (Config.RITUAL.SPOTS = MIN_PLAYERS), a hovering orb with a BillboardGui) under workspace.Map.RitualCircle, and keeps it in sync
	with the Ritual state: spots glow green while someone stands on them, the sign reads
	"n/2 players", then "Hold still! 5s", then "Ritual resting 3:20". Also reads the players'
	HumanoidRootPart positions for RitualService.step. Everything is decor: anchored, no collision,
	no queries. Holds no gameplay rules.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Ritual = require(ReplicatedStorage.Shared.Ritual)

local RitualView = {}

RitualView.MODEL_NAME = "RitualCircle"

local IDLE = Color3.fromRGB(190, 160, 255)
local TAKEN = Color3.fromRGB(120, 255, 160)
local CHARGE = Color3.fromRGB(255, 226, 120)
local REST = Color3.fromRGB(150, 150, 170)

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

local function textLabel(name: string, parent: Instance, y: number, h: number, size: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0, y)
	label.Size = UDim2.fromScale(1, h)
	label.Font = Enum.Font.FredokaOne
	label.TextSize = size
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = Color3.fromRGB(60, 30, 110)
	label.TextStrokeTransparency = 0.2
	label.Parent = parent
	return label
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
	gui.Size = UDim2.fromOffset(220, 74)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	gui.MaxDistance = 140
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Parent = core
	title = textLabel("Title", gui, 0, 0.5, 26)
	line = textLabel("Line", gui, 0.5, 0.5, 22)

	model:SetAttribute("Phase", "Idle")
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
	model:SetAttribute("Phase", state.phase)
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
