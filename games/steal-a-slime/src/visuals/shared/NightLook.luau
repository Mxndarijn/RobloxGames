--!strict
--[[
	NightLook (owner: Archer)

	Pure maths for the client night look (VisualsClient NightSky). Jolt's
	DayNight cycle only writes Lighting.ClockTime; this maps it to how much
	"night" to blend into the place's day Lighting / Atmosphere values.

	  NightLook.SKY                      Sky properties the client ensures
	      (no textures set: the Sky keeps Roblox's default skybox, sun, moon).
	  NightLook.NIGHT                    Look at full night (cool blue
	      ambient for readability, thinner darker atmosphere so stars show).
	  NightLook.factor(clockTime): number   0 by day, 1 at night, smooth
	      ramps around DayNight's SUNRISE (06:30) / SUNSET (17:30).
	  NightLook.blend(day, f): Look      day -> NIGHT by f (0..1).
]]

local NightLook = {}

export type Look = {
	Ambient: Color3,
	OutdoorAmbient: Color3,
	Brightness: number,
	ExposureCompensation: number,
	Density: number, -- Atmosphere
	Haze: number,
	Glare: number,
	Color: Color3,
	Decay: Color3,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

NightLook.SKY = table.freeze({
	StarCount = 3000,
	CelestialBodiesShown = true,
	SunAngularSize = 18,
	MoonAngularSize = 15,
})

NightLook.NIGHT = table.freeze({
	Ambient = rgb(78, 86, 128),
	OutdoorAmbient = rgb(104, 114, 166),
	Brightness = 1.6,
	ExposureCompensation = 0.35,
	Density = 0.2,
	Haze = 0.4,
	Glare = 0,
	Color = rgb(58, 68, 112),
	Decay = rgb(26, 30, 62),
} :: Look)

NightLook.KEYS = table.freeze({
	"Ambient",
	"OutdoorAmbient",
	"Brightness",
	"ExposureCompensation",
	"Density",
	"Haze",
	"Glare",
	"Color",
	"Decay",
})

-- Ramps: dusk 16:30 -> 18:30, dawn 05:30 -> 07:30.
NightLook.DUSK = table.freeze({ 16.5, 18.5 })
NightLook.DAWN = table.freeze({ 5.5, 7.5 })

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

function NightLook.factor(clockTime: number): number
	local c = clockTime % 24
	local dusk, dawn = NightLook.DUSK, NightLook.DAWN
	if c >= dawn[2] and c <= dusk[1] then
		return 0
	elseif c > dusk[1] then
		return smooth((c - dusk[1]) / (dusk[2] - dusk[1]))
	end
	return 1 - smooth((c - dawn[1]) / (dawn[2] - dawn[1]))
end

function NightLook.blend(day: Look, f: number): Look
	local out = {}
	for _, key in NightLook.KEYS do
		local a, b = (day :: any)[key], (NightLook.NIGHT :: any)[key]
		out[key] = if typeof(a) == "Color3" then a:Lerp(b, f) else a + (b - a) * f
	end
	return (out :: any) :: Look
end

return table.freeze(NightLook)
