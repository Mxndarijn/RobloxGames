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
local WeatherLook = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("WeatherLook"))

local WeatherFx = {}

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
		e.Speed = NumberRange.new(5, 9)
		e.Size = NumberSequence.new(0.35)
		e.Transparency = NumberSequence.new(0.1)
		e.RotSpeed = NumberRange.new(-60, 60)
		e.SpreadAngle = Vector2.new(25, 25)
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
				part.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 40, 0))
			end
		end)
	end
end

local function teardown()
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

local function tween(instance: Instance, goal: { [string]: any })
	TweenService:Create(instance, TweenInfo.new(Config.WEATHER_FADE_SECONDS, Enum.EasingStyle.Sine), goal):Play()
end

-- Draws weather `id` ("Clear" fades everything out, then removes the instances).
function WeatherFx.show(id: string)
	if id == shown then
		return
	end
	shown = id
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
	for name, spec in WeatherLook.EMITTERS do
		local emitter = (part :: Part):FindFirstChild(name)
		if emitter and emitter:IsA("ParticleEmitter") then
			local rate = if active[name] then Weather.emitterRate(spec.rate, spec.lifetime, scale, spec.share) else 0
			tween(emitter, { Rate = rate })
		end
	end
	local rgb = look.tint.TintColor
	tween(tint :: ColorCorrectionEffect, {
		TintColor = Color3.fromRGB(rgb[1], rgb[2], rgb[3]),
		Brightness = look.tint.Brightness,
		Contrast = look.tint.Contrast,
		Saturation = look.tint.Saturation,
	})
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
	Weather.attach(workspace)
	Weather.Changed:Connect(refresh)
	workspace:GetAttributeChangedSignal(Constants.WEATHER_DEBUG_ATTRIBUTE):Connect(refresh)
	refresh()
end

return WeatherFx
