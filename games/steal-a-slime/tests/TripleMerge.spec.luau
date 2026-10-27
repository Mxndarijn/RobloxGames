--!strict
-- The 3-slime merge (TripleMerge, CONTRACT.md §21): rules, odds, determinism, anti-dupe and the vat decor.
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Genome = require("../src/shared/Genome")
local MeshAssets = require("../src/shared/MeshAssets")
local PlayerData = require("../src/shared/PlayerData")
local RanchProps = require("../src/visuals/shared/RanchProps")
local Rng = require("../src/shared/Rng")
local SlimeRoster = require("../src/shared/SlimeRoster")
local TestRunner = require("./TestRunner")
local TripleMerge = require("../src/shared/TripleMerge")
local VatDecor = require("../src/visuals/shared/VatDecor")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local slime = Fixtures.slime

local function three(tier: number, extra: { [string]: any }?): { Genome.Slime }
	local out = {}
	for i, id in { "a", "b", "c" } do
		out[i] = slime(id, tier, extra)
	end
	return out
end

describe("TripleMerge: rules", function()
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
	it("the tier is T+1 up to Celestial, T+2 only up to Legendary, and Divine stays Divine", function()
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
		expect(TripleMerge.odds(6).tier).toBe(7)
		expect(TripleMerge.odds(7).tier).toBe(8)
		expect(TripleMerge.odds(8).tier).toBe(8)
		expect(TripleMerge.odds(9).tier).toBe(9)
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
			return TripleMerge.merge(three(3), Rng.new(99), "x")
		end
		local x, y = make(), make()
		expect(x).toEqual(y)
	end)
	it("the child is a real species of its tier with its colour", function()
		local ins = three(2)
		local child = TripleMerge.merge(ins, Rng.new(1), "x")
		expect(child.species ~= nil).toBe(true)
		expect((SlimeRoster.get(child.species :: string) :: any).tier).toBe(child.tier)
		expect(child.size >= Config.MIN_SIZE and child.size <= Config.MAX_SIZE).toBe(true)
	end)
	it("maxed inputs stay maxed", function()
		local child = TripleMerge.merge(three(Config.MAX_TIER), Rng.new(4), "x")
		expect(child.tier).toBe(Config.MAX_TIER)
	end)
end)

describe("TripleMerge: recipes, caps and the assist", function()
	local MergeRecipes = require("../src/shared/MergeRecipes")

	local function trio(tier: number, species: { string }): { Genome.Slime }
		local out = {}
		for i, id in { "a", "b", "c" } do
			out[i] = slime(id, tier, { species = species[i] })
		end
		return out
	end
	local everything: MergeRecipes.Ctx = { unlocked = MergeRecipes.everySpecies }

	it("a recipe hit gives its hybrid one tier up, never a jump, whatever the seed", function()
		for _, recipe in MergeRecipes.RECIPES do
			for seed = 1, 20 do
				local child = TripleMerge.merge(trio(recipe.tier - 1, recipe.inputs), Rng.new(seed), "x", everything)
				expect(child.species).toBe(recipe.id)
				expect(child.tier).toBe(recipe.tier)
				expect(child.name).toBe((SlimeRoster.get(recipe.id) :: any).name)
			end
		end
	end)
	it("Mythic x3 at random gives a Secret spawn species and Secret x3 a Celestial, never a jackpot", function()
		for seed = 1, 300 do
			local child = TripleMerge.merge(trio(6, { "cosmo", "cosmo", "cosmo" }), Rng.new(seed), "x", everything)
			expect(child.tier).toBe(Config.SECRET_TIER)
			local entry = SlimeRoster.get(child.species :: string) :: any
			expect(entry.kind).toBe("spawn")
			expect(entry.jackpot).toBeNil()
			local up = TripleMerge.merge(trio(7, { "midas", "gaia", "boo" }), Rng.new(seed), "y", everything)
			expect(up.tier).toBe(8)
			expect((SlimeRoster.get(up.species :: string) :: any).jackpot).toBeNil()
		end
	end)
	it("Mythic and Secret loads merge at random; Celestial and Divine loads only merge as a recipe", function()
		expect((TripleMerge.canMerge(trio(6, { "cosmo", "cosmo", "cosmo" })))).toBe(true)
		expect((TripleMerge.canMerge(trio(7, { "midas", "midas", "midas" })))).toBe(true)
		expect(select(2, TripleMerge.canMerge(trio(8, { "lunara", "solaris", "nebulon" })))).toBe(
			"only a recipe merges these"
		)
		expect(select(2, TripleMerge.canMerge(trio(9, { "aurora", "kirin", "goo_oracle" })))).toBe(
			"only a recipe merges these"
		)
		local nightwing = MergeRecipes.recipeFor("nightwing") :: any
		expect(nightwing.tier).toBe(Config.SECRET_TIER)
		expect((TripleMerge.canMerge(trio(nightwing.tier - 1, nightwing.inputs)))).toBe(true)
		local child = TripleMerge.merge(trio(nightwing.tier - 1, nightwing.inputs), Rng.new(1), "x", everything)
		expect(child.species).toBe("nightwing")
	end)
	it("the child is marked brewed: 1 from a random merge, 2 from a recipe, and earns that bonus", function()
		local function plain(s: Genome.Slime): Genome.Slime
			local copy = table.clone(s)
			copy.brewed = nil
			return copy
		end
		for seed = 1, 20 do
			local random = TripleMerge.merge(three(2), Rng.new(seed), "r", everything)
			expect(random.brewed).toBe(1)
			expect(Genome.baseIncome(random)).toBeCloseTo(
				Genome.baseIncome(plain(random)) * Config.BREWED_INCOME_MULT,
				1e-9
			)
		end
		local recipe = MergeRecipes.RECIPES[1]
		local hybrid = TripleMerge.merge(trio(recipe.tier - 1, recipe.inputs), Rng.new(3), "h", everything)
		expect(hybrid.species).toBe(recipe.id)
		expect(hybrid.brewed).toBe(2)
		expect(Genome.baseIncome(hybrid)).toBeCloseTo(
			Genome.baseIncome(plain(hybrid)) * Config.RECIPE_INCOME_MULT,
			1e-9
		)
	end)
	it("a +2 jump lands on Legendary at most: Epic x3 is always Legendary", function()
		local jumped = false
		for seed = 1, 400 do
			expect(TripleMerge.merge(three(4), Rng.new(seed), "x").tier).toBe(5)
			jumped = jumped or TripleMerge.merge(three(3), Rng.new(seed), "y").tier == 5
		end
		expect(jumped).toBe(true)
	end)
	it("random results are unlocked spawn species, never hybrids, bosses, event Secrets or jackpots", function()
		local rng = Rng.new(11)
		for i = 1, 600 do
			local tier = (i % 6) + 1
			local child = TripleMerge.merge(three(tier), rng, `r{i}`)
			local entry = SlimeRoster.get(child.species :: string) :: any
			expect(entry.kind).toBe("spawn")
			expect(entry.jackpot).toBeNil()
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
			local child = TripleMerge.merge(three(2), rng, `a{i}`, ctx)
			if child.tier == 3 and child.species == "pengoo" then
				hits += 1
			end
		end
		local base = 1 - Config.TRIPLE_MERGE_JUMP_CHANCE
		local total = 0
		for _, id in { "whiskers", "lop", "moo", "chomp", "pengoo" } do
			total += Genome.speciesWeight(SlimeRoster.get(id) :: any)
		end
		local pengoo = Genome.speciesWeight(SlimeRoster.get("pengoo") :: any) / total
		local expected = base * (Config.MERGE_ASSIST_CHANCE + (1 - Config.MERGE_ASSIST_CHANCE) * pengoo)
		expect(math.abs(hits / n - expected) < 0.03).toBe(true)
	end)
	it("one seed is one result, and a recipe hit draws the same numbers as a random merge", function()
		local recipe = MergeRecipes.recipeFor("soda") :: MergeRecipes.Recipe
		local function after(ins: { Genome.Slime }): number
			local rng = Rng.new(77)
			TripleMerge.merge(ins, rng, "x", everything)
			return rng:float()
		end
		expect(after(trio(1, recipe.inputs))).toBe(after(trio(1, { "gummy", "gummy", "pebble" })))
		local a = TripleMerge.merge(trio(1, { "gummy", "gummy", "pebble" }), Rng.new(5), "x", everything)
		local b = TripleMerge.merge(trio(1, { "gummy", "gummy", "pebble" }), Rng.new(5), "x", everything)
		expect(a).toEqual(b)
	end)
	it("apply reads the save: every family at any rank, and the owned species", function()
		local d = Fixtures.data({
			slime("a", 1, { species = "bubbles" }),
			slime("b", 1, { species = "gummy" }),
			slime("c", 1, { species = "mochi" }),
		})
		local ctx = TripleMerge.ctxFor(d)
		expect(ctx.found and ctx.found.bubbles).toBe(true)
		expect(ctx.unlocked(SlimeRoster.get("prickles") :: any)).toBe(true)
		local ok, child = TripleMerge.apply(d, { "a", "b", "c" }, nil, Rng.new(1), "n")
		expect(ok).toBe(true)
		expect((child :: Genome.Slime).species).toBe("soda")
	end)
end)

describe("TripleMerge: jackpots", function()
	it("refuses any load with a jackpot in it", function()
		for _, case in
			{
				{ tier = 7, species = { "jackpot", "midas", "midas" } },
				{ tier = 7, species = { "midas", "midas", "jackpot" } },
				{ tier = 8, species = { "star_emperor", "lunara", "solaris" } },
				{ tier = 9, species = { "goo_god", "goo_god", "goo_god" } },
			}
		do
			local ins = {}
			for i, id in { "a", "b", "c" } do
				ins[i] = slime(id, case.tier, { species = case.species[i] })
			end
			local ok, reason = TripleMerge.canMerge(ins)
			expect(ok).toBe(false)
			expect(reason).toBe("jackpot slimes can't be merged")
		end
	end)
	it("a refused jackpot merge leaves the save as it was", function()
		local d = Fixtures.data({
			slime("a", 7, { species = "jackpot" }),
			slime("b", 7, { species = "midas" }),
			slime("c", 7, { species = "midas" }),
		})
		d.rebirths = 30
		local ok, reason = TripleMerge.apply(d, { "a", "b", "c" }, nil, Rng.new(1), "n")
		expect(ok).toBe(false)
		expect(reason).toBe("jackpot slimes can't be merged")
		expect(#d.slimes).toBe(3)
	end)
end)

describe("TripleMerge: shines", function()
	local MergeRecipes = require("../src/shared/MergeRecipes")
	local everything: MergeRecipes.Ctx = { unlocked = MergeRecipes.everySpecies }
	local function shiny(tier: number, shines: { [number]: string? }, species: string?): { Genome.Slime }
		local out = {}
		for i, id in { "a", "b", "c" } do
			out[i] = slime(id, tier, { species = species, shine = shines[i] })
		end
		return out
	end

	it("the child keeps a shine all three parents share", function()
		for seed = 1, 30 do
			local child = TripleMerge.merge(shiny(2, { "Gold", "Gold", "Gold" }), Rng.new(seed), "x", everything)
			expect(child.shine).toBe("Gold")
		end
	end)
	it("a mixed or partial shine is dropped", function()
		local cases: { { [number]: string? } } = {
			{ "Gold", "Gold", "Diamond" },
			{ [1] = "Rainbow", [3] = "Rainbow" },
			{ [3] = "Gold" },
		}
		for _, shines in cases do
			local child = TripleMerge.merge(shiny(2, shines), Rng.new(1), "x", everything)
			expect(child.shine).toBeNil()
		end
	end)
	it("three Secrets sharing a shine brew a Divine that keeps it, from the recipe's rebirths", function()
		local recipe = Config.SHINE_RECIPE
		expect(recipe.from).toBe(Config.SECRET_TIER)
		local ctx: MergeRecipes.Ctx = { unlocked = MergeRecipes.everySpecies, rebirths = recipe.rebirths }
		for seed = 1, 100 do
			local ins = shiny(recipe.from, { "Diamond", "Diamond", "Diamond" }, "midas")
			local child = TripleMerge.merge(ins, Rng.new(seed), "x", ctx)
			expect(child.tier).toBe(recipe.into)
			expect(child.shine).toBe("Diamond")
			local entry = SlimeRoster.get(child.species :: string) :: any
			expect(`{entry.tier} {entry.kind} {entry.jackpot}`).toBe(`{recipe.into} spawn nil`)
		end
	end)
	it("below the recipe's rebirths the same shiny Secrets brew a Celestial", function()
		local recipe = Config.SHINE_RECIPE
		local ctx: MergeRecipes.Ctx = { unlocked = MergeRecipes.everySpecies, rebirths = recipe.rebirths - 1 }
		for seed = 1, 50 do
			local child =
				TripleMerge.merge(shiny(recipe.from, { "Gold", "Gold", "Gold" }, "midas"), Rng.new(seed), "x", ctx)
			expect(child.tier).toBe(Config.SECRET_TIER + 1)
			expect(child.shine).toBe("Gold")
		end
	end)
	it("Secrets without a shared shine brew a Celestial at any rank", function()
		local ctx: MergeRecipes.Ctx = { unlocked = MergeRecipes.everySpecies, rebirths = 99 }
		for seed = 1, 50 do
			local ins = shiny(Config.SECRET_TIER, { [1] = "Gold", [2] = "Gold" }, "midas")
			local child = TripleMerge.merge(ins, Rng.new(seed), "x", ctx)
			expect(child.tier).toBe(Config.SECRET_TIER + 1)
		end
	end)
	it("apply brews the Divine from a save with enough rebirths", function()
		local d = Fixtures.data({
			slime("a", 7, { species = "midas", shine = "Rainbow" }),
			slime("b", 7, { species = "gaia", shine = "Rainbow" }),
			slime("c", 7, { species = "boo", shine = "Rainbow" }),
		})
		d.rebirths = Config.SHINE_RECIPE.rebirths
		local ok, child = TripleMerge.apply(d, { "a", "b", "c" }, nil, Rng.new(2), "n")
		expect(ok).toBe(true)
		expect((child :: Genome.Slime).tier).toBe(Config.SHINE_RECIPE.into)
		expect((child :: Genome.Slime).shine).toBe("Rainbow")
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
