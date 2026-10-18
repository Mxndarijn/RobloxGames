--!strict
--[[
	SpeciesDex (pure, CONTRACT.md §36)

	The SlimeDex: one entry per spawn, hybrid and boss species (50), the event Secrets as bonus entries, and
	mutation stamps "<species>:<Mutation>". `record` is what PlayerData.discover runs for every slime a player
	gets: it sets data.found[species] and the stamp of the slime's primary mutation. Counts feed Collection
	(milestones), PlotSkins, Badges and the plot attributes; `view` builds State.dex. Recipe hints and the
	featured-Secret week come in through `Sources`, so this module needs neither MergeRecipes nor EventSecrets.
	No Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local SlimeRoster = if script then require(script.Parent.SlimeRoster) else require("./SlimeRoster")

type Entry = SlimeRoster.Entry

export type Data = {
	found: { [string]: boolean },
	stamps: { [string]: boolean },
}

export type Recipe = { inputs: { string }, hint: string }

-- What the view needs from other systems (Snapshot passes the real ones, tests pass fakes).
export type Sources = {
	recipeFor: (hybridId: string) -> Recipe?, -- MergeRecipes.recipeFor
	-- EventSecrets.featuredWeek: unix start of the week `id` is featured (this week, else its next); nil = none
	featuredWeek: (id: string, now: number) -> number?,
}

export type EntryView = {
	id: string,
	tier: number,
	kind: string,
	found: boolean,
	name: string?,
	hint: string?,
	ingredients: { string }?,
	stamps: { string },
	gold: { string },
}

export type View = {
	found: number,
	total: number,
	stamps: number,
	stampTotal: number,
	gold: number,
	bonusFound: number,
	bonusTotal: number,
	entries: { EntryView },
}

local ENTRIES: { Entry } = {}
local BONUS = SlimeRoster.ofKind("event")
local inDex: { [string]: Entry } = {}
local stamped: { [string]: boolean } = {}
for _, entry in SlimeRoster.ROSTER do
	if entry.kind == "spawn" or entry.kind == "hybrid" or entry.kind == "boss" then
		table.insert(ENTRIES, entry)
		inDex[entry.id] = entry
		stamped[entry.id] = entry.kind ~= "boss"
	end
end

-- "None" + the plain mutations: the 8 core stamps of a species, in display order.
local CORE: { string } = { "None" }
local isCore: { [string]: boolean } = { None = true }
for _, m in Config.MUTATIONS do
	table.insert(CORE, m.name)
	isCore[m.name] = true
end
-- Combo and weather mutations: gold bonus stamps.
local isGold: { [string]: boolean } = {}
for _, list in { Config.COMBOS, Config.WEATHER_MUTATIONS, Config.WEATHER_COMBOS } :: { { any } } do
	for _, m in list do
		isGold[m.name] = true
	end
end

local stampSpecies = 0
for _, yes in stamped do
	if yes then
		stampSpecies += 1
	end
end

local SpeciesDex = {
	ENTRIES = table.freeze(ENTRIES),
	BONUS = BONUS,
	CORE_STAMPS = table.freeze(CORE),
	TOTAL = #ENTRIES,
	STAMP_TOTAL = stampSpecies * #CORE,
	BOSS_HINT = "Defeat the boss event",
	UNKNOWN = "???",
}

function SpeciesDex.stampKey(species: string, mutation: string): string
	return `{species}:{mutation}`
end

-- A species the Dex knows: an entry or a bonus entry.
function SpeciesDex.isSpecies(id: any): boolean
	if type(id) ~= "string" then
		return false
	end
	local entry = SlimeRoster.get(id)
	return entry ~= nil and (inDex[id] ~= nil or entry.kind == "event")
end

-- A stamp key that can exist: a stamped species and a core or gold mutation.
function SpeciesDex.isStamp(key: any): boolean
	if type(key) ~= "string" then
		return false
	end
	local species, mutation = string.match(key, "^([^:]+):([^:]+)$")
	return species ~= nil
		and stamped[species] == true
		and (isCore[mutation :: string] == true or isGold[mutation :: string] == true)
end

-- Marks the slime's species found and its primary-mutation stamp. Returns whether the species is new.
function SpeciesDex.record(data: Data, slime: { species: string?, mutation: string, mutations: { string }? }): boolean
	local species = slime.species
	if not SpeciesDex.isSpecies(species) then
		return false
	end
	local id = species :: string
	local fresh = not data.found[id]
	data.found[id] = true
	local key = SpeciesDex.stampKey(id, Genome.primaryMutation(Genome.mutationList(slime :: any)))
	if SpeciesDex.isStamp(key) then
		data.stamps[key] = true
	end
	return fresh
end

-- Entries found among the 50.
function SpeciesDex.count(data: Data): number
	local n = 0
	for id in data.found do
		if inDex[id] then
			n += 1
		end
	end
	return n
end

-- Event Secrets owned.
function SpeciesDex.bonusCount(data: Data): number
	local n = 0
	for _, entry in BONUS do
		if data.found[entry.id] then
			n += 1
		end
	end
	return n
end

local function mutationOf(key: string): string?
	return string.match(key, ":([^:]+)$")
end

-- Core stamps (out of STAMP_TOTAL).
function SpeciesDex.stampCount(data: Data): number
	local n = 0
	for key in data.stamps do
		if SpeciesDex.isStamp(key) and isCore[mutationOf(key) :: string] then
			n += 1
		end
	end
	return n
end

-- Gold bonus stamps (combo and weather mutations).
function SpeciesDex.goldCount(data: Data): number
	local n = 0
	for key in data.stamps do
		if SpeciesDex.isStamp(key) and isGold[mutationOf(key) :: string] then
			n += 1
		end
	end
	return n
end

-- Entries of one tier among the 50.
function SpeciesDex.tierSize(tier: number): number
	local n = 0
	for _, entry in ENTRIES do
		if entry.tier == tier then
			n += 1
		end
	end
	return n
end

-- Found entries of one tier.
function SpeciesDex.tierCount(data: Data, tier: number): number
	local n = 0
	for _, entry in ENTRIES do
		if entry.tier == tier and data.found[entry.id] then
			n += 1
		end
	end
	return n
end

-- Bit k-1 set when a found entry has tier k (plot attribute DexTierMask, badges).
function SpeciesDex.tierMask(data: Data): number
	local mask = 0
	for _, entry in ENTRIES do
		if data.found[entry.id] and entry.tier >= 1 and entry.tier <= Config.MAX_TIER then
			mask = bit32.bor(mask, bit32.lshift(1, entry.tier - 1))
		end
	end
	return mask
end

local function stampsOf(data: Data, id: string): ({ string }, { string })
	local core, gold = {}, {}
	if not stamped[id] then
		return core, gold
	end
	for _, mutation in CORE do
		if data.stamps[SpeciesDex.stampKey(id, mutation)] then
			table.insert(core, mutation)
		end
	end
	for mutation in isGold do
		if data.stamps[SpeciesDex.stampKey(id, mutation)] then
			table.insert(gold, mutation)
		end
	end
	table.sort(gold)
	return core, gold
end

-- "19 Oct" for a unix time (UTC).
function SpeciesDex.weekLabel(startsAt: number): string
	return `{tonumber(os.date("!%d", startsAt))} {os.date("!%b", startsAt)}`
end

local function entryView(data: Data, entry: Entry, now: number, sources: Sources): EntryView
	local found = data.found[entry.id] == true
	local core, gold = stampsOf(data, entry.id)
	local view: EntryView = {
		id = entry.id,
		tier = entry.tier,
		kind = entry.kind,
		found = found,
		name = if found then entry.name else nil,
		hint = nil,
		ingredients = nil,
		stamps = core,
		gold = gold,
	}
	if entry.kind == "hybrid" then
		local recipe = sources.recipeFor(entry.id)
		if recipe then
			local known = true
			local slots = {}
			for i, input in recipe.inputs do
				local has = data.found[input] == true
				known = known and has
				slots[i] = if has then input else ""
			end
			view.ingredients = slots
			view.hint = recipe.hint
			if known then
				view.name = entry.name
			end
		end
	elseif entry.kind == "boss" then
		view.hint = SpeciesDex.BOSS_HINT
	elseif entry.kind == "event" then
		local week = sources.featuredWeek(entry.id, now)
		local featuredNow = week ~= nil and week <= now
		if found or featuredNow then
			view.name = entry.name
			view.hint = if week then `Featured Secret: week of {SpeciesDex.weekLabel(week)}` else nil
		else
			view.hint = SpeciesDex.UNKNOWN
		end
	end
	return view
end

-- State.dex.
function SpeciesDex.view(data: Data, now: number, sources: Sources): View
	local entries: { EntryView } = {}
	for _, entry in ENTRIES do
		table.insert(entries, entryView(data, entry, now, sources))
	end
	for _, entry in BONUS do
		table.insert(entries, entryView(data, entry, now, sources))
	end
	return {
		found = SpeciesDex.count(data),
		total = SpeciesDex.TOTAL,
		stamps = SpeciesDex.stampCount(data),
		stampTotal = SpeciesDex.STAMP_TOTAL,
		gold = SpeciesDex.goldCount(data),
		bonusFound = SpeciesDex.bonusCount(data),
		bonusTotal = #BONUS,
		entries = entries,
	}
end

return table.freeze(SpeciesDex)
