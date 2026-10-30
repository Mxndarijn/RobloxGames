--!strict
--[[
	Fountain

	Decides what the slime fountain spills out and where it lands (was
	Volcano; `Volcano.luau` is a thin alias). Pure: the server turns the
	returned spec into a slime model and its slide ride (FountainRide).
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local EggKind = if script then require(script.Parent.EggKind) else require("./EggKind")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")
local SlimeRoster = if script then require(script.Parent.SlimeRoster) else require("./SlimeRoster")

export type Drop = {
	slime: Genome.Slime,
	angle: number, -- radians around the fountain
	radius: number, -- studs from the fountain centre
}

local Fountain = {}

-- The landing-ring curb (WorldLayout Plaza.LandingRing: 18 tiles, bbox centre r 38.678, 13.145 x 10.27):
-- its farthest corner is at r 44.30. It is visual-only (no collider; slimes are anchored and script
-- moved, so no collision group could stop them), so wilds must never be placed or run through it.
Fountain.LANDING_RING_OUTER = 44.4
-- Biggest slime body radius (Config.SLIME_BASE_DIAMETER 3 x MAX_SIZE 2 / 2).
Fountain.SLIME_RADIUS = Config.SLIME_BASE_DIAMETER * Config.MAX_SIZE / 2
-- Landings start one margin stud past the curb for the widest slime (was 34: inside the ring).
Fountain.MIN_RADIUS = Fountain.LANDING_RING_OUTER + Fountain.SLIME_RADIUS + 1
Fountain.MAX_RADIUS = 62
-- The band no resting wild slime may occupy: from the old landing radius (31, inside the ring stones'
-- reach with the biggest slime) out to the curb's farthest corner. Spawns, lane/landing spots and
-- dropped wilds all go through clearOfRing, so they share this one band.
Fountain.RING_BAND_INNER = 31
Fountain.RING_BAND_OUTER = Fountain.LANDING_RING_OUTER

-- Whether a slime centred `r` studs from the axis overlaps the ring band (body radius SLIME_RADIUS).
function Fountain.inRingBand(r: number): boolean
	return r > Fountain.RING_BAND_INNER - Fountain.SLIME_RADIUS and r < Fountain.MIN_RADIUS
end

Fountain.UP_ON_HEIGHT = 3 -- studs over the plaza floor (y 0) a spot inside RING_BAND_INNER is up on the fountain

--[[
	Whether a spot (x, y, z: its feet) is up on the fountain or its slide, inside RING_BAND_INNER and more than
	UP_ON_HEIGHT over the plaza floor. A slime dropped up there has no way down to walk (the dome, the slide head and
	the slide's railed trough): it pops back onto the lane (contract/slime-walk.md). Under the slide is not up on it.
]]
function Fountain.upOn(x: number, y: number, z: number): boolean
	return x * x + z * z < Fountain.RING_BAND_INNER * Fountain.RING_BAND_INNER and y > Fountain.UP_ON_HEIGHT
end

-- (x, z) moved straight out from the axis to MIN_RADIUS when it sits in the ring band.
function Fountain.clearOfRing(x: number, z: number): (number, number)
	local r = math.sqrt(x * x + z * z)
	if not Fountain.inRingBand(r) then
		return x, z
	end
	local angle = math.atan2(z, x)
	return math.cos(angle) * Fountain.MIN_RADIUS, math.sin(angle) * Fountain.MIN_RADIUS
end

function Fountain.spawnInterval(raining: boolean): number
	return if raining then Config.RAIN_SPAWN_INTERVAL else Config.SPAWN_INTERVAL
end

-- `minTier` (optional, pity) keeps the rarity at or above that tier.
-- `luckMult` (optional, CycleModifier) scales the rarity luck.
-- `families` (optional, FEATURES.FountainTiers: FountainTiers.pool of the server's fountain tier) adds the open
-- families' species to the pool the species is picked from after the tier is rolled; `extraSpecies` (optional) adds
-- more entries (an event Secret), counted only at their own tier (Genome.speciesPool, contract/slime-odds.md).
function Fountain.roll(
	rng: Rng.Rng,
	id: string,
	raining: boolean,
	minTier: number?,
	luckMult: number?,
	families: { string }?,
	extraSpecies: { SlimeRoster.Entry }?
): Drop
	local slime = Genome.generate(rng, {
		id = id,
		minTier = minTier,
		luck = (if raining then Config.RAIN_LUCK else 1) * (luckMult or 1),
		families = families,
		extraSpecies = extraSpecies,
	})
	return {
		slime = slime,
		angle = rng:float() * math.pi * 2,
		radius = Fountain.MIN_RADIUS + rng:float() * (Fountain.MAX_RADIUS - Fountain.MIN_RADIUS),
	}
end

-- Seconds an unclaimed wild slime lives: WILD_LIFETIME, stretched for Mythic / Secret (Config.TIER_LIFETIME_MULT).
function Fountain.wildLifetime(slime: Genome.Slime): number
	-- A Mystery Egg lives by the tier it shows, never the hidden one inside.
	local tier = EggKind.shownTier(slime)
	return Config.WILD_LIFETIME * (Config.TIER_LIFETIME_MULT[tier] or 1)
end

return Fountain
