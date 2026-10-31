--!strict
-- Why a slime can't be grabbed (src/shared/GrabBlock.luau): the reason its GrabPrompt shows.
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local GrabBlock = require("../src/shared/GrabBlock")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function me(carrying: boolean, freePad: boolean, cash: number): GrabBlock.Me
	return { carrying = carrying, freePad = freePad, cash = cash }
end

local function wild(price: number, boss: boolean?): GrabBlock.Target
	return { state = "Wild", price = price, boss = boss == true }
end

describe("GrabBlock.reason", function()
	it("is nil when you can grab it", function()
		expect(GrabBlock.reason(me(false, true, 100), wild(100))).toBeNil()
		expect(GrabBlock.reason(me(false, true, 0), wild(0))).toBeNil()
	end)
	it("carrying beats every other reason, steals included", function()
		expect(GrabBlock.reason(me(true, false, 0), wild(50))).toBe("carrying")
		expect(GrabBlock.reason(me(true, true, 0), { state = "Pad", price = nil, boss = false })).toBe("carrying")
	end)
	it("a full plot blocks free and paid wild slimes, not the boss or a steal", function()
		expect(GrabBlock.reason(me(false, false, 999), wild(0))).toBe("plotFull")
		expect(GrabBlock.reason(me(false, false, 999), wild(10))).toBe("plotFull")
		expect(GrabBlock.reason(me(false, false, 0), wild(0, true))).toBeNil()
		expect(GrabBlock.reason(me(false, false, 0), { state = "Pad", price = nil, boss = false })).toBeNil()
	end)
	it("not enough money when the price is above your cash", function()
		expect(GrabBlock.reason(me(false, true, 99), wild(100))).toBe("money")
	end)
	it("every reason has its text", function()
		expect(GrabBlock.TEXT.carrying).toBe("Already carrying a slime")
		expect(GrabBlock.TEXT.plotFull).toBe("Plot is full, buy more pads")
		expect(GrabBlock.TEXT.money).toBe("Not enough money")
	end)
	it("money says how much cash is missing", function()
		expect(GrabBlock.text("money", wild(100), me(false, true, 99))).toBe("Need $1 more")
		expect(GrabBlock.text("money", wild(15000), me(false, true, 2500))).toBe("Need $12.5K more")
		expect(GrabBlock.text("money", wild(100))).toBe("Not enough money")
	end)
end)

describe("GrabBlock rank gate", function()
	local function ranked(rebirths: number?, need: number?, price: number?, boss: boolean?): GrabBlock.Reason?
		local who: GrabBlock.Me = { carrying = false, freePad = true, cash = 1000, rebirths = rebirths }
		return GrabBlock.reason(who, { state = "Wild", price = price or 0, boss = boss == true, rebirths = need })
	end
	it("is 'rank' when the slime needs more rebirths than the player has, nil at exactly enough", function()
		expect(ranked(4, 5)).toBe("rank")
		expect(ranked(nil, 5)).toBe("rank")
		expect(ranked(5, 5)).toBeNil()
		expect(ranked(0, nil)).toBeNil()
	end)
	it("ranks below carrying but above a full plot and money", function()
		expect(GrabBlock.reason({ carrying = true, freePad = true, cash = 0, rebirths = 0 }, {
			state = "Wild",
			price = 0,
			boss = false,
			rebirths = 12,
		})).toBe("carrying")
		expect(GrabBlock.reason({ carrying = false, freePad = false, cash = 0, rebirths = 0 }, {
			state = "Wild",
			price = 50,
			boss = false,
			rebirths = 12,
		})).toBe("rank")
	end)
	it("never gates a steal or the boss", function()
		local who: GrabBlock.Me = { carrying = false, freePad = true, cash = 0, rebirths = 0 }
		expect(GrabBlock.reason(who, { state = "Pad", boss = false, rebirths = 25 })).toBeNil()
		expect(ranked(0, 25, 0, true)).toBeNil()
	end)
	it("text names the rebirth for 'rank' and falls back to TEXT for the rest", function()
		expect(GrabBlock.text("rank", { state = "Wild", boss = false, rebirths = 12 })).toBe("Rebirth 12 to grab this")
		for _, reason in { "carrying", "plotFull", "money" } :: { GrabBlock.Reason } do
			expect(GrabBlock.text(reason, { state = "Wild", boss = false })).toBe(GrabBlock.TEXT[reason])
		end
	end)
	it("rebirthsFor reads CATCH_REBIRTHS by rarity and the egg kind's rebirths for a Mystery Egg", function()
		for tier = 1, Config.MAX_TIER do
			expect(GrabBlock.rebirthsFor(Fixtures.slime("s", tier))).toBe(Config.CATCH_REBIRTHS[tier])
		end
		expect(GrabBlock.rebirthsFor(Fixtures.slime("s", 6))).toBe(5)
		expect(GrabBlock.rebirthsFor(Fixtures.slime("s", 9))).toBe(25)
		for _, kind in Config.MYSTERY_EGG.KINDS do
			-- the egg's kind decides, never the (hidden) tier inside
			expect(GrabBlock.rebirthsFor(Fixtures.slime("e", 9, { egg = { kind = kind.id } }))).toBe(kind.rebirths)
		end
	end)
end)

describe("GrabBlock.hasFreePad", function()
	local function views(pads: { number? }): { { slime: { pad: number? } } }
		local out = {}
		for i = 1, 4 do
			table.insert(out, { slime = { pad = pads[i] } })
		end
		return out
	end
	it("finds a gap among the unlocked pads", function()
		expect(GrabBlock.hasFreePad(4, views({ 1, 2, 4 }))).toBe(true)
		expect(GrabBlock.hasFreePad(3, views({ 1, 2, 3 }))).toBe(false)
		expect(GrabBlock.hasFreePad(0, {})).toBe(false)
	end)
end)
