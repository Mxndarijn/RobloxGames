--!strict
--[[
	Fountain

	Decides what the slime fountain spills out and where it lands (was
	Volcano; `Volcano.luau` is a thin alias). Pure: the server turns the
	returned spec into a slime model and its slide ride (FountainRide).
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")

export type Drop = {
	slime: Genome.Slime,
	angle: number, -- radians around the fountain
	radius: number, -- studs from the fountain centre
}

local Fountain = {}

Fountain.MIN_RADIUS = 34
Fountain.MAX_RADIUS = 62

function Fountain.spawnInterval(raining: boolean): number
	return if raining then Config.RAIN_SPAWN_INTERVAL else Config.SPAWN_INTERVAL
end

-- `minTier` (optional, pity) keeps the rarity at or above that tier.
-- `luckMult` / `mutationMult` (optional, CycleModifier) scale the rarity luck and mutation chance.
function Fountain.roll(
	rng: Rng.Rng,
	id: string,
	raining: boolean,
	minTier: number?,
	luckMult: number?,
	mutationMult: number?
): Drop
	local baseChance = if raining then Config.RAIN_MUTATION_CHANCE else Config.DROP_MUTATION_CHANCE
	local slime = Genome.generate(rng, {
		id = id,
		minTier = minTier,
		mutationChance = math.min(1, baseChance * (mutationMult or 1)),
		luck = (if raining then Config.RAIN_LUCK else 1) * (luckMult or 1),
	})
	return {
		slime = slime,
		angle = rng:float() * math.pi * 2,
		radius = Fountain.MIN_RADIUS + rng:float() * (Fountain.MAX_RADIUS - Fountain.MIN_RADIUS),
	}
end

-- Whether another wild slime may spawn.
function Fountain.canSpawn(wildCount: number, raining: boolean): boolean
	local cap = if raining then Config.MAX_WILD_SLIMES * 2 else Config.MAX_WILD_SLIMES
	return wildCount < cap
end

return Fountain
