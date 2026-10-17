--!strict
-- Events board (FEATURES.EventsBoard, CONTRACT.md §20) core logic, cloud-eligible twin of tests/ui/EventsBoard.spec
-- (tests/ui is not staged for the cloud run): flag, missing / hostile attribute, boundaries, server-clock input.
local Config = require("../src/shared/Config")
local EventsBoard = require("../src/ui/EventsBoard")
local TestRunner = require("./TestRunner")
local WeeklyEvents = require("../src/shared/WeeklyEvents")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local DAY = 86400
local MON = 1_792_368_000 -- 2026-10-19 00:00 UTC
local SAT_START = MON + 5 * DAY + Config.WEEKLY.TRAIT_START_HOUR * 3600
local surge = { name = "LuckSurge", label = "Luck Surge", luck = 2, mutation = 1, endsAt = 200 }

describe("EventsBoard core", function()
	it("is off when the flag is off, whatever the inputs", function()
		expect(EventsBoard.lines(WeeklyEvents.encode(MON + 60), surge, 80, MON + 60, false)).toBeNil()
		expect(EventsBoard.text(nil, nil, 0, 0, false)).toBeNil()
	end)
	it("a server without the weekly attribute (flag off) or the modifier field shows nothing, never errors", function()
		expect(EventsBoard.lines(nil, nil, 0, MON, true)).toBeNil()
		expect(EventsBoard.lines(nil, nil, 0, MON + 0.5, true)).toBeNil()
		for _, junk in { 5, true, {}, "", "garbage" } do
			expect(EventsBoard.lines(junk, nil, 0, MON, true)).toBeNil()
		end
	end)
	it("takes the fractional server clock and counts down to the exact boundaries", function()
		local at = SAT_START - 0.5
		local text = EventsBoard.text(WeeklyEvents.encode(at), nil, 0, at, true) :: string
		expect(string.find(text, "Next: ", 1, true) ~= nil).toBe(true)
		expect(string.find(text, " in 0:01", 1, true) ~= nil).toBe(true) -- ceil(0.5 s) = 1 s
		local live = SAT_START + 0.5
		local liveText = EventsBoard.text(WeeklyEvents.encode(live), nil, 0, live, true) :: string
		local trait = WeeklyEvents.current(live)[2]
		expect(string.find(liveText, trait.label, 1, true) ~= nil).toBe(true)
	end)
	it("the trait line disappears at its end second while the mutation week stays", function()
		local ends = SAT_START + Config.WEEKLY.TRAIT_SECONDS
		local attr = WeeklyEvents.encode(SAT_START + 60)
		local trait = WeeklyEvents.current(SAT_START + 60)[2]
		local text = EventsBoard.text(attr, nil, 0, ends, true) :: string
		expect(string.find(text, trait.label, 1, true)).toBeNil()
		expect(string.find(text, " week - ", 1, true) ~= nil).toBe(true)
	end)
	it("a stale attribute after the whole week has passed hides the board", function()
		expect(EventsBoard.lines(WeeklyEvents.encode(MON + 60), nil, 0, MON + 8 * DAY, true)).toBeNil()
	end)
end)
