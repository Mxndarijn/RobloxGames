--!strict
--[[
	Genome

	A slime is a small plain table (its genome) that is saved as-is and turned
	into Parts by the server's SlimeModel builder. Rarity tier, colour, size,
	pattern, eyes and mouth are all rolled from an Rng so a seed
	reproduces the slime. Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")
local SlimeLooks = if script then require(script.Parent.SlimeLooks) else require("./SlimeLooks")
local SlimeRoster = if script then require(script.Parent.SlimeRoster) else require("./SlimeRoster")

export type Slime = {
	id: string,
	name: string,
	tier: number,
	color: { number }, -- { r, g, b } integers 0..255
	size: number, -- MIN_SIZE..MAX_SIZE, two decimals
	pattern: string,
	eyes: string,
	mouth: string,
	pad: number?, -- home pad on the owner's plot (nil while wild)
	species: string?, -- SlimeRoster id (wild spawns since v28; nil for older/merged slimes)
	growth: number?, -- 0..1 (FEATURES.GrowingSlimes, Growth); nil = not grown yet (old saves, wild, merged slimes)
	keep: boolean?, -- kept by its owner: never merged (CONTRACT.md §21.1); nil = not kept
}

export type GenerateOptions = {
	id: string,
	tier: number?, -- force a tier instead of rolling one
	luck: number?, -- multiplies weights of tier >= 3 (Slime Rain)
	minTier: number?, -- pity: never roll below this tier
	families: { string }?, -- open FountainTiers family ids: their species join the Classic pool (Genome.speciesPool)
	extraSpecies: { SlimeRoster.Entry }?, -- more entries for the pool (only those of the rolled tier count)
}

local NAME_START = { "Bl", "Gl", "Sq", "Wob", "J", "Goo", "Pud", "Sl", "Fl", "Z", "Mu", "Dr" }
local NAME_MID = { "o", "oo", "u", "i", "ee", "a", "ub", "ib" }
local NAME_END = { "rp", "p", "sh", "bble", "lly", "ber", "dle", "mp", "x", "nk", "zz", "b" }

local Genome = {}

local function clampInt(n: number, lo: number, hi: number): number
	return math.clamp(math.floor(n + 0.5), lo, hi)
end

local function roundSize(n: number): number
	return math.clamp(math.floor(n * 100 + 0.5) / 100, Config.MIN_SIZE, Config.MAX_SIZE)
end

-- Smallest size a generated slime of `tier` may have (Config.TIER_SIZE_FLOOR; 0 = no floor).
function Genome.sizeFloor(tier: number): number
	return Config.TIER_SIZE_FLOOR[tier] or 0
end

local function contains(list: { string }, value: any): boolean
	return table.find(list, value) ~= nil
end

function Genome.rarity(tier: number): Config.Rarity
	return Config.RARITIES[math.clamp(math.floor(tonumber(tier) or 1), 1, Config.MAX_TIER)]
end

-- Rolls a rarity tier. `luck` multiplies the weight of tiers >= 3; tiers below
-- `minTier` (pity) can't be rolled.
function Genome.rollTier(roll: number, luck: number?, minTier: number?): number
	local weights = {}
	for i, r in Config.RARITIES do
		weights[i] = if r.tier >= 3 then r.weight * (luck or 1) else r.weight
		if minTier and r.tier < minTier then
			weights[i] = 0
		end
	end
	return Rng.weightedIndex(weights, roll)
end

-- Spawning species a drop of `tier` picks from: Classic, then each of `families` (open FountainTiers ids) in order,
-- then the `extra` entries of that tier. nil / empty `families` = Classic only.
function Genome.speciesPool(tier: number, families: { string }?, extra: { SlimeRoster.Entry }?): { SlimeRoster.Entry }
	local pool = SlimeRoster.forTier(tier)
	if families then
		for _, family in families do
			local members = SlimeRoster.forTier(tier, family)
			table.move(members, 1, #members, #pool + 1, pool)
		end
	end
	if extra then
		for _, entry in extra do
			if entry.tier == tier then
				table.insert(pool, entry)
			end
		end
	end
	return pool
end

-- Picks a species of `tier` uniformly from Genome.speciesPool(tier, families, extra); nil for a tier outside the
-- rarities or an empty pool.
function Genome.rollSpecies(
	tier: number,
	roll: number,
	families: { string }?,
	extra: { SlimeRoster.Entry }?
): SlimeRoster.Entry?
	if tier < 1 or tier > Config.MAX_TIER then
		return nil
	end
	local list = Genome.speciesPool(tier, families, extra)
	if #list == 0 then
		return nil
	end
	return list[math.clamp(math.floor(roll * #list) + 1, 1, #list)]
end

function Genome.rollName(rng: Rng.Rng): string
	return rng:pick(NAME_START) .. rng:pick(NAME_MID) .. rng:pick(NAME_END)
end

function Genome.generate(rng: Rng.Rng, options: GenerateOptions): Slime
	local tier = if options.tier
		then math.clamp(math.floor(options.tier), 1, Config.MAX_TIER)
		else Genome.rollTier(rng:float(), options.luck, options.minTier)
	-- Bright, saturated colours: one channel high, one low, one random.
	local channels = { rng:int(200, 255), rng:int(30, 90), rng:int(40, 255) }
	local order = rng:int(1, 6)
	local perms = { { 1, 2, 3 }, { 1, 3, 2 }, { 2, 1, 3 }, { 2, 3, 1 }, { 3, 1, 2 }, { 3, 2, 1 } }
	local p = perms[order]
	local species = Genome.rollSpecies(tier, rng:float(), options.families, options.extraSpecies)
	-- A named type wears its own colour (SlimeLooks); the random roll above is
	-- still drawn so the rest of the genome stays seed-stable.
	local look = species and SlimeLooks.get(species.id)
	local color = if look
		then { look.color[1], look.color[2], look.color[3] }
		else { channels[p[1]], channels[p[2]], channels[p[3]] }
	local slime: Slime = {
		id = options.id,
		name = if species then species.name else Genome.rollName(rng),
		tier = tier,
		color = color,
		size = roundSize(math.max(Config.MIN_SIZE + rng:float() * 0.6, Genome.sizeFloor(tier))),
		pattern = rng:pick(Config.PATTERNS),
		eyes = rng:pick(Config.EYES),
		mouth = rng:pick(Config.MOUTHS),
		pad = nil,
		species = if species then species.id else nil,
	}
	return slime
end

-- Growth 0..1 that counts: 0 with FEATURES.GrowingSlimes off or no/garbage `growth`.
function Genome.growthFraction(slime: Slime): number
	local g = slime.growth
	if not Config.FEATURES.GrowingSlimes or type(g) ~= "number" or g ~= g then
		return 0
	end
	return math.clamp(g, 0, 1)
end

-- Cash/sec before the rebirth multiplier (incl. growth).
function Genome.baseIncome(slime: Slime): number
	local growth = 1 + Config.GROWTH_MAX_INCOME_BONUS * Genome.growthFraction(slime)
	return Genome.rarity(slime.tier).income * slime.size * growth
end

function Genome.displayName(slime: Slime): string
	local rarity = Genome.rarity(slime.tier).name
	return `{rarity} {slime.name}`
end

function Genome.copy(slime: Slime): Slime
	local c = table.clone(slime)
	c.color = table.clone(slime.color)
	return c
end

-- Turns untrusted data (old saves, corrupted entries) into a valid slime or nil.
function Genome.sanitize(raw: any): Slime?
	if type(raw) ~= "table" then
		return nil
	end
	local id = raw.id
	if type(id) ~= "string" or #id == 0 or #id > 64 then
		return nil
	end
	local tier = tonumber(raw.tier)
	if not tier or tier ~= tier then
		return nil
	end
	local color = { 200, 255, 200 }
	if type(raw.color) == "table" then
		for i = 1, 3 do
			local c = tonumber(raw.color[i])
			if c and c == c then
				color[i] = clampInt(c, 0, 255)
			end
		end
	end
	local size = tonumber(raw.size) or 1
	if size ~= size then
		size = 1
	end
	local name = if type(raw.name) == "string" and #raw.name > 0 and #raw.name <= 32 then raw.name else "Blob"
	local pad = tonumber(raw.pad)
	if pad and (pad ~= pad or pad < 1 or pad > Config.PADS_MAX) then
		pad = nil
	end
	local growth = tonumber(raw.growth)
	if growth and (growth ~= growth or growth <= 0) then
		growth = nil
	end
	return {
		id = id,
		name = name,
		tier = clampInt(tier, 1, Config.MAX_TIER),
		color = color,
		size = roundSize(size),
		pattern = if contains(Config.PATTERNS, raw.pattern) then raw.pattern else "Plain",
		eyes = if contains(Config.EYES, raw.eyes) then raw.eyes else "Round",
		mouth = if contains(Config.MOUTHS, raw.mouth) then raw.mouth else "Smile",
		pad = if pad then math.floor(pad) else nil,
		species = if type(raw.species) == "string" and SlimeRoster.get(raw.species) then raw.species else nil,
		growth = if growth then math.floor(math.min(growth, 1) * 1e4 + 0.5) / 1e4 else nil,
		keep = if raw.keep == true then true else nil,
	}
end

return Genome
