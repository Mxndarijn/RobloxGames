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
	weight: number, -- relative fountain drop weight
	color: { number }, -- UI colour (RGB 0..255)
	carrySlow: number, -- base WalkSpeed fraction lost while carrying
	escapeTime: number, -- seconds a thief may hold it before it escapes for sure
}

export type Mutation = {
	name: string, -- permanent save id (slimes, dex keys); never rename
	displayName: string, -- what players see (RANCH_RENAME.md: Lava shows as Syrup)
	multiplier: number,
	weight: number, -- relative weight when a mutation is rolled
}

-- A pair of mutations that fuse into one combo mutation (FEATURES.MutationStacking).
export type Combo = {
	a: string, -- Config.MUTATIONS names (order does not matter)
	b: string,
	name: string, -- combo save id; never rename, never collides with a MUTATIONS name
	displayName: string,
	multiplier: number, -- total multiplier of the combo (above a * b)
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
	{
		-- Secret: ~1 in 1000 wild spawns (0.1 / (100 + 0.1)); announced to everyone.
		tier = 7,
		name = "Secret",
		income = 800,
		weight = 0.1,
		color = { 20, 240, 220 },
		carrySlow = 0.35,
		escapeTime = 15,
	},
}

local MUTATIONS: { Mutation } = {
	-- Ordered by multiplier (Merge ranks by position). `name` is the save id;
	-- `displayName` is what players see (Lava shows as Syrup).
	{ name = "Glow", displayName = "Glow", multiplier = 1.5, weight = 50 },
	{ name = "Lava", displayName = "Syrup", multiplier = 2, weight = 30 },
	{ name = "Galaxy", displayName = "Galaxy", multiplier = 3, weight = 15 },
	{ name = "Rainbow", displayName = "Rainbow", multiplier = 4, weight = 8 },
	{ name = "Gold", displayName = "Gold", multiplier = 5, weight = 5 },
	{ name = "Crystal", displayName = "Crystal", multiplier = 7, weight = 2 },
	{ name = "Eclipse", displayName = "Eclipse", multiplier = 10, weight = 0.5 },
}

-- Combo mutations (FEATURES.MutationStacking): when a slime holds both `a` and `b` they fuse into
-- `name`, worth `multiplier` instead of a * b. Dex keys use the combo name.
local COMBOS: { Combo } = {
	{ a = "Glow", b = "Lava", name = "Solar", displayName = "Solar", multiplier = 4 }, -- 1.5 * 2 = 3
	{ a = "Lava", b = "Galaxy", name = "Nebula", displayName = "Nebula", multiplier = 8 }, -- 2 * 3 = 6
	{ a = "Galaxy", b = "Rainbow", name = "Aurora", displayName = "Aurora", multiplier = 15 }, -- 3 * 4 = 12
	{ a = "Gold", b = "Crystal", name = "Royal", displayName = "Royal", multiplier = 45 }, -- 5 * 7 = 35
}

-- Rebirth N (the Nth rebirth, i.e. done at N-1 rebirths) also needs the player
-- to own one slime of this SlimeRoster species (data.slimes, i.e. on a pad).
-- Not consumed: the normal rebirth wipe applies, so keep it as the keeper if
-- the next level needs it again. Rarity escalates; a level without an entry
-- uses the last entry below it (Progression.requiredSpecies).
local REBIRTH_SLIMES: { [number]: string } = {
	[1] = "sprout", -- Uncommon
	[2] = "carrot",
	[3] = "bunny_puff", -- Rare
	[4] = "piglet",
	[5] = "billy_gum", -- Epic
	[6] = "rodeo_ram",
	[7] = "honey_queen", -- Legendary
	[8] = "harvest_king",
	[9] = "rock_candy", -- Mythic
	[10] = "gumdrop_titan",
	[15] = "moonmilk", -- Secret
	[20] = "golden_goose_goo",
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
for _, combo in COMBOS do
	table.freeze(combo)
end

local Config = {
	RARITIES = table.freeze(RARITIES),
	MUTATIONS = table.freeze(MUTATIONS),
	COMBOS = table.freeze(COMBOS),
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
	REBIRTH_SLIMES = table.freeze(REBIRTH_SLIMES), -- required species per rebirth level
	REBIRTH_TIERS = table.freeze(REBIRTH_TIERS), -- ranks (CONTRACT.md §8.8)

	-- Permanent upgrades (Request("BuyUpgrade", id)), goals and SlimeDex rewards (CONTRACT.md §8.8)
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
	-- B1: seconds a ProximityPrompt / UI button must be held for any important
	-- action (steal, buy, lock, pad, merge, claim, sell, rebirth). Free Grab, Open Shop, Talk stay instant.
	HOLD_CONFIRM_SECONDS = 0.8,
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

	-- Stacking mutations (FEATURES.MutationStacking)
	MAX_MUTATIONS = 3, -- a slime carries at most this many mutations (a fused combo counts as one)
	STACK_MUTATION_CHANCE = 0.25, -- chance per free slot that a mutated slime rolls one more (drops, merges, Appraise)

	-- Appraise (FEATURES.Appraise): reroll one owned slime's mutation or size
	APPRAISE_COST_FRACTION = 0.3, -- of the slime's current value (Economy.sellPrice)
	APPRAISE_MUTATION_CHANCE = 0.6, -- chance a mutation reroll lands on a mutation (else None)

	-- Fountain (wild slime spawns)
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
	SECRET_TIER = 7, -- Config.RARITIES tier of the Secret slimes (SlimeRoster.SECRET_TIER)
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
		BossSlime = true, -- a big free Epic+ slime spills from the fountain every BOSS_INTERVAL
		FollowPets = true, -- your favourite (or best) slime follows you as a small pet (client-only)
		DayNight = true, -- Lighting.ClockTime cycles every DAY_LENGTH seconds
		Minimap = true, -- Visuals.MinimapData points of interest for a UI minimap
		DespawnTelegraph = true, -- wild slime models get DespawnAt before they expire; false = silent removal
		Habitats = true, -- pads turn into their slime's habitat (HABITATS.md); false = pads as before
		SlimeAnimations = false, -- slimes play the uploaded KeyframeSequences (MeshAssets.ANIMATIONS) once a probe track loads; false = procedural Motor6D motion (ui/SlimeMotor)
		CycleModifier = true, -- a server modifier (Luck Surge, Mutation Surge, ...) is rolled at each dawn and dusk of the DayNight cycle (CycleModifier); needs DayNight; false = no modifier
		SlideCollision = true, -- invisible colliders along the FULL fountain slide, top to mouth (B6: players fell through above LOW_SLIDE_Y); false = low stretch only
		Appraise = true, -- pay APPRAISE_COST_FRACTION of a slime's value to reroll its mutation or size (Appraise)
		MysteryEgg = true, -- a cash-only Mystery Egg in the Shop hatches a random slime (MysteryEgg); false = no egg, BuyEgg refused
		FriendBonus = true, -- +FRIEND_BONUS_PER_FRIEND income per friend in the same server, up to FRIEND_BONUS_CAP (FriendBonus); false = no bonus
		MutationStacking = true, -- slimes can carry several mutations and some pairs fuse into a combo (Config.COMBOS); false = rolls give at most one mutation (saves still migrate and load)
		Weather = true, -- Rain / Snow / Starfall cycle (WeatherService) and client visuals (WeatherFx); WEATHER.md
		SlimeLod = true, -- distance / graphics-quality LOD tiers for the code-driven slime motion (SLIME_LOD, ui/SlimeLod); false = every animated slime gets full motion as before
		GrowingSlimes = true, -- slimes on a pad grow over time (+GROWTH_MAX_INCOME_BONUS income at full growth, offline time counts, capped) (Growth); false = no growth, income and size unchanged
		AdminEvents = true, -- admin-only timed Luck / Mutation surge and Slime Rain, chat command + MessagingService (AdminEvents, CONTRACT.md §12); false = never triggers
		Parade = true, -- wilds hop the goo-parade lane round the plaza into the goo drain (ParadeLane); false = landing band as before
	}),

	-- Slime motion LOD (FEATURES.SlimeLod, ui/SlimeLod). Studs from the camera: full motion up to
	-- NEAR, squish only (smaller, every MID_EVERY frames) up to MID, static beyond. At a saved
	-- graphics quality level of 1..LOW_QUALITY_MAX (0 = Automatic counts as normal) the *_LOW radii apply.
	SLIME_LOD = table.freeze({
		NEAR = 30,
		MID = 60,
		NEAR_LOW = 15,
		MID_LOW = 35,
		LOW_QUALITY_MAX = 4,
		MID_EVERY = 3,
		MID_AMPLITUDE = 0.5,
		HYSTERESIS = 0.1, -- share of a radius a slime must cross back to change tier again (selection runs 4x a second)
	}),

	-- Boss Slime event (FEATURES.BossSlime)
	BOSS_FIRST_AT = 8 * 60, -- seconds after server start
	BOSS_INTERVAL = 15 * 60,
	BOSS_TIER = 4, -- Epic
	BOSS_LIFETIME = 120,

	-- Day / night (FEATURES.DayNight)
	DAY_LENGTH = 12 * 60, -- seconds per full day
	DAY_FRACTION = 0.7, -- share of the cycle that is daytime (06:30-17:30)

	-- Server modifier per day / night phase (FEATURES.CycleModifier). Weighted roll at each dawn
	-- and dusk; `luck` multiplies the rarity weight of tier >= 3 (like RAIN_LUCK), `mutation`
	-- multiplies the wild mutation chance. "None" must stay (it is the quiet phase).
	MODIFIERS = table.freeze({
		table.freeze({ name = "None", label = "None", weight = 5, luck = 1, mutation = 1 }),
		table.freeze({ name = "LuckSurge", label = "Luck Surge", weight = 3, luck = 2, mutation = 1 }),
		table.freeze({ name = "MutationSurge", label = "Mutation Surge", weight = 3, luck = 1, mutation = 3 }),
		table.freeze({ name = "GoldenHour", label = "Golden Hour", weight = 1, luck = 1.5, mutation = 2 }),
	}),

	-- Live admin events (FEATURES.AdminEvents, CONTRACT.md §12). Only these UserIds (plus the place
	-- owner when the creator is a user) may trigger one. Chat: "/event luck 10" (minutes).
	ADMIN_USER_IDS = table.freeze({} :: { number }),
	ADMIN_EVENTS = table.freeze({
		table.freeze({ id = "luck", label = "Luck Event", icon = "🍀", luck = 3, mutation = 1 }),
		table.freeze({ id = "mutation", label = "Mutation Event", icon = "🧬", luck = 1, mutation = 4 }),
		table.freeze({ id = "rain", label = "Slime Rain", icon = "🌧", luck = 1, mutation = 1 }), -- Spawner.forceRain
	}),
	ADMIN_EVENT_DEFAULT_SECONDS = 600,
	ADMIN_EVENT_MIN_SECONDS = 30,
	ADMIN_EVENT_MAX_SECONDS = 1800,
	ADMIN_EVENT_COOLDOWN = 20, -- seconds between two accepted triggers (local and received)
	ADMIN_EVENT_TOPIC = "SlimeAdminEvent",

	-- Mystery Egg (FEATURES.MysteryEgg): bought with in-game cash only, never Robux. The price is
	-- MYSTERY_EGG_PRICE x the rebirth multiplier, so selling the hatch never beats the price.
	-- `tier` is a Config.RARITIES tier, `weight` its share of the drop table (Common and Secret never drop).
	MYSTERY_EGG_PRICE = 2000,
	MYSTERY_EGG_MUTATION_CHANCE = 0.05,
	MYSTERY_EGG_REVEAL_SECONDS = 6, -- how long the hatch banner stays up
	MYSTERY_EGG_DROPS = table.freeze({
		table.freeze({ tier = 2, weight = 50 }),
		table.freeze({ tier = 3, weight = 30 }),
		table.freeze({ tier = 4, weight = 14 }),
		table.freeze({ tier = 5, weight = 5 }),
		table.freeze({ tier = 6, weight = 1 }),
	}),
	-- Weather (FEATURES.Weather, WEATHER.md). Clear plus three visual types, cycled by the server.
	-- `mutation` (a Config.MUTATIONS name) and `chanceBonus` (added to the mutation roll chance) are the
	-- hook for #8 and stay nil / 0 here: this change adds no mutation ids and touches no mutation rolls.
	WEATHER_ORDER = table.freeze({ "Clear", "Rain", "Snow", "Starfall" }),
	WEATHER = table.freeze({
		Clear = table.freeze({
			displayName = "Clear",
			mutation = nil,
			chanceBonus = 0,
			weight = 4,
			minSeconds = 240,
			maxSeconds = 420,
		}),
		Rain = table.freeze({
			displayName = "Rain",
			mutation = nil,
			chanceBonus = 0,
			weight = 3,
			minSeconds = 120,
			maxSeconds = 210,
		}),
		Snow = table.freeze({
			displayName = "Snow",
			mutation = nil,
			chanceBonus = 0,
			weight = 3,
			minSeconds = 120,
			maxSeconds = 210,
		}),
		Starfall = table.freeze({
			displayName = "Starfall",
			mutation = nil,
			chanceBonus = 0,
			weight = 1,
			minSeconds = 90,
			maxSeconds = 150,
		}),
	}),
	WEATHER_FIRST_AT = 60, -- seconds after server start before the first change away from Clear
	WEATHER_FADE_SECONDS = 2, -- client tween in / out
	WEATHER_PARTICLE_CAP = 160, -- hard cap on weather particles alive at once, whatever the quality level

	-- Slime growth (FEATURES.GrowingSlimes): a slime's `growth` (0..1) rises by dt / GROWTH_SECONDS while it
	-- sits on a pad. Offline time counts too, up to GROWTH_OFFLINE_CAP_SECONDS. At growth 1 a slime earns
	-- (and sells for) 1 + GROWTH_MAX_INCOME_BONUS times its base income and is drawn GROWTH_MAX_SCALE_BONUS bigger.
	GROWTH_SECONDS = 12 * 60 * 60,
	GROWTH_OFFLINE_CAP_SECONDS = 8 * 60 * 60,
	GROWTH_MAX_INCOME_BONUS = 0.5,
	GROWTH_MAX_SCALE_BONUS = 0.1,

	-- Daily reward
	DAILY_BASE = 100,
	DAILY_STREAK_CAP = 7,

	-- Redeem codes (CONTRACT.md §10). Keys are UPPERCASE; players type any case.
	-- reward: { kind = "cash", amount } or { kind = "boost", mult, minutes };
	-- expiresAt = unix seconds (nil = never). Once per player, kept in the save.
	CODES = table.freeze({
		WELCOME = table.freeze({ reward = table.freeze({ kind = "cash", amount = 1000 }) }),
		SLIMEBOOST = table.freeze({ reward = table.freeze({ kind = "boost", mult = 2, minutes = 10 }) }),
		LAUNCH = table.freeze({
			reward = table.freeze({ kind = "cash", amount = 5000 }),
			expiresAt = 1830297600, -- 2028-01-01 00:00:00 UTC
		}),
	}),
	CODE_MAX_LENGTH = 24,
	CODE_BOOST_MAX_MULT = 10,

	-- Roblox badges (server/Badges, v29-BADGES-NEEDED.md). `badgeId` is the Roblox badge id to paste once the
	-- badge exists on the experience; nil = placeholder, the milestone is skipped (no BadgeService call).
	-- `trigger` + `value` are read by Badges.reached.
	BADGES = table.freeze({
		table.freeze({ key = "FirstSlime", name = "First Slime", trigger = "caught", value = 1, badgeId = nil }),
		table.freeze({ key = "FirstSteal", name = "Sticky Fingers", trigger = "stolen", value = 1, badgeId = nil }),
		table.freeze({ key = "FirstRebirth", name = "Reborn", trigger = "rebirths", value = 1, badgeId = nil }),
		table.freeze({ key = "Rebirth5", name = "Born Again x5", trigger = "rebirths", value = 5, badgeId = nil }),
		table.freeze({ key = "Dex25", name = "Dex Explorer", trigger = "dexPercent", value = 25, badgeId = nil }),
		table.freeze({ key = "Dex50", name = "Dex Collector", trigger = "dexPercent", value = 50, badgeId = nil }),
		table.freeze({ key = "Dex100", name = "Dex Master", trigger = "dexPercent", value = 100, badgeId = nil }),
		table.freeze({ key = "FirstLegendary", name = "Legend Spotted", trigger = "tier", value = 5, badgeId = nil }),
		table.freeze({ key = "FirstSecret", name = "Secret Keeper", trigger = "tier", value = 7, badgeId = nil }),
		table.freeze({
			key = "Millionaire",
			name = "Slime Millionaire",
			trigger = "earned",
			value = 1000000,
			badgeId = nil,
		}),
	}),
	BADGE_RETRIES = 4, -- BadgeService attempts per badge (backoff 2, 4, 8 s)

	-- Friend income bonus (FEATURES.FriendBonus, CONTRACT.md §11)
	FRIEND_BONUS_PER_FRIEND = 0.1, -- +10% income per friend in the same server
	FRIEND_BONUS_CAP = 0.3, -- at most +30%
	FRIEND_CACHE_SECONDS = 600, -- a Player:IsFriendsWith answer is reused this long
	FRIEND_RETRY_SECONDS = 30, -- after a failed check, don't ask again for this long

	-- Persistence
	SAVE_VERSION = 4, -- CONTRACT.md §8.9 (v4: slime.mutations list, SaveData.migrateV3)
	AUTOSAVE_INTERVAL = 60,
	SESSION_STALE_SECONDS = 180, -- a session lock older than this may be taken over
	MAX_SLIMES_SAVED = 64,
}

return table.freeze(Config)
