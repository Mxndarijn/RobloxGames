--!strict
-- Fountain tiers + slime families per rank (FEATURES.FountainTiers, CONTRACT.md §19): the tier ladder, the
-- family pool and the drop rule (contract/slime-odds.md), species / save safety, the catch gate, the server tier step and the tier looks.
-- The flag is off by default, so the flag-on paths are driven through the `enabled` arguments.
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Fountain = require("../src/shared/Fountain")
local FountainTiers = require("../src/shared/FountainTiers")
local Genome = require("../src/shared/Genome")
local Perks = require("../src/shared/Perks")
local Rng = require("../src/shared/Rng")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local SlimeLooks = require("../src/shared/SlimeLooks")
local SlimeRoster = require("../src/shared/SlimeRoster")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

describe("FountainTiers: the ladder", function()
	it("opens one family per rank that carries one, at the Config.REBIRTH_TIERS thresholds", function()
		local ranks = {}
		for _, rank in Config.REBIRTH_TIERS do
			if rank.family then
				table.insert(ranks, rank)
			end
		end
		expect(#ranks).toBe(#FountainTiers.FAMILIES)
		expect(#ranks + 1).toBe(FountainTiers.MAX_TIER)
		for i, rank in ranks do
			local family = FountainTiers.FAMILIES[i]
			expect(rank.family).toBe(family.id)
			expect(family.tier).toBe(i + 1)
		end
	end)
	it("tierFor steps at 3 / 6 / 10 rebirths and never leaves 1..MAX_TIER", function()
		expect(FountainTiers.tierFor(0)).toBe(1)
		expect(FountainTiers.tierFor(2)).toBe(1)
		expect(FountainTiers.tierFor(3)).toBe(2)
		expect(FountainTiers.tierFor(5)).toBe(2)
		expect(FountainTiers.tierFor(6)).toBe(3)
		expect(FountainTiers.tierFor(9)).toBe(3)
		expect(FountainTiers.tierFor(10)).toBe(4)
		expect(FountainTiers.tierFor(99)).toBe(FountainTiers.MAX_TIER)
	end)
	it("has a look per tier: tier 1 keeps the built glow, each tier after glows brighter", function()
		expect(#FountainTiers.LOOKS).toBe(FountainTiers.MAX_TIER)
		expect(FountainTiers.look(1).glowBrightness).toBe(1)
		for tier = 2, FountainTiers.MAX_TIER do
			expect(FountainTiers.look(tier).glowBrightness > FountainTiers.look(tier - 1).glowBrightness).toBe(true)
		end
		expect(FountainTiers.look(0)).toBe(FountainTiers.look(1))
		expect(FountainTiers.look(99)).toBe(FountainTiers.look(FountainTiers.MAX_TIER))
		for tier, look in FountainTiers.LOOKS do
			expect(look.name ~= "").toBe(true)
			expect(#look.glow).toBe(3)
			expect(tier >= 1).toBe(true)
		end
	end)
	it("every family is in the drop pool, in order", function()
		expect(FountainTiers.allFamilies()).toEqual({ "orchard", "frost", "starlight" })
	end)
	it("rank cards never mention a family: no slime needs a rank", function()
		local wrangler = Perks.tier(3)
		expect(wrangler.family).toBe("orchard")
		expect(string.find(Perks.tierText(wrangler), "Garden", 1, true)).toBeNil()
	end)
	it("the fountain upgrade toast names the fountain only", function()
		expect(FountainTiers.upgradeText(1)).toBeNil()
		expect(FountainTiers.upgradeText(2)).toBe("The fountain grew into the Garden Fountain!")
	end)
	it("shows the families as Meadow, Garden, Frost & Sea and Starlight", function()
		expect(FountainTiers.CLASSIC_NAME).toBe("Meadow")
		local names = {}
		for _, family in FountainTiers.FAMILIES do
			table.insert(names, family.name)
		end
		expect(names).toEqual({ "Garden", "Frost & Sea", "Starlight" })
		expect(FountainTiers.look(1).name).toBe("Meadow Fountain")
		expect(FountainTiers.look(3).name).toBe("Frost & Sea Fountain")
	end)
end)

describe("FountainTiers: species", function()
	it("every family holds its types per tier, each with a look and its own species kit", function()
		local expected = {
			orchard = { 2, 2, 0, 0, 0, 0, 0 },
			frost = { 0, 0, 2, 2, 1, 0, 0 },
			starlight = { 0, 0, 0, 2, 1, 3, 2 },
		}
		for _, family in FountainTiers.FAMILIES do
			local counts = expected[family.id]
			assert(counts, family.id)
			for tier = 1, Config.MAX_TIER do
				local list = SlimeRoster.forTier(tier, family.id)
				expect(#list).toBe(counts[tier])
				for _, entry in list do
					local look = SlimeLooks.get(entry.id)
					expect(look ~= nil).toBe(true)
					expect((look :: any).kit).toBe(`slime_{entry.id}`)
				end
			end
		end
	end)
	it(
		"Classic rolls never see a family type, and the Classic roster is 15 types with Midas the only Secret",
		function()
			local n = 0
			for _, entry in SlimeRoster.ofKind("spawn") do
				if entry.family == nil then
					n += 1
				else
					expect(FountainTiers.family(entry.family) ~= nil).toBe(true)
				end
			end
			expect(n).toBe(15)
			local secret = SlimeRoster.forTier(SlimeRoster.SECRET_TIER)
			expect(#secret).toBe(1)
			expect(secret[1].id).toBe("midas")
			for tier = 1, Config.MAX_TIER do
				for roll = 0, 9 do
					local entry = Genome.rollSpecies(tier, roll / 10)
					expect((entry :: any).family).toBeNil()
				end
			end
		end
	)
	it("an open family's roll can pick every species of the tier: Classic and the family's", function()
		for _, family in FountainTiers.FAMILIES do
			for tier = 1, Config.MAX_TIER do
				local pool = Genome.speciesPool(tier, { family.id })
				local want = #SlimeRoster.forTier(tier) + #SlimeRoster.forTier(tier, family.id)
				expect(#pool).toBe(want)
				local seen = {}
				for k = 0, #pool - 1 do
					local entry = Genome.rollSpecies(tier, (k + 0.5) / #pool, { family.id }) :: any
					expect(entry.tier).toBe(tier)
					expect(entry.family == nil or entry.family == family.id).toBe(true)
					seen[entry.id] = true
				end
				for _, entry in pool do
					expect(seen[entry.id]).toBe(true)
				end
			end
		end
	end)
	it("family ids don't collide with Classic ids and stay lower-case", function()
		local seen = {}
		for _, entry in SlimeRoster.ROSTER do
			expect(seen[entry.id]).toBeNil()
			seen[entry.id] = true
			expect(entry.id).toBe(string.lower(entry.id))
		end
	end)
end)

describe("FountainTiers: drops", function()
	local function drops(pool: { string }?, n: number): { Genome.Slime }
		local rng = Rng.new(11)
		local out = {}
		for i = 1, n do
			table.insert(out, Fountain.roll(rng, `s{i}`, false, nil, nil, pool).slime)
		end
		return out
	end

	it("without families every drop is Classic", function()
		for _, slime in drops(nil, 600) do
			expect(SlimeRoster.get(slime.species :: string).family).toBeNil()
		end
		for _, slime in drops({}, 200) do
			expect(SlimeRoster.get(slime.species :: string).family).toBeNil()
		end
	end)
	it("families never change the rolled tier: the same seed gives the same tiers", function()
		local a, b = drops(nil, 400), drops(FountainTiers.allFamilies(), 400)
		for i = 1, 400 do
			expect(a[i].tier).toBe(b[i].tier)
		end
	end)
	it("a full pool drops every spawning species of the tiers rolled, family slimes at their uniform share", function()
		local pool = FountainTiers.allFamilies()
		local seen: { [string]: number } = {}
		local family, total = 0, 6000
		for _, slime in drops(pool, total) do
			local id = slime.species :: string
			seen[id] = (seen[id] or 0) + 1
			if SlimeRoster.get(id).family then
				family += 1
			end
		end
		-- Every species of Common to Epic shows up in 6000 drops (Legendary+ are too rare to demand).
		for tier = 1, 4 do
			for _, entry in Genome.speciesPool(tier, pool) do
				expect((seen[entry.id] or 0) > 0).toBe(true)
			end
		end
		-- Expected family share: sum over tiers of P(tier) x family species / all species at that tier.
		local weights, sum = {}, 0
		for i, r in Config.RARITIES do
			weights[i] = r.weight
			sum += r.weight
		end
		local expected = 0
		for tier = 1, Config.MAX_TIER do
			local all = #Genome.speciesPool(tier, pool)
			expected += weights[tier] / sum * (all - #SlimeRoster.forTier(tier)) / all
		end
		expect(math.abs(family / total - expected) < 0.03).toBe(true)
	end)
	it("only the families of the pool drop", function()
		for _, slime in drops({ "orchard" }, 600) do
			local f = SlimeRoster.get(slime.species :: string).family
			expect(f == nil or f == "orchard").toBe(true)
		end
	end)
	it("extra species join only the pool of their own tier", function()
		local event = SlimeRoster.ofKind("event")[1]
		expect(event.tier).toBe(SlimeRoster.SECRET_TIER)
		local secrets = Genome.speciesPool(SlimeRoster.SECRET_TIER, nil, { event })
		expect(secrets[#secrets].id).toBe(event.id)
		expect(#secrets).toBe(#SlimeRoster.forTier(SlimeRoster.SECRET_TIER) + 1)
		expect(#Genome.speciesPool(1, nil, { event })).toBe(#SlimeRoster.forTier(1))
		expect(Genome.rollSpecies(SlimeRoster.SECRET_TIER, 0.999, nil, { event })).toBe(event)
	end)
	it("family drops sell and earn like Classic ones: no multiplier, same tier / size income", function()
		local classic = Fixtures.slime("a", 2, { species = "bumble", size = 1.2 })
		local family = Fixtures.slime("b", 2, { species = "prickles", size = 1.2 })
		expect(Genome.baseIncome(family)).toBe(Genome.baseIncome(classic))
		expect(Spawner.price(family, 0.9)).toBe(Spawner.price(classic, 0.9))
	end)
end)

describe("FountainTiers: server", function()
	it("the world starts at tier 1 and the tier step is a no-op with the feature off", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, nil, 0)
		session.data.rebirths = 12
		expect(world.fountainTier).toBe(1)
		expect(Spawner.stepFountainTier(world)).toBe(false)
		expect(world.fountainTier).toBe(1)
		expect(Spawner.familyPool()).toBeNil()
	end)
	it("the tier follows the best rank on the server, only ever rises, and announces once", function()
		local world = ServerFixtures.world()
		local low = ServerFixtures.join(world, 1, nil, 0)
		local high = ServerFixtures.join(world, 2, nil, 0)
		expect(Spawner.stepFountainTier(world, true)).toBe(false)
		high.data.rebirths = 6
		expect(Spawner.stepFountainTier(world, true)).toBe(true)
		expect(world.fountainTier).toBe(3)
		expect(Spawner.familyPool(true)).toEqual({ "orchard", "frost", "starlight" })
		expect(Spawner.stepFountainTier(world, true)).toBe(false)
		local told = ServerFixtures.notifications(world, nil)
		expect(#told).toBe(1)
		expect(string.find(told[1], "Frost & Sea Fountain", 1, true) ~= nil).toBe(true)
		-- the high rank leaves: the fountain keeps its tier
		world.sessions[2] = nil
		low.data.rebirths = 0
		Spawner.stepFountainTier(world, true)
		expect(world.fountainTier).toBe(3)
	end)
	it("a spawned drop is Classic with the feature off even at tier 4", function()
		local world = ServerFixtures.world()
		world.fountainTier = 4
		for _ = 1, 80 do
			local id = Spawner.spawnOne(world, T0)
			expect(SlimeRoster.get(world.wild[id].slime.species :: string).family).toBeNil()
			world.wild[id] = nil
		end
	end)
	it("a player with no rebirths catches a slime of any family", function()
		for _, species in { "prickles", "ninja", "seraph" } do
			local world = ServerFixtures.world()
			local rookie = ServerFixtures.join(world, 1, nil, 1e9)
			local id = Spawner.spawnOne(world, T0)
			world.wild[id].slime.species = species
			world.wild[id].price = 100
			expect((Carry.grab(world, 1, id, 5, T0 + 1))).toBe(true)
			expect(rookie.data.cash < 1e9).toBe(true)
		end
	end)
end)

describe("FountainTiers: saves", function()
	it("a family species round-trips through the save and sanitize", function()
		local slime = Fixtures.slime("s1", 6, { species = "seraph" })
		local clean = Genome.sanitize(slime) :: Genome.Slime
		expect(clean.species).toBe("seraph")
		local data = Fixtures.data({ slime }, 100)
		local back = SaveData.deserialize(SaveData.serialize(data))
		expect(back.slimes[1].species).toBe("seraph")
	end)
	it("an unknown species (a family this build never heard of) loads as an untyped slime", function()
		local clean = Genome.sanitize(Fixtures.slime("s2", 3, { species = "future_family_slime" })) :: Genome.Slime
		expect(clean.species).toBeNil()
		expect(clean.tier).toBe(3)
	end)
end)
