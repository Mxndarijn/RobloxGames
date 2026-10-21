--!strict
-- Slime odds (contract/slime-odds.md): the Mythic / Secret size floors and wild lifetimes, the catch toast, the
-- server's drop rule over the open families, and the top-tier look presets.
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Fountain = require("../src/shared/Fountain")
local FountainTiers = require("../src/shared/FountainTiers")
local Genome = require("../src/shared/Genome")
local RareSpawn = require("../src/visuals/shared/RareSpawn")
local Rng = require("../src/shared/Rng")
local ServerFixtures = require("./ServerFixtures")
local SlimeRoster = require("../src/shared/SlimeRoster")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")
local TopTierFx = require("../src/visuals/shared/TopTierFx")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local MYTHIC, SECRET = Config.SECRET_TIER - 1, Config.SECRET_TIER

-- Spawns until a wild of `tier` shows up (pity forced to Legendary+ so it is quick); returns its id.
local function spawnTier(world: any, tier: number): string
	for _ = 1, 5000 do
		world.pity.sinceLegendary = Config.PITY_LEGENDARY
		local id = Spawner.spawnOne(world, T0)
		if world.wild[id].slime.tier == tier then
			world.wild[id].price = 0
			return id
		end
		world.wild[id] = nil
	end
	error(`no tier {tier} spawn`)
end

describe("Mythic and Secret size floors", function()
	it("generated Mythics are at least 1.2 and Secrets at least 1.4, never above MAX_SIZE", function()
		for tier, floor in { [MYTHIC] = 1.2, [SECRET] = 1.4 } do
			expect(Genome.sizeFloor(tier)).toBe(floor)
			local rng = Rng.new(3)
			for i = 1, 300 do
				local slime = Genome.generate(rng, { id = `s{i}`, tier = tier })
				expect(slime.size >= floor and slime.size <= Config.MAX_SIZE).toBe(true)
			end
		end
	end)
	it("lower tiers keep the plain size roll", function()
		expect(Genome.sizeFloor(5)).toBe(0)
		local rng, small = Rng.new(3), 0
		for i = 1, 300 do
			if Genome.generate(rng, { id = `s{i}`, tier = 5 }).size < 1.2 then
				small += 1
			end
		end
		expect(small > 0).toBe(true)
	end)
end)

describe("Mythic and Secret wild lifetimes", function()
	it("Mythic lives 1.5x and Secret 2x WILD_LIFETIME, the rest 1x", function()
		for tier = 1, Config.MAX_TIER do
			local mult = if tier == MYTHIC then 1.5 elseif tier == SECRET then 2 else 1
			expect(Fountain.wildLifetime(Fixtures.slime("x", tier))).toBe(Config.WILD_LIFETIME * mult)
		end
	end)
	it("a fountain Mythic / Secret spawns with the long lifetime and the size floor", function()
		local world = ServerFixtures.world()
		for _, tier in { MYTHIC, SECRET } do
			local wild = world.wild[spawnTier(world, tier)]
			expect(wild.expiresAt - wild.spawnedAt).toBe(Fountain.wildLifetime(wild.slime))
			expect(wild.expiresAt - wild.spawnedAt > Config.WILD_LIFETIME).toBe(true)
			expect(wild.slime.size >= Genome.sizeFloor(tier)).toBe(true)
			expect(wild.rare).toBe(tier)
		end
	end)
	it("a dropped Secret gets its long lifetime again", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1)
		local id = spawnTier(world, SECRET)
		expect((Carry.grab(world, 1, id, 1, T0))).toBe(true)
		expect(Carry.release(world, 1, T0 + 30, "here", "drop")).toBe(true)
		expect(world.wild[id].expiresAt).toBe(T0 + 30 + Config.WILD_LIFETIME * 2)
	end)
end)

describe("Mythic and Secret announcements", function()
	it("the spawn toast names the species and goes to every player", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1)
		ServerFixtures.clearEvents(world)
		local wild = world.wild[spawnTier(world, MYTHIC)]
		local told = ServerFixtures.notifications(world, nil)
		local text = Spawner.rareText(wild.slime)
		expect(table.find(told, text) ~= nil).toBe(true)
		expect(string.find(text, wild.slime.name, 1, true) ~= nil).toBe(true)
		expect(string.find(text, "MYTHIC", 1, true) ~= nil).toBe(true)
	end)
	it("bringing a Mythic home tells everyone '<player> caught <Species>!'", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1)
		local id = spawnTier(world, MYTHIC)
		local name = world.wild[id].slime.name
		expect((Carry.grab(world, 1, id, 1, T0))).toBe(true)
		ServerFixtures.clearEvents(world)
		expect((Carry.deposit(world, 1))).toBe(true)
		expect(table.find(ServerFixtures.notifications(world, nil), `P1 caught {name}!`) ~= nil).toBe(true)
	end)
	it("catchText is only for Mythic and Secret", function()
		expect(Carry.catchText("P1", Fixtures.slime("a", 5))).toBeNil()
		local secret = Fixtures.slime("b", SECRET, { species = "midas" })
		expect(Carry.catchText("P1", secret)).toBe(`P1 caught {secret.name}!`)
	end)
end)

describe("Spawner drop rule over the open families", function()
	-- Drops the way spawnOne does with FEATURES.FountainTiers on (the flag is passed, the default stays off).
	local function speciesSeen(n: number): { [string]: boolean }
		local families = Spawner.familyPool(true)
		local rng = Rng.new(19)
		local seen = {}
		for i = 1, n do
			for tier = 1, Config.MAX_TIER do
				local slime = Genome.generate(rng, { id = `s{i}`, tier = tier, families = families })
				seen[slime.species :: string] = true
			end
		end
		return seen
	end

	it("every species of every family can drop, at every tier", function()
		local seen = speciesSeen(200)
		for _, entry in SlimeRoster.ofKind("spawn") do
			expect(seen[entry.id]).toBe(true)
		end
	end)
	it("with the feature off the server drops Classic species only", function()
		local world = ServerFixtures.world()
		world.fountainTier = FountainTiers.MAX_TIER
		expect(Spawner.familyPool(false)).toBeNil()
		for _ = 1, 300 do
			local id = Spawner.spawnOne(world, T0)
			local family = SlimeRoster.get(world.wild[id].slime.species :: string).family
			world.wild[id] = nil
			if not Config.FEATURES.FountainTiers then
				expect(family).toBeNil()
			end
		end
	end)
end)

describe("Mythic and Secret looks", function()
	it("the eruption rises and fades to nothing within ERUPTION_SECONDS", function()
		expect(TopTierFx.ERUPTION_SECONDS).toBe(2)
		local shake0, tint0 = TopTierFx.eruption(0)
		expect(shake0).toBe(0)
		expect(tint0).toBe(0)
		local shake, tint = TopTierFx.eruption(0.2)
		expect(shake > 0 and shake <= TopTierFx.SHAKE_STUDS).toBe(true)
		expect(tint > 0 and tint <= 1).toBe(true)
		local endShake, endTint = TopTierFx.eruption(TopTierFx.ERUPTION_SECONDS)
		expect(endShake).toBe(0)
		expect(endTint).toBe(0)
	end)
	it("only a fresh Secret drop erupts", function()
		expect(TopTierFx.erupts(SECRET, 100, 101)).toBe(true)
		expect(TopTierFx.erupts(MYTHIC, 100, 101)).toBe(false)
		expect(TopTierFx.erupts(SECRET, 100, 100 + TopTierFx.FRESH_SECONDS + 1)).toBe(false)
		expect(TopTierFx.erupts(SECRET, nil, 100)).toBe(false)
	end)
	it("pedestal glow under Mythic and Secret only; the Secret one has a small column", function()
		for tier = 1, 5 do
			expect(TopTierFx.pedestal(tier)).toBeNil()
		end
		local mythic, secret = TopTierFx.pedestal(MYTHIC), TopTierFx.pedestal(SECRET)
		expect(mythic ~= nil and mythic.column == nil).toBe(true)
		expect(secret ~= nil and (secret.column or 0) > 0 and (secret.column or 0) <= 10).toBe(true)
	end)
	it("shows no disc under a Mythic or Secret pad slime: the pedestal only carries its light and sparkles", function()
		expect(TopTierFx.PEDESTAL_TRANSPARENCY).toBe(1)
		for _, tier in { MYTHIC, SECRET } do
			local spec = TopTierFx.pedestal(tier)
			expect(spec ~= nil and spec.brightness > 0 and spec.range > 0).toBe(true)
		end
	end)
	it("the Secret marker orbits motes, and the fountain beam stays a short see-through marker", function()
		expect(RareSpawn.TIERS[SECRET].orbit).toBe(3)
		expect(RareSpawn.TIERS[MYTHIC].orbit).toBeNil()
		expect(TopTierFx.FOUNTAIN_BEAM.height <= 24).toBe(true)
		expect(TopTierFx.FOUNTAIN_BEAM.width <= 1).toBe(true)
		expect(TopTierFx.FOUNTAIN_BEAM.transparency >= 0.6).toBe(true)
		local ax, _, az = RareSpawn.orbitOffset(0, 1, 3, 3)
		local bx, _, bz = RareSpawn.orbitOffset(1, 1, 3, 3)
		expect(ax ~= bx or az ~= bz).toBe(true)
		expect(math.abs(math.sqrt(ax * ax + az * az) - 3 * RareSpawn.ORBIT_RADIUS) < 1e-6).toBe(true)
	end)
end)
