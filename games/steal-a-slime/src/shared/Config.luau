--!strict
--[[
	Config

	Every tunable for Steal a Slime in one frozen table. Pure data: no Roblox
	APIs, so it loads unchanged on the server, the client and under Lune.
]]

export type Rarity = {
	tier: number,
	name: string,
	income: number, -- cash/sec for a size-1.0, plain slime at 0 rebirths
	weight: number, -- relative fountain drop weight
	color: { number }, -- UI colour (RGB 0..255)
	carrySlow: number, -- base WalkSpeed fraction lost while carrying
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

-- v13 progression (CONTRACT.md §8.8)
export type RebirthTier = {
	rebirths: number, -- reached at this many rebirths
	title: string,
	unlock: string?, -- upgrade id this rank unlocks (its Config.UPGRADES levelRequires[1] is this rank's rebirths)
	income: number?, -- income bonus (0.25 = +25 %)
	family: string?, -- FountainTiers family id: this rank grows the fountain into its look (FEATURES.FountainTiers; FountainTiers.FAMILIES)
	merge: number?, -- top rarity tier this rank lets the player put in the merge vat (MergeGate, contract/merge-vat.md §21.9)
}

export type Upgrade = {
	id: string, -- BuyUpgrade argument, State.upgrades[i].id
	name: string,
	text: string, -- what one level does
	maxLevel: number,
	base: number, -- price of level 1
	growth: number, -- price of level n+1 = base * growth^n
	levelRequires: { number }, -- rebirths each level needs (level n needs levelRequires[n]), one per level, never decreasing
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

-- Plot skins (FEATURES.PlotSkins, CONTRACT.md §15): goo jar tower themes. A skin's slimes are a whole family
-- (`family`, a FountainTiers.FAMILIES id) or a `species` list (SlimeRoster ids); it unlocks once `threshold` of them
-- are found (PlotSkins). Neither = always unlocked. Colours are RGB 0..255; `color` is the picker card's swatch.
-- `floor`, `trim` and `decor` are PlotDecor.applySkin's plot paint: the Base, trim parts and mailbox slot it paints
-- are hidden under the goo jar tower meshes.
export type PlotSkin = {
	id: string, -- permanent save id; never rename
	name: string,
	family: string?,
	species: { string }?,
	threshold: number?,
	color: { number }?,
	floor: { color: { number }, material: string }?, -- plot Base; nil = leave as built
	trim: { number }?,
	decor: string?, -- MeshAssets name that stands in for the plot's mailbox slot
}

-- A plot base: the building a plot stands in (FEATURES.BaseShapes, CONTRACT.md §44), chosen apart from the skin.
-- `rebirths` = the rebirth count that unlocks it (nil = everyone). Ids are permanent save ids.
export type PlotBase = {
	id: string, -- permanent save id; never rename
	name: string,
	rebirths: number?,
}

-- Pet seats (contract/pet-seats.md): what the follow pet rides on, picked in the Skins menu's Cloud tab. `mesh` is the
-- MeshAssets name (shared/modeling-kit/models/PET_MOUNTS.md); `seat` is the height of the seat surface over the mesh's
-- bottom in native studs (where the pet's foot goes; decoration such as a cherry or an arch rises above it).
-- `unlock`: "free" (everyone), "merges" (`count` slimes merged, stats.merges), "dex" (`percent` of the SlimeDex
-- found) or "exclusive" (sold in the Exclusive shop; nobody owns one yet).
export type PetSeat = {
	id: string, -- permanent save id; never rename
	name: string,
	mesh: string,
	seat: number,
	color: { number }, -- icon tile colour, RGB 0..255
	unlock: { kind: "free" | "merges" | "dex" | "exclusive", count: number?, percent: number? },
}

-- A PvP tool or fun item (FEATURES.PvP, CONTRACT.md §26). Price is derived (PvpRules.price), never stored.
-- No tool has a damage / health field: PvP never lowers Humanoid health (Validate.pvpTools asserts it).
export type PvpTool = {
	id: string, -- BuyPvpItem argument and save key; never rename
	name: string,
	line: string, -- "Knockback" | "Trap" | "Blaster" | "Fun"
	tier: number, -- 1.. within its line (Fun items: 1)
	rebirths: number, -- rank gate: a Config.REBIRTH_TIERS threshold
	cooldown: number, -- seconds, >= Config.PVP.MIN_COOLDOWN (Squirter: the refill after a tank)
	kind: string, -- "tool" | "fun"
	cosmetic: boolean, -- never moves or slows a non-consenting player
	push: number?, -- Knockback: horizontal studs; Mega Trap: the spit-out push
	arc: number?, -- Knockback: studs of vertical arc (default Config.PVP.KNOCKBACK_DEFAULT_ARC)
	reach: number?, -- Knockback: studs
	special: string?, -- Knockback: "bonk" | "bounce" | "boom" | "thunder" | "royal"
	pogo: { number }?, -- Bounce Glove: bounce heights in studs, first to last
	blastRadius: number?, -- Boom Glove: studs around the target
	blastPush: number?, -- Boom Glove: studs the blast pushes
	chain: number?, -- Thunder Glove: extra players the lightning jumps to
	chainRange: number?, -- Thunder Glove: studs from the target
	chainFactor: number?, -- Thunder Glove: push x this for a chained player
	range: number?, -- Blaster: studs
	speed: number?, -- Blaster: blob speed in studs/s (sets the flight time)
	shots: number?, -- Squirter: shots per tank
	shotGap: number?, -- Squirter: seconds between shots, >= the UsePvpItem rate limit
	slowMax: number?, -- Squirter: the stacked slow never takes more than this fraction
	blobs: number?, -- Blaster: blobs per shot
	spreadDeg: number?, -- Blaster: degrees between neighbouring blobs
	splash: number?, -- Cannon: studs around the impact that are slowed
	pool: number?, -- Cannon: radius of the slowing pool, studs
	poolSeconds: number?, -- Cannon: how long the pool stays
	radius: number?, -- Trap: studs
	pull: number?, -- Mega Trap: studs around it that are pulled in
	spitArc: number?, -- Mega Trap: studs of vertical arc of the spit
	control: number?, -- hard crowd control seconds (trap hold, dance, bubble, pancake), <= PVP.CONTROL_MAX_SECONDS
	slow: number?, -- Blaster / Trap / FunBalloon: speed taken away, 0.3 = 30 % (Squirter: per stacked hit)
	slowSeconds: number?, -- Blaster / Trap / FunBalloon: <= PVP.SLOW_MAX_SECONDS
	nudge: number?, -- FunSqueaky: studs of push when a squashed player springs back
	height: number?, -- FunBouncePad: studs straight up for the pad's owner
	maxPlaced: number?, -- placed objects at once
	hatSeconds: number?, -- FunHatLauncher: how long a hat stays on
}

local RARITIES: { Rarity } = {
	{
		tier = 1,
		name = "Common",
		income = 1,
		weight = 52,
		color = { 170, 220, 170 },
		carrySlow = 0.05,
	},
	{
		tier = 2,
		name = "Uncommon",
		income = 3,
		weight = 28,
		color = { 90, 200, 255 },
		carrySlow = 0.1,
	},
	{
		tier = 3,
		name = "Rare",
		income = 9,
		weight = 13,
		color = { 60, 110, 255 },
		carrySlow = 0.15,
	},
	{
		tier = 4,
		name = "Epic",
		income = 27,
		weight = 5.2,
		color = { 180, 80, 255 },
		carrySlow = 0.2,
	},
	{
		tier = 5,
		name = "Legendary",
		income = 80,
		weight = 1.2,
		color = { 255, 190, 40 },
		carrySlow = 0.25,
	},
	{
		tier = 6,
		name = "Mythic",
		income = 250,
		weight = 0.2,
		color = { 255, 60, 90 },
		carrySlow = 0.3,
	},
	{
		-- Secret: ~1 in 2000 wild spawns (0.05 / 99.65); announced to everyone.
		tier = 7,
		name = "Secret",
		income = 800,
		weight = 0.05,
		color = { 20, 240, 220 },
		carrySlow = 0.35,
	},
	{
		-- Celestial: above Secret; grabbed from rebirth 18 (CATCH_REBIRTHS).
		tier = 8,
		name = "Celestial",
		income = 2500,
		weight = 0.015,
		color = { 255, 236, 150 },
		carrySlow = 0.4,
	},
	{
		-- Divine: the top; grabbed from rebirth 25, or brewed from three Secrets that share a shine (SHINE_RECIPE).
		tier = 9,
		name = "Divine",
		income = 8000,
		weight = 0.004,
		color = { 255, 130, 245 },
		carrySlow = 0.45,
	},
}

-- Rebirth N (the Nth rebirth, i.e. done at N-1 rebirths) also needs the player to own these SlimeRoster
-- species (data.slimes, i.e. on a pad; a repeated id needs that many). Every level has its own list, and
-- the rebirth uses them up: those slimes are gone, even the favourite (Progression.rebirth). Each list asks
-- for the rarity players farm at that level; a family species only shows up once that family is open
-- (FountainTiers), merge hybrids start at rebirth 12, and boss and event slimes are never asked for (a boss
-- win gives no slime).
local REBIRTH_SLIMES: { { string } } = {
	{ "bumble" }, -- 1
	{ "moo" },
	{ "blaze" },
	{ "octo" },
	{ "king" }, -- 5
	{ "lop", "octo" },
	{ "chomp", "blaze" },
	{ "frostbite" },
	{ "king", "zap" },
	{ "ninja" }, -- 10
	{ "cosmo" },
	{ "steam" },
	{ "imp", "drako" },
	{ "robo" },
	{ "seraph" }, -- 15
	{ "kraken" },
	{ "dragon_king" },
	{ "amethyst" },
	{ "midas" },
	{ "cosmo", "seraph" }, -- 20
	{ "thunderbee" },
	{ "prism" },
	{ "cyber_ninja" },
	{ "eclipse" },
	{ "boo" }, -- 25
	{ "dragon_king", "cosmo" },
	{ "midas", "amethyst" },
	{ "nightwing" },
	{ "eclipse", "prism" },
	{ "midas", "eclipse", "boo" }, -- 30
}
for _, list in REBIRTH_SLIMES do
	table.freeze(list)
end

local REBIRTH_TIERS: { RebirthTier } = {
	{ rebirths = 0, title = "Slime Rookie", merge = 1 },
	{ rebirths = 1, title = "Goo Getter", unlock = "CarrySpeed", merge = 2 },
	{ rebirths = 3, title = "Slime Wrangler", unlock = "OfflineCap", family = "orchard", merge = 4 },
	{ rebirths = 5, title = "Blob Baron", unlock = "Luck", merge = 5 },
	{ rebirths = 6, title = "Goo Tycoon", income = 0.05, family = "frost" },
	{ rebirths = 7, title = "Jelly Magnate", income = 0.1 },
	{ rebirths = 8, title = "Ooze Overlord", income = 0.15 },
	{ rebirths = 10, title = "Slime Sovereign", income = 0.25, family = "starlight" },
	{ rebirths = 12, title = "Gel Emperor", income = 0.35 },
	{ rebirths = 15, title = "Gelatinous Legend", income = 0.5, merge = 6 },
	{ rebirths = 20, title = "Mythic Monarch", income = 1, merge = 7 },
	{ rebirths = 25, title = "Goo Titan", income = 1.5 },
	{ rebirths = 30, title = "Slime Deity", income = 2 },
}

local UPGRADES: { Upgrade } = {
	{
		id = "Income",
		name = "Slime Snacks",
		text = "+10% income",
		maxLevel = 25,
		base = 2000,
		growth = 2.2,
		levelRequires = { 0, 0, 0, 0, 0, 2, 2, 2, 2, 2, 6, 6, 6, 6, 6, 12, 12, 12, 12, 12, 20, 20, 20, 20, 20 },
		step = 0.1,
	},
	{
		id = "CarrySpeed",
		name = "Strong Arms",
		text = "-15% carry slowdown",
		maxLevel = 4,
		base = 5000,
		growth = 3,
		levelRequires = { 1, 3, 6, 10 },
		step = 0.15,
	},
	{
		id = "OfflineCap",
		name = "Night Shift",
		text = "+1h offline income cap",
		maxLevel = 4,
		base = 20000,
		growth = 3,
		levelRequires = { 3, 6, 10, 15 },
		step = 3600,
	},
	{
		id = "Luck",
		name = "Lucky Charm",
		text = "+3% chance a slime you bring home is one rarity higher",
		maxLevel = 10,
		base = 100000,
		growth = 4,
		levelRequires = { 5, 5, 5, 8, 8, 12, 12, 16, 20, 25 },
		step = 0.03,
	},
	{
		id = "QuickBrew",
		name = "Quick Brew",
		text = "-15% merge vat brew time",
		maxLevel = 4,
		base = 25000,
		growth = 3,
		levelRequires = { 2, 4, 6, 8 },
		step = 0.15,
	},
}

local GOALS: { Goal } = {
	{
		id = "Catch",
		title = "Catch <n> slime<s>",
		stat = "caught",
		targets = { 1, 10, 50, 200, 1000 },
		rewards = { 10, 100, 2000, 50000, 500000 },
	},
	{
		id = "Merge",
		title = "Merge <n> time<s>",
		stat = "merges",
		targets = { 1, 10, 50, 250 },
		rewards = { 25, 500, 10000, 250000 },
	},
	{
		id = "Steal",
		title = "Steal <n> slime<s>",
		stat = "stolen",
		targets = { 1, 10, 50, 200 },
		rewards = { 50, 1000, 20000, 300000 },
	},
	{
		id = "Lock",
		title = "Lock your base <n> time<s>",
		stat = "locks",
		targets = { 1, 25, 100 },
		rewards = { 10, 250, 5000 },
	},
	{
		id = "Pads",
		title = "Unlock <n> pad<s>",
		stat = "pads",
		targets = { 6, 8, 16, 24, 32 },
		rewards = { 50, 300, 20000, 1000000, 50000000 },
	},
	{
		id = "Earn",
		title = "Earn <n> in total",
		stat = "earned",
		targets = { 1e4, 1e6, 1e8, 1e10 },
		rewards = { 200, 20000, 1e6, 5e7 },
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

-- SlimeDex ladder (CONTRACT.md §36.3): species found (of SpeciesDex.TOTAL).
-- `reward` is cash x rebirthMultiplier, `bonus` a permanent income bonus (the ladder adds up to 0.45).
local DEX_MILESTONES: { species: { DexMilestone } } = {
	species = {
		{ count = 8, reward = 200, bonus = 0.02 },
		{ count = 15, reward = 1000, bonus = 0.03 },
		{ count = 20, reward = 10000, bonus = 0.05 },
		{ count = 32, reward = 250000, bonus = 0.1 },
		{ count = 40, reward = 1.5e6, bonus = 0.1 },
		{ count = 50, reward = 1e7, bonus = 0.15 },
	},
}

local PLOT_SKINS: { PlotSkin } = {
	{ id = "classic", name = "Classic Ranch", color = { 110, 226, 170 } },
	-- Garden and Frost & Sea list their first family species, so a new family slime never moves the unlock.
	{
		id = "garden",
		name = "Garden",
		species = { "sprout", "cheddar", "prickles", "flan" },
		threshold = 0.75,
		color = { 252, 176, 118 },
	},
	{
		id = "crystal",
		name = "Frost & Sea",
		species = { "chomp", "pengoo", "frostbite", "zap", "ninja" },
		threshold = 0.75,
		color = { 124, 210, 236 },
		floor = { color = { 148, 124, 190 }, material = "Slate" },
		trim = { 214, 196, 255 },
		decor = "plot_skin_crystal",
	},
	{ id = "starlight", name = "Starlight", family = "starlight", threshold = 0.75, color = { 250, 212, 118 } },
	{
		id = "candy",
		name = "Candy",
		species = { "gummy", "mochi", "flan", "soda", "rocky_road" },
		threshold = 0.75,
		color = { 246, 146, 192 },
		floor = { color = { 224, 142, 172 }, material = "Sand" },
		trim = { 255, 190, 214 },
		decor = "plot_skin_candy",
	},
	{
		id = "mushroom",
		name = "Forest",
		species = { "mushie", "froggo", "pebble", "truffle", "moo_shroom", "bloom" },
		threshold = 0.75,
		color = { 184, 150, 236 },
		floor = { color = { 112, 150, 72 }, material = "Grass" },
		trim = { 255, 214, 196 },
		decor = "plot_skin_mushroom",
	},
}

local PLOT_BASES: { PlotBase } = {
	{ id = "jar", name = "Goo Jar Tower" },
	{ id = "factory", name = "Goo Factory", rebirths = 20 },
	{ id = "pagoda", name = "Mushroom Pagoda", rebirths = 25 },
}
for _, base in PLOT_BASES do
	table.freeze(base)
end
local function seat(id: string, name: string, mesh: string, height: number, color: { number }, unlock: any): PetSeat
	return table.freeze({
		id = id,
		name = name,
		mesh = mesh,
		seat = height,
		color = color,
		unlock = table.freeze(table.clone(unlock)),
	})
end
local EXCLUSIVE = { kind = "exclusive" }
local PET_SEATS: { PetSeat } = {
	seat("cloud", "Fluffy", "pet_cloud", 1.225, { 235, 240, 255 }, { kind = "free" }),
	seat("jelly", "Jelly", "pet_mount_jelly", 1.17, { 140, 220, 90 }, { kind = "merges", count = 200 }),
	seat(
		"rainbow_cloud",
		"Rainbow Cloud",
		"pet_mount_rainbow_cloud",
		1.22,
		{ 250, 250, 255 },
		{ kind = "dex", percent = 80 }
	),
	seat("storm_cloud", "Storm Cloud", "pet_mount_storm_cloud", 1.22, { 90, 92, 110 }, EXCLUSIVE),
	seat("sunset_cloud", "Sunset Cloud", "pet_mount_sunset_cloud", 1.22, { 255, 170, 140 }, EXCLUSIVE),
	seat("ice_cloud", "Ice Cloud", "pet_mount_ice_cloud", 1.22, { 170, 215, 245 }, EXCLUSIVE),
	seat("flame_cloud", "Flame Cloud", "pet_mount_flame_cloud", 1.22, { 255, 120, 40 }, EXCLUSIVE),
	seat("leaf", "Leaf", "pet_mount_leaf", 0.25, { 80, 170, 60 }, EXCLUSIVE),
	seat("bubble", "Bubble", "pet_mount_bubble", 1.22, { 225, 235, 245 }, EXCLUSIVE),
	seat("lily_pad", "Lily Pad", "pet_mount_lily_pad", 0.99, { 100, 200, 90 }, EXCLUSIVE),
	seat("mushroom", "Mushroom", "pet_mount_mushroom", 1.23, { 230, 50, 50 }, EXCLUSIVE),
	seat("pancakes", "Pancakes", "pet_mount_pancakes", 0.99, { 240, 170, 80 }, EXCLUSIVE),
	seat("star_cushion", "Star Cushion", "pet_mount_star_cushion", 0.94, { 255, 200, 50 }, EXCLUSIVE),
	seat("crescent_moon", "Crescent Moon", "pet_mount_crescent_moon", 0.63, { 250, 240, 180 }, EXCLUSIVE),
	seat("magic_carpet", "Magic Carpet", "pet_mount_magic_carpet", 0.30, { 200, 40, 60 }, EXCLUSIVE),
	seat("ufo", "UFO", "pet_mount_ufo", 1.0, { 130, 140, 170 }, EXCLUSIVE),
	seat("royal_cushion", "Royal Cushion", "pet_mount_royal_cushion", 0.80, { 140, 60, 190 }, EXCLUSIVE),
	seat("hoverboard", "Hoverboard", "pet_mount_hoverboard", 0.70, { 130, 70, 220 }, EXCLUSIVE),
	seat("clam_shell", "Clam Shell", "pet_mount_clam_shell", 0.80, { 250, 150, 140 }, EXCLUSIVE),
}

-- PvP ladder (FEATURES.PvP, CONTRACT.md §26, docs/PVP.md). Every gate is a REBIRTH_TIERS threshold; the price is
-- derived (PvpRules.price = factor x Economy.rebirthCost(gate), at least PVP.PRICE_MIN). Nothing here has a damage field.
local function withExtra(tool: { [string]: any }, extra: { [string]: any }): PvpTool
	for key, value in extra do
		tool[key] = value
	end
	return tool :: any
end
local function knock(
	id: string,
	name: string,
	tier: number,
	gate: number,
	push: number,
	extra: { [string]: any }
): PvpTool
	return withExtra({
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
	}, extra)
end
-- One trap charge per buy; a placed trap is used up when it catches someone (cooldown = time between throws).
local function trap(id: string, name: string, tier: number, gate: number, extra: { [string]: any }): PvpTool
	return withExtra({
		id = id,
		name = name,
		line = "Trap",
		tier = tier,
		rebirths = gate,
		cooldown = 2,
		kind = "tool",
		cosmetic = false,
	}, extra)
end
local function blaster(id: string, name: string, tier: number, gate: number, extra: { [string]: any }): PvpTool
	return withExtra({
		id = id,
		name = name,
		line = "Blaster",
		tier = tier,
		rebirths = gate,
		kind = "tool",
		cosmetic = false,
	}, extra)
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
	knock("KnockGlove1", "Bonk Glove", 1, 1, 12, { special = "bonk" }),
	knock("KnockGlove2", "Bounce Glove", 2, 5, 15, { special = "bounce", pogo = { 6, 4, 2 } }),
	knock("KnockGlove3", "Boom Glove", 3, 8, 18, { special = "boom", blastRadius = 6, blastPush = 8 }),
	knock("KnockGlove4", "Thunder Glove", 4, 12, 22, {
		special = "thunder",
		chain = 2,
		chainRange = 12,
		chainFactor = 0.5,
	}),
	knock("KnockGlove5", "Royal Glove", 5, 20, 26, { special = "royal", arc = 8 }),
	trap("GooTrap1", "Goo Puddle", 1, 3, { radius = 3, slow = 0.5, slowSeconds = 2 }),
	trap("GooTrap2", "Sticky Trap", 2, 6, { radius = 3.5, control = 1.5, slow = 0.5, slowSeconds = 1.5 }),
	trap("GooTrap3", "Mega Trap", 3, 10, { radius = 4, control = 2, pull = 4, push = 4, spitArc = 3 }),
	blaster("GooBlaster1", "Goo Squirter", 1, 7, {
		cooldown = 3,
		range = 40,
		speed = 80,
		shots = 6,
		shotGap = 0.25,
		slow = 0.15,
		slowMax = 0.45,
		slowSeconds = 0.75,
	}),
	blaster("GooBlaster2", "Goo Blaster", 2, 12, {
		cooldown = 3,
		range = 45,
		speed = 70,
		blobs = 3,
		spreadDeg = 8,
		slow = 0.4,
		slowSeconds = 2,
	}),
	blaster("GooBlaster3", "Goo Cannon", 3, 20, {
		cooldown = 6,
		range = 50,
		speed = 45,
		splash = 6,
		pool = 6,
		poolSeconds = 4,
		slow = 0.5,
		slowSeconds = 3,
	}),
	-- Fun items (CONTRACT.md §26.8): the rest of their tunables live in PVP_FUN.
	fun("FunConfetti", "Confetti Popper", 0, 3, true, {}),
	fun("FunBalloon", "Goo Balloon", 1, 3, true, { slow = 0.2, slowSeconds = 2 }), -- slows only a thief in the splash
	fun("FunBubbles", "Bubble Wand", 3, 5, false, { control = 1.5 }),
	fun("FunBouncePad", "Bounce Pad", 5, 8, false, { height = 30, maxPlaced = 2 }),
	fun("FunSqueaky", "Squeaky Hammer", 6, 1.5, false, { control = 0.8, reach = 10, nudge = 4 }),
	fun("FunHatLauncher", "Slime Hat Launcher", 7, 4, true, { hatSeconds = 30 }),
	fun("FunDanceBomb", "Dance Bomb", 8, 20, false, { control = 2 }),
	fun("FunFireworks", "Goo Fireworks", 10, 12, true, {}),
}

for _, def in UPGRADES do
	table.freeze(def.levelRequires)
end
for _, list in { REBIRTH_TIERS, UPGRADES, DEX_MILESTONES.species } :: { { any } } do
	for _, entry in list do
		table.freeze(entry)
	end
end
for _, skin in PLOT_SKINS do
	if skin.species then
		table.freeze(skin.species)
	end
	if skin.color then
		table.freeze(skin.color)
	end
	if skin.floor then
		table.freeze(skin.floor.color)
		table.freeze(skin.floor)
	end
	if skin.trim then
		table.freeze(skin.trim)
	end
	table.freeze(skin)
end
for _, tool in PVP_TOOLS do
	if tool.pogo then
		table.freeze(tool.pogo)
	end
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
-- v30 C9: wild slimes moved too fast. Every wild-slime pace (the parade lane walk, its hop rate) scales by this;
-- 1 = the old pace, 0.65 = 35% slower. The lane walk is a fixed route over the slime's lifetime, so the lifetime
-- stretches by 1 / mult to keep the drain reached right at expiry (WILD_LIFETIME below).
-- One boss attack (Config.BOSS.MOVES): a frozen table typed loosely, since every attack kind has its own fields
-- (Shared.BossAttacks reads them by kind).
local function bossAttack(def: { [string]: any }): { [string]: any }
	return table.freeze(def)
end

local SLIME_MOVE_SPEED_MULT = 0.65
-- A base grows by floors of PADS_PER_FLOOR pads (CONTRACT.md §5.3). Row f lists, for each of floor f's pads in order,
-- the rebirths that open it (Economy.padRebirths). A pad open at 0 rebirths costs PAD_START_COSTS (the first
-- PADS_START are free); any other pad costs PAD_PRICE_SHARE of the rebirth after the one that opens it (Economy.padCost).
-- Adding a row adds a floor.
local PADS_PER_FLOOR = 8
local BASE_FLOORS = table.freeze({
	table.freeze({ padRebirths = table.freeze({ 0, 0, 0, 0, 0, 0, 0, 0 }) }),
	table.freeze({ padRebirths = table.freeze({ 1, 1, 2, 3, 4, 5, 6, 7 }) }),
	table.freeze({ padRebirths = table.freeze({ 8, 9, 10, 10, 11, 12, 13, 14 }) }),
	table.freeze({ padRebirths = table.freeze({ 15, 16, 17, 18, 20, 22, 24, 26 }) }),
})
local SPAWN_INTERVAL = 5 -- seconds between fountain drops
local RITUAL_MIN_PLAYERS = 2 -- Config.RITUAL.MIN_PLAYERS; also the number of stand spots
local WILD_BASE_LIFETIME = 75 -- seconds at the old pace

local Config = {
	RARITIES = table.freeze(RARITIES),
	MAX_TIER = #RARITIES,

	PATTERNS = table.freeze({ "Plain", "Spots", "Stripes", "Belly" }),
	EYES = table.freeze({ "Round", "Sleepy", "Angry", "Happy", "Cyclops", "Wide" }),
	MOUTHS = table.freeze({ "Smile", "Open", "Flat", "Fang" }),

	MIN_SIZE = 0.8,
	MAX_SIZE = 2.0,
	-- Mythic / Secret presentation (contract/slime-odds.md): a generated slime of these tiers is at least this big
	-- (Genome.sizeFloor) and lives this many WILD_LIFETIMEs in the wild (Spawner.wildLifetime). Other tiers: none / 1.
	TIER_SIZE_FLOOR = table.freeze({ [6] = 1.2, [7] = 1.4, [8] = 1.5, [9] = 1.6 }) :: { [number]: number },
	TIER_LIFETIME_MULT = table.freeze({ [6] = 1.5, [7] = 2, [8] = 2.5, [9] = 3 }) :: { [number]: number },

	-- World
	PLOT_COUNT = 8, -- one plot per player; server MaxPlayers = 8
	SLIME_BASE_DIAMETER = 3, -- studs at size 1.0 (ModelFactory)
	SLIME_MESH_ASSET_ID = 103340234939607, -- Jolt's slime package; server SlimeMesh, procedural fallback
	STATE_MIN_INTERVAL = 0.25, -- State snapshots are coalesced to at most 4/s per player
	LEADERBOARD_INTERVAL = 60,
	LEADERBOARD_SIZE = 10,
	LEADERBOARD_PAGE = 100, -- entries per GetSortedAsync page (the top 10 shows; the rest give players their rank)
	LEADERBOARD_RANK_DEPTH = 1000, -- how deep a refresh pages for the server's players' ranks; deeper = "1000+"
	LEADERBOARD_RANK_RESERVE = 8, -- GetSortedAsync budget a deeper page must leave for the next refreshes

	-- Economy
	STARTING_CASH = 25,
	PADS_START = 4,
	PADS_PER_FLOOR = PADS_PER_FLOOR,
	BASE_FLOORS = BASE_FLOORS,
	PADS_MAX = #BASE_FLOORS * PADS_PER_FLOOR,
	PAD_START_COSTS = table.freeze({ 250, 1000, 4000, 12000 }) :: { number }, -- pads PADS_START + 1.. that are open at 0 rebirths
	PAD_PRICE_SHARE = 0.25, -- a pad opened by rebirth R costs this share of rebirth R + 1 (Economy.padCost)
	PAD_SAME_REBIRTH_GROWTH = 1.5, -- each further pad opened by the same rebirth costs this many times the one before
	SELL_PRICE_SHARE = 0.3, -- a slime sells for this share of what the fountain charges for it (Economy.sellPrice)
	OFFLINE_RATE = 0.25, -- fraction of income earned while offline
	OFFLINE_CAP_SECONDS = 2 * 60 * 60, -- offline income stops accruing after 2 h
	WELCOME_BACK_MIN_SECONDS = 4 * 60 * 60, -- away at least this long = a welcome-back card on join

	-- Rebirth
	-- cash rebirth N costs (Economy.rebirthCost(N - 1)), set with the pacing sim (docs/economy-proposal.html)
	REBIRTH_COSTS = table.freeze({
		15_000,
		120_000,
		700_000,
		2_900_000,
		12_000_000,
		39_000_000,
		89_000_000,
		180_000_000,
		400_000_000,
		860_000_000,
		1_400_000_000,
		2_200_000_000,
		4_200_000_000,
		8_700_000_000,
		19_000_000_000,
		46_000_000_000,
		92_000_000_000,
		120_000_000_000,
		150_000_000_000,
		250_000_000_000,
		620_000_000_000,
		1_300_000_000_000,
		2_200_000_000_000,
		2_800_000_000_000,
		3_600_000_000_000,
		5_300_000_000_000,
		6_700_000_000_000,
		7_200_000_000_000,
		7_900_000_000_000,
		8_500_000_000_000,
	}) :: { number },
	-- income multiplier each rebirth adds, by band: rebirth n adds the `step` of the last band with `from` <= n
	REBIRTH_MULTIPLIER_STEPS = table.freeze({
		table.freeze({ from = 1, step = 0.5 }),
		table.freeze({ from = 11, step = 1 }),
		table.freeze({ from = 21, step = 1.5 }),
	}),
	MAX_REBIRTHS = #REBIRTH_SLIMES,
	REBIRTH_SLIMES = table.freeze(REBIRTH_SLIMES), -- species each rebirth needs and uses up, one list per level
	REBIRTH_TIERS = table.freeze(REBIRTH_TIERS), -- ranks (CONTRACT.md §8.8)

	-- Permanent upgrades (Request("BuyUpgrade", id)), goals and SlimeDex rewards (CONTRACT.md §8.8)
	UPGRADES = table.freeze(UPGRADES),
	GOALS = table.freeze(GOALS),
	DEX_MILESTONES = table.freeze({
		species = table.freeze(DEX_MILESTONES.species),
	}),
	PLOT_SKINS = table.freeze(PLOT_SKINS), -- plot skins unlocked by SlimeDex sets (CONTRACT.md §15)
	PLOT_SKIN_DEFAULT = "classic",
	PLOT_BASES = table.freeze(PLOT_BASES), -- plot bases unlocked by rebirths (CONTRACT.md §44)
	PLOT_BASE_DEFAULT = "jar",
	PET_SEATS = table.freeze(PET_SEATS), -- what the follow pet rides on (PetSeats, contract/pet-seats.md)
	PET_SEAT_DEFAULT = "cloud",

	-- Lock / steal
	JOIN_LOCK_SECONDS = 120,
	LOCK_SECONDS = 120,
	LOCK_SECONDS_PER_REBIRTH = 10, -- a lock lasts this much longer per rebirth, up to LOCK_MAX_SECONDS
	LOCK_MAX_SECONDS = 240, -- the longest single lock (4 min); locks never stack or extend
	-- B1: seconds a ProximityPrompt / UI button must be held for any important
	-- action (steal, buy, lock, pad, merge, claim, sell, rebirth). Free Grab, Open Shop, Talk stay instant.
	HOLD_CONFIRM_SECONDS = 0.8,
	-- After you drop a slime (Drop, a hit, dying) you can't pick any slime up for this long (Carry.grab).
	DROP_PICKUP_COOLDOWN = 1.5,
	TUTORIAL_STEAL_SKIP_SECONDS = 20, -- solo tutorial: Steal step skips itself after this long with nobody to steal from
	STEAL_REACH = 14, -- studs: max server-checked distance to grab a slime
	-- SlimeGuard (FEATURES.SlimeGuard, CONTRACT.md §41). Movement thresholds live in the shared MovementGuard defaults.
	SLIME_GUARD = table.freeze({
		ENFORCE = true, -- false = watch mode: flags are logged and add points, nothing else happens; true = steals bounce, pause, kick
		SAMPLE_SECONDS = 0.1, -- one position per player this often (the server's view tick)
		LAUNCH_SPEED = 150, -- studs/s allowed while a PvP launch / control window is open (PvpLaunch.guardActive)
		SERVER_MOVE_SECONDS = 1, -- after a server teleport or respawn the next second is not checked
		TELEPORT_COOLDOWN = 3, -- seconds after a teleport flag in which the player can't steal
		DEPOSIT_SPEED_SLACK = 1.5, -- a stolen slime may reach home at most this much faster than its carry speed allows
		BREATHER_SECONDS = 20, -- a victim's base locks this long after a slime is stolen from it
		UNDO_SECONDS = 600, -- a kick undoes the player's steals from this many seconds back
		LOG_PER_MINUTE = 20, -- log lines per player per minute at most
		POINTS = table.freeze({
			teleport = 3,
			lockedEntry = 3,
			earlyDeposit = 3,
			speed = 2,
			fly = 2,
		} :: { [string]: number }),
	}),
	SLAP_REACH = 10,
	SLAP_COOLDOWN = 1.5,
	-- The default melee Bat Tool (server/BatTool, every player, live, NOT behind FEATURES.PvP). A hit on anyone
	-- carrying a slime is the base slap (CarryDrop.slap: reach SLAP_REACH, cooldown SLAP_COOLDOWN, they drop it) plus a push.
	BAT = table.freeze({
		TOOL_NAME = "Bat",
		PUSH = 5, -- studs of knockback (PvpKnockbackRules.plan, capped by PVP.KNOCKBACK_MAX_PUSH)
		FACING_DOT = 0.3, -- the target must be in front: dot(look, direction to them) >= this (about 72 degrees each side)
		CLOSE_STUDS = 3, -- closer than this the facing check is skipped (hugging a thief)
		SWING_GAP = 0.4, -- seconds between swing events (a whiff never spends the SLAP_COOLDOWN)
	}),
	MAX_CARRY_SLOW = 0.6,
	BASE_WALK_SPEED = 16,

	-- Shop (permanent, kept on rebirth)
	SPEED_COIL_PRICE = 1500,
	SPEED_COIL_WALK_SPEED = 19, -- WalkSpeed while the coil is held (1.19x BASE_WALK_SPEED; boost +3, 25% of the old +12)

	-- Merge vat (VatState, TripleMerge, CONTRACT.md §21): three slimes of one rarity brew into one of a higher rarity
	VAT_SIZE = 3, -- spots in a plot's vat
	-- seconds one brew takes, by the rarity going in (before Quick brew)
	MERGE_BREW_SECONDS = table.freeze({ 300, 180, 420, 900, 1800, 3600, 5400, 7200, 9000 }) :: { number },
	TRIPLE_MERGE_JUMP_CHANCE = 0.2, -- chance the result is two rarities up (up to MERGE_JUMP_MAX_TIER)
	MERGE_MAX_TIER = 8, -- a random merge result is at most Celestial; three slimes of this tier or higher only merge in a recipe
	-- three slimes of `from` that share a shine brew a random `into` species (keeping the shine), from `rebirths`
	SHINE_RECIPE = table.freeze({ from = 7, into = 9, rebirths = 25 }),
	MERGE_JUMP_MAX_TIER = 5, -- a +2 jump lands on Legendary at most
	MERGE_ASSIST_CHANCE = 0.35, -- share of random merge results drawn from the species the player hasn't found
	TRIPLE_MERGE_SIZE_BONUS = 0.15, -- added to the parents' mean size
	-- a species earning x times its rarity's income (SlimeRoster INCOME) spawns x ^ this times less often within it
	SPECIES_RARITY_POWER = 4,
	JACKPOT_SHARE = 0.1, -- a jackpot species (SlimeRoster.jackpot) is this share of its rarity's drops, whatever else is in the pool
	-- Shines (weather mutations): a wild slime rolls at most one when it spawns. `weather` = only while that
	-- Config.WEATHER id is on (nil = any weather); `chance` per wild slime; income x `mult`. Ids are saved: never rename.
	SHINES = table.freeze({
		table.freeze({ id = "Gold", mult = 1.5, chance = 0.03, color = { 255, 205, 60 } }),
		table.freeze({ id = "Diamond", mult = 2, chance = 0.04, weather = "Snow", color = { 150, 230, 255 } }),
		table.freeze({ id = "Rainbow", mult = 4, chance = 0.02, weather = "Starfall", color = { 255, 120, 220 } }),
	}),
	BREWED_INCOME_MULT = 1.5, -- income x this for a slime the vat made (Slime.brewed = 1)
	RECIPE_INCOME_MULT = 2, -- income x this for a recipe hybrid the vat made (Slime.brewed = 2)

	-- Fountain (wild slime spawns)
	SPAWN_INTERVAL = SPAWN_INTERVAL,
	SLIME_MOVE_SPEED_MULT = SLIME_MOVE_SPEED_MULT,
	WILD_BASE_LIFETIME = WILD_BASE_LIFETIME,
	WILD_LIFETIME = math.round(WILD_BASE_LIFETIME / SLIME_MOVE_SPEED_MULT), -- 115: walk + hop slower, drain still at expiry
	DESPAWN_TELEGRAPH_SECONDS = 5, -- wild slimes warn this long before they expire (FEATURES.DespawnTelegraph)
	-- Despawn telegraph FX: a one-shot 3D sound with the poof (in the SFX group).
	DESPAWN_POOF_SOUND = true,
	DESPAWN_POOF_SOUND_ID = "rbxassetid://9125639751", -- Pro Sound Effects "Magic Poofs Short Breathy Bursts Wheezy Exhale"
	-- Wild slimes expire every few seconds near the fountain: at most one poof sound per this many seconds.
	DESPAWN_POOF_SOUND_GAP = 10,
	-- v13 rarity curve (CONTRACT.md §8.7): pity per server, Legendary+ drops are announced
	PITY_EPIC = 30, -- after this many drops without an Epic+, the next one is at least Epic
	PITY_LEGENDARY = 300, -- same for Legendary+
	SECRET_TIER = 7, -- Config.RARITIES tier of the Secret slimes (SlimeRoster.SECRET_TIER)
	RARE_ANNOUNCE_TIER = 5, -- wild drops of this tier or higher: Notify everyone + RareSpawn attributes
	FREE_DROP_CHANCE = 0.01, -- share of wild slimes that cost nothing to grab
	-- other wild slimes cost this many seconds of their base income, by rarity (Economy.wildPrice)
	WILD_PRICE_SECONDS = table.freeze({ 12, 600, 1500, 2400, 2400, 6000, 15000, 30000, 60000 }) :: { number },
	-- rebirths a player needs to grab a wild slime of each rarity from the fountain (stealing is never gated)
	CATCH_REBIRTHS = table.freeze({ 0, 0, 0, 0, 0, 5, 12, 18, 25 }) :: { number },
	-- a drop of at least this rarity is guaranteed once this many seconds pass without one (per server, on top of pity)
	GUARANTEE_SECONDS = table.freeze({ [5] = 5 * 60, [6] = 15 * 60 }) :: { [number]: number },

	-- Slime Rain event
	RAIN_INTERVAL = 60 * 60, -- design: hourly
	RAIN_FIRST_AT = 5 * 60,
	RAIN_DURATION = 3 * 60, -- design: 3 minutes
	RAIN_SPAWN_INTERVAL = 2.5, -- seconds between fountain drops during rain
	RAIN_LUCK = 5, -- rarity weights for tier >= 3 multiplied by this during rain

	-- Weekly event rotation (FEATURES.WeeklyEvents, CONTRACT.md §17). The whole schedule is a pure function
	-- of unix time (UTC), so every server agrees. Weeks run Monday 00:00 - Sunday 24:00 UTC (ISO weeks).
	-- On each week's Saturday, `TRAIT_START_HOUR` (UTC) a TRAITS[week % m] event runs for TRAIT_SECONDS
	-- (shorter than a day, so it never spills over); `luck` multiplies the rarity luck like a
	-- CycleModifier. WeeklyEvents clamps every value to MAX_MULTIPLIER whatever is written here.
	WEEKLY = table.freeze({
		TRAIT_WEEKDAY = 6, -- Saturday (0 = Sunday)
		TRAIT_START_HOUR = 18, -- UTC
		TRAIT_SECONDS = 2 * 60 * 60,
		TRAITS = table.freeze({
			table.freeze({ id = "lucky", label = "Lucky Saturday", icon = "🍀", luck = 1.5 }),
		}),
		MAX_MULTIPLIER = 2,
		SYNC_SECONDS = 60, -- the server re-checks the schedule at least this often
	}),

	-- Extras, each behind a flag (CONTRACT.md §2 Extras). false = fully off.
	FEATURES = table.freeze({
		DespawnTelegraph = true, -- wild slime models get DespawnAt before they expire; false = silent removal
		Habitats = true, -- pads turn into their slime's habitat (HABITATS.md); false = pads as before
		SlimeAnimations = true, -- slimes play the uploaded KeyframeSequences (MeshAssets.ANIMATIONS) once a probe track loads; false = procedural Motor6D motion (ui/SlimeMotor)
		CycleModifier = true, -- a server modifier (Luck Surge, Golden Hour) is rolled at each dawn and dusk of the DayNight cycle (CycleModifier); false = no modifier
		SlideCollision = true, -- invisible colliders along the FULL fountain slide, top to mouth (B6: players fell through above LOW_SLIDE_Y); false = low stretch only
		FriendsInBase = true, -- the owner's lock-button switch lets their Roblox friends in this server through a locked base's stopper and steal there (PlotGuests, CONTRACT.md §42); false = no switch, locks block friends like anyone
		FriendBonus = true, -- +FRIEND_BONUS_PER_FRIEND income per friend in the same server, up to FRIEND_BONUS_CAP (FriendBonus); false = no bonus
		Weather = true, -- Rain / Snow / Starfall cycle (WeatherService) and client visuals (WeatherFx); WEATHER.md
		GrowingSlimes = true, -- slimes on a pad grow over time (+GROWTH_MAX_INCOME_BONUS income at full growth, offline time counts, capped) (Growth); false = no growth, income and size unchanged
		AdminEvents = true, -- admin-only timed Luck surge and Slime Rain, chat command + MessagingService (AdminEvents, CONTRACT.md §12); false = never triggers
		CoopRitual = true, -- 2-4 players stand on the ritual circle for a timed "Blessed" income boost (Ritual, CONTRACT.md §13); false = no circle, no boost
		PlotSkins = true, -- plot skins unlocked by owning ~75 % of a SlimeDex set (PlotSkins, CONTRACT.md §15); false = no remote, State fields, plot attribute or visuals (risky: needs frame review)
		StealAlerts = true, -- v21 full steal alerts (StealAlert, CONTRACT.md §17): owner gets a red screen-edge flash, a repeating alarm, a direction arrow + world ping to the thief; the carrying thief gets a trail; a SLAP gets a hit effect; a "while you were away" notice on join from a capped saved steal log; false = the plain banner + toast only (needs frame review)
		WeeklyEvents = true, -- a timed Saturday trait event, a pure function of os.time (WeeklyEvents, CONTRACT.md §18); false = no event, no attribute
		FountainSplit = true, -- draft for Merijn's fountain collision choice (a): MeshSwap places the slime_fountain as 5 meshes (basin, dome, eave, silo, slide; same look) and the tower pieces collide as PreciseConvexDecomposition instead of the hand-placed Basin / Trim / Silo / Top colliders (SlideColliders stay); any piece failing to load keeps the single mesh and the colliders (CONTRACT.md §28, docs/COLLISION.md; needs a Studio walk + ball-drop test before it can ship)
		SlidePCD = true, -- the slide as a real collision mesh: MeshSwap makes fountain_split_slide PreciseConvexDecomposition (needs FountainSplit) and, once it is placed, FountainColliders drops the SlideColliders Post / Brace boxes it replaces; the floor slabs (the walk surface), rails and Skirt stay (docs/COLLISION.md); false = decor slide and every box
		FountainTiers = true, -- v19: the central fountain's look upgrades with the server's best rank (FountainTiers glow) and every slime family drops from it on every server, with no rank needed to catch one; false = one Meadow fountain, Classic drops only (needs frame review)
		Consumables = true, -- restocking Shop section: luck potion, weather totem on a server-wide CONSUMABLES_RESTOCK_SECONDS schedule (Consumables); false = no section, BuyConsumable refused
		ServerProfiler = false, -- dev tool, stays off in live (log + clock reads only help while profiling). v23: rolling per-system server timings, a one-line log every PROFILER.LOG_INTERVAL s and budget warnings (server/Profiler, CONTRACT.md §25); false = no clock reads, no log
		Audio = true, -- v23 SoundController: central SFX registry, Music / SFX SoundGroups, mute + volume, day/night ambience (ui/SoundController, ui/AudioLogic, CONTRACT.md §2 Extras); false = Notify sounds play as before, no groups, no ambience, no toggle
		PvP = true, -- v22 PvP fairness core (PvpRules, server/PvpService, CONTRACT.md §26, docs/PVP.md): rank-gated tools and fun items bought with cash, control limits; false = BuyPvpItem refused, no runtime state, no attributes, nothing saved changes
		Parade = true, -- wilds hop the goo-parade lane round the plaza into the goo drain (ParadeLane); false = landing band as before
		MysteryEggs = true, -- the fountain sometimes drops a Mystery Egg that incubates on a pad, can be stolen and hatches into a slime (MysteryEgg, EggKind, contract/mystery-egg.md); false = no egg drops (eggs already on plots still hatch)
		MoveSlime = true, -- E "Move" on your own pad slimes: pick one up and place it on another pad (swap if taken), Request MoveSlime (ui/SlimeMove); false = no Move prompt and MoveSlime is refused
		SlimeChoreo = true, -- species gaits and hops, lane beats and reactions to players (SlimePersona, ParadeChoreo, ui/SlimeGait, contract/slime-life.md); false = every slime glides the lane at one pace
		SlimeAlive = true, -- pad slimes fidget and greet you, put-downs drop in, a Move hops over, escapes race home sweating, the slide ride grins, jelly springs on top (ui/SlimeFidget, contract/slime-life.md "Alive motion"); false = pad slimes only breathe and glance, a Move snaps
		BaseShapes = false, -- choosable plot bases next to the skins: the goo jar tower, the Goo Factory (rebirth 20) and the Mushroom Pagoda (rebirth 25) (PlotBases, BaseShapes, CONTRACT.md §44); false = no remote, State fields or plot attribute, every plot is the jar
		SlimeGuard = true, -- anti-cheat for stealing (SlimeGuard, CONTRACT.md §41): movement checks, steal gate, deposit check, steal record, breather lock, locked-base intruders reported (never moved); false = none of it
		MoveGuardLog = false, -- log-only server movement check (MoveGuard, server/MoveWatch): counts root moves a player could not have walked and logs a rate-limited summary; never moves, kicks or releases anyone
	}),

	-- Movement guard (FEATURES.MoveGuardLog, shared/MoveGuard). Allowed displacement per sample:
	-- horizontal maxSpeed x dt x FACTOR + SLACK; up MAX_UP_SPEED x dt + SLACK; down MAX_FALL_SPEED x dt + SLACK.
	MOVE_GUARD = table.freeze({
		FACTOR = 1.5, -- headroom over the server's own walk speed (lag bursts, sample jitter)
		SLACK = 4, -- studs added to every sample (a late position update followed by its catch-up, uneven sample times)
		MAX_UP_SPEED = 100, -- studs/s going up (jump ~50, Bounce Pad 25 studs needs ~99)
		MAX_FALL_SPEED = 400, -- studs/s going down (free fall has no hard cap; two seconds of gravity)
		MAX_DT = 1, -- seconds; a longer gap between samples (server hitch) re-baselines instead of judging
		RESPAWN_ALLOW = 2, -- seconds after a new character appears (spawn pivot, join)
		TELEPORT_ALLOW = 1, -- seconds after a server teleport (drop tube, rescue, eject, floor evacuate)
		LAUNCH_ALLOW = 3, -- seconds after a PvP launch (arc flight, landing, client rubber-band)
		LOG_INTERVAL = 30, -- seconds between summary lines
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
		AMBIENT_VOLUME = 0.15, -- loop volume inside the Music group (low on purpose)
		AMBIENT_FADE_SECONDS = 4, -- crossfade day <-> night
		SFX_MIN_GAP = 0.05, -- seconds between two plays of the same SFX name
		SFX_MAX_LIVE = 4, -- most copies of one SFX name sounding at once
		SFX_MAX_SECONDS = 15, -- a Sound that never reports Ended is cleaned up after this
		-- SFX registry name -> Notify sound name (Sounds.IDS) or a direct asset id.
		SFX = table.freeze({
			buy = "Cash",
			collect = "Deposit",
			steal = "Stolen",
			merge = "Merge",
			rebirth = "Rebirth",
			alarm = "Alarm",
			error = "ErrorSoft",
			click = "rbxasset://sounds/button.wav",
		}),
		-- Ambience: a looped bed per time of day, plus a night one-shot played now and then over it.
		AMBIENT_DAY_ID = "rbxassetid://91856264327473", -- birds: own 20 s seamless loop (Merijn's upload)
		AMBIENT_NIGHT_ID = "rbxassetid://9112764573", -- "Crickets Night 3" (Pro Sound Effects, 64 s loop), kept low
		AMBIENT_NIGHT_VOLUME = 0.07, -- the crickets bed sits under the owl
		-- "Owl Hooting Reverberant Several 1 (SFX)", Pro Sound Effects, public domain, 16 s. Not a seamless loop,
		-- so it plays whole, once per gap, never looped.
		NIGHT_ONESHOT_ID = "rbxassetid://9117182190",
		NIGHT_ONESHOT_MIN_SECONDS = 20, -- gap between owl calls, picked at random in MIN..MAX
		NIGHT_ONESHOT_MAX_SECONDS = 45,
		NIGHT_ONESHOT_VOLUME = 0.3, -- inside the Music group; louder than the beds, it is rare
		NIGHT_ONESHOT_SPEED_JITTER = 0.05, -- PlaybackSpeed 1 +- this, so repeats don't sound identical
		NIGHT_ONESHOT_MIN_LEVEL = 0.9, -- calls only once the night has (nearly) faded in
		-- Music (APM library, public domain): one track by time of day, the boss track during a boss fight / haul.
		-- These are finished cues, looped whole. Inside the Music group, under the player's Music slider.
		MUSIC = table.freeze({
			day = "rbxassetid://1836753678", -- "Little Moment Of Calm" (120 s)
			night = "rbxassetid://1837212983", -- "Sleepy Time" (65 s)
			boss = "rbxassetid://1836675698", -- "Silly Chase" (145 s)
		}),
		MUSIC_VOLUME = 0.22, -- quiet on purpose: music sits far under the game
		MUSIC_FADE_SECONDS = 3,
		-- Weather beds (Pro Sound Effects loops), by Constants.WEATHER_ATTRIBUTE value. The day / night bed ducks
		-- to WEATHER_DUCK while one plays.
		WEATHER_BEDS = table.freeze({
			Rain = "rbxassetid://9112857056", -- "Rain On Window 2" (46 s loop)
			Snow = "rbxassetid://9114057104", -- "Desert Wind Whistley Light Gusts 1" (37 s), soft cold wind
		}),
		WEATHER_BED_VOLUME = 0.18,
		WEATHER_DUCK = 0.3,
		-- Thunder during rain: one of these Sounds.IDS names now and then, at a random gap in MIN..MAX seconds.
		THUNDER = table.freeze({ "Thunder1", "Thunder2", "Thunder3" }),
		THUNDER_VOLUME = 0.3,
		THUNDER_MIN_SECONDS = 25,
		THUNDER_MAX_SECONDS = 60,
		-- 3D one-shots (SoundController.play with `at`): full volume within MIN, silent past MAX studs.
		SFX_3D_MIN_DISTANCE = 12,
		SFX_3D_MAX_DISTANCE = 110,
		SFX_SPEED_JITTER = 0.08, -- playVariant: PlaybackSpeed 1 +- this
		SFX_TRIM_FADE = 0.2, -- seconds a trimmed sound (Sounds.TRIM) fades out over
		-- State-driven cues (ui/SoundCues).
		CUES = table.freeze({}),
		-- World sounds driven by workspace attributes: boss attacks, egg hatches, rituals, the fountain (ui/WorldAudio).
		WORLD = table.freeze({
			CULL_DISTANCE = 150, -- studs from the camera: boss / egg / ritual one-shots farther away are skipped
			BOSS_MAX_DISTANCE = 150, -- boss sounds (3D) are heard within this many studs
			EGG_MAX_DISTANCE = 80, -- hatch show sounds (3D)
			RITUAL_MAX_DISTANCE = 80, -- ritual spot / done one-shots (3D)
			LATE_SECONDS = 0.4, -- a timed cue seen more than this long after its moment is dropped, not played late
			FORGET_SECONDS = 30, -- seconds a played cue key is remembered (so a re-sent attribute never replays it)
			FIND_EVERY = 1, -- seconds between looks for the boss model, the ritual circle and the fountain
			-- Looped 3D beds, in the Music group (the Music slider covers them).
			FOUNTAIN_ID = "rbxassetid://9120557315", -- plaza fountain water
			FOUNTAIN_VOLUME = 0.25,
			FOUNTAIN_MIN_DISTANCE = 12, -- full volume inside this many studs of the pool
			FOUNTAIN_MAX_DISTANCE = 45, -- silent past this
			-- Pro Sound Effects "Magic Force Field Constant 1": hums at the orb while the ritual charges.
			RITUAL_HUM_ID = "rbxassetid://9116386800",
			RITUAL_HUM_VOLUME = 0.35,
			RITUAL_HUM_FADE_SECONDS = 0.8, -- fade in when the charge starts, out when it ends
			RITUAL_HUM_MIN_DISTANCE = 8,
			RITUAL_HUM_MAX_DISTANCE = 70,
		}),
		-- Slime voices, pickup / put-down and footsteps (ui/SlimeAudio, ui/Footsteps).
		SLIME = table.freeze({
			-- Slime sounds are 3D at the slime and only for slimes this close to the camera (studs).
			MAX_DISTANCE = 35,
			SLIME_GAP = 5, -- seconds: one slime squishes or blips at most once in this long
			MAX_PER_SECOND = 1, -- squishes + blips across all slimes in any one second (nearest win)
			LAND_VOLUME = 0.5, -- a hop or fidget landing (SlimeSquish), on top of Sounds.VOLUME
			BLIP_CHANCE = 0.15, -- share of fidgets / new emotes that get a SlimeBlip
			BLIP_GAP = 8, -- seconds between two blips across all slimes
			BLIP_VOLUME = 0.5,
			CARRY_VOLUME = 1, -- SlimePickup / SlimePutdown (always play within MAX_DISTANCE)
			-- Pitch by size (the model's Size attribute, Config.MIN_SIZE..MAX_SIZE): bigger slimes sound lower.
			-- PlaybackSpeed = SPEED_AT_SIZE_1 - SPEED_PER_SIZE * (size - 1), clamped to SPEED_MIN..SPEED_MAX.
			SPEED_AT_SIZE_1 = 1.1,
			SPEED_PER_SIZE = 0.3,
			SPEED_MIN = 0.75,
			SPEED_MAX = 1.3,
			-- Footsteps: Humanoid.FloorMaterial name -> Sounds.VARIANTS group. Other floors keep Roblox's own step.
			STEP_MATERIALS = table.freeze({
				Grass = "StepGrass",
				LeafyGrass = "StepGrass",
				Ground = "StepGrass",
				Mud = "StepGrass",
				Snow = "StepSnow",
				Glacier = "StepSnow",
				Ice = "StepSnow",
			}),
			-- Ground snow tints the grass but never changes its material: from this snow cover (0..1) on, a
			-- set listed here steps as the set it maps to.
			SNOW_COVER_MIN = 0.5,
			SNOW_STEPS = table.freeze({ StepGrass = "StepSnow" }),
			STRIDE_STUDS = 3.5, -- studs per step at STRIDE_WALK_SPEED
			STRIDE_WALK_SPEED = 16, -- Humanoid.WalkSpeed the stride above is for; faster walkers take longer strides
			STRIDE_MIN = 2.5,
			STRIDE_MAX = 6,
			STEP_MIN_SPEED = 1.5, -- studs / s: slower than this a character stands still (no steps)
			FIRST_STEP_SHARE = 0.4, -- share of a stride to the first step after standing or landing
			OTHERS_DISTANCE = 40, -- studs from the camera: other players' steps within this
			STEP_VOLUME = 0.6, -- the local player's steps
			OTHERS_STEP_VOLUME = 0.35, -- other players' steps
		}),
	}),

	-- A slime being stolen leaves a see-through copy on its pad until the steal ends (server/StealGhost).
	STEAL_GHOST_TRANSPARENCY = 0.6,

	-- Full steal alerts (FEATURES.StealAlerts, StealAlert / ui/StealAlertFx). Client timings in seconds.
	STEAL_ALERT = table.freeze({
		FLASH_SECONDS = 1.2, -- red screen-edge flash when a theft starts
		FLASH_PULSES = 2,
		ALARM_REPEAT = 3, -- the toast already plays the first Alarm; it sounds again this often ...
		ALARM_REPEATS = 2, -- ... at most this many extra times per theft
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
		NEAR_MAX = 16, -- near rigs with the full life (reactions, emotes, effects); further near ones draw as mid
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

	-- Boss event (server/BossEvent, Shared.BossFight, contract/boss-event.md). Seconds unless noted.
	BOSS = table.freeze({
		FIRST_AT = 8 * 60, -- first arrival after server start
		INTERVAL = 20 * 60, -- between arrivals
		WARNING_SECONDS = 60, -- heads-up before the boss arrives
		RAIN_GAP = 3 * 60, -- skip when Slime Rain runs or is due this close to the arrival
		SKIP_DELAY = 5 * 60, -- a skipped arrival moves this much later
		FIGHT_SECONDS = 150,
		HAUL_SECONDS = 90,
		LINGER_SECONDS = 6, -- the won / failed result stays in State.boss
		PRIORITY_SECONDS = 5, -- head start for the top contributor in the haul
		POINTS_PER_PLAYER = 110, -- meter target = this x players on the server (dazed hits count DAZED_MULTIPLIER)
		HIT_GAP = 0.4, -- one meter point per player per this many seconds
		HIT_REACH = 13, -- studs from the swinger's root to the boss Body (about the boss's radius at SCALE + a bat's reach)
		DRAIN_PER_SECOND = 0.02, -- share of the target lost per second with nobody hitting
		DRAIN_GRACE = 1, -- seconds without a hit before the drain starts
		STAGE_EVERY = 0.25, -- meter share between stages (it speeds up at each; no slimes drop)
		MVP_BONUS = 0.5, -- Boss Champion boost, for the player who brings the boss home: +50 % income ...
		MVP_SPEED = 0.15, -- ... and +15 % walk speed (Shop.walkSpeed) ...
		MVP_SECONDS = 5 * 60, -- ... for this long (runtime only, never saved; a new win restarts the timer)
		CARRY_SLOW = 0.5, -- carrier walks at BASE_WALK_SPEED x (1 - this): half speed
		SCALE = 1.5, -- model scale in the fight phase (a MAX_SIZE boss mesh is about 9 studs wide at 1)
		SPOT_ANGLE = math.rad(35), -- boss spot around the fountain centre (radians, 0 = +X): the widest stretch inside the lane
		SPOT_RADIUS = 51, -- studs: between the landing ring and the parade lane
		WANDER_ARC = math.rad(45), -- the boss roams within this either side of SPOT_ANGLE (BossArea; the lane and drain fence it in)
		WANDER_CLEARANCE = 6.25, -- studs from its centre to the parade lane's edge and the goo drain's lip
		-- Moves (Shared.BossChoreo): it strolls between stops, turns to look at players, and attacks from a stop.
		STROLL_SPEED = 4.5, -- studs / s at full stride (x the stage speed-up)
		STROLL_MIN = 8, -- studs: shortest stroll
		STROLL_MAX = 18, -- studs: longest stroll
		STROLL_EASE = 0.7, -- seconds it takes to set off and to stop
		STROLL_TOWARD = 0.7, -- chance a stroll heads for the players' middle (else anywhere in the area)
		LOOK_SECONDS = table.freeze({ 0.9, 1.8 }), -- a stop to look at the nearest player
		ARRIVE_SECONDS = 1.6, -- it drops onto the boss spot and splats
		ARRIVE_FALL = 0.6, -- of which the fall
		ARRIVE_HEIGHT = 24, -- studs it drops from
		WINDUP_SECONDS = 1.2, -- the telegraph before an attack
		LEG_WINDUP_SECONDS = 0.7, -- the shorter telegraph before each next leg of a multi-leg charge
		HOP_SECONDS = 0.55, -- a hops attack's leap
		HOP_HEIGHT = 6, -- studs high it leaps
		CHARGE_EASE = 0.25, -- seconds a charge takes to reach full speed and to stop
		CHARGE_MIN = 8, -- studs: a charge aimed this short (off the thin boss area) runs along the area instead
		STRIKE_SECONDS = 0.7, -- a cone or the spit's throw
		RING_DELAY = 0.35, -- the stomp lands this long into a ring attack, then the ring runs out
		SPIT_FLIGHT = 0.7, -- seconds a goo spit flies before it lands
		DAZED_SECONDS = 2.5, -- after every attack
		RISE_HEIGHT = 9, -- studs it floats up while its guards are out
		RISE_SECONDS = 1, -- the float up
		LAND_SECONDS = 0.8, -- the float down
		GUARD_SECONDS = 12, -- longest a guard call lasts (it lands when every guard is popped)
		SHRINK_SECONDS = 0.6, -- the meter is full: it shrinks to carry size over this long before it can be grabbed
		MOVE_PIVOT_INTERVAL = 0.2, -- seconds between the server's pivots of the boss Body (clients draw every frame)
		-- Attacks (Shared.BossAttacks): dodge the telegraphed attack, then punish it while it is dazed.
		FIRST_ATTACK = 3, -- seconds after it lands before its first attack
		ATTACK_GAP = table.freeze({ 2.5, 4 }), -- seconds from one attack's daze to the next windup (÷ the stage speed-up)
		STAGE_SPEEDUP = 0.1, -- +10 % move and attack pace at every STAGE_EVERY of the meter
		PHASE_AT = 0.5, -- meter share from which its `phase` attacks join its `start` ones
		DAZED_MULTIPLIER = 2, -- a hit while it is dazed counts this many meter points
		STUN_SECONDS = 1.5, -- a player hit by an attack can't land bat hits or slaps for this long
		HIT_ARC = 8, -- studs high an attack's knockback throws a player
		RING_WIDTH = 3.5, -- studs: how thick the stomp's goo ring is (jump over it)
		CONE_HIT_AT = 0.25, -- seconds into a cone attack its push lands
		PUDDLE_RADIUS = 4.5, -- studs: a goo spit puddle; standing in it slows you
		SPIT_SPREAD = 6, -- studs: a spit with nobody to aim at lands this far round the boss
		ATTACK_RANGE = 40, -- studs from the boss a spit or a jelly-rain drop may aim at a player (further = ignored)
		STRIKE_HEIGHT = 9, -- studs a player's root may be above the arena floor and still be struck (roofs, the slide: no)
		GUARD_RADIUS = 11, -- studs from the boss its guards stand
		GUARD_REACH = 8, -- studs from a swinger's root to a guard for a bat hit
		GUARD_POINTS = 2, -- meter points per popped guard
		GUARD_SIZE = 3.4, -- studs: a guard's body (a mini copy of its boss)
		-- Per boss species: `start` attacks from the first one, `phase` from PHASE_AT. Kinds: ring { radius, speed, push },
		-- spit { count, slowSeconds, slow }, guards { count }, cone { radius, angle (degrees), push },
		-- charge { distance, speed, width, push }, vent { multiplier } (passive: hits on its back while dazed),
		-- hops { count, distance, radius, speed, push } (it leaps at you, a small ring on every landing).
		-- Signature options, one per boss: ring `waves` (+ `waveGap` s, `waveSpeedUp` x), guards `heal` (meter share it
		-- gets back if its guards outlast the call), charge `bounces` (it charges again at the top hitter) with
		-- `sideways` + `backAndForth` (a crab's scuttle), spit `burst` { delay, radius, speed, push } (each puddle
		-- bursts into a ring), guards `rain` { every, count, delay, radius, speed, push } (while it floats it drops goo
		-- on the nearest players: a red circle, then a splash ring a moment after it lands).
		MOVES = table.freeze({
			goozilla = table.freeze({
				-- signature: a double stomp, the second ring faster
				start = table.freeze({
					bossAttack({
						kind = "ring",
						radius = 22,
						speed = 22,
						push = 40,
						waves = 2,
						waveGap = 0.7,
						waveSpeedUp = 1.4,
					}),
					bossAttack({ kind = "spit", count = 3, slowSeconds = 5, slow = 0.5 }),
				}),
				phase = table.freeze({
					bossAttack({ kind = "cone", radius = 20, angle = 110, push = 45 }),
					bossAttack({
						kind = "ring",
						radius = 26,
						speed = 24,
						push = 45,
						waves = 3,
						waveGap = 0.6,
						waveSpeedUp = 1.3,
					}),
				}),
			}),
			queen_jelly = table.freeze({
				-- signature: royal guards; while they stand she rains jelly on you, and if they outlast the call she
				-- heals 15 % of the meter
				start = table.freeze({
					bossAttack({
						kind = "guards",
						count = 3,
						heal = 0.15,
						rain = table.freeze({ every = 1.5, count = 2, delay = 0.6, radius = 7, speed = 16, push = 32 }),
					}),
					bossAttack({ kind = "cone", radius = 18, angle = 90, push = 45 }),
				}),
				phase = table.freeze({
					bossAttack({ kind = "ring", radius = 24, speed = 20, push = 40 }),
					bossAttack({ kind = "spit", count = 4, slowSeconds = 5, slow = 0.5 }),
				}),
			}),
			mecha_goo = table.freeze({
				-- signature: a ricochet charge, then it turns and rams the top hitter again
				start = table.freeze({
					bossAttack({ kind = "charge", distance = 35, speed = 32, width = 8, push = 50, bounces = 1 }),
					bossAttack({ kind = "ring", radius = 20, speed = 26, push = 40 }),
				}),
				phase = table.freeze({
					bossAttack({ kind = "spit", count = 4, slowSeconds = 5, slow = 0.5 }),
					bossAttack({ kind = "charge", distance = 35, speed = 36, width = 8, push = 50, bounces = 2 }),
					bossAttack({ kind = "vent", multiplier = 3 }),
				}),
			}),
			klawdius = table.freeze({
				start = table.freeze({
					bossAttack({ kind = "cone", radius = 16, angle = 70, push = 35 }),
					-- signature: a sideways scuttle, back and forth three times
					bossAttack({
						kind = "charge",
						distance = 24,
						speed = 30,
						width = 7,
						push = 40,
						sideways = true,
						backAndForth = true,
						bounces = 2,
					}),
				}),
				phase = table.freeze({
					bossAttack({ kind = "spit", count = 4, slowSeconds = 5, slow = 0.55 }),
					bossAttack({ kind = "ring", radius = 22, speed = 22, push = 40 }),
					bossAttack({ kind = "vent", multiplier = 3 }),
				}),
			}),
			pumpking = table.freeze({
				-- signature: bouncing stomps, three hops at you with a ring on every landing
				start = table.freeze({
					bossAttack({ kind = "hops", count = 3, distance = 7, radius = 12, speed = 24, push = 32 }),
					bossAttack({ kind = "spit", count = 3, slowSeconds = 5, slow = 0.5 }),
				}),
				phase = table.freeze({
					bossAttack({
						kind = "guards",
						count = 3,
						rain = table.freeze({ every = 1.6, count = 2, delay = 0.6, radius = 7, speed = 16, push = 30 }),
					}),
					bossAttack({ kind = "hops", count = 4, distance = 8, radius = 14, speed = 26, push = 35 }),
					bossAttack({ kind = "vent", multiplier = 3 }),
				}),
			}),
			goomancer = table.freeze({
				start = table.freeze({
					-- signature: rune puddles that burst into a ring a moment after they land
					bossAttack({
						kind = "spit",
						count = 4,
						slowSeconds = 6,
						slow = 0.5,
						burst = table.freeze({ delay = 1.6, radius = 10, speed = 16, push = 35 }),
					}),
					bossAttack({ kind = "cone", radius = 20, angle = 100, push = 40 }),
				}),
				phase = table.freeze({
					bossAttack({ kind = "ring", radius = 28, speed = 26, push = 45 }),
					bossAttack({ kind = "vent", multiplier = 3 }),
				}),
			}),
		}),
		-- every tier-6 boss twice and each Secret once per lap
		ROTATION = table.freeze({
			"goozilla",
			"queen_jelly",
			"klawdius",
			"pumpking",
			"mecha_goo",
			"goozilla",
			"queen_jelly",
			"klawdius",
			"pumpking",
			"goomancer",
		}),
		SECRET_FOUNTAIN_TIER = 4, -- a Secret-tier boss needs this fountain tier (Starlight)
		SECRET_FALLBACK = "goozilla",
	}),

	-- Boss badges kept in the save (Shared.BossBadges, contract/boss-event.md), not Roblox badges. `trigger` + `value`
	-- are read by BossBadges.reached: "hits" / "hauls" / "mvps" (data.boss counters), "win" (wins of `species`),
	-- "wins" (wins of every species summed). A new boss species gets its own "win" line.
	BOSS_BADGES = table.freeze({
		table.freeze({
			key = "BossBrawler",
			name = "Boss Brawler",
			description = "Land a hit on a boss.",
			trigger = "hits",
			value = 1,
		}),
		table.freeze({
			key = "BossGoozilla",
			name = "Goozilla Tamer",
			description = "Carry Goozilla home yourself.",
			trigger = "win",
			value = 1,
			species = "goozilla",
		}),
		table.freeze({
			key = "BossQueenJelly",
			name = "Dethroned",
			description = "Carry Queen Jelly home yourself.",
			trigger = "win",
			value = 1,
			species = "queen_jelly",
		}),
		table.freeze({
			key = "BossKlawdius",
			name = "Shell Shocked",
			description = "Carry Klawdius home yourself.",
			trigger = "win",
			value = 1,
			species = "klawdius",
		}),
		table.freeze({
			key = "BossPumpking",
			name = "Pumpkin Smasher",
			description = "Carry Pumpking home yourself.",
			trigger = "win",
			value = 1,
			species = "pumpking",
		}),
		table.freeze({
			key = "BossGoomancer",
			name = "Spellbreaker",
			description = "Carry Goomancer home yourself.",
			trigger = "win",
			value = 1,
			species = "goomancer",
		}),
		table.freeze({
			key = "BossMechaGoo",
			name = "Scrap Metal",
			description = "Carry Mecha Goo home yourself.",
			trigger = "win",
			value = 1,
			species = "mecha_goo",
		}),
		table.freeze({
			key = "BossHauler",
			name = "Heavy Lifter",
			description = "Carry a boss home yourself.",
			trigger = "hauls",
			value = 1,
		}),
		table.freeze({
			key = "BossHunter10",
			name = "Boss Hunter",
			description = "Carry 10 bosses home.",
			trigger = "wins",
			value = 10,
		}),
	}),

	-- Day / night (DayNight)
	DAY_LENGTH = 12 * 60, -- seconds per full day
	DAY_FRACTION = 0.7, -- share of the cycle that is daytime (06:30-17:30)

	-- Server modifier per day / night phase (FEATURES.CycleModifier). Weighted roll at each dawn
	-- and dusk; `luck` multiplies the rarity weight of tier >= 3 (like RAIN_LUCK).
	-- "None" must stay (it is the quiet phase).
	MODIFIERS = table.freeze({
		table.freeze({ name = "None", label = "None", weight = 5, luck = 1 }),
		table.freeze({ name = "LuckSurge", label = "Luck Surge", weight = 3, luck = 2 }),
		table.freeze({ name = "GoldenHour", label = "Golden Hour", weight = 1, luck = 1.5 }),
	}),

	-- Live admin events (FEATURES.AdminEvents, CONTRACT.md §12). Only these UserIds (plus the place
	-- owner when the creator is a user) may trigger one. Chat: "/event luck 10" (minutes).
	ADMIN_USER_IDS = table.freeze({} :: { number }),
	ADMIN_EVENTS = table.freeze({
		table.freeze({ id = "luck", label = "Luck Event", icon = "🍀", luck = 3 }),
		table.freeze({ id = "rain", label = "Slime Rain", icon = "🌧", luck = 1 }), -- Spawner.forceRain
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
		SERVER_COOLDOWN = 600, -- seconds the circle rests after a ritual
		PLAYER_COOLDOWN = 600, -- seconds before the same player can count again
		BLESS_SECONDS = 180,
		BONUS = table.freeze({ [2] = 0.3, [3] = 0.2, [4] = 0.3 }), -- Blessed income bonus by participants; tiers above SPOTS stay as data but can't be reached (Ritual.bonus caps at SPOTS)
	}),

	-- Follow-pet passives (Perks.petPassive, CONTRACT.md §14). The kind comes from the favourite slime's tier;
	-- value = tier * perTier, capped per kind. All additive and server-side.
	PET_PASSIVES = table.freeze({
		KIND_BY_TIER = table.freeze({ "income", "income", "luck", "luck", "income", "luck", "luck", "income", "luck" }),
		KINDS = table.freeze({
			income = table.freeze({ icon = "💰", word = "income", perTier = 0.01, cap = 0.08 }), -- x(1 + value) income
			luck = table.freeze({ icon = "🍀", word = "luck", perTier = 0.01, cap = 0.06 }), -- added to Perks.luckChance
		}),
	}),

	-- Lucky Charm show (contract/lucky-charm.md): the pad shows the slime as caught, then as its new species.
	LUCKY_SHOW = table.freeze({
		MORPH_SECONDS = 1.2, -- the pad shows the caught slime this long, then the promoted one (and the owner hears Lucky)
		FX_SECONDS = 5, -- the model on the pad carries LuckyAt / LuckyFromTier this long
	}),

	-- Wild Mystery Eggs (FEATURES.MysteryEggs, contract/mystery-egg.md). Each KINDS entry: `id` (saved, never rename),
	-- `name` (shown as "<name> Mystery Egg"), `tier` (the Config.RARITIES tier the egg shows: label colour, lifetime,
	-- carry slowdown), `weight` (share of egg drops), `hatchSeconds` (incubation on a pad, real time), `announce` (server
	-- toast on spawn), `rebirths` (a Config.REBIRTH_TIERS threshold: fewer rebirths can't grab or steal this kind,
	-- EggKind.grabBlock) and `drops` (tier weights of the slime inside). A wild egg is free to grab and can't be sold.
	MYSTERY_EGG = table.freeze({
		DROP_CHANCE = 0.015, -- share of fountain drops that are an egg
		RAIN_MULT = 3, -- DROP_CHANCE multiplier during Slime Rain
		MAX_WILD = 1, -- loose eggs at once (on the lane or dropped)
		RAIN_MAX_WILD = 2,
		WARM_SPEED = 1.5, -- incubation speed while the owner stands in their HomeZone
		HATCH_ANNOUNCE_TIER = 5, -- a hatch of this tier or higher is toasted to the whole server (at the reveal)
		LUCKY_CHANCE = 0.05, -- share of eggs whose slime inside is one tier higher than its roll (capped at Secret)
		HATCH_SIZE_MIN = 1.0, -- a hatchling's size is HATCH_SIZE_MIN + up to HATCH_SIZE_SPAN (wild: MIN_SIZE + 0.6)
		HATCH_SIZE_SPAN = 0.6,
		HATCH_BURST_SECONDS = 3, -- the pad keeps showing the egg this long after a hatch (the show's wobble), then the slime
		HATCH_REVEAL_SECONDS = 4.2, -- the hatch toasts go out and the slime's label returns this long after the hatch
		HATCH_FX_SECONDS = 8, -- the model on the pad carries HatchedAt / HatchedFrom / HatchLucky / HatchTier this long
		KINDS = table.freeze({
			table.freeze({
				id = "speckled",
				name = "Speckled",
				tier = 3,
				weight = 60,
				hatchSeconds = 3 * 60,
				pity = 8, -- lucky meter: the 8th hatch in a row without the top tier gets it
				rebirths = 0,
				announce = false,
				drops = table.freeze({
					{ tier = 2, weight = 55 },
					{ tier = 3, weight = 35 },
					{ tier = 4, weight = 10 },
				}),
			}),
			table.freeze({
				id = "shiny",
				name = "Shiny",
				tier = 4,
				weight = 27,
				hatchSeconds = 6 * 60,
				pity = 8, -- lucky meter: the 8th hatch in a row without the top tier gets it
				rebirths = 1,
				announce = false,
				drops = table.freeze({
					{ tier = 3, weight = 50 },
					{ tier = 4, weight = 40 },
					{ tier = 5, weight = 10 },
				}),
			}),
			table.freeze({
				id = "golden",
				name = "Golden",
				tier = 5,
				weight = 10,
				hatchSeconds = 10 * 60,
				pity = 12, -- lucky meter: the 12th hatch in a row without the top tier gets it
				rebirths = 3,
				announce = true,
				drops = table.freeze({ { tier = 4, weight = 55 }, { tier = 5, weight = 40 }, { tier = 6, weight = 5 } }),
			}),
			table.freeze({
				id = "cosmic",
				name = "Cosmic",
				tier = 6,
				weight = 3,
				hatchSeconds = 15 * 60,
				pity = 12, -- lucky meter: the 12th hatch in a row without the top tier gets it
				rebirths = 6,
				announce = true,
				drops = table.freeze({ { tier = 5, weight = 60 }, { tier = 6, weight = 35 }, { tier = 7, weight = 5 } }),
			}),
		}),
	}),
	-- Restocking consumables (FEATURES.Consumables, competitor-gaps.md #13). The stock of slot
	-- floor(unix time / CONSUMABLES_RESTOCK_SECONDS) is a pure function of the slot, so every server
	-- agrees. `max` is the most a player may buy per restock (the roll is minStock..maxStock; 0 = sold out
	-- this slot). `price` is x the rebirth multiplier. Ids are the BuyConsumable argument: never rename.
	CONSUMABLES_RESTOCK_SECONDS = 5 * 60,
	CONSUMABLE_HELD_MAX = 99, -- most of one consumable a player can hold (a purchase over it is refused)
	CONSUMABLES = table.freeze({
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
	WEATHER_ORDER = table.freeze({ "Clear", "Rain", "Snow", "Starfall" }),
	WEATHER = table.freeze({
		Clear = table.freeze({
			displayName = "Clear",
			weight = 4,
			minSeconds = 240,
			maxSeconds = 420,
		}),
		Rain = table.freeze({
			displayName = "Rain",
			weight = 3,
			minSeconds = 120,
			maxSeconds = 210,
		}),
		Snow = table.freeze({
			displayName = "Snow",
			weight = 3,
			minSeconds = 120,
			maxSeconds = 210,
		}),
		Starfall = table.freeze({
			displayName = "Starfall",
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
	GROWTH_LABEL_GAP = 0.4, -- studs between the top of the slime and the bottom edge of its floating tag (contract/slime-labels.md)

	-- Daily reward
	DAILY_BASE = 100,
	DAILY_STREAK_CAP = 7,
	DAILY_QUESTS = table.freeze({ count = 3, pool = table.freeze(DAILY_QUEST_POOL) }),

	-- Redeem codes (CONTRACT.md §10). Keys are UPPERCASE; players type any case.
	-- reward: { kind = "cash", amount } or { kind = "boost", mult, minutes };
	-- expiresAt = unix seconds (nil = never). Once per player, kept in the save.
	CODES = table.freeze({
		WELCOME = table.freeze({ reward = table.freeze({ kind = "cash", amount = 50 }) }),
		SLIMEBOOST = table.freeze({ reward = table.freeze({ kind = "boost", mult = 2, minutes = 10 }) }),
		LAUNCH = table.freeze({
			reward = table.freeze({ kind = "cash", amount = 100 }),
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

	-- World shops (CONTRACT.md §27): studs from the character's HumanoidRootPart to the stand's Counter,
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

	-- PvP (FEATURES.PvP, CONTRACT.md §26, docs/PVP.md). PvP works everywhere: there are no safe zones.
	PVP = table.freeze({
		CONTROL_MAX_SECONDS = 2, -- longest hard crowd control (hold, dance, bounce) on one player
		SLOW_MAX_SECONDS = 3, -- longest slow (a stacked Squirter slow included, counted from its first hit)
		CONTROL_IMMUNITY_SECONDS = 3, -- after any control ends, the target cannot be controlled again for this long
		MIN_COOLDOWN = 1.5, -- no tool re-arms faster than this (the Squirter's cooldown is per tank)
		PRICE_FACTOR_TOOL = 0.03, -- price = factor x Economy.rebirthCost(gate), pacing sim tunes
		PRICE_FACTOR_FUN = 0.01,
		PRICE_FACTOR_TRAP = 0.006, -- one Goo Trap charge (used up when it catches someone)
		PRICE_MIN = 100,
		-- Knockback: the push is capped, the arc is capped, and the landing point stays inside the map.
		KNOCKBACK_MAX_PUSH = 40, -- studs (the Royal Glove power punch, 26 x CHARGE_PUSH); gloves push 2.4-5x the Bat
		KNOCKBACK_ARC_HEIGHT = 8, -- studs of vertical arc at most (Royal Glove)
		KNOCKBACK_DEFAULT_ARC = 3, -- studs of arc of a glove row without its own `arc`
		KNOCKBACK_BOUNDS_MARGIN = 20, -- studs kept clear of the map edge (covers the friction-boost overshoot of a max push)
		KNOCKBACK_SECONDS = 0.35, -- the launch covers the push in this long
		KNOCKBACK_FRICTION_BOOST = 1, -- horizontal launch speed x this; 1 = the target lands about `push` studs away (Studio-measured: PlatformStand keeps friction off during the push)
		KNOCKBACK_MAX_SPEED_Y = 110, -- studs/s: client-side cap on a launch's vertical speed (Bounce Pad 25 studs needs ~99)
		LAUNCH_GUARD_SECONDS = 5, -- after a PvP launch / while under control the void guard (Rescue.PVP_SAFE_Y) is armed
		KNOCKBACK_CONTROL_SECONDS = 0.6, -- a knockback counts as control (PvpRules.applyControl), then immunity
		CHARGE_SECONDS = 0.5, -- hold the button this long for UsePvpItem `charged` (power punch, mega confetti pop, fireworks volley)
		CHARGE_PUSH = 1.5, -- power punch: push x this
		CHARGE_COOLDOWN = 2, -- power punch: cooldown x this
		TRAP_PLACE_RANGE = 40, -- studs: how far from the owner a Goo Trap may be thrown
		TRAP_MAX_HELD = 5, -- charges per trap tier a player may hold (buying a 6th is refused)
		TRAP_MAX_LIVE = 5, -- live traps per player over all tiers (a 6th removes the oldest)
		TRAP_LIFETIME_SECONDS = 180, -- a placed trap is gone after this long if it caught nobody
		BLOB_GRAVITY = 60, -- studs/s^2: the goo blob's arc (server hit test and the client particle use the same)
		SPLAT_RADIUS = 3, -- studs: the slippery splat a missed blob leaves
		SPLAT_SECONDS = 5, -- how long a missed blob's splat stays
		SPLAT_SLOW = 0.3, -- splat: speed taken away
		SPLAT_SLOW_SECONDS = 1, -- splat: how long the slip lasts
		SPLAT_MAX = 6, -- splats / pools per shooter at once (the oldest goes)
		FX_SECONDS = 1, -- client FX from PvpEvent "Effect" live at most this long (nothing persistent, no server parts)
		MAP_BOUNDS = table.freeze({ minX = -320, maxX = 320, minZ = -320, maxZ = 320 }), -- WorldBorder.GROUND_HALF = 320, Ground centred on the origin
	}),
	PVP_TOOLS = table.freeze(PVP_TOOLS),
	-- Fun item tunables (CONTRACT.md §26.8, server/PvpFun, Shared.PvpFunRules, ui/PvpFunFx). Studs, seconds, studs/s.
	PVP_FUN = table.freeze({
		AIM_RANGE = 40, -- a thrown / placed fun item lands at most this far from the user
		THROW_SPEED = 42, -- horizontal speed of a lobbed balloon / dance bomb
		THROW_MIN_SECONDS = 0.35, -- shortest lob flight
		THROW_MAX_SECONDS = 1.1, -- longest lob flight
		LANDING_WINDOW = 0.6, -- a landing still catches players this long after it
		CONFETTI = table.freeze({
			RANGE = 22, -- the pop bursts this far along the aim
			RADIUS = 10, -- the rain covers this far around the burst
			MEGA_RADIUS = 16,
			STICK_SECONDS = 4, -- confetti stays on a player this long
		}),
		BALLOON = table.freeze({
			SPLASH_RADIUS = 7,
			PAINT_SECONDS = 10,
			SPLATS_MAX = 8, -- ground splats per client
		}),
		BUBBLES = table.freeze({
			COUNT = 5, -- bubbles per stream
			SPACING = 0.18, -- seconds between bubbles
			SPEED = 10, -- along the aim
			RISE = 1.5, -- upward drift
			LIFETIME = 3.5,
			SIZE = 2.6, -- bubble diameter
			RADIUS = 2.6, -- a root this close touches a bubble
			LIFT = 7, -- a bubbled player floats this high
			POP_RANGE = 40, -- other players this close may click a bubble to pop it
			STREAMS_MAX = 8, -- live streams on the server (the oldest goes)
			SLIME_FLOAT_SECONDS = 2.5, -- a wild slime a bubble touches floats this long (client only)
		}),
		BOUNCE_PAD = table.freeze({
			SECONDS = 60, -- a pad lives this long
			RADIUS = 3.5, -- stepping this close to the centre bounces
			HEIGHT = 18, -- everyone but the owner bounces this high
			RETRIGGER = 1.2, -- the same player bounces again after this
		}),
		HAMMER = table.freeze({
			AIM_RADIUS = 5, -- the bonked player / slime is this close to the aim point
			COMBO_HITS = 3,
			COMBO_WINDOW = 3.5, -- the combo hits land within this
			COMBO_PUSH_SCALE = 1.5,
			SLIME_SQUASH_SECONDS = 1.2, -- a slime's squash, wobble and spring (client)
		}),
		HATS = table.freeze({
			RANGE = 40,
			HIT_RADIUS = 3,
			SPEED = 70, -- the flying hat (client)
			MAX_STACK = 3,
			SLIME_SECONDS = 20, -- a missed hat hops around as a hat-slime this long (client)
			SLIMES_MAX = 6, -- hat-slimes per client
		}),
		DANCE = table.freeze({
			RADIUS = 4.5, -- the disco bubble is ~9 studs across
			SECONDS = 4, -- it stays this long; players walking in also dance
		}),
		FIREWORKS = table.freeze({
			HEIGHT = 60, -- the burst is this high above the launch point
			FLIGHT = 1.1, -- rocket rise time (client)
			VOLLEY = 3, -- rockets at full charge
			VOLLEY_GAP = 0.3, -- seconds between volley rockets (client)
			SPREAD = 10, -- volley rockets fan out this far (client)
			CHEER_RADIUS = 40, -- wild slimes this close to the launch cheer-hop (client)
			SECONDS = 4, -- the burst and its goo rain (client)
		}),
		FX_MAX = 24, -- client: fun effects alive at once (the oldest goes)
		PROXIES_MAX = 6, -- client: squash / float proxies at once
		FX_RANGE = 220, -- client: farther fun effects are skipped (fireworks are seen from anywhere)
	}),

	-- Persistence
	SAVE_VERSION = 9, -- CONTRACT.md §8.9 (v6: settings + normalised plotSkin / stealLog, SaveData.migrateV5; v7: mutation fields stripped, SaveData.migrateV6; v8: Goo Trap charges, SaveData.migrateV7; v9: boss record replaces trophies, SaveData.migrateV8)
	AUTOSAVE_INTERVAL = 60,
	SESSION_STALE_SECONDS = 180, -- a session lock older than this may be taken over
	SAVE_DRAIN_SECONDS = 20, -- a load waits at most this long for the same player's saves still in flight
	SAVE_DRAIN_STEP = 0.25, -- seconds between checks while a load waits for those saves
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
