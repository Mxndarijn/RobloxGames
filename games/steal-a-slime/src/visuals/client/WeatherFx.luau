--!strict
--[[
	WeatherFx (VisualsClient module, FEATURES.Weather, WEATHER.md)

	Client-only. Mirrors the workspace attribute Constants.WEATHER_ATTRIBUTE (Weather module) and
	draws it: one anchored emitter part that follows the camera (moved on Heartbeat only while a
	weather is showing) and a ColorCorrection tint, both tweened in / out over WEATHER_FADE_SECONDS.
	Emitter rates = base * quality scale (graphics level, touch) under Config.WEATHER_PARTICLE_CAP.
	Nothing is drawn while FEATURES.Weather is off, except for the Constants.WEATHER_DEBUG_ATTRIBUTE
	preview that the pc-watcher sets on one client for proof frames.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local Weather = require(Shared:WaitForChild("Weather"))
local WeatherGrade = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("WeatherGrade"))
local WeatherLook = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("WeatherLook"))

local SnowGround = require(script.Parent:WaitForChild("SnowGround"))

local WeatherFx = {}

-- Snow starts at a fixed height so every flake (speed 7 x lifetime 8, 15 deg spread, >= 52 studs down) lands on the ground (v30 F2).
local SNOW_EMITTER_Y = 42

local STAR_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SOFT_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local part: Part? = nil
local tint: ColorCorrectionEffect? = nil
local heartbeat: RBXScriptConnection? = nil
local shown: string = Weather.CLEAR
local token = 0
local started = false

local function quality(): number
	local ok, level = pcall(function()
		return (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel.Value
	end)
	return Weather.qualityScale(if ok and type(level) == "number" then level else 0, UserInputService.TouchEnabled)
end

local function makeEmitter(name: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Rate = 0
	e.Enabled = true
	e.Lifetime = NumberRange.new(WeatherLook.EMITTERS[name].lifetime)
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Acceleration = Vector3.zero
	if name == "Drops" then
		e.Speed = NumberRange.new(70, 90)
		e.Size = NumberSequence.new(0.12)
		e.Orientation = Enum.ParticleOrientation.VelocityParallel
		e.Transparency = NumberSequence.new(0.45)
		e.Color = ColorSequence.new(Color3.fromRGB(190, 215, 255))
		e.Texture = SOFT_TEXTURE
		e.Squash = NumberSequence.new(-14)
	elseif name == "Flakes" then
		e.Speed = NumberRange.new(7, 9)
		e.Size = NumberSequence.new(0.35)
		-- fades out in the last stretch, i.e. as it lands and melts into the cover
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.08, 0.1),
			NumberSequenceKeypoint.new(0.85, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		e.RotSpeed = NumberRange.new(-60, 60)
		e.SpreadAngle = Vector2.new(15, 15)
		e.Color = ColorSequence.new(Color3.new(1, 1, 1))
		e.Texture = STAR_TEXTURE
	elseif name == "Stars" then
		e.Speed = NumberRange.new(30, 45)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.2) })
		e.LightEmission = 1
		e.Color = ColorSequence.new(Color3.fromRGB(255, 240, 160), Color3.fromRGB(190, 160, 255))
		e.Texture = STAR_TEXTURE
		e.SpreadAngle = Vector2.new(8, 8)
		e.Acceleration = Vector3.new(6, 0, 0) -- slight slant, so they read as shooting stars
	else
		e.Speed = NumberRange.new(2, 6)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		e.LightEmission = 1
		e.Transparency = NumberSequence.new(0.2)
		e.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(160, 200, 255))
		e.Texture = STAR_TEXTURE
		e.SpreadAngle = Vector2.new(180, 180)
	end
	return e
end

local function ensureFx()
	if not part then
		local p = Instance.new("Part")
		p.Name = "WeatherEmitter"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Transparency = 1
		p.Size = Vector3.new(90, 1, 90)
		for name in WeatherLook.EMITTERS do
			makeEmitter(name).Parent = p
		end
		p.Parent = workspace
		part = p
	end
	if not tint then
		local c = Instance.new("ColorCorrectionEffect")
		c.Name = "WeatherTint"
		c.Parent = Lighting
		tint = c
	end
	if not heartbeat then
		heartbeat = RunService.Heartbeat:Connect(function()
			local camera = workspace.CurrentCamera
			if part and camera then
				local at = camera.CFrame.Position
				local y = if shown == "Snow" then SNOW_EMITTER_Y else at.Y + 40
				part.CFrame = CFrame.new(at.X, y, at.Z)
			end
		end)
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
	if part then
		part:Destroy()
		part = nil
	end
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
		local emitter = (part :: Part):FindFirstChild(name)
		fromRates[name] = if emitter and emitter:IsA("ParticleEmitter") then emitter.Rate else 0
	end
	local value = driver :: NumberValue
	value.Value = 0
	local function step()
		local alpha = value.Value
		applyGrade(WeatherGrade.lerp(from, goal, alpha))
		local e = WeatherGrade.ease(alpha)
		for name, rate in rates do
			local emitter = part and part:FindFirstChild(name)
			if emitter and emitter:IsA("ParticleEmitter") then
				emitter.Rate = fromRates[name] + (rate - fromRates[name]) * e
			end
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
	if id == Weather.CLEAR and not part then
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
