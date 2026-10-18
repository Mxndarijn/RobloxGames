--!strict
--[[
	MergePreview (pure, CONTRACT.md §21.1)

	The one place the merge menu asks "what will these slimes make?". Three picks that form a merge recipe
	whose hybrid the player has already found preview as that hybrid (`kind = "recipe"`, CONTRACT.md §35).
	Every other load, an undiscovered recipe hit included, previews as a random species of the next rarity
	(`kind = "random"`), so the menu never gives a recipe away. Only shows odds; the server rolls the child.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local Merge = if script then require(script.Parent.Merge) else require("./Merge")
local MergeRecipes = if script then require(script.Parent.MergeRecipes) else require("./MergeRecipes")
local SlimeRoster = if script then require(script.Parent.SlimeRoster) else require("./SlimeRoster")
local TripleMerge = if script then require(script.Parent.TripleMerge) else require("./TripleMerge")

type Slime = Genome.Slime

export type Recipe = {
	species: string, -- SlimeRoster id of the result
	name: string, -- its display name
	tier: number,
}

export type Preview = {
	kind: "random" | "recipe",
	title: string, -- "Random Rare slime" or the recipe hybrid's name
	tier: number,
	rarity: string,
	color: { number }, -- rarity colour
	jumpTier: number?,
	jumpRarity: string?,
	jumpChance: number, -- 0..1
	mutations: { string }, -- kept for sure (strongest first)
	freshMutationChance: number, -- 0..1, chance of one more on top
	size: number, -- expected size
	species: string?, -- recipe only
}

local MergePreview = {}

-- Species the State's species Dex marks found (`dex.entries[i] = { id, found }`); nil for any other shape.
local function foundInDex(dex: any): { [string]: boolean }?
	if type(dex) ~= "table" or type(dex.entries) ~= "table" then
		return nil
	end
	local found: { [string]: boolean } = {}
	for _, entry: any in dex.entries :: { any } do
		if type(entry) == "table" and entry.found == true and type(entry.id) == "string" then
			found[entry.id] = true
		end
	end
	return found
end

-- The merge recipe these three slimes match when the player has found its hybrid, else nil (then the
-- preview is a random species of the next rarity). `known` is the client's State: its owned slimes and
-- the species Dex (`dex.entries`) say what the player has found.
function MergePreview.recipeFor(slimes: { Slime }, known: any?): Recipe?
	if #slimes ~= TripleMerge.COUNT or slimes[1].tier ~= slimes[2].tier or slimes[2].tier ~= slimes[3].tier then
		return nil
	end
	local recipe = MergeRecipes.find({ slimes[1].species, slimes[2].species, slimes[3].species })
	if not recipe or recipe.tier ~= slimes[1].tier + 1 then
		return nil
	end
	local state = if type(known) == "table" then known else {}
	if not MergeRecipes.isDiscovered(recipe.id, MergeRecipes.foundOf(state.slimes, foundInDex(state.dex))) then
		return nil
	end
	local entry = SlimeRoster.get(recipe.id) :: SlimeRoster.Entry
	return { species = recipe.id, name = entry.name, tier = recipe.tier }
end

local function expectedSize(slimes: { Slime }, bonus: number): number
	local sum = 0
	for _, s in slimes do
		sum += s.size
	end
	local size = math.clamp(sum / #slimes + bonus, Config.MIN_SIZE, Config.MAX_SIZE)
	return math.floor(size * 100 + 0.5) / 100
end

-- The preview for slimes of one rarity going into the vat that takes `vatSize` (2 = pair vat, 3 = TripleMerge;
-- default #slimes). Fewer picks than `vatSize` preview what the full load gives (mutations and size from
-- the picks so far).
function MergePreview.forSlimes(slimes: { Slime }, known: any?, mutationBonus: number?, vatSize: number?): Preview
	local triple = (vatSize or #slimes) >= TripleMerge.COUNT
	local fromTier = slimes[1].tier
	local tier, jumpTier, jumpChance, fresh, mutations, size
	if triple then
		local odds = TripleMerge.odds(fromTier, mutationBonus)
		tier, jumpTier, jumpChance, fresh = odds.tier, odds.jumpTier, odds.jumpChance, odds.freshMutationChance
		mutations = TripleMerge.keptMutations(slimes)
		size = expectedSize(slimes, Config.TRIPLE_MERGE_SIZE_BONUS)
	else
		tier, jumpTier, jumpChance = math.min(fromTier + 1, Config.MAX_TIER), nil, 0
		fresh = math.min(1, Config.MERGE_MUTATION_CHANCE + (mutationBonus or 0))
		local primary = Genome.primaryMutation(Genome.mutationList(slimes[1]))
		if slimes[2] then
			primary = Merge.inheritedMutation(primary, Genome.primaryMutation(Genome.mutationList(slimes[2])))
		end
		mutations = if primary == "None" then {} else { primary }
		size = expectedSize(slimes, Config.MERGE_SIZE_BONUS)
	end
	if fromTier >= Config.MAX_TIER then
		fresh = 1 -- maxed slimes always roll a fresh mutation
	end

	local recipe = if triple then MergePreview.recipeFor(slimes, known) else nil
	if recipe then
		tier, jumpTier, jumpChance = recipe.tier, nil, 0
	end
	local rarity = Genome.rarity(tier)
	local title = if recipe then recipe.name else `Random {rarity.name} slime`
	return {
		kind = if recipe then "recipe" else "random",
		title = title,
		tier = tier,
		rarity = rarity.name,
		color = rarity.color,
		jumpTier = jumpTier,
		jumpRarity = if jumpTier then Genome.rarity(jumpTier).name else nil,
		jumpChance = jumpChance,
		mutations = mutations,
		freshMutationChance = fresh,
		size = size,
		species = if recipe then recipe.species else nil,
	}
end

return table.freeze(MergePreview)
