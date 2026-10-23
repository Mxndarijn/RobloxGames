--!strict
--[[
	SpeciesDex (pure, CONTRACT.md §36)

	The SlimeDex: one entry per spawn, hybrid and boss species (50) and the event Secrets as bonus entries.
	`record` is what PlayerData.discover runs for every slime a player gets: it sets data.found[species]. Counts feed Collection
	(milestones), PlotSkins, Badges and the plot attributes; `view` builds State.dex. Recipe hints and the
	featured-Secret week come in through `Sources`, so this module needs neither MergeRecipes nor EventSecrets.
	No Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local FountainTiers = if script then require(script.Parent.FountainTiers) else require("./FountainTiers")
local SlimeRoster = if script then require(script.Parent.SlimeRoster) else require("./SlimeRoster")

type Entry = SlimeRoster.Entry

export type Data = {
	found: { [string]: boolean },
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
	name: string,
	hint: string?,
	ingredients: { string }?,
	ingredientSets: { string }?, -- hybrids: each slot's set ("Meadow", "Garden", ...), sent even while the slot is ""
}

export type View = {
	found: number,
	total: number,
	bonusFound: number,
	bonusTotal: number,
	entries: { EntryView },
}

local ENTRIES: { Entry } = {}
local BONUS = SlimeRoster.ofKind("event")
local inDex: { [string]: Entry } = {}
for _, entry in SlimeRoster.ROSTER do
	if entry.kind == "spawn" or entry.kind == "hybrid" or entry.kind == "boss" then
		table.insert(ENTRIES, entry)
		inDex[entry.id] = entry
	end
end

local SpeciesDex = {
	ENTRIES = table.freeze(ENTRIES),
	BONUS = BONUS,
	TOTAL = #ENTRIES,
	BOSS_HINT = "Defeat the boss event",
}

-- A species the Dex knows: an entry or a bonus entry.
function SpeciesDex.isSpecies(id: any): boolean
	if type(id) ~= "string" then
		return false
	end
	local entry = SlimeRoster.get(id)
	return entry ~= nil and (inDex[id] ~= nil or entry.kind == "event")
end

-- The set a species belongs to: its FountainTiers family's name, "Meadow" for the Classic species.
function SpeciesDex.setName(id: string): string
	local entry = SlimeRoster.get(id)
	local family = if entry then FountainTiers.family(entry.family) else nil
	return if family then family.name else FountainTiers.CLASSIC_NAME
end

-- Marks the slime's species found. Returns whether the species is new.
function SpeciesDex.record(data: Data, slime: { species: string?, egg: any? }): boolean
	local species = slime.species
	-- An unhatched egg is recorded at its hatch (contract/mystery-egg.md).
	if slime.egg ~= nil or not SpeciesDex.isSpecies(species) then
		return false
	end
	local id = species :: string
	local fresh = not data.found[id]
	data.found[id] = true
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

-- Bit k-1 set when a found entry has tier k (badges).
function SpeciesDex.tierMask(data: Data): number
	local mask = 0
	for _, entry in ENTRIES do
		if data.found[entry.id] and entry.tier >= 1 and entry.tier <= Config.MAX_TIER then
			mask = bit32.bor(mask, bit32.lshift(1, entry.tier - 1))
		end
	end
	return mask
end

-- "19 Oct" for a unix time (UTC).
function SpeciesDex.weekLabel(startsAt: number): string
	return `{tonumber(os.date("!%d", startsAt))} {os.date("!%b", startsAt)}`
end

local function entryView(data: Data, entry: Entry, now: number, sources: Sources): EntryView
	local found = data.found[entry.id] == true
	local view: EntryView = {
		id = entry.id,
		tier = entry.tier,
		kind = entry.kind,
		found = found,
		name = entry.name,
		hint = nil,
		ingredients = nil,
	}
	if entry.kind == "hybrid" then
		local recipe = sources.recipeFor(entry.id)
		if recipe then
			local slots, sets = {}, {}
			for i, input in recipe.inputs do
				slots[i] = if data.found[input] == true then input else ""
				sets[i] = SpeciesDex.setName(input)
			end
			view.ingredients = slots
			view.ingredientSets = sets
			view.hint = recipe.hint
		end
	elseif entry.kind == "boss" then
		view.hint = SpeciesDex.BOSS_HINT
	elseif entry.kind == "event" then
		local week = sources.featuredWeek(entry.id, now)
		local featuredNow = week ~= nil and week <= now
		if (found or featuredNow) and week then
			view.hint = `Featured Secret: week of {SpeciesDex.weekLabel(week)}`
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
		bonusFound = SpeciesDex.bonusCount(data),
		bonusTotal = #BONUS,
		entries = entries,
	}
end

return table.freeze(SpeciesDex)
