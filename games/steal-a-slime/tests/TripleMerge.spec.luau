--!strict
-- 3-slime merge vat (FEATURES.MergeVat3, CONTRACT.md §21): rules, odds, determinism, anti-dupe, the Merge3
-- action, the panel's switch and the vat decor. The flag is off by default; flag-on paths pass ctx.features.MergeVat3.
local Actions = require("../src/server/Actions")
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Genome = require("../src/shared/Genome")
local MergeVat = require("../src/server/MergeVat")
local MeshAssets = require("../src/shared/MeshAssets")
local PlayerData = require("../src/shared/PlayerData")
local RanchProps = require("../src/visuals/shared/RanchProps")
local Remotes = require("../src/shared/Remotes")
local Rng = require("../src/shared/Rng")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")
local TripleMerge = require("../src/shared/TripleMerge")
local Validate = require("../src/shared/Validate")
local VatDecor = require("../src/visuals/shared/VatDecor")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local slime = Fixtures.slime

local function three(tier: number, extra: { [string]: any }?): { Genome.Slime }
	local out = {}
	for i, id in { "a", "b", "c" } do
		out[i] = slime(id, tier, extra)
	end
	return out
end

describe("TripleMerge: rules", function()
	it("is behind FEATURES.MergeVat3, default off", function()
		expect(Config.FEATURES.MergeVat3).toBe(false)
	end)
	it("takes exactly three different slimes of one rarity", function()
		expect((TripleMerge.canMerge(three(2)))).toBe(true)
		expect(select(2, TripleMerge.canMerge({ slime("a", 2), slime("b", 2) }))).toBe("need three slimes")
		expect(select(2, TripleMerge.canMerge({ slime("a", 2), slime("a", 2), slime("c", 2) }))).toBe(
			"need three different slimes"
		)
		expect(select(2, TripleMerge.canMerge({ slime("a", 2), slime("b", 2), slime("c", 3) }))).toBe(
			"slimes must be the same rarity"
		)
	end)
	it("the tier is T+1 up to Mythic, T+2 only up to Legendary, and Secret stays Secret", function()
		for tier = 1, Config.MAX_TIER do
			local odds = TripleMerge.odds(tier)
			local expected = if tier >= Config.MAX_TIER
				then Config.MAX_TIER
				else math.min(tier + 1, Config.MERGE_MAX_TIER)
			expect(odds.tier).toBe(expected)
			if odds.jumpTier then
				expect(odds.jumpTier).toBe(tier + 2)
				expect(odds.jumpTier <= Config.MERGE_JUMP_MAX_TIER).toBe(true)
				expect(odds.jumpChance).toBe(Config.TRIPLE_MERGE_JUMP_CHANCE)
			else
				expect(odds.jumpChance).toBe(0)
			end
		end
		expect(TripleMerge.odds(3).jumpTier).toBe(5)
		expect(TripleMerge.odds(4).jumpTier).toBeNil()
		expect(TripleMerge.odds(6).tier).toBe(6)
		expect(TripleMerge.odds(7).tier).toBe(7)
	end)
	it("rolls the jump at about TRIPLE_MERGE_JUMP_CHANCE and never lower than T+1", function()
		local rng = Rng.new(3)
		local jumps, n = 0, 3000
		for i = 1, n do
			local child = TripleMerge.merge(three(2), rng, `k{i}`)
			expect(child.tier == 3 or child.tier == 4).toBe(true)
			if child.tier == 4 then
				jumps += 1
			end
		end
		expect(math.abs(jumps / n - Config.TRIPLE_MERGE_JUMP_CHANCE) < 0.03).toBe(true)
		for i = 1, 200 do
			expect(TripleMerge.merge(three(5), rng, `s{i}`).tier).toBe(6) -- no jump into Secret
		end
	end)
	it("is deterministic: one seed and inputs, one child", function()
		local function make(): Genome.Slime
			return TripleMerge.merge(three(3, { mutation = "Glow", mutations = { "Glow" } }), Rng.new(99), "x")
		end
		local x, y = make(), make()
		expect(x).toEqual(y)
	end)
	it("the child is a real species of its tier with its colour, and keeps the strongest mutation", function()
		local ins = three(2)
		ins[1].mutation, ins[1].mutations = "Galaxy", { "Galaxy" }
		local child = TripleMerge.merge(ins, Rng.new(1), "x")
		expect(child.species ~= nil).toBe(true)
		local SlimeRoster = require("../src/shared/SlimeRoster")
		expect((SlimeRoster.get(child.species :: string) :: any).tier).toBe(child.tier)
		expect(Genome.mutationMultiplier(child.mutation) >= Genome.mutationMultiplier("Galaxy")).toBe(true)
		expect(child.size >= Config.MIN_SIZE and child.size <= Config.MAX_SIZE).toBe(true)
	end)
	it("keeps every mutation the three carry, as many as fit", function()
		local ins = three(2)
		ins[1].mutation, ins[1].mutations = "Galaxy", { "Galaxy" }
		ins[2].mutation, ins[2].mutations = "Glow", { "Glow" }
		ins[3].mutation, ins[3].mutations = "Gold", { "Gold" }
		local list = Genome.mutationList(TripleMerge.merge(ins, Rng.new(5), "x"))
		expect(#list >= 1 and #list <= Config.MAX_MUTATIONS).toBe(true)
		expect(Genome.mutationsMultiplier(list) >= 3).toBe(true)
	end)
	it("three of one mutation upgrade it", function()
		local ins = three(2, { mutation = "Glow", mutations = { "Glow" } })
		local child = TripleMerge.merge(ins, Rng.new(8), "x")
		expect(Genome.mutationMultiplier(child.mutation) > Genome.mutationMultiplier("Glow")).toBe(true)
	end)
	it("maxed inputs stay maxed and always roll a mutation", function()
		local child = TripleMerge.merge(three(Config.MAX_TIER), Rng.new(4), "x")
		expect(child.tier).toBe(Config.MAX_TIER)
		expect(child.mutation ~= "None").toBe(true)
	end)
end)

describe("TripleMerge: recipes, caps and the assist", function()
	local MergeRecipes = require("../src/shared/MergeRecipes")
	local SlimeRoster = require("../src/shared/SlimeRoster")

	local function trio(tier: number, species: { string }): { Genome.Slime }
		local out = {}
		for i, id in { "a", "b", "c" } do
			out[i] = slime(id, tier, { species = species[i] })
		end
		return out
	end
	local everything: MergeRecipes.Ctx = { unlocked = MergeRecipes.unlockedFor(math.huge) }

	it("a recipe hit gives its hybrid one tier up, never a jump, whatever the seed", function()
		for _, recipe in MergeRecipes.RECIPES do
			for seed = 1, 20 do
				local child = TripleMerge.merge(trio(recipe.tier - 1, recipe.inputs), Rng.new(seed), "x", nil, everything)
				expect(child.species).toBe(recipe.id)
				expect(child.tier).toBe(recipe.tier)
				expect(child.name).toBe((SlimeRoster.get(recipe.id) :: any).name)
			end
		end
	end)
	it("a random merge never makes a Secret: Mythic x3 gives a Mythic spawn species", function()
		for seed = 1, 300 do
			local child =
				TripleMerge.merge(trio(6, { "cosmo", "cosmo", "cosmo" }), Rng.new(seed), "x", nil, everything)
			expect(child.tier).toBe(6)
			expect((SlimeRoster.get(child.species :: string) :: any).kind).toBe("spawn")
		end
	end)
	it("a +2 jump lands on Legendary at most: Epic x3 is always Legendary", function()
		local jumped = false
		for seed = 1, 400 do
			expect(TripleMerge.merge(three(4), Rng.new(seed), "x").tier).toBe(5)
			jumped = jumped or TripleMerge.merge(three(3), Rng.new(seed), "y").tier == 5
		end
		expect(jumped).toBe(true)
	end)
	it("random results are unlocked spawn species, never hybrids, bosses or event Secrets", function()
		local rng = Rng.new(11)
		for i = 1, 600 do
			local tier = (i % 6) + 1
			local child = TripleMerge.merge(three(tier), rng, `r{i}`)
			local entry = SlimeRoster.get(child.species :: string) :: any
			expect(entry.kind).toBe("spawn")
			expect(entry.family).toBeNil() -- the default ctx opens Classic only
		end
	end)
	it("the assist gives an unfound species about MERGE_ASSIST_CHANCE more often", function()
		-- Rare pool with every family open: whiskers lop moo chomp pengoo. Found: all but pengoo.
		local found = { whiskers = true, lop = true, moo = true, chomp = true }
		local ctx: MergeRecipes.Ctx = { unlocked = everything.unlocked, found = found }
		local rng = Rng.new(21)
		local hits, n = 0, 4000
		for i = 1, n do
			local child = TripleMerge.merge(three(2), rng, `a{i}`, nil, ctx)
			if child.tier == 3 and child.species == "pengoo" then
				hits += 1
			end
		end
		local base = 1 - Config.TRIPLE_MERGE_JUMP_CHANCE
		local expected = base * (Config.MERGE_ASSIST_CHANCE + (1 - Config.MERGE_ASSIST_CHANCE) / 5)
		expect(math.abs(hits / n - expected) < 0.03).toBe(true)
	end)
	it("one seed is one result, and a recipe hit draws the same numbers as a random merge", function()
		local recipe = MergeRecipes.recipeFor("soda") :: MergeRecipes.Recipe
		local function after(ins: { Genome.Slime }): number
			local rng = Rng.new(77)
			TripleMerge.merge(ins, rng, "x", nil, everything)
			return rng:float()
		end
		expect(after(trio(1, recipe.inputs))).toBe(after(trio(1, { "gummy", "gummy", "pebble" })))
		local a = TripleMerge.merge(trio(1, { "gummy", "gummy", "pebble" }), Rng.new(5), "x", nil, everything)
		local b = TripleMerge.merge(trio(1, { "gummy", "gummy", "pebble" }), Rng.new(5), "x", nil, everything)
		expect(a).toEqual(b)
	end)
	it("apply reads the save: rank-opened families and the owned species", function()
		local d = Fixtures.data({
			slime("a", 1, { species = "bubbles" }),
			slime("b", 1, { species = "gummy" }),
			slime("c", 1, { species = "mochi" }),
		})
		local ctx = TripleMerge.ctxFor(d)
		expect(ctx.found and ctx.found.bubbles).toBe(true)
		expect(ctx.unlocked(SlimeRoster.get("prickles") :: any)).toBe(false)
		d.rebirths = 100
		expect(TripleMerge.ctxFor(d).unlocked(SlimeRoster.get("prickles") :: any)).toBe(true)
		local ok, child = TripleMerge.apply(d, { "a", "b", "c" }, nil, Rng.new(1), "n")
		expect(ok).toBe(true)
		expect((child :: Genome.Slime).species).toBe("soda")
	end)
end)

describe("TripleMerge: apply (anti-dupe)", function()
	local function data()
		return Fixtures.data({ slime("a", 2), slime("x", 1), slime("b", 2), slime("c", 2), slime("d", 2) })
	end
	it("replaces three with one on the first pad; the others stay", function()
		local d = data()
		local pad = (PlayerData.findSlime(d, "a") :: Genome.Slime).pad
		local ok, child = TripleMerge.apply(d, { "a", "b", "c" }, nil, Rng.new(1), "new1")
		expect(ok).toBe(true)
		expect(#d.slimes).toBe(3)
		expect(PlayerData.findSlime(d, "a")).toBeNil()
		expect(PlayerData.findSlime(d, "b")).toBeNil()
		expect(PlayerData.findSlime(d, "c")).toBeNil()
		expect((child :: Genome.Slime).pad).toBe(pad)
		expect(PlayerData.findSlime(d, "new1") ~= nil).toBe(true)
	end)
	it("a refused merge changes nothing", function()
		for _, ids in
			{
				{ "a", "a", "b" },
				{ "a", "b" },
				{ "a", "b", "c", "d" },
				{ "a", "b", "zzz" },
				{ "a", "b", "x" },
			}
		do
			local d = data()
			local before = #d.slimes
			local ok = TripleMerge.apply(d, ids, nil, Rng.new(1), "n")
			expect(ok).toBe(false)
			expect(#d.slimes).toBe(before)
			expect(PlayerData.findSlime(d, "n")).toBeNil()
		end
	end)
	it("busy slimes and a reused id are refused; the favourite moves to the child", function()
		local d = data()
		expect(select(2, TripleMerge.apply(d, { "a", "b", "c" }, { c = true }, Rng.new(1), "n"))).toBe("slime is busy")
		expect(select(2, TripleMerge.apply(d, { "a", "b", "c" }, nil, Rng.new(1), "d"))).toBe("duplicate")
		d.favoriteId = "b"
		local ok, child = TripleMerge.apply(d, { "a", "b", "c" }, nil, Rng.new(1), "n2")
		expect(ok).toBe(true)
		expect(d.favoriteId).toBe((child :: Genome.Slime).id)
	end)
	it("can't be applied twice to the same slimes (the second call finds them gone)", function()
		local d = data()
		expect((TripleMerge.apply(d, { "a", "b", "c" }, nil, Rng.new(1), "n"))).toBe(true)
		expect(select(2, TripleMerge.apply(d, { "a", "b", "c" }, nil, Rng.new(1), "n3"))).toBe("missing slime")
	end)
end)

describe("TripleMerge: server action", function()
	local ctxOn: Actions.Context = {
		distanceBetween = function()
			return 2
		end,
		positionOf = function()
			return nil
		end,
		features = { MergeVat3 = true },
	}
	local ctxOff: Actions.Context = { distanceBetween = ctxOn.distanceBetween, positionOf = ctxOn.positionOf }

	local function call(world: any, userId: number, ids: { any }, ctx: Actions.Context)
		world.sessions[userId].limiter = {}
		return Actions.handle(world, userId, "Merge3", ids, T0 + 100, ctx)
	end

	it("is a registered, rate-limited action with three string args", function()
		expect(#Remotes.ACTIONS.Merge3.args).toBe(3)
		expect(Validate.ACTIONS.Merge3 ~= nil).toBe(true)
	end)
	it("is refused with the flag off and merges with it on", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { slime("a", 2), slime("b", 2), slime("c", 2), slime("x", 1) })
		local off = call(world, 1, { "a", "b", "c" }, ctxOff)
		expect(off.ok).toBe(false)
		expect(#s.data.slimes).toBe(4)
		local on = call(world, 1, { "a", "b", "c" }, ctxOn)
		expect(on.ok).toBe(true)
		expect(#s.data.slimes).toBe(2)
		expect(s.data.stats.merges).toBe(1)
		expect(#ServerFixtures.notifications(world, 1) >= 1).toBe(true)
	end)
	it("rejects malformed args and someone else's slimes", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1, { slime("a", 2), slime("b", 2), slime("c", 2) })
		local other = ServerFixtures.join(world, 2)
		expect(call(world, 1, { "a", "b" }, ctxOn).ok).toBe(false)
		expect(call(world, 1, { "a", "b", 5 }, ctxOn).ok).toBe(false)
		expect(call(world, 2, { "a", "b", "c" }, ctxOn).ok).toBe(false)
		expect(#other.data.slimes).toBe(0)
	end)
	it("a slime being carried away is busy", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { slime("a", 2), slime("b", 2), slime("c", 2) })
		ServerFixtures.join(world, 2)
		ServerFixtures.unlock(s)
		Carry.grab(world, 2, "c", 1, T0)
		expect(select(2, MergeVat.merge3(world, s, { "a", "b", "c" }))).toBe("slime is busy")
		expect(#s.data.slimes).toBe(3)
	end)
end)

describe("TripleMerge: decor", function()
	it("the vat stands on the disc's bottom at the disc's width and takes no world slot", function()
		local pose = VatDecor.pose(0, 3, 0)
		expect(math.abs(pose.position[2] - pose.size[2] / 2 - 1) < 1e-9).toBe(true)
		expect(math.abs(VatDecor.BODY_DIAMETER * VatDecor.SCALE - VatDecor.DISC_DIAMETER) < 1e-9).toBe(true)
		expect(MeshAssets.meshId("merge_vat") ~= nil).toBe(true)
		expect(RanchProps.INTENTIONALLY_UNPLACED.merge_vat ~= nil).toBe(true)
		local function scan(node: any)
			local a = node.attributes or {}
			expect(a.MeshAsset ~= "merge_vat" and a.BorderMesh ~= "merge_vat").toBe(true)
			for _, c in node.children or {} do
				scan(c)
			end
		end
		for _, root in WorldLayout.build() do
			scan(root)
		end
	end)
end)
