--!strict
--[[
	Volcano

	Decides what the volcano spits out and where it lands. Pure: the server
	turns the returned spec into a slime model and a bounce tween.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")

export type Drop = {
	slime: Genome.Slime,
	angle: number, -- radians around the volcano
	radius: number, -- studs from the volcano centre
}

local Volcano = {}

Volcano.MIN_RADIUS = 34
Volcano.MAX_RADIUS = 62

function Volcano.spawnInterval(raining: boolean): number
	return if raining then Config.RAIN_SPAWN_INTERVAL else Config.SPAWN_INTERVAL
end

-- `minTier` (optional, pity) keeps the rarity at or above that tier.
function Volcano.roll(rng: Rng.Rng, id: string, raining: boolean, minTier: number?): Drop
	local slime = Genome.generate(rng, {
		id = id,
		minTier = minTier,
		mutationChance = if raining then Config.RAIN_MUTATION_CHANCE else Config.DROP_MUTATION_CHANCE,
		luck = if raining then Config.RAIN_LUCK else 1,
	})
	return {
		slime = slime,
		angle = rng:float() * math.pi * 2,
		radius = Volcano.MIN_RADIUS + rng:float() * (Volcano.MAX_RADIUS - Volcano.MIN_RADIUS),
	}
end

-- Whether another wild slime may spawn.
function Volcano.canSpawn(wildCount: number, raining: boolean): boolean
	local cap = if raining then Config.MAX_WILD_SLIMES * 2 else Config.MAX_WILD_SLIMES
	return wildCount < cap
end

return Volcano
