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
	displayName: string, -- what players see (docs/archive/RANCH_RENAME.md: Lava shows as Syrup)
	multiplier: number,
	weight: number, -- relative weight when a mutation is rolled
}

-- A restocking consumable (FEATURES.Consumables, Config.CONSUMABLES).
export type Consumable = {
	id: string, -- BuyConsumable argument and save key; never rename
	name: string,
	icon: string,
	text: string,
	price: number, -- x the rebirth multiplier
	minStock: number, -- per-restock quantity per player is rolled in minStock..maxStock
	maxStock: number,
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
	family: string?, -- FountainTiers family id this rank opens (FEATURES.FountainTiers; FountainTiers.FAMILIES)
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
	flag: string?, -- Config.FEATURES name that must be on for the upgrade to be listed, bought or have any effect
}

export type Goal = {
	id: string,
	title: string, -- "<n>" = the formatted target, "<s>" = "s" unless the target is 1
	stat: string, -- Goals.stat name
	targets: { number },
	rewards: { number }, -- base cash, x rebirthMultiplier when paid
	cash: boolean?, -- format targets as $
}

export type DailyQuest = {
	id: string,
	stat: string, -- Goals.stat name
	title: string, -- "<n>" = the formatted target, "<s>" = "s" unless the target is 1
	icon: string, -- Config.GOALS id whose item icon the card shows
	cash: boolean?, -- format targets as $
	choices: { number }, -- possible targets
	reward: { kind: string, amount: number?, mult: number?, minutes: number? },
}

export type DexMilestone = { count: number, reward: number, bonus: number }

-- Plot skins (FEATURES.PlotSkins, CONTRACT.md §15). `set` = rarity tier whose SlimeDex set must be
-- `threshold` complete. Colours are RGB 0..255; `fence` multiplies the fence / gate mesh colours (white = none).
export type PlotSkin = {
	id: string, -- permanent save id; never rename
	name: string,
	set: number?, -- Config.RARITIES tier; nil = always unlocked
	threshold: number?,
	floor: { color: { number }, material: string }?, -- plot Base; nil = leave as built
	fence: { number }?,
	decor: string?, -- MeshAssets name that stands in for the plot's mailbox slot
}

-- A PvP tool or fun item (FEATURES.PvP, CONTRACT.md §26). Price is derived (PvpRules.price), never stored.
-- No tool has a damage / health field: PvP never lowers Humanoid health (Validate.pvpTools asserts it).
export type PvpTool = {
	id: string, -- BuyPvpItem argument and save key; never rename
	name: string,
	line: string, -- "Knockback" | "Trap" | "Blaster" | "Fun"
	tier: number, -- 1.. within its line (Fun items: 1)
	rebirths: number, -- rank gate: a Config.REBIRTH_TIERS threshold
	cooldown: number, -- seconds, >= Config.PVP.MIN_COOLDOWN
	kind: string, -- "tool" | "fun"
	cosmetic: boolean, -- never moves or slows a non-consenting player
	allowInSafeZone: boolean?, -- usable by someone standing in a safe zone (cosmetic only)
	push: number?, -- Knockback: horizontal studs
	reach: number?, -- Knockback: studs
	range: number?, -- Blaster: studs
	traps: number?, -- Trap: placed at once
	radius: number?, -- Trap: studs
	control: number?, -- hard crowd control seconds (freeze, dance, bounce), <= PVP.CONTROL_MAX_SECONDS
	slow: number?, -- Blaster: speed taken away, 0.3 = 30 %
	slowSeconds: number?, -- Blaster: <= PVP.SLOW_MAX_SECONDS
	nudge: number?, -- FunSqueaky: studs
	height: number?, -- FunBouncePad: studs straight up
	maxPlaced: number?, -- placed objects at once
	fadeSeconds: number?,
	maxDecals: number?,
	hatSeconds: number?,
}

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

-- Weather-only mutations (Config.WEATHER[id].mutation). Kept out of MUTATIONS so the plain roll pool,
-- the merge ladder and the Dex total stay exactly as they were; Genome.mutationInfo knows both lists.
-- Weight 0: never rolled plain, only through the weather bonus in Genome.rollMutation.
local WEATHER_MUTATIONS: { Mutation } = {
	{ name = "Wet", displayName = "Wet", multiplier = 1.75, weight = 0 },
	{ name = "Frozen", displayName = "Frozen", multiplier = 2.5, weight = 0 },
}

-- Combo mutations (FEATURES.MutationStacking): when a slime holds both `a` and `b` they fuse into
-- `name`, worth `multiplier` instead of a * b. Dex keys use the combo name.
local COMBOS: { Combo } = {
	{ a = "Glow", b = "Lava", name = "Solar", displayName = "Solar", multiplier = 4 }, -- 1.5 * 2 = 3
	{ a = "Lava", b = "Galaxy", name = "Nebula", displayName = "Nebula", multiplier = 8 }, -- 2 * 3 = 6
	{ a = "Galaxy", b = "Rainbow", name = "Aurora", displayName = "Aurora", multiplier = 15 }, -- 3 * 4 = 12
	{ a = "Gold", b = "Crystal", name = "Royal", displayName = "Royal", multiplier = 45 }, -- 5 * 7 = 35
}

-- Combos that use a weather-only mutation (same rules as COMBOS; kept apart so COMBOS and the Dex total do not change).
local WEATHER_COMBOS: { Combo } = {
	{ a = "Wet", b = "Frozen", name = "Sleet", displayName = "Sleet", multiplier = 6 }, -- 1.75 * 2.5 = 4.4
	{ a = "Frozen", b = "Galaxy", name = "Comet", displayName = "Comet", multiplier = 11 }, -- 2.5 * 3 = 7.5
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
	{ rebirths = 3, title = "Slime Wrangler", unlock = "OfflineCap", family = "orchard" },
	{ rebirths = 5, title = "Blob Baron", unlock = "Luck" },
	{ rebirths = 6, title = "Goo Tycoon", keep = 2, family = "frost" },
	{ rebirths = 7, title = "Jelly Magnate", income = 0.1 },
	{ rebirths = 8, title = "Ooze Overlord", lock = 30 },
	{ rebirths = 10, title = "Slime Sovereign", keep = 3, income = 0.25, family = "starlight" },
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
	-- v19 (RainMagnet, CONTRACT.md §23): off with FEATURES.RainMagnet; the def stays so saves keep the level.
	{
		id = "RainMagnet",
		name = "Rain Magnet",
		text = "+5% chance a slime you bring home in Rain, Snow or Starfall picks up that weather's mutation",
		maxLevel = 5,
		base = 300000,
		growth = 3,
		requires = 6,
		step = 0.05,
		flag = "RainMagnet",
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

-- Daily quests (Quests, Goals menu): `count` distinct pool entries rolled per player per UTC day. A target is
-- one of `choices`; progress = stat gained since the roll (Goals.stat names). Cash is x rebirthMultiplier on
-- claim; a boost follows the Codes boost rules. Pool ids are permanent save ids.
local DAILY_QUEST_POOL: { DailyQuest } = {
	{
		id = "Catch",
		stat = "caught",
		title = "Catch <n> slime<s>",
		icon = "Catch",
		choices = { 3, 5, 8 },
		reward = { kind = "cash", amount = 400 },
	},
	{
		id = "Steal",
		stat = "stolen",
		title = "Steal <n> slime<s>",
		icon = "Steal",
		choices = { 1, 2, 3 },
		reward = { kind = "cash", amount = 1000 },
	},
	{
		id = "Earn",
		stat = "earned",
		title = "Earn <n> today",
		icon = "Earn",
		cash = true,
		choices = { 5000, 20000, 100000 },
		reward = { kind = "cash", amount = 600 },
	},
	{
		id = "Merge",
		stat = "merges",
		title = "Merge <n> time<s>",
		icon = "Merge",
		choices = { 1, 2, 3 },
		reward = { kind = "boost", mult = 2, minutes = 5 },
	},
	{
		id = "Lock",
		stat = "locks",
		title = "Lock your base <n> time<s>",
		icon = "Lock",
		choices = { 1, 2, 3 },
		reward = { kind = "cash", amount = 300 },
	},
	{
		id = "Rebirth",
		stat = "rebirths",
		title = "Rebirth <n> time<s>",
		icon = "Rebirth",
		choices = { 1 },
		reward = { kind = "boost", mult = 2, minutes = 15 },
	},
}
for _, quest in DAILY_QUEST_POOL do
	table.freeze(quest.choices)
	table.freeze(quest.reward)
	table.freeze(quest)
end

local DEX_MILESTONES: { DexMilestone } = {
	{ count = 10, reward = 500, bonus = 0.02 },
	{ count = 25, reward = 2500, bonus = 0.03 },
	{ count = 50, reward = 10000, bonus = 0.05 },
	{ count = 100, reward = 50000, bonus = 0.05 },
	{ count = 200, reward = 250000, bonus = 0.1 },
	{ count = 400, reward = 1.5e6, bonus = 0.15 },
	{ count = 720, reward = 1e7, bonus = 0.25 },
}

local PLOT_SKINS: { PlotSkin } = {
	{ id = "classic", name = "Classic Ranch" },
	{
		id = "mushroom",
		name = "Mushroom Meadow",
		set = 1,
		threshold = 0.75,
		floor = { color = { 112, 150, 72 }, material = "Grass" },
		fence = { 255, 214, 196 },
		decor = "plot_skin_mushroom",
	},
	{
		id = "candy",
		name = "Candy Patch",
		set = 2,
		threshold = 0.75,
		floor = { color = { 224, 142, 172 }, material = "Sand" },
		fence = { 255, 190, 214 },
		decor = "plot_skin_candy",
	},
	{
		id = "crystal",
		name = "Crystal Grotto",
		set = 3,
		threshold = 0.75,
		floor = { color = { 148, 124, 190 }, material = "Slate" },
		fence = { 214, 196, 255 },
		decor = "plot_skin_crystal",
	},
}

-- v22 PvP ladder (FEATURES.PvP, CONTRACT.md §26, docs/PVP.md). Every gate is a REBIRTH_TIERS threshold; the price is
-- derived (PvpRules.price = factor x Economy.rebirthCost(gate), at least PVP.PRICE_MIN). Nothing here has a damage field.
local function knock(id: string, name: string, tier: number, gate: number, push: number): PvpTool
	return {
		id = id,
		name = name,
		line = "Knockback",
		tier = tier,
		rebirths = gate,
		cooldown = 1.5,
		kind = "tool",
		cosmetic = false,
		push = push,
		reach = 10,
	}
end
local function trap(
	id: string,
	name: string,
	tier: number,
	gate: number,
	traps: number,
	freeze: number,
	rearm: number,
	radius: number
): PvpTool
	return {
		id = id,
		name = name,
		line = "Trap",
		tier = tier,
		rebirths = gate,
		cooldown = rearm,
		kind = "tool",
		cosmetic = false,
		traps = traps,
		control = freeze,
		radius = radius,
	}
end
local function blaster(
	id: string,
	name: string,
	tier: number,
	gate: number,
	slow: number,
	seconds: number,
	cooldown: number,
	range: number
): PvpTool
	return {
		id = id,
		name = name,
		line = "Blaster",
		tier = tier,
		rebirths = gate,
		cooldown = cooldown,
		kind = "tool",
		cosmetic = false,
		slow = slow,
		slowSeconds = seconds,
		range = range,
	}
end
local function fun(
	id: string,
	name: string,
	gate: number,
	cooldown: number,
	cosmetic: boolean,
	extra: { [string]: any }
): PvpTool
	local tool: any = {
		id = id,
		name = name,
		line = "Fun",
		tier = 1,
		rebirths = gate,
		cooldown = cooldown,
		kind = "fun",
		cosmetic = cosmetic,
	}
	for key, value in extra do
		tool[key] = value
	end
	return tool
end
local PVP_TOOLS: { PvpTool } = {
	knock("KnockGlove1", "Bonk Glove", 1, 1, 5),
	knock("KnockGlove2", "Bounce Glove", 2, 5, 6),
	knock("KnockGlove3", "Boom Glove", 3, 8, 7),
	knock("KnockGlove4", "Thunder Glove", 4, 12, 7.5),
	knock("KnockGlove5", "Royal Glove", 5, 20, 8),
	trap("GooTrap1", "Goo Puddle", 1, 3, 1, 1, 30, 3),
	trap("GooTrap2", "Sticky Trap", 2, 6, 2, 1.5, 25, 3.5),
	trap("GooTrap3", "Mega Trap", 3, 10, 2, 2, 20, 4),
	blaster("GooBlaster1", "Goo Squirter", 1, 7, 0.3, 2, 12, 40),
	blaster("GooBlaster2", "Goo Blaster", 2, 12, 0.4, 2.5, 11, 45),
	blaster("GooBlaster3", "Goo Cannon", 3, 20, 0.5, 3, 10, 50),
	fun("FunConfetti", "Confetti Popper", 0, 5, true, { allowInSafeZone = true }),
	fun("FunBalloon", "Goo Balloon", 1, 3, true, { fadeSeconds = 10, maxDecals = 8 }),
	fun("FunBubbles", "Bubble Wand", 3, 4, true, {}),
	fun("FunBouncePad", "Bounce Pad", 5, 10, false, { height = 25, control = 1.2, maxPlaced = 1 }),
	fun("FunSqueaky", "Squeaky Hammer", 6, 3, false, { nudge = 2 }),
	fun("FunHatLauncher", "Slime Hat Launcher", 7, 8, true, { hatSeconds = 30 }),
	fun("FunDanceBomb", "Dance Bomb", 8, 45, false, { control = 2 }),
	fun("FunFireworks", "Goo Fireworks", 10, 20, true, {}),
}

for _, list in { REBIRTH_TIERS, UPGRADES, DEX_MILESTONES } :: { { any } } do
	for _, entry in list do
		table.freeze(entry)
	end
end
for _, skin in PLOT_SKINS do
	if skin.floor then
		table.freeze(skin.floor.color)
		table.freeze(skin.floor)
	end
	if skin.fence then
		table.freeze(skin.fence)
	end
	table.freeze(skin)
end
for _, tool in PVP_TOOLS do
	table.freeze(tool)
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
for _, mutation in WEATHER_MUTATIONS do
	table.freeze(mutation)
end
for _, combo in WEATHER_COMBOS do
	table.freeze(combo)
end

-- v30 C9: wild slimes moved too fast. Every wild-slime pace (the parade lane walk, its hop rate) scales by this;
-- 1 = the old pace, 0.65 = 35% slower. The lane walk is a fixed route over the slime's lifetime, so the lifetime
-- stretches by 1 / mult to keep the drain reached right at expiry (WILD_LIFETIME below).
local SLIME_MOVE_SPEED_MULT = 0.65
local RITUAL_MIN_PLAYERS = 2 -- Config.RITUAL.MIN_PLAYERS; also the number of stand spots
local WILD_BASE_LIFETIME = 75 -- seconds at the old pace

local Config = {
	RARITIES = table.freeze(RARITIES),
	MUTATIONS = table.freeze(MUTATIONS),
	COMBOS = table.freeze(COMBOS),
	WEATHER_MUTATIONS = table.freeze(WEATHER_MUTATIONS),
	WEATHER_COMBOS = table.freeze(WEATHER_COMBOS),
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
	WELCOME_BACK_MIN_SECONDS = 4 * 60 * 60, -- away at least this long = a welcome-back card on join

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
	PLOT_SKINS = table.freeze(PLOT_SKINS), -- plot skins unlocked by SlimeDex sets (CONTRACT.md §15)
	PLOT_SKIN_DEFAULT = "classic",

	-- Lock / steal
	JOIN_LOCK_SECONDS = 45,
	LOCK_SECONDS = 60,
	LOCK_SECONDS_PER_REBIRTH = 10,
	LOCK_MAX_REMAINING = 300, -- extending can never push the lock past 5 min
	LOCK_BASE_COST = 25,
	REVENGE_SECONDS = 60, -- FEATURES.Revenge: how long a robbed player sees the thief's plot, and the thief pays more for locks
	REVENGE_LOCK_COST_MULT = 2, -- FEATURES.Revenge: lock price multiplier for a thief inside any victim's window
	LOCK_INCOME_SECONDS = 15, -- lock costs this many seconds of plot income (or base cost)
	-- B1: seconds a ProximityPrompt / UI button must be held for any important
	-- action (steal, buy, lock, pad, merge, claim, sell, rebirth). Free Grab, Open Shop, Talk stay instant.
	HOLD_CONFIRM_SECONDS = 0.8,
	TUTORIAL_STEAL_SKIP_SECONDS = 20, -- solo tutorial: Steal step skips itself after this long with nobody to steal from
	STEAL_REACH = 14, -- studs: max server-checked distance to grab a slime
	SLAP_REACH = 10,
	SLAP_COOLDOWN = 1.5,
	-- The default melee Bat Tool (server/BatTool, every player, live, NOT behind FEATURES.PvP). A hit on a carrying
	-- thief is the base slap (StealService.slap: reach SLAP_REACH, cooldown SLAP_COOLDOWN) plus a knockback push.
	BAT = table.freeze({
		TOOL_NAME = "Bat",
		PUSH = 5, -- studs of knockback (PvpKnockbackRules.plan, capped by PVP.KNOCKBACK_MAX_PUSH)
		FACING_DOT = 0.3, -- the thief must be in front: dot(look, direction to them) >= this (about 72 degrees each side)
		CLOSE_STUDS = 3, -- closer than this the facing check is skipped (hugging a thief)
		SWING_GAP = 0.4, -- seconds between swing events (a whiff never spends the SLAP_COOLDOWN)
	}),
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
	-- 3-slime merge (FEATURES.MergeVat3, TripleMerge)
	TRIPLE_MERGE_JUMP_CHANCE = 0.2, -- chance the result is two rarities up (never into Secret)
	TRIPLE_MERGE_MUTATION_CHANCE = 0.3, -- chance of a fresh mutation on top of the inherited ones
	TRIPLE_MERGE_SIZE_BONUS = 0.15, -- added to the parents' mean size

	-- Stacking mutations (FEATURES.MutationStacking)
	MAX_MUTATIONS = 3, -- a slime carries at most this many mutations (a fused combo counts as one)
	STACK_MUTATION_CHANCE = 0.25, -- chance per free slot that a mutated slime rolls one more (drops, merges, Appraise)

	-- Appraise: reroll one owned slime's mutation or size
	APPRAISE_COST_FRACTION = 0.3, -- of the slime's current value (Economy.sellPrice)
	APPRAISE_MUTATION_CHANCE = 0.6, -- chance a mutation reroll lands on a mutation (else None)

	-- Fountain (wild slime spawns)
	SPAWN_INTERVAL = 4,
	MAX_WILD_SLIMES = 18,
	SLIME_MOVE_SPEED_MULT = SLIME_MOVE_SPEED_MULT,
	WILD_BASE_LIFETIME = WILD_BASE_LIFETIME,
	WILD_LIFETIME = math.round(WILD_BASE_LIFETIME / SLIME_MOVE_SPEED_MULT), -- 115: walk + hop slower, drain still at expiry
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
	FAMILY_DROP_CHANCE = 0.3, -- FEATURES.FountainTiers: share of fountain drops that are a family slime (from the families the server's fountain tier has opened)
	WILD_PRICE_SECONDS = 20, -- other wild slimes cost this many seconds of their income

	-- Slime Rain event
	RAIN_INTERVAL = 60 * 60, -- design: hourly
	RAIN_FIRST_AT = 5 * 60,
	RAIN_DURATION = 3 * 60, -- design: 3 minutes
	RAIN_SPAWN_INTERVAL = 0.75,
	RAIN_MUTATION_CHANCE = 0.35,
	RAIN_LUCK = 3, -- rarity weights for tier >= 3 multiplied by this during rain
	RAIN_WARNING_SECONDS = 60, -- everyone gets a heads-up toast this long before a rain

	-- Weekly event rotation (FEATURES.WeeklyEvents, CONTRACT.md §17). The whole schedule is a pure function
	-- of unix time (UTC), so every server agrees. Weeks run Monday 00:00 - Sunday 24:00 UTC (ISO weeks).
	-- Each week's mutation is MUTATION_ROTATION[week % n]; on that week's Saturday, `TRAIT_START_HOUR`
	-- (UTC) a TRAITS[week % m] event runs for TRAIT_SECONDS (shorter than a day, so it never spills over).
	-- `chanceBonus` is added to the wild drop mutation chance for that mutation only (the same roll window
	-- as the weather bonus); `luck` / `mutation` multiply the rarity luck / mutation chance like a
	-- CycleModifier. WeeklyEvents clamps every value to MAX_* whatever is written here.
	WEEKLY = table.freeze({
		MUTATION_ROTATION = table.freeze({ "Glow", "Lava", "Galaxy", "Rainbow", "Gold", "Crystal" }), -- Config.MUTATIONS names; "Eclipse" stays rare
		MUTATION_CHANCE_BONUS = 0.03, -- doubles the base 3 % drop chance for the week's mutation, no more
		TRAIT_WEEKDAY = 6, -- Saturday (0 = Sunday)
		TRAIT_START_HOUR = 18, -- UTC
		TRAIT_SECONDS = 2 * 60 * 60,
		TRAITS = table.freeze({
			table.freeze({ id = "lucky", label = "Lucky Saturday", icon = "🍀", luck = 1.5, mutation = 1 }),
			table.freeze({ id = "mutant", label = "Mutant Saturday", icon = "🧬", luck = 1, mutation = 1.5 }),
		}),
		MAX_CHANCE_BONUS = 0.05,
		MAX_MULTIPLIER = 2,
		SYNC_SECONDS = 60, -- the server re-checks the schedule at least this often
	}),

	-- Extras, each behind a flag (CONTRACT.md §2 Extras). false = fully off.
	FEATURES = table.freeze({
		BossSlime = true, -- a big free Epic+ slime spills from the fountain every BOSS_INTERVAL
		FollowPets = true, -- your favourite (or best) slime follows you as a small pet (client-only)
		DayNight = true, -- Lighting.ClockTime cycles every DAY_LENGTH seconds
		Minimap = true, -- Visuals.MinimapData points of interest for a UI minimap
		DespawnTelegraph = true, -- wild slime models get DespawnAt before they expire; false = silent removal
		Habitats = true, -- pads turn into their slime's habitat (HABITATS.md); false = pads as before
		SlimeAnimations = true, -- slimes play the uploaded KeyframeSequences (MeshAssets.ANIMATIONS) once a probe track loads; false = procedural Motor6D motion (ui/SlimeMotor)
		CycleModifier = true, -- a server modifier (Luck Surge, Mutation Surge, ...) is rolled at each dawn and dusk of the DayNight cycle (CycleModifier); needs DayNight; false = no modifier
		SlideCollision = true, -- invisible colliders along the FULL fountain slide, top to mouth (B6: players fell through above LOW_SLIDE_Y); false = low stretch only
		FriendBonus = true, -- +FRIEND_BONUS_PER_FRIEND income per friend in the same server, up to FRIEND_BONUS_CAP (FriendBonus); false = no bonus
		MutationStacking = true, -- slimes can carry several mutations and some pairs fuse into a combo (Config.COMBOS); false = rolls give at most one mutation (saves still migrate and load)
		WeatherMutations = true, -- the current weather boosts the roll chance of its mutation (Config.WEATHER[id].mutation / chanceBonus; Genome.rollMutation); needs Weather to be on to ever leave Clear
		Weather = true, -- Rain / Snow / Starfall cycle (WeatherService) and client visuals (WeatherFx); WEATHER.md
		SnowGround = true, -- SnowGround v2: client ground snow by tinting the existing Ground / Terrain / paths (no extra parts or meshes), settles during Snow, melts after; v1 (one flat Snow Part) was cut in #223. Snowfall particles stay with Weather.
		GrowingSlimes = true, -- slimes on a pad grow over time (+GROWTH_MAX_INCOME_BONUS income at full growth, offline time counts, capped) (Growth); false = no growth, income and size unchanged
		AdminEvents = true, -- admin-only timed Luck / Mutation surge and Slime Rain, chat command + MessagingService (AdminEvents, CONTRACT.md §12); false = never triggers
		PetPassives = true, -- the favourite (follow) slime grants a small capped perk by tier / mutations: income, luck or merge mutation chance (Perks.petPassive, CONTRACT.md §14); false = cosmetic only
		CoopRitual = true, -- 2-4 players stand on the ritual circle for a timed "Blessed" income boost (Ritual, CONTRACT.md §13); false = no circle, no boost
		PlotSkins = true, -- plot skins unlocked by owning ~75 % of a SlimeDex set (PlotSkins, CONTRACT.md §15); false = no remote, State fields, plot attribute or visuals (risky: needs frame review)
		Revenge = true, -- for REVENGE_SECONDS after a thief robs you, you see their plot highlighted and their lock costs them x REVENGE_LOCK_COST_MULT (server/Revenge, CONTRACT.md §16); false = no marks, no highlight, normal lock price
		StealAlerts = true, -- v21 full steal alerts (StealAlert, CONTRACT.md §17): owner gets a red screen-edge flash, a repeating alarm, a direction arrow + world ping to the thief; the carrying thief gets a trail; a SLAP gets a hit effect; a "while you were away" notice on join from a capped saved steal log; false = the plain banner + toast only (needs frame review)
		WeeklyEvents = true, -- rotating weekly mutation boost (one Config.MUTATIONS entry per ISO week) + a timed Saturday trait event, a pure function of os.time (WeeklyEvents, CONTRACT.md §18); false = no boost, no attribute
		FountainSplit = true, -- draft for Merijn's fountain collision choice (a): MeshSwap places the slime_fountain as 5 meshes (basin, dome, eave, silo, slide; same look) and the tower pieces collide as PreciseConvexDecomposition instead of the hand-placed Basin / Trim / Silo / Top colliders (SlideColliders stay); any piece failing to load keeps the single mesh and the colliders (CONTRACT.md §28, docs/COLLISION.md; needs a Studio walk + ball-drop test before it can ship)
		SlidePCD = true, -- the slide as a real collision mesh: MeshSwap makes fountain_split_slide PreciseConvexDecomposition (needs FountainSplit) and, once it is placed, FountainColliders drops the SlideColliders Floor / Joint / Post / Brace boxes it replaces; the Fill block + ridge roof, the Skirt and SlideTopWatch stay (the PCD trough is a walkable ramp, docs/COLLISION.md); false = decor slide and every box as before
		FountainTiers = true, -- v19: the central fountain upgrades with the server's best rank (FountainTiers: ring, crest, glow) and each rank opens a slime family that drops from it; catching a family slime needs your own rank; false = one Meadow fountain, Classic drops only (needs frame review)
		MergeVat3 = true, -- v19: the plot merge vat takes 3 slimes of one rarity for one of the next (or, sometimes, two) rarities, keeping every mutation (TripleMerge, Request Merge3, CONTRACT.md §21); false = the two-slime vat only (needs frame review)
		Consumables = true, -- restocking Shop section: mutation spray, luck potion, weather totem on a server-wide CONSUMABLES_RESTOCK_SECONDS schedule (Consumables); false = no section, BuyConsumable refused
		RainMagnet = true, -- v19: the Rain Magnet upgrade (rank 6): a wild slime you bring home during Rain / Snow / Starfall (or the Slime Rain event) may pick up that weather's mutation; needs Weather + WeatherMutations to ever have a target (RainMagnet, CONTRACT.md §23); false = no upgrade in the shop, no purchase, no effect (needs frame review)
		ServerProfiler = false, -- dev tool, stays off in live (log + clock reads only help while profiling). v23: rolling per-system server timings, a one-line log every PROFILER.LOG_INTERVAL s and budget warnings (server/Profiler, CONTRACT.md §25); false = no clock reads, no log
		Audio = true, -- v23 SoundController: central SFX registry, Music / SFX SoundGroups, mute + volume, day/night ambience (ui/SoundController, ui/AudioLogic, CONTRACT.md §2 Extras); false = Notify sounds play as before, no groups, no ambience, no toggle
		PvP = true, -- v22 PvP fairness core (PvpRules, server/PvpService, CONTRACT.md §26, docs/PVP.md): rank-gated tools and fun items bought with cash, safe zones, new-player shield, control limits; false = BuyPvpItem refused, no runtime state, no attributes, nothing saved changes
		WorldShops = true, -- CONTRACT.md §27: Item Shop + Upgrade Shop stands (ItemShopStand / UpgradeShopStand), Request OpenShop / CloseShop / ShopBuy, ShopEvent, range checks; false = the single ShopStand and the HUD Shop as before
		WorldShopsStrict = true, -- CONTRACT.md §27.6: the old buy actions also need an open shop in range ("NotOpen"); on since the HUD Shop button is gone in HUD v2. Needs WorldShops
		Parade = true, -- wilds hop the goo-parade lane round the plaza into the goo drain (ParadeLane); false = landing band as before
	}),

	-- Server profiler (FEATURES.ServerProfiler, server/Profiler). BUDGET_MS = p95 ms per frame / call.
	PROFILER = table.freeze({
		WINDOW = 120, -- samples kept per system
		LOG_INTERVAL = 30, -- seconds between summary lines
		BUDGET_MS = table.freeze({
			GameLoop = 4,
			Rescue = 1,
			Players = 3,
			View = 4,
			Heartbeat = 8,
		} :: { [string]: number }),
	}),

	-- Audio (FEATURES.Audio, ui/AudioLogic / ui/SoundController). An empty or malformed id = that sound stays silent.
	AUDIO = table.freeze({
		DEFAULT_SFX_VOLUME = 0.8, -- 0..1, SFX SoundGroup
		DEFAULT_MUSIC_VOLUME = 0.35, -- 0..1, Music / Ambient SoundGroup
		AMBIENT_VOLUME = 0.25, -- loop volume inside the Music group (low on purpose)
		AMBIENT_FADE_SECONDS = 4, -- crossfade day <-> night
		-- SFX registry name -> Notify sound name (Sounds.IDS) or a direct asset id.
		SFX = table.freeze({
			buy = "Cash",
			collect = "Deposit",
			steal = "Stolen",
			merge = "Merge",
			rebirth = "Rebirth",
			alarm = "Alarm",
			error = "rbxasset://sounds/uuhhh.mp3",
			click = "rbxasset://sounds/button.wav",
		}),
		-- Ambient loops (20 s seamless, Merijn-owned uploads).
		AMBIENT_DAY_ID = "rbxassetid://91856264327473", -- birds (original procedural loop, uploaded via Open Cloud; moderation pending at upload)
		AMBIENT_NIGHT_ID = "rbxassetid://132943569734014", -- crickets (same)
	}),

	-- Full steal alerts (FEATURES.StealAlerts, StealAlert / ui/StealAlertFx). Client timings in seconds.
	STEAL_ALERT = table.freeze({
		FLASH_SECONDS = 1.2, -- red screen-edge flash when a theft starts
		FLASH_PULSES = 2,
		ALARM_REPEAT = 3, -- the toast already plays the first Alarm; it sounds again this often ...
		ALARM_REPEATS = 2, -- ... at most this many extra times per theft
		ARROW_MARGIN = 56, -- px from the viewport edge the direction arrow stays inside
		PING_HIDE_STUDS = 14, -- thief ping hides inside this distance (you can see them)
		TRAIL_LIFETIME = 0.6, -- the thief's trail (under the 2 s fx cap)
		SLAP_FX_SECONDS = 0.5,
		LOG_CAP = 12, -- saved theft entries kept per player (oldest dropped)
		SUMMARY_NAMES = 3, -- thief names listed in the join notice ("... and 2 more")
		NAME_MAX = 20,
	}),

	-- Slime motion LOD (ui/SlimeLod). Studs from the camera: full motion up to
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

	-- Habitat morph feel (HabitatFx / HabitatMorph, HABITATS.md "Animation"). Client only.
	-- STAGGER = share of the morph the last prop waits before it starts; OVERSHOOT = easeOutBack
	-- strength when rising; BURST_* = puff particles per transform by quality; MAX_ANIMATING = pads
	-- morphing at once before a new change snaps (cap); SNAP_BEYOND = studs from the camera beyond
	-- which a change snaps with no puff.
	HABITAT_ANIM = table.freeze({
		STAGGER = 0.35,
		OVERSHOOT = 1.6,
		BURST_FULL = 24,
		BURST_SIMPLE = 8,
		MAX_ANIMATING = 6,
		SNAP_BEYOND = 90,
		REDUCED_ATTRIBUTE = "ReducedMotion", -- LocalPlayer attribute; true = no tween, no puff
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

	-- Co-op ritual (FEATURES.CoopRitual, CONTRACT.md §13). The circle sits on the meadow outside the ring path beside plot 1's
	-- entrance, clear of the slime lane, the plots, the slide and the fountain (bearing: 0 = +Z, like WorldLayout.PROP_SPOTS). Every number is server-side.
	RITUAL = table.freeze({
		BEARING = 348, -- degrees round the fountain
		DISTANCE = 93, -- studs from the fountain axis
		CIRCLE_RADIUS = 6, -- the painted disc
		SPOTS = RITUAL_MIN_PLAYERS, -- glowing stand spots: one per required player (so 2 pads)
		SPOT_DISTANCE = 3.5, -- spot centre from the circle centre
		STAND_RADIUS = 2.4, -- a player counts on the nearest spot within this (horizontal)
		STAND_HEIGHT = 8, -- and a root part at most this high above the plaza ground (not on the fountain)
		MIN_PLAYERS = RITUAL_MIN_PLAYERS,
		HOLD_SECONDS = 6, -- everyone must keep standing this long
		SERVER_COOLDOWN = 240, -- seconds the circle rests after a ritual
		PLAYER_COOLDOWN = 600, -- seconds before the same player can count again
		BLESS_SECONDS = 180,
		BONUS = table.freeze({ [2] = 0.3, [3] = 0.2, [4] = 0.3 }), -- Blessed income bonus by participants; tiers above SPOTS stay as data but can't be reached (Ritual.bonus caps at SPOTS)
	}),

	-- Follow-pet passives (FEATURES.PetPassives, CONTRACT.md §14). The kind comes from the favourite slime's tier;
	-- value = tier * perTier + MUTATION_STEP per mutation, capped per kind. All additive and server-side.
	PET_PASSIVES = table.freeze({
		MUTATION_STEP = 0.01, -- extra per mutation on the slime
		KIND_BY_TIER = table.freeze({ "income", "income", "luck", "luck", "mutation", "mutation", "luck" }),
		KINDS = table.freeze({
			income = table.freeze({ icon = "💰", word = "income", perTier = 0.01, cap = 0.08 }), -- x(1 + value) income
			luck = table.freeze({ icon = "🍀", word = "luck", perTier = 0.01, cap = 0.06 }), -- added to Perks.luckChance
			mutation = table.freeze({ icon = "🧬", word = "mutation", perTier = 0.02, cap = 0.12 }), -- added to the merge mutation chance
		}),
	}),

	-- Mystery Egg: bought with in-game cash only, never Robux. The price is
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
	-- Restocking consumables (FEATURES.Consumables, competitor-gaps.md #13). The stock of slot
	-- floor(unix time / CONSUMABLES_RESTOCK_SECONDS) is a pure function of the slot, so every server
	-- agrees. `max` is the most a player may buy per restock (the roll is minStock..maxStock; 0 = sold out
	-- this slot). `price` is x the rebirth multiplier. Ids are the BuyConsumable argument: never rename.
	CONSUMABLES_RESTOCK_SECONDS = 5 * 60,
	CONSUMABLE_HELD_MAX = 99, -- most of one consumable a player can hold (a purchase over it is refused)
	CONSUMABLES = table.freeze({
		table.freeze({
			id = "MutationSpray",
			name = "Mutation Spray",
			icon = "🧪",
			text = "Adds a mutation to your favourite slime (or rerolls it).",
			price = 3000,
			minStock = 1,
			maxStock = 3,
		}),
		table.freeze({
			id = "LuckPotion",
			name = "Luck Potion",
			icon = "🍀",
			text = "Better rarity odds for everyone's fountain drops.",
			price = 2000,
			minStock = 1,
			maxStock = 4,
		}),
		table.freeze({
			id = "WeatherTotem",
			name = "Weather Totem",
			icon = "🗿",
			text = "Calls the weather shown here next.",
			price = 5000,
			minStock = 0,
			maxStock = 2,
		}),
	}),
	LUCK_POTION_MULT = 2.5, -- x the fountain's tier >= 3 rarity weights while a potion is active
	LUCK_POTION_SECONDS = 5 * 60, -- each potion adds this much time (they extend, never stack the multiplier)
	LUCK_POTION_MAX_SECONDS = 15 * 60, -- most time that can be queued
	SPAWN_LUCK_CAP = 4, -- potion x cycle modifier luck never goes above this (a modifier alone may)

	-- Weather (FEATURES.Weather, WEATHER.md). Clear plus three visual types, cycled by the server.
	-- `mutation` (a Config.MUTATIONS name) and `chanceBonus` (extra absolute chance, on top of the roll's own
	-- chance, that the roll lands on that mutation) are read by Genome.rollMutation while that weather is current.
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
			mutation = "Wet",
			chanceBonus = 0.1,
			weight = 3,
			minSeconds = 120,
			maxSeconds = 210,
		}),
		Snow = table.freeze({
			displayName = "Snow",
			mutation = "Frozen",
			chanceBonus = 0.1,
			weight = 3,
			minSeconds = 120,
			maxSeconds = 210,
		}),
		Starfall = table.freeze({
			displayName = "Starfall",
			mutation = "Galaxy",
			chanceBonus = 0.05,
			weight = 1,
			minSeconds = 90,
			maxSeconds = 150,
		}),
	}),
	WEATHER_FIRST_AT = 60, -- seconds after server start before the first change away from Clear
	WEATHER_FADE_SECONDS = 3.5, -- client grade (tint, atmosphere, ambient, emitter rates) tween in / out, one tween
	WEATHER_PARTICLE_CAP = 160, -- hard cap on weather particles alive at once, whatever the quality level

	-- Slime growth (FEATURES.GrowingSlimes): a slime's `growth` (0..1) rises by dt / GROWTH_SECONDS while it
	-- sits on a pad. Offline time counts too, up to GROWTH_OFFLINE_CAP_SECONDS. At growth 1 a slime earns
	-- (and sells for) 1 + GROWTH_MAX_INCOME_BONUS times its base income and is drawn GROWTH_MAX_SCALE_BONUS bigger.
	GROWTH_SECONDS = 12 * 60 * 60,
	GROWTH_OFFLINE_CAP_SECONDS = 8 * 60 * 60,
	GROWTH_MAX_INCOME_BONUS = 0.5,
	GROWTH_MAX_SCALE_BONUS = 0.1,
	GROWTH_LABEL_GAP = 1.5, -- studs between the top of the slime and its "Growth %" label

	-- Daily reward
	DAILY_BASE = 100,
	DAILY_STREAK_CAP = 7,
	DAILY_QUESTS = table.freeze({ count = 3, pool = table.freeze(DAILY_QUEST_POOL) }),

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

	-- World shops (FEATURES.WorldShops, CONTRACT.md §27): studs from the character's HumanoidRootPart to the stand's Counter,
	-- checked on the server on OpenShop and on every purchase; out of range closes the shop.
	SHOP_RANGE = 14,

	-- Owner-only plot pad prompts (LockPrompt / BuyPadPrompt / MergePrompt): the prompts' MaxActivationDistance, and the extra
	-- studs the server allows on top of it (lag, the prompt part's own size) when it checks the owner against THAT prompt part.
	PLOT_PAD_PROMPT_DISTANCE = 10,
	PLOT_PAD_RANGE_SLACK = 4,

	-- Friend income bonus (FEATURES.FriendBonus, CONTRACT.md §11)
	FRIEND_BONUS_PER_FRIEND = 0.1, -- +10% income per friend in the same server
	FRIEND_BONUS_CAP = 0.3, -- at most +30%
	FRIEND_CACHE_SECONDS = 600, -- a Player:IsFriendsWith answer is reused this long
	FRIEND_RETRY_SECONDS = 30, -- after a failed check, don't ask again for this long

	-- x2 Weekends (Weekend, competitor-gaps #17): server clock, UTC, nothing saved.
	WEEKEND = table.freeze({
		enabled = true, -- false = never double
		multiplier = 2, -- cash income x this while active (stacks with the other boosts)
		weekdays = table.freeze({ 6, 0 }), -- UTC weekdays (0 = Sunday .. 6 = Saturday): Sat 00:00 - Sun 23:59
		overrideDates = table.freeze({} :: { string }), -- extra whole UTC days "YYYY-MM-DD" (a holiday event)
	}),

	-- v22 PvP fairness core (FEATURES.PvP, CONTRACT.md §26). Zones are XZ discs (the Y axis is ignored).
	-- Positions are derived from the world layout: the hub spawn sits at bearing 67.5 / r 64 (scripts/StaticWorld
	-- SPAWN_YAW / SPAWN_RADIUS), the ShopStand at bearing 67.5 / r 90 (WorldLayout.PROP_SPOTS), the fountain
	-- ("fountain rim") at the origin out to the landing-ring curb r 44.4 (Fountain.LANDING_RING_OUTER); tests/PvpRules.spec
	-- checks each against its source. Bearing 0 = +Z, so x = sin(b) * r and z = cos(b) * r.
	PVP = table.freeze({
		SAFE_ZONES = table.freeze({
			table.freeze({
				id = "spawn",
				x = math.sin(math.rad(67.5)) * 64,
				z = math.cos(math.rad(67.5)) * 64,
				radius = 16,
			}),
			table.freeze({
				id = "shop",
				x = math.sin(math.rad(67.5)) * 90,
				z = math.cos(math.rad(67.5)) * 90,
				radius = 16,
			}),
			table.freeze({ id = "fountain", x = 0, z = 0, radius = 44.4 }),
		}),
		NEW_PLAYER_SHIELD_SECONDS = 600, -- shield until this much play time OR the first rebirth, whichever is first; ends early when the player steals
		CONTROL_MAX_SECONDS = 2, -- longest hard crowd control (freeze, dance, bounce) on one player
		SLOW_MAX_SECONDS = 3, -- longest slow
		CONTROL_IMMUNITY_SECONDS = 3, -- after any control ends, the target cannot be controlled again for this long
		MIN_COOLDOWN = 1.5, -- no tool re-arms faster than this
		PRICE_FACTOR_TOOL = 0.03, -- price = factor x Economy.rebirthCost(gate), pacing sim tunes
		PRICE_FACTOR_FUN = 0.01,
		PRICE_MIN = 100,
		-- Knockback: horizontal push is capped, the arc is small, and the landing point stays inside the map.
		KNOCKBACK_MAX_PUSH = 8, -- studs (2x the base slap push of 4)
		KNOCKBACK_ARC_HEIGHT = 2, -- studs of vertical arc at most
		KNOCKBACK_BOUNDS_MARGIN = 6, -- studs kept clear of the map edge
		KNOCKBACK_SECONDS = 0.35, -- the launch covers the push in this long
		KNOCKBACK_FRICTION_BOOST = 1.5, -- horizontal launch speed x this, ground friction eats the rest (the landing stays clamped inside the map margin)
		KNOCKBACK_MAX_SPEED_Y = 110, -- studs/s: client-side cap on a launch's vertical speed (Bounce Pad 25 studs needs ~99)
		LAUNCH_GUARD_SECONDS = 5, -- after a PvP launch / while under control the void guard (Rescue.PVP_SAFE_Y) is armed
		KNOCKBACK_CONTROL_SECONDS = 0.6, -- a knockback counts as control (PvpRules.applyControl), then immunity
		FUN_AIM_RANGE = 40, -- studs: how far a Balloon / Bounce Pad / Fireworks aim point may be
		TRAP_PLACE_RANGE = 40, -- studs: how far from the owner a Goo Trap may be placed
		FUN_NUDGE_CONTROL_SECONDS = 0.3, -- Squeaky Hammer nudge counts as a tiny control
		FIREWORKS_SECONDS = 4, -- FunFireworks Effect duration
		BOUNCE_PAD_SECONDS = 60, -- a placed Bounce Pad lives this long
		BOUNCE_PAD_RADIUS = 4, -- studs: stepping within this horizontal distance triggers it
		BOUNCE_RETRIGGER_SECONDS = 2, -- the owner's pad cannot relaunch them sooner
		FX_SECONDS = 1, -- client FX from PvpEvent "Effect" live at most this long (nothing persistent, no server parts)
		MAP_BOUNDS = table.freeze({ minX = -320, maxX = 320, minZ = -320, maxZ = 320 }), -- WorldBorder.GROUND_HALF = 320, Ground centred on the origin
	}),
	PVP_TOOLS = table.freeze(PVP_TOOLS),

	-- Persistence
	SAVE_VERSION = 6, -- CONTRACT.md §8.9 (v4: slime.mutations list, SaveData.migrateV3; v5: weather mutations Wet/Frozen, SaveData.migrateV4; v6: settings + normalised plotSkin / stealLog, SaveData.migrateV5)
	AUTOSAVE_INTERVAL = 60,
	SESSION_STALE_SECONDS = 180, -- a session lock older than this may be taken over
	MAX_SLIMES_SAVED = 64,
}

local Validate = if script then require(script.Parent.Validate) else require("./Validate")
do
	local problems = Validate.pvpTools(Config.PVP_TOOLS, Config.PVP, Config.REBIRTH_TIERS)
	assert(#problems == 0, `Config.PVP_TOOLS: {table.concat(problems, "; ")}`)
end

-- Studio-only review override of the default-off flags (FeatureOverride); a no-op everywhere else.
local FeatureOverride = if script then require(script.Parent.FeatureOverride) else require("./FeatureOverride");
(Config :: any).FEATURES = FeatureOverride.install(Config.FEATURES)

return table.freeze(Config)
