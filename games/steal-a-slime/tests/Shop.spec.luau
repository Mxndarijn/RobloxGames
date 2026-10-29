--!strict
-- The Speed Coil, tutorial progress, Effects events, State.shop / tutorialStep / daily.day, saves.
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
local TutorialService = require("../src/server/TutorialService")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local FIRST = Config.REBIRTH_SLIMES[1][1] -- the species rebirth 1 uses up

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

-- Brews `ids` in the vat through the real requests and collects at once.
local function brew(world: any, ids: { string }): boolean
	for _, id in ids do
		if not call(world, 1, "VatAdd", id).ok then
			return false
		end
	end
	if not call(world, 1, "VatStart").ok then
		return false
	end
	world.sessions[1].data.vat.endsAt = 0 -- the brew is done
	return call(world, 1, "VatCollect").ok
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
	it("sells the Speed Coil once; it speeds up walking only while held", function()
		local data = PlayerData.new()
		data.cash = Config.SPEED_COIL_PRICE - 1
		expect(select(2, Shop.buySpeedCoil(data))).toBe("not enough cash")
		expect(Shop.walkSpeed(data)).toBe(Config.BASE_WALK_SPEED)
		expect(Shop.walkSpeed(data, true)).toBe(Config.BASE_WALK_SPEED) -- holding nothing you own
		data.cash = Config.SPEED_COIL_PRICE
		expect((Shop.buySpeedCoil(data))).toBe(true)
		expect(data.cash).toBe(0)
		expect(Shop.walkSpeed(data)).toBe(Config.BASE_WALK_SPEED) -- owned, in the Backpack
		expect(Shop.walkSpeed(data, true)).toBe(Config.SPEED_COIL_WALK_SPEED) -- held
		expect(select(2, Shop.buySpeedCoil(data))).toBe("you already own the Speed Coil")
	end)
	it("view matches the UI's ShopCatalog item ids", function()
		local data = PlayerData.new()
		local view = Shop.view(data)
		expect(view).toEqual({ SpeedCoil = { price = Config.SPEED_COIL_PRICE, owned = false } })
		data.speedCoil = true
		view = Shop.view(data)
		expect(view.SpeedCoil.price).toBeNil()
		expect(view.SpeedCoil.owned).toBe(true)
	end)
	it("Request actions charge, notify and survive rebirth", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 1, { species = FIRST }) }, 1e6)
		expect(call(world, 1, "BuySpeedCoil").ok).toBe(true)
		expect(call(world, 1, "BuySpeedCoil").message).toBe("you already own the Speed Coil")
		expect(call(world, 1, "BuyLockUpgrade").message).toBe("unknown action")
		expect(s.data.cash).toBe(1e6 - Config.SPEED_COIL_PRICE)
		expect(call(world, 1, "Rebirth").ok).toBe(true)
		expect(s.data.speedCoil).toBe(true)
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
		-- Bought a pad, merged and bought an upgrade during Grab: Deposit, Lock, Leaderboard and Guide still show.
		local data = {
			tutorialStep = 1,
			stats = { caught = 0, merges = 1, locks = 0 },
			padsUnlocked = Config.PADS_START + 1,
			upgrades = { [Config.UPGRADES[1].id] = 1 },
		}
		expect((TutorialProgress.complete(data, "BuyPad"))).toBe(false)
		expect((TutorialProgress.complete(data, "Grab"))).toBe(true)
		expect(TutorialProgress.currentId(data)).toBe("Deposit")
		data.stats.caught = 1
		TutorialProgress.complete(data, "Deposit")
		expect(TutorialProgress.currentId(data)).toBe("Lock")
		data.stats.locks = 1
		TutorialProgress.complete(data, "Lock")
		expect(TutorialProgress.currentId(data)).toBe("Leaderboard")
		TutorialProgress.complete(data, "Leaderboard")
		expect(TutorialProgress.currentId(data)).toBe("Guide")
		-- BuyPad, Merge and BuyItem are already done, so the Guide ends it.
		local changed, finished = TutorialProgress.complete(data, "Guide")
		expect(changed).toBe(true)
		expect(finished).toBe(true)
		expect(data.tutorialStep).toBe(0)
	end)
	it("has UI card copy for every step", function()
		local UiTutorial = require("../src/ui/Tutorial")
		for _, name in TutorialProgress.STEPS do
			expect(UiTutorial.find(name)).toBeTruthy()
		end
	end)
	it("advances from real gameplay and pays nothing for it", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, nil, 1e7)
		s.data.padsUnlocked = Config.PADS_START -- not done yet, or BuyPad is skipped
		expect(s.data.tutorialStep).toBe(1)
		local id = Spawner.spawnOne(world, T0)
		world.wild[id].price = 0
		expect((Carry.grab(world, 1, id, 1, T0))).toBe(true)
		expect(TutorialProgress.currentId(s.data)).toBe("Deposit")
		expect((Carry.deposit(world, 1))).toBe(true)
		expect(TutorialProgress.currentId(s.data)).toBe("Lock")
		s.lockUntil = 0
		expect(call(world, 1, "Lock").ok).toBe(true)
		expect(TutorialProgress.currentId(s.data)).toBe("Leaderboard")
		TutorialService.tick(world, {
			pose = function()
				return { X = 5, Y = 0, Z = 5 }, nil
			end,
			propPosition = function()
				return { X = 0, Y = 3, Z = 0 }
			end,
		})
		expect(TutorialProgress.currentId(s.data)).toBe("Guide")
		TutorialService.talkedToGuide(world, 1)
		expect(TutorialProgress.currentId(s.data)).toBe("BuyPad")
		expect(call(world, 1, "BuyPad").ok).toBe(true)
		expect(TutorialProgress.currentId(s.data)).toBe("Merge")
		PlayerData.addSlime(s.data, Fixtures.slime("m1", 1))
		PlayerData.addSlime(s.data, Fixtures.slime("m2", 1))
		PlayerData.addSlime(s.data, Fixtures.slime("m3", 1))
		expect(brew(world, { "m1", "m2", "m3" })).toBe(true)
		expect(TutorialProgress.currentId(s.data)).toBe("BuyItem")
		local cash = s.data.cash
		expect(call(world, 1, "BuyUpgrade", Config.UPGRADES[1].id).ok).toBe(true)
		expect(s.data.tutorialStep).toBe(0)
		expect(s.data.cash < cash).toBe(true) -- paid for the upgrade, got nothing back
		local texts = table.concat(ServerFixtures.notifications(world, 1), "\n")
		expect(string.find(texts, "Tutorial complete", 1, true) ~= nil).toBeTruthy()
	end)
end)

describe("Effects events (CONTRACT.md §5.4)", function()
	it("queues Collect on deposit, Steal on a steal, Merge and Rebirth", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, {
			Fixtures.slime("a", 1),
			Fixtures.slime("b", 1),
			Fixtures.slime("c", 1),
			Fixtures.slime("need", 2, { species = FIRST }),
		}, 1e7)
		local victim = ServerFixtures.join(world, 2, { Fixtures.slime("gem", 2) })
		ServerFixtures.unlock(victim)
		expect((Carry.grab(world, 1, "gem", 1, T0))).toBe(true)
		expect((Carry.deposit(world, 1))).toBe(true)
		expect(brew(world, { "a", "b", "c" })).toBe(true)
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
		s.data.rebirths = 2
		expect(Snapshot.build(world, s, T0).lockDuration).toBe(Steal.lockDuration(2))
		s.data.rebirths = 0
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
	it("round-trips speedCoil and tutorialStep", function()
		local data = PlayerData.new()
		data.speedCoil = true
		data.tutorialStep = 4
		local back = SaveData.deserialize(SaveData.serialize(data, 1))
		expect(back.speedCoil).toBe(true)
		expect(back.tutorialStep).toBe(4)
	end)
	it("defaults old saves: tutorial only for empty profiles, garbage clamped", function()
		local empty = SaveData.deserialize({ version = 2, cash = 10 })
		expect(empty.tutorialStep).toBe(1)
		expect(empty.speedCoil).toBe(false)
		local veteran = SaveData.deserialize({ version = 2, rebirths = 2 })
		expect(veteran.tutorialStep).toBe(0)
		local bad = SaveData.deserialize({ version = 2, speedCoil = "yes", tutorialStep = -4 })
		expect(bad.speedCoil).toBe(false)
		expect(bad.tutorialStep).toBe(0)
	end)
	it("drops an old save's lockLevel: not read, not written back", function()
		local old = SaveData.deserialize({ version = 2, cash = 10, lockLevel = 3 })
		expect((old :: any).lockLevel).toBeNil()
		expect(SaveData.serialize(old, 1).lockLevel).toBeNil()
		expect((PlayerData.new() :: any).lockLevel).toBeNil()
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
