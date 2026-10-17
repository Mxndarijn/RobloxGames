--!strict
-- v13 progression (CONTRACT.md §8.8-§8.9): rebirth ranks past 5, upgrades, goals,
-- SlimeDex rewards and the save v3 migration of a v12-shaped save.
local Actions = require("../src/server/Actions")
local Carry = require("../src/server/Carry")
local Collection = require("../src/shared/Collection")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local Fixtures = require("./Fixtures")
local Goals = require("../src/shared/Goals")
local Income = require("../src/server/Income")
local Milestones = require("../src/server/Milestones")
local Perks = require("../src/shared/Perks")
local PlayerData = require("../src/shared/PlayerData")
local Progression = require("../src/shared/Progression")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local Sessions = require("../src/server/Sessions")
local Snapshot = require("../src/server/Snapshot")
local Spawner = require("../src/server/Spawner")
local Steal = require("../src/shared/Steal")
local TestRunner = require("./TestRunner")
local Upgrades = require("../src/shared/Upgrades")

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

describe("Rebirth cost past 5", function()
	it("is unchanged up to 5 rebirths, then doubles", function()
		for r = 0, Config.REBIRTH_LATE_FROM do
			expect(Economy.rebirthCost(r)).toBe(math.floor(Config.REBIRTH_BASE_COST * Config.REBIRTH_COST_GROWTH ^ r))
		end
		local five = Economy.rebirthCost(5)
		expect(Economy.rebirthCost(6)).toBe(five * 2)
		expect(Economy.rebirthCost(10)).toBe(five * 32)
	end)
end)

describe("Perks: rebirth ranks", function()
	it("has ranks past rebirth 5, ascending, each with a perk", function()
		local last = -1
		local past5 = 0
		for i, tier in Config.REBIRTH_TIERS do
			expect(tier.rebirths > last).toBe(true)
			last = tier.rebirths
			if i > 1 then
				expect(#Perks.tierText(tier) > 0).toBe(true)
			end
			if tier.rebirths > 5 then
				past5 += 1
			end
		end
		expect(past5 >= 6).toBe(true)
	end)
	it("takes the best unlocked value of keep / income / lock", function()
		expect(Perks.title(0)).toBe("Slime Rookie")
		expect(Perks.title(6)).toBe("Goo Tycoon")
		expect(Perks.keepCount(5)).toBe(1)
		expect(Perks.keepCount(6)).toBe(2)
		expect(Perks.keepCount(11)).toBe(3)
		expect(Perks.rankIncomeBonus(6)).toBe(0)
		expect(Perks.rankIncomeBonus(7)).toBe(0.1)
		expect(Perks.rankIncomeBonus(12)).toBe(0.25)
		expect(Perks.lockBonus(8)).toBe(30)
		expect(Steal.lockDuration(8, 0)).toBe(Config.LOCK_SECONDS + 8 * Config.LOCK_SECONDS_PER_REBIRTH + 30)
		expect(Perks.nextTier(30)).toBeNil()
		expect((Perks.nextTier(6) :: any).title).toBe("Jelly Magnate")
	end)
	it("keeps the favourite plus the best slimes at Goo Tycoon, never a busy one", function()
		local data = Fixtures.data({
			Fixtures.slime("weak", 1),
			Fixtures.slime("fav", 2),
			Fixtures.slime("best", 6),
			Fixtures.slime("second", 5),
			Fixtures.slime("need", 1, { species = "honey_queen" }),
		}, 1e12)
		data.rebirths = 6
		data.favoriteId = "fav"
		local ok = Progression.rebirth(data, { best = true })
		expect(ok).toBe(true)
		local ids = {}
		for _, s in data.slimes do
			table.insert(ids, s.id)
		end
		expect(ids).toEqual({ "fav", "second" })
		expect(data.favoriteId).toBe("fav")
		expect(data.slimes[2].pad).toBe(2)
	end)
	it("announces a new rank on the rebirth that reaches it", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 1, { species = "rodeo_ram" }) }, 1e12)
		s.data.rebirths = 5
		expect(call(world, 1, "Rebirth").ok).toBe(true)
		local texts = table.concat(ServerFixtures.notifications(world, 1), "\n")
		expect(string.find(texts, "New rank: Goo Tycoon!", 1, true) ~= nil).toBe(true)
	end)
end)

describe("Upgrades (BuyUpgrade)", function()
	it("is locked until its rebirth count, then costs base x growth^level up to max", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, nil, 1e12)
		expect(call(world, 1, "BuyUpgrade", "Luck").message).toBe("locked: reach 5 rebirths")
		expect(call(world, 1, "BuyUpgrade", "Nope").message).toBe("unknown upgrade")
		expect(call(world, 1, "BuyUpgrade", 42).message).toBe("bad argument")
		local before = s.data.cash
		expect(call(world, 1, "BuyUpgrade", "Income").ok).toBe(true)
		expect(s.data.cash).toBe(before - 2000)
		expect(call(world, 1, "BuyUpgrade", "Income").ok).toBe(true)
		expect(before - s.data.cash).toBe(2000 + 5000)
		s.data.upgrades.Income = 10
		expect(call(world, 1, "BuyUpgrade", "Income").message).toBe("already maxed")
		s.data.cash = 0
		s.data.rebirths = 1
		expect(call(world, 1, "BuyUpgrade", "CarrySpeed").message).toBe("not enough cash")
	end)
	it("Income, rank and SlimeDex bonuses multiply plot income", function()
		local data = Fixtures.data({ Fixtures.slime("a", 1) })
		local base = PlayerData.incomePerSecond(data)
		data.upgrades.Income = 2
		expect(PlayerData.incomePerSecond(data)).toBeCloseTo(base * 1.2)
		data.dexRewards = 2 -- +2 % +3 %
		expect(PlayerData.incomePerSecond(data)).toBeCloseTo(base * 1.2 * 1.05)
		data.rebirths = 7
		local mult = Economy.rebirthMultiplier(7)
		expect(PlayerData.incomePerSecond(data)).toBeCloseTo(base * mult * 1.2 * 1.05 * 1.1)
		expect(Perks.incomeMultiplier(data)).toBeCloseTo(mult * 1.2 * 1.05 * 1.1)
	end)
	it("Strong Arms shrinks the carry slowdown, Night Shift extends the offline cap", function()
		local world = ServerFixtures.world()
		local a = ServerFixtures.join(world, 1)
		local b = ServerFixtures.join(world, 2)
		b.data.upgrades.CarrySpeed = 4
		local x, y = Spawner.spawnOne(world, T0), Spawner.spawnOne(world, T0)
		world.wild[x].price, world.wild[y].price = 0, 0
		world.wild[x].slime.tier, world.wild[y].slime.tier = 6, 6
		Carry.grab(world, 1, x, 1, T0)
		Carry.grab(world, 2, y, 1, T0)
		local slowA = 1 - Carry.walkSpeed(a, T0) / Config.BASE_WALK_SPEED
		local slowB = 1 - Carry.walkSpeed(b, T0) / Config.BASE_WALK_SPEED
		expect(slowB).toBeCloseTo(slowA * 0.4, 1e-6)
		local data = Fixtures.data({ Fixtures.slime("s", 1) }, 0)
		data.upgrades.OfflineCap = 2
		data.lastOnline = T0 - 100000
		data.padsUnlocked = Config.PADS_START
		local s = Sessions.join(ServerFixtures.world(), 9, "P9", data, T0)
		assert(s, "session")
		expect(s.data.cash).toBe(math.floor((Config.OFFLINE_CAP_SECONDS + 7200) * Config.OFFLINE_RATE))
		expect(Income.MAX_TICK > 0).toBe(true)
	end)
	it("Lucky Charm can raise a deposited wild slime one rarity", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		s.data.slimes = {}
		s.data.upgrades.Luck = 5
		world.rng = {
			float = function()
				return 0
			end,
		} :: any
		local id = "lucky"
		world.wild[id] = {
			slime = Fixtures.slime(id, 2),
			price = 0,
			spawnedAt = T0,
			expiresAt = T0 + 60,
			angle = 0,
			radius = 40,
		}
		expect((Carry.grab(world, 1, id, 1, T0))).toBe(true)
		expect((Carry.deposit(world, 1))).toBe(true)
		expect(s.data.slimes[1].tier).toBe(3)
		expect(s.data.stats.caught).toBe(1)
		local texts = table.concat(ServerFixtures.notifications(world, 1), "\n")
		expect(string.find(texts, "Lucky! Your Uncommon slime became Rare!", 1, true) ~= nil).toBe(true)
	end)
	it("lists every upgrade in State order with lock state", function()
		local data = Fixtures.data()
		data.rebirths = 3
		local view = Upgrades.view(data)
		local listed = 0
		for _, def in Config.UPGRADES do
			listed += if def.flag == nil then 1 else 0
		end
		expect(#view).toBe(listed) -- a flag-gated upgrade (RainMagnet) is not listed while its flag is off
		expect(view[1].id).toBe("Income")
		expect(view[3].unlocked).toBe(true)
		expect(view[4].unlocked).toBe(false)
		expect(view[4].price).toBeNil()
	end)
end)

describe("Goals and SlimeDex rewards", function()
	it("pays stages as stats grow, x rebirthMultiplier, and tracks real actions", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("m1", 1), Fixtures.slime("m2", 1) }, 1e6)
		s.lockUntil = 0
		expect(call(world, 1, "Merge", "m1", "m2").ok).toBe(true)
		expect(call(world, 1, "Lock").ok).toBe(true)
		expect(s.data.stats.merges).toBe(1)
		expect(s.data.stats.locks).toBe(1)
		local cash = s.data.cash
		expect(Milestones.check(world, s)).toBe(2)
		expect(s.data.cash).toBe(cash + 200 + 100)
		local texts = table.concat(ServerFixtures.notifications(world, 1), "\n")
		expect(string.find(texts, "Goal complete: Merge 1 time! +$200", 1, true) ~= nil).toBe(true)
		expect(Milestones.check(world, s)).toBe(0)
	end)
	it("pays several reached stages at once (retroactive) and shows the next one", function()
		local data = Fixtures.data()
		data.rebirths = 2
		data.stats.caught = 60
		local paid = Goals.check(data)
		local catch = {}
		for _, p in paid do
			if p.id == "Catch" then
				table.insert(catch, p.reward)
			end
		end
		expect(catch).toEqual({ 100, 1000, 10000 }) -- x2 at 2 rebirths
		local view = Goals.view(data)
		expect(view[1].id).toBe("Catch")
		expect(view[1].stage).toBe(3)
		expect(view[1].target).toBe(200)
		expect(view[1].title).toBe("Catch 200 slimes")
		expect(view[1].done).toBe(false)
		expect(view[1].nextTitle).toBe(Goals.title(Config.GOALS[1], Config.GOALS[1].targets[5]))
	end)
	it("builds the plot DexTierMask from discovered tiers", function()
		local data = Fixtures.data()
		data.dex = {}
		expect(Collection.tierMask(data)).toBe(0)
		data.dex["1:None:Plain:Round"] = true
		data.dex["3:Glow:Spots:Wide"] = true
		data.dex["3:None:Belly:Happy"] = true
		data.dex["6:Gold:Plain:Angry"] = true
		data.dex["junk"] = true
		expect(Collection.tierMask(data)).toBe(0b100101)
	end)
	it("pays SlimeDex milestones with a permanent income bonus", function()
		local data = Fixtures.data()
		for i = 1, 26 do
			data.dex[`k{i}`] = true
		end
		local paid = Collection.check(data)
		expect(#paid).toBe(2)
		expect(data.dexRewards).toBe(2)
		expect(Perks.dexBonus(data)).toBeCloseTo(0.05)
		expect(Collection.view(data)[2].claimed).toBe(true)
		expect(Collection.view(data)[3].claimed).toBe(false)
	end)
	it("puts every v13 field in State", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		local state = Snapshot.build(world, s, T0) :: any
		for _, key in
			{
				"walkSpeed",
				"incomeMultiplier",
				"rebirthTitle",
				"rebirthTiers",
				"upgrades",
				"goals",
				"dexRewards",
				"dexBonus",
				"stats",
				"tutorialStepId",
				"nextRebirthTier",
			}
		do
			expect(state[key] ~= nil).toBe(true)
		end
		expect(#state.rebirthTiers).toBe(#Config.REBIRTH_TIERS)
		expect(state.stats.rebirths).toBe(0)
	end)
end)

describe("SaveData v3 migration (v12-shaped save)", function()
	-- What a v12 live server wrote (SaveData.serialize at SAVE_VERSION 2).
	local function v12Save(): { [string]: any }
		local slimes = {}
		for i = 1, 8 do
			table.insert(slimes, {
				id = `v12-{i}`,
				name = "Globble",
				tier = (i % 6) + 1,
				color = { 200, 60, 120 },
				size = 1.25,
				pattern = "Spots",
				eyes = "Happy",
				mouth = "Fang",
				mutation = if i == 3 then "Gold" else "None",
				pad = i,
			})
		end
		local dex = {}
		for i = 1, 30 do
			table.insert(dex, `{(i % 6) + 1}:None:Plain:{i}`)
		end
		return {
			version = 2,
			cash = 1234567,
			rebirths = 5,
			padsUnlocked = 8,
			slimes = slimes,
			favoriteId = "v12-3",
			lastOnline = T0 - 60,
			daily = { lastDay = 19000, streak = 4 },
			dex = dex,
			totalEarned = 3000000,
			totalStolen = 12,
			lockLevel = 2,
			speedCoil = true,
			tutorialStep = 5, -- v12 step 5 = Steal
		}
	end

	it("keeps every v2 field and adds zeroed v3 progression", function()
		local d = SaveData.deserialize(v12Save())
		expect(d.version).toBe(Config.SAVE_VERSION)
		expect(d.cash).toBe(1234567)
		expect(d.rebirths).toBe(5)
		expect(#d.slimes).toBe(8)
		expect(d.favoriteId).toBe("v12-3")
		expect(d.lockLevel).toBe(2)
		expect(d.speedCoil).toBe(true)
		expect(d.daily.streak).toBe(4)
		expect(PlayerData.dexCount(d)).toBe(36) -- 30 saved keys + 6 from the slimes on the plot
		expect(d.tutorialStep).toBe(6) -- still Steal, now step 6
		expect(next(d.upgrades)).toBeNil()
		expect(next(d.goals)).toBeNil()
		expect(d.dexRewards).toBe(0)
		expect(d.stats.caught).toBe(36) -- max(#slimes, dex count)
		expect(d.stats.merges).toBe(0)
	end)
	it("pays reached goals and dex milestones once on the first join", function()
		local d = SaveData.deserialize(v12Save())
		local world = ServerFixtures.world()
		local cash = d.cash
		local s = Sessions.join(world, 1, "Vet", d, T0)
		assert(s, "session")
		expect(s.data.goals.Catch).toBe(2) -- 1, 10
		expect(s.data.goals.Steal).toBe(2) -- 1, 10
		expect(s.data.goals.Pads).toBe(4)
		expect(s.data.goals.Earn).toBe(2) -- 10K, 1M
		expect(s.data.goals.Rebirth).toBe(2) -- 1, 3
		expect(s.data.dexRewards).toBe(2) -- 10, 25
		expect(s.data.cash > cash).toBe(true)
		local again = SaveData.deserialize(SaveData.serialize(s.data, T0))
		local world2 = ServerFixtures.world()
		local before = again.cash
		local s2 = Sessions.join(world2, 1, "Vet", again, T0)
		assert(s2, "session")
		expect(s2.data.cash).toBe(before) -- nothing paid twice
	end)
	it("round-trips v3 fields and does not remap the tutorial again", function()
		local d = SaveData.deserialize(v12Save())
		d.upgrades.Income = 3
		d.upgrades.Luck = 99
		d.stats.merges = 7
		d.goals.Merge = 1
		d.dexRewards = 2
		local raw = SaveData.serialize(d, T0)
		expect(raw.version).toBe(Config.SAVE_VERSION)
		local back = SaveData.deserialize(raw)
		expect(back.upgrades.Income).toBe(3)
		expect(back.upgrades.Luck).toBe(5) -- clamped to maxLevel
		expect(back.stats.merges).toBe(7)
		expect(back.stats.caught).toBe(36)
		expect(back.goals.Merge).toBe(1)
		expect(back.dexRewards).toBe(2)
		expect(back.tutorialStep).toBe(6)
	end)
	it("survives garbage in the v3 fields", function()
		local raw = v12Save()
		raw.version = 3
		raw.upgrades = { Income = "lots", CarrySpeed = -4, Bogus = 3 }
		raw.stats = "nope"
		raw.goals = { Catch = 1e9, Fake = 2 }
		raw.dexRewards = 1e9
		local d = SaveData.deserialize(raw)
		expect(d.upgrades.Income).toBeNil()
		expect(d.upgrades.CarrySpeed).toBeNil()
		expect((d.upgrades :: any).Bogus).toBeNil()
		expect(d.stats.caught).toBe(0)
		expect(d.goals.Catch).toBe(5)
		expect((d.goals :: any).Fake).toBeNil()
		expect(d.dexRewards).toBe(#Config.DEX_MILESTONES)
	end)
end)
