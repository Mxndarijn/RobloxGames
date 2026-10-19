--!strict
--[[
	MysteryEgg (pure)

	A Shop egg bought with in-game cash only (never Robux). It hatches into a
	slime rolled from Config.MYSTERY_EGG_DROPS (tier weights) through the same
	Genome.generate and PlayerData.addSlime path as every other slime, so the
	save format is unchanged. The price is MYSTERY_EGG_PRICE x the rebirth
	multiplier: a slime sells for 30 s of its (rebirth-scaled) income, so the
	egg never pays for itself. Nothing is charged when the plot is full.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Economy = if script then require(script.Parent.Economy) else require("./Economy")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")
local Types = if script then require(script.Parent.Types) else require("./Types")

type Data = PlayerData.Data

local MysteryEgg = {}

-- Cash price for this player.
function MysteryEgg.price(data: Data): number
	return math.floor(Config.MYSTERY_EGG_PRICE * Economy.rebirthMultiplier(data.rebirths))
end

function MysteryEgg.weights(): { number }
	local weights = {}
	for i, drop in Config.MYSTERY_EGG_DROPS do
		weights[i] = drop.weight
	end
	return weights
end

-- Chance of each tier: { [tier] = probability }; sums to 1.
function MysteryEgg.probabilities(): { [number]: number }
	local total = 0
	for _, drop in Config.MYSTERY_EGG_DROPS do
		total += drop.weight
	end
	local out = {}
	for _, drop in Config.MYSTERY_EGG_DROPS do
		out[drop.tier] = drop.weight / total
	end
	return out
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
	Hatches an egg onto the plot without charging (events, admin grants).
	Returns (true, slime) or (false, reason).
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

--[[
	Buys and hatches an egg with cash. Returns (true, slime) or (false, reason).
	The plot and the cash are checked before anything changes.
]]
function MysteryEgg.buy(data: Data, rng: Rng.Rng, id: string): (boolean, Genome.Slime | string)
	if not PlayerData.freePad(data) then
		return false, "plot full"
	end
	if not PlayerData.spend(data, MysteryEgg.price(data)) then
		return false, "not enough cash"
	end
	return MysteryEgg.hatchInto(data, rng, id)
end

function MysteryEgg.view(data: Data, hatched: { slime: Genome.Slime, at: number }?): Types.EggView
	return { price = MysteryEgg.price(data), hatched = hatched }
end

return table.freeze(MysteryEgg)
