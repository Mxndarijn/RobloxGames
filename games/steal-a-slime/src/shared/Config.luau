--!strict
--[[
	Config

	Every tunable for Steal a Slime in one frozen table. Pure data: no Roblox
	APIs, so it loads unchanged on the server, the client and under Lune.
]]

export type Rarity = {
	tier: number,
	name: string,
	income: number, -- cash/sec for a size-1.0, unmutated slime at 0 rebirths
	weight: number, -- relative volcano drop weight
	color: { number }, -- UI colour (RGB 0..255)
	carrySlow: number, -- base WalkSpeed fraction lost while carrying
	escapeTime: number, -- seconds a thief may hold it before it escapes for sure
}

export type Mutation = {
	name: string,
	multiplier: number,
	weight: number, -- relative weight when a mutation is rolled
}

-- v13 progression (CONTRACT.md §8.8)
export type RebirthTier = {
	rebirths: number, -- reached at this many rebirths
	title: string,
	unlock: string?, -- upgrade id this rank unlocks (also Config.UPGRADES[i].requires)
	keep: number?, -- slimes kept on rebirth
	income: number?, -- income bonus (0.25 = +25 %)
	lock: number?, -- extra seconds per bought lock
}

export type Upgrade = {
	id: string, -- BuyUpgrade argument, State.upgrades[i].id
	name: string,
	text: string, -- what one level does
	maxLevel: number,
	base: number, -- price of level 1
	growth: number, -- price of level n+1 = base * growth^n
	requires: number, -- rebirths needed
	step: number, -- effect per level (meaning depends on id)
}

export type Goal = {
	id: string,
	title: string, -- "<n>" = the formatted target, "<s>" = "s" unless the target is 1
	stat: string, -- Goals.stat name
	targets: { number },
	rewards: { number }, -- base cash, x rebirthMultiplier when paid
	cash: boolean?, -- format targets as $
}

export type DexMilestone = { count: number, reward: number, bonus: number }

local RARITIES: { Rarity } = {
	{
		tier = 1,
		name = "Common",
		income = 1,
		weight = 52,
		color = { 170, 220, 170 },
		carrySlow = 0.05,
		escapeTime = 25,
	},
	{
		tier = 2,
		name = "Uncommon",
		income = 3,
		weight = 28,
		color = { 90, 200, 255 },
		carrySlow = 0.1,
		escapeTime = 23,
	},
	{
		tier = 3,
		name = "Rare",
		income = 9,
		weight = 13,
		color = { 60, 110, 255 },
		carrySlow = 0.15,
		escapeTime = 21,
	},
	{
		tier = 4,
		name = "Epic",
		income = 27,
		weight = 5.2,
		color = { 180, 80, 255 },
		carrySlow = 0.2,
		escapeTime = 19,
	},
	{
		tier = 5,
		name = "Legendary",
		income = 80,
		weight = 1.45,
		color = { 255, 190, 40 },
		carrySlow = 0.25,
		escapeTime = 17,
	},
	{
		tier = 6,
		name = "Mythic",
		income = 250,
		weight = 0.35,
		color = { 255, 60, 90 },
		carrySlow = 0.3,
		escapeTime = 15,
	},
}

local MUTATIONS: { Mutation } = {
	{ name = "Glow", multiplier = 1.5, weight = 50 },
	{ name = "Lava", multiplier = 2, weight = 30 },
	{ name = "Galaxy", multiplier = 3, weight = 15 },
	{ name = "Gold", multiplier = 5, weight = 5 },
}

local REBIRTH_TIERS: { RebirthTier } = {
	{ rebirths = 0, title = "Slime Rookie" },
	{ rebirths = 1, title = "Goo Getter", unlock = "CarrySpeed" },
	{ rebirths = 3, title = "Slime Wrangler", unlock = "OfflineCap" },
	{ rebirths = 5, title = "Blob Baron", unlock = "Luck" },
	{ rebirths = 6, title = "Goo Tycoon", keep = 2 },
	{ rebirths = 7, title = "Jelly Magnate", income = 0.1 },
	{ rebirths = 8, title = "Ooze Overlord", lock = 30 },
	{ rebirths = 10, title = "Slime Sovereign", keep = 3, income = 0.25 },
	{ rebirths = 12, title = "Gel Emperor", lock = 60 },
	{ rebirths = 15, title = "Gelatinous Legend", keep = 4, income = 0.5 },
	{ rebirths = 20, title = "Mythic Monarch", income = 1 },
	{ rebirths = 30, title = "Slime Deity", keep = 5, income = 2 },
}

local UPGRADES: { Upgrade } = {
	{
		id = "Income",
		name = "Slime Snacks",
		text = "+10% income",
		maxLevel = 10,
		base = 2000,
		growth = 2.5,
		requires = 0,
		step = 0.1,
	},
	{
		id = "CarrySpeed",
		name = "Strong Arms",
		text = "-15% carry slowdown",
		maxLevel = 4,
		base = 5000,
		growth = 3,
		requires = 1,
		step = 0.15,
	},
	{
		id = "OfflineCap",
		name = "Night Shift",
		text = "+1h offline income cap",
		maxLevel = 4,
		base = 20000,
		growth = 3,
		requires = 3,
		step = 3600,
	},
	{
		id = "Luck",
		name = "Lucky Charm",
		text = "+4% chance a slime you bring home is one rarity higher",
		maxLevel = 5,
		base = 100000,
		growth = 3,
		requires = 5,
		step = 0.04,
	},
}

local GOALS: { Goal } = {
	{
		id = "Catch",
		title = "Catch <n> slime<s>",
		stat = "caught",
		targets = { 1, 10, 50, 200, 1000 },
		rewards = { 50, 500, 5000, 50000, 500000 },
	},
	{
		id = "Merge",
		title = "Merge <n> time<s>",
		stat = "merges",
		targets = { 1, 10, 50, 250 },
		rewards = { 200, 2000, 25000, 250000 },
	},
	{
		id = "Steal",
		title = "Steal <n> slime<s>",
		stat = "stolen",
		targets = { 1, 10, 50, 200 },
		rewards = { 300, 3000, 30000, 300000 },
	},
	{
		id = "Lock",
		title = "Lock your base <n> time<s>",
		stat = "locks",
		targets = { 1, 25, 100 },
		rewards = { 100, 2500, 25000 },
	},
	{
		id = "Pads",
		title = "Unlock <n> pad<s>",
		stat = "pads",
		targets = { 5, 6, 7, 8 },
		rewards = { 200, 1000, 5000, 20000 },
	},
	{
		id = "Earn",
		title = "Earn <n> in total",
		stat = "earned",
		targets = { 1e4, 1e6, 1e8, 1e10 },
		rewards = { 1000, 50000, 2e6, 1e8 },
		cash = true,
	},
	{
		id = "Rebirth",
		title = "Rebirth <n> time<s>",
		stat = "rebirths",
		targets = { 1, 3, 6, 10, 20 },
		rewards = { 2000, 20000, 500000, 5e6, 1e8 },
	},
}

local DEX_MILESTONES: { DexMilestone } = {
	{ count = 10, reward = 500, bonus = 0.02 },
	{ count = 25, reward = 2500, bonus = 0.03 },
	{ count = 50, reward = 10000, bonus = 0.05 },
	{ count = 100, reward = 50000, bonus = 0.05 },
	{ count = 200, reward = 250000, bonus = 0.1 },
	{ count = 400, reward = 1.5e6, bonus = 0.15 },
	{ count = 720, reward = 1e7, bonus = 0.25 },
}

for _, list in { REBIRTH_TIERS, UPGRADES, DEX_MILESTONES } :: { { any } } do
	for _, entry in list do
		table.freeze(entry)
	end
end
for _, goal in GOALS do
	table.freeze(goal.targets)
	table.freeze(goal.rewards)
	table.freeze(goal)
end

for _, rarity in RARITIES do
	table.freeze(rarity.color)
	table.freeze(rarity)
end
for _, mutation in MUTATIONS do
	table.freeze(mutation)
end

local Config = {
	RARITIES = table.freeze(RARITIES),
	MUTATIONS = table.freeze(MUTATIONS),
	MAX_TIER = #RARITIES,

	PATTERNS = table.freeze({ "Plain", "Spots", "Stripes", "Belly" }),
	EYES = table.freeze({ "Round", "Sleepy", "Angry", "Happy", "Cyclops", "Wide" }),
	MOUTHS = table.freeze({ "Smile", "Open", "Flat", "Fang" }),

	MIN_SIZE = 0.8,
	MAX_SIZE = 2.0,

	-- World
	PLOT_COUNT = 8, -- one plot per player; server MaxPlayers = 8
	SLIME_BASE_DIAMETER = 3, -- studs at size 1.0 (ModelFactory)
	SLIME_MESH_ASSET_ID = 103340234939607, -- Jolt's slime package; server SlimeMesh, procedural fallback
	STATE_MIN_INTERVAL = 0.25, -- State snapshots are coalesced to at most 4/s per player
	LEADERBOARD_INTERVAL = 60,
	LEADERBOARD_SIZE = 10,

	-- Economy
	STARTING_CASH = 25,
	PADS_START = 4,
	PADS_MAX = 8, -- design MVP: 8 pads per plot
	PAD_BASE_COST = 100,
	PAD_COST_GROWTH = 2.5,
	SELL_SECONDS = 30, -- a slime sells for this many seconds of its income
	OFFLINE_RATE = 0.5, -- fraction of income earned while offline
	OFFLINE_CAP_SECONDS = 2 * 60 * 60, -- offline income stops accruing after 2 h

	-- Rebirth
	REBIRTH_BASE_COST = 5000,
	REBIRTH_COST_GROWTH = 3,
	REBIRTH_MULTIPLIER_STEP = 0.5, -- +50 % income per rebirth
	MAX_REBIRTHS = 50,
	REBIRTH_LATE_FROM = 5, -- from this many rebirths on, the cost grows by REBIRTH_COST_GROWTH_LATE
	REBIRTH_COST_GROWTH_LATE = 2,
	REBIRTH_TIERS = table.freeze(REBIRTH_TIERS), -- ranks (CONTRACT.md §8.8)

	-- Permanent upgrades (Request("BuyUpgrade", id)), goals and Slimedex rewards (CONTRACT.md §8.8)
	UPGRADES = table.freeze(UPGRADES),
	GOALS = table.freeze(GOALS),
	DEX_MILESTONES = table.freeze(DEX_MILESTONES),

	-- Lock / steal
	JOIN_LOCK_SECONDS = 45,
	LOCK_SECONDS = 60,
	LOCK_SECONDS_PER_REBIRTH = 10,
	LOCK_MAX_REMAINING = 300, -- extending can never push the lock past 5 min
	LOCK_BASE_COST = 25,
	LOCK_INCOME_SECONDS = 15, -- lock costs this many seconds of plot income (or base cost)
	STEAL_REACH = 14, -- studs: max server-checked distance to grab a slime
	SLAP_REACH = 10,
	SLAP_COOLDOWN = 1.5,
	WRIGGLE_MAX_CHANCE = 0.12, -- per-second escape chance as the escape timer runs out
	STOLEN_EXTRA_SLOW = 0.25, -- extra slowdown, ramps up the longer a stolen slime is held
	MAX_CARRY_SLOW = 0.6,
	BASE_WALK_SPEED = 16,

	-- Shop (permanent, kept on rebirth)
	LOCK_UPGRADE_MAX = 5,
	LOCK_UPGRADE_SECONDS = 15, -- every bought lock lasts this much longer per level
	LOCK_UPGRADE_COSTS = table.freeze({ 500, 2000, 8000, 30000, 100000 }), -- price of level 1..MAX
	SPEED_COIL_PRICE = 1500,
	SPEED_COIL_WALK_SPEED = 22, -- base WalkSpeed; the carry slowdown applies to it

	-- Merge
	MERGE_MUTATION_CHANCE = 0.15,
	MERGE_SIZE_BONUS = 0.1,

	-- Volcano
	SPAWN_INTERVAL = 4,
	MAX_WILD_SLIMES = 18,
	WILD_LIFETIME = 75,
	DESPAWN_TELEGRAPH_SECONDS = 5, -- wild slimes warn this long before they expire (FEATURES.DespawnTelegraph)
	-- Despawn telegraph FX: optional one-shot sound with the poof. Off until a real asset is chosen.
	DESPAWN_POOF_SOUND = false,
	-- Despawn telegraph FX: PLACEHOLDER id. Replace with a real short pop/poof id before
	-- enabling DESPAWN_POOF_SOUND. The client never plays id 0; don't ship 0 as "the sound".
	DESPAWN_POOF_SOUND_ID = "rbxassetid://0",
	DROP_MUTATION_CHANCE = 0.03,
	-- v13 rarity curve (CONTRACT.md §8.7): pity per server, Legendary+ drops are announced
	PITY_EPIC = 30, -- after this many drops without an Epic+, the next one is at least Epic
	PITY_LEGENDARY = 300, -- same for Legendary+
	RARE_ANNOUNCE_TIER = 5, -- wild drops of this tier or higher: Notify everyone + RareSpawn attributes
	FREE_DROP_CHANCE = 0.25, -- share of wild slimes that cost nothing to grab
	WILD_PRICE_SECONDS = 20, -- other wild slimes cost this many seconds of their income

	-- Slime Rain event
	RAIN_INTERVAL = 60 * 60, -- design: hourly
	RAIN_FIRST_AT = 5 * 60,
	RAIN_DURATION = 3 * 60, -- design: 3 minutes
	RAIN_SPAWN_INTERVAL = 0.75,
	RAIN_MUTATION_CHANCE = 0.35,
	RAIN_LUCK = 3, -- rarity weights for tier >= 3 multiplied by this during rain
	RAIN_WARNING_SECONDS = 60, -- everyone gets a heads-up toast this long before a rain

	-- Extras, each behind a flag (CONTRACT.md §2 Extras). false = fully off.
	FEATURES = table.freeze({
		BossSlime = true, -- a big free Epic+ slime erupts every BOSS_INTERVAL
		FollowPets = true, -- your favourite (or best) slime follows you as a small pet (client-only)
		DayNight = true, -- Lighting.ClockTime cycles every DAY_LENGTH seconds
		Minimap = true, -- Visuals.MinimapData points of interest for a UI minimap
		DespawnTelegraph = true, -- wild slime models get DespawnAt before they expire; false = silent removal
	}),

	-- Boss Slime event (FEATURES.BossSlime)
	BOSS_FIRST_AT = 8 * 60, -- seconds after server start
	BOSS_INTERVAL = 15 * 60,
	BOSS_TIER = 4, -- Epic
	BOSS_LIFETIME = 120,

	-- Day / night (FEATURES.DayNight)
	DAY_LENGTH = 12 * 60, -- seconds per full day
	DAY_FRACTION = 0.7, -- share of the cycle that is daytime (06:30-17:30)

	-- Daily reward
	DAILY_BASE = 100,
	DAILY_STREAK_CAP = 7,

	-- Persistence
	SAVE_VERSION = 3, -- CONTRACT.md §8.9
	AUTOSAVE_INTERVAL = 60,
	SESSION_STALE_SECONDS = 180, -- a session lock older than this may be taken over
	MAX_SLIMES_SAVED = 64,
}

return table.freeze(Config)
