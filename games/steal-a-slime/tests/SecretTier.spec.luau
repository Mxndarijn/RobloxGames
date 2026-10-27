--!strict
-- Secret slimes: ~1 in 2000 wild spawns; Secret and rarer drops are announced to every player with the Secret sound.
local Config = require("../src/shared/Config")
local Genome = require("../src/shared/Genome")
local RareAnnounce = require("../src/ui/RareAnnounce")
local Rng = require("../src/shared/Rng")
local ServerFixtures = require("./ServerFixtures")
local SlimeRoster = require("../src/shared/SlimeRoster")
local Sounds = require("../src/ui/Sounds")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

describe("Secret spawn rate", function()
	it("has a weight share of ~0.05 %", function()
		local total = 0
		for _, r in Config.RARITIES do
			total += r.weight
		end
		local share = Config.RARITIES[Config.SECRET_TIER].weight / total
		expect(math.abs(share - 0.0005) < 0.00005).toBe(true)
	end)
	it("rolls Secret about once per 2000 seeded tier rolls", function()
		local rng = Rng.new(28)
		local N, secrets = 400000, 0
		for _ = 1, N do
			if Genome.rollTier(rng:float(), 1, nil) == Config.SECRET_TIER then
				secrets += 1
			end
		end
		local rate = secrets / N
		expect(rate > 0.0003 and rate < 0.0007).toBe(true)
	end)
	it("hands Secret rolls a Classic Secret roster species", function()
		for seed = 1, 50 do
			local s = Genome.generate(Rng.new(seed), { id = "s", tier = Config.SECRET_TIER })
			expect(s.tier).toBe(7)
			local entry = SlimeRoster.get(s.species :: string) :: SlimeRoster.Entry
			expect(entry.tier).toBe(Config.SECRET_TIER)
			expect(entry.family).toBeNil()
		end
	end)
end)

describe("Secret announcement", function()
	it("notifies everyone with the Secret sound on a Secret or rarer spawn, and never otherwise", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1, nil, 0)
		ServerFixtures.join(world, 2, nil, 0)
		world.rng = Rng.new(28)
		local tierNames = {}
		for i, r in Config.RARITIES do
			tierNames[i] = r.name
		end
		local secrets, others = 0, 0
		for i = 1, 300000 do
			world.outbox = {}
			local id = Spawner.spawnSlime(world, T0 + i)
			local tier = world.wild[id].slime.tier
			local secretNotes, text = 0, ""
			for _, e in world.outbox do
				if e.type == "Notify" and e.sound == "Secret" then
					secretNotes += 1
					text = e.text
					expect(e.userId).toBeNil() -- nil = every player
				end
			end
			if tier >= Config.SECRET_TIER then
				secrets += 1
				expect(secretNotes).toBe(1)
				expect(RareAnnounce.classify(text, "Secret")).toBe("drop")
				local banner = RareAnnounce.dropBanner({ tier = tier, at = T0, text = text }, T0 + 1, tierNames)
				local mark = `🌌 {string.upper(tierNames[tier])} 🌌`
				expect(banner ~= nil and string.find((banner :: any).text, mark, 1, true) ~= nil).toBe(true)
			else
				others += 1
				expect(secretNotes).toBe(0)
			end
			world.wild[id] = nil
		end
		expect(secrets > 0).toBe(true)
		expect(others > 0).toBe(true)
		expect(Sounds.resolve("Secret") ~= nil).toBe(true)
		expect(Sounds.resolve("Secret") ~= Sounds.resolve("Rebirth")).toBe(true)
	end)
end)
