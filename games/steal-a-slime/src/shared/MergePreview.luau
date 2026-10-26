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
local MergeGate = if script then require(script.Parent.MergeGate) else require("./MergeGate")
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
	title: string, -- "Random slime" (with `rarity` beside it) or the recipe hybrid's name
	tier: number,
	rarity: string,
	color: { number }, -- rarity colour
	jumpTier: number?,
	jumpRarity: string?,
	jumpChance: number, -- 0..1
	jumpOpensAt: number?, -- the rebirth count that opens the jump this load would have without the rank gate
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

-- The preview for one to three slimes of one rarity in the vat. A load short of three previews what the full
-- load gives (size from the slimes so far; a recipe shows only once all three are in).
function MergePreview.forSlimes(slimes: { Slime }, known: any?): Preview
	local fromTier = slimes[1].tier
	local rebirths = if type(known) == "table" and type(known.rebirths) == "number" then known.rebirths else nil
	local odds = TripleMerge.odds(fromTier, rebirths)
	local tier, jumpTier, jumpChance = odds.tier, odds.jumpTier, odds.jumpChance
	local jumpOpensAt = if jumpTier == nil and TripleMerge.odds(fromTier).jumpTier
		then MergeGate.rebirthsFor(fromTier + 1)
		else nil
	local size = expectedSize(slimes, Config.TRIPLE_MERGE_SIZE_BONUS)
	local recipe = MergePreview.recipeFor(slimes, known)
	if recipe then
		tier, jumpTier, jumpChance, jumpOpensAt = recipe.tier, nil, 0, nil
	end
	local rarity = Genome.rarity(tier)
	local title = if recipe then recipe.name else "Random slime"
	return {
		kind = if recipe then "recipe" else "random",
		title = title,
		tier = tier,
		rarity = rarity.name,
		color = rarity.color,
		jumpTier = jumpTier,
		jumpRarity = if jumpTier then Genome.rarity(jumpTier).name else nil,
		jumpChance = jumpChance,
		jumpOpensAt = jumpOpensAt,
		size = size,
		species = if recipe then recipe.species else nil,
	}
end

return table.freeze(MergePreview)
