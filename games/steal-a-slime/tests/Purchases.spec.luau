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
		s.data.credits = { brew = 2, hatch = 0 }
		s.data.offlineDouble = { cash = 50, at = T0, used = false }
		local view = Purchases.view(s, T0)
		expect(view.owned).toEqual({ ufo = true })
		expect(view.passes).toEqual({ Income2x = true, Offline2x = false })
		expect(view.starterClaimed).toBe(false)
		expect(view.credits).toEqual({ brew = 2, hatch = 0 })
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
