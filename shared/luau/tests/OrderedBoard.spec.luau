--!strict
local OrderedBoard = require("../src/ranking/OrderedBoard")
local T = require("../testing/TestRunner")
local describe, it, expect = T.describe, T.it, T.expect

local function named(userId: number): string
	return `P{userId}`
end

describe("OrderedBoard.clamp", function()
	it("floors and caps to a valid OrderedDataStore value", function()
		expect(OrderedBoard.clamp(12.9)).toBe(12)
		expect(OrderedBoard.clamp(-5)).toBe(0)
		expect(OrderedBoard.clamp(1e300)).toBe(OrderedBoard.MAX_VALUE)
		expect(OrderedBoard.clamp(math.huge)).toBe(OrderedBoard.MAX_VALUE)
	end)

	it("turns NaN and non-numbers into 0", function()
		expect(OrderedBoard.clamp(0 / 0)).toBe(0)
		expect(OrderedBoard.clamp("12")).toBe(0)
		expect(OrderedBoard.clamp(nil)).toBe(0)
	end)
end)

describe("OrderedBoard.shouldWrite", function()
	it("writes only a saved, writable, changed value", function()
		expect(OrderedBoard.shouldWrite(true, false, nil, 5)).toBe(true)
		expect(OrderedBoard.shouldWrite(true, false, 5, 5)).toBe(false)
		expect(OrderedBoard.shouldWrite(false, false, nil, 5)).toBe(false)
		expect(OrderedBoard.shouldWrite(true, true, nil, 5)).toBe(false)
	end)
end)

describe("OrderedBoard keys", function()
	it("round-trips a user id through its key", function()
		expect(OrderedBoard.key(42)).toBe("u_42")
		expect(OrderedBoard.userIdFromKey("u_42")).toBe(42)
		expect(OrderedBoard.userIdFromKey(OrderedBoard.key(7, "p:"), "p:")).toBe(7)
	end)

	it("rejects other shapes", function()
		expect(OrderedBoard.userIdFromKey("u_")).toBe(nil)
		expect(OrderedBoard.userIdFromKey("u_12x")).toBe(nil)
		expect(OrderedBoard.userIdFromKey("x_12")).toBe(nil)
		expect(OrderedBoard.userIdFromKey(12)).toBe(nil)
	end)

	it("names one store per period", function()
		expect(OrderedBoard.periodKey("Weekly", 2912)).toBe("Weekly_2912")
		expect(OrderedBoard.periodKey("Weekly", 2912.7)).toBe("Weekly_2912")
	end)
end)

describe("OrderedBoard.entries", function()
	it("ranks a page best first and names each player", function()
		local entries = OrderedBoard.entries({ { key = "u_1", value = 30 }, { key = "u_2", value = 10 } }, named)
		expect(#entries).toBe(2)
		expect(entries[1].rank).toBe(1)
		expect(entries[1].userId).toBe(1)
		expect(entries[1].name).toBe("P1")
		expect(entries[2].rank).toBe(2)
		expect(entries[2].value).toBe(10)
	end)

	it("skips junk without leaving a gap in the ranks", function()
		local entries = OrderedBoard.entries(
			{
				{ key = "bad", value = 99 },
				"nope",
				{ key = "u_3", value = "x" },
				{ key = "u_4", value = 0 / 0 },
				{ key = "u_5", value = 8 },
			} :: { any },
			named
		)
		expect(#entries).toBe(1)
		expect(entries[1].userId).toBe(5)
		expect(entries[1].rank).toBe(1)
	end)

	it("stops at the size", function()
		local page = {}
		for i = 1, 15 do
			table.insert(page, { key = `u_{i}`, value = 100 - i })
		end
		expect(#OrderedBoard.entries(page, named)).toBe(10)
		expect(#OrderedBoard.entries(page, named, { size = 3 })).toBe(3)
	end)
end)

describe("OrderedBoard.pageFrom", function()
	it("sorts records highest first, ties by key", function()
		local page = OrderedBoard.pageFrom({
			{ key = "u_2", value = 5 },
			{ key = "u_1", value = 5 },
			{ key = "u_3", value = 9.5 },
		})
		expect(page[1].key).toBe("u_3")
		expect(page[1].value).toBe(9)
		expect(page[2].key).toBe("u_1")
		expect(page[3].key).toBe("u_2")
	end)

	it("clamps values like a store write", function()
		local page = OrderedBoard.pageFrom({ { key = "u_1", value = -3 }, { key = "u_2", value = 0 / 0 } })
		expect(page[1].value).toBe(0)
		expect(page[2].value).toBe(0)
	end)
end)
