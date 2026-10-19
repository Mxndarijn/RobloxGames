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

return AudioLogic
