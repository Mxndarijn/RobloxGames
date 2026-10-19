--!strict
local Actions = require("../src/server/Actions")
local Appraise = require("../src/shared/Appraise")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local Fixtures = require("./Fixtures")
local Genome = require("../src/shared/Genome")
local Remotes = require("../src/shared/Remotes")
local Rng = require("../src/shared/Rng")
local ServerFixtures = require("./ServerFixtures")
local Snapshot = require("../src/server/Snapshot")
local TestRunner = require("./TestRunner")
local Validate = require("../src/shared/Validate")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

local function ctx(seed: number): Actions.Context
	return {
		distanceBetween = function()
			return 2
		end,
		positionOf = function()
			return "pos"
		end,
		rng = Rng.new(seed),
	}
end

local function call(world: any, userId: number, seed: number, now: number, ...: any)
	return Actions.handle(world, userId, "Appraise", table.pack(...), now, ctx(seed))
end

local function slime()
	return Fixtures.slime("a", 4, { size = 1.2, pattern = "Spots", eyes = "Happy" })
end

describe("Appraise", function()
	it("is a rate-limited, declared action", function()
		expect(Remotes.ACTIONS.Appraise ~= nil).toBeTruthy()
		expect(Validate.ACTIONS.Appraise ~= nil).toBeTruthy()
	end)
	it("costs 30% of the slime's current value", function()
		local s = slime()
		local value = Economy.sellPrice(s, 2)
		expect(Config.APPRAISE_COST_FRACTION).toBe(0.3)
		expect(Appraise.cost(s, 2)).toBe(math.floor(value * 0.3))
		-- a cheaper slime costs less: tracks the current value
		local bigger = Fixtures.slime("b", 5, { size = 1.2 })
		expect(Appraise.cost(bigger, 2) > Appraise.cost(s, 2)).toBeTruthy()
	end)
	it("charges exactly the cost through the Request action", function()
		local world = ServerFixtures.world()
		local s = slime()
		local price = Appraise.cost(s, 0)
		local session = ServerFixtures.join(world, 1, { s }, price + 7)
		local res = call(world, 1, 5, T0 + 100, "a", "size")
		expect(res.ok).toBe(true)
		expect(session.data.cash).toBe(7)
		expect(res.appraisal.cost).toBe(price)
		expect(res.appraisal.kind).toBe("size")
	end)
	it("answers with the income and price before and after, as the next State shows them", function()
		local world = ServerFixtures.world()
		local s = slime()
		local session = ServerFixtures.join(world, 1, { s }, 100_000)
		local before = Snapshot.build(world, session, T0 + 99).slimes[1]
		local res = call(world, 1, 5, T0 + 100, "a", "size")
		expect(res.ok).toBe(true)
		local a = res.appraisal
		expect(a.beforeSize).toBe(1.2)
		expect(a.incomeBefore).toBe(before.income)
		expect(a.cost).toBe(before.appraiseCost)
		local after = Snapshot.build(world, session, T0 + 101).slimes[1]
		expect(a.afterSize).toBe(after.slime.size)
		expect(a.incomeAfter).toBe(after.income)
		expect(a.costAfter).toBe(after.appraiseCost)
	end)
	it("rolls sizes on the Config.APPRAISE_SIZE_DECIMALS grid, ends included", function()
		local scale = 10 ^ Config.APPRAISE_SIZE_DECIMALS
		expect(Appraise.rollSize(0)).toBe(Config.MIN_SIZE)
		expect(Appraise.rollSize(0.9999999)).toBe(Config.MAX_SIZE)
		for i = 0, 99 do
			local size = Appraise.rollSize(i / 100 + 0.003)
			expect(math.abs(size * scale - math.floor(size * scale + 0.5)) < 1e-6).toBe(true)
		end
	end)
	it("rejects insufficient cash and changes nothing", function()
		local world = ServerFixtures.world()
		local s = slime()
		local price = Appraise.cost(s, 0)
		local session = ServerFixtures.join(world, 1, { s }, price - 1)
		local res = call(world, 1, 5, T0 + 100, "a", "size")
		expect(res.ok).toBe(false)
		expect(res.message).toBe("not enough cash")
		expect(session.data.cash).toBe(price - 1)
		expect(session.data.slimes[1].size).toBe(1.2)
	end)
	it("rejects a non-owner and a bad kind without spending", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1, { slime() }, 10_000)
		local other = ServerFixtures.join(world, 2, { Fixtures.slime("b", 4) }, 10_000)
		local res = call(world, 2, 5, T0 + 100, "a", "size")
		expect(res.ok).toBe(false)
		expect(res.message).toBe("not your slime")
		expect(other.data.cash).toBe(10_000)
		expect(call(world, 1, 5, T0 + 100, "a", "tier").message).toBe("bad argument")
		expect(call(world, 1, 5, T0 + 200, "a", "mutation").message).toBe("bad argument")
		expect(call(world, 1, 5, T0 + 300, "nope", "size").message).toBe("not your slime")
	end)
	it("is rate-limited", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1, { slime() }, 100_000)
		expect(call(world, 1, 5, T0 + 100, "a", "size").ok).toBe(true)
		expect(call(world, 1, 6, T0 + 100.1, "a", "size").message).toBe("too fast")
		expect(call(world, 1, 6, T0 + 101, "a", "size").ok).toBe(true)
	end)
	it("a size reroll changes only the size", function()
		for seed = 1, 20 do
			local data = Fixtures.data({ slime() }, 1_000_000)
			local before = Genome.copy(data.slimes[1])
			expect((Appraise.reroll(data, "a", "size", Rng.new(seed)))).toBe(true)
			local after = data.slimes[1]
			local expected = Genome.copy(before)
			expected.size = after.size
			expect(Genome.copy(after)).toEqual(expected)
			expect(after.size >= Config.MIN_SIZE and after.size <= Config.MAX_SIZE).toBeTruthy()
		end
	end)
	it("is deterministic with a seeded Rng", function()
		local function run(kind: string, seed: number)
			local data = Fixtures.data({ slime() }, 1_000_000)
			local _, appraisal = Appraise.reroll(data, "a", kind, Rng.new(seed))
			return appraisal
		end
		for seed = 1, 10 do
			expect(run("size", seed)).toEqual(run("size", seed))
		end
	end)
	it("keeps the save format: same fields before and after", function()
		local data = Fixtures.data({ slime() }, 1_000_000)
		local keys = {}
		for k in data.slimes[1] do
			table.insert(keys, k)
		end
		table.sort(keys)
		Appraise.reroll(data, "a", "size", Rng.new(3))
		local after = {}
		for k in data.slimes[1] do
			table.insert(after, k)
		end
		table.sort(after)
		expect(after).toEqual(keys)
	end)
	it("Snapshot offers the price per slime, nil with the feature off", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, { slime() }, 5)
		local view = Snapshot.build(world, session, T0).slimes[1]
		expect(view.appraiseCost).toBe(Appraise.cost(session.data.slimes[1], session.data.rebirths))
	end)
end)
