--!strict
-- Daily streak helpers for the welcome / daily reward card (src/ui/Daily.luau).
local Daily = require("../../src/ui/Daily")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function reward(day: number, skin: boolean?): Daily.Reward
	return {
		day = day,
		kind = if skin then "trail" else "cash",
		label = `d{day}`,
		short = `d{day}`,
		icon = "Cash",
		skin = skin == true,
	}
end

local TRACK = { reward(8), reward(9), reward(10), reward(11), reward(12), reward(13), reward(14, true) }

describe("Daily.track", function()
	it("marks days before today claimed, today, and the rest upcoming", function()
		local cells = Daily.track({ available = true, streak = 9, day = 10, track = TRACK })
		expect(#cells).toBe(7)
		expect(cells[1].state).toBe("claimed")
		expect(cells[2].state).toBe("claimed")
		expect(cells[3].state).toBe("today")
		expect(cells[4].state).toBe("upcoming")
		expect(cells[7].reward.skin).toBe(true)
	end)
	it("shows today as claimed once nothing is available", function()
		expect(Daily.track({ available = false, streak = 10, day = 10, track = TRACK })[3].state).toBe("claimed")
	end)
	it("is empty without a track", function()
		expect(#Daily.track({ available = true, streak = 0, day = 1 })).toBe(0)
	end)
end)

describe("Daily.dayLabel", function()
	it("names today and skin days, numbers the rest, and is empty once claimed", function()
		local cells = Daily.track({ available = true, streak = 9, day = 10, track = TRACK })
		expect(Daily.dayLabel(cells[1])).toBe("")
		expect(Daily.dayLabel(cells[3])).toBe("Day 10")
		expect(Daily.dayLabel(cells[4])).toBe("11")
		expect(Daily.dayLabel(cells[7])).toBe("Day 14")
	end)
end)

describe("Daily.shouldAutoOpen", function()
	it("opens on the first available snapshot and on each false -> true edge only", function()
		expect(Daily.shouldAutoOpen(nil, true)).toBe(true)
		expect(Daily.shouldAutoOpen(false, true)).toBe(true)
		expect(Daily.shouldAutoOpen(true, true)).toBe(false)
		expect(Daily.shouldAutoOpen(nil, false)).toBe(false)
	end)
end)
