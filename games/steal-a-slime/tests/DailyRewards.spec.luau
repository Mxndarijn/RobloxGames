--!strict
local Config = require("../src/shared/Config")
local Consumables = require("../src/shared/Consumables")
local DailyRewards = require("../src/shared/DailyRewards")
local Economy = require("../src/shared/Economy")
local EggKind = require("../src/shared/EggKind")
local Fixtures = require("./Fixtures")
local PetSeats = require("../src/shared/PetSeats")
local PlayerData = require("../src/shared/PlayerData")
local Progression = require("../src/shared/Progression")
local Rng = require("../src/shared/Rng")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local DAY = 86400
local T0 = 20000 * DAY + 3600
local ALL_ON = { MysteryEggs = true, Consumables = true, Weather = true }

local function eggs(seed: number?): DailyRewards.EggSource
	local n = 0
	return {
		rng = Rng.new(seed or 1),
		newId = function()
			n += 1
			return `daily{n}`
		end,
	}
end

-- A player whose last claim was yesterday on `streak`, so today's claim is day streak + 1.
local function onStreak(streak: number): PlayerData.Data
	local data = Fixtures.data(nil, 0)
	data.daily = { lastDay = Progression.dayNumber(T0) - 1, streak = streak }
	return data
end

describe("Daily streak table", function()
	it("has 30 days: skins on 7, 14, 21 and 30, cash on the first five", function()
		expect(Config.DAILY_STREAK_CAP).toBe(30)
		expect(Config.DAILY_REWARDS[7].kind).toBe("trail")
		expect(Config.DAILY_REWARDS[14].kind).toBe("trail")
		expect(Config.DAILY_REWARDS[21].kind).toBe("seat")
		expect(Config.DAILY_REWARDS[30].kind).toBe("seat")
		for day = 1, 5 do
			expect(Config.DAILY_REWARDS[day].kind).toBe("cash")
		end
		expect(Config.DAILY_REWARDS[1].amount).toBe(500)
		expect(Config.DAILY_REWARDS[29].amount).toBe(15000)
	end)
	it("every skin day names a daily trail or seat that is never sold", function()
		for _, entry: any in Config.DAILY_REWARDS do
			if entry.kind == "trail" then
				local def: any = nil
				for _, t: any in Config.EXCLUSIVE_SHOP.trails do
					if t.id == entry.id then
						def = t
					end
				end
				expect(def ~= nil and def.daily == true).toBe(true)
				expect(Config.EXCLUSIVE_SHOP.products[`Trail_{entry.id}`]).toBeNil()
				expect(Config.EXCLUSIVE_SHOP.products[`Gift_Trail_{entry.id}`]).toBeNil()
			elseif entry.kind == "seat" then
				local seat = PetSeats.get(entry.id) :: any
				expect(seat.unlock.kind).toBe("daily")
				expect(Config.EXCLUSIVE_SHOP.products[`Seat_{entry.id}`]).toBeNil()
			elseif entry.kind == "consumable" then
				expect(Consumables.def(entry.id) ~= nil).toBe(true)
			end
		end
	end)
end)

describe("Daily streak days", function()
	it("repeat after day 30", function()
		expect(DailyRewards.dayOf(1)).toBe(1)
		expect(DailyRewards.dayOf(30)).toBe(30)
		expect(DailyRewards.dayOf(31)).toBe(1)
		expect(DailyRewards.dayOf(45)).toBe(15)
	end)
	it("an existing long streak carries on where the 30 days put it", function()
		local data = onStreak(44)
		expect(DailyRewards.view(data, T0, ALL_ON).day).toBe(15)
	end)
	it("the track is the day's week, or days 24-30 at the end", function()
		expect(DailyRewards.trackStart(1)).toBe(1)
		expect(DailyRewards.trackStart(7)).toBe(1)
		expect(DailyRewards.trackStart(8)).toBe(8)
		expect(DailyRewards.trackStart(21)).toBe(15)
		expect(DailyRewards.trackStart(22)).toBe(22)
		expect(DailyRewards.trackStart(29)).toBe(24)
		expect(DailyRewards.trackStart(30)).toBe(24)
		local view = DailyRewards.view(onStreak(20), T0, ALL_ON)
		expect(#view.track).toBe(7)
		expect(view.track[7].day).toBe(21)
		expect(view.track[7].skin).toBe(true)
	end)
end)

describe("Daily streak claim", function()
	it("pays cash x the rebirth multiplier and grows the streak", function()
		local data = onStreak(2)
		data.rebirths = 3
		local ok, reward = DailyRewards.claim(data, T0, eggs(), ALL_ON)
		expect(ok).toBe(true)
		local r = reward :: DailyRewards.Reward
		expect(r.day).toBe(3)
		expect(r.kind).toBe("cash")
		expect(data.cash).toBe(math.floor(1000 * Economy.rebirthMultiplier(3)))
		expect(data.daily.streak).toBe(3)
	end)
	it("only once per UTC day; a missed day starts again at day 1", function()
		local data = onStreak(5)
		expect((DailyRewards.claim(data, T0, eggs(), ALL_ON))).toBe(true)
		expect(select(2, DailyRewards.claim(data, T0 + 60, eggs(), ALL_ON))).toBe("already claimed today")
		local _, later = DailyRewards.claim(data, T0 + 3 * DAY, eggs(), ALL_ON)
		expect((later :: any).day).toBe(1)
		expect(data.daily.streak).toBe(1)
	end)
	it("day 7 gives the Mint Fizz trail, and an owner gets a Mystery Egg instead", function()
		local data = onStreak(6)
		local _, reward = DailyRewards.claim(data, T0, eggs(), ALL_ON)
		expect((reward :: any).kind).toBe("trail")
		expect(table.find(data.ownedTrails, "mint_fizz") ~= nil).toBe(true)
		local again = onStreak(36)
		table.insert(again.ownedTrails, "mint_fizz")
		local before = #again.slimes
		local _, swapped = DailyRewards.claim(again, T0, eggs(), ALL_ON)
		expect((swapped :: any).kind).toBe("egg")
		expect(#again.slimes).toBe(before + 1)
	end)
	it("day 21 gives the Golden Cloud seat, which then unlocks and survives a save", function()
		local SaveData = require("../src/shared/SaveData")
		local data = onStreak(20)
		DailyRewards.claim(data, T0, eggs(), ALL_ON)
		local seat = PetSeats.get("golden_cloud") :: any
		expect(PetSeats.unlocked(data, seat)).toBe(true)
		expect(PetSeats.equip(data, "golden_cloud")).toBe(true)
		local loaded = SaveData.deserialize(SaveData.serialize(data, T0))
		expect(loaded.petSeat).toBe("golden_cloud")
		expect(table.find(loaded.ownedSeats, "golden_cloud") ~= nil).toBe(true)
	end)
	it("a daily trail survives a save", function()
		local SaveData = require("../src/shared/SaveData")
		local data = onStreak(13)
		DailyRewards.claim(data, T0, eggs(), ALL_ON)
		local loaded = SaveData.deserialize(SaveData.serialize(data, T0))
		expect(table.find(loaded.ownedTrails, "sunbeam") ~= nil).toBe(true)
	end)
	it("an egg lands on a free pad, incubating, of a kind the player's rebirths may grab", function()
		for seed = 1, 20 do
			local data = onStreak(5)
			DailyRewards.claim(data, T0, eggs(seed), ALL_ON)
			local egg = data.slimes[#data.slimes]
			local kind = EggKind.of(egg) :: any
			expect(kind ~= nil).toBe(true)
			expect(kind.rebirths).toBe(0)
			expect(egg.egg and egg.egg.hatchAt ~= nil).toBe(true)
			expect(egg.pad ~= nil).toBe(true)
		end
	end)
	it("an egg with a full plot, or with eggs off, pays the fallback cash", function()
		local data = onStreak(5)
		data.padsUnlocked = 1
		PlayerData.addSlime(data, Fixtures.slime("a", 1))
		local _, reward = DailyRewards.claim(data, T0, eggs(), ALL_ON)
		expect((reward :: any).kind).toBe("cash")
		expect(data.cash).toBe(Config.DAILY_FALLBACK_CASH)
		local off = DailyRewards.resolve(onStreak(5), 6, { MysteryEggs = false })
		expect(off.kind).toBe("cash")
	end)
	it("gives the boost and the items", function()
		local data = onStreak(8)
		DailyRewards.claim(data, T0, eggs(), ALL_ON)
		expect(data.boostMult).toBe(2)
		expect(data.boostUntil).toBe(T0 + 15 * 60)
		local potions = onStreak(26)
		DailyRewards.claim(potions, T0, eggs(), ALL_ON)
		expect(Consumables.held(potions, "LuckPotion")).toBe(2)
		local totem = onStreak(9)
		DailyRewards.claim(totem, T0, eggs(), ALL_ON)
		expect(Consumables.held(totem, "WeatherTotem")).toBe(1)
	end)
	it("an item whose feature is off, or a full stack, pays the fallback cash", function()
		expect(DailyRewards.resolve(onStreak(9), 10, { Consumables = true, Weather = false }).kind).toBe("cash")
		expect(DailyRewards.resolve(onStreak(12), 13, { Consumables = false }).kind).toBe("cash")
		local full = onStreak(12)
		full.consumables.held.LuckPotion = Config.CONSUMABLE_HELD_MAX
		expect(DailyRewards.resolve(full, 13, ALL_ON).kind).toBe("cash")
	end)
end)

describe("Daily streak view", function()
	it("shows today's reward, the next skin and nothing pending once claimed", function()
		local data = onStreak(2)
		local view = DailyRewards.view(data, T0, ALL_ON)
		expect(view.available).toBe(true)
		expect(view.day).toBe(3)
		expect(view.amount).toBe(1000)
		expect(view.reward.icon).toBe("Cash")
		expect((view.nextSkin :: any).day).toBe(7)
		DailyRewards.claim(data, T0, eggs(), ALL_ON)
		local after = DailyRewards.view(data, T0 + 60, ALL_ON)
		expect(after.available).toBe(false)
		expect(after.day).toBe(3)
	end)
	it("skips owned skins when naming the next one", function()
		local data = onStreak(2)
		table.insert(data.ownedTrails, "mint_fizz")
		expect((DailyRewards.view(data, T0, ALL_ON).nextSkin :: any).day).toBe(14)
	end)
end)
