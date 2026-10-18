--!strict
--[[
	Genome

	A slime is a small plain table (its genome) that is saved as-is and turned
	into Parts by the server's SlimeModel builder. Rarity tier, colour, size,
	pattern, eyes, mouth and mutation are all rolled from an Rng so a seed
	reproduces the slime. Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")
local SlimeLooks = if script then require(script.Parent.SlimeLooks) else require("./SlimeLooks")
local SlimeRoster = if script then require(script.Parent.SlimeRoster) else require("./SlimeRoster")
local Weather = if script then require(script.Parent.Weather) else require("./Weather")

export type Slime = {
	id: string,
	name: string,
	tier: number,
	color: { number }, -- { r, g, b } integers 0..255
	size: number, -- MIN_SIZE..MAX_SIZE, two decimals
	pattern: string,
	eyes: string,
	mouth: string,
	mutation: string, -- primary (highest multiplier) of `mutations`; "None" when it is empty. Kept for visuals, dex keys and old saves
	mutations: { string }?, -- every mutation (Config.MUTATIONS / COMBOS names, at most Config.MAX_MUTATIONS); nil = just `mutation`
	pad: number?, -- home pad on the owner's plot (nil while wild)
	species: string?, -- SlimeRoster id (wild spawns since v28; nil for older/merged slimes)
	growth: number?, -- 0..1 (FEATURES.GrowingSlimes, Growth); nil = not grown yet (old saves, wild, merged slimes)
	keep: boolean?, -- kept by its owner: never merged (CONTRACT.md §21.1); nil = not kept
}

export type GenerateOptions = {
	id: string,
	tier: number?, -- force a tier instead of rolling one
	mutationChance: number?, -- default Config.DROP_MUTATION_CHANCE
	luck: number?, -- multiplies weights of tier >= 3 (Slime Rain)
	minTier: number?, -- pity: never roll below this tier
	weeklyMutation: string?, -- WeeklyEvents boost: this mutation gets `weeklyBonus` extra roll range
	weeklyBonus: number?,
	family: string?, -- FountainTiers family id: the species comes from that family (Classic when it has none at the tier)
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

local function contains(list: { string }, value: any): boolean
	return table.find(list, value) ~= nil
end

function Genome.rarity(tier: number): Config.Rarity
	return Config.RARITIES[math.clamp(math.floor(tonumber(tier) or 1), 1, Config.MAX_TIER)]
end

export type MutationInfo = { name: string, displayName: string, multiplier: number }

-- A single mutation or a combo (Config.COMBOS) by save id.
function Genome.mutationInfo(name: any): MutationInfo?
	for _, m in Config.MUTATIONS do
		if m.name == name then
			return m
		end
	end
	for _, m in Config.WEATHER_MUTATIONS do
		if m.name == name then
			return m
		end
	end
	for _, c in Config.COMBOS do
		if c.name == name then
			return c
		end
	end
	for _, c in Config.WEATHER_COMBOS do
		if c.name == name then
			return c
		end
	end
	return nil
end

-- Player-facing mutation name for a save id ("Lava" -> "Syrup"). Unknown ids
-- and "None" come back unchanged.
function Genome.mutationDisplayName(name: string): string
	local m = Genome.mutationInfo(name)
	return if m then m.displayName else name
end

function Genome.mutationMultiplier(name: string): number
	local m = Genome.mutationInfo(name)
	return if m then m.multiplier else 1
end

-- Every mutation of a slime as a fresh list (empty = none). Slimes built before
-- the list existed (or by hand) fall back to the single `mutation` field.
function Genome.mutationList(slime: { mutation: string, mutations: { string }? }): { string }
	local list = slime.mutations
	-- A list that no longer matches `mutation` is stale (something set the single field): trust the field.
	if type(list) == "table" and Genome.primaryMutation(list) == slime.mutation then
		return table.clone(list)
	end
	return if slime.mutation ~= "None" and slime.mutation ~= nil then { slime.mutation } else {}
end

-- The strongest mutation of a list ("None" when empty): the legacy `mutation` field.
function Genome.primaryMutation(list: { string }): string
	local best, bestMult = "None", 0
	for _, name in list do
		local mult = Genome.mutationMultiplier(name)
		if mult > bestMult then
			best, bestMult = name, mult
		end
	end
	return best
end

-- Total value multiplier of a mutation list: the product of its entries.
function Genome.mutationsMultiplier(list: { string }): number
	local total = 1
	for _, name in list do
		total *= Genome.mutationMultiplier(name)
	end
	return total
end

-- Sets both the list and the primary `mutation` of a slime in one go.
function Genome.setMutations(slime: Slime, list: { string })
	slime.mutations = list
	slime.mutation = Genome.primaryMutation(list)
end

local function comboOf(a: string, b: string): Config.Combo?
	for _, list in { Config.COMBOS, Config.WEATHER_COMBOS } do
		for _, c in list do
			if (c.a == a and c.b == b) or (c.a == b and c.b == a) then
				return c
			end
		end
	end
	return nil
end

-- Fuses every combo pair in the list (repeats: a combo can fuse again). New list.
function Genome.fuseCombos(list: { string }): { string }
	local out = table.clone(list)
	local changed = true
	while changed do
		changed = false
		for i = 1, #out do
			for j = i + 1, #out do
				local combo = comboOf(out[i], out[j])
				if combo then
					out[i] = combo.name
					table.remove(out, j)
					changed = true
					break
				end
			end
			if changed then
				break
			end
		end
	end
	return out
end

-- Adds `name` to a list: ignored if already there or "None"/unknown; fuses combos;
-- left unchanged when it would not fit under Config.MAX_MUTATIONS. New list.
function Genome.addMutation(list: { string }, name: string): { string }
	if name == "None" or not Genome.mutationInfo(name) or table.find(list, name) then
		return table.clone(list)
	end
	local out = table.clone(list)
	table.insert(out, name)
	out = Genome.fuseCombos(out)
	if #out > Config.MAX_MUTATIONS then
		return table.clone(list)
	end
	return out
end

-- With FEATURES.MutationStacking a mutated slime may roll more mutations: per free
-- slot STACK_MUTATION_CHANCE (two draws each). No draw at all when it carries none or the flag is off.
function Genome.stackMutations(list: { string }, rng: Rng.Rng): { string }
	if not Config.FEATURES.MutationStacking or #list == 0 then
		return list
	end
	local out = list
	for _ = #list + 1, Config.MAX_MUTATIONS do
		local extra = Genome.rollMutation(rng:float(), rng:float(), Config.STACK_MUTATION_CHANCE)
		if extra == "None" then
			break
		end
		out = Genome.addMutation(out, extra)
	end
	return out
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

-- Weather bonus (FEATURES.WeatherMutations): the current weather's mutation and extra roll chance,
-- cached and refreshed from Weather.Changed so a roll does no lookup.
local weatherMutation: string? = nil
local weatherBonus = 0
local weatherConnection: { Disconnect: (any) -> () }? = nil

local function refreshWeather()
	local w = Weather.data(Weather.getCurrent())
	if Config.FEATURES.WeatherMutations and w and w.mutation and w.chanceBonus > 0 then
		weatherMutation, weatherBonus = w.mutation, w.chanceBonus
	else
		weatherMutation, weatherBonus = nil, 0
	end
end

-- Idempotent (re-binding replaces the old listener). Runs once at load; tests call it again after Weather.reset().
function Genome.bindWeather()
	if weatherConnection then
		weatherConnection:Disconnect()
	end
	weatherConnection = Weather.Changed:Connect(refreshWeather)
	refreshWeather()
end

-- The (mutation, extra chance) the current weather adds to rolls; nil, 0 when none.
function Genome.weatherBoost(): (string?, number)
	return weatherMutation, weatherBonus
end

-- Returns "None" unless `chanceRoll < chance`, then picks a mutation by weight. While a weather with a
-- mutation is current, the next `chanceBonus` of the roll range (chance <= roll < chance + bonus) lands on
-- that weather's mutation, so its chance is raised and no other mutation's is.
-- `weeklyMutation` / `weeklyBonus` (optional, WeeklyEvents) add one more window of `weeklyBonus` right after the
-- weather one, so the week's mutation is raised the same way and no other mutation's chance changes.
function Genome.rollMutation(
	chanceRoll: number,
	pickRoll: number,
	chance: number,
	weeklyMutation: string?,
	weeklyBonus: number?
): string
	if chanceRoll >= chance then
		local edge = chance
		if weatherMutation and chanceRoll < edge + weatherBonus then
			return weatherMutation
		end
		if weatherMutation then
			edge += weatherBonus
		end
		if weeklyMutation and chanceRoll < edge + (weeklyBonus or 0) then
			return weeklyMutation
		end
		return "None"
	end
	local weights = {}
	for i, m in Config.MUTATIONS do
		weights[i] = m.weight
	end
	return Config.MUTATIONS[Rng.weightedIndex(weights, pickRoll)].name
end

-- Alias of mutationDisplayName (v28 name).
Genome.mutationDisplay = Genome.mutationDisplayName

-- Picks a roster species of `tier` (uniform within the tier).
-- `family` (FountainTiers id) picks from that family's types instead; a tier it has none at (Secret) stays Classic.
function Genome.rollSpecies(tier: number, roll: number, family: string?): SlimeRoster.Entry?
	if tier < 1 or tier > Config.MAX_TIER then
		return nil
	end
	local list = SlimeRoster.forTier(tier, family)
	if #list == 0 and family then
		list = SlimeRoster.forTier(tier)
	end
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
	local chance = options.mutationChance or Config.DROP_MUTATION_CHANCE
	local mutation = Genome.rollMutation(rng:float(), rng:float(), chance, options.weeklyMutation, options.weeklyBonus)
	-- Bright, saturated colours: one channel high, one low, one random.
	local channels = { rng:int(200, 255), rng:int(30, 90), rng:int(40, 255) }
	local order = rng:int(1, 6)
	local perms = { { 1, 2, 3 }, { 1, 3, 2 }, { 2, 1, 3 }, { 2, 3, 1 }, { 3, 1, 2 }, { 3, 2, 1 } }
	local p = perms[order]
	local species = Genome.rollSpecies(tier, rng:float(), options.family)
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
		size = roundSize(Config.MIN_SIZE + rng:float() * 0.6),
		pattern = rng:pick(Config.PATTERNS),
		eyes = rng:pick(Config.EYES),
		mouth = rng:pick(Config.MOUTHS),
		mutation = mutation,
		mutations = if mutation == "None" then {} else { mutation },
		pad = nil,
		species = if species then species.id else nil,
	}
	-- Stack rolls come last so a seed's other traits (and unmutated slimes) are unchanged.
	Genome.setMutations(slime, Genome.stackMutations(slime.mutations :: { string }, rng))
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
	return Genome.rarity(slime.tier).income
		* slime.size
		* Genome.mutationsMultiplier(Genome.mutationList(slime))
		* growth
end

-- Every mutation's player-facing name, space separated ("Glow Syrup"); "" for none.
function Genome.mutationsDisplay(list: { string }): string
	local names = {}
	for _, name in list do
		table.insert(names, Genome.mutationDisplayName(name))
	end
	return table.concat(names, " ")
end

function Genome.displayName(slime: Slime): string
	local rarity = Genome.rarity(slime.tier).name
	local mutations = Genome.mutationsDisplay(Genome.mutationList(slime))
	if mutations ~= "" then
		return `{mutations} {rarity} {slime.name}`
	end
	return `{rarity} {slime.name}`
end

-- SlimeDex entry: which visible combination this slime is (its primary mutation, so the
-- dex stays a fixed size: stacks count as their strongest mutation, combos have their own).
function Genome.dexKey(slime: Slime): string
	return `{slime.tier}:{Genome.primaryMutation(Genome.mutationList(slime))}:{slime.pattern}:{slime.eyes}`
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
	-- v4 `mutations` list; older saves only have the single `mutation` (SaveData.migrateV3 builds the list).
	local source: { any } = if type(raw.mutations) == "table" then raw.mutations else { raw.mutation }
	local mutations: { string } = {}
	for _, m in source do
		if
			type(m) == "string"
			and m ~= "None"
			and Genome.mutationInfo(m)
			and not table.find(mutations, m)
			and #mutations < Config.MAX_MUTATIONS
		then
			table.insert(mutations, m)
		end
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
		mutation = Genome.primaryMutation(mutations),
		mutations = mutations,
		pad = if pad then math.floor(pad) else nil,
		species = if type(raw.species) == "string" and SlimeRoster.get(raw.species) then raw.species else nil,
		growth = if growth then math.floor(math.min(growth, 1) * 1e4 + 0.5) / 1e4 else nil,
		keep = if raw.keep == true then true else nil,
	}
end

Genome.bindWeather()

return Genome
