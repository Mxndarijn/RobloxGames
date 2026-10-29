--!strict
--[[
	MergeVat (pure, CONTRACT.md §21)

	The plot merge vat's requests over VatState (the rules) and World (busy slimes, toasts, effects):
	  * VatAdd(id): Move mode placed a pad slime in the vat. It keeps its pad (a see-through copy shows there).
	  * VatRemove(id): the menu's X; the slime is simply back on its own pad.
	  * VatStart / VatCancel: start the brew (Config.MERGE_BREW_SECONDS x Perks.brewFactor) or stop it; cancel
	    keeps the slimes in the vat.
	  * VatCollect: a finished brew merges (TripleMerge: recipe or random) onto the first input's pad. The roll's
	    seed is drawn from `world.rng` at Start, so the result is fixed before the clock runs.
	While brewing the inputs earn nothing and can't be stolen, moved or sold (VatState.isLocked; Income,
	StealService and Actions read it).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local MergeRecipes = if Shared then require(Shared.MergeRecipes) else require("../shared/MergeRecipes")
local Perks = if Shared then require(Shared.Perks) else require("../shared/Perks")
local Rng = if Shared then require(Shared.Rng) else require("../shared/Rng")
local VatState = if Shared then require(Shared.VatState) else require("../shared/VatState")
local GameAnalytics = if script then require(script.Parent.GameAnalytics) else require("./GameAnalytics")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

local MergeVat = {}

local function changed(_world: World, session: Session)
	World.markDirty(session)
end

function MergeVat.add(world: World, session: Session, id: string): (boolean, string?)
	if World.isBusy(world, id) then
		return false, "slime is busy"
	end
	local ok, reason = VatState.add(session.data, id)
	if not ok then
		return false, reason
	end
	changed(world, session)
	return true, nil
end

function MergeVat.remove(world: World, session: Session, id: string): (boolean, string?)
	local ok, reason = VatState.remove(session.data, id)
	if not ok then
		return false, reason
	end
	changed(world, session)
	return true, nil
end

function MergeVat.start(world: World, session: Session, now: number): (boolean, string?)
	for _, id in VatState.ids(session.data) do
		if World.isBusy(world, id) then
			return false, "slime is busy"
		end
	end
	local seed = world.rng:int(1, Rng.SEED_MAX)
	local ok, reason = VatState.start(session.data, now, Perks.brewFactor(session.data), seed)
	if not ok then
		return false, reason
	end
	changed(world, session)
	return true, nil
end

function MergeVat.cancel(world: World, session: Session): (boolean, string?)
	local ok, reason = VatState.cancel(session.data)
	if not ok then
		return false, reason
	end
	changed(world, session)
	return true, nil
end

function MergeVat.collect(world: World, session: Session, now: number): (boolean, string?)
	local known = table.clone(session.data.found)
	local found = MergeRecipes.foundOf(session.data.slimes, (session.data :: any).found)
	local ok, result = VatState.collect(session.data, now, world.rng, world.newId(), World.busySet(world))
	if not ok then
		return false, result :: string
	end
	local child = result :: Genome.Slime
	session.data.stats.merges += 1
	changed(world, session)
	local recipe = if child.species then MergeRecipes.recipeFor(child.species) else nil
	local isNew = child.species ~= nil and not known[child.species]
	local text = if recipe and not found[recipe.id]
		then `You discovered {child.name}!`
		elseif recipe then `You brewed a {child.name}!`
		else `Merged into a {Genome.displayName(child)}!` .. (if isNew then " (new SlimeDex entry)" else "")
	World.notify(world, session.userId, text, "good", if recipe then "Rare" else "Merge")
	World.effect(world, "Merge", { plotIndex = session.plotIndex, userId = session.userId })
	World.tutorial(world, session, "Merge")
	World.track(
		world,
		session.userId,
		{ op = "count", name = "Merged", fields = { GameAnalytics.tierField(child.tier) } }
	)
	if recipe and not found[recipe.id] then
		World.track(world, session.userId, { op = "event", name = "RecipeFound", fields = { `Recipe - {recipe.id}` } })
	end
	return true, nil
end

return MergeVat
