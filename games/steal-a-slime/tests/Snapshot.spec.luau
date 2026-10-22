--!strict
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local EventSecrets = require("../src/shared/EventSecrets")
local Fixtures = require("./Fixtures")
local MergeRecipes = require("../src/shared/MergeRecipes")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local SlimeRoster = require("../src/shared/SlimeRoster")
local Snapshot = require("../src/server/Snapshot")
local SpeciesDex = require("../src/shared/SpeciesDex")
local Steal = require("../src/shared/Steal")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

local STATE_KEYS = {
	"serverTime",
	"featuredSecret",
	"plotIndex",
	"cash",
	"incomePerSec",
	"rebirths",
	"rebirthMultiplier",
	"rebirthCost",
	"canRebirth",
	"padsUnlocked",
	"padsMax",
	"slimes",
	"lockUntil",
	"lockCost",
	"lockDuration",
	"rain",
	"dex",
	"daily",
	"shop",
	-- v13 (CONTRACT.md §8.2): always sent
	"walkSpeed",
	"incomeMultiplier",
	"rebirthTitle",
	"rebirthTiers",
	"upgrades",
	"goals",
	"dexRewards",
	"dexBonus",
	"stats",
	"boss",
	"modifier",
	"egg",
}

describe("Snapshot.build", function()
	it("has every Types.State field with the right values", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2, { species = "bumble" }) }, 77)
		s.data.padsUnlocked = 4
		local state = Snapshot.build(world, s, T0)
		for _, key in STATE_KEYS do
			expect((state :: any)[key] ~= nil).toBeTruthy()
		end
		expect(state.serverTime).toBe(T0)
		expect(state.plotIndex).toBe(1)
		expect(state.cash).toBe(77)
		expect(state.incomePerSec).toBe(3)
		expect(state.padsMax).toBe(Config.PADS_MAX)
		expect(state.nextPadCost).toBe(Economy.padCost(4))
		expect(state.lockUntil).toBe(T0 + Config.JOIN_LOCK_SECONDS)
		expect(state.lockDuration).toBe(Steal.lockDuration(0))
		expect(state.dex.total).toBe(SpeciesDex.TOTAL)
		expect(state.dex.found).toBe(1)
		expect(state.rain.active).toBe(false)
		expect(state.rain.nextAt).toBe(T0 + Config.RAIN_FIRST_AT)
		expect(state.daily.available).toBe(true)
		expect(state.carrying).toBeNil()
		expect(state.boss.active).toBe(false)
		expect(state.boss.phase).toBeNil()
		expect(state.boss.endsAt).toBeNil()
		expect(state.boss.nextAt).toBe(T0 + Config.BOSS.FIRST_AT)
		expect(state.boss.badges).toBe(0)
		expect(state.bossBadges).toEqual({})
		expect(state.slimes[1].income).toBe(3)
		expect(state.slimes[1].stolenBy).toBeNil()
	end)
	it("shows stolenBy and zero income for a slime being carried away", function()
		local world = ServerFixtures.world()
		local victim = ServerFixtures.join(world, 1, { Fixtures.slime("gem", 4) })
		local thief = ServerFixtures.join(world, 2)
		ServerFixtures.unlock(victim)
		Carry.grab(world, 2, "gem", 1, T0)
		local vs = Snapshot.build(world, victim, T0)
		expect(vs.slimes[1].stolenBy).toBe(2)
		expect(vs.slimes[1].income).toBe(0)
		expect(vs.incomePerSec).toBe(0)
		local ts = Snapshot.build(world, thief, T0)
		local carrying = ts.carrying
		assert(carrying, "carrying")
		expect(carrying.kind).toBe("stolen")
		expect(carrying.ownerUserId).toBe(1)
		expect(carrying.walkSpeed < Config.BASE_WALK_SPEED).toBeTruthy()
	end)
	it("has no nextPadCost when every pad is unlocked", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		expect(Snapshot.build(world, s, T0).nextPadCost).toBeNil()
	end)
end)

describe("Snapshot State.hotbar", function()
	it("is nil until set, then the saved 9 keys", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		expect(Snapshot.build(world, s, T0).hotbar).toBeNil()
		s.data.hotbar = { "tool:Bat", "", "", "", "", "", "", "", "pvp:KnockGlove1" }
		local state = Snapshot.build(world, s, T0)
		expect(state.hotbar).toEqual(s.data.hotbar)
		expect(state.hotbar ~= s.data.hotbar).toBe(true) -- a copy, not the live save table
	end)
	it("an old save without a hotbar survives serialize -> JSON -> deserialize with State.hotbar nil", function()
		local serde = require("@lune/serde")
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		for _, old in { { version = 6, cash = 500, rebirths = 1 }, SaveData.serialize(Fixtures.data(nil, 0), T0) } do
			expect((old :: any).hotbar).toBeNil()
			local loaded = SaveData.deserialize(serde.decode("json", serde.encode("json", old)))
			local raw = SaveData.serialize(loaded, T0)
			expect((raw :: any).hotbar).toBeNil()
			s.data = SaveData.deserialize(serde.decode("json", serde.encode("json", raw)))
			expect(Snapshot.build(world, s, T0).hotbar).toBeNil()
		end
	end)
end)

describe("Snapshot State.dex", function()
	local function entry(state: any, id: string): any
		for _, e in state.dex.entries do
			if e.id == id then
				return e
			end
		end
		error(`no entry {id}`)
	end
	it("lists the 50 entries and the event Secrets with counts", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, {
			Fixtures.slime("a", 1, { species = "gummy" }),
			Fixtures.slime("c", 1, { species = "gummy" }),
		})
		local state = Snapshot.build(world, s, T0) :: any
		expect(#state.dex.entries).toBe(SpeciesDex.TOTAL + #SpeciesDex.BONUS)
		expect(state.dex.found).toBe(1)
		expect(state.dex.total).toBe(SpeciesDex.TOTAL)
		expect(state.dex.bonusTotal).toBe(#SpeciesDex.BONUS)
		local gummy = entry(state, "gummy")
		expect(gummy.found).toBe(true)
		expect(gummy.name).toBe("Gummy")
		local moo = entry(state, "moo")
		expect(moo.found).toBe(false)
		expect(moo.name).toBeNil()
		expect(entry(state, "goozilla").hint).toBe(SpeciesDex.BOSS_HINT)
		expect(entry(state, "glitch").kind).toBe("event")
	end)
	it("a hybrid card carries its real recipe hint and fills the slots of found ingredients", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 1, { species = "gummy" }) })
		local state = Snapshot.build(world, s, T0) :: any
		local recipe = MergeRecipes.recipeFor("soda") :: MergeRecipes.Recipe
		local soda = entry(state, "soda")
		expect(soda.hint).toBe(recipe.hint)
		expect(#soda.ingredients).toBe(3)
		for i, input in recipe.inputs do
			expect(soda.ingredients[i]).toBe(if input == "gummy" then "gummy" else "")
		end
		expect(soda.name).toBeNil()
	end)
	it("names this week's featured event Secret with its week; the others stay ???", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		local state = Snapshot.build(world, s, T0) :: any
		local featured = EventSecrets.featured(T0)
		local e = entry(state, featured.id)
		expect(e.found).toBe(false)
		expect(e.name).toBe(featured.name)
		expect(e.hint).toBe(`Featured Secret: week of {SpeciesDex.weekLabel(featured.startsAt)}`)
		for _, other in SpeciesDex.BONUS do
			if other.id ~= featured.id then
				expect(entry(state, other.id).hint).toBe("???")
			end
		end
	end)
	it("State.dex totals match the roster: 32 spawn + 15 hybrids + 6 bosses", function()
		expect(#SlimeRoster.ofKind("spawn") + #SlimeRoster.ofKind("hybrid") + #SlimeRoster.ofKind("boss")).toBe(
			SpeciesDex.TOTAL
		)
		expect(SpeciesDex.TOTAL).toBe(53)
		expect(#SpeciesDex.BONUS).toBe(#SlimeRoster.ofKind("event"))
	end)
end)

describe("Snapshot push coalescing", function()
	it("pushes only when dirty and at most once per STATE_MIN_INTERVAL", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		expect(Snapshot.due(s, T0)).toBe(true)
		Snapshot.pushed(s, T0)
		expect(Snapshot.due(s, T0 + 1)).toBe(false)
		s.dirty = true
		expect(Snapshot.due(s, T0 + Config.STATE_MIN_INTERVAL / 2)).toBe(false)
		expect(Snapshot.due(s, T0 + Config.STATE_MIN_INTERVAL)).toBe(true)
	end)
end)
