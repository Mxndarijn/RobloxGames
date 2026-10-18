--!strict
local Appraise = require("../src/shared/Appraise")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Genome = require("../src/shared/Genome")
local Merge = require("../src/shared/Merge")
local Rng = require("../src/shared/Rng")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function rolls(values: { number }): any
	local f = Fixtures.rolls(values)
	return {
		float = function()
			return f()
		end,
	}
end

describe("MutationStacking config", function()
	it("is a flagged feature, default on, with a cap and combos over real mutations", function()
		expect(Config.FEATURES.MutationStacking).toBe(true)
		expect(Config.MAX_MUTATIONS).toBe(3)
		for _, c in Config.COMBOS do
			expect(Genome.mutationInfo(c.a) ~= nil and Genome.mutationInfo(c.b) ~= nil).toBe(true)
			expect(c.multiplier > Genome.mutationMultiplier(c.a) * Genome.mutationMultiplier(c.b)).toBe(true)
			for _, m in Config.MUTATIONS do
				expect(m.name ~= c.name).toBe(true)
			end
		end
	end)
end)

describe("Genome stacking", function()
	it("adds, dedupes and caps", function()
		local l = Genome.addMutation({}, "Glow")
		expect(Genome.addMutation(l, "Glow")).toEqual({ "Glow" })
		expect(Genome.addMutation(l, "None")).toEqual({ "Glow" })
		expect(Genome.addMutation(l, "Bogus")).toEqual({ "Glow" })
		l = Genome.addMutation(Genome.addMutation(l, "Gold"), "Eclipse")
		expect(Genome.addMutation({ "Glow", "Gold", "Eclipse" }, "Rainbow")).toEqual({ "Glow", "Gold", "Eclipse" })
		expect(#l).toBe(3)
	end)
	it("fuses a combo pair in either order, and the combo counts once", function()
		expect(Genome.addMutation({ "Glow" }, "Lava")).toEqual({ "Solar" })
		expect(Genome.addMutation({ "Lava" }, "Glow")).toEqual({ "Solar" })
		-- full list still takes a mutation that fuses
		expect(Genome.addMutation({ "Gold", "Glow", "Eclipse" }, "Lava")).toEqual({ "Gold", "Solar", "Eclipse" })
	end)
	it("multiplies the value of every mutation, combos use their own multiplier", function()
		expect(Genome.mutationsMultiplier({})).toBe(1)
		expect(Genome.mutationsMultiplier({ "Gold", "Crystal" })).toBe(35)
		expect(Genome.mutationsMultiplier({ "Solar" })).toBe(4)
		local s = Fixtures.slime("a", 3, { size = 2 })
		Genome.setMutations(s, { "Gold", "Glow" })
		expect(Genome.baseIncome(s)).toBe(Config.RARITIES[3].income * 2 * 7.5)
		expect(s.mutation).toBe("Gold")
	end)
	it("old single-field slimes keep their value", function()
		local s = Fixtures.slime("a", 3, { mutation = "Lava" })
		expect(Genome.baseIncome(s)).toBe(Config.RARITIES[3].income * 2)
		expect(Genome.primaryMutation(Genome.mutationList(s))).toBe("Lava")
	end)
	it("labels show all mutations; the primary is the strongest", function()
		local s = Fixtures.slime("a", 1)
		Genome.setMutations(s, { "Glow", "Lava" })
		expect(Genome.displayName(s)).toBe("Glow Syrup Common Blorp")
		expect(Genome.primaryMutation(Genome.mutationList(s))).toBe("Lava")
		Genome.setMutations(s, { "Solar" })
		expect(Genome.displayName(s)).toBe("Solar Common Blorp")
	end)
	it("stackMutations rolls extra mutations per free slot and stops on a miss", function()
		-- chance float below 0.25 = hit; then pick float
		local hit = Genome.stackMutations({ "Glow" }, rolls({ 0.1, 0.99, 0.9 }))
		expect(#hit >= 1).toBe(true)
		expect(hit[1]).toBe("Glow")
		expect(Genome.stackMutations({ "Glow" }, rolls({ 0.9 }))).toEqual({ "Glow" })
		expect(Genome.stackMutations({}, rolls({ 0.0 }))).toEqual({})
	end)
	it("generate: unmutated slimes and traits are unchanged by stacking, mutated ones may stack", function()
		local stacked = 0
		for seed = 1, 400 do
			local s = Genome.generate(Rng.new(seed), { id = "x", mutationChance = 1 })
			local list = s.mutations :: { string }
			expect(#list >= 1 and #list <= Config.MAX_MUTATIONS).toBe(true)
			expect(s.mutation).toBe(Genome.primaryMutation(list))
			if #list > 1 then
				stacked += 1
			end
			local plain = Genome.generate(Rng.new(seed), { id = "x", mutationChance = 0 })
			expect(#(plain.mutations :: { string })).toBe(0)
			expect(plain.mutation).toBe("None")
		end
		expect(stacked > 0).toBe(true)
	end)
end)

describe("Merge and Appraise stacking", function()
	it("a child keeps the parents' other mutations, capped", function()
		local a = Fixtures.slime("a", 2)
		local b = Fixtures.slime("b", 2)
		Genome.setMutations(a, { "Gold", "Crystal" }) -- the primary is Crystal (7), Gold rides along
		Genome.setMutations(b, { "Rainbow", "Eclipse" })
		local child = Merge.merge(a, b, rolls({ 0.99, 0.99, 0.99, 0.99, 0.99, 0.99 }), "c")
		local list = child.mutations :: { string }
		expect(#list <= Config.MAX_MUTATIONS).toBe(true)
		expect(child.mutation).toBe(Genome.primaryMutation(list))
		expect(table.find(list, "Gold") ~= nil).toBe(true)
	end)
	it("single-mutation merges still behave like before", function()
		local a = Fixtures.slime("a", 2, { mutation = "Glow" })
		local b = Fixtures.slime("b", 2, { mutation = "Glow" })
		local child = Merge.merge(a, b, rolls({ 0.99 }), "c")
		expect(child.mutation).toBe("Lava")
		expect(child.mutations).toEqual({ "Lava" })
	end)
	it("an Appraise mutation reroll replaces the whole list and reports before / after", function()
		local data = Fixtures.data({ Fixtures.slime("a", 1, { mutation = "Gold" }) }, 1e9)
		Genome.setMutations(data.slimes[1], { "Gold", "Glow" })
		local ok, result = Appraise.reroll(data, "a", "mutation", rolls({ 0.99 }))
		expect(ok).toBe(true)
		local ap = result :: any
		expect(ap.beforeMutations).toEqual({ "Gold", "Glow" })
		expect(ap.afterMutations).toEqual({})
		expect(data.slimes[1].mutation).toBe("None")
	end)
end)
