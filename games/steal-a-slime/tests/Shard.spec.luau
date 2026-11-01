--!strict
local Shard = require("./Shard")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local SPECS = { "A.spec", "B.spec", "C.spec", "D.spec", "E.spec", "ui/F.spec", "ui/G.spec" }
local WEIGHTS = { ["A.spec"] = 70, ["B.spec"] = 50, ["C.spec"] = 30, ["D.spec"] = 20 }

describe("Shard.pick", function()
	it("puts every spec in exactly one shard", function()
		for n = 1, 5 do
			local seen = {}
			for k = 1, n do
				for _, spec in Shard.pick(SPECS, WEIGHTS, k, n) do
					expect(seen[spec]).toBeNil()
					seen[spec] = true
				end
			end
			for _, spec in SPECS do
				expect(seen[spec]).toBe(true)
			end
		end
	end)

	it("keeps the heaviest specs apart", function()
		local shardOf = {}
		for k = 1, 3 do
			for _, spec in Shard.pick(SPECS, WEIGHTS, k, 3) do
				shardOf[spec] = k
			end
		end
		expect(shardOf["A.spec"] ~= shardOf["B.spec"]).toBe(true)
		expect(shardOf["A.spec"] ~= shardOf["C.spec"]).toBe(true)
		expect(shardOf["B.spec"] ~= shardOf["C.spec"]).toBe(true)
	end)

	it("keeps the input order inside a shard and gives the same split every time", function()
		local first = Shard.pick(SPECS, WEIGHTS, 2, 3)
		expect(Shard.pick(SPECS, WEIGHTS, 2, 3)).toEqual(first)
		local index = {}
		for i, spec in SPECS do
			index[spec] = i
		end
		for i = 2, #first do
			expect(index[first[i - 1]] < index[first[i]]).toBe(true)
		end
	end)

	it("is the whole list with one shard", function()
		expect(Shard.pick(SPECS, WEIGHTS, 1, 1)).toEqual(SPECS)
	end)

	it("rejects a shard outside 1..n", function()
		expect(pcall(Shard.pick, SPECS, WEIGHTS, 0, 2)).toBe(false)
		expect(pcall(Shard.pick, SPECS, WEIGHTS, 3, 2)).toBe(false)
	end)
end)
