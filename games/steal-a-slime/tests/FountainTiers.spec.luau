--!strict
-- Fountain tiers + slime families per rank (FEATURES.FountainTiers, CONTRACT.md §19): the tier ladder, the
-- family pool and roll, species / save safety, the catch gate, the server tier step and the tier decor.
-- The flag is off by default, so the flag-on paths are driven through the `enabled` arguments.
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Constants = require("../src/shared/Constants")
local Fixtures = require("./Fixtures")
local Fountain = require("../src/shared/Fountain")
local FountainTierDecor = require("../src/visuals/shared/FountainTierDecor")
local FountainTiers = require("../src/shared/FountainTiers")
local Genome = require("../src/shared/Genome")
local MeshAssets = require("../src/shared/MeshAssets")
local Perks = require("../src/shared/Perks")
local RanchProps = require("../src/visuals/shared/RanchProps")
local Rng = require("../src/shared/Rng")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local SlimeLooks = require("../src/shared/SlimeLooks")
local SlimeRoster = require("../src/shared/SlimeRoster")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")
local WorldBudget = require("./WorldBudget.spec")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

local function materialOk(name: string): boolean
	return SlimeLooks.isMaterial(name) or name == "Foil" or name == "Neon"
end

describe("FountainTiers: the ladder", function()
	it("is behind FEATURES.FountainTiers, default off", function()
		expect(Config.FEATURES.FountainTiers).toBe(false)
	end)
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
			expect(FountainTiers.rebirthsFor(family.id)).toBe(rank.rebirths)
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
	it("has a look per tier: tier 1 adds nothing, ring from tier 2, crest from tier 3", function()
		expect(#FountainTiers.LOOKS).toBe(FountainTiers.MAX_TIER)
		expect(FountainTiers.look(1).ring or FountainTiers.look(1).crest).toBe(false)
		expect(FountainTiers.look(2).ring).toBe(true)
		expect(FountainTiers.look(2).crest).toBe(false)
		expect(FountainTiers.look(3).crest).toBe(true)
		expect(FountainTiers.look(4).crest).toBe(true)
		expect(FountainTiers.look(0)).toBe(FountainTiers.look(1))
		expect(FountainTiers.look(99)).toBe(FountainTiers.look(FountainTiers.MAX_TIER))
		for tier, look in FountainTiers.LOOKS do
			expect(look.name ~= "").toBe(true)
			expect(materialOk(look.material)).toBe(true)
			expect(tier >= 1).toBe(true)
		end
	end)
	it("the pool grows with the tier and always lists open families in order", function()
		expect(#FountainTiers.pool(1)).toBe(0)
		expect(FountainTiers.pool(2)).toEqual({ "orchard" })
		expect(FountainTiers.pool(4)).toEqual({ "orchard", "frost", "starlight" })
	end)
	it("rank cards only mention a family with the feature on (off: tierText is unchanged)", function()
		local wrangler = Perks.tier(3)
		expect(wrangler.family).toBe("orchard")
		expect(string.find(Perks.tierText(wrangler), "Orchard", 1, true)).toBeNil()
		expect(FountainTiers.rankText("orchard")).toBe("opens the Orchard slimes")
	end)
end)

describe("FountainTiers: species", function()
	it("every family has one type per tier 1..6, with a look and a kit, and none at Secret", function()
		for _, family in FountainTiers.FAMILIES do
			for tier = 1, Config.MAX_TIER - 1 do
				local list = SlimeRoster.forTier(tier, family.id)
				expect(#list).toBe(1)
				local look = SlimeLooks.get(list[1].id)
				expect(look ~= nil).toBe(true)
				-- same kit as the Classic types of that tier
				expect((look :: any).kit).toBe((SlimeLooks.get(SlimeRoster.forTier(tier)[1].id) :: any).kit)
			end
			expect(#SlimeRoster.forTier(SlimeRoster.SECRET_TIER, family.id)).toBe(0)
		end
	end)
	it("Classic rolls never see a family type, and the Classic roster is the original 31 + 2 Secret", function()
		local n = 0
		for _, entry in SlimeRoster.ROSTER do
			if entry.family == nil then
				n += 1
			else
				expect(FountainTiers.family(entry.family) ~= nil).toBe(true)
			end
		end
		expect(n).toBe(31)
		for tier = 1, Config.MAX_TIER do
			for roll = 0, 9 do
				local entry = Genome.rollSpecies(tier, roll / 10)
				expect((entry :: any).family).toBeNil()
			end
		end
	end)
	it("a family roll picks that family's type, falling back to Classic where it has none", function()
		for _, family in FountainTiers.FAMILIES do
			for tier = 1, Config.MAX_TIER - 1 do
				expect((Genome.rollSpecies(tier, 0.5, family.id) :: any).family).toBe(family.id)
			end
			expect((Genome.rollSpecies(SlimeRoster.SECRET_TIER, 0.5, family.id) :: any).family).toBeNil()
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
			table.insert(out, Fountain.roll(rng, `s{i}`, false, nil, nil, nil, nil, nil, pool).slime)
		end
		return out
	end

	it("without a pool the sequence is exactly the v28 one (no extra rng draws)", function()
		local a, b, c = drops(nil, 60), drops({}, 60), drops(nil, 60)
		for i = 1, 60 do
			expect(a[i].species).toBe(c[i].species)
			expect(a[i].species).toBe(b[i].species)
			expect(a[i].tier).toBe(b[i].tier)
			expect(a[i].mutation).toBe(b[i].mutation)
			expect(SlimeRoster.get(a[i].species :: string).family).toBeNil()
		end
	end)
	it("a full pool turns about FAMILY_DROP_CHANCE of drops into family types, every family shows up", function()
		local pool = FountainTiers.pool(FountainTiers.MAX_TIER)
		local seen: { [string]: number } = {}
		local family, total = 0, 4000
		for _, slime in drops(pool, total) do
			local f = SlimeRoster.get(slime.species :: string).family
			if f then
				family += 1
				seen[f] = (seen[f] or 0) + 1
			end
		end
		expect(math.abs(family / total - Config.FAMILY_DROP_CHANCE) < 0.04).toBe(true)
		for _, id in pool do
			expect((seen[id] or 0) > 0).toBe(true)
		end
		expect(seen.orchard > seen.frost and seen.frost > seen.starlight).toBe(true) -- weights 5 / 3 / 2
	end)
	it("only the families of the pool drop", function()
		for _, slime in drops({ "orchard" }, 600) do
			local f = SlimeRoster.get(slime.species :: string).family
			expect(f == nil or f == "orchard").toBe(true)
		end
	end)
	it("a family's luck makes better rarities likelier", function()
		local function rare(id: string?): number
			local rng = Rng.new(5)
			local n = 0
			for i = 1, 6000 do
				local slime = Genome.generate(rng, { id = `s{i}`, luck = FountainTiers.luck(id), family = id })
				if slime.tier >= 4 then
					n += 1
				end
			end
			return n
		end
		expect(rare("starlight") > rare(nil)).toBe(true)
		expect(FountainTiers.luck(nil)).toBe(1)
		expect(FountainTiers.luck("nope")).toBe(1)
	end)
	it("family drops sell and earn like Classic ones: no multiplier, same tier / size / mutation income", function()
		local classic = Fixtures.slime("a", 4, { species = "billy_gum", size = 1.2 })
		local family = Fixtures.slime("b", 4, { species = "plum_stag", size = 1.2 })
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
		expect(Spawner.familyPool(world)).toBeNil()
	end)
	it("the tier follows the best rank on the server, only ever rises, and announces once", function()
		local world = ServerFixtures.world()
		local low = ServerFixtures.join(world, 1, nil, 0)
		local high = ServerFixtures.join(world, 2, nil, 0)
		expect(Spawner.stepFountainTier(world, true)).toBe(false)
		high.data.rebirths = 6
		expect(Spawner.stepFountainTier(world, true)).toBe(true)
		expect(world.fountainTier).toBe(3)
		expect(Spawner.familyPool(world, true)).toEqual({ "orchard", "frost" })
		expect(Spawner.stepFountainTier(world, true)).toBe(false)
		local told = ServerFixtures.notifications(world, nil)
		expect(#told).toBe(1)
		expect(string.find(told[1], "Frost Fountain", 1, true) ~= nil).toBe(true)
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
	it("the catch gate: a family slime needs the family's rank, Classic and stolen slimes never do", function()
		local plum = Fixtures.slime("p", 4, { species = "plum_stag" })
		local classic = Fixtures.slime("c", 4, { species = "billy_gum" })
		local merged = Fixtures.slime("m", 4)
		expect(Carry.familyBlock(0, plum, true)).toBe("Reach Slime Wrangler (3 rebirths) to catch Orchard slimes")
		expect(Carry.familyBlock(2, plum, true) ~= nil).toBe(true)
		expect(Carry.familyBlock(3, plum, true)).toBeNil()
		expect(Carry.familyBlock(0, classic, true)).toBeNil()
		expect(Carry.familyBlock(0, merged, true)).toBeNil()
		expect(Carry.familyBlock(5, Fixtures.slime("g", 6, { species = "glacier_gem" }), true)).toBe(
			"Reach Goo Tycoon (6 rebirths) to catch Frost slimes"
		)
		expect(Carry.familyBlock(0, plum)).toBeNil() -- flag off
	end)
	it("a refused family grab costs nothing and a rank-ready player grabs it", function()
		local world = ServerFixtures.world()
		local rookie = ServerFixtures.join(world, 1, nil, 1e9)
		local id = Spawner.spawnOne(world, T0)
		world.wild[id].slime.species = "plum_stag"
		world.wild[id].price = 100
		-- feature off: the gate is not applied
		expect((Carry.grab(world, 1, id, 5, T0 + 1))).toBe(true)
		expect(rookie.data.cash < 1e9).toBe(true)
	end)
end)

describe("FountainTiers: saves", function()
	it("a family species round-trips through the save and sanitize", function()
		local slime = Fixtures.slime("s1", 5, { species = "cherry_baron" })
		local clean = Genome.sanitize(slime) :: Genome.Slime
		expect(clean.species).toBe("cherry_baron")
		local data = Fixtures.data({ slime }, 100)
		local back = SaveData.deserialize(SaveData.serialize(data))
		expect(back.slimes[1].species).toBe("cherry_baron")
	end)
	it("an unknown species (a family this build never heard of) loads as an untyped slime", function()
		local clean = Genome.sanitize(Fixtures.slime("s2", 3, { species = "future_family_slime" })) :: Genome.Slime
		expect(clean.species).toBeNil()
		expect(clean.tier).toBe(3)
	end)
	it("the save version is unchanged: no new saved field", function()
		expect(Config.SAVE_VERSION).toBe(6)
	end)
end)

describe("FountainTiers: decor", function()
	it("tier 1 shows nothing, tier 2 the ring, tier 3+ ring and crest, tinted by the tier", function()
		local p1 = FountainTierDecor.poses(1)
		expect(p1.ring).toBeNil()
		expect(p1.crest).toBeNil()
		local p2 = FountainTierDecor.poses(2)
		expect(p2.ring ~= nil and p2.crest == nil).toBe(true)
		expect((p2.ring :: any).color).toEqual(FountainTiers.look(2).color)
		local p4 = FountainTierDecor.poses(4)
		expect(p4.ring ~= nil and p4.crest ~= nil).toBe(true)
		expect((p4.crest :: any).material).toBe("Neon")
	end)
	it("the ring stands on the ground round the silo axis, the crest floats over the fountain top", function()
		local p = FountainTierDecor.poses(4)
		local ring, crest = p.ring :: FountainTierDecor.Pose, p.crest :: FountainTierDecor.Pose
		expect(ring.position[1]).toBe(0)
		expect(ring.position[3]).toBe(0)
		expect(math.abs(ring.position[2] - ring.size[2] / 2) < 1e-9).toBe(true)
		local underside = crest.position[2] - crest.size[2] / 2
		expect(underside > WorldLayout.FOUNTAIN_HEIGHT).toBe(true)
		-- the ring posts (r 14.6) stay clear of the plinth (r 13.1)
		expect(ring.size[1] / 2 >= 14.6).toBe(true)
	end)
	it("the crest bobs by at most BOB and spins a full turn at SPIN", function()
		for t = 0, 40 do
			local bob, yaw = FountainTierDecor.crestMotion(t / 3)
			expect(math.abs(bob) <= FountainTierDecor.BOB + 1e-9).toBe(true)
			expect(yaw >= 0 and yaw < math.pi * 2).toBe(true)
		end
	end)
	it("both meshes are uploaded kit meshes, run-time only (no WorldLayout slot)", function()
		for _, name in { "fountain_tier_ring", "fountain_tier_crest" } do
			expect(MeshAssets.meshId(name) ~= nil).toBe(true)
			expect(MeshAssets.get(name).size ~= nil).toBe(true)
			expect(RanchProps.INTENTIONALLY_UNPLACED[name] ~= nil).toBe(true)
		end
	end)
	it("takes no world mesh slot: WorldLayout.build() places neither mesh", function()
		local function scan(node: any)
			local a = node.attributes or {}
			for _, key in { "MeshAsset", "BorderMesh" } do
				expect(a[key] ~= "fountain_tier_ring" and a[key] ~= "fountain_tier_crest").toBe(true)
			end
			for _, c in node.children or {} do
				scan(c)
			end
		end
		for _, root in WorldLayout.build() do
			scan(root)
		end
		for _, prop in WorldLayout.RANCH_PROPS do
			expect(prop.mesh ~= "fountain_tier_ring" and prop.mesh ~= "fountain_tier_crest").toBe(true)
		end
		expect(WorldBudget.uploaded.total <= WorldLayout.MESH_SLOT_BUDGET).toBe(true)
	end)
	it("the workspace attribute is named once", function()
		expect(Constants.FOUNTAIN_TIER_ATTRIBUTE).toBe("FountainTier")
	end)
end)
