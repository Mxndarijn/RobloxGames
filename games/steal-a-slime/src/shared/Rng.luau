--!strict
--[[
	Rng

	Deterministic Park-Miller LCG so a seed gives the same slime in Lune and in
	Roblox. Anything that accepts a "roll" takes a `() -> number` returning
	[0, 1); `Rng.new(seed):float` style closures satisfy that.
]]

export type Rng = {
	state: number,
	float: (self: Rng) -> number,
	int: (self: Rng, min: number, max: number) -> number,
	pick: <T>(self: Rng, list: { T }) -> T,
}

local MODULUS = 2147483647
local MULTIPLIER = 48271

local Rng = {}
Rng.__index = Rng

-- Largest seed `new` keeps as given: draw roll seeds with `rng:int(1, Rng.SEED_MAX)`.
Rng.SEED_MAX = MODULUS - 1

local function normalizeSeed(seed: number?): number
	local s = math.floor(math.abs(tonumber(seed) or 1)) % MODULUS
	if s == 0 then
		s = 1
	end
	return s
end

function Rng.new(seed: number?): Rng
	local self = setmetatable({ state = normalizeSeed(seed) }, Rng)
	return (self :: any) :: Rng
end

-- Uniform float in [0, 1).
function Rng.float(self: Rng): number
	self.state = (self.state * MULTIPLIER) % MODULUS
	return (self.state - 1) / (MODULUS - 1)
end

-- Uniform integer in [min, max] (inclusive).
function Rng.int(self: Rng, min: number, max: number): number
	return min + math.floor(self:float() * (max - min + 1))
end

function Rng.pick<T>(self: Rng, list: { T }): T
	return list[self:int(1, #list)]
end

-- Returns a plain roll function `() -> number` backed by this generator.
function Rng.roller(self: Rng): () -> number
	return function()
		return self:float()
	end
end

-- Picks an index from a list of weights, using one roll in [0, 1).
function Rng.weightedIndex(weights: { number }, roll: number): number
	local total = 0
	for _, w in weights do
		total += math.max(0, w)
	end
	if total <= 0 then
		return 1
	end
	local target = roll * total
	local acc = 0
	for i, w in weights do
		acc += math.max(0, w)
		if target < acc then
			return i
		end
	end
	return #weights
end

return Rng
