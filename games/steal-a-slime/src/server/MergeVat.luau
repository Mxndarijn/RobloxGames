--!strict
--[[
	MergeVat (pure)

	Request("Merge", a, b): two owned, not-busy slimes of the same tier become
	one slime of tier + 1 on the first slime's pad (Shared.Merge.apply).
	Request("Merge3", a, b, c) and Request("AutoMerge", mask): the 3-slime vat (TripleMerge, MergePlan); a merge
	recipe hit gets its own toast (CONTRACT.md §31).
	Request("KeepSlime", id, keep): kept slimes are never merged (CONTRACT.md §21.1).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local Merge = if Shared then require(Shared.Merge) else require("../shared/Merge")
local MergePlan = if Shared then require(Shared.MergePlan) else require("../shared/MergePlan")
local MergeRecipes = if Shared then require(Shared.MergeRecipes) else require("../shared/MergeRecipes")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local TripleMerge = if Shared then require(Shared.TripleMerge) else require("../shared/TripleMerge")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

local MergeVat = {}

local function foundBefore(session: Session): { [string]: boolean }
	return MergeRecipes.foundOf(session.data.slimes, (session.data :: any).found)
end

-- One toast per recipe hit in `made` (CONTRACT.md §31): "discovered" the first time the hybrid is found.
local function recipeToasts(world: World, session: Session, made: { Genome.Slime }, found: { [string]: boolean })
	for _, child in made do
		local recipe = if child.species then MergeRecipes.recipeFor(child.species) else nil
		if recipe then
			local text = if found[recipe.id] then `You brewed a {child.name}!` else `You discovered {child.name}!`
			found[recipe.id] = true
			World.notify(world, session.userId, text, "good", "Rare")
		end
	end
end

function MergeVat.merge(world: World, session: Session, idA: string, idB: string): (boolean, string?)
	local known = table.clone(session.data.dex)
	local ok, result = Merge.apply(session.data, idA, idB, World.busySet(world), world.rng, world.newId())
	if not ok then
		return false, result :: string
	end
	local child = result :: Genome.Slime
	session.data.stats.merges += 1
	World.markDirty(session)
	local isNew = not known[Genome.dexKey(child)]
	World.notify(
		world,
		session.userId,
		`Merged into a {Genome.displayName(child)}!` .. (if isNew then " (new SlimeDex entry)" else ""),
		"good",
		"Merge"
	)
	World.effect(world, "Merge", { plotIndex = session.plotIndex, userId = session.userId })
	World.tutorial(world, session, "Merge")
	return true, nil
end

-- FEATURES.MergeVat3 (the caller checks the flag): three slimes of one rarity -> one of a higher rarity
-- (TripleMerge.apply: validated first, so a refused merge changes nothing). The child takes the first pad.
function MergeVat.merge3(world: World, session: Session, ids: { string }): (boolean, string?)
	local known = table.clone(session.data.dex)
	local found = foundBefore(session)
	local ok, result = TripleMerge.apply(session.data, ids, World.busySet(world), world.rng, world.newId())
	if not ok then
		return false, result :: string
	end
	local child = result :: Genome.Slime
	session.data.stats.merges += 1
	World.markDirty(session)
	local isNew = not known[Genome.dexKey(child)]
	World.notify(
		world,
		session.userId,
		`Three slimes merged into a {Genome.displayName(child)}!` .. (if isNew then " (new SlimeDex entry)" else ""),
		"good",
		"Merge"
	)
	recipeToasts(world, session, { child }, found)
	World.effect(world, "Merge", { plotIndex = session.plotIndex, userId = session.userId })
	World.tutorial(world, session, "Merge")
	return true, nil
end

-- FEATURES.MergeVat3 (the caller checks the flag): every group of three MergePlan finds in the rarities of
-- `mask`, planned on the server's own data. Each group goes through TripleMerge.apply on its own, so a
-- refused group changes nothing and the rest still merge. One Notify for the batch.
function MergeVat.autoMerge(world: World, session: Session, mask: number): (boolean, string?)
	local tiers = MergePlan.tiersOf(mask)
	if next(tiers) == nil then
		return false, "pick a rarity"
	end
	local busy = World.busySet(world)
	local groups = MergePlan.plan(MergePlan.fromData(session.data, busy), { tiers = tiers })
	if #groups == 0 then
		return false, "nothing to merge"
	end
	local known = table.clone(session.data.dex)
	local found = foundBefore(session)
	local made: { Genome.Slime } = {}
	for _, group in groups do
		local ok, result = TripleMerge.apply(session.data, group.ids, busy, world.rng, world.newId())
		if ok then
			table.insert(made, result :: Genome.Slime)
		end
	end
	if #made == 0 then
		return false, "nothing to merge"
	end
	session.data.stats.merges += #made
	World.markDirty(session)
	local best = made[1]
	local fresh = 0
	for _, child in made do
		if child.tier > best.tier then
			best = child
		end
		if not known[Genome.dexKey(child)] then
			known[Genome.dexKey(child)] = true
			fresh += 1
		end
	end
	local text = if #made == 1
		then `Auto-merged into a {Genome.displayName(best)}!`
		else `Auto-merged {#made} times! Best: {Genome.displayName(best)}`
	World.notify(
		world,
		session.userId,
		text .. (if fresh > 0 then ` ({fresh} new SlimeDex entr{if fresh == 1 then "y" else "ies"})` else ""),
		"good",
		"Merge"
	)
	recipeToasts(world, session, made, found)
	World.effect(world, "Merge", { plotIndex = session.plotIndex, userId = session.userId })
	World.tutorial(world, session, "Merge")
	return true, nil
end

-- Marks an owned slime as kept (never merged) or clears the mark.
function MergeVat.setKeep(session: Session, id: string, keep: boolean): (boolean, string?)
	local slime = PlayerData.findSlime(session.data, id)
	if not slime then
		return false, "not your slime"
	end
	slime.keep = if keep then true else nil
	World.markDirty(session)
	return true, nil
end

return MergeVat
