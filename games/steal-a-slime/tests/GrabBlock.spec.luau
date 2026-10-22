--!strict
-- Why a slime can't be grabbed (src/shared/GrabBlock.luau): the reason its GrabPrompt shows.
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
