--!strict
--[[
	MergePreview (pure, CONTRACT.md §21.1)

	The one place the merge menu asks "what will these slimes make?". Today every load gives a random species
	of the next rarity (`kind = "random"`). `MergePreview.recipeFor` is the hook for merge recipes: when it
	returns a recipe, the preview names that species (`kind = "recipe"`), or hides it behind a silhouette and
	a hint while the player has not discovered it. Only shows odds; the server rolls the real child.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local Merge = if script then require(script.Parent.Merge) else require("./Merge")
local TripleMerge = if script then require(script.Parent.TripleMerge) else require("./TripleMerge")

type Slime = Genome.Slime

export type Recipe = {
	species: string, -- SlimeRoster id of the result
	name: string, -- its display name
	tier: number,
	discovered: boolean, -- false = show a silhouette and `hint`
	hint: string?,
}

export type Preview = {
	kind: "random" | "recipe",
	title: string, -- "Random Rare slime", the recipe species' name, or "???"
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
	discovered: boolean, -- false only for an undiscovered recipe
	hint: string?, -- recipe only, while undiscovered
}

local MergePreview = {}

-- The merge recipe these slimes match, or nil (then the result is a random species of the next rarity).
-- `known` is whatever the recipe lookup needs to tell discovered results apart (the menu passes State).
function MergePreview.recipeFor(_slimes: { Slime }, _known: any?): Recipe?
	return nil
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

	local recipe = MergePreview.recipeFor(slimes, known)
	if recipe then
		tier, jumpTier, jumpChance = recipe.tier, nil, 0
	end
	local rarity = Genome.rarity(tier)
	local title = if recipe then (if recipe.discovered then recipe.name else "???") else `Random {rarity.name} slime`
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
		discovered = if recipe then recipe.discovered else true,
		hint = if recipe and not recipe.discovered then recipe.hint else nil,
	}
end

return table.freeze(MergePreview)
