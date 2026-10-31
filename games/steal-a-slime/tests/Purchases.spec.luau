--!strict
-- Exclusive Shop grants, credits, Game Passes and the roll-first vat / egg seeds (contract/exclusive-shop.md §2-§5).
local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local ExclusiveRotation = require("../src/shared/ExclusiveRotation")
local Fixtures = require("./Fixtures")
local Income = require("../src/server/Income")
local MergeVat = require("../src/server/MergeVat")
local MysteryEgg = require("../src/shared/MysteryEgg")
local Perks = require("../src/shared/Perks")
local PetSeats = require("../src/shared/PetSeats")
local PlayerData = require("../src/shared/PlayerData")
local Purchases = require("../src/server/Purchases")
local Rng = require("../src/shared/Rng")
local ServerFixtures = require("./ServerFixtures")
local Snapshot = require("../src/server/Snapshot")
local TestRunner = require("./TestRunner")
local VatState = require("../src/shared/VatState")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local ON = { features = {} }

local function egg(id: string, kind: string, hatchAt: number?, tier: number?): any
	return Fixtures.slime(id, tier or 4, { species = "lop", egg = { kind = kind, hatchAt = hatchAt } })
end

-- A session with three Commons brewing in the vat.
local function brewing(world: any, userId: number): any
	local session = ServerFixtures.join(
		world,
		userId,
		{ Fixtures.slime("a", 1), Fixtures.slime("b", 1), Fixtures.slime("c", 1) },
		0
	)
	for _, id in { "a", "b", "c" } do
		assert(MergeVat.add(world, session, id))
	end
	assert(MergeVat.start(world, session, T0))
	return session
end

local function ctx(features: { [string]: boolean }): Actions.Context
	return {
		distanceBetween = function()
			return 2
		end,
		positionOf = function()
			return "pos"
		end,
		features = features,
	}
end

describe("Purchases.grant", function()
	it("refuses an unknown product, changing nothing", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		expect(select(2, Purchases.grant(world, s, "Nope", T0, ON))).toBe("unknown product")
		expect(s.data.ownedSeats).toEqual({})
	end)
	it("a seat joins the owned seats once, unlocks it and drops its product key from the view", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		local ufo = PetSeats.get("ufo") :: any
		expect(PetSeats.unlocked(s.data, ufo)).toBe(false)
		local function row(): any
			for _, r in PetSeats.view(s.data) do
				if r.id == "ufo" then
					return r
				end
			end
			return nil
		end
		expect(row().productKey).toBe("Seat_ufo")
		expect(Purchases.grant(world, s, "Seat_ufo", T0, ON)).toBe(true)
		expect(Purchases.grant(world, s, "Seat_ufo", T0, ON)).toBe(true)
		expect(s.data.ownedSeats).toEqual({ "ufo" })
		expect(PetSeats.unlocked(s.data, ufo)).toBe(true)
		expect(row().productKey).toBeNil()
		expect(PetSeats.equip(s.data, "ufo")).toBe(true)
		expect(PetSeats.current(s.data)).toBe("ufo")
	end)
	it("free seats never carry a product key", function()
		for _, r in PetSeats.view(PlayerData.new()) do
			if r.kind ~= "exclusive" then
				expect(r.productKey).toBeNil()
			end
		end
	end)
	it("the Starter Bundle gives its seats and a capped income boost and is marked claimed", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		local def = (Purchases.product("StarterBundle") :: any).grant
		expect(Purchases.grant(world, s, "StarterBundle", T0, ON)).toBe(true)
		expect(s.data.ownedSeats).toEqual({ "leaf" })
		expect(s.data.starterBundle).toBe(true)
		expect(s.data.boostMult).toBe(def.boostMult)
		expect(s.data.boostUntil).toBe(T0 + def.boostSeconds)
	end)
	it("Finish now ends a running brew without changing its roll", function()
		local world = ServerFixtures.world()
		local s = brewing(world, 1)
		local seed = (s.data.vat :: any).seed
		expect(type(seed)).toBe("number")
		expect(VatState.isReady(s.data, T0 + 1)).toBe(false)
		expect(Purchases.grant(world, s, "FinishBrew_1", T0 + 1, ON)).toBe(true)
		expect(VatState.isReady(s.data, T0 + 1)).toBe(true)
		expect((s.data.vat :: any).seed).toBe(seed)
		expect(Snapshot.build(world, s, T0 + 1).vat.endsAt).toBe(T0 + 1)
		expect(s.data.credits.brew).toBe(0)
	end)
	it("Finish now with no brew running saves a brew credit, up to the cap", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		expect(Purchases.grant(world, s, "FinishBrew_2", T0, ON)).toBe(true)
		expect(s.data.credits.brew).toBe(1)
		s.data.credits.brew = Config.EXCLUSIVE_SHOP.creditMax
		Purchases.grant(world, s, "FinishBrew_2", T0, ON)
		expect(s.data.credits.brew).toBe(Config.EXCLUSIVE_SHOP.creditMax)
	end)
	it("Hatch now readies the incubating egg of that kind closest to ready, else saves a hatch credit", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, {
			egg("g1", "golden", T0 + 900),
			egg("g2", "golden", T0 + 300),
			egg("s1", "speckled", T0 + 100),
		}, 0)
		expect(Purchases.grant(world, s, "HatchNow_golden", T0, ON)).toBe(true)
		expect((s.data.slimes[2].egg :: any).hatchAt).toBe(T0)
		expect((s.data.slimes[1].egg :: any).hatchAt).toBe(T0 + 900)
		expect((s.data.slimes[3].egg :: any).hatchAt).toBe(T0 + 100)
		expect(Purchases.grant(world, s, "HatchNow_cosmic", T0, ON)).toBe(true)
		expect(s.data.credits.hatch).toBe(1)
	end)
	it("Hatch now readies the egg the player aimed at (AimHatch) when it fits the paid kind", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, {
			egg("g1", "golden", T0 + 900),
			egg("g2", "golden", T0 + 300),
			egg("s1", "speckled", T0 + 100),
		}, 0)
		expect(Purchases.aimHatch(world, s, "g1", T0)).toBe(true)
		Purchases.grant(world, s, "HatchNow_golden", T0, ON)
		expect((s.data.slimes[1].egg :: any).hatchAt).toBe(T0)
		expect((s.data.slimes[2].egg :: any).hatchAt).toBe(T0 + 300)
		-- An aim at another kind's egg is ignored: a golden receipt never readies the speckled egg.
		expect(Purchases.aimHatch(world, s, "s1", T0)).toBe(true)
		Purchases.grant(world, s, "HatchNow_golden", T0, ON)
		expect((s.data.slimes[3].egg :: any).hatchAt).toBe(T0 + 100)
		expect((s.data.slimes[2].egg :: any).hatchAt).toBe(T0)
		expect(s.hatchTarget).toBeNil()
	end)
	it("AimHatch refuses anything that is not your incubating pad egg", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { egg("g1", "golden", T0 + 900), egg("done", "golden", T0 - 1) }, 0)
		expect((Purchases.aimHatch(world, s, "nope", T0))).toBe(false)
		expect((Purchases.aimHatch(world, s, "done", T0))).toBe(false)
		expect(s.hatchTarget).toBeNil()
	end)
	it("Double it pays the last welcome-back payout once; with none it grants nothing", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, nil, 0)
		expect(Purchases.grant(world, s, "DoubleOffline", T0, ON)).toBe(true)
		expect(s.data.cash).toBe(0)
		s.data.offlineDouble = { cash = 700, at = T0, used = false }
		Purchases.grant(world, s, "DoubleOffline", T0, ON)
		Purchases.grant(world, s, "DoubleOffline", T0, ON)
		expect(s.data.cash).toBe(700)
		expect((s.data.offlineDouble :: any).used).toBe(true)
	end)
	it("the server Luck Potion extends the server-wide potion and tells everyone who gave it", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		expect(Purchases.grant(world, s, "ServerLuckPotion", T0, ON)).toBe(true)
		expect(world.potionUntil).toBe(T0 + Config.LUCK_POTION_SECONDS)
		local texts = ServerFixtures.notifications(world, nil)
		expect(table.find(texts, "P1 gave the server a Luck Potion!") ~= nil).toBe(true)
	end)
end)

describe("UseCredit", function()
	it("is refused for bad arguments", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1)
		local bad = Actions.handle(world, 1, "UseCredit", table.pack(5), T0, ctx({}))
		expect(bad.message).toBe("bad argument")
		local kind = Actions.handle(world, 1, "UseCredit", table.pack("gold"), T0 + 1, ctx({}))
		expect(kind.message).toBe("unknown credit")
	end)
	it("spends a brew credit on the running brew, and keeps it when there is none", function()
		local world = ServerFixtures.world()
		local s = brewing(world, 1)
		s.data.credits.brew = 1
		local res = Actions.handle(world, 1, "UseCredit", table.pack("brew"), T0 + 5, ctx({}))
		expect(res.ok).toBe(true)
		expect(s.data.credits.brew).toBe(0)
		expect(VatState.isReady(s.data, T0 + 5)).toBe(true)
		local none = Actions.handle(world, 1, "UseCredit", table.pack("brew"), T0 + 6, ctx({}))
		expect(none.message).toBe("no brew credits")
	end)
	it("spends a hatch credit on the named egg", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { egg("g1", "golden", T0 + 900), egg("g2", "golden", T0 + 300) }, 0)
		s.data.credits.hatch = 2
		local res = Actions.handle(world, 1, "UseCredit", table.pack("hatch", "g1"), T0, ctx({}))
		expect(res.ok).toBe(true)
		expect((s.data.slimes[1].egg :: any).hatchAt).toBe(T0)
		expect(s.data.credits.hatch).toBe(1)
		local again = Actions.handle(world, 1, "UseCredit", table.pack("hatch", "g1"), T0 + 1, ctx({}))
		expect(again.message).toBe("no egg to hatch")
		expect(s.data.credits.hatch).toBe(1)
	end)
end)

describe("Game Passes", function()
	it("Income2x is one more income factor; free players are unchanged", function()
		local data = Fixtures.data({ Fixtures.slime("a", 2) }, 0)
		local base = Perks.bonusMultiplier(data)
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 2) }, 0)
		expect(Perks.bonusMultiplier(s.data)).toBe(base)
		Purchases.applyPasses(s, { Income2x = true })
		expect(Perks.bonusMultiplier(s.data)).toBe(base * Config.EXCLUSIVE_SHOP.passes.Income2x.incomeMult)
		Purchases.applyPasses(s, {})
		expect(Perks.bonusMultiplier(s.data)).toBe(base)
	end)
	it("Offline2x pays the pass rate on join and tops up a payout made before the pass check", function()
		local data = Fixtures.data({ Fixtures.slime("a", 3) }, 0)
		data.lastOnline = T0 - 3600
		local perSec = PlayerData.incomePerSecond(data)
		local cap = Perks.offlineCap(data)
		local basePay = Economy.offlineIncome(perSec, T0 - 3600, T0, cap)
		expect(Income.offlineRate(data)).toBe(Config.OFFLINE_RATE)
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 3) }, 0)
		s.data.lastOnline = T0 - 3600
		s.data.cash = 0
		Income.applyOffline(world, s, T0, { CashPads = false }) -- the payout in cash (CashPads.spec covers the pads)
		expect(s.data.cash).toBe(basePay)
		expect((s.data.offlineDouble :: any).cash).toBe(basePay)
		local extra = Purchases.applyPasses(s, { Offline2x = true })
		local full =
			Economy.offlineIncome(perSec, T0 - 3600, T0, cap, Config.EXCLUSIVE_SHOP.passes.Offline2x.offlineRate)
		expect(extra).toBe(math.floor(basePay * 0.5 / Config.OFFLINE_RATE) - basePay)
		expect(math.abs(s.data.cash - full) <= 1).toBe(true)
		expect((s.data.offlineDouble :: any).cash).toBe(s.data.cash)
		expect(Purchases.applyPasses(s, { Offline2x = true })).toBe(0)
	end)
end)

describe("State.exclusiveShop", function()
	it("shows owned seats, passes, the bundle, credits, the payout and this week's featured seats", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		Purchases.grant(world, s, "Seat_ufo", T0, ON)
		Purchases.applyPasses(s, { Income2x = true })
		s.data.credits = { brew = 2, hatch = 0, rain = 1, boss = 0, totem = 0, snack = 0 }
		s.data.offlineDouble = { cash = 50, at = T0, used = false }
		local view = Purchases.view(s, T0)
		expect(view.owned).toEqual({ ufo = true })
		expect(view.passes.Income2x).toBe(true)
		expect(view.passes.Offline2x).toBe(false)
		expect(view.passes.VIP).toBe(false)
		expect(view.starterClaimed).toBe(false)
		expect(view.credits).toEqual({ brew = 2, hatch = 0, rain = 1, boss = 0, totem = 0, snack = 0 })
		expect(view.offlineDouble).toEqual({ cash = 50, available = true })
		expect(view.paidRandomAllowed).toBe(false)
		expect(view.featured).toEqual(ExclusiveRotation.featured(ExclusiveRotation.week(T0)))
		s.paidRandomAllowed = true
		expect(Purchases.view(s, T0).paidRandomAllowed).toBe(true)
	end)
end)

describe("roll first", function()
	local function load(): PlayerData.Data
		local data = Fixtures.data({ Fixtures.slime("a", 1), Fixtures.slime("b", 1), Fixtures.slime("c", 1) }, 0)
		for _, id in { "a", "b", "c" } do
			assert(VatState.add(data, id))
		end
		return data
	end
	local function look(child: any): string
		return `{child.tier}|{child.species}|{child.name}|{child.pattern}|{child.color[1]},{child.color[2]}`
	end
	it("a vat with the same seed brews the same slime, finished early or not, whatever Rng Collect gets", function()
		local one, two = load(), load()
		assert(VatState.start(one, T0, nil, 12345))
		assert(VatState.start(two, T0, nil, 12345))
		assert(VatState.finishNow(two, T0 + 1))
		local ok1, a = VatState.collect(one, T0 + 3600 * 24, Rng.new(1), "x")
		local ok2, b = VatState.collect(two, T0 + 1, Rng.new(999), "x")
		expect(ok1 and ok2).toBe(true)
		expect(look(a)).toBe(look(b))
	end)
	it("a vat saved without a seed still rolls on the caller's Rng", function()
		local one, two = load(), load()
		assert(VatState.start(one, T0))
		assert(VatState.start(two, T0))
		local _, a = VatState.collect(one, T0 + 3600 * 24, Rng.new(5), "x")
		local _, b = VatState.collect(two, T0 + 3600 * 24, Rng.new(5), "x")
		expect(look(a)).toBe(look(b))
	end)
	it("an egg's hatch roll is fixed by its seed, so a Hatch now skip changes nothing", function()
		local function hatch(rngSeed: number, at: number): any
			local data = Fixtures.data({ egg("e", "golden", nil, 4) }, 0)
			data.eggLuck = { golden = 11 } -- a full lucky meter: the hatch rerolls at the top tier
			local slime = data.slimes[1]
			assert(MysteryEgg.startIncubating(slime, T0, 777))
			if at < T0 + 1e6 then
				(slime.egg :: any).hatchAt = at
			end
			local ok, out = MysteryEgg.hatchEgg(data, "e", at, Rng.new(rngSeed))
			assert(ok, "hatch failed")
			return out
		end
		local waited, skipped = hatch(1, T0 + 2e6), hatch(42, T0 + 5)
		expect(look(waited)).toBe(look(skipped))
	end)
	it("the server stores a seed when an egg starts incubating and when a brew starts", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { egg("e", "speckled", nil, 1) }, 0)
		local Server = require("../src/server/MysteryEgg")
		Server.step(world, 1, T0)
		local stored = s.data.slimes[1].egg :: any
		expect(type(stored.hatchAt)).toBe("number")
		expect(type(stored.seed)).toBe("number")
		local b = brewing(world, 2)
		expect(type((b.data.vat :: any).seed)).toBe("number")
		expect(VatState.cancel(b.data)).toBe(true)
		expect((b.data.vat :: any).seed).toBeNil()
	end)
end)

describe("Game Pass effects", function()
	it("VIP and x2 income multiply; Fast Brew halves brews; Warm Nest and Lucky Charm+ set their fields", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		local brewBefore = Perks.brewFactor(s.data)
		local luckBefore = Perks.luckChance(s.data)
		Purchases.applyPasses(
			s,
			{ VIP = true, Income2x = true, FastBrew = true, WarmNest = true, LuckyCharmPlus = true }
		)
		expect(math.abs((s.data.passIncomeMult :: number) - 2.2) < 1e-9).toBe(true)
		expect(Perks.brewFactor(s.data)).toBe(brewBefore * 0.5)
		expect(s.data.passWarmNest).toBe(true)
		expect(math.abs(Perks.luckChance(s.data) - (luckBefore + 0.05)) < 1e-9).toBe(true)
		expect(Perks.baseLuckChance(s.data)).toBe(luckBefore)
		Purchases.applyPasses(s, {})
		expect(s.data.passIncomeMult).toBeNil()
		expect(s.data.passBrewFactor).toBeNil()
		expect(s.data.passWarmNest).toBeNil()
		expect(s.data.passLuckBonus).toBeNil()
		expect(Perks.brewFactor(s.data)).toBe(brewBefore)
	end)
	it("Warm Nest warms pad eggs while the owner is away from home", function()
		local function hatchAtAfter(warm: boolean): number
			local world = ServerFixtures.world()
			local pad = egg("e", "speckled", T0 + 600, 1)
			local s = ServerFixtures.join(world, 1, { pad }, 0)
			s.home = false
			if warm then
				Purchases.applyPasses(s, { WarmNest = true })
			end
			require("../src/server/MysteryEgg").step(world, 10, T0 + 10)
			return pad.egg.hatchAt
		end
		expect(hatchAtAfter(true) < hatchAtAfter(false)).toBe(true)
	end)
end)

describe("Slime Club and VIP perks", function()
	it("the Club gives one Finish now and one Hatch now credit per UTC day", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		Purchases.applySubscriptions(world, s, { SlimeClub = true }, T0)
		expect(s.data.credits.brew).toBe(1)
		expect(s.data.credits.hatch).toBe(1)
		Purchases.stepDaily(world, s, T0 + 60)
		expect(s.data.credits.brew).toBe(1) -- once a day
		Purchases.stepDaily(world, s, T0 + 86400)
		expect(s.data.credits.brew).toBe(2)
		Purchases.applySubscriptions(world, s, { SlimeClub = false }, T0 + 2 * 86400)
		expect(s.data.credits.brew).toBe(2) -- not a member any more
		expect(Purchases.member(s)).toBeNil()
	end)
	it("hides the member tag while the player turned Show my VIP tag off, and keeps the perks", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		Purchases.applyPasses(s, { VIP = true })
		s.data.settings.showMemberTag = false
		expect(Purchases.member(s)).toBeNil()
		expect(Purchases.hasEffect(s, "vip")).toBe(true)
		s.data.settings.showMemberTag = true
		expect(Purchases.member(s)).toBe("vip")
	end)
	it("a VIP gives the server a Luck Potion once a day, never where paid random items are restricted", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		expect(select(2, Purchases.claimPerk(world, s, "vipPotion", T0))).toBe("that is a VIP perk")
		Purchases.applyPasses(s, { VIP = true })
		expect(Purchases.member(s)).toBe("vip")
		s.paidRandomAllowed = false
		expect(select(2, Purchases.claimPerk(world, s, "vipPotion", T0))).toBe("not available in your region")
		s.paidRandomAllowed = true
		expect(Purchases.vipPotionReady(s, T0)).toBe(true)
		expect((Purchases.claimPerk(world, s, "vipPotion", T0))).toBe(true)
		expect((world.potionUntil or 0) > T0).toBe(true)
		expect((Purchases.claimPerk(world, s, "vipPotion", T0 + 60))).toBe(false)
		expect(Purchases.vipPotionReady(s, T0 + 86400)).toBe(true)
	end)
end)

describe("Thief Radar", function()
	it("lists who is in the owner's base and tells an away owner once per visit", function()
		local ThiefRadar = require("../src/server/ThiefRadar")
		local world = ServerFixtures.world()
		local owner = ServerFixtures.join(world, 1)
		local visitor = ServerFixtures.join(world, 2)
		Purchases.applyPasses(owner, { ThiefRadar = true })
		owner.home = false
		world.guard[2] = { plot = { index = owner.plotIndex, since = T0 } } :: any
		ThiefRadar.step(world, nil)
		expect(owner.radar).toEqual({ 2 })
		local function told(): number
			local n = 0
			for _, text in ServerFixtures.notifications(world, 1) do
				if string.find(text, visitor.name, 1, true) then
					n += 1
				end
			end
			return n
		end
		expect(told()).toBe(1)
		ThiefRadar.step(world, nil)
		expect(told()).toBe(1) -- once per visit
		world.guard[2] = { plot = nil } :: any
		ThiefRadar.step(world, nil)
		expect(owner.radar).toEqual({})
		Purchases.applyPasses(owner, {})
		ThiefRadar.step(world, nil)
		expect(owner.radar).toBeNil()
	end)
end)

describe("Server boosts and small comforts", function()
	it("a paid Slime Rain starts now, once per server cooldown; refused it becomes a credit", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		expect(Purchases.rainRefusal(world, T0)).toBeNil()
		expect((Purchases.grant(world, s, "SlimeRain", T0, ON))).toBe(true)
		expect(world.paidRainAt).toBe(T0)
		expect(world.rainForcedUntil ~= nil).toBe(true)
		local later = T0 + Config.RAIN_DURATION + 1
		expect(Purchases.rainRefusal(world, later) ~= nil).toBe(true) -- the cooldown
		Purchases.grant(world, s, "SlimeRain", later, ON)
		expect(s.data.credits.rain).toBe(1)
		local free = T0 + Config.EXCLUSIVE_SHOP.serverBoosts.rainCooldown + Config.RAIN_DURATION + 1
		if Purchases.rainRefusal(world, free) == nil then
			expect((Purchases.useCredit(world, s, "rain", nil, free, ON))).toBe(true)
			expect(s.data.credits.rain).toBe(0)
		end
	end)
	it("summoning the boss brings it after the warning, never twice within the cooldown", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		world.nextBossAt = T0 + 5000
		expect(Purchases.summonRefusal(world, T0)).toBeNil()
		Purchases.grant(world, s, "SummonBoss", T0, ON)
		expect(world.nextBossAt).toBe(T0 + Config.BOSS.WARNING_SECONDS)
		world.nextBossAt = T0 + 5000
		Purchases.grant(world, s, "SummonBoss", T0 + 60, ON)
		expect(s.data.credits.boss).toBe(1)
		expect(world.nextBossAt).toBe(T0 + 5000)
	end)
	it("the Weather Totem asks the weather service; without one it is a credit", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		Purchases.grant(world, s, "WeatherTotem", T0, ON)
		expect(s.data.credits.totem).toBe(1)
		if Config.FEATURES.Weather == true then
			local asked = nil
			local weatherCtx = {
				features = {},
				requestWeather = function(id: string): boolean
					asked = id
					return true
				end,
			}
			Purchases.grant(world, s, "WeatherTotem", T0, weatherCtx)
			expect(asked ~= nil).toBe(true)
			expect(s.data.credits.totem).toBe(1)
		end
	end)
	it("an income boost adds x2 into the capped code boost", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		Purchases.grant(world, s, "IncomeBoost15", T0, ON)
		expect(s.data.boostMult >= 2).toBe(true)
		expect(s.data.boostUntil).toBe(T0 + 900)
	end)
	it("Keep my streak carries a broken streak on to today's claim", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		local today = math.floor(T0 / 86400)
		s.data.daily = { lastDay = today - 3, streak = 5 }
		expect(Purchases.streakKeepable(s.data, T0)).toBe(true)
		Purchases.grant(world, s, "KeepStreak", T0, ON)
		expect(Purchases.streakKeepable(s.data, T0)).toBe(false)
		local Progression = require("../src/shared/Progression")
		Progression.claimDaily(s.data, T0)
		expect(s.data.daily.streak).toBe(6)
	end)
	it("a Growth snack feeds the aimed slime, else the least grown one; nothing to feed is a credit", function()
		local world = ServerFixtures.world()
		local a, b = Fixtures.slime("a", 1), Fixtures.slime("b", 1)
		a.growth, b.growth = 0.5, 0.1
		local s = ServerFixtures.join(world, 1, { a, b }, 0)
		expect((Purchases.aimSnack(world, s, "a"))).toBe(true)
		Purchases.grant(world, s, "GrowthSnack", T0, ON)
		expect((a.growth :: number) > 0.5).toBe(true)
		expect(b.growth).toBe(0.1)
		Purchases.grant(world, s, "GrowthSnack", T0, ON)
		expect((b.growth :: number) > 0.1).toBe(true)
		a.growth, b.growth = 1, 1
		Purchases.grant(world, s, "GrowthSnack", T0, ON)
		expect(s.data.credits.snack).toBe(1)
	end)
end)

describe("Exclusive styles, bundles and seasons", function()
	local PlotSkins = require("../src/shared/PlotSkins")
	local SaveData = require("../src/shared/SaveData")
	local Seasons = require("../src/shared/Seasons")
	local Carry = require("../src/server/Carry")
	it(
		"a hat, fanfare, lock style and base skin are owned once bought and worn with EquipStyle / EquipPlotSkin",
		function()
			local world = ServerFixtures.world()
			local s = ServerFixtures.join(world, 1)
			expect((Purchases.equipStyle(s, "hat", "party"))).toBe(false)
			for _, key in { "Hat_party", "Fanfare_confetti", "LockStyle_candy", "Skin_space" } do
				Purchases.grant(world, s, key, T0, ON)
			end
			expect(s.data.ownedStyles.hat).toEqual({ "party" })
			expect(s.data.ownedStyles.plotSkin).toEqual({ "space" })
			expect((Purchases.equipStyle(s, "hat", "party"))).toBe(true)
			expect((Purchases.equipStyle(s, "lockStyle", "candy"))).toBe(true)
			expect(s.data.wornStyles.hat).toBe("party")
			expect((Purchases.equipStyle(s, "hat", ""))).toBe(true)
			expect(s.data.wornStyles.hat).toBeNil()
			expect((Purchases.equipStyle(s, "trail", "sparkle"))).toBe(false)
			expect(PlotSkins.unlocked(s.data, PlotSkins.get("space") :: any)).toBe(true)
			expect((PlotSkins.equip(s.data, "space"))).toBe(true)
			expect(PlotSkins.unlocked(s.data, PlotSkins.get("beach") :: any)).toBe(false)
		end
	)
	it("styles survive a save round trip; unknown and unowned ids are dropped", function()
		local data = Fixtures.data(nil, 0)
		data.ownedStyles = { hat = { "party", "nope", "party" }, plotSkin = { "space" }, junk = { "x" } } :: any
		data.wornStyles = { hat = "party", fanfare = "confetti" }
		data.plotSkin = "space"
		local back = SaveData.deserialize(SaveData.serialize(data, T0))
		expect(back.ownedStyles.hat).toEqual({ "party" })
		expect(back.ownedStyles.plotSkin).toEqual({ "space" })
		expect((back.ownedStyles :: any).junk).toBeNil()
		expect(back.wornStyles.hat).toBe("party")
		expect(back.wornStyles.fanfare).toBeNil() -- not owned
		expect(back.plotSkin).toBe("space")
	end)
	it("an Exclusive base is owned once bought, says where to pick it, and State lists it", function()
		local PlotBases = require("../src/shared/PlotBases")
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		expect(Purchases.owns(s.data, "Base_rocket")).toBe(false)
		expect(Purchases.grant(world, s, "Base_rocket", T0, ON)).toBe(true)
		expect(s.data.ownedStyles.plotBase).toEqual({ "rocket" })
		expect(Purchases.owns(s.data, "Base_rocket")).toBe(true)
		expect(Purchases.giveItem(s.data, "Base_rocket")).toBe(false) -- once
		expect(ServerFixtures.notifications(world, 1)).toEqual({ "the Space Rocket base is yours! Pick it in Skins." })
		expect(PlotBases.unlocked(s.data, PlotBases.get("rocket") :: any)).toBe(true)
		expect(Purchases.view(s, T0, world).styles.plotBase).toEqual({ rocket = true })
	end)
	it("a gifted Exclusive base goes to the target; a gift taken back takes the base off", function()
		local PlotBases = require("../src/shared/PlotBases")
		local world = ServerFixtures.world()
		local buyer, target = ServerFixtures.join(world, 1), ServerFixtures.join(world, 2)
		assert(Purchases.aimGift(world, buyer, "Base_lighthouse", 2, T0))
		Purchases.grant(world, buyer, "Gift_Base_lighthouse", T0 + 1, {
			save = function()
				return true
			end,
		})
		expect(target.data.ownedStyles.plotBase).toEqual({ "lighthouse" })
		expect(buyer.data.ownedStyles.plotBase).toBeNil()
		expect(ServerFixtures.notifications(world, 2)).toEqual({ "P1 gave you the Lighthouse base!" })
		expect(select(2, Purchases.aimGift(world, buyer, "Base_lighthouse", 2, T0 + 2))).toBe("they already have it")
		-- The target's save fails: the base is taken back and taken off; the buyer keeps a gift credit.
		target.data.plotBase = "carousel"
		assert(Purchases.aimGift(world, buyer, "Base_carousel", 2, T0 + 3))
		Purchases.grant(world, buyer, "Gift_Base_carousel", T0 + 4, {
			save = function()
				return false
			end,
		})
		expect(target.data.ownedStyles.plotBase).toEqual({ "lighthouse" })
		expect(target.data.plotBase).toBe("jar")
		expect(PlotBases.current(target.data)).toBe("jar")
		expect(buyer.data.giftCredits).toEqual({ "Base_carousel" })
	end)
	it("a bundle gives every item in it, skipping owned ones", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		Purchases.grant(world, s, "Seat_magic_carpet", T0, ON)
		Purchases.grant(world, s, "BoutiqueBundle", T0, ON)
		expect(s.data.ownedSeats).toEqual({ "magic_carpet" })
		expect(s.data.ownedStyles.plotSkin).toEqual({ "fairground" })
		expect(s.data.ownedStyles.fanfare).toEqual({ "confetti" })
	end)
	it("seasonal items sell only in their season window (UTC, wrapping the new year)", function()
		local function at(month: number, day: number): number
			return os.time({ year = 2026, month = month, day = day, hour = 12 }) :: number
		end
		expect(Seasons.ofProduct("Hat_witch")).toBe("halloween")
		expect(Seasons.ofProduct("Skin_haunted")).toBe("halloween")
		expect(Seasons.ofProduct("Gift_Hat_witch")).toBe("halloween")
		expect(Seasons.ofProduct("Hat_party")).toBeNil()
		expect(Seasons.active("halloween", at(10, 31))).toBe(true)
		expect(Seasons.active("halloween", at(12, 1))).toBe(false)
		expect(Seasons.active("winter", at(12, 24))).toBe(true)
		expect(Seasons.active("winter", at(1, 3))).toBe(true)
		expect(Seasons.active("winter", at(2, 1))).toBe(false)
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		local hidden = PlotSkins.view(s.data, at(3, 1))
		for _, v in hidden do
			expect(v.id ~= "haunted").toBe(true)
		end
		local shown = false
		for _, v in PlotSkins.view(s.data, at(10, 31)) do
			shown = shown or v.id == "haunted"
		end
		expect(shown).toBe(true)
	end)
	it("a worn fanfare bursts on the slime when it lands on your pad", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		Purchases.grant(world, s, "Fanfare_starburst", T0, ON)
		Purchases.equipStyle(s, "fanfare", "starburst")
		Carry.fanfare(world, s, "slime1")
		local found = false
		for _, event in world.outbox do
			if event.type == "Effect" and event.effect == "Fanfare_starburst" and event.slimeId == "slime1" then
				found = true
			end
		end
		expect(found).toBe(true)
	end)
end)
