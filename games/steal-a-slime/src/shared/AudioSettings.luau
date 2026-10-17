--!strict
--[[
	AudioSettings

	The saved Sound card values (FEATURES.Audio, CONTRACT.md §2 Extras / §8.9c): music and SFX
	volume (0..1, 5 % steps) and a mute flag. Stored as `settings` in the save from v6 on; the
	field is read, migrated and written whether or not the flag is on. Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

export type Settings = { musicVolume: number, sfxVolume: number, muted: boolean }

local AudioSettings = {}

function AudioSettings.defaults(): Settings
	return {
		musicVolume = Config.AUDIO.DEFAULT_MUSIC_VOLUME,
		sfxVolume = Config.AUDIO.DEFAULT_SFX_VOLUME,
		muted = false,
	}
end

-- A volume rounded to 0.01 and clamped to 0..1; anything that is not a finite number -> default.
function AudioSettings.volume(value: any, default: number): number
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return default
	end
	return math.floor(math.clamp(value, 0, 1) * 100 + 0.5) / 100
end

-- Untrusted saved / sent value -> clean settings; each bad or missing field falls back to its default.
function AudioSettings.clean(raw: any): Settings
	local out = AudioSettings.defaults()
	if type(raw) ~= "table" then
		return out
	end
	out.musicVolume = AudioSettings.volume(raw.musicVolume, out.musicVolume)
	out.sfxVolume = AudioSettings.volume(raw.sfxVolume, out.sfxVolume)
	out.muted = raw.muted == true
	return out
end

return AudioSettings
