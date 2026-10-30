--!strict
local Rng = require("../src/core/Rng")
local T = require("../testing/TestRunner")
local describe, it, expect = T.describe, T.it, T.expect

describe("Rng", function()
	it("gives the same sequence for the same seed", function()
		local a, b = Rng.new(42), Rng.new(42)
		for _ = 1, 20 do
			expect(a:float()).toBe(b:float())
		end
	end)

	it("gives different sequences for different seeds", function()
		local a, b = Rng.new(1), Rng.new(2)
		expect(a:float() == b:float()).toBe(false)
	end)

	it("matches the Park-Miller sequence for seed 1", function()
		local rng = Rng.new(1)
		rng:float()
		expect(rng.state).toBe(48271)
		rng:float()
		expect(rng.state).toBe(182605794)
	end)

	it("treats nil, 0 and non-finite seeds as 1", function()
		local one = Rng.new(1):float()
		expect(Rng.new(nil):float()).toBe(one)
		expect(Rng.new(0):float()).toBe(one)
		expect(Rng.new(math.huge):float()).toBe(one)
		expect(Rng.new(0 / 0):float()).toBe(one)
	end)

	it("float stays in [0, 1)", function()
		local rng = Rng.new(7)
		for _ = 1, 2000 do
			local f = rng:float()
			expect(f >= 0 and f < 1).toBe(true)
		end
	end)

	it("int covers [min, max] inclusive and nothing else", function()
		local rng = Rng.new(99)
		local seen = {}
		for _ = 1, 2000 do
			local n = rng:int(3, 6)
			expect(n >= 3 and n <= 6 and n == math.floor(n)).toBe(true)
			seen[n] = true
		end
		expect(seen).toEqual({ [3] = true, [4] = true, [5] = true, [6] = true })
	end)

	it("int with min == max always returns that value", function()
		local rng = Rng.new(5)
		for _ = 1, 10 do
			expect(rng:int(4, 4)).toBe(4)
		end
	end)

	it("pick returns elements of the list", function()
		local rng = Rng.new(3)
		local list = { "a", "b", "c" }
		for _ = 1, 50 do
			expect(table.find(list, rng:pick(list)) ~= nil).toBe(true)
		end
	end)

	it("roller returns a function that advances the generator", function()
		local a, b = Rng.new(11), Rng.new(11)
		local roll = a:roller()
		expect(roll()).toBe(b:float())
		expect(roll()).toBe(b:float())
	end)

	it("weighted uses one float roll", function()
		local a, b = Rng.new(8), Rng.new(8)
		expect(a:weighted({ 1, 1, 1 })).toBe(Rng.weightedIndex({ 1, 1, 1 }, b:float()))
	end)
end)

describe("Rng.weightedIndex", function()
	it("maps the roll onto cumulative weights", function()
		local w = { 1, 3 }
		expect(Rng.weightedIndex(w, 0)).toBe(1)
		expect(Rng.weightedIndex(w, 0.24)).toBe(1)
		expect(Rng.weightedIndex(w, 0.25)).toBe(2)
		expect(Rng.weightedIndex(w, 0.999)).toBe(2)
	end)

	it("never picks zero or negative weights", function()
		local w = { 0, -5, 2 }
		expect(Rng.weightedIndex(w, 0)).toBe(3)
		expect(Rng.weightedIndex(w, 0.5)).toBe(3)
	end)

	it("returns 1 when every weight is zero or the list is empty", function()
		expect(Rng.weightedIndex({ 0, 0 }, 0.5)).toBe(1)
		expect(Rng.weightedIndex({}, 0.5)).toBe(1)
	end)

	it("clamps a roll of 1 to the last index", function()
		expect(Rng.weightedIndex({ 1, 1 }, 1)).toBe(2)
	end)
end)

describe("Rng.SEED_MAX", function()
	it("is the largest seed new keeps as given", function()
		expect(Rng.new(Rng.SEED_MAX).state).toBe(Rng.SEED_MAX)
		expect(Rng.new(Rng.SEED_MAX + 1).state).toBe(1)
	end)
end)
