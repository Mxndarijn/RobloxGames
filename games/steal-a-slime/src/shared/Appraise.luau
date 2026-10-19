--!strict
--[[
	Appraise

	Pay Config.APPRAISE_COST_FRACTION of an owned slime's current value
	(Economy.sellPrice) to reroll its size. Only that
	field of the slime changes, so the save format is untouched. The roll comes
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

Appraise.KINDS = table.freeze({ "size" })

-- Price to reroll `slime` at the owner's rebirth count (at least 1).
function Appraise.cost(slime: Genome.Slime, rebirths: number): number
	return math.max(1, math.floor(Economy.sellPrice(slime, rebirths) * Config.APPRAISE_COST_FRACTION))
end

function Appraise.rollSize(roll: number): number
	local size = Config.MIN_SIZE + roll * (Config.MAX_SIZE - Config.MIN_SIZE)
	return math.clamp(math.floor(size * 100 + 0.5) / 100, Config.MIN_SIZE, Config.MAX_SIZE)
end

--[[
	Rerolls `kind` ("size") of the owned slime `id`. Returns
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
	if kind ~= "size" then
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
		beforeSize = slime.size,
		afterSize = slime.size,
	}
	slime.size = Appraise.rollSize(rng:float())
	appraisal.afterSize = slime.size
	return true, appraisal
end

return table.freeze(Appraise)
