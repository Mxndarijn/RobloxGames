--!strict
--[[
	MergeRecipes (pure, CONTRACT.md §31)

	Which slime three slimes of one tier make in the vat. Three spawning species of tier T that form a recipe
	(a multiset: order doesn't matter, repeats count) give that recipe's hybrid of tier T + 1. Anything else
	falls back to a random spawning species of the next tier from the player's unlocked families, capped at
	Config.MERGE_MAX_TIER, with a +2 jump only up to Config.MERGE_JUMP_MAX_TIER and the merge assist (a share
	of results from the species the player hasn't found). `resolve` draws no randomness: TripleMerge rolls
	from its outcome, and the merge menu previews it.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local FountainTiers = if script then require(script.Parent.FountainTiers) else require("./FountainTiers")
local SlimeRoster = if script then require(script.Parent.SlimeRoster) else require("./SlimeRoster")

export type Recipe = {
	id: string, -- the hybrid's SlimeRoster id
	inputs: { string }, -- three spawning species of tier - 1, sorted
	tier: number,
	hint: string, -- Dex hint line
}

export type Input = { tier: number, species: string? }

export type Ctx = {
	unlocked: (entry: SlimeRoster.Entry) -> boolean,
	found: { [string]: boolean }?,
}

export type Outcome = {
	kind: "recipe" | "random" | "refused",
	reason: string?, -- refused
	recipe: Recipe?, -- recipe
	tier: number, -- the result tier (0 when refused)
	jumpTier: number?, -- random: T + 2 when allowed
	jumpChance: number,
	pool: { string }, -- random: unlocked spawning species of `tier`
	assistPool: { string }, -- random: `pool` minus the found species
	assistChance: number,
}

local function r(id: string, a: string, b: string, c: string, hint: string): Recipe
	local inputs = { a, b, c }
	table.sort(inputs)
	local entry = SlimeRoster.get(id)
	assert(entry and entry.kind == "hybrid", `recipe for unknown hybrid {id}`)
	return table.freeze({ id = id, inputs = table.freeze(inputs), tier = entry.tier, hint = hint })
end

-- docs/SLIME-ECONOMY.md §2.2.
local RECIPES: { Recipe } = {
	r("soda", "bubbles", "gummy", "mochi", "Fizzy, chewy and soft: three Commons walk into a vat."),
	r("rocky_road", "cheddar", "mochi", "pebble", "A scoop of rock, cheese and rice cake."),
	r("bloom", "bumble", "mushie", "prickles", "A bee, a mushroom and a cactus flower."),
	r("honey_toad", "bumble", "flan", "froggo", "Something sticky landed on a frog."),
	r("truffle", "flan", "flan", "mushie", "Double caramel on a mushroom."),
	r("moo_shroom", "lop", "moo", "moo", "Two cows and a bunny went into the woods."),
	r("snow_bunny", "lop", "lop", "pengoo", "Two bunnies and a friend from the cold."),
	r("catfish", "chomp", "pengoo", "whiskers", "A cat, a shark and the penguin that brought them together."),
	r("sushi", "chomp", "chomp", "pengoo", "A penguin's favourite dinner, twice."),
	r("steam", "blaze", "frostbite", "zap", "Fire, ice and a storm."),
	r("kraken", "octo", "octo", "zap", "Two octopuses in a thunderstorm."),
	r("thunderbee", "imp", "zap", "zap", "Double lightning and a little devil."),
	r("dragon_king", "king", "king", "king", "Three crowns make a dragon."),
	r("cyber_ninja", "ninja", "ninja", "robo", "Two shadows and a machine."),
	r("nightwing", "cosmo", "seraph", "seraph", "Two angels fell into the stars."),
}

local MergeRecipes = {}

MergeRecipes.RECIPES = table.freeze(RECIPES)

-- The lookup key of a species multiset: sorted ids joined by "+".
function MergeRecipes.key(species: { string }): string
	local sorted = table.clone(species)
	table.sort(sorted)
	return table.concat(sorted, "+")
end

local byKey: { [string]: Recipe } = {}
local byId: { [string]: Recipe } = {}
for _, recipe in RECIPES do
	local key = MergeRecipes.key(recipe.inputs)
	assert(not byKey[key], `two recipes share {key}`)
	byKey[key] = recipe
	byId[recipe.id] = recipe
end

-- The recipe of exactly these three species, or nil (also when any species is nil).
function MergeRecipes.find(species: { string? }): Recipe?
	local ids: { string } = {}
	for i = 1, 3 do
		local id = species[i]
		if type(id) ~= "string" then
			return nil
		end
		ids[i] = id
	end
	if #species ~= 3 then
		return nil
	end
	return byKey[MergeRecipes.key(ids)]
end

function MergeRecipes.recipeFor(hybridId: string): Recipe?
	return byId[hybridId]
end

function MergeRecipes.hint(hybridId: string): string?
	local recipe = byId[hybridId]
	return if recipe then recipe.hint else nil
end

-- Every input species of `recipe` is found (the Dex can name it).
function MergeRecipes.isKnown(recipe: Recipe, found: { [string]: boolean }?): boolean
	for _, id in recipe.inputs do
		if not (found and found[id]) then
			return false
		end
	end
	return true
end

-- The player has found the hybrid itself (the merge menu may name its recipe).
function MergeRecipes.isDiscovered(hybridId: string, found: { [string]: boolean }?): boolean
	return found ~= nil and found[hybridId] == true
end

-- Species the player counts as found: the species of `slimes` (Genome slimes or State slime views) plus a
-- saved `found` set.
function MergeRecipes.foundOf(slimes: { any }?, found: { [string]: boolean }?): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(found) == "table" then
		for id, yes in found do
			if yes == true and type(id) == "string" then
				out[id] = true
			end
		end
	end
	for _, s in slimes or {} do
		local slime = if type(s) == "table" and type(s.slime) == "table" then s.slime else s
		if type(slime) == "table" and type(slime.species) == "string" then
			out[slime.species] = true
		end
	end
	return out
end

-- Classic always; a family once a player of `rebirths` may catch it.
function MergeRecipes.unlockedFor(rebirths: number): (entry: SlimeRoster.Entry) -> boolean
	return function(entry: SlimeRoster.Entry): boolean
		return FountainTiers.catchBlock(rebirths, entry.family) == nil
	end
end

-- The unlocked spawning species of `tier` (roster order), and those of them not found yet.
function MergeRecipes.pool(tier: number, ctx: Ctx): ({ string }, { string })
	local pool, assist = {}, {}
	for _, entry in SlimeRoster.ROSTER do
		if entry.kind == "spawn" and entry.tier == tier and ctx.unlocked(entry) then
			table.insert(pool, entry.id)
			if not (ctx.found and ctx.found[entry.id]) then
				table.insert(assist, entry.id)
			end
		end
	end
	return pool, assist
end

local function refused(reason: string): Outcome
	return {
		kind = "refused",
		reason = reason,
		tier = 0,
		jumpChance = 0,
		pool = {},
		assistPool = {},
		assistChance = 0,
	}
end

-- What three inputs of one tier make. No randomness: the caller rolls jump, assist and species from it.
function MergeRecipes.resolve(inputs: { Input }, ctx: Ctx): Outcome
	if #inputs ~= 3 then
		return refused("need three slimes")
	end
	local from = inputs[1].tier
	for _, input in inputs do
		if input.tier ~= from then
			return refused("slimes must be the same rarity")
		end
	end
	if from < Config.MAX_TIER then
		local recipe = MergeRecipes.find({ inputs[1].species, inputs[2].species, inputs[3].species })
		if recipe and recipe.tier == from + 1 then
			return {
				kind = "recipe",
				recipe = recipe,
				tier = recipe.tier,
				jumpChance = 0,
				pool = {},
				assistPool = {},
				assistChance = 0,
			}
		end
	end
	local tier = if from >= Config.MAX_TIER then Config.MAX_TIER else math.min(from + 1, Config.MERGE_MAX_TIER)
	local jump = from + 2
	local canJump = jump <= Config.MERGE_JUMP_MAX_TIER
	local pool, assistPool = MergeRecipes.pool(tier, ctx)
	return {
		kind = "random",
		tier = tier,
		jumpTier = if canJump then jump else nil,
		jumpChance = if canJump then Config.TRIPLE_MERGE_JUMP_CHANCE else 0,
		pool = pool,
		assistPool = assistPool,
		assistChance = if #assistPool > 0 then Config.MERGE_ASSIST_CHANCE else 0,
	}
end

return table.freeze(MergeRecipes)
