--!strict
-- When the welcome back / daily reward card opens by itself, and in which mode (src/ui/PopupQueue.luau).
local PopupQueue = require("../../src/ui/PopupQueue")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function state(step: string?, daily: boolean?, report: boolean?): any
	return {
		tutorialStepId = step,
		daily = if daily == nil then nil else { available = daily, streak = 1, amount = 100, day = 2 },
		welcomeBack = if report then { away = 19800, cash = 100, grown = 0 } else nil,
	}
end

describe("PopupQueue.blocker", function()
	it("is the tutorial during Grab, Deposit, Lock and BuyPad, nil on the other steps and when finished", function()
		for _, id in { "Grab", "Deposit", "Lock", "BuyPad" } do
			expect(PopupQueue.blocker(state(id))).toBe("Tutorial")
		end
		for _, id in { "Leaderboard", "Guide", "Merge", "BuyItem" } do
			expect(PopupQueue.blocker(state(id))).toBeNil()
		end
		expect(PopupQueue.blocker(state(nil))).toBeNil()
		expect(PopupQueue.blocker({ tutorialStepId = "Done" })).toBeNil() -- unknown = finished
		expect(PopupQueue.blocker(nil)).toBeNil()
	end)
end)

describe("PopupQueue.update: the daily mode", function()
	it("opens at once when a claim is ready and nothing blocks, then not again while it stays ready", function()
		local q = PopupQueue.new()
		expect(q.update(state(nil, true))).toBe("daily")
		expect(q.pending()).toBeNil()
		expect(q.update(state(nil, true))).toBeNil()
	end)
	it("waits through the blocking tutorial steps and opens on the others", function()
		for _, id in { "Leaderboard", "Guide", "Merge", "BuyItem" } do
			local q = PopupQueue.new()
			expect(q.update(state("Grab", true))).toBeNil()
			expect(q.update(state("BuyPad", true))).toBeNil()
			expect(q.pending()).toBe("daily")
			expect(q.update(state(id, true))).toBe("daily")
		end
	end)
	it("never replaces an open menu or the bag: it waits until they close", function()
		local q = PopupQueue.new()
		expect(q.update(state(nil, true), true)).toBeNil()
		expect(q.update(state(nil, true), true)).toBeNil()
		expect(q.update(state(nil, true), false)).toBe("daily")
	end)
	it("drops the queued claim when it goes away, and queues again on the next edge", function()
		local q = PopupQueue.new()
		q.update(state("Grab", true))
		expect(q.update(state("Grab", false))).toBeNil()
		expect(q.pending()).toBeNil()
		expect(q.update(state(nil, true))).toBe("daily")
	end)
	it("Settings 'Daily popup' off: a new day's claim does not open the card", function()
		local q = PopupQueue.new()
		expect(q.update(state(nil, true), false, false)).toBeNil()
		expect(q.update(state(nil, true), false, true)).toBeNil() -- the edge is gone
	end)
	it("ignores States without a daily view", function()
		expect(PopupQueue.new().update(state(nil))).toBeNil()
	end)
end)

describe("PopupQueue.update: the join mode", function()
	it("opens once per join and takes the pending daily with it", function()
		local q = PopupQueue.new()
		local s = state(nil, true, true)
		expect(q.update(s)).toBe("join")
		expect(q.pending()).toBeNil()
		expect(q.update(s)).toBeNil() -- closing it without claiming does not reopen it
	end)
	it("shows even with Settings 'Daily popup' off", function()
		expect(PopupQueue.new().update(state(nil, true, true), false, false)).toBe("join")
	end)
	it("waits for the blocking tutorial steps and open menus", function()
		local q = PopupQueue.new()
		expect(q.update(state("BuyPad", true, true))).toBeNil()
		expect(q.update(state("Merge", true, true), true)).toBeNil()
		expect(q.update(state("Merge", true, true))).toBe("join")
	end)
	it("a later new day opens the daily mode", function()
		local q = PopupQueue.new()
		expect(q.update(state(nil, true, true))).toBe("join")
		q.update(state(nil, false, true))
		expect(q.update(state(nil, true, true))).toBe("daily")
	end)
	it("with the daily already claimed it still opens for the report", function()
		expect(PopupQueue.new().update(state(nil, false, true))).toBe("join")
	end)
end)
