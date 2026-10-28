--!strict
--[[
	AudioLogic (FEATURES.Audio, CONTRACT.md §2 Extras)

	Pure rules behind ui/SoundController (no Roblox APIs; loads under Lune):
	  AudioLogic.clampVolume(v, fallback?)         number -> 0..1 (NaN / non-number -> fallback or 0)
	  AudioLogic.sanitize(raw, cfg)                -> { muted, sfx, music } from stored attributes
	  AudioLogic.groupVolume(settings, group)      -> 0 when muted, else the group's volume
	  AudioLogic.resolveSfx(cfg, name)             -> asset id or nil (registry name, Notify name or raw id)
	  AudioLogic.isNight(clockTime)                ClockTime outside dayNight.SUNRISE..SUNSET (Shared.DayNight passed in)
	  AudioLogic.ambientFor(clockTime, cfg, dayNight)      -> "day" | "night", id? (nil id = silent)
	  AudioLogic.fadeStep(current, target, dt, s)  linear fade towards target over `s` seconds
	  AudioLogic.allowSfx(state, name, now, cfg)   per-name throttle (SFX_MIN_GAP, SFX_MAX_LIVE); true reserves a slot
	  AudioLogic.releaseSfx(state, name)           frees the slot when that Sound is gone
	  AudioLogic.oneshotId(cfg)                    -> NIGHT_ONESHOT_ID or nil (nil = no owl)
	  AudioLogic.oneshotStep(timer, dt, level, cfg, rng, spec?) -> timer?, fire  one-shot countdown (rng: () -> 0..1;
	                                               spec = gap range and bed level, default the night owl)
	  AudioLogic.oneshotSpeed(cfg, rng)            PlaybackSpeed for one call
	  AudioLogic.layerTargets(input, cfg, dayNight) -> every looped layer that should sound now (music, beds, weather)
	  AudioLogic.jitter(base, spread, rng)         base +- spread (PlaybackSpeed variation for repeated SFX)
	  AudioLogic.playSpeed(cfg, name, speed?, rng) PlaybackSpeed for one play (Sounds.SPEED, Sounds.VARY jitter)
	  AudioLogic.pick(list, rng)                   one entry of a variant list
]]

local Sounds = if script then require(script.Parent.Sounds) else require("./Sounds")

local AudioLogic = {}

AudioLogic.VOLUME_STEP = 0.05

export type Settings = { muted: boolean, sfx: number, music: number }

function AudioLogic.clampVolume(v: any, fallback: number?): number
	if type(v) ~= "number" or v ~= v then
		return fallback or 0
	end
	return math.clamp(v, 0, 1)
end

-- Snaps to whole multiples of `step` (integer percent maths, so 0.35 stays 0.35 and not 0.35000000000000003).
function AudioLogic.snapVolume(v: any, step: number?): number
	local stepPct = math.max(1, math.round((step or AudioLogic.VOLUME_STEP) * 100))
	local pct = math.round(AudioLogic.clampVolume(v, 0) * 100 / stepPct) * stepPct
	return math.clamp(pct, 0, 100) / 100
end

function AudioLogic.volumeFromPixel(x: any, left: any, width: any, step: number?): number
	if type(x) ~= "number" or type(left) ~= "number" or type(width) ~= "number" or width <= 0 then
		return 0
	end
	return AudioLogic.snapVolume((x - left) / width, step)
end

function AudioLogic.volumeToAlpha(v: any): number
	return AudioLogic.clampVolume(v, 0)
end

function AudioLogic.percentText(v: any): string
	return `{math.round(AudioLogic.clampVolume(v, 0) * 100)}%`
end

function AudioLogic.sanitize(raw: any, cfg: any): Settings
	local r: { [string]: any } = if type(raw) == "table" then raw else {}
	return {
		muted = r.muted == true,
		sfx = AudioLogic.clampVolume(r.sfx, cfg.DEFAULT_SFX_VOLUME),
		music = AudioLogic.clampVolume(r.music, cfg.DEFAULT_MUSIC_VOLUME),
	}
end

function AudioLogic.groupVolume(settings: Settings, group: string): number
	if settings.muted then
		return 0
	end
	return if group == "Music" then settings.music else settings.sfx
end

local function validId(id: any): string?
	if
		type(id) == "string"
		and (string.match(id, "^rbxassetid://%d+$") or string.match(id, "^rbxasset://[%w_/%.%-]+$"))
	then
		return id
	end
	return nil
end

-- Registry name ("buy") -> Config.AUDIO.SFX entry -> Notify name or direct id. Unknown / empty -> nil (silent).
function AudioLogic.resolveSfx(cfg: any, name: any): string?
	if type(name) ~= "string" then
		return nil
	end
	local entry = cfg.SFX[name]
	if entry == nil then
		entry = name
	end
	return validId(entry) or validId(Sounds.resolve(entry))
end

function AudioLogic.isNight(clockTime: number, dayNight: any): boolean
	local t = clockTime % 24
	return t < dayNight.SUNRISE or t >= dayNight.SUNSET
end

function AudioLogic.ambientFor(clockTime: number, cfg: any, dayNight: any): (string, string?)
	if AudioLogic.isNight(clockTime, dayNight) then
		return "night", validId(cfg.AMBIENT_NIGHT_ID)
	end
	return "day", validId(cfg.AMBIENT_DAY_ID)
end

function AudioLogic.oneshotId(cfg: any): string?
	return validId(cfg.NIGHT_ONESHOT_ID)
end

function AudioLogic.fadeStep(current: number, target: number, dt: number, seconds: number): number
	if seconds <= 0 or math.abs(target - current) < 1e-6 then
		return target
	end
	local step = math.max(dt, 0) / seconds
	if current < target then
		return math.min(target, current + step)
	end
	return math.max(target, current - step)
end

export type SfxState = { last: { [string]: number }, live: { [string]: number } }

function AudioLogic.newSfxState(): SfxState
	return { last = {}, live = {} }
end

-- Click spam or a burst of hits must not stack dozens of copies of one sound.
function AudioLogic.allowSfx(state: SfxState, name: string, now: number, cfg: any): boolean
	local last = state.last[name]
	if last and now - last < cfg.SFX_MIN_GAP then
		return false
	end
	if (state.live[name] or 0) >= cfg.SFX_MAX_LIVE then
		return false
	end
	state.last[name] = now
	state.live[name] = (state.live[name] or 0) + 1
	return true
end

function AudioLogic.releaseSfx(state: SfxState, name: string)
	state.live[name] = math.max(0, (state.live[name] or 0) - 1)
end

-- Seconds until the next night one-shot: uniform in NIGHT_ONESHOT_MIN..MAX_SECONDS.
-- Timing of a random one-shot over a bed: gap range and the bed level it needs. Default = the night owl.
export type OneshotSpec = { min: number, max: number, minLevel: number }

local function nightSpec(cfg: any): OneshotSpec
	return {
		min = cfg.NIGHT_ONESHOT_MIN_SECONDS,
		max = cfg.NIGHT_ONESHOT_MAX_SECONDS,
		minLevel = cfg.NIGHT_ONESHOT_MIN_LEVEL,
	}
end

-- Seconds until the next one-shot: uniform in spec.min..max.
function AudioLogic.oneshotGap(cfg: any, rng: () -> number, spec: OneshotSpec?): number
	local s = spec or nightSpec(cfg)
	return s.min + (s.max - s.min) * math.clamp(rng(), 0, 1)
end

-- One frame of the night one-shot countdown. Below NIGHT_ONESHOT_MIN_LEVEL (day, or the dusk / dawn fade) the
-- timer is cleared; the first full-night frame starts a fresh gap. Returns the new timer and whether to play now.
function AudioLogic.oneshotStep(
	timer: number?,
	dt: number,
	level: number,
	cfg: any,
	rng: () -> number,
	spec: OneshotSpec?
): (number?, boolean)
	local s = spec or nightSpec(cfg)
	if level < s.minLevel then
		return nil, false
	end
	if timer == nil then
		return AudioLogic.oneshotGap(cfg, rng, s), false
	end
	local left = timer - math.max(dt, 0)
	if left <= 0 then
		return AudioLogic.oneshotGap(cfg, rng, s), true
	end
	return left, false
end

function AudioLogic.oneshotSpeed(cfg: any, rng: () -> number): number
	return 1 + (math.clamp(rng(), 0, 1) * 2 - 1) * cfg.NIGHT_ONESHOT_SPEED_JITTER
end

function AudioLogic.jitter(base: number, spread: number, rng: () -> number): number
	return base + (math.clamp(rng(), 0, 1) * 2 - 1) * spread
end

-- PlaybackSpeed for one play of `name` (a registry name like "click" or a Sounds.IDS name): the caller's speed
-- times the sound's own Sounds.SPEED, with a jitter on top for names in Sounds.VARY.
function AudioLogic.playSpeed(cfg: any, name: string, speed: number?, rng: () -> number): number
	local entry = cfg.SFX[name]
	local soundName = if type(entry) == "string" and Sounds.IDS[entry] ~= nil then entry else name
	local base = (speed or 1) * (Sounds.SPEED[soundName] or 1)
	if Sounds.VARY[soundName] then
		return base * AudioLogic.jitter(1, cfg.SFX_SPEED_JITTER, rng)
	end
	return base
end

function AudioLogic.pick<T>(list: { T }, rng: () -> number): T?
	if #list == 0 then
		return nil
	end
	return list[math.clamp(math.floor(math.clamp(rng(), 0, 1) * #list) + 1, 1, #list)]
end

export type LayerInput = {
	clockTime: number,
	boss: boolean?, -- a boss fight is on: the boss track replaces the day / night music
	weather: string?, -- Constants.WEATHER_ATTRIBUTE value; nil / "Clear" = no weather bed
}
export type Layer = { id: string, volume: number, fade: number }

-- Every looped layer that should sound now, by key, with its volume inside the Music group and its fade time.
-- Layers missing from the result fade out. An empty or malformed id leaves that layer out (silent).
function AudioLogic.layerTargets(input: LayerInput, cfg: any, dayNight: any): { [string]: Layer }
	local out: { [string]: Layer } = {}
	local night = AudioLogic.isNight(input.clockTime, dayNight)
	local track = if input.boss then "boss" elseif night then "night" else "day"
	local musicId = validId(cfg.MUSIC[track])
	if musicId then
		out["music_" .. track] = { id = musicId, volume = cfg.MUSIC_VOLUME, fade = cfg.MUSIC_FADE_SECONDS }
	end
	local weatherId = if input.weather then validId(cfg.WEATHER_BEDS[input.weather]) else nil
	local which, bedId = AudioLogic.ambientFor(input.clockTime, cfg, dayNight)
	if bedId then
		local base = if which == "night" then cfg.AMBIENT_NIGHT_VOLUME or cfg.AMBIENT_VOLUME else cfg.AMBIENT_VOLUME
		local volume = base * (if weatherId then cfg.WEATHER_DUCK else 1)
		out["bed_" .. which] = { id = bedId, volume = volume, fade = cfg.AMBIENT_FADE_SECONDS }
	end
	if weatherId and input.weather then
		out["weather_" .. input.weather] =
			{ id = weatherId, volume = cfg.WEATHER_BED_VOLUME, fade = cfg.AMBIENT_FADE_SECONDS }
	end
	return out
end

return AudioLogic
