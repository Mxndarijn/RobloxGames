--!strict
--[[
	PlayerSettings

	The Settings menu values (CONTRACT.md §8.9c): every setting, its default and its allowed values, on top of
	the shared SettingsSchema. Saved as `settings` in the save; the server cleans saved and sent values with
	`clean` / `parse`, the client builds the Settings card from `TABS` and mirrors each value onto a LocalPlayer
	attribute (`attribute`) that the systems it controls read. Pure: no Roblox APIs.

	The three audio ids keep the names the save has used since v6, so old saves load unchanged. A save
	without a newer id gets its default.
]]

local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local SettingsSchema = if Lib
	then require(Lib.settings.SettingsSchema)
	else require("../../../../shared/luau/src/settings/SettingsSchema")
local Config = if script then require(script.Parent.Config) else require("./Config")

export type Values = SettingsSchema.Values
export type Settings = Values

export type Entry = {
	id: string,
	icon: string,
	name: string,
	hint: string?, -- one line under the name
	labels: { string }?, -- choice settings: the button text of each choice, in order
	attribute: string, -- LocalPlayer attribute the client mirrors the value onto
}

export type Tab = { key: string, icon: string, label: string, entries: { Entry } }

local PlayerSettings = {}

-- Ids (never rename one: they are save keys).
PlayerSettings.IDS = table.freeze({
	muted = "muted",
	musicVolume = "musicVolume",
	sfxVolume = "sfxVolume",
	stealAlarm = "stealAlarm",
	buttonClicks = "buttonClicks",
	holdToSell = "holdToSell",
	tutorialHints = "tutorialHints",
	dailyPopup = "dailyPopup",
	reducedMotion = "reducedMotion",
	effects = "effects",
	cameraShake = "cameraShake",
	othersEffects = "othersEffects",
	showOnBoards = "showOnBoards",
	numberStyle = "numberStyle",
})

PlayerSettings.schema = SettingsSchema.new({
	{ id = "muted", kind = "toggle", default = false },
	{ id = "musicVolume", kind = "slider", default = Config.AUDIO.DEFAULT_MUSIC_VOLUME, min = 0, max = 1, step = 0.01 },
	{ id = "sfxVolume", kind = "slider", default = Config.AUDIO.DEFAULT_SFX_VOLUME, min = 0, max = 1, step = 0.01 },
	{ id = "stealAlarm", kind = "toggle", default = true },
	{ id = "buttonClicks", kind = "toggle", default = true },
	{ id = "holdToSell", kind = "toggle", default = true },
	{ id = "tutorialHints", kind = "toggle", default = true },
	{ id = "dailyPopup", kind = "toggle", default = true },
	{ id = "reducedMotion", kind = "toggle", default = false },
	{ id = "effects", kind = "choice", default = "full", choices = { "low", "full" } },
	{ id = "cameraShake", kind = "toggle", default = true },
	{ id = "othersEffects", kind = "toggle", default = true },
	{ id = "showOnBoards", kind = "toggle", default = true },
	{ id = "numberStyle", kind = "choice", default = "short", choices = { "short", "full" } },
})

-- The Settings card: tabs in order, rows in order. The Sound rows are read by the Sound tab's own
-- controls (mute toggle and two sliders); every other row is a toggle or a choice switch.
PlayerSettings.TABS = table.freeze({
	table.freeze({
		key = "sound",
		icon = "🔊",
		label = "Sound",
		entries = table.freeze({
			{
				id = "muted",
				icon = "🔇",
				name = "Mute all",
				hint = "Turns every sound off",
				attribute = "AudioMuted",
			} :: Entry,
			{ id = "musicVolume", icon = "🎵", name = "Music", attribute = "AudioMusicVolume" },
			{ id = "sfxVolume", icon = "🔔", name = "Effects", attribute = "AudioSfxVolume" },
			{
				id = "stealAlarm",
				icon = "🚨",
				name = "Steal alarm",
				hint = "The siren when a slime is stolen",
				attribute = "SettingStealAlarm",
			},
			{
				id = "buttonClicks",
				icon = "👆",
				name = "Button clicks",
				hint = "The pop when you press a button",
				attribute = "SettingButtonClicks",
			},
		}),
	}),
	table.freeze({
		key = "game",
		icon = "🎮",
		label = "Game",
		entries = table.freeze({
			{
				id = "holdToSell",
				icon = "🤚",
				name = "Hold to sell",
				hint = "So you never sell by accident",
				attribute = "SettingHoldToSell",
			} :: Entry,
			{
				id = "tutorialHints",
				icon = "💡",
				name = "Tutorial hints",
				hint = "The arrow and the next-step card",
				attribute = "SettingTutorialHints",
			},
			{
				id = "dailyPopup",
				icon = "📅",
				name = "Daily reward popup",
				hint = "Show it when you join",
				attribute = "SettingDailyPopup",
			},
		}),
	}),
	table.freeze({
		key = "visuals",
		icon = "✨",
		label = "Visuals",
		entries = table.freeze({
			{
				id = "reducedMotion",
				icon = "🐢",
				name = "Reduced motion",
				hint = "No bounces, puffs or tweens",
				attribute = Config.HABITAT_ANIM.REDUCED_ATTRIBUTE,
			} :: Entry,
			{
				id = "effects",
				icon = "💧",
				name = "Goo effects",
				hint = "Sparkles, splashes and puffs",
				labels = { "Low", "Full" },
				attribute = "SettingEffects",
			},
			{
				id = "cameraShake",
				icon = "📳",
				name = "Camera shake",
				hint = "When you get hit or a Secret lands",
				attribute = "SettingCameraShake",
			},
			{
				id = "othersEffects",
				icon = "👥",
				name = "Other players' effects",
				hint = "Their carry trails and hit effects",
				attribute = "SettingOthersEffects",
			},
		}),
	}),
	table.freeze({
		key = "me",
		icon = "👤",
		label = "Me",
		entries = table.freeze({
			{
				id = "showOnBoards",
				icon = "🙈",
				name = "Show me on leaderboards",
				hint = "Off: you show as a hidden player",
				attribute = "SettingShowOnBoards",
			} :: Entry,
			{
				id = "numberStyle",
				icon = "🔢",
				name = "Number style",
				hint = "$1.2M or $1,234,567",
				labels = { "Short", "Full" },
				attribute = "SettingNumberStyle",
			},
		}),
	}),
})

-- The name the leaderboards show for a player who turned "Show me on leaderboards" off.
PlayerSettings.HIDDEN_NAME = "Hidden player"

local entryById: { [string]: Entry } = {}
for _, tab in PlayerSettings.TABS do
	for _, entry in tab.entries do
		entryById[entry.id] = entry
	end
end

function PlayerSettings.defaults(): Values
	return PlayerSettings.schema:defaults()
end

-- Untrusted saved / snapshot table -> every setting; each bad or missing value at its default.
function PlayerSettings.clean(raw: any): Values
	return PlayerSettings.schema:clean(raw)
end

-- Untrusted changes from a client -> the valid ones, or nil when anything in it is bad.
function PlayerSettings.parse(raw: any): Values?
	return PlayerSettings.schema:parse(raw)
end

-- `current` with `changes` over it, plus the ids that changed.
function PlayerSettings.apply(current: Values, changes: Values): (Values, { string })
	return PlayerSettings.schema:apply(current, changes)
end

-- The card row of a setting (icon, name, attribute), or nil for an unknown id.
function PlayerSettings.entry(id: string): Entry?
	return entryById[id]
end

-- The local player's value of a setting on the client: the attribute the Settings card mirrors it onto, or the
-- default while it is unset (before the first State) or junk. `player` is anything with GetAttribute.
function PlayerSettings.get(player: any, id: string): SettingsSchema.Value
	local entry = entryById[id]
	local def = PlayerSettings.schema.byId[id]
	if entry == nil or def == nil then
		error(`PlayerSettings.get: unknown setting {id}`, 2)
	end
	local raw = if player then player:GetAttribute(entry.attribute) else nil
	return PlayerSettings.schema:value(id, raw) :: SettingsSchema.Value
end

-- True when the local player turned the setting on (toggle settings only).
function PlayerSettings.on(player: any, id: string): boolean
	return PlayerSettings.get(player, id) == true
end

-- The name a leaderboard shows for a player with these settings.
function PlayerSettings.boardName(settings: any, name: string): string
	return if PlayerSettings.clean(settings).showOnBoards then name else PlayerSettings.HIDDEN_NAME
end

return PlayerSettings
