--!strict
-- Draft named slime roster (SlimeRoster.luau): counts, unique ids, save safety.
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Genome = require("../src/shared/Genome")
local SlimeRoster = require("../src/shared/SlimeRoster")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("SlimeRoster", function()
	it("has 4/3/3/2/2/2 Classic slimes per tier and Midas at Secret (7)", function()
		local expected = { 4, 3, 3, 2, 2, 2, 1 }
		expect(#expected).toBe(Config.MAX_TIER)
		expect(Config.SECRET_TIER).toBe(Config.MAX_TIER)
		for tier, count in expected do
			expect(#SlimeRoster.forTier(tier)).toBe(count)
		end
		expect(SlimeRoster.SECRET_TIER).toBe(Config.MAX_TIER)
	end)

	it("has 40 spawning species: 17 Classic, Orchard 7, Frost 8, Starlight 8, and five Secrets", function()
		local byFamily: { [string]: number } = {}
		local secret = {}
		local spawning = SlimeRoster.ofKind("spawn")
		for _, entry in spawning do
			local family = entry.family or "classic"
			byFamily[family] = (byFamily[family] or 0) + 1
			if entry.tier == SlimeRoster.SECRET_TIER then
				table.insert(secret, entry.id)
			end
		end
		expect(#spawning).toBe(40)
		expect(byFamily).toEqual({ classic = 17, orchard = 7, frost = 8, starlight = 8 })
		table.sort(secret)
		expect(secret).toEqual({ "abyss", "boo", "eclipse", "gaia", "midas" })
	end)

	it("adds 15 hybrids, 6 bosses and 7 event Secrets that never roll as a spawn", function()
		expect(#SlimeRoster.ofKind("hybrid")).toBe(15)
		expect(#SlimeRoster.ofKind("boss")).toBe(6)
		expect(#SlimeRoster.ofKind("event")).toBe(7)
		expect(#SlimeRoster.ROSTER).toBe(68)
		for _, entry in SlimeRoster.ROSTER do
			expect(entry.family == nil or entry.kind == "spawn").toBe(true)
			if entry.kind ~= "spawn" then
				for _, other in SlimeRoster.forTier(entry.tier) do
					expect(other.id ~= entry.id).toBe(true)
				end
			end
		end
		for _, entry in SlimeRoster.ofKind("event") do
			expect(entry.tier).toBe(SlimeRoster.SECRET_TIER)
		end
	end)

	it("uses unique lower-case ids with a name and look note", function()
		local seen = {}
		for _, entry in SlimeRoster.ROSTER do
			expect(seen[entry.id]).toBe(nil)
			seen[entry.id] = true
			expect(string.match(entry.id, "^[a-z][a-z0-9_]*$") ~= nil).toBe(true)
			expect(#entry.name > 0 and #entry.look > 0).toBe(true)
			expect(SlimeRoster.get(entry.id)).toBe(entry)
		end
	end)
end)

describe("SlimeRoster species income", function()
	it("gives every species a bonus between x0.9 and x1.4, hybrids x1.2 and event Secrets x1.4", function()
		for _, entry in SlimeRoster.ROSTER do
			expect(entry.income >= 0.9 and entry.income <= 1.4).toBe(true)
			if entry.kind == "hybrid" then
				expect(entry.income).toBe(1.2)
			elseif entry.kind == "event" then
				expect(entry.income).toBe(1.4)
			end
		end
		expect(SlimeRoster.incomeBonus("not_a_species")).toBe(1)
		expect(SlimeRoster.incomeBonus(nil)).toBe(1)
	end)
	it("lets later families earn more than the Classic species of the same rarity", function()
		local order = { [""] = 0, orchard = 1, frost = 2, starlight = 3 }
		for tier = 1, SlimeRoster.SECRET_TIER do
			local best: { [string]: number } = {}
			for _, entry in SlimeRoster.ofKind("spawn") do
				if entry.tier == tier then
					local f = entry.family or ""
					best[f] = math.max(best[f] or 0, entry.income)
				end
			end
			for f, v in best do
				if f ~= "" and best[""] then
					expect(`{tier} {f}: {v >= best[""]}`).toBe(`{tier} {f}: true`)
					expect(order[f] ~= nil).toBe(true)
				end
			end
		end
	end)
	it("multiplies a slime's income and makes better earners rarer within their rarity", function()
		local plain = Fixtures.slime("a", 4, { species = "blaze", size = 1 })
		local drako = Fixtures.slime("b", 4, { species = "drako", size = 1 })
		expect(Genome.baseIncome(drako) / Genome.baseIncome(plain)).toBe(SlimeRoster.incomeBonus("drako"))
		local blaze, dragon = SlimeRoster.get("blaze") :: any, SlimeRoster.get("drako") :: any
		expect(Genome.speciesWeight(dragon) < Genome.speciesWeight(blaze)).toBe(true)
		-- the weighted pick lands on drako about as often as its weight says
		local pool = Genome.speciesPool(4, { "frost", "starlight" })
		local total, hits, n = 0, 0, 2000
		for _, entry in pool do
			total += Genome.speciesWeight(entry)
		end
		for i = 1, n do
			local entry = Genome.pickWeighted(pool, (i - 0.5) / n) :: any
			hits += if entry.id == "drako" then 1 else 0
		end
		expect(math.abs(hits / n - Genome.speciesWeight(dragon) / total) < 0.01).toBe(true)
	end)
end)
