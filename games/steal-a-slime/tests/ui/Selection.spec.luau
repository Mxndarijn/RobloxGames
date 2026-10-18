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

describe("Selection.vatLoad", function()
	local function rarity(tier: number): string
		return if tier == 1 then "Common" else "Uncommon"
	end
	local kept = { slime = { id = "k", tier = 1, name = "Blob", keep = true }, income = 1 }
	local all = { slimes[1], slimes[2], slimes[3], slimes[4], kept, view("e", 1, 3) }
	it("accepts distinct owned slimes of one rarity, for the pair and the 3-slime vat", function()
		expect((Selection.vatLoad(all, { "a", "b" }, 2))).toBe(true)
		expect((Selection.vatLoad(all, { "a", "b", "e" }, 3))).toBe(true)
	end)
	it("counts down what is still missing", function()
		expect(select(2, Selection.vatLoad(all, {}, 3))).toBe("Pick 3 slimes of the same rarity")
		expect(select(2, Selection.vatLoad(all, { "a" }, 3, rarity))).toBe("Pick 2 more Common slimes")
		expect(select(2, Selection.vatLoad(all, { "a", "b" }, 3, rarity))).toBe("Pick 1 more Common slime")
	end)
	it("rejects repeats, mixed rarities, stolen, kept and missing slimes with a reason", function()
		expect(select(2, Selection.vatLoad(all, { "a", "a" }, 2))).toBe("Pick 2 different slimes")
		expect(select(2, Selection.vatLoad(all, { "a", "c" }, 2))).toBe("All 2 must be the same rarity")
		expect(select(2, Selection.vatLoad(all, { "a", "d" }, 2))).toBe("This slime is being stolen")
		expect(select(2, Selection.vatLoad(all, { "a", "k" }, 2))).toBe("Blob is kept: tap 🔒 to free it")
		expect(select(2, Selection.vatLoad(all, { "a", "zzz" }, 2))).toBe("A slime left your plot")
	end)
end)

describe("Selection.pick", function()
	it("adds, removes, and starts over on another rarity", function()
		local s = Selection.pick({}, "a", slimes, 3)
		s = Selection.pick(s, "b", slimes, 3)
		expect(s).toEqual({ "a", "b" })
		expect(Selection.pick(s, "a", slimes, 3)).toEqual({ "b" })
		expect(Selection.pick(s, "c", slimes, 3)).toEqual({ "c" })
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
