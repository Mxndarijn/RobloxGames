--!strict
--[[
	Rng: deterministic Park-Miller generator, so a seed gives the same sequence under Lune and in Roblox.

	Anything that accepts a "roll" takes a `() -> number` returning [0, 1); `rng:roller()` gives one.

		local rng = Rng.new(42)
		rng:float()            -- [0, 1)
		rng:int(1, 6)          -- 1..6 inclusive
		rng:pick({ "a", "b" }) -- one element
		Rng.weightedIndex({ 1, 3 }, rng:float())
]]

export type Rng = {
	state: number,
	float: (self: Rng) -> number,
	int: (self: Rng, min: number, max: number) -> number,
	pick: <T>(self: Rng, list: { T }) -> T,
	weighted: (self: Rng, weights: { number }) -> number,
	roller: (self: Rng) -> () -> number,
}

local MODULUS = 2147483647
local MULTIPLIER = 48271

local Rng = {}
Rng.__index = Rng

-- Largest seed `new` keeps as given: draw seeds for later generators with `rng:int(1, Rng.SEED_MAX)`.
Rng.SEED_MAX = MODULUS - 1

local function normalizeSeed(seed: number?): number
	local n = tonumber(seed) or 1
	if n ~= n or n == math.huge or n == -math.huge then
		n = 1
	end
	local s = math.floor(math.abs(n)) % MODULUS
	if s == 0 then
		s = 1
	end
	return s
end

-- A seed of nil, 0 or a non-finite number is replaced by 1 (Park-Miller needs a state in 1..MODULUS-1).
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

-- One element of a non-empty list (nil for an empty list).
function Rng.pick<T>(self: Rng, list: { T }): T
	return list[self:int(1, #list)]
end

-- Index into `weights`, chosen with probability proportional to each weight.
function Rng.weighted(self: Rng, weights: { number }): number
	return Rng.weightedIndex(weights, self:float())
end

-- A plain roll function `() -> number` backed by this generator.
function Rng.roller(self: Rng): () -> number
	return function()
		return self:float()
	end
end

-- Picks an index from a list of weights using one roll in [0, 1). Negative weights count as 0; all-zero weights
-- give 1.
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

return table.freeze(Rng)
