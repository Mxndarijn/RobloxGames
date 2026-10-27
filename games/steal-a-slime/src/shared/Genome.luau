--!strict
--[[
	Genome

	A slime is a small plain table (its genome) that is saved as-is and turned
	into Parts by the server's SlimeModel builder. Rarity tier, colour, size,
	pattern, eyes and mouth are all rolled from an Rng so a seed
	reproduces the slime. Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local EggKind = if script then require(script.Parent.EggKind) else require("./EggKind")
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
	egg: EggKind.Egg?, -- still a Mystery Egg (contract/mystery-egg.md): the rest of the record is the slime inside
	brewed: number?, -- made in the merge vat: 1 = random merge (BREWED_INCOME_MULT), 2 = recipe (RECIPE_INCOME_MULT)
	shine: string?, -- a Config.SHINES id (weather mutation): income x its mult
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
	return Genome.pickWeighted(Genome.speciesPool(tier, families, extra), roll)
end

-- How often a species spawns within its rarity, relative to the others: a species earning x more is
-- x ^ SPECIES_RARITY_POWER times rarer.
function Genome.speciesWeight(entry: SlimeRoster.Entry): number
	return 1 / entry.income ^ Config.SPECIES_RARITY_POWER
end

-- One entry of `list`, weighted by Genome.speciesWeight, for a roll in [0, 1); nil for an empty list.
function Genome.pickWeighted(list: { SlimeRoster.Entry }, roll: number): SlimeRoster.Entry?
	if #list == 0 then
		return nil
	end
	-- A jackpot takes Config.JACKPOT_SHARE of the pool whatever else is in it; the rest share by speciesWeight.
	local plain, jackpots = 0, 0
	for _, entry in list do
		if entry.jackpot then
			jackpots += 1
		else
			plain += Genome.speciesWeight(entry)
		end
	end
	local share = if plain > 0 and jackpots > 0
		then Config.JACKPOT_SHARE / (1 - Config.JACKPOT_SHARE) * plain / jackpots
		else 1
	local function weight(entry: SlimeRoster.Entry): number
		return if entry.jackpot then share else Genome.speciesWeight(entry)
	end
	local total = 0
	for _, entry in list do
		total += weight(entry)
	end
	local at = math.clamp(roll, 0, 1) * total
	for _, entry in list do
		at -= weight(entry)
		if at < 0 then
			return entry
		end
	end
	return list[#list]
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

-- Spawning species of `tier` in every family, roster order.
local function speciesOfTier(tier: number): { SlimeRoster.Entry }
	local out = {}
	for _, entry in SlimeRoster.ROSTER do
		if entry.kind == "spawn" and entry.tier == tier then
			table.insert(out, entry)
		end
	end
	return out
end

-- Gives `slime` a species of its own tier (`roll` in [0, 1) picks it), with that species' name and colour. In place.
-- A slime without a species keeps its random name and colour.
local function matchSpecies(slime: Slime, roll: number)
	local list = speciesOfTier(slime.tier)
	local old = slime.species and SlimeRoster.get(slime.species)
	if not old then
		return
	end
	if #list == 0 then
		slime.species = nil
		return
	end
	local entry = list[math.clamp(math.floor(roll * #list) + 1, 1, #list)]
	slime.species = entry.id
	if slime.name == old.name then
		slime.name = entry.name
	end
	local look = SlimeLooks.get(entry.id)
	if look then
		slime.color = { look.color[1], look.color[2], look.color[3] }
	end
end

-- Lucky Charm: one rarity higher, and a species of that rarity (`roll` picks it), so a species never shows a rarity
-- it doesn't have. Grows to the new tier's size floor. In place; false (unchanged) for an egg or a MAX_TIER slime.
function Genome.promote(slime: Slime, roll: number): boolean
	if slime.egg or slime.tier >= Config.MAX_TIER then
		return false
	end
	slime.tier += 1
	slime.size = roundSize(math.max(slime.size, Genome.sizeFloor(slime.tier)))
	matchSpecies(slime, roll)
	return true
end

-- Stable [0, 1) from a slime id, so repairing the same save always picks the same species.
local function idRoll(id: string): number
	local h = 0
	for i = 1, #id do
		h = (h * 31 + string.byte(id, i)) % 1000003
	end
	return h / 1000003
end

-- Growth 0..1 that counts: 0 with FEATURES.GrowingSlimes off or no/garbage `growth`.
function Genome.growthFraction(slime: Slime): number
	local g = slime.growth
	if not Config.FEATURES.GrowingSlimes or type(g) ~= "number" or g ~= g then
		return 0
	end
	return math.clamp(g, 0, 1)
end

-- Cash/sec before the rebirth multiplier (incl. growth); an egg earns nothing.
function Genome.baseIncome(slime: Slime): number
	if slime.egg then
		return 0
	end
	local growth = 1 + Config.GROWTH_MAX_INCOME_BONUS * Genome.growthFraction(slime)
	return Genome.rarity(slime.tier).income
		* slime.size
		* growth
		* Genome.brewMultiplier(slime)
		* Genome.shineMultiplier(slime)
		* SlimeRoster.incomeBonus(slime.species)
end

-- The Config.SHINES row of a slime's shine, or nil.
function Genome.shine(slime: Slime): { id: string, mult: number, chance: number, weather: string?, color: { number } }?
	local id = slime.shine
	if id == nil then
		return nil
	end
	for _, row in Config.SHINES do
		if row.id == id then
			return row :: any
		end
	end
	return nil
end

-- Income multiplier of a slime's shine (1 without one).
function Genome.shineMultiplier(slime: Slime): number
	local row = Genome.shine(slime)
	return if row then row.mult else 1
end

-- Income multiplier a vat-made slime keeps for life: BREWED_INCOME_MULT, or RECIPE_INCOME_MULT for a recipe hybrid.
function Genome.brewMultiplier(slime: Slime): number
	return if slime.brewed == 2
		then Config.RECIPE_INCOME_MULT
		elseif slime.brewed == 1 then Config.BREWED_INCOME_MULT
		else 1
end

-- "Rare Lop"; an egg shows its egg name ("Golden Mystery Egg"), never the slime inside.
function Genome.displayName(slime: Slime): string
	local kind = EggKind.of(slime)
	if kind then
		return EggKind.displayName(kind)
	end
	local rarity = Genome.rarity(slime.tier).name
	local shine = if Genome.shine(slime) then `{slime.shine} ` else ""
	return `{shine}{rarity} {slime.name}`
end

-- Whether this record is still an unhatched Mystery Egg.
function Genome.isEgg(slime: Slime): boolean
	return EggKind.isEgg(slime)
end

function Genome.copy(slime: Slime): Slime
	local c = table.clone(slime)
	c.color = table.clone(slime.color)
	if slime.egg then
		c.egg = table.clone(slime.egg)
	end
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
	local slime: Slime = {
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
		egg = EggKind.sanitize(raw.egg),
		brewed = if raw.brewed == 1 or raw.brewed == 2 then raw.brewed else nil,
		shine = if type(raw.shine) == "string" and Genome.shine({ shine = raw.shine } :: any) then raw.shine else nil,
	}
	-- A species whose rarity differs from the slime's (a Lucky Charm catch kept its old species) becomes one of the
	-- slime's rarity: the rarity and income stay, the type matches them.
	local entry = slime.species and SlimeRoster.get(slime.species)
	if entry and entry.tier ~= slime.tier and not slime.egg then
		matchSpecies(slime, idRoll(id))
	end
	return slime
end

return Genome
