--!strict
-- "Open locked door" (src/server/LockBreak.luau, contract/exclusive-shop.md §11): only the buyer passes one locked
-- base's door, only for Config.EXCLUSIVE_SHOP.lockBreak.seconds; breather locks and bases that already let the buyer in
-- can't be broken; the lock itself stays up for everyone else.
local Actions = require("../src/server/Actions")
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local GameLoop = require("../src/server/GameLoop")
local LockBreak = require("../src/server/LockBreak")
local Purchases = require("../src/server/Purchases")
local Scene = require("../src/server/Scene")
local ServerFixtures = require("./ServerFixtures")
local SlimeGuard = require("../src/server/SlimeGuard")
local StealService = require("../src/server/StealService")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local SECONDS = Config.EXCLUSIVE_SHOP.lockBreak.seconds
local SHOP = { features = { ExclusiveShop = true, FriendsInBase = true } }

local function ctx(features: { [string]: boolean }?): Actions.Context
	return {
		distanceBetween = function()
			return 2
		end,
		positionOf = function()
			return "pos"
		end,
		features = features or SHOP.features,
	}
end

-- Owner 1 has "gem" and "opal" on a base locked from T0 for 200 s; 2 is the buyer, 3 another thief.
local function setup()
	local world = ServerFixtures.world()
	local owner = ServerFixtures.join(world, 1, { Fixtures.slime("gem", 4), Fixtures.slime("opal", 3) })
	local buyer = ServerFixtures.join(world, 2)
	local other = ServerFixtures.join(world, 3)
	for _, s in { owner, buyer, other } do
		s.friendIds = {}
	end
	owner.lockStartedAt = T0
	owner.lockUntil = T0 + 200
	return world, owner, buyer, other
end

-- The buyer aims at the owner's base and the LockBreak receipt arrives `after` seconds later.
local function buy(world: any, buyer: any, plotIndex: number, at: number)
	assert(LockBreak.aim(world, buyer, plotIndex, at, SHOP.features))
	assert(Purchases.grant(world, buyer, "LockBreak", at + 1, SHOP))
end

describe("AimLockBreak", function()
	it("refuses an open base, your own base, a missing base and a running pass", function()
		local world, owner, buyer, _ = setup()
		expect(select(2, LockBreak.aim(world, buyer, buyer.plotIndex, T0 + 1, SHOP.features))).toBe(
			"that's your own base"
		)
		expect(select(2, LockBreak.aim(world, buyer, 99, T0 + 1, SHOP.features))).toBe("that is not a base")
		expect(select(2, LockBreak.aim(world, buyer, 1.5, T0 + 1, SHOP.features))).toBe("that is not a base")
		owner.lockUntil = 0
		expect(select(2, LockBreak.aim(world, buyer, owner.plotIndex, T0 + 1, SHOP.features))).toBe(
			"that base isn't locked"
		)
		owner.lockUntil = T0 + 200
		buy(world, buyer, owner.plotIndex, T0 + 1)
		expect(select(2, LockBreak.aim(world, buyer, owner.plotIndex, T0 + 3, SHOP.features))).toBe(
			"your lock break is still running"
		)
	end)

	it("refuses a base in its breather lock after a steal", function()
		local world, owner, buyer, _ = setup()
		ServerFixtures.unlock(owner)
		SlimeGuard.breather(world, owner, T0 + 1)
		local ok, reason = LockBreak.aim(world, buyer, owner.plotIndex, T0 + 2, SHOP.features)
		expect(ok).toBe(false)
		expect(reason).toBe("that base just lost a slime: its short lock can't be opened")
		-- A breather that ended: the next normal lock can be broken again.
		expect((StealService.buyLock(world, owner, T0 + 2 + Config.SLIME_GUARD.BREATHER_SECONDS))).toBe(true)
		expect((LockBreak.aim(world, buyer, owner.plotIndex, T0 + 3 + Config.SLIME_GUARD.BREATHER_SECONDS, nil))).toBe(
			true
		)
	end)

	it("refuses a base whose owner already lets the buyer in as a friend", function()
		local world, owner, buyer, _ = setup()
		owner.friendIds = { [2] = true }
		owner.data.allowFriends = true
		local ok, reason = LockBreak.aim(world, buyer, owner.plotIndex, T0 + 1, SHOP.features)
		expect(ok).toBe(false)
		expect(reason).toBe("you can already walk in: they let their friends in")
	end)

	it("goes through Request AimLockBreak, gated by the shop flag", function()
		local world, owner, buyer, _ = setup()
		local off = Actions.handle(
			world,
			2,
			"AimLockBreak",
			table.pack(owner.plotIndex),
			T0 + 1,
			ctx({
				ExclusiveShop = false,
			})
		)
		expect(off.message).toBe("the Exclusive Shop is off")
		expect(Actions.handle(world, 2, "AimLockBreak", table.pack("x"), T0 + 2, ctx()).message).toBe("bad argument")
		expect(Actions.handle(world, 2, "AimLockBreak", table.pack(owner.plotIndex), T0 + 3, ctx()).ok).toBe(true)
		expect(buyer.lockBreakAim and buyer.lockBreakAim.plot).toBe(owner.plotIndex)
	end)
end)

describe("a lock break", function()
	it("lets only the buyer through that one door, and the lock stays up for everyone else", function()
		local world, owner, buyer, other = setup()
		local before = owner.lockUntil
		buy(world, buyer, owner.plotIndex, T0 + 10)
		expect(owner.lockUntil).toBe(before)
		expect(StealService.isLocked(owner, T0 + 12)).toBe(true)
		expect(LockBreak.passes(world, 2, owner.plotIndex, T0 + 12)).toBe(true)
		expect(LockBreak.passes(world, 3, owner.plotIndex, T0 + 12)).toBe(false)
		expect(LockBreak.passes(world, 2, other.plotIndex, T0 + 12)).toBe(false)
		-- The stopper lets the buyer through, nobody else.
		expect(SlimeGuard.stopperPasses(world, SHOP.features, T0 + 12)[owner.plotIndex]).toEqual({ 2 })
		expect(SlimeGuard.stopperPasses(world, SHOP.features, T0 + 12)[other.plotIndex]).toBeNil()
		-- Steal prompts on for the buyer only.
		expect(Scene.describe(world, T0 + 12)["gem"].guestsOnly).toBe(",2,")
		-- The buyer may steal there; the other thief still can't.
		expect((Carry.grab(world, 3, "opal", 1, T0 + 12))).toBe(false)
		expect((Carry.grab(world, 2, "gem", 1, T0 + 12))).toBe(true)
	end)

	it("ends after its seconds, cleanly, and the next steal is refused again", function()
		local world, owner, buyer, _ = setup()
		buy(world, buyer, owner.plotIndex, T0 + 10)
		local ends = T0 + 11 + SECONDS
		expect((buyer.lockBreak :: any).untilTime).toBe(ends)
		expect(LockBreak.passes(world, 2, owner.plotIndex, ends - 0.1)).toBe(true)
		expect(LockBreak.passes(world, 2, owner.plotIndex, ends)).toBe(false)
		expect(SlimeGuard.stopperPasses(world, SHOP.features, ends)[owner.plotIndex]).toBeNil()
		ServerFixtures.clearEvents(world)
		buyer.dirty = false
		GameLoop.step(world, ends)
		expect(buyer.lockBreak).toBeNil()
		expect(buyer.dirty).toBe(true)
		expect(table.find(ServerFixtures.notifications(world, 2), "Your lock break ended") ~= nil).toBe(true)
		expect(Purchases.view(buyer, ends, world).lockBreak).toBeNil()
		expect((StealService.steal(world, buyer, "gem", 1, ends + 1))).toBe(false)
	end)

	it("can't be stacked: a second purchase while one runs is a credit and the end time stays", function()
		local world, owner, buyer, _ = setup()
		buy(world, buyer, owner.plotIndex, T0 + 10)
		local ends = (buyer.lockBreak :: any).untilTime
		expect((LockBreak.aim(world, buyer, owner.plotIndex, T0 + 20, SHOP.features))).toBe(false)
		expect(Purchases.grant(world, buyer, "LockBreak", T0 + 20, SHOP)).toBe(true)
		expect((buyer.lockBreak :: any).untilTime).toBe(ends)
		expect(buyer.data.lockBreakCredits).toBe(1)
		-- Spending the credit is refused the same way while the pass runs.
		local res = Actions.handle(world, 2, "UseCredit", table.pack("lockBreak", owner.plotIndex), T0 + 21, ctx())
		expect(res.message).toBe("your lock break is still running")
		expect(buyer.data.lockBreakCredits).toBe(1)
	end)

	it("tells the owner who broke in, and the buyer how long it lasts", function()
		local world, owner, buyer, _ = setup()
		buy(world, buyer, owner.plotIndex, T0 + 10)
		expect(ServerFixtures.notifications(world, 1)).toEqual({ "P2 broke into your base!" })
		expect(ServerFixtures.notifications(world, 2)[1]).toBe(`P1's door is open for you for {SECONDS}s!`)
		local view = Purchases.view(buyer, T0 + 12, world)
		expect(view.lockBreak).toEqual({ plot = owner.plotIndex, untilTime = T0 + 11 + SECONDS })
	end)

	it("never makes the buyer an intruder, and lets them out after it ends", function()
		local world, owner, buyer, _ = setup()
		world.guardMode = "watch"
		buy(world, buyer, owner.plotIndex, T0 + 10)
		expect(SlimeGuard.trackPlot(world, buyer, owner.plotIndex, T0 + 15)).toBeNil()
		local ends = T0 + 11 + SECONDS
		expect(SlimeGuard.trackPlot(world, buyer, owner.plotIndex, ends + 1)).toBeNil()
		expect(SlimeGuard.stopperPasses(world, SHOP.features, ends + 1)[owner.plotIndex]).toEqual({ 2 })
		expect((Carry.grab(world, 2, "gem", 1, ends + 1))).toBe(false)
		-- Out: the door is shut for them again, and walking back in is intrusion.
		expect(SlimeGuard.trackPlot(world, buyer, nil, ends + 2)).toBeNil()
		expect(SlimeGuard.stopperPasses(world, SHOP.features, ends + 2)[owner.plotIndex]).toBeNil()
		expect(SlimeGuard.trackPlot(world, buyer, owner.plotIndex, ends + 3)).toBe(owner.plotIndex)
	end)

	it("pauses while the base is in a breather lock after a steal", function()
		local world, owner, buyer, _ = setup()
		buy(world, buyer, owner.plotIndex, T0 + 10)
		ServerFixtures.unlock(owner)
		SlimeGuard.breather(world, owner, T0 + 20)
		expect(LockBreak.passes(world, 2, owner.plotIndex, T0 + 21)).toBe(false)
		expect((StealService.steal(world, buyer, "gem", 1, T0 + 21))).toBe(false)
		local after = T0 + 20 + Config.SLIME_GUARD.BREATHER_SECONDS
		expect(LockBreak.passes(world, 2, owner.plotIndex, after)).toBe(true)
	end)

	it("ends when its plot changes owner", function()
		local world, owner, buyer, _ = setup()
		buy(world, buyer, owner.plotIndex, T0 + 10)
		world.plots[owner.plotIndex] = 3
		expect(LockBreak.pass(world, buyer, T0 + 12)).toBeNil()
		expect(LockBreak.passes(world, 2, owner.plotIndex, T0 + 12)).toBe(false)
	end)
end)

describe("LockBreak receipts and credits", function()
	it("becomes a credit without an aim, with a stale aim, or when the aimed lock ended", function()
		local world, owner, buyer, _ = setup()
		expect(Purchases.grant(world, buyer, "LockBreak", T0 + 1, SHOP)).toBe(true)
		expect(buyer.data.lockBreakCredits).toBe(1)
		assert(LockBreak.aim(world, buyer, owner.plotIndex, T0 + 2, SHOP.features))
		Purchases.grant(world, buyer, "LockBreak", T0 + 3 + Config.EXCLUSIVE_SHOP.lockBreak.aimSeconds, SHOP)
		expect(buyer.data.lockBreakCredits).toBe(2)
		assert(LockBreak.aim(world, buyer, owner.plotIndex, T0 + 4, SHOP.features))
		owner.lockUntil = T0 + 5
		Purchases.grant(world, buyer, "LockBreak", T0 + 6, SHOP)
		expect(buyer.data.lockBreakCredits).toBe(3)
		expect(buyer.lockBreak).toBeNil()
		expect(buyer.lockBreakAim).toBeNil()
	end)

	it("a credit opens a locked base with UseCredit and is spent only when it opens", function()
		local world, owner, buyer, _ = setup()
		buyer.data.lockBreakCredits = 1
		local none = Actions.handle(world, 2, "UseCredit", table.pack("lockBreak", buyer.plotIndex), T0 + 1, ctx())
		expect(none.message).toBe("that's your own base")
		expect(buyer.data.lockBreakCredits).toBe(1)
		local res = Actions.handle(world, 2, "UseCredit", table.pack("lockBreak", owner.plotIndex), T0 + 2, ctx())
		expect(res.ok).toBe(true)
		expect(buyer.data.lockBreakCredits).toBe(0)
		expect(LockBreak.passes(world, 2, owner.plotIndex, T0 + 3)).toBe(true)
		local empty = Actions.handle(world, 2, "UseCredit", table.pack("lockBreak", owner.plotIndex), T0 + 4, ctx())
		expect(empty.message).toBe("no lock break credits")
	end)

	it("is refused, changing nothing, with the credits full (Roblox asks again later)", function()
		local world, _, buyer, _ = setup()
		buyer.data.lockBreakCredits = Config.EXCLUSIVE_SHOP.creditMax
		local ok, reason = Purchases.grant(world, buyer, "LockBreak", T0 + 1, SHOP)
		expect(ok).toBe(false)
		expect(reason).toBe("too many lock break credits")
		expect(buyer.data.lockBreakCredits).toBe(Config.EXCLUSIVE_SHOP.creditMax)
	end)
end)
