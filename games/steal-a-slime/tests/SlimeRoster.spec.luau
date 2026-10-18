--!strict
-- Draft named slime roster (SlimeRoster.luau): counts, unique ids, save safety.
local Config = require("../src/shared/Config")
local SlimeRoster = require("../src/shared/SlimeRoster")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("SlimeRoster", function()
	it("has 4/3/3/2/1/1 Classic slimes per tier and Midas at Secret (7)", function()
		local expected = { 4, 3, 3, 2, 1, 1, 1 }
		expect(#expected).toBe(Config.MAX_TIER)
		expect(Config.SECRET_TIER).toBe(Config.MAX_TIER)
		for tier, count in expected do
			expect(#SlimeRoster.forTier(tier)).toBe(count)
		end
		expect(SlimeRoster.SECRET_TIER).toBe(Config.MAX_TIER)
	end)

	it("has 32 species: 15 Classic, Orchard 4, Frost 5, Starlight 8, and Secret = Midas, Eclipse, Boo", function()
		local byFamily: { [string]: number } = {}
		local secret = {}
		for _, entry in SlimeRoster.ROSTER do
			local family = entry.family or "classic"
			byFamily[family] = (byFamily[family] or 0) + 1
			if entry.tier == SlimeRoster.SECRET_TIER then
				table.insert(secret, entry.id)
			end
		end
		expect(#SlimeRoster.ROSTER).toBe(32)
		expect(byFamily).toEqual({ classic = 15, orchard = 4, frost = 5, starlight = 8 })
		table.sort(secret)
		expect(secret).toEqual({ "boo", "eclipse", "midas" })
	end)

	it("uses unique lower-case ids with a name and look note", function()
		local seen = {}
		for _, entry in SlimeRoster.ROSTER do
			expect(seen[entry.id]).toBe(nil)
			seen[entry.id] = true
			expect(string.match(entry.id, "^[a-z][a-z0-9_]*$") ~= nil).toBe(true)
			expect(#entry.name > 0 and #entry.look > 0).toBe(true)
			expect(SlimeRoster.get(entry.id)).toBe(entry)
			local lower = string.lower(entry.name .. " " .. entry.look .. " " .. entry.id)
			expect(string.find(lower, "volcan", 1, true)).toBe(nil)
			expect(string.find(lower, "lava", 1, true)).toBe(nil)
		end
	end)

	it("keeps existing mutation save ids and adds new ones on the curve", function()
		local names = {}
		for _, m in Config.MUTATIONS do
			names[m.name] = m
		end
		for _, keep in { "Glow", "Lava", "Galaxy", "Gold" } do
			expect(names[keep] ~= nil).toBe(true)
			expect(SlimeRoster.MUTATION_DISPLAY[keep] ~= nil).toBe(true)
		end
		expect(SlimeRoster.MUTATION_DISPLAY.Lava).toBe("Syrup")
		expect(names.Lava.displayName).toBe("Syrup")
		for _, m in SlimeRoster.NEW_MUTATIONS do
			-- v28: wired into Config with the drafted values.
			expect(names[m.name] ~= nil).toBe(true)
			expect(names[m.name].multiplier).toBe(m.multiplier)
			expect(names[m.name].weight).toBe(m.weight)
			expect(SlimeRoster.MUTATION_DISPLAY[m.name] ~= nil).toBe(true)
		end
		-- Config order is the merge rank: multiplier up, weight down.
		for i = 2, #Config.MUTATIONS do
			local a, b = Config.MUTATIONS[i - 1], Config.MUTATIONS[i]
			expect(b.multiplier > a.multiplier).toBe(true)
			expect(b.weight < a.weight).toBe(true)
		end
	end)
end)
