--!strict
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Merge = require("../src/shared/Merge")
local PlayerData = require("../src/shared/PlayerData")
local Rng = require("../src/shared/Rng")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local slime = Fixtures.slime

describe("Merge.canMerge", function()
	it("requires two different slimes of the same tier", function()
		expect((Merge.canMerge(slime("a", 1), slime("b", 1)))).toBe(true)
		expect((Merge.canMerge(slime("a", 1), slime("b", 2)))).toBe(false)
		expect((Merge.canMerge(slime("a", 1), slime("a", 1)))).toBe(false)
		expect((Merge.canMerge(slime("a", 1), nil))).toBe(false)
	end)
end)

describe("Merge.merge", function()
	it("produces the next tier with blended colour and bigger size", function()
		local a = slime("a", 2, { color = { 200, 0, 100 }, size = 1 })
		local b = slime("b", 2, { color = { 100, 50, 0 }, size = 1.2 })
		local child = Merge.merge(a, b, Rng.new(3), "c")
		expect(child.id).toBe("c")
		expect(child.tier).toBe(3)
		expect(child.color).toEqual({ 150, 25, 50 })
		expect(child.size).toBeCloseTo(1.1 + Config.MERGE_SIZE_BONUS, 1e-9)
	end)
	it("caps tier at MAX_TIER", function()
		local rng = Rng.new(10)
		for i = 1, 30 do
			local child = Merge.merge(slime("a", Config.MAX_TIER), slime("b", Config.MAX_TIER), rng, `c{i}`)
			expect(child.tier).toBe(Config.MAX_TIER)
		end
	end)
	it("is deterministic for a seed", function()
		local x = Merge.merge(slime("a", 1), slime("b", 1, { name = "Gloop" }), Rng.new(5), "c")
		local y = Merge.merge(slime("a", 1), slime("b", 1, { name = "Gloop" }), Rng.new(5), "c")
		expect(x).toEqual(y)
		expect(x.name).toBe("Bloop")
	end)
end)

describe("Merge.findPair", function()
	it("picks the highest tier with a pair, cheapest first", function()
		local list = {
			slime("a", 1),
			slime("b", 1),
			slime("c", 3, { size = 2 }),
			slime("d", 3, { size = 1 }),
			slime("e", 3, { size = 1.5 }),
			slime("f", 4),
		}
		local x, y = Merge.findPair(list)
		expect(x).toBe("d")
		expect(y).toBe("e")
	end)
	it("skips busy slimes and avoids the favourite", function()
		local list = { slime("a", 2), slime("b", 2), slime("c", 2, { size = 2 }) }
		local x, y = Merge.findPair(list, { b = true }, "a")
		expect(x).toBe("c")
		expect(y).toBe("a")
	end)
	it("returns nil when nothing matches", function()
		expect((Merge.findPair({ slime("a", 1), slime("b", 2) }))).toBeNil()
	end)
end)

describe("Merge.apply", function()
	it("consumes both inputs and puts the child on the first pad", function()
		local data = Fixtures.data({ slime("a", 1), slime("b", 2), slime("c", 1) })
		local ok, child = Merge.apply(data, "c", "a", nil, Rng.new(1), "new")
		expect(ok).toBe(true)
		assert(type(child) == "table", "precondition")
		expect(#data.slimes).toBe(2)
		expect(PlayerData.findSlime(data, "a")).toBeNil()
		expect(PlayerData.findSlime(data, "c")).toBeNil()
		expect(child.pad).toBe(3)
		expect(child.tier).toBe(2)
	end)
	it("rejects busy, unowned or mismatched slimes without changes", function()
		local data = Fixtures.data({ slime("a", 1), slime("b", 1), slime("c", 2) })
		expect((Merge.apply(data, "a", "b", { b = true }, Rng.new(1), "n"))).toBe(false)
		expect((Merge.apply(data, "a", "zzz", nil, Rng.new(1), "n"))).toBe(false)
		expect((Merge.apply(data, "a", "c", nil, Rng.new(1), "n"))).toBe(false)
		expect(#data.slimes).toBe(3)
	end)
	it("moves the favourite flag to the child", function()
		local data = Fixtures.data({ slime("a", 1), slime("b", 1) })
		data.favoriteId = "b"
		Merge.apply(data, "a", "b", nil, Rng.new(1), "n")
		expect(data.favoriteId).toBe("n")
	end)
end)
