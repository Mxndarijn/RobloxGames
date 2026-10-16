--!strict
--[[
	Fountain

	Decides what the slime fountain spills out and where it lands (was
	Volcano; `Volcano.luau` is a thin alias). Pure: the server turns the
	returned spec into a slime model and a bounce tween.
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
function Fountain.roll(rng: Rng.Rng, id: string, raining: boolean, minTier: number?): Drop
	local slime = Genome.generate(rng, {
		id = id,
		minTier = minTier,
		mutationChance = if raining then Config.RAIN_MUTATION_CHANCE else Config.DROP_MUTATION_CHANCE,
		luck = if raining then Config.RAIN_LUCK else 1,
	})
	return {
		slime = slime,
		angle = rng:float() * math.pi * 2,
		radius = Fountain.MIN_RADIUS + rng:float() * (Fountain.MAX_RADIUS - Fountain.MIN_RADIUS),
	}
end

-- Run-out from the spiral mouth to a rolled landing. The slide turns towards
-- +angle (atan2(z, x)) at its mouth; landings up to RUN_OUT_AHEAD radians
-- ahead keep going that way, the rest swing back the short way.
Fountain.RUN_OUT_AHEAD = math.pi * 1.25

local function polar(p: { number }): (number, number)
	return math.atan2(p[3], p[1]), math.sqrt(p[1] * p[1] + p[3] * p[3])
end

-- Signed turn (radians) the run-out makes around the fountain axis.
local function sweep(mouth: { number }, landing: { number }): number
	local a0 = polar(mouth)
	local a1 = polar(landing)
	local d = (a1 - a0) % (math.pi * 2)
	return if d > Fountain.RUN_OUT_AHEAD then d - math.pi * 2 else d
end

-- True when the run-out keeps the slide's direction of travel.
function Fountain.runOutAhead(mouth: { number }, landing: { number }): boolean
	return sweep(mouth, landing) >= 0
end

-- World position at u in 0..1 of the run-out (mouth / landing are { x, y, z },
-- fountain axis at the origin). Polar: the radius stays between the mouth's
-- and the landing's, so the path curls round the fountain instead of cutting
-- through it; the radius eases in so the slime leaves along the slide.
function Fountain.runOut(mouth: { number }, landing: { number }, u: number): (number, number, number)
	u = math.clamp(u, 0, 1)
	if u >= 1 then
		return landing[1], landing[2], landing[3]
	end
	local a0, r0 = polar(mouth)
	local _, r1 = polar(landing)
	local angle = a0 + sweep(mouth, landing) * u
	local r = r0 + (r1 - r0) * (u * u * (3 - 2 * u))
	return math.cos(angle) * r, mouth[2] + (landing[2] - mouth[2]) * u, math.sin(angle) * r
end

-- Whether another wild slime may spawn.
function Fountain.canSpawn(wildCount: number, raining: boolean): boolean
	local cap = if raining then Config.MAX_WILD_SLIMES * 2 else Config.MAX_WILD_SLIMES
	return wildCount < cap
end

return Fountain
