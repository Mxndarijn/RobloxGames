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
export type Emitter = {
	rate: number,
	lifetime: number,
	share: number,
	speed: { number },
	spread: number,
	sideAccel: number,
}
-- Scene grade on top of the tint: Atmosphere (Color mixed by fogMix, Density / Haze added), Lighting Ambient /
-- OutdoorAmbient mixed by ambientMix and ExposureCompensation added. NightSky applies it on the day / night look.
export type Atmo = {
	fog: { number },
	fogMix: number,
	density: number,
	haze: number,
	ambient: { number },
	ambientMix: number,
	exposure: number,
}
export type Look = { tint: Tint, atmo: Atmo, emitter: string?, emitters: { [string]: Emitter } }

WeatherLook.NEUTRAL = table.freeze({
	TintColor = table.freeze({ 255, 255, 255 }),
	Brightness = 0,
	Contrast = 0,
	Saturation = 0,
}) :: Tint

WeatherLook.NEUTRAL_ATMO = table.freeze({
	fog = table.freeze({ 200, 210, 225 }),
	fogMix = 0,
	density = 0,
	haze = 0,
	ambient = table.freeze({ 200, 210, 225 }),
	ambientMix = 0,
	exposure = 0,
}) :: Atmo

-- Emitter names on every tile of the camera sheet. share = this emitter's part of Config.WEATHER_PARTICLE_CAP.
-- How the particles move (WeatherShelter reads it to keep them out of the jars): speed = { min, max } studs/s
-- straight down, spread = SpreadAngle in degrees, sideAccel = sideways Acceleration in studs/s^2.
WeatherLook.EMITTERS = table.freeze({
	Drops = table.freeze({ rate = 220, lifetime = 1.1, share = 0.5, speed = { 70, 90 }, spread = 0, sideAccel = 0 }),
	Flakes = table.freeze({ rate = 90, lifetime = 8, share = 0.7, speed = { 7, 9 }, spread = 15, sideAccel = 0 }),
	Stars = table.freeze({ rate = 14, lifetime = 5, share = 0.4, speed = { 30, 45 }, spread = 8, sideAccel = 6 }),
	Glints = table.freeze({ rate = 30, lifetime = 3, share = 0.3, speed = { 2, 6 }, spread = 180, sideAccel = 0 }),
}) :: { [string]: Emitter }

WeatherLook.LOOKS = table.freeze({
	Clear = table.freeze({ tint = WeatherLook.NEUTRAL, atmo = WeatherLook.NEUTRAL_ATMO, emitters = table.freeze({}) }),
	Rain = table.freeze({
		tint = table.freeze({
			TintColor = table.freeze({ 190, 205, 230 }),
			Brightness = -0.06,
			Contrast = 0.05,
			Saturation = -0.15,
		}),
		atmo = table.freeze({
			fog = table.freeze({ 120, 135, 160 }),
			fogMix = 0.35,
			density = 0.12,
			haze = 1.2,
			ambient = table.freeze({ 110, 125, 150 }),
			ambientMix = 0.35,
			exposure = -0.15,
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
		atmo = table.freeze({
			fog = table.freeze({ 225, 235, 248 }),
			fogMix = 0.45,
			density = 0.1,
			haze = 0.8,
			ambient = table.freeze({ 200, 215, 240 }),
			ambientMix = 0.35,
			exposure = 0.1,
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
		atmo = table.freeze({
			fog = table.freeze({ 90, 70, 150 }),
			fogMix = 0.3,
			density = 0.04,
			haze = 0.4,
			ambient = table.freeze({ 120, 100, 190 }),
			ambientMix = 0.3,
			exposure = -0.1,
		}),
		emitters = table.freeze({ "Stars", "Glints" }),
	}),
}) :: { [string]: any }

return table.freeze(WeatherLook)
