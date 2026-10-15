--!strict
--[[
	NightSky (VisualsClient module)

	Client-only, idempotent. Ensures a Sky (NightLook.SKY: many stars, sun and
	moon shown, default skybox textures) and an Atmosphere in Lighting, then
	on every Lighting.ClockTime change (the server's DayNight cycle) blends
	Ambient / OutdoorAmbient / Brightness / ExposureCompensation and the
	Atmosphere towards NightLook.NIGHT by NightLook.factor.

	The day values are the place's own (default.project.json), captured once
	into "NightLookDay_<key>" attributes on Lighting / the Atmosphere, so a
	second start never captures night values as "day".
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NightLook = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("NightLook"))

local NightSky = {}

NightSky.ATTRIBUTE_PREFIX = "NightLookDay_"
local ATMOSPHERE_KEYS = table.freeze({ Density = true, Haze = true, Glare = true, Color = true, Decay = true })

local started = false

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
		local look = NightLook.blend(day, NightLook.factor(Lighting.ClockTime))
		for _, key in NightLook.KEYS do
			local holder: any = if ATMOSPHERE_KEYS[key] then atmosphere else Lighting
			holder[key] = (look :: any)[key]
		end
	end
	Lighting:GetPropertyChangedSignal("ClockTime"):Connect(apply)
	apply()
end

return NightSky
