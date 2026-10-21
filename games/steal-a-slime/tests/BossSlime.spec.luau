--!strict
-- The boss slime the boss event puts in the plaza (src/shared/BossSlime.luau, contract/boss-event.md).
local BossSlime = require("../src/shared/BossSlime")
local Config = require("../src/shared/Config")
local Genome = require("../src/shared/Genome")
local Rng = require("../src/shared/Rng")
local SlimeLooks = require("../src/shared/SlimeLooks")
local SlimeRoster = require("../src/shared/SlimeRoster")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("BossSlime.build", function()
	it("makes every boss species at MAX_SIZE with its name, tier and colour", function()
		for seed = 1, 30 do
			for _, entry in SlimeRoster.ofKind("boss") do
				local slime = BossSlime.build(Rng.new(seed), `b{seed}`, entry.id) :: Genome.Slime
				expect(slime.species).toBe(entry.id)
				expect(slime.name).toBe(entry.name)
				expect(slime.size).toBe(Config.MAX_SIZE)
				expect(slime.tier).toBe(entry.tier)
				local look = SlimeLooks.get(entry.id)
				if look then
					expect(slime.color[1]).toBe(look.color[1])
				end
			end
		end
	end)
	it("refuses species that are not bosses", function()
		expect(BossSlime.build(Rng.new(1), "x", "gummy")).toBeNil()
		expect(BossSlime.build(Rng.new(1), "x", "nope")).toBeNil()
	end)
end)
