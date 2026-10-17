--!strict
--[[
	SnowGround v2 (VisualsClient module, FEATURES.SnowGround): "snow on the surfaces, no sheet".

	Client-only ground snow made by TINTING surfaces that already exist, so it adds zero parts and zero mesh
	slots (SnowCover.PART_COUNT / MESH_SLOTS = 0) and is flush by construction: there is no second layer to
	z-fight with the paths or to clip into props. (v1 laid one translucent Snow Part over the whole ground; it
	washed the plaza sand and the paths into a flat sheet and was cut.)
	  * the inner ground and the border hills are Terrain (GroundTerrain, BorderTerrain): Terrain:SetMaterialColor for
	    Grass / LeafyGrass (full), Rock (lighter) and Ground (the dirt paths) / Sand (the plaza): only a light frost;
	  * the pads (and other big flat grass parts, if any): Color lerps toward snow white; pads only a light frost.
	The weights come from SnowCover.tints(level, snowing): settling is one eased curve, melting clears the frost
	first and the grass / hills last. Materials never change, so nothing pops.

	Flicker avoidance:
	  * the level is quantized (SnowCover.quantize, 1/128) and colours are only written when the quantized step or
	    the phase changes; nothing is written on the frames in between;
	  * every colour comes from the surface's ORIGINAL colour (saved once per instance / terrain material), never
	    from its current one, so there is no drift and level 0 restores the original bit for bit;
	  * if something else recolours a tinted part (the server restyling a pad), the new colour becomes the
	    original; our own writes are told apart by comparing with the last colour we applied;
	  * Heartbeat only runs while the level moves (it disconnects when settled) and creates no instances.
	Parts that stream in under Map / Plots get the current tint; removed ones are dropped.

	Late joiners place the level and the phase from the server stamps (WeatherStartedAt / SnowEndedAt) via
	SnowCover.levelAt, so one that arrives mid-melt sees the paths cleared first. The pc-watcher pins the
	client-local level with the workspace attribute SnowCoverDebug (0..1); with the pin set the weather decides
	the phase (Snow = settling, anything else = melting).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local SnowCover = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("SnowCover"))

local SnowGround = {}

type Entry = { orig: Color3, applied: Color3, kind: string }

local TERRAIN_GRASS = { Enum.Material.Grass, Enum.Material.LeafyGrass }
local TERRAIN_FROST = { Enum.Material.Ground, Enum.Material.Sand } -- the dirt paths and the plaza sand
local SAME = 1.5 / 255 -- Color is stored with 8 bits per channel: closer than this is "unchanged"

local tracked: { [BasePart]: Entry } = setmetatable({}, { __mode = "k" }) :: any
local terrainOrig: { [Enum.Material]: Color3 }? = nil
local tracking = false
local connection: RBXScriptConnection? = nil
local level = 0
local snowing = false
local started = false
local appliedKey: number? = nil
local tints: SnowCover.Tints = SnowCover.tints(0, false)

local function forced(): number?
	local value = workspace:GetAttribute(Constants.SNOW_COVER_DEBUG_ATTRIBUTE)
	return if type(value) == "number" then math.clamp(value, 0, 1) else nil
end

local function same(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < SAME and math.abs(a.G - b.G) < SAME and math.abs(a.B - b.B) < SAME
end

local function mixed(orig: Color3, weight: number): Color3
	if weight <= 0 then
		return orig
	end
	local r, g, b = SnowCover.lerpColor(orig.R, orig.G, orig.B, weight)
	return Color3.new(r, g, b)
end

local function weightOf(kind: string): number
	return if kind == "grass" then tints.grass else tints.path
end

local function paint(part: BasePart, entry: Entry)
	local current = part.Color
	if not same(current, entry.applied) then
		entry.orig = current -- someone else recoloured it: that is the new original
	end
	local color = mixed(entry.orig, weightOf(entry.kind))
	if part.Color ~= color then
		part.Color = color
	end
	entry.applied = color
end

local function register(inst: Instance)
	if not inst:IsA("BasePart") or tracked[inst] then
		return
	end
	local parent = inst.Parent
	local kind = SnowCover.classify(
		inst.Name,
		inst.Material.Name,
		parent ~= nil and parent.Name == "Paths",
		inst.Size.X,
		inst.Size.Z,
		inst.Transparency
	)
	if kind then
		local entry = { orig = inst.Color, applied = inst.Color, kind = kind }
		tracked[inst] = entry
		paint(inst, entry)
	end
end

local function watch(root: Instance)
	for _, d in root:GetDescendants() do
		register(d)
	end
	root.DescendantAdded:Connect(register)
end

-- First snow: remember the terrain colours and start following the map. Never runs while the feature is idle.
local function startTracking()
	if tracking then
		return
	end
	tracking = true
	local terrain = workspace.Terrain
	local saved = {}
	for _, list in { TERRAIN_GRASS, TERRAIN_FROST, { Enum.Material.Rock } } do
		for _, material in list do
			saved[material] = terrain:GetMaterialColor(material)
		end
	end
	terrainOrig = saved
	for _, name in { "Map", "Plots" } do
		local root = workspace:FindFirstChild(name)
		if root then
			watch(root)
		end
	end
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "Map" or child.Name == "Plots" then
			watch(child)
		end
	end)
end

local function draw()
	local q = SnowCover.quantize(level)
	local key = q * 2 + (if snowing then 1 else 0)
	if key == appliedKey then
		return
	end
	if q <= 0 and not tracking then
		appliedKey = key
		return -- never snowed: nothing was touched, nothing to restore
	end
	appliedKey = key
	startTracking()
	tints = SnowCover.tints(q, snowing)
	for part, entry in tracked do
		if part.Parent == nil then
			tracked[part] = nil
		else
			paint(part, entry)
		end
	end
	local saved = terrainOrig
	if saved then
		local terrain = workspace.Terrain
		for _, material in TERRAIN_GRASS do
			terrain:SetMaterialColor(material, mixed(saved[material], tints.terrainGrass))
		end
		for _, material in TERRAIN_FROST do
			terrain:SetMaterialColor(material, mixed(saved[material], tints.path)) -- paths melt first
		end
		terrain:SetMaterialColor(Enum.Material.Rock, mixed(saved[Enum.Material.Rock], tints.rock))
	end
end

local function stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

local function run()
	if connection then
		return
	end
	connection = RunService.Heartbeat:Connect(function(dt)
		local pin = forced()
		level = if pin then pin else SnowCover.step(level, dt, snowing)
		draw()
		if pin or SnowCover.settled(level, snowing) then
			stop()
		end
	end)
end

-- Called by WeatherFx whenever the shown weather changes.
function SnowGround.setSnowing(value: boolean)
	if not started then
		return
	end
	snowing = value
	if forced() or not SnowCover.settled(level, snowing) then
		run()
	end
end

-- Late joiners: place the level and the phase from the server's stamps (WeatherStartedAt / SnowEndedAt) and the
-- server clock. A SnowCoverDebug pin or a WeatherDebug preview builds up from 0 instead, so the shots can show it mid-way.
local function place()
	local pinned = forced() ~= nil or workspace:GetAttribute(Constants.WEATHER_DEBUG_ATTRIBUTE) ~= nil
	snowing = workspace:GetAttribute(Constants.WEATHER_ATTRIBUTE) == "Snow"
	level = SnowCover.levelAt(
		snowing,
		workspace:GetAttribute(Constants.WEATHER_STARTED_ATTRIBUTE),
		workspace:GetAttribute(Constants.SNOW_ENDED_ATTRIBUTE),
		workspace:GetServerTimeNow(),
		pinned
	)
	draw()
	if forced() or not SnowCover.settled(level, snowing) then
		run()
	end
end

function SnowGround.start(enabled: boolean)
	started = true
	if enabled then
		place()
	end
	workspace:GetAttributeChangedSignal(Constants.SNOW_COVER_DEBUG_ATTRIBUTE):Connect(function()
		run()
	end)
end

return SnowGround
