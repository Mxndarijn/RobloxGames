--!strict
--[[
	TripleMerge (FEATURES.MergeVat3, CONTRACT.md §21)

	Three slimes of ONE rarity go into the vat and one slime of a higher rarity comes out (all three are
	consumed). The rules are fixed; only the odds are rolled, from the server's Rng, so one seed always gives
	one result:
	  * tier      T + 1 (like the two-slime vat); with Config.TRIPLE_MERGE_JUMP_CHANCE it is T + 2, but never
	              into the Secret tier (a jump needs T + 2 below MAX_TIER; Secret stays a find). Tier-7 inputs
	              stay tier 7 and always roll a fresh mutation, as in Merge.
	  * mutation  the strongest of the three (equal ones upgrade, Merge.inheritedMutation), every other
	              mutation they carry too (strongest first, combos fuse, as many as fit), plus a fresh roll
	              (Config.TRIPLE_MERGE_MUTATION_CHANCE; pet bonus included).
	  * species   the child is a real SlimeRoster species of its tier (its name and colour), not a blended name.
	  * size      mean of the three + Config.TRIPLE_MERGE_SIZE_BONUS.
	  * traits    pattern / eyes / mouth each from one of the three.
	Anti-dupe: `apply` checks everything first (three DIFFERENT ids, owned, not busy, not kept, same tier) and only then
	removes the inputs and adds the child, so a refused merge changes nothing and an accepted one never leaves
	an input behind. Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local Merge = if script then require(script.Parent.Merge) else require("./Merge")
local Perks = if script then require(script.Parent.Perks) else require("./Perks")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")
local SlimeLooks = if script then require(script.Parent.SlimeLooks) else require("./SlimeLooks")

type Slime = Genome.Slime

export type Odds = { tier: number, jumpTier: number?, jumpChance: number, freshMutationChance: number }

local TripleMerge = {}

TripleMerge.COUNT = 3

-- Whether `slimes` (exactly three) can go in together; a reason when not.
function TripleMerge.canMerge(slimes: { Slime? }): (boolean, string?)
	if #slimes ~= TripleMerge.COUNT then
		return false, "need three slimes"
	end
	local a, b, c = slimes[1], slimes[2], slimes[3]
	if not a or not b or not c then
		return false, "missing slime"
	end
	if a.id == b.id or b.id == c.id or a.id == c.id then
		return false, "need three different slimes"
	end
	if a.tier ~= b.tier or b.tier ~= c.tier then
		return false, "slimes must be the same rarity"
	end
	return true, nil
end

-- What three slimes of `tier` can become (for the UI preview and the roll).
function TripleMerge.odds(tier: number, mutationBonus: number?): Odds
	local base = math.min(tier + 1, Config.MAX_TIER)
	local jump = tier + 2
	local canJump = tier < Config.MAX_TIER and jump <= Config.MAX_TIER - 1
	return {
		tier = base,
		jumpTier = if canJump then jump else nil,
		jumpChance = if canJump then Config.TRIPLE_MERGE_JUMP_CHANCE else 0,
		freshMutationChance = math.min(1, Config.TRIPLE_MERGE_MUTATION_CHANCE + (mutationBonus or 0)),
	}
end

local function primaryOf(s: Slime): string
	return Genome.primaryMutation(Genome.mutationList(s))
end

-- Every mutation the parents carry except `primary`, strongest first.
local function othersOf(slimes: { Slime }, primary: string): { string }
	local carried: { string } = {}
	for _, parent in slimes do
		for _, m in Genome.mutationList(parent) do
			if m ~= primary and not table.find(carried, m) then
				table.insert(carried, m)
			end
		end
	end
	table.sort(carried, function(x, y)
		local mx, my = Genome.mutationMultiplier(x), Genome.mutationMultiplier(y)
		if mx ~= my then
			return mx > my
		end
		return x < y
	end)
	return carried
end

-- The child's inherited primary mutation before the fresh roll: the parents' primaries folded with
-- Merge.inheritedMutation (equal ones upgrade).
function TripleMerge.inheritedPrimary(slimes: { Slime }): string
	local mutation = primaryOf(slimes[1])
	for i = 2, #slimes do
		mutation = Merge.inheritedMutation(mutation, primaryOf(slimes[i]))
	end
	return mutation
end

-- Every mutation the child keeps for sure (the inherited primary, then the others strongest first, combos
-- fused, at most MAX_MUTATIONS). A fresh roll can still add or upgrade one.
function TripleMerge.keptMutations(slimes: { Slime }): { string }
	local primary = TripleMerge.inheritedPrimary(slimes)
	local mutations: { string } = if primary == "None" then {} else { primary }
	for _, m in othersOf(slimes, primary) do
		mutations = Genome.addMutation(mutations, m)
	end
	return mutations
end

-- Builds the child (no side effects). `slimes` must have passed canMerge. Draw order is fixed: jump, species,
-- fresh mutation (2 draws), three trait picks (pattern, eyes, mouth), stacking.
function TripleMerge.merge(slimes: { Slime }, rng: Rng.Rng, id: string, mutationBonus: number?): Slime
	local a, b, c = slimes[1], slimes[2], slimes[3]
	local odds = TripleMerge.odds(a.tier, mutationBonus)
	local maxed = a.tier >= Config.MAX_TIER
	local tier = odds.tier
	if odds.jumpTier and rng:float() < odds.jumpChance then
		tier = odds.jumpTier
	end

	local species = Genome.rollSpecies(tier, rng:float())
	local look = if species then SlimeLooks.get(species.id) else nil

	local mutation = TripleMerge.inheritedPrimary(slimes)
	local chance = if maxed then 1 else odds.freshMutationChance
	local rolled = Genome.rollMutation(rng:float(), rng:float(), chance)
	if Genome.mutationMultiplier(rolled) > Genome.mutationMultiplier(mutation) then
		mutation = rolled
	end

	local color = { 200, 255, 200 }
	if look then
		color = { look.color[1], look.color[2], look.color[3] }
	else
		for i = 1, 3 do
			color[i] = math.floor((a.color[i] + b.color[i] + c.color[i]) / 3 + 0.5)
		end
	end
	local size = math.clamp(
		math.floor(((a.size + b.size + c.size) / 3 + Config.TRIPLE_MERGE_SIZE_BONUS) * 100 + 0.5) / 100,
		Config.MIN_SIZE,
		Config.MAX_SIZE
	)
	local function one<T>(x: T, y: T, z: T): T
		local pick = rng:int(1, 3)
		return if pick == 1 then x else if pick == 2 then y else z
	end

	local mutations: { string } = if mutation == "None" then {} else { mutation }
	-- Every other mutation the parents carry (strongest first); the primaries are already in `mutation`.
	for _, m in othersOf(slimes, mutation) do
		mutations = Genome.addMutation(mutations, m)
	end

	local child: Slime = {
		id = id,
		name = if species then species.name else a.name,
		tier = tier,
		color = color,
		size = size,
		pattern = one(a.pattern, b.pattern, c.pattern),
		eyes = one(a.eyes, b.eyes, c.eyes),
		mouth = one(a.mouth, b.mouth, c.mouth),
		mutation = "None",
		pad = nil,
		species = if species then species.id else nil,
	}
	Genome.setMutations(child, Genome.stackMutations(mutations, rng))
	return child
end

--[[
	Validated merge on a player's data: three different owned slimes, none in `busy`, one tier. The child takes
	the first slime's pad. Returns (ok, childOrReason).
]]
function TripleMerge.apply(
	data: PlayerData.Data,
	ids: { string },
	busy: { [string]: boolean }?,
	rng: Rng.Rng,
	newId: string
): (boolean, Slime | string)
	if #ids ~= TripleMerge.COUNT then
		return false, "need three slimes"
	end
	for _, id in ids do
		if busy and busy[id] then
			return false, "slime is busy"
		end
	end
	local slimes: { Slime? } = {}
	for i, id in ids do
		local found = PlayerData.findSlime(data, id)
		if not found then
			return false, "missing slime"
		end
		if found.keep then
			return false, "slime is kept"
		end
		slimes[i] = found
	end
	local ok, reason = TripleMerge.canMerge(slimes)
	if not ok then
		return false, reason or "cannot merge"
	end
	local parents = slimes :: { Slime }
	if PlayerData.findSlime(data, newId) then
		return false, "duplicate"
	end
	local pad = parents[1].pad
	local wasFavorite = false
	for _, id in ids do
		wasFavorite = wasFavorite or data.favoriteId == id
	end
	local child = TripleMerge.merge(parents, rng, newId, Perks.petMutationBonus(data))
	for _, id in ids do
		PlayerData.removeSlime(data, id)
	end
	local added = PlayerData.addSlime(data, child, pad)
	if not added then
		-- The inputs' pads were just freed, so this can't fail; never lose a slime if it somehow does.
		PlayerData.addSlime(data, child, nil)
	end
	if wasFavorite then
		data.favoriteId = child.id
	end
	return true, child
end

return table.freeze(TripleMerge)
