--!strict
--[[
	WeatherFx (VisualsClient module, FEATURES.Weather, WEATHER.md)

	Client-only. Mirrors the workspace attribute Constants.WEATHER_ATTRIBUTE (Weather module) and
	draws it: a sheet of anchored emitter tiles over the camera (WeatherShelter: snapped to a world
	grid, moved on Heartbeat only while a weather is showing) and a ColorCorrection tint, both tweened
	in / out over WEATHER_FADE_SECONDS. Tiles near a goo jar emit nothing, so no weather falls inside one.
	Emitter rates = base * quality scale (graphics level, touch; the lowest level on "Goo effects: Low") under Config.WEATHER_PARTICLE_CAP,
	shared out over the tiles.
	Nothing is drawn while FEATURES.Weather is off, except for the Constants.WEATHER_DEBUG_ATTRIBUTE
	preview that the pc-watcher sets on one client for proof frames.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local EffectPrefs = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("EffectPrefs"))
local Weather = require(Shared:WaitForChild("Weather"))
local WeatherGrade = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("WeatherGrade"))
local WeatherLook = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("WeatherLook"))
local WeatherShelter = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("WeatherShelter"))
local WorldLayout = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("WorldLayout"))

local SnowGround = require(script.Parent:WaitForChild("SnowGround"))

local WeatherFx = {}

local STAR_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SOFT_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local REMASK_FALL = 2 -- studs the sheet may rise or sink before the tile masks are worked out again

local sheet: Folder? = nil
local tiles: { Part } = {}
local footprints = WeatherShelter.footprints()
-- What every emitter would run at with no jars around (the fade tweens these); the Heartbeat shares them out.
local current: { [string]: number } = {}
local masks: { { [string]: boolean } } = {}
local maskKey: string? = nil
local tint: ColorCorrectionEffect? = nil
local heartbeat: RBXScriptConnection? = nil
local shown: string = Weather.CLEAR
local token = 0
local started = false

local function quality(): number
	if EffectPrefs.isLow(Players.LocalPlayer) then
		return Weather.qualityScale(1, UserInputService.TouchEnabled)
	end
	local ok, level = pcall(function()
		return (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel.Value
	end)
	return Weather.qualityScale(if ok and type(level) == "number" then level else 0, UserInputService.TouchEnabled)
end

local function makeEmitter(name: string): ParticleEmitter
	local spec = WeatherLook.EMITTERS[name]
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Rate = 0
	e.Enabled = true
	e.Lifetime = NumberRange.new(spec.lifetime)
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Speed = NumberRange.new(spec.speed[1], spec.speed[2])
	e.SpreadAngle = Vector2.new(spec.spread, spec.spread)
	e.Acceleration = Vector3.new(spec.sideAccel, 0, 0)
	if name == "Drops" then
		e.Size = NumberSequence.new(0.12)
		e.Orientation = Enum.ParticleOrientation.VelocityParallel
		e.Transparency = NumberSequence.new(0.45)
		e.Color = ColorSequence.new(Color3.fromRGB(190, 215, 255))
		e.Texture = SOFT_TEXTURE
		e.Squash = NumberSequence.new(-14)
	elseif name == "Flakes" then
		e.Size = NumberSequence.new(0.35)
		-- fades out in the last stretch, i.e. as it lands and melts into the cover
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.08, 0.1),
			NumberSequenceKeypoint.new(0.85, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.RotSpeed = NumberRange.new(-60, 60)
		e.Color = ColorSequence.new(Color3.new(1, 1, 1))
		e.Texture = STAR_TEXTURE
	elseif name == "Stars" then
		-- sideAccel gives them a slight slant, so they read as shooting stars
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.2) })
		e.LightEmission = 1
		e.Color = ColorSequence.new(Color3.fromRGB(255, 240, 160), Color3.fromRGB(190, 160, 255))
		e.Texture = STAR_TEXTURE
	else
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		e.LightEmission = 1
		e.Transparency = NumberSequence.new(0.2)
		e.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(160, 200, 255))
		e.Texture = STAR_TEXTURE
	end
	return e
end

-- Which emitters each tile may run: only those whose particles cannot drift into a jar from that tile.
local function remask(centres: { { number } }, fall: number)
	local margins: { [string]: number } = {}
	for name, spec in WeatherLook.EMITTERS do
		margins[name] = WeatherShelter.reach(spec, fall)
	end
	for i, c in centres do
		local mask = {}
		for name, margin in margins do
			mask[name] = WeatherShelter.open(c[1], c[2], margin, footprints)
		end
		masks[i] = mask
	end
end

-- Moves the sheet over the camera and shares the current rates out over the tiles that may emit.
local function follow()
	local camera = workspace.CurrentCamera
	if not camera or #tiles == 0 then
		return
	end
	local at = camera.CFrame.Position
	local y = if shown == "Snow" then WeatherShelter.SNOW_Y else at.Y + WeatherShelter.ABOVE_CAMERA
	local centres = WeatherShelter.tiles(at.X, at.Z)
	local fall = y - WorldLayout.PLOT_FLOOR_TOP
	local bucket = math.floor(fall / REMASK_FALL)
	local key = `{centres[1][1]},{centres[1][2]},{bucket}`
	if key ~= maskKey then
		maskKey = key
		remask(centres, (bucket + 1) * REMASK_FALL) -- the bucket's highest fall, so the margin never falls short
	end
	local frames = table.create(#tiles)
	for i, c in centres do
		frames[i] = CFrame.new(c[1], y, c[2])
	end
	workspace:BulkMoveTo(tiles, frames, Enum.BulkMoveMode.FireCFrameChanged)
	local share = 1 / #tiles
	for i, p in tiles do
		local mask = masks[i]
		for _, child in p:GetChildren() do
			if child:IsA("ParticleEmitter") then
				local rate = if mask[child.Name] then (current[child.Name] or 0) * share else 0
				if math.abs(child.Rate - rate) > 1e-4 then
					child.Rate = rate
				end
			end
		end
	end
end

local function ensureFx()
	if not sheet then
		local folder = Instance.new("Folder")
		folder.Name = "WeatherEmitter"
		local size = WeatherShelter.TILE
		for i = 1, WeatherShelter.TILES * WeatherShelter.TILES do
			local p = Instance.new("Part")
			p.Name = `Tile_{i}`
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Transparency = 1
			p.Size = Vector3.new(size, 1, size)
			for name in WeatherLook.EMITTERS do
				makeEmitter(name).Parent = p
			end
			p.Parent = folder
			tiles[i] = p
		end
		folder.Parent = workspace
		sheet = folder
		maskKey = nil
	end
	if not tint then
		local c = Instance.new("ColorCorrectionEffect")
		c.Name = "WeatherTint"
		c.Parent = Lighting
		tint = c
	end
	if not heartbeat then
		heartbeat = RunService.Heartbeat:Connect(follow)
	end
end

local driver: NumberValue? = nil
local driverTween: Tween? = nil
local driverConn: RBXScriptConnection? = nil

local function teardown()
	if driverConn then
		driverConn:Disconnect()
		driverConn = nil
	end
	WeatherGrade.set(WeatherGrade.NEUTRAL)
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	if sheet then
		sheet:Destroy()
		sheet = nil
	end
	table.clear(tiles)
	table.clear(masks)
	table.clear(current)
	maskKey = nil
	if tint then
		tint:Destroy()
		tint = nil
	end
end

local function applyGrade(grade: WeatherGrade.Grade)
	if tint then
		tint.TintColor = Color3.fromRGB(grade.TintR, grade.TintG, grade.TintB)
		tint.Brightness = grade.Brightness
		tint.Contrast = grade.Contrast
		tint.Saturation = grade.Saturation
	end
	WeatherGrade.set(grade) -- NightSky re-applies Atmosphere + ambient in the same frame
end

-- One tween (0 -> 1 on a NumberValue) moves the tint, the Atmosphere / ambient grade and the emitter rates
-- together, so the screen changes colour in a single smooth go. A change during a tween starts from what is
-- on screen now.
local function transition(goal: WeatherGrade.Grade, rates: { [string]: number })
	if driverTween then
		driverTween:Cancel()
	end
	if driverConn then
		driverConn:Disconnect()
	end
	if not driver then
		driver = Instance.new("NumberValue")
	end
	local from = WeatherGrade.get()
	local fromRates: { [string]: number } = {}
	for name in rates do
		fromRates[name] = current[name] or 0
	end
	local value = driver :: NumberValue
	value.Value = 0
	local function step()
		local alpha = value.Value
		applyGrade(WeatherGrade.lerp(from, goal, alpha))
		local e = WeatherGrade.ease(alpha)
		for name, rate in rates do
			current[name] = fromRates[name] + (rate - fromRates[name]) * e
		end
	end
	driverConn = value.Changed:Connect(step)
	local info = TweenInfo.new(Config.WEATHER_FADE_SECONDS, Enum.EasingStyle.Linear)
	local t = TweenService:Create(value, info, { Value = 1 })
	driverTween = t
	t:Play()
end

-- Draws weather `id` ("Clear" fades everything out, then removes the instances).
function WeatherFx.show(id: string)
	if id == shown then
		return
	end
	shown = id
	SnowGround.setSnowing(id == "Snow")
	token += 1
	local mine = token
	local look = WeatherLook.LOOKS[id] or WeatherLook.LOOKS.Clear
	if id == Weather.CLEAR and not sheet then
		return
	end
	ensureFx()
	local scale = quality()
	local active: { [string]: boolean } = {}
	for _, name in look.emitters do
		active[name] = true
	end
	local rates: { [string]: number } = {}
	for name, spec in WeatherLook.EMITTERS do
		rates[name] = if active[name] then Weather.emitterRate(spec.rate, spec.lifetime, scale, spec.share) else 0
	end
	transition(WeatherGrade.of(id), rates)
	if id == Weather.CLEAR then
		task.delay(Config.WEATHER_FADE_SECONDS + 4, function()
			if token == mine then
				teardown()
			end
		end)
	end
end

local function refresh()
	local debug = workspace:GetAttribute(Constants.WEATHER_DEBUG_ATTRIBUTE)
	WeatherFx.show(Weather.visualId(Config.FEATURES.Weather, Weather.getCurrent(), debug))
end

function WeatherFx.start()
	if started then
		return
	end
	started = true
	-- Late joiners get the cover level from the server stamps; nothing at all while Weather is off.
	if Config.FEATURES.Weather or workspace:GetAttribute(Constants.WEATHER_DEBUG_ATTRIBUTE) ~= nil then
		SnowGround.start(true)
	end
	Weather.attach(workspace)
	Weather.Changed:Connect(refresh)
	workspace:GetAttributeChangedSignal(Constants.WEATHER_DEBUG_ATTRIBUTE):Connect(refresh)
	refresh()
end

return WeatherFx
