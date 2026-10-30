--!strict
--[[
	ObbyLook (pure, contract/obby.md §5)

	The obby world's own look: a candy-pink, lilac-hazed sky world, whatever the time of day or weather on the map.
	VisualsClient ObbyWorld fades `mix` from 0 (the map's look) to 1 (this look) over FADE seconds while the local
	player is in the obby world (WorldLayout.inObbyWorld) and back when they leave; NightSky blends LOOK over its day /
	night and weather look by that mix, and ObbyWorld tints a ColorCorrection by it.

	  ObbyLook.LOOK                    Lighting + Atmosphere values at mix 1 (NightLook.Look keys)
	  ObbyLook.TINT                    ColorCorrection at mix 1 (TintColor, Saturation, Brightness)
	  ObbyLook.blend(base, mix): Look  base -> LOOK by mix (0..1)
	  ObbyLook.toward(mix, inside, dt) the next mix: moves 1 / FADE per second towards 1 inside, 0 outside
	  ObbyLook.get / set / onChanged   the current mix (client), like WeatherGrade
]]

local NightLook = if script then require(script.Parent.NightLook) else require("./NightLook")

local ObbyLook = {}

ObbyLook.FADE = 0.6 -- seconds for the full swap

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

ObbyLook.LOOK = table.freeze({
	Ambient = rgb(170, 140, 200),
	OutdoorAmbient = rgb(214, 180, 230),
	Brightness = 2.4,
	ExposureCompensation = 0.25,
	Density = 0.42, -- Atmosphere: thick enough that the backdrop melts into the haze
	Haze = 2.2,
	Glare = 0.4,
	Color = rgb(255, 196, 232),
	Decay = rgb(170, 130, 230),
} :: NightLook.Look)

ObbyLook.TINT = table.freeze({
	TintColor = rgb(255, 236, 248),
	Saturation = 0.2,
	Brightness = 0.03,
})

local function lerp(a: any, b: any, t: number): any
	if typeof(a) == "Color3" then
		return (a :: Color3):Lerp(b, t)
	end
	return a + (b - a) * t
end

function ObbyLook.blend(base: NightLook.Look, mix: number): NightLook.Look
	local t = math.clamp(mix, 0, 1)
	local out: any = {}
	for _, key in NightLook.KEYS do
		out[key] = lerp((base :: any)[key], (ObbyLook.LOOK :: any)[key], t)
	end
	return out :: NightLook.Look
end

function ObbyLook.toward(mix: number, inside: boolean, dt: number): number
	local step = dt / ObbyLook.FADE
	return if inside then math.min(1, mix + step) else math.max(0, mix - step)
end

-- Shared current mix (client). set() notifies listeners (NightSky) in the same frame.
local current = 0
local listeners: { (number) -> () } = {}

function ObbyLook.get(): number
	return current
end

function ObbyLook.set(mix: number)
	if mix == current then
		return
	end
	current = mix
	for _, fn in listeners do
		fn(mix)
	end
end

function ObbyLook.onChanged(fn: (number) -> ()): { Disconnect: () -> () }
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

return ObbyLook
