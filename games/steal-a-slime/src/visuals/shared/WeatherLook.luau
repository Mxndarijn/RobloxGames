--!strict
--[[
	WeatherLook (owner: Archer, FEATURES.Weather)

	Data only, for the client WeatherFx: per weather id the ColorCorrection tint and which camera
	emitter runs. `rate` is the base particles/second at full quality (Weather.emitterRate scales and
	caps it), `lifetime` the particle life in seconds. NEUTRAL is the Clear tint everything tweens to.
]]

local WeatherLook = {}

-- TintColor is r, g, b 0..255: plain data, so the Lune tests can load this module.
export type Tint = { TintColor: { number }, Brightness: number, Contrast: number, Saturation: number }
export type Emitter = { rate: number, lifetime: number, share: number }
export type Look = { tint: Tint, emitter: string?, emitters: { [string]: Emitter } }

WeatherLook.NEUTRAL = table.freeze({
	TintColor = table.freeze({ 255, 255, 255 }),
	Brightness = 0,
	Contrast = 0,
	Saturation = 0,
}) :: Tint

-- Emitter names under the camera part. share = this emitter's part of Config.WEATHER_PARTICLE_CAP.
WeatherLook.EMITTERS = table.freeze({
	Drops = table.freeze({ rate = 220, lifetime = 1.1, share = 0.5 }),
	Flakes = table.freeze({ rate = 90, lifetime = 7, share = 0.7 }),
	Stars = table.freeze({ rate = 14, lifetime = 5, share = 0.4 }),
	Glints = table.freeze({ rate = 30, lifetime = 3, share = 0.3 }),
}) :: { [string]: Emitter }

WeatherLook.LOOKS = table.freeze({
	Clear = table.freeze({ tint = WeatherLook.NEUTRAL, emitters = table.freeze({}) }),
	Rain = table.freeze({
		tint = table.freeze({
			TintColor = table.freeze({ 190, 205, 230 }),
			Brightness = -0.06,
			Contrast = 0.05,
			Saturation = -0.15,
		}),
		emitters = table.freeze({ "Drops" }),
	}),
	Snow = table.freeze({
		tint = table.freeze({
			TintColor = table.freeze({ 225, 238, 255 }),
			Brightness = 0.04,
			Contrast = -0.03,
			Saturation = -0.2,
		}),
		emitters = table.freeze({ "Flakes" }),
	}),
	Starfall = table.freeze({
		tint = table.freeze({
			TintColor = table.freeze({ 205, 190, 255 }),
			Brightness = -0.08,
			Contrast = 0.08,
			Saturation = 0.15,
		}),
		emitters = table.freeze({ "Stars", "Glints" }),
	}),
}) :: { [string]: any }

return table.freeze(WeatherLook)
