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

	it(
		"has 32 spawning species: 15 Classic, Orchard 4, Frost 5, Starlight 8, and Secret = Midas, Eclipse, Boo",
		function()
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
			expect(#spawning).toBe(32)
			expect(byFamily).toEqual({ classic = 15, orchard = 4, frost = 5, starlight = 8 })
			table.sort(secret)
			expect(secret).toEqual({ "boo", "eclipse", "midas" })
		end
	)

	it("adds 15 hybrids, 3 bosses and 7 event Secrets that never roll as a spawn", function()
		expect(#SlimeRoster.ofKind("hybrid")).toBe(15)
		expect(#SlimeRoster.ofKind("boss")).toBe(3)
		expect(#SlimeRoster.ofKind("event")).toBe(7)
		expect(#SlimeRoster.ROSTER).toBe(57)
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
