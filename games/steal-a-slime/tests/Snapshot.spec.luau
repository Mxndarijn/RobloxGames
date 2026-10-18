--!strict
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local Fixtures = require("./Fixtures")
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
		expect(state.dex.stamps).toBe(1)
		expect(state.rain.active).toBe(false)
		expect(state.rain.nextAt).toBe(T0 + Config.RAIN_FIRST_AT)
		expect(state.daily.available).toBe(true)
		expect(state.carrying).toBeNil()
		expect(state.boss.active).toBe(false)
		expect(state.boss.phase).toBeNil()
		expect(state.boss.endsAt).toBeNil()
		expect(state.boss.nextAt).toBe(T0 + Config.BOSS.FIRST_AT)
		expect(state.boss.trophies).toBe(0)
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
		expect(carrying.escapeAt).toBe(T0 + Config.RARITIES[4].escapeTime)
		expect(carrying.walkSpeed < Config.BASE_WALK_SPEED).toBeTruthy()
	end)
	it("has no nextPadCost when every pad is unlocked", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		expect(Snapshot.build(world, s, T0).nextPadCost).toBeNil()
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
	it("lists the 50 entries and the event Secrets with counts, stamps and gold stamps", function()
		local world = ServerFixtures.world()
		local glow = Fixtures.slime("a", 1, { species = "gummy", mutation = "Glow", mutations = { "Glow" } })
		local solar = Fixtures.slime("b", 1, { species = "gummy", mutation = "Solar", mutations = { "Solar" } })
		local s = ServerFixtures.join(world, 1, { glow, solar, Fixtures.slime("c", 1, { species = "gummy" }) })
		local state = Snapshot.build(world, s, T0) :: any
		expect(#state.dex.entries).toBe(SpeciesDex.TOTAL + #SpeciesDex.BONUS)
		expect(state.dex.found).toBe(1)
		expect(state.dex.total).toBe(SpeciesDex.TOTAL)
		expect(state.dex.stamps).toBe(2) -- gummy:None, gummy:Glow
		expect(state.dex.stampTotal).toBe(SpeciesDex.STAMP_TOTAL)
		expect(state.dex.gold).toBe(1) -- gummy:Solar
		expect(state.dex.bonusTotal).toBe(#SpeciesDex.BONUS)
		local gummy = entry(state, "gummy")
		expect(gummy.found).toBe(true)
		expect(gummy.name).toBe("Gummy")
		expect(table.concat(gummy.stamps, ",")).toBe("None,Glow")
		expect(table.concat(gummy.gold, ",")).toBe("Solar")
		local moo = entry(state, "moo")
		expect(moo.found).toBe(false)
		expect(moo.name).toBeNil()
		expect(entry(state, "goozilla").hint).toBe(SpeciesDex.BOSS_HINT)
		expect(entry(state, "glitch").kind).toBe("event")
	end)
	it("State.dex totals match the roster: 32 spawn + 15 hybrids + 3 bosses, 47 x 8 stamps", function()
		expect(#SlimeRoster.ofKind("spawn") + #SlimeRoster.ofKind("hybrid") + #SlimeRoster.ofKind("boss")).toBe(
			SpeciesDex.TOTAL
		)
		expect(SpeciesDex.TOTAL).toBe(50)
		expect(SpeciesDex.STAMP_TOTAL).toBe(376)
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
