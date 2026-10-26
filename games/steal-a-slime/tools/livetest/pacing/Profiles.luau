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
	eggs: boolean?, -- takes Mystery Eggs for what they are expected to hatch into (default: no, as eggs show no income)
	consumables: number?, -- buys and drinks a Luck Potion when its price x this is under their cash; nil = never
	flip: string?, -- "full": once the pads are full, buys wild slimes to sell at once instead of upgrading; "always": every trip
	rebirth: boolean?, -- false = never rebirths
	afk: number?, -- chance that a trip is followed by an AFK stretch (still online, so still a target)
	afkSeconds: number?, -- length of one AFK stretch
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
		name = "average",
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

-- Skill of the original three is the same as before; the profile names below add the cases of a real server.
-- casual15: a casual player who plays exactly one 15 minute session every single day.
table.insert(Profiles.LIST, {
	name = "casual15",
	playChance = 1,
	sessions = { 1, 1 },
	minutes = { 15, 15 },
	walk = 30,
	think = 8,
	mistake = 0.4,
	smart = false,
	steal = 0.04,
	defend = 0.25,
	lock = 0.3,
	padRatio = 2,
	upgradeRatio = 3,
})
-- thief: regular skill, steals whenever a target is open and worth more than a wild slime, hardly defends.
table.insert(Profiles.LIST, {
	name = "thief",
	playChance = 0.8,
	sessions = { 1, 2 },
	minutes = { 30, 75 },
	walk = 22,
	think = 3,
	mistake = 0.15,
	smart = true,
	steal = 1,
	defend = 0.1,
	lock = 0.3,
	padRatio = 3,
	upgradeRatio = 5,
})
-- victim: long sessions, half of it AFK on the plot, never locks, hardly defends: the easiest plot on the server.
table.insert(Profiles.LIST, {
	name = "victim",
	playChance = 0.7,
	sessions = { 1, 2 },
	minutes = { 60, 150 },
	walk = 30,
	think = 8,
	mistake = 0.3,
	smart = false,
	steal = 0,
	defend = 0.05,
	lock = 0,
	padRatio = 2,
	upgradeRatio = 3,
	afk = 0.6,
	afkSeconds = 300,
})

-- flipper / flipall: average skill, buy the best-profit wild slime and sell it at once (Spawner.price vs Economy.sellPrice).
for _, row in { { "flipper", "full" }, { "flipall", "always" } } do
	local copy = table.clone(Profiles.LIST[2])
	copy.name = row[1]
	copy.flip = row[2]
	table.insert(Profiles.LIST, copy)
end

-- flipprobe: one 60 minute session that only flips and buys nothing (use with --start-level), to measure a flip rate at a level.
do
	local copy = table.clone(Profiles.LIST[2])
	copy.name = "flipprobe"
	copy.flip = "always"
	copy.playChance = 1
	copy.sessions = { 1, 1 }
	copy.minutes = { 60, 60 }
	copy.steal = 0
	copy.lock = 0
	copy.rebirth = false
	copy.padRatio = 1e18
	copy.upgradeRatio = 1e18
	table.insert(Profiles.LIST, copy)
end

-- Default population of one server: half casual, a third regular, the rest grinders.
Profiles.DEFAULT_MIX = { casual = 8, average = 5, grinder = 3 }

function Profiles.get(name: string): Profile?
	if name == "regular" then
		name = "average" -- the old name
	end
	for _, p in Profiles.LIST do
		if p.name == name then
			return p
		end
	end
	return nil
end

-- Copy of `name` under another name (late joiners keep their skill).
function Profiles.variant(name: string, label: string): Profile?
	local base = Profiles.get(name)
	if not base then
		return nil
	end
	local copy = table.clone(base)
	copy.name = label
	return copy
end

function Profiles.names(): { string }
	local out = {}
	for _, p in Profiles.LIST do
		table.insert(out, p.name)
	end
	return out
end

return Profiles
