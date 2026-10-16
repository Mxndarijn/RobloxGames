--!strict
--[[
	NightSky (VisualsClient module)

	Client-only, idempotent. Ensures a Sky (NightLook.SKY: many stars, sun and
	moon shown, default skybox textures) and an Atmosphere in Lighting, then
	on every Lighting.ClockTime change (the server's DayNight cycle) blends
	Ambient / OutdoorAmbient / Brightness / ExposureCompensation and the
	Atmosphere towards NightLook.NIGHT by NightLook.factor. The weather grade (WeatherGrade, driven by
	WeatherFx) is layered on top of that look, re-applied each frame while it tweens.

	The day values are the place's own (default.project.json), captured once
	into "NightLookDay_<key>" attributes on Lighting / the Atmosphere, so a
	second start never captures night values as "day".
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NightLook = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("NightLook"))
local WeatherGrade = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("WeatherGrade"))

local NightSky = {}

NightSky.ATTRIBUTE_PREFIX = "NightLookDay_"
local ATMOSPHERE_KEYS = table.freeze({ Density = true, Haze = true, Glare = true, Color = true, Decay = true })

local started = false

local function toRgb(c: Color3): { number }
	return { c.R * 255, c.G * 255, c.B * 255 }
end

local function toColor(rgb: { number }): Color3
	return Color3.fromRGB(math.round(rgb[1]), math.round(rgb[2]), math.round(rgb[3]))
end

local function ensure(className: string): Instance
	local existing = Lighting:FindFirstChildOfClass(className)
	if existing then
		return existing
	end
	local created = Instance.new(className)
	created.Name = className
	created.Parent = Lighting
	return created
end

-- The day look: attribute if captured before, else the current property (captured now).
local function dayLook(atmosphere: Instance): NightLook.Look
	local day = {}
	for _, key in NightLook.KEYS do
		local holder: Instance = if ATMOSPHERE_KEYS[key] then atmosphere else Lighting
		local attribute = NightSky.ATTRIBUTE_PREFIX .. key
		local value = holder:GetAttribute(attribute)
		if value == nil then
			value = (holder :: any)[key]
			holder:SetAttribute(attribute, value)
		end
		day[key] = value
	end
	return (day :: any) :: NightLook.Look
end

function NightSky.start()
	if started then
		return
	end
	started = true
	local sky: any = ensure("Sky")
	for key, value in NightLook.SKY do
		sky[key] = value
	end
	local atmosphere = ensure("Atmosphere")
	local day = dayLook(atmosphere)
	local function apply()
		local look: any = NightLook.blend(day, NightLook.factor(Lighting.ClockTime))
		local grade = WeatherGrade.get()
		if grade ~= WeatherGrade.NEUTRAL then -- weather grade (WeatherFx) layered on the day / night look
			look.Color =
				toColor(WeatherGrade.mixColor(toRgb(look.Color), { grade.FogR, grade.FogG, grade.FogB }, grade.FogMix))
			look.Ambient = toColor(
				WeatherGrade.mixColor(toRgb(look.Ambient), { grade.AmbR, grade.AmbG, grade.AmbB }, grade.AmbMix)
			)
			look.OutdoorAmbient = toColor(
				WeatherGrade.mixColor(toRgb(look.OutdoorAmbient), { grade.AmbR, grade.AmbG, grade.AmbB }, grade.AmbMix)
			)
			look.Density = WeatherGrade.density(look.Density, grade)
			look.Haze = WeatherGrade.haze(look.Haze, grade)
			look.ExposureCompensation = WeatherGrade.exposure(look.ExposureCompensation, grade)
		end
		for _, key in NightLook.KEYS do
			local holder: any = if ATMOSPHERE_KEYS[key] then atmosphere else Lighting
			holder[key] = look[key]
		end
	end
	Lighting:GetPropertyChangedSignal("ClockTime"):Connect(apply)
	WeatherGrade.onChanged(apply)
	apply()
end

return NightSky
