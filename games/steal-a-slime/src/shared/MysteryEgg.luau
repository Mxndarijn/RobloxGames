--!strict
--[[
	MysteryEgg (pure)

	A free egg (boss helpers, Server/MysteryEgg.spawnForEvent). It hatches into
	a slime rolled from Config.MYSTERY_EGG_DROPS (tier weights) through the same
	Genome.generate and PlayerData.addSlime path as every other slime, so the
	save format is unchanged.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")
local Types = if script then require(script.Parent.Types) else require("./Types")

type Data = PlayerData.Data

local MysteryEgg = {}

function MysteryEgg.weights(): { number }
	local weights = {}
	for i, drop in Config.MYSTERY_EGG_DROPS do
		weights[i] = drop.weight
	end
	return weights
end

-- Tier for one roll in [0, 1).
function MysteryEgg.rollTier(roll: number): number
	return Config.MYSTERY_EGG_DROPS[Rng.weightedIndex(MysteryEgg.weights(), roll)].tier
end

-- A fresh slime (no pad yet) from the drop table.
function MysteryEgg.hatch(rng: Rng.Rng, id: string): Genome.Slime
	return Genome.generate(rng, {
		id = id,
		tier = MysteryEgg.rollTier(rng:float()),
	})
end

--[[
	Hatches an egg onto the plot. Returns (true, slime) or (false, reason).
]]
function MysteryEgg.hatchInto(data: Data, rng: Rng.Rng, id: string): (boolean, Genome.Slime | string)
	if not PlayerData.freePad(data) then
		return false, "plot full"
	end
	local slime = MysteryEgg.hatch(rng, id)
	local ok, reason = PlayerData.addSlime(data, slime)
	if not ok then
		return false, reason :: string
	end
	return true, slime
end

function MysteryEgg.view(hatched: { slime: Genome.Slime, at: number }?): Types.EggView
	return { hatched = hatched }
end

return table.freeze(MysteryEgg)
