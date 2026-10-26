--!strict
--[[
	WorldSeed (pure)

	Picks the seeds of a live server's world generators. `nextInteger` is the engine's random source
	(Random:NextInteger on the server), so the seeds never come from the clock or from each other: a
	player who knows the start time or one generator's state learns nothing about the egg generator or
	the cycle modifier. Tests build the World with fixed seeds instead.
]]

local WorldSeed = {}

WorldSeed.MAX = 2147483646 -- Rng state range is 1 .. 2^31 - 2

export type Seeds = { world: number, egg: number }

function WorldSeed.pick(nextInteger: (min: number, max: number) -> number): Seeds
	return {
		world = nextInteger(1, WorldSeed.MAX),
		egg = nextInteger(1, WorldSeed.MAX),
	}
end

return WorldSeed
