--!strict
--[[
	Appraise

	Pay Config.APPRAISE_COST_FRACTION of an owned slime's current value
	(Economy.sellPrice) to reroll its mutation or its size. Only those two
	fields of the slime change, so the save format is untouched. The roll comes
	from the caller's Rng, so a seed gives the same result in Lune and Roblox.
	Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Economy = if script then require(script.Parent.Economy) else require("./Economy")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")
local Types = if script then require(script.Parent.Types) else require("./Types")

local Appraise = {}

Appraise.KINDS = table.freeze({ "mutation", "size" })

-- Price to reroll `slime` at the owner's rebirth count (at least 1).
function Appraise.cost(slime: Genome.Slime, rebirths: number): number
	return math.max(1, math.floor(Economy.sellPrice(slime, rebirths) * Config.APPRAISE_COST_FRACTION))
end

function Appraise.rollSize(roll: number): number
	local size = Config.MIN_SIZE + roll * (Config.MAX_SIZE - Config.MIN_SIZE)
	return math.clamp(math.floor(size * 100 + 0.5) / 100, Config.MIN_SIZE, Config.MAX_SIZE)
end

--[[
	Rerolls `kind` ("mutation" | "size") of the owned slime `id`. Returns
	(true, appraisal) or (false, reason). Checks ownership, kind and cash
	before anything is spent or changed.
]]
function Appraise.reroll(
	data: PlayerData.Data,
	id: string,
	kind: string,
	rng: Rng.Rng
): (boolean, Types.Appraisal | string)
	local slime = PlayerData.findSlime(data, id)
	if not slime then
		return false, "not your slime"
	end
	if kind ~= "mutation" and kind ~= "size" then
		return false, "bad argument"
	end
	local cost = Appraise.cost(slime, data.rebirths)
	if not PlayerData.spend(data, cost) then
		return false, "not enough cash"
	end
	local appraisal: Types.Appraisal = {
		slimeId = id,
		kind = kind,
		cost = cost,
		beforeMutation = slime.mutation,
		afterMutation = slime.mutation,
		beforeMutations = Genome.mutationList(slime),
		afterMutations = Genome.mutationList(slime),
		beforeSize = slime.size,
		afterSize = slime.size,
	}
	if kind == "mutation" then
		local first = Genome.rollMutation(rng:float(), rng:float(), Config.APPRAISE_MUTATION_CHANCE)
		-- A reroll replaces the whole list; with stacking it can land on several (and combos).
		Genome.setMutations(slime, Genome.stackMutations(if first == "None" then {} else { first }, rng))
		appraisal.afterMutation = slime.mutation
		appraisal.afterMutations = Genome.mutationList(slime)
		PlayerData.discover(data, slime)
	else
		slime.size = Appraise.rollSize(rng:float())
		appraisal.afterSize = slime.size
	end
	return true, appraisal
end

return table.freeze(Appraise)
