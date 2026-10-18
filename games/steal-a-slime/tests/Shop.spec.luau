--!strict
-- Shop upgrades, tutorial progress, Effects events, State.shop / tutorialStep / daily.day, saves.
local Actions = require("../src/server/Actions")
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local Leaderboard = require("../src/server/Leaderboard")
local PlayerData = require("../src/shared/PlayerData")
local Progression = require("../src/shared/Progression")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local Shop = require("../src/shared/Shop")
local Snapshot = require("../src/server/Snapshot")
local Spawner = require("../src/server/Spawner")
local Steal = require("../src/shared/Steal")
local TestRunner = require("./TestRunner")
local TutorialProgress = require("../src/shared/TutorialProgress")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

local ctx: Actions.Context = {
	distanceBetween = function()
		return 2
	end,
	positionOf = function()
		return nil
	end,
}

local function call(world: any, userId: number, action: string, ...: any)
	local session = world.sessions[userId]
	if session then
		session.limiter = {}
	end
	return Actions.handle(world, userId, action, table.pack(...), T0 + 100, ctx)
end

local function effects(world: any): { string }
	local kinds = {}
	for _, event in world.outbox do
		if event.type == "Effect" then
			table.insert(kinds, event.effect)
		end
	end
	return kinds
end

describe("Shop", function()
	it("prices lock upgrades per level and stops at the max", function()
		for level = 0, Config.LOCK_UPGRADE_MAX - 1 do
			expect(Shop.lockUpgradeCost(level)).toBe(Config.LOCK_UPGRADE_COSTS[level + 1])
		end
		expect(Shop.lockUpgradeCost(Config.LOCK_UPGRADE_MAX)).toBeNil()
		expect(#Config.LOCK_UPGRADE_COSTS).toBe(Config.LOCK_UPGRADE_MAX)
	end)
	it("buys lock upgrades with cash and refuses when broke or maxed", function()
		local data = PlayerData.new()
		data.cash = 0
		expect(select(2, Shop.buyLockUpgrade(data))).toBe("not enough cash")
		data.cash = 1e9
		for _ = 1, Config.LOCK_UPGRADE_MAX do
			expect((Shop.buyLockUpgrade(data))).toBe(true)
		end
		expect(data.lockLevel).toBe(Config.LOCK_UPGRADE_MAX)
		expect(select(2, Shop.buyLockUpgrade(data))).toBe("locks are already maxed")
	end)
	it("lock upgrades lengthen every bought lock", function()
		expect(Steal.lockDuration(2, 3)).toBe(Steal.lockDuration(2) + 3 * Config.LOCK_UPGRADE_SECONDS)
		expect(Steal.lockDuration(0, 99)).toBe(Steal.lockDuration(0, Config.LOCK_UPGRADE_MAX))
		local data = PlayerData.new()
		data.cash = 1e6
		data.lockLevel = 2
		local ok, lockUntil = Steal.buyLock(data, 0, 500, 0)
		expect(ok).toBe(true)
		expect(lockUntil).toBe(500 + Config.LOCK_SECONDS + 2 * Config.LOCK_UPGRADE_SECONDS)
	end)
	it("sells the Speed Coil once and speeds up walking", function()
		local data = PlayerData.new()
		data.cash = Config.SPEED_COIL_PRICE - 1
		expect(select(2, Shop.buySpeedCoil(data))).toBe("not enough cash")
		expect(Shop.walkSpeed(data)).toBe(Config.BASE_WALK_SPEED)
		data.cash = Config.SPEED_COIL_PRICE
		expect((Shop.buySpeedCoil(data))).toBe(true)
		expect(data.cash).toBe(0)
		expect(Shop.walkSpeed(data)).toBe(Config.SPEED_COIL_WALK_SPEED)
		expect(select(2, Shop.buySpeedCoil(data))).toBe("you already own the Speed Coil")
	end)
	it("view matches the UI's ShopCatalog item ids", function()
		local data = PlayerData.new()
		local view = Shop.view(data)
		expect(view.LockUpgrade).toEqual({ price = Config.LOCK_UPGRADE_COSTS[1], level = 0, maxLevel = 5 })
		expect(view.SpeedCoil).toEqual({ price = Config.SPEED_COIL_PRICE, owned = false })
		data.speedCoil = true
		data.lockLevel = Config.LOCK_UPGRADE_MAX
		view = Shop.view(data)
		expect(view.SpeedCoil.price).toBeNil()
		expect(view.LockUpgrade.price).toBeNil()
	end)
	it("Request actions charge, notify and survive rebirth", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 1, { species = "bumble" }) }, 1e6)
		expect(call(world, 1, "BuySpeedCoil").ok).toBe(true)
		expect(call(world, 1, "BuyLockUpgrade").ok).toBe(true)
		expect(call(world, 1, "BuySpeedCoil").message).toBe("you already own the Speed Coil")
		expect(s.data.cash).toBe(1e6 - Config.SPEED_COIL_PRICE - Config.LOCK_UPGRADE_COSTS[1])
		expect(call(world, 1, "Rebirth").ok).toBe(true)
		expect(s.data.speedCoil).toBe(true)
		expect(s.data.lockLevel).toBe(1)
	end)
end)

describe("TutorialProgress", function()
	it("walks the six steps in order and finishes", function()
		local data = { tutorialStep = 1 }
		for i, name in TutorialProgress.STEPS do
			expect(TutorialProgress.current(data)).toBe(i)
			local changed, finished = TutorialProgress.complete(data, name)
			expect(changed).toBe(true)
			expect(finished).toBe(i == #TutorialProgress.STEPS)
		end
		expect(TutorialProgress.current(data)).toBeNil()
		expect((TutorialProgress.complete(data, "Grab"))).toBe(false)
	end)
	it("does not skip ahead on a later action and ignores earlier ones (CONTRACT.md §9.2)", function()
		local data = { tutorialStep = 1 }
		expect((TutorialProgress.complete(data, "Merge"))).toBe(false)
		expect(data.tutorialStep).toBe(1)
		data.tutorialStep = 5
		expect((TutorialProgress.complete(data, "Grab"))).toBe(false)
		expect(data.tutorialStep).toBe(5)
		expect((TutorialProgress.complete(data, "Nope"))).toBe(false)
	end)
	it("skips steps the saved data shows are already done", function()
		-- Bought a pad and merged during Grab: Deposit and Lock still show, BuyPad / Merge don't.
		local data = {
			tutorialStep = 1,
			stats = { caught = 0, merges = 1, locks = 0 },
			padsUnlocked = Config.PADS_START + 1,
			totalStolen = 0,
			rebirths = 0,
		}
		expect((TutorialProgress.complete(data, "BuyPad"))).toBe(false)
		expect((TutorialProgress.complete(data, "Grab"))).toBe(true)
		expect(TutorialProgress.currentId(data)).toBe("Deposit")
		data.stats.caught = 1
		TutorialProgress.complete(data, "Deposit")
		expect(TutorialProgress.currentId(data)).toBe("Lock")
		data.stats.locks = 1
		TutorialProgress.complete(data, "Lock")
		expect(TutorialProgress.currentId(data)).toBe("Steal")
		-- A rebirth while at Steal (solo server) finishes Steal and Rebirth.
		data.rebirths = 1
		local changed, finished = TutorialProgress.complete(data, "Rebirth")
		expect(changed).toBe(true)
		expect(finished).toBe(true)
		expect(data.tutorialStep).toBe(0)
	end)
	it("has UI overlay copy for every step", function()
		local UiTutorial = require("../src/ui/Tutorial")
		for _, name in TutorialProgress.STEPS do
			expect(UiTutorial.find(name)).toBeTruthy()
		end
	end)
	it("advances from real gameplay: grab, deposit, lock, buy pad, merge, steal, rebirth", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, nil, 1e7)
		s.data.padsUnlocked = Config.PADS_START -- not done yet, or BuyPad is skipped (§9.2)
		expect(s.data.tutorialStep).toBe(1)
		local id = Spawner.spawnOne(world, T0)
		world.wild[id].price = 0
		expect((Carry.grab(world, 1, id, 1, T0))).toBe(true)
		expect(s.data.tutorialStep).toBe(2)
		expect((Carry.deposit(world, 1))).toBe(true)
		expect(s.data.tutorialStep).toBe(3)
		s.lockUntil = 0
		expect(call(world, 1, "Lock").ok).toBe(true)
		expect(s.data.tutorialStep).toBe(4)
		expect(TutorialProgress.currentId(s.data)).toBe("BuyPad")
		expect(call(world, 1, "BuyPad").ok).toBe(true)
		expect(s.data.tutorialStep).toBe(5)
		PlayerData.addSlime(s.data, Fixtures.slime("m1", 1))
		PlayerData.addSlime(s.data, Fixtures.slime("m2", 1))
		expect(call(world, 1, "Merge", "m1", "m2").ok).toBe(true)
		expect(s.data.tutorialStep).toBe(6)
		local victim = ServerFixtures.join(world, 2, { Fixtures.slime("gem", 2) })
		ServerFixtures.unlock(victim)
		expect((Carry.grab(world, 1, "gem", 1, T0 + 1))).toBe(true)
		expect(s.data.tutorialStep).toBe(7)
		Carry.release(world, 1, T0 + 2, nil, "drop")
		world.escaping = {}
		PlayerData.addSlime(s.data, Fixtures.slime("need", 2, { species = "bumble" }))
		expect(call(world, 1, "Rebirth").ok).toBe(true)
		expect(s.data.tutorialStep).toBe(0)
		local texts = table.concat(ServerFixtures.notifications(world, 1), "\n")
		expect(string.find(texts, "Tutorial complete", 1, true) ~= nil).toBeTruthy()
	end)
end)

describe("Effects events (CONTRACT.md §5.4)", function()
	it("queues Collect on deposit, Steal on a steal, Merge and Rebirth", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(
			world,
			1,
			{ Fixtures.slime("a", 1), Fixtures.slime("b", 1), Fixtures.slime("need", 2, { species = "bumble" }) },
			1e7
		)
		local victim = ServerFixtures.join(world, 2, { Fixtures.slime("gem", 2) })
		ServerFixtures.unlock(victim)
		expect((Carry.grab(world, 1, "gem", 1, T0))).toBe(true)
		expect((Carry.deposit(world, 1))).toBe(true)
		expect(call(world, 1, "Merge", "a", "b").ok).toBe(true)
		expect(call(world, 1, "Rebirth").ok).toBe(true)
		expect(effects(world)).toEqual({ "Steal", "Collect", "Merge", "Rebirth" })
		for _, event in world.outbox do
			if event.type == "Effect" and event.effect == "Steal" then
				expect(event.slimeId).toBe("gem")
			elseif event.type == "Effect" and event.effect == "Merge" then
				expect(event.plotIndex).toBe(s.plotIndex)
			end
		end
	end)
end)

describe("State additions", function()
	it("has shop, tutorialStep and daily.day", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, nil, 0)
		local state = Snapshot.build(world, s, T0)
		expect(state.shop.SpeedCoil.owned).toBe(false)
		expect(state.tutorialStep).toBe(1)
		expect(state.daily.day).toBe(1)
		expect(state.daily.amount).toBe(Progression.dailyAmount(1, 0))
		s.data.lockLevel = 2
		expect(Snapshot.build(world, s, T0).lockDuration).toBe(Steal.lockDuration(0, 2))
		-- claimed yesterday on day 3 -> today's claim pays day 4
		local today = Progression.dayNumber(T0)
		s.data.daily = { lastDay = today - 1, streak = 3 }
		expect(Snapshot.build(world, s, T0).daily.day).toBe(4)
		s.data.daily = { lastDay = today, streak = 9 }
		state = Snapshot.build(world, s, T0)
		expect(state.daily.available).toBe(false)
		expect(state.daily.day).toBe(Config.DAILY_STREAK_CAP)
		s.data.tutorialStep = 0
		expect(Snapshot.build(world, s, T0).tutorialStep).toBeNil()
	end)
end)

describe("SaveData (shop / tutorial fields)", function()
	it("round-trips lockLevel, speedCoil and tutorialStep", function()
		local data = PlayerData.new()
		data.lockLevel = 3
		data.speedCoil = true
		data.tutorialStep = 4
		local back = SaveData.deserialize(SaveData.serialize(data, 1))
		expect(back.lockLevel).toBe(3)
		expect(back.speedCoil).toBe(true)
		expect(back.tutorialStep).toBe(4)
	end)
	it("defaults old saves: tutorial only for empty profiles, garbage clamped", function()
		local empty = SaveData.deserialize({ version = 2, cash = 10 })
		expect(empty.tutorialStep).toBe(1)
		expect(empty.lockLevel).toBe(0)
		expect(empty.speedCoil).toBe(false)
		local veteran = SaveData.deserialize({ version = 2, rebirths = 2 })
		expect(veteran.tutorialStep).toBe(0)
		local bad = SaveData.deserialize({ version = 2, lockLevel = 99, speedCoil = "yes", tutorialStep = -4 })
		expect(bad.lockLevel).toBe(Config.LOCK_UPGRADE_MAX)
		expect(bad.speedCoil).toBe(false)
		expect(bad.tutorialStep).toBe(0)
	end)
end)

describe("Leaderboard.boardRows", function()
	it("formats ranks and cash, and shows a placeholder when empty", function()
		local rows = Leaderboard.boardRows({
			stat = "TotalEarned",
			entries = { { rank = 1, userId = 1, name = "Ann", value = 1500 } },
		})
		expect(rows).toEqual({ { rank = "#1", name = "Ann", value = "$1.5K" } })
		expect(Leaderboard.boardRows(nil)[1].name).toBe(Leaderboard.EMPTY_TEXT)
	end)
end)
