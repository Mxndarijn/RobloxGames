--!strict
-- Merge menu rules (CONTRACT.md §21.1): auto-merge planning (MergePlan), the result preview (MergePreview),
-- kept slimes, and the AutoMerge / KeepSlime actions. Flag-on paths pass ctx.features.MergeVat3.
local Actions = require("../src/server/Actions")
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Merge = require("../src/shared/Merge")
local MergePlan = require("../src/shared/MergePlan")
local MergePreview = require("../src/shared/MergePreview")
local PlayerData = require("../src/shared/PlayerData")
local Remotes = require("../src/shared/Remotes")
local Rng = require("../src/shared/Rng")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")
local TripleMerge = require("../src/shared/TripleMerge")
local Validate = require("../src/shared/Validate")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local slime = Fixtures.slime

local function cand(id: string, tier: number, income: number, extra: { [string]: any }?): MergePlan.Candidate
	local c: any = { id = id, tier = tier, income = income, size = 1 }
	for k, v in extra or {} do
		c[k] = v
	end
	return c
end

local function idsOf(groups: { MergePlan.Group }): { { string } }
	local out = {}
	for i, g in groups do
		out[i] = g.ids
	end
	return out
end

describe("MergePlan: rarity masks", function()
	it("round-trips a rarity set and never includes Secret", function()
		expect(MergePlan.maskOf({ [1] = true, [3] = true })).toBe(5)
		local back = MergePlan.tiersOf(5)
		expect(back[1] and back[3] and not back[2]).toBe(true)
		expect(MergePlan.tiersOf(2 ^ Config.MAX_TIER - 1)[Config.MAX_TIER]).toBeNil()
		expect(MergePlan.maskOf({ [Config.MAX_TIER] = true })).toBe(0)
	end)
	it("ignores junk masks", function()
		expect(next(MergePlan.tiersOf(-1))).toBeNil()
		expect(next(MergePlan.tiersOf(0 / 0))).toBeNil()
		expect(next(MergePlan.tiersOf(math.huge))).toBeNil()
	end)
end)

describe("MergePlan.plan", function()
	it("takes the lowest-income slimes first, in groups of three, leftovers stay", function()
		local list = {
			cand("a", 1, 5),
			cand("b", 1, 1),
			cand("c", 1, 3),
			cand("d", 1, 2),
			cand("e", 1, 4),
			cand("f", 1, 9),
			cand("g", 1, 8),
		}
		expect(idsOf(MergePlan.plan(list, { tiers = { [1] = true } }))).toEqual({ { "b", "d", "c" }, { "e", "a", "g" } })
	end)
	it("never uses favourite, kept or busy slimes", function()
		local list = {
			cand("fav", 1, 0, { favorite = true }),
			cand("kept", 1, 0, { keep = true }),
			cand("busy", 1, 0, { busy = true }),
			cand("a", 1, 1),
			cand("b", 1, 1),
			cand("c", 1, 1),
		}
		expect(idsOf(MergePlan.plan(list, { tiers = { [1] = true } }))).toEqual({ { "a", "b", "c" } })
	end)
	it("only plans the chosen rarities, lowest first, and stops at the limit", function()
		local list = {}
		for i = 1, 6 do
			table.insert(list, cand(`r{i}`, 3, i))
			table.insert(list, cand(`c{i}`, 1, i))
			table.insert(list, cand(`u{i}`, 2, i))
		end
		local groups = MergePlan.plan(list, { tiers = { [1] = true, [3] = true } })
		expect(#groups).toBe(4)
		expect(groups[1].tier).toBe(1)
		expect(groups[3].tier).toBe(3)
		expect(MergePlan.countByTier(groups)).toEqual({ [1] = 2, [3] = 2 })
		expect(#MergePlan.plan(list, { tiers = { [1] = true, [2] = true, [3] = true }, limit = 5 })).toBe(5)
	end)
	it("ties break on size, then id", function()
		local list = { cand("z", 1, 1, { size = 0.5 }), cand("y", 1, 1), cand("x", 1, 1) }
		expect(MergePlan.plan(list, { tiers = { [1] = true } })[1].ids).toEqual({ "z", "x", "y" })
	end)
end)

describe("MergePlan.suggest", function()
	local list = {
		cand("c1", 1, 3),
		cand("c2", 1, 1),
		cand("u1", 2, 1),
		cand("u2", 2, 2),
		cand("u3", 2, 3),
		cand("u4", 2, 0, { favorite = true }),
	}
	it("picks the cheapest group of the lowest rarity that has one", function()
		local g = MergePlan.suggest(list, nil, 3)
		expect(g and g.tier).toBe(2)
		expect(g and g.ids).toEqual({ "u1", "u2", "u3" })
	end)
	it("honours a rarity and the vat size; nil when there is no group", function()
		expect((MergePlan.suggest(list, 1, 2) :: any).ids).toEqual({ "c2", "c1" })
		expect(MergePlan.suggest(list, 1, 3)).toBeNil()
		expect(MergePlan.suggest({}, nil, 3)).toBeNil()
	end)
end)

describe("MergePlan candidates", function()
	it("from data: income from PlayerData.slimeIncome, flags from data and the busy set", function()
		local data = Fixtures.data({ slime("a", 2, { keep = true }), slime("b", 2), slime("c", 2, { size = 2 }) })
		data.favoriteId = "b"
		local list = MergePlan.fromData(data, { c = true })
		expect(list[1].keep).toBe(true)
		expect(list[2].favorite).toBe(true)
		expect(list[3].busy).toBe(true)
		expect(list[3].income).toBe(PlayerData.slimeIncome(data, data.slimes[3]))
	end)
	it("from State views: a slime being stolen is busy", function()
		local list = MergePlan.fromViews({
			{ slime = slime("a", 1), income = 4 },
			{ slime = slime("b", 1, { keep = true }), income = 1, stolenBy = 7 },
		}, "a")
		expect(list[1].favorite and list[1].income == 4).toBe(true)
		expect(list[2].busy and list[2].keep).toBe(true)
	end)
end)

describe("MergePreview", function()
	it("shows a random species of the next rarity, the jump and what carries over", function()
		local p = MergePreview.forSlimes({
			slime("a", 2, { mutation = "Glow", mutations = { "Glow" }, size = 1 }),
			slime("b", 2, { size = 1.3 }),
			slime("c", 2, { size = 1.1 }),
		})
		expect(p.kind).toBe("random")
		expect(p.title).toBe(`Random {Config.RARITIES[3].name} slime`)
		expect(p.tier).toBe(3)
		expect(p.jumpRarity).toBe(Config.RARITIES[4].name)
		expect(p.jumpChance).toBe(Config.TRIPLE_MERGE_JUMP_CHANCE)
		expect(p.mutations).toEqual({ "Glow" })
		expect(p.size).toBe(math.floor(((1 + 1.3 + 1.1) / 3 + Config.TRIPLE_MERGE_SIZE_BONUS) * 100 + 0.5) / 100)
	end)
	it("previews the full load from fewer picks, and the pair vat without a jump", function()
		local partial = MergePreview.forSlimes({ slime("a", 1) }, nil, nil, 3)
		expect(partial.jumpTier).toBe(3)
		local pair = MergePreview.forSlimes({ slime("a", 1), slime("b", 1) }, nil, nil, 2)
		expect(pair.tier).toBe(2)
		expect(pair.jumpTier).toBeNil()
		expect(pair.jumpChance).toBe(0)
	end)
	it("the top rarity stays put and always rolls a mutation; no recipe matches", function()
		local s = { slime("a", Config.MAX_TIER), slime("b", Config.MAX_TIER), slime("c", Config.MAX_TIER) }
		local p = MergePreview.forSlimes(s)
		expect(p.tier).toBe(Config.MAX_TIER)
		expect(p.freshMutationChance).toBe(1)
		expect(MergePreview.recipeFor(s)).toBeNil()
	end)
	it("names a recipe only once its hybrid is found; an undiscovered hit looks like any random merge", function()
		local picks = {
			slime("a", 1, { species = "mochi" }),
			slime("b", 1, { species = "bubbles" }),
			slime("c", 1, { species = "gummy" }),
		}
		local random = MergePreview.forSlimes({ slime("x", 1), slime("y", 1), slime("z", 1) }, { slimes = {} })
		local hidden = MergePreview.forSlimes(picks, { slimes = {} })
		expect(hidden).toEqual(MergePreview.forSlimes(picks, nil))
		expect(hidden.kind).toBe("random")
		expect(hidden.title).toBe(random.title)
		expect(hidden.jumpChance).toBe(random.jumpChance)
		expect(hidden.species).toBeNil()

		local owned = MergePreview.forSlimes(picks, { slimes = { { slime = slime("s", 2, { species = "soda" }) } } })
		local saved = MergePreview.forSlimes(picks, { slimes = {}, found = { soda = true } })
		for _, p in { owned, saved } do
			expect(p.kind).toBe("recipe")
			expect(p.title).toBe("Soda Pop")
			expect(p.species).toBe("soda")
			expect(p.tier).toBe(2)
			expect(p.jumpTier).toBeNil()
			expect(p.jumpChance).toBe(0)
		end
		-- The pair vat never takes a recipe.
		local pair = MergePreview.forSlimes({ picks[1], picks[2] }, { found = { soda = true } }, nil, 2)
		expect(pair.kind).toBe("random")
	end)
	it("lists the inherited mutations strongest first, like the merge itself", function()
		local parents = {
			slime("a", 2, { mutation = "Gold", mutations = { "Gold" } }),
			slime("b", 2, { mutation = "Glow", mutations = { "Glow" } }),
			slime("c", 2),
		}
		local kept = TripleMerge.keptMutations(parents)
		expect(kept[1]).toBe(TripleMerge.inheritedPrimary(parents))
		expect(#kept >= 1).toBe(true)
		expect(#TripleMerge.keptMutations({ slime("a", 1), slime("b", 1), slime("c", 1) })).toBe(0)
	end)
end)

describe("kept slimes", function()
	it("are never merged by hand, in the pair or the 3-slime vat", function()
		local data = Fixtures.data({ slime("a", 1, { keep = true }), slime("b", 1), slime("c", 1) })
		expect(select(2, TripleMerge.apply(data, { "a", "b", "c" }, nil, Rng.new(1), "n1"))).toBe("slime is kept")
		expect(select(2, Merge.apply(data, "b", "a", nil, Rng.new(1), "n2"))).toBe("slime is kept")
		expect(#data.slimes).toBe(3)
	end)
	it("survive a save round trip; junk is dropped and false is not written", function()
		local data = Fixtures.data({ slime("a", 1, { keep = true }), slime("b", 1) })
		local saved = SaveData.serialize(data, T0)
		expect(saved.slimes[1].keep).toBe(true)
		expect(saved.slimes[2].keep).toBeNil()
		local back = SaveData.deserialize(saved)
		expect(back.slimes[1].keep).toBe(true)
		expect(back.slimes[2].keep).toBeNil()
		saved.slimes[2].keep = "yes"
		expect(SaveData.deserialize(saved).slimes[2].keep).toBeNil()
	end)
end)

describe("AutoMerge / KeepSlime actions", function()
	local ctxOn: Actions.Context = {
		distanceBetween = function()
			return 2
		end,
		positionOf = function()
			return nil
		end,
		features = { MergeVat3 = true },
	}
	local ctxOff: Actions.Context =
		{ distanceBetween = ctxOn.distanceBetween, positionOf = ctxOn.positionOf, features = { MergeVat3 = false } }

	local function call(world: any, userId: number, action: string, args: { any }, ctx: Actions.Context)
		world.sessions[userId].limiter = {}
		return Actions.handle(world, userId, action, args, T0 + 100, ctx)
	end

	it("are registered, rate-limited actions", function()
		expect(Remotes.ACTIONS.AutoMerge.args).toEqual({ "number" })
		expect(Remotes.ACTIONS.KeepSlime.args).toEqual({ "string", "boolean" })
		expect(Validate.ACTIONS.AutoMerge ~= nil and Validate.ACTIONS.KeepSlime ~= nil).toBe(true)
	end)
	it("merges every planned group of the chosen rarities, skipping favourite and kept slimes", function()
		local world = ServerFixtures.world()
		-- A plot holds PADS_MAX slimes: c1 (favourite), c2..c5, k (kept), u1, u2.
		local list = {}
		for i = 1, 5 do
			table.insert(list, slime(`c{i}`, 1))
		end
		table.insert(list, slime("k", 1, { keep = true }))
		table.insert(list, slime("u1", 2))
		table.insert(list, slime("u2", 2))
		local s = ServerFixtures.join(world, 1, list)
		s.data.favoriteId = "c1"
		local res = call(world, 1, "AutoMerge", { MergePlan.maskOf({ [1] = true, [2] = true }) }, ctxOn)
		expect(res.ok).toBe(true)
		-- equal incomes and sizes: ids decide, so c2, c3, c4 merge; c5 is left over, the Uncommons are only two
		expect(s.data.stats.merges).toBe(1)
		expect(#s.data.slimes).toBe(#list - 3 + 1)
		for _, id in { "c1", "c5", "k", "u1", "u2" } do
			expect(PlayerData.findSlime(s.data, id) ~= nil).toBe(true)
		end
		for _, id in { "c2", "c3", "c4" } do
			expect(PlayerData.findSlime(s.data, id)).toBeNil()
		end
		expect(#ServerFixtures.notifications(world, 1)).toBe(1)
	end)
	it("is refused with the flag off, with no rarity, and with nothing to merge", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { slime("a", 1), slime("b", 1), slime("c", 1), slime("d", 2) })
		expect(call(world, 1, "AutoMerge", { 1 }, ctxOff).message).toBe("the 3-slime vat is off")
		expect(call(world, 1, "AutoMerge", { 0 }, ctxOn).message).toBe("pick a rarity")
		expect(call(world, 1, "AutoMerge", { 2 }, ctxOn).message).toBe("nothing to merge")
		expect(call(world, 1, "AutoMerge", { "1" }, ctxOn).ok).toBe(false)
		expect(#s.data.slimes).toBe(4)
	end)
	it("skips a slime being carried away", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { slime("a", 1), slime("b", 1), slime("c", 1) })
		ServerFixtures.join(world, 2)
		ServerFixtures.unlock(s)
		Carry.grab(world, 2, "c", 1, T0)
		expect(call(world, 1, "AutoMerge", { 1 }, ctxOn).message).toBe("nothing to merge")
		expect(#s.data.slimes).toBe(3)
	end)
	it("KeepSlime marks and clears an owned slime only, and Merge3 then refuses it", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { slime("a", 2), slime("b", 2), slime("c", 2) })
		ServerFixtures.join(world, 2)
		expect(call(world, 1, "KeepSlime", { "a", true }, ctxOn).ok).toBe(true)
		expect(s.data.slimes[1].keep).toBe(true)
		expect(call(world, 2, "KeepSlime", { "a", false }, ctxOn).message).toBe("not your slime")
		expect(call(world, 1, "Merge3", { "a", "b", "c" }, ctxOn).message).toBe("slime is kept")
		expect(call(world, 1, "KeepSlime", { "a", false }, ctxOn).ok).toBe(true)
		expect(s.data.slimes[1].keep).toBeNil()
		expect(call(world, 1, "Merge3", { "a", "b", "c" }, ctxOn).ok).toBe(true)
	end)
end)
