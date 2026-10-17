--!strict
local Config = require("../../src/shared/Config")
local EventsBoard = require("../../src/ui/EventsBoard")
local TestRunner = require("../TestRunner")
local WeeklyEvents = require("../../src/shared/WeeklyEvents")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function utc(y: number, m: number, d: number, h: number, min: number, s: number): number
	return os.time({ year = y, month = m, day = d, hour = h, min = min, sec = s }) -- Lune runs in UTC
end

local SAT_TRAIT = utc(2026, 10, 17, 19, 0, 0) -- Saturday inside the trait window
local WED = utc(2026, 10, 14, 12, 0, 0)
local surge = { name = "LuckSurge", label = "Luck Surge", luck = 2, mutation = 1, endsAt = 200 }

describe("EventsBoard", function()
	it("is behind FEATURES.EventsBoard, default off", function()
		expect(Config.FEATURES.EventsBoard).toBe(false)
		expect(EventsBoard.text(WeeklyEvents.encode(WED), surge, 80, WED, false)).toBeNil()
	end)
	it("lists the weekly mutation, the modifier and the next event", function()
		local lines = EventsBoard.lines(WeeklyEvents.encode(WED), surge, 80, WED, true) :: { string }
		local mutation = WeeklyEvents.mutationEvent(WED)
		expect(#lines).toBe(4)
		expect(lines[1]).toBe("📅 Server events")
		expect(string.find(lines[2], `{mutation.id} week - `, 1, true) ~= nil).toBe(true)
		expect(lines[3]).toBe("Luck Surge x2 luck - 2:00 left")
		expect(string.find(lines[4], "Next: ", 1, true) == 1).toBe(true)
		expect(string.find(lines[4], WeeklyEvents.next(WED).label, 1, true) ~= nil).toBe(true)
	end)
	it("adds the Saturday trait event with its multipliers while it runs", function()
		local trait = WeeklyEvents.current(SAT_TRAIT)[2]
		expect(trait ~= nil).toBe(true)
		local text = EventsBoard.text(WeeklyEvents.encode(SAT_TRAIT), nil, 0, SAT_TRAIT, true) :: string
		expect(string.find(text, trait.label, 1, true) ~= nil).toBe(true)
		expect(string.find(text, "1h 0m left", 1, true) ~= nil).toBe(true)
	end)
	it("counts down to the next event in days and hours", function()
		local at = utc(2026, 10, 17, 18, 0, 0) - (2 * 86400 + 3 * 3600)
		local text = EventsBoard.text(WeeklyEvents.encode(at), nil, 0, at, true) :: string
		expect(string.find(text, " in 2d 3h", 1, true) ~= nil).toBe(true)
	end)
	it("works without the weekly attribute (modifier only) and hides when empty", function()
		local lines = EventsBoard.lines(nil, surge, 80, WED, true) :: { string }
		expect(#lines).toBe(2)
		expect(EventsBoard.lines(nil, nil, 0, WED, true)).toBeNil()
		expect(EventsBoard.lines("garbage", { name = "None", label = "None", luck = 1, mutation = 1 }, 0, WED, true)).toBeNil()
	end)
	it("drops an event that has ended", function()
		local attr = WeeklyEvents.encode(WED)
		expect(EventsBoard.lines(attr, nil, 0, WED + 30 * 86400, true)).toBeNil()
	end)
end)
