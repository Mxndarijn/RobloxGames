--!strict
-- Pure UI selection helpers (src/ui/Selection.luau).
local Selection = require("../../src/ui/Selection")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function view(id: string, tier: number, income: number, stolenBy: number?)
	return { slime = { id = id, tier = tier }, income = income, stolenBy = stolenBy }
end

local slimes = {
	view("a", 1, 1),
	view("b", 1, 2),
	view("c", 2, 5),
	view("d", 1, 1, 42),
}

describe("Selection.canMergePair", function()
	it("accepts two distinct owned slimes of the same tier", function()
		expect((Selection.canMergePair(slimes, "a", "b"))).toBe(true)
	end)
	it("rejects missing, identical, mixed-tier and stolen picks", function()
		expect((Selection.canMergePair(slimes, "a", nil))).toBe(false)
		expect((Selection.canMergePair(slimes, "a", "a"))).toBe(false)
		expect((Selection.canMergePair(slimes, "a", "c"))).toBe(false)
		expect((Selection.canMergePair(slimes, "a", "d"))).toBe(false)
		expect((Selection.canMergePair(slimes, "a", "zzz"))).toBe(false)
	end)
	it("explains why", function()
		local _, reason = Selection.canMergePair(slimes, "a", "c")
		expect(reason).toBe("Slimes must be the same tier")
	end)
end)

describe("Selection.toggle / prune", function()
	it("adds, removes and keeps at most two (oldest dropped)", function()
		local s = Selection.toggle({}, "a")
		expect(s).toEqual({ "a" })
		s = Selection.toggle(s, "b")
		expect(s).toEqual({ "a", "b" })
		s = Selection.toggle(s, "c")
		expect(s).toEqual({ "b", "c" })
		s = Selection.toggle(s, "b")
		expect(s).toEqual({ "c" })
	end)
	it("does not modify its input", function()
		local s = { "a" }
		Selection.toggle(s, "b")
		expect(s).toEqual({ "a" })
	end)
	it("prunes ids that are gone or being stolen", function()
		expect(Selection.prune({ "a", "d", "gone" }, slimes)).toEqual({ "a" })
	end)
end)

describe("Selection.sorted", function()
	it("puts the favourite first, then tier desc, income desc", function()
		local order = {}
		for _, v in Selection.sorted(slimes, "a") do
			table.insert(order, v.slime.id)
		end
		expect(order).toEqual({ "a", "c", "b", "d" })
	end)
end)

describe("Selection.pickSlapTarget", function()
	it("picks the nearest carrier within reach, never yourself", function()
		local candidates = {
			{ userId = 1, distance = 2 },
			{ userId = 2, distance = 8 },
			{ userId = 3, distance = 5 },
			{ userId = 4, distance = 30 },
		}
		expect(Selection.pickSlapTarget(candidates, 10, 1)).toBe(3)
		expect(Selection.pickSlapTarget(candidates, 1, nil)).toBeNil()
		expect(Selection.pickSlapTarget({}, 10, nil)).toBeNil()
	end)
end)
