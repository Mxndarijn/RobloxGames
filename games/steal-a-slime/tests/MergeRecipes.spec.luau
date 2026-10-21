--!strict
-- Merge recipes (CONTRACT.md §35): the 15 recipes, the pure lookup and its random fallback.
local Config = require("../src/shared/Config")
local MergeRecipes = require("../src/shared/MergeRecipes")
local SlimeRoster = require("../src/shared/SlimeRoster")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local ALL: MergeRecipes.Ctx = { unlocked = MergeRecipes.everySpecies }
local CLASSIC: MergeRecipes.Ctx = { unlocked = MergeRecipes.classicOnly }

local function inputs(tier: number, species: { string? }): { MergeRecipes.Input }
	return {
		{ tier = tier, species = species[1] },
		{ tier = tier, species = species[2] },
		{ tier = tier, species = species[3] },
	}
end

local function orders(list: { string }): { { string } }
	local a, b, c = list[1], list[2], list[3]
	return { { a, b, c }, { a, c, b }, { b, a, c }, { b, c, a }, { c, a, b }, { c, b, a } }
end

describe("MergeRecipes: the recipes", function()
	it("has one recipe per hybrid: 15, each three spawning species of one tier under it", function()
		expect(#MergeRecipes.RECIPES).toBe(15)
		expect(#MergeRecipes.RECIPES).toBe(#SlimeRoster.ofKind("hybrid"))
		for _, hybrid in SlimeRoster.ofKind("hybrid") do
			local recipe = MergeRecipes.recipeFor(hybrid.id) :: MergeRecipes.Recipe
			expect(recipe ~= nil).toBe(true)
			expect(recipe.tier).toBe(hybrid.tier)
			expect(#recipe.inputs).toBe(3)
			for _, id in recipe.inputs do
				local entry = SlimeRoster.get(id) :: SlimeRoster.Entry
				expect(entry.kind).toBe("spawn")
				expect(entry.tier).toBe(hybrid.tier - 1)
			end
			expect(#(MergeRecipes.hint(hybrid.id) :: string) > 0).toBe(true)
		end
		expect((MergeRecipes.recipeFor("sushi") :: any).tier).toBe(4)
		expect(MergeRecipes.recipeFor("gummy")).toBeNil()
		expect(MergeRecipes.hint("gummy")).toBeNil()
	end)
	it("every recipe hits in any order", function()
		for _, recipe in MergeRecipes.RECIPES do
			for _, order in orders(recipe.inputs) do
				expect((MergeRecipes.find(order) :: any).id).toBe(recipe.id)
				local outcome = MergeRecipes.resolve(inputs(recipe.tier - 1, order), CLASSIC)
				expect(outcome.kind).toBe("recipe")
				expect((outcome.recipe :: any).id).toBe(recipe.id)
				expect(outcome.tier).toBe(recipe.tier)
				expect(outcome.jumpChance).toBe(0)
			end
		end
	end)
	it("no two recipes share an input set", function()
		local seen = {}
		for _, recipe in MergeRecipes.RECIPES do
			local key = MergeRecipes.key(recipe.inputs)
			expect(seen[key]).toBeNil()
			seen[key] = true
		end
	end)
	it("mixed tiers never hit; they are refused", function()
		local outcome = MergeRecipes.resolve({
			{ tier = 1, species = "bubbles" },
			{ tier = 1, species = "gummy" },
			{ tier = 2, species = "mochi" },
		}, ALL)
		expect(outcome.kind).toBe("refused")
		expect(outcome.reason).toBe("slimes must be the same rarity")
		expect(MergeRecipes.resolve(inputs(1, { "bubbles", "gummy" }) :: any, ALL).kind).toBe("random")
		local two = { { tier = 1, species = "bubbles" }, { tier = 1, species = "gummy" } }
		expect(MergeRecipes.resolve(two, ALL).reason).toBe("need three slimes")
	end)
	it("a nil species never hits", function()
		for _, recipe in MergeRecipes.RECIPES do
			for i = 1, 3 do
				local species: { string? } = table.clone(recipe.inputs) :: { string? }
				species[i] = nil
				expect(MergeRecipes.find(species)).toBeNil()
				expect(MergeRecipes.resolve(inputs(recipe.tier - 1, species), ALL).kind).toBe("random")
			end
		end
	end)
	it("the right species at the wrong tier never hit", function()
		local outcome = MergeRecipes.resolve(inputs(2, { "bubbles", "gummy", "mochi" }), ALL)
		expect(outcome.kind).toBe("random")
	end)
end)

describe("MergeRecipes: the random fallback", function()
	it("the pool is unlocked spawn species of the result tier, never hybrids, bosses or event Secrets", function()
		for tier = 1, Config.MAX_TIER do
			local pool = MergeRecipes.pool(tier, ALL)
			for _, id in pool do
				local entry = SlimeRoster.get(id) :: SlimeRoster.Entry
				expect(entry.kind).toBe("spawn")
				expect(entry.tier).toBe(tier)
			end
			expect(#pool).toBe(
				#SlimeRoster.forTier(tier)
					+ #SlimeRoster.forTier(tier, "orchard")
					+ #SlimeRoster.forTier(tier, "frost")
					+ #SlimeRoster.forTier(tier, "starlight")
			)
		end
	end)
	it("locked families stay out of the pool until the rank opens them", function()
		local classic = MergeRecipes.resolve(inputs(5, {}), CLASSIC)
		expect(classic.tier).toBe(6)
		expect(table.concat(classic.pool, ",")).toBe("cosmo")
		local starlight = MergeRecipes.resolve(inputs(5, {}), ALL)
		expect(table.concat(starlight.pool, ",")).toBe("cosmo,seraph,amethyst,prism")
		for tier = 1, Config.MAX_TIER do
			for _, id in MergeRecipes.pool(tier, CLASSIC) do
				expect((SlimeRoster.get(id) :: SlimeRoster.Entry).family).toBeNil()
			end
		end
	end)
	it("caps: Mythic x3 is Mythic, Secret x3 Secret, and the jump stops at Legendary", function()
		expect(MergeRecipes.resolve(inputs(6, {}), ALL).tier).toBe(6)
		local secret = MergeRecipes.resolve(inputs(7, {}), ALL)
		expect(secret.tier).toBe(7)
		expect(secret.jumpTier).toBeNil()
		expect(MergeRecipes.resolve(inputs(3, {}), ALL).jumpTier).toBe(5)
		expect(MergeRecipes.resolve(inputs(4, {}), ALL).jumpTier).toBeNil()
		for tier = 1, Config.MAX_TIER do
			local outcome = MergeRecipes.resolve(inputs(tier, {}), ALL)
			expect(outcome.kind).toBe("random")
			if tier < Config.MAX_TIER then
				expect(outcome.tier <= Config.MERGE_MAX_TIER).toBe(true)
			end
			expect((outcome.jumpTier or 0) <= Config.MERGE_JUMP_MAX_TIER).toBe(true)
		end
	end)
	it("the assist pool is the unfound part of the pool, and empty means no assist", function()
		local some = MergeRecipes.resolve(inputs(1, {}), { unlocked = CLASSIC.unlocked, found = { bumble = true } })
		expect(table.concat(some.assistPool, ",")).toBe("mushie,froggo")
		expect(some.assistChance).toBe(Config.MERGE_ASSIST_CHANCE)
		local found = { bumble = true, mushie = true, froggo = true }
		local none = MergeRecipes.resolve(inputs(1, {}), { unlocked = CLASSIC.unlocked, found = found })
		expect(#none.assistPool).toBe(0)
		expect(none.assistChance).toBe(0)
	end)
end)

describe("MergeRecipes: discovery", function()
	local soda = MergeRecipes.recipeFor("soda") :: MergeRecipes.Recipe
	it("known = every input found; discovered = the hybrid found", function()
		expect(MergeRecipes.isKnown(soda, { bubbles = true, gummy = true })).toBe(false)
		expect(MergeRecipes.isKnown(soda, { bubbles = true, gummy = true, mochi = true })).toBe(true)
		expect(MergeRecipes.isDiscovered("soda", { bubbles = true, gummy = true, mochi = true })).toBe(false)
		expect(MergeRecipes.isDiscovered("soda", { soda = true })).toBe(true)
		expect(MergeRecipes.isDiscovered("soda", nil)).toBe(false)
	end)
	it("found = owned species (slimes or State views) plus the saved set", function()
		local found = MergeRecipes.foundOf(
			{ { species = "gummy" }, { slime = { species = "soda" } }, { species = nil } },
			{ mochi = true }
		)
		expect(found.gummy).toBe(true)
		expect(found.soda).toBe(true)
		expect(found.mochi).toBe(true)
		expect(found.pebble).toBeNil()
	end)
end)
