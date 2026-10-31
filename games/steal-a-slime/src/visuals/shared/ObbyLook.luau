--!strict
--[[
	ObbyLook (pure, contract/obby.md §5)

	The obby world's own look: a clear candy sky world (blue zenith, violet-pink horizon), whatever the time of day or weather on the map.
	VisualsClient ObbyWorld sets `mix` to 1 (this look) on the frame the local player arrives in the obby world
	(WorldLayout.inObbyWorld) and back to 0 (the map's look) on the frame they leave, under a short neutral veil;
	NightSky blends the look over its day / night and weather look by that mix, and ObbyWorld swaps its tint and the
	place's post effects with it.

	  ObbyLook.LOOK / NIGHT            Lighting + Atmosphere values at mix 1 by day / by night (NightLook.Look keys)
	  ObbyLook.TINT                    ColorCorrection at mix 1 (TintColor, Saturation, Brightness, Contrast)
	  ObbyLook.BLOOM / SUN_RAYS / ATMOSPHERE
	                                   the place's Bloom, SunRays and Atmosphere Offset at mix 1 (ObbyWorld blends them)
	  ObbyLook.target(night): Look     LOOK -> NIGHT by the night factor (0..1, NightLook.factor)
	  ObbyLook.blend(base, mix, night?): Look
	                                   base -> target(night) by mix (0..1)
	  ObbyLook.VEIL                    the swap's veil: start tint, seconds to clear, the camera focus lift
	  ObbyLook.get / set / onChanged   the current mix (client), like WeatherGrade
	  ObbyLook.isInside / setInside / onInsideChanged
	                                   whether the local player is in the obby world now (client; ObbyWorld sets it
	                                   each frame, listeners hear only changes): the one signal the plot marker, the
	                                   weather and the tutorial guide read to stand down there
]]

local NightLook = if script then require(script.Parent.NightLook) else require("./NightLook")

local ObbyLook = {}

-- The swap happens at once under a neutral veil that clears in `seconds`; `focusLift` is where the camera looks
-- above the root (the default camera's focus) when ObbyWorld steadies it after the teleport.
ObbyLook.VEIL = table.freeze({
	color = Color3.fromRGB(128, 126, 134),
	seconds = 0.35,
	focusLift = Vector3.new(0, 1.5, 0),
})

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Clear candy sky: a blue zenith fading into a cloud-pink horizon (Haze tints only the low sky), thin enough
-- that the backdrop keeps its edges, low ambient so the sun casts readable shadows on the course, and exposure below
-- the map's so nothing washes out.
ObbyLook.LOOK = table.freeze({
	Ambient = rgb(96, 84, 128),
	OutdoorAmbient = rgb(132, 114, 164),
	Brightness = 2.2,
	ExposureCompensation = -0.1,
	Density = 0.32,
	Haze = 1.4,
	Glare = 0,
	-- cloud-pink, the cloud sea's own tone, so the far banks fade into the horizon instead of a violet band
	Color = rgb(244, 214, 238),
	Decay = rgb(236, 206, 238),
} :: NightLook.Look)

-- The same world at night (blended in by NightLook.factor): a starry sky fading into an indigo-plum horizon, with
-- enough ambient to read the course.
ObbyLook.NIGHT = table.freeze({
	Ambient = rgb(92, 80, 132),
	OutdoorAmbient = rgb(118, 104, 166),
	Brightness = 1.4,
	ExposureCompensation = 0.1,
	Density = 0.3,
	Haze = 1.6,
	Glare = 0,
	Color = rgb(150, 90, 170),
	Decay = rgb(90, 50, 120),
} :: NightLook.Look)

ObbyLook.TINT = table.freeze({
	TintColor = rgb(255, 246, 252),
	Saturation = 0.12,
	Brightness = -0.03,
	Contrast = 0.1,
})

-- Post effects at mix 1: almost no Bloom (bright parts keep their edges), no SunRays, and a high Atmosphere Offset
-- so the horizon band fades softly into the sky.
ObbyLook.BLOOM = table.freeze({ Intensity = 0.12, Size = 16, Threshold = 2.4 })
ObbyLook.SUN_RAYS = table.freeze({ Intensity = 0 })
ObbyLook.ATMOSPHERE = table.freeze({ Offset = 0.7 })

local function lerp(a: any, b: any, t: number): any
	if typeof(a) == "Color3" then
		return (a :: Color3):Lerp(b, t)
	end
	return a + (b - a) * t
end

function ObbyLook.target(night: number?): NightLook.Look
	local n = math.clamp(night or 0, 0, 1)
	local out: any = {}
	for _, key in NightLook.KEYS do
		out[key] = lerp((ObbyLook.LOOK :: any)[key], (ObbyLook.NIGHT :: any)[key], n)
	end
	return out :: NightLook.Look
end

function ObbyLook.blend(base: NightLook.Look, mix: number, night: number?): NightLook.Look
	local t = math.clamp(mix, 0, 1)
	local target: any = ObbyLook.target(night)
	local out: any = {}
	for _, key in NightLook.KEYS do
		out[key] = lerp((base :: any)[key], target[key], t)
	end
	return out :: NightLook.Look
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

local function subscribe<T>(list: { (T) -> () }, fn: (T) -> ()): { Disconnect: () -> () }
	table.insert(list, fn)
	return {
		Disconnect = function()
			local i = table.find(list, fn)
			if i then
				table.remove(list, i)
			end
		end,
	}
end

function ObbyLook.onChanged(fn: (number) -> ()): { Disconnect: () -> () }
	return subscribe(listeners, fn)
end

local inside = false
local insideListeners: { (boolean) -> () } = {}

function ObbyLook.isInside(): boolean
	return inside
end

function ObbyLook.setInside(value: boolean)
	if value == inside then
		return
	end
	inside = value
	for _, fn in table.clone(insideListeners) do
		fn(value)
	end
end

function ObbyLook.onInsideChanged(fn: (boolean) -> ()): { Disconnect: () -> () }
	return subscribe(insideListeners, fn)
end

return ObbyLook
