--!strict
--[[
	WeatherGrade (owner: Archer, FEATURES.Weather)

	The whole-screen weather colour grade as ONE flat vector of numbers (ColorCorrection tint, Atmosphere
	mix / density / haze, ambient mix, exposure), so a weather change is a single lerp driven by a single
	tween and nothing changes piecemeal. Pure data and maths: no Roblox types, so the Lune tests load it.

	WeatherFx drives `set`; NightSky listens to `Changed` and layers `atmosphere` / `ambient` on its day / night
	look. `current` is the grade being shown right now.
]]

local WeatherLook = if script then require(script.Parent.WeatherLook) else require("./WeatherLook")

export type Grade = { [string]: number }

local WeatherGrade = {}

WeatherGrade.KEYS = table.freeze({
	"TintR",
	"TintG",
	"TintB",
	"Brightness",
	"Contrast",
	"Saturation",
	"FogR",
	"FogG",
	"FogB",
	"FogMix",
	"Density",
	"Haze",
	"AmbR",
	"AmbG",
	"AmbB",
	"AmbMix",
	"Exposure",
})

-- Atmosphere clamps (Roblox ranges).
WeatherGrade.MAX_DENSITY = 1
WeatherGrade.MAX_HAZE = 10

function WeatherGrade.fromLook(look: any): Grade
	local t, a = look.tint, look.atmo
	return table.freeze({
		TintR = t.TintColor[1],
		TintG = t.TintColor[2],
		TintB = t.TintColor[3],
		Brightness = t.Brightness,
		Contrast = t.Contrast,
		Saturation = t.Saturation,
		FogR = a.fog[1],
		FogG = a.fog[2],
		FogB = a.fog[3],
		FogMix = a.fogMix,
		Density = a.density,
		Haze = a.haze,
		AmbR = a.ambient[1],
		AmbG = a.ambient[2],
		AmbB = a.ambient[3],
		AmbMix = a.ambientMix,
		Exposure = a.exposure,
	})
end

function WeatherGrade.of(id: string): Grade
	return WeatherGrade.fromLook(WeatherLook.LOOKS[id] or WeatherLook.LOOKS.Clear)
end

WeatherGrade.NEUTRAL = WeatherGrade.of("Clear")

function WeatherGrade.ease(alpha: number): number
	local x = math.clamp(alpha, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Every key moves with the same eased alpha, so tint, fog and ambient arrive together.
function WeatherGrade.lerp(a: Grade, b: Grade, alpha: number): Grade
	local e = WeatherGrade.ease(alpha)
	local out = {}
	for _, key in WeatherGrade.KEYS do
		out[key] = a[key] + (b[key] - a[key]) * e
	end
	return out
end

-- Atmosphere / lighting values from a day-night look value plus the grade. Colours are r, g, b 0..255.
function WeatherGrade.mixColor(base: { number }, target: { number }, mix: number): { number }
	return {
		base[1] + (target[1] - base[1]) * mix,
		base[2] + (target[2] - base[2]) * mix,
		base[3] + (target[3] - base[3]) * mix,
	}
end

function WeatherGrade.density(base: number, grade: Grade): number
	return math.clamp(base + grade.Density, 0, WeatherGrade.MAX_DENSITY)
end

function WeatherGrade.haze(base: number, grade: Grade): number
	return math.clamp(base + grade.Haze, 0, WeatherGrade.MAX_HAZE)
end

function WeatherGrade.exposure(base: number, grade: Grade): number
	return base + grade.Exposure
end

-- Shared current grade (client). set() notifies listeners (NightSky) in the same frame the tint changes.
local current: Grade = WeatherGrade.NEUTRAL
local listeners: { (Grade) -> () } = {}

function WeatherGrade.get(): Grade
	return current
end

function WeatherGrade.set(grade: Grade)
	current = grade
	for _, fn in listeners do
		fn(grade)
	end
end

function WeatherGrade.onChanged(fn: (Grade) -> ()): { Disconnect: () -> () }
	table.insert(listeners, fn)
	return {
		Disconnect = function()
			local i = table.find(listeners, fn)
			if i then
				table.remove(listeners, i)
			end
		end,
	}
end

return WeatherGrade
