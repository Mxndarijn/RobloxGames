--!strict
--[[
	Player profiles for the pacing sim: how often and how long a kind of
	player plays, how fast and how well they play, and how much they steal,
	defend and lock. Guesses, not measurements: tune them when analytics
	give real session lengths and retention.
]]

export type Profile = {
	name: string,
	playChance: number, -- chance they play at all on a given day
	sessions: { number }, -- sessions on a day they play: min, max
	minutes: { number }, -- length of one session: min, max
	walk: number, -- seconds for a fountain round trip at BASE_WALK_SPEED, not carrying
	think: number, -- seconds between trips (menus, looking around)
	mistake: number, -- chance a trip takes a random affordable slime instead of the best
	smart: boolean, -- keeps and hunts the species the next rebirth needs
	steal: number, -- chance a trip is a steal attempt when a target is open
	defend: number, -- chance they slap a thief off while they are online
	lock: number, -- chance they relock whenever their lock is down
	padRatio: number, -- buys a pad when its price x this is under their cash
	upgradeRatio: number, -- same for upgrades and the Speed Coil
}

local Profiles = {} :: { LIST: { Profile }, [string]: any }

Profiles.LIST = {
	{
		name = "casual",
		playChance = 0.55,
		sessions = { 1, 2 },
		minutes = { 15, 45 },
		walk = 30,
		think = 8,
		mistake = 0.4,
		smart = false,
		steal = 0.04,
		defend = 0.25,
		lock = 0.3,
		padRatio = 2,
		upgradeRatio = 3,
	},
	{
		name = "regular",
		playChance = 0.8,
		sessions = { 1, 2 },
		minutes = { 30, 75 },
		walk = 22,
		think = 3,
		mistake = 0.15,
		smart = true,
		steal = 0.12,
		defend = 0.55,
		lock = 0.7,
		padRatio = 3,
		upgradeRatio = 5,
	},
	{
		name = "grinder",
		playChance = 0.95,
		sessions = { 2, 3 },
		minutes = { 60, 150 },
		walk = 16,
		think = 1,
		mistake = 0,
		smart = true,
		steal = 0.25,
		defend = 0.85,
		lock = 1,
		padRatio = 3,
		upgradeRatio = 5,
	},
}

-- Default population of one server: half casual, a third regular, the rest grinders.
Profiles.DEFAULT_MIX = { casual = 8, regular = 5, grinder = 3 }

function Profiles.get(name: string): Profile?
	for _, p in Profiles.LIST do
		if p.name == name then
			return p
		end
	end
	return nil
end

function Profiles.names(): { string }
	local out = {}
	for _, p in Profiles.LIST do
		table.insert(out, p.name)
	end
	return out
end

return Profiles
