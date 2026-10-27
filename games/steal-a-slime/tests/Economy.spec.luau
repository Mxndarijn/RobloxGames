--!strict
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local Fixtures = require("./Fixtures")
local Genome = require("../src/shared/Genome")
local PlayerData = require("../src/shared/PlayerData")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("Economy income", function()
	it("rebirth multiplier adds each rebirth's band step and ignores garbage", function()
		expect(Economy.rebirthMultiplier(0)).toBe(1)
		expect(Economy.rebirthMultiplier(1)).toBe(1 + Economy.rebirthStep(1))
		expect(Economy.rebirthMultiplier(10)).toBe(6)
		expect(Economy.rebirthMultiplier(20)).toBe(16)
		expect(Economy.rebirthMultiplier(30)).toBe(31)
		expect(Economy.rebirthMultiplier(-3)).toBe(1)
		expect(Economy.rebirthMultiplier(0 / 0)).toBe(1)
	end)
	it("rebirth steps follow REBIRTH_MULTIPLIER_STEPS: each band's step from its first rebirth on", function()
		local bands = Config.REBIRTH_MULTIPLIER_STEPS
		for i, band in bands do
			expect(Economy.rebirthStep(band.from)).toBe(band.step)
			if i > 1 then
				expect(Economy.rebirthStep(band.from - 1)).toBe(bands[i - 1].step)
				expect(band.step > bands[i - 1].step).toBeTruthy()
			end
		end
		local sum = 1
		for n = 1, Config.MAX_REBIRTHS do
			sum += Economy.rebirthStep(n)
			expect(Economy.rebirthMultiplier(n)).toBe(sum)
		end
	end)
	it("rebirth multiplier stops growing at MAX_REBIRTHS", function()
		local top = Economy.rebirthMultiplier(Config.MAX_REBIRTHS)
		expect(Economy.rebirthMultiplier(Config.MAX_REBIRTHS + 5)).toBe(top)
	end)
	it("per-slime income applies the rebirth multiplier", function()
		local s = Fixtures.slime("a", 2) -- 3/s
		expect(Economy.slimeIncome(s, 0)).toBe(3)
		expect(Economy.slimeIncome(s, 2)).toBe(6)
	end)
	it("plot income sums slimes and skips busy ones", function()
		local slimes = { Fixtures.slime("a", 1), Fixtures.slime("b", 2), Fixtures.slime("c", 3) }
		expect(Economy.plotIncome(slimes, 0)).toBe(13)
		expect(Economy.plotIncome(slimes, 0, { c = true })).toBe(4)
		expect(Economy.plotIncome({}, 5)).toBe(0)
	end)
end)

describe("Economy.tickIncome", function()
	it("accumulates fractions across ticks", function()
		local cash, rem = 0, 0
		for _ = 1, 60 do
			cash, rem = Economy.tickIncome(cash, rem, 1.5, 1 / 60)
		end
		expect(cash).toBe(1)
		expect(rem).toBeCloseTo(0.5, 1e-6)
	end)
	it("pays whole seconds directly", function()
		local cash, rem, paid = Economy.tickIncome(10, 0, 3, 2)
		expect(cash).toBe(16)
		expect(rem).toBe(0)
		expect(paid).toBe(6)
	end)
	it("ignores zero, negative and NaN inputs", function()
		expect((Economy.tickIncome(5, 0.2, 0, 1))).toBe(5)
		expect((Economy.tickIncome(5, 0.2, 3, -1))).toBe(5)
		expect((Economy.tickIncome(5, 0.2, 0 / 0, 1))).toBe(5)
	end)
end)

describe("Economy.offlineIncome", function()
	it("pays OFFLINE_RATE of income for the time away", function()
		local cash, secs = Economy.offlineIncome(10, 1000, 1600)
		expect(secs).toBe(600)
		expect(cash).toBe(math.floor(10 * 600 * Config.OFFLINE_RATE))
	end)
	it("is capped at OFFLINE_CAP_SECONDS", function()
		local now = 1e9
		local cash, secs = Economy.offlineIncome(10, now - 10 * 24 * 3600, now)
		expect(secs).toBe(Config.OFFLINE_CAP_SECONDS)
		expect(cash).toBe(math.floor(10 * Config.OFFLINE_CAP_SECONDS * Config.OFFLINE_RATE))
	end)
	it("respects custom cap and rate", function()
		expect((Economy.offlineIncome(2, 100, 1100, 50, 1))).toBe(100)
	end)
	it("pays nothing for new players, clock skew or no income", function()
		expect((Economy.offlineIncome(10, 0, 5000))).toBe(0)
		expect((Economy.offlineIncome(10, 5000, 4000))).toBe(0)
		expect((Economy.offlineIncome(0, 100, 5000))).toBe(0)
		expect((Economy.offlineIncome(10, 0 / 0, 5000))).toBe(0)
	end)
end)

describe("Economy prices", function()
	it("wild price is WILD_PRICE_SECONDS of the rarity's base income, at least 1", function()
		for tier = 1, Config.MAX_TIER do
			local slime = Fixtures.slime("w", tier)
			local expected = math.floor(Genome.baseIncome(slime) * Config.WILD_PRICE_SECONDS[tier])
			expect(Economy.wildPrice(slime)).toBe(expected)
		end
		expect(Economy.wildPrice(Fixtures.slime("w", 2))).toBe(3 * Config.WILD_PRICE_SECONDS[2])
		expect(Economy.wildPrice(Fixtures.slime("w", 1, { size = 0.001 }))).toBe(1)
	end)
	it("a rarer slime never costs fewer seconds of its income, and always more cash, at the fountain", function()
		expect(#Config.WILD_PRICE_SECONDS).toBe(Config.MAX_TIER)
		for tier = 2, Config.MAX_TIER do
			expect(Config.WILD_PRICE_SECONDS[tier] >= Config.WILD_PRICE_SECONDS[tier - 1]).toBeTruthy()
			local cheaper, dearer = Fixtures.slime("a", tier - 1), Fixtures.slime("b", tier)
			expect(Economy.wildPrice(dearer) > Economy.wildPrice(cheaper)).toBeTruthy()
		end
	end)
	it("sell price is SELL_PRICE_SHARE of the wild price, at least 1, and nil for an egg", function()
		local s = Fixtures.slime("a", 2)
		expect(Economy.sellPrice(s)).toBe(math.floor(Economy.wildPrice(s) * Config.SELL_PRICE_SHARE))
		expect((Economy.sellPrice(Fixtures.slime("a", 1, { size = 0.01 })) :: number) >= 1).toBeTruthy()
		expect(Economy.sellPrice(Fixtures.slime("e", 2, { egg = { kind = "Basic", hatchAt = 0 } }))).toBeNil()
	end)
	it("buying a wild slime and selling it at once always loses cash, at every rarity", function()
		for tier = 1, Config.MAX_TIER do
			for _, size in { 0.5, 1, 2 } do
				local s = Fixtures.slime("f", tier, { size = size })
				expect((Economy.sellPrice(s) :: number) < Economy.wildPrice(s)).toBeTruthy()
			end
		end
	end)
	it("the first PADS_START pads are free and the rest of floor 1 costs PAD_START_COSTS at 0 rebirths", function()
		for pad = 1, Config.PADS_PER_FLOOR do
			expect(Economy.rebirthsForPad(pad)).toBe(0)
		end
		for i, cost in Config.PAD_START_COSTS do
			local owned = Config.PADS_START + i - 1
			expect(Economy.padRebirths(owned)).toBe(0)
			expect(Economy.padCost(owned)).toBe(cost)
		end
	end)
	it("a higher-floor pad needs the rebirths its BASE_FLOORS row lists", function()
		for floor, row in Config.BASE_FLOORS do
			for i, need in row.padRebirths do
				local pad = (floor - 1) * Config.PADS_PER_FLOOR + i
				expect(Economy.rebirthsForPad(pad)).toBe(need)
				expect(Economy.padRebirths(pad - 1)).toBe(need)
			end
		end
	end)
	it("a rebirth-gated pad costs PAD_PRICE_SHARE of the rebirth after the one that opens it", function()
		local pad = Config.PADS_PER_FLOOR + 1
		local need = Economy.rebirthsForPad(pad)
		expect(need > 0).toBeTruthy()
		expect(Economy.padCost(pad - 1)).toBe(math.floor(Config.PAD_PRICE_SHARE * Economy.rebirthCost(need)))
	end)
	it("each further pad the same rebirth opens costs PAD_SAME_REBIRTH_GROWTH times the one before", function()
		local found = 0
		for pad = Config.PADS_PER_FLOOR + 2, Config.PADS_MAX do
			local need = Economy.rebirthsForPad(pad)
			if need == Economy.rebirthsForPad(pad - 1) and need ~= Economy.rebirthsForPad(pad - 2) then
				found += 1
				local before = Economy.padCost(pad - 2) :: number
				local cost = Economy.padCost(pad - 1) :: number
				local share = Config.PAD_PRICE_SHARE * Economy.rebirthCost(need)
				expect(cost).toBe(math.floor(share * Config.PAD_SAME_REBIRTH_GROWTH))
				expect(cost).toBeCloseTo(before * Config.PAD_SAME_REBIRTH_GROWTH, 1)
			end
		end
		expect(found > 0).toBeTruthy()
	end)
	it("prices every pad up to PADS_MAX higher than the one before and stops there", function()
		local last = 0
		for owned = Config.PADS_START, Config.PADS_MAX - 1 do
			local cost = Economy.padCost(owned) :: number
			expect(cost > last).toBeTruthy()
			last = cost
		end
		expect(Economy.padCost(Config.PADS_MAX)).toBeNil()
		expect(Economy.padRebirths(Config.PADS_MAX)).toBeNil()
	end)
	it("shows the floors with unlocked pads plus the next one once the top floor is full", function()
		local per = Config.PADS_PER_FLOOR
		expect(Config.PADS_MAX).toBe(#Config.BASE_FLOORS * per)
		expect(Economy.floorOf(1)).toBe(1)
		expect(Economy.floorOf(per)).toBe(1)
		expect(Economy.floorOf(per + 1)).toBe(2)
		expect(Economy.floorOf(Config.PADS_MAX)).toBe(#Config.BASE_FLOORS)
		expect(Economy.floorsShown(0)).toBe(1)
		expect(Economy.floorsShown(per - 1)).toBe(1)
		expect(Economy.floorsShown(per)).toBe(2)
		expect(Economy.floorsShown(per + 1)).toBe(2)
		expect(Economy.floorsShown(Config.PADS_MAX)).toBe(#Config.BASE_FLOORS)
	end)
	it("rebirth cost reads REBIRTH_COSTS, one price per rebirth, the last one past max", function()
		expect(#Config.REBIRTH_COSTS).toBe(Config.MAX_REBIRTHS)
		for r = 0, Config.MAX_REBIRTHS - 1 do
			expect(Economy.rebirthCost(r)).toBe(Config.REBIRTH_COSTS[r + 1])
		end
		expect(Economy.rebirthCost(Config.MAX_REBIRTHS + 3)).toBe(Config.REBIRTH_COSTS[#Config.REBIRTH_COSTS])
		expect(Economy.rebirthCost(-1)).toBe(Config.REBIRTH_COSTS[1])
	end)
	it("formats numbers", function()
		expect(Economy.formatNumber(999)).toBe("999")
		expect(Economy.formatNumber(1500)).toBe("1.5K")
		expect(Economy.formatNumber(2000000)).toBe("2M")
		expect(Economy.formatNumber(-1250)).toBe("-1.25K")
		expect(Economy.formatNumber(0 / 0)).toBe("0")
	end)
end)

describe("PlayerData plot", function()
	it("fills the lowest free pad and refuses when full", function()
		local data = PlayerData.new()
		for i = 1, Config.PADS_START do
			local ok, pad = PlayerData.addSlime(data, Fixtures.slime(`s{i}`))
			expect(ok).toBe(true)
			expect(pad).toBe(i)
		end
		local ok, reason = PlayerData.addSlime(data, Fixtures.slime("extra"))
		expect(ok).toBe(false)
		expect(reason).toBe("plot full")
	end)
	it("reuses a freed pad and rejects duplicates", function()
		local data = Fixtures.data({ Fixtures.slime("a"), Fixtures.slime("b") })
		PlayerData.removeSlime(data, "a")
		expect(PlayerData.freePad(data)).toBe(1)
		expect((PlayerData.addSlime(data, Fixtures.slime("b")))).toBe(false)
	end)
	it("records SlimeDex species once", function()
		local data = Fixtures.data({
			Fixtures.slime("a", 1, { species = "gummy" }),
			Fixtures.slime("b", 1, { species = "gummy" }),
		})
		expect(PlayerData.dexCount(data)).toBe(1)
		PlayerData.addSlime(data, Fixtures.slime("c", 2, { species = "bumble" }))
		expect(PlayerData.dexCount(data)).toBe(2)
	end)
	it("buys pads with cash", function()
		local data = PlayerData.new()
		data.cash = 50
		expect((PlayerData.buyPad(data))).toBe(false)
		data.cash = 1000
		expect((PlayerData.buyPad(data))).toBe(true)
		expect(data.padsUnlocked).toBe(Config.PADS_START + 1)
		expect(data.cash).toBe(1000 - Config.PAD_START_COSTS[1])
	end)
	it("refuses a pad the player hasn't rebirthed enough for, and charges nothing", function()
		local data = PlayerData.new()
		data.padsUnlocked = Config.PADS_PER_FLOOR
		data.cash = 1e15
		local need = Economy.padRebirths(data.padsUnlocked) :: number
		expect(need > 0).toBeTruthy()
		data.rebirths = need - 1
		local ok, reason = PlayerData.buyPad(data)
		expect(ok).toBe(false)
		expect(reason).toBe(`Rebirth {need} to unlock this pad`)
		expect(data.cash).toBe(1e15)
		expect(data.padsUnlocked).toBe(Config.PADS_PER_FLOOR)
		data.rebirths = need
		expect((PlayerData.buyPad(data))).toBe(true)
		expect(data.padsUnlocked).toBe(Config.PADS_PER_FLOOR + 1)
	end)
	it("sells slimes for cash and clears the favourite", function()
		local data = Fixtures.data({ Fixtures.slime("a", 2) }, 0)
		PlayerData.setFavorite(data, "a")
		local ok, price = PlayerData.sell(data, "a")
		expect(ok).toBe(true)
		local expected = Economy.sellPrice(Fixtures.slime("a", 2))
		expect(price).toBe(expected)
		expect(data.cash).toBe(expected)
		expect(#data.slimes).toBe(0)
		expect(data.favoriteId).toBeNil()
		expect((PlayerData.sell(data, "a"))).toBe(false)
	end)
	it("spend refuses negative amounts and overdrafts", function()
		local data = Fixtures.data(nil, 10)
		expect(PlayerData.spend(data, -5)).toBe(false)
		expect(PlayerData.spend(data, 11)).toBe(false)
		expect(PlayerData.spend(data, 10)).toBe(true)
		expect(data.cash).toBe(0)
	end)
	it("favourite must be an owned slime", function()
		local data = Fixtures.data({ Fixtures.slime("a") })
		expect(PlayerData.setFavorite(data, "zzz")).toBe(false)
		expect(PlayerData.setFavorite(data, "a")).toBe(true)
		expect(data.favoriteId).toBe("a")
	end)
end)
