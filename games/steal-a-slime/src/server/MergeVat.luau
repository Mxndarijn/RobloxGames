--!strict
--[[
	MergeVat (pure)

	Request("Merge", a, b): two owned, not-busy slimes of the same tier become
	one slime of tier + 1 on the first slime's pad (Shared.Merge.apply).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local Merge = if Shared then require(Shared.Merge) else require("../shared/Merge")
local TripleMerge = if Shared then require(Shared.TripleMerge) else require("../shared/TripleMerge")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

local MergeVat = {}

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
	World.effect(world, "Merge", { plotIndex = session.plotIndex, userId = session.userId })
	World.tutorial(world, session, "Merge")
	return true, nil
end

return MergeVat
