--!strict
-- One modal at a time; the early tutorial steps hold the daily popup back (src/ui/PopupQueue.luau).
local PopupQueue = require("../../src/ui/PopupQueue")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function state(step: string?, daily: boolean?): any
	return {
		tutorialStepId = step,
		daily = if daily == nil then nil else { available = daily, streak = 1, amount = 100 },
	}
end

describe("PopupQueue.blocker", function()
	it("is the tutorial during Grab..BuyPad, nil from Merge onward and when finished", function()
		for _, id in { "Grab", "Deposit", "Lock", "BuyPad" } do
			expect(PopupQueue.blocker(state(id))).toBe("Tutorial")
		end
		for _, id in { "Merge", "Steal", "Rebirth" } do
			expect(PopupQueue.blocker(state(id))).toBeNil()
		end
		expect(PopupQueue.blocker(state(nil))).toBeNil()
		expect(PopupQueue.blocker({ tutorialStep = 2 })).toBe("Tutorial") -- v12 numeric steps
		expect(PopupQueue.blocker({ tutorialStepId = "Done" })).toBeNil() -- unknown = finished
		expect(PopupQueue.blocker(nil)).toBeNil()
	end)
end)

describe("PopupQueue.update", function()
	it("opens the daily popup at once when there is no tutorial", function()
		local q = PopupQueue.new()
		expect(q.update(state(nil, true))).toBe("Daily")
		expect(q.has("Daily")).toBe(false) -- taken off the queue
		expect(q.update(state(nil, true))).toBeNil() -- not again while still available
	end)
	it("keeps the daily popup queued during the tutorial, opens it when finished", function()
		local q = PopupQueue.new()
		expect(q.update(state("Grab", true))).toBeNil()
		expect(q.has("Daily")).toBe(true)
		expect(q.update(state("Lock", true))).toBeNil()
		expect(q.update(state("BuyPad", true))).toBeNil()
		expect(q.queued()[1]).toBe("Daily")
		expect(q.update(state(nil, true))).toBe("Daily")
		expect(q.update(state(nil, true))).toBeNil()
	end)
	it("opens the queued daily popup during Merge, Steal and Rebirth", function()
		for _, id in { "Merge", "Steal", "Rebirth" } do
			local q = PopupQueue.new()
			expect(q.update(state("Grab", true))).toBeNil()
			expect(q.update(state(id, true))).toBe("Daily")
			expect(q.update(state(id, true))).toBeNil()
		end
	end)
	it("opens the welcome-back card from Merge onward, before the daily popup", function()
		local q = PopupQueue.new()
		local s = state("BuyPad", true)
		s.welcomeBack = {}
		expect(q.update(s)).toBeNil()
		s.tutorialStepId = "Merge"
		expect(q.update(s)).toBe("Welcome")
		expect(q.update(s, true)).toBeNil()
		expect(q.update(s)).toBe("Daily")
	end)
	it("drops the queued daily when the claim goes away (claimed from the HUD)", function()
		local q = PopupQueue.new()
		q.update(state("Grab", true))
		expect(q.update(state("Grab", false))).toBeNil()
		expect(q.has("Daily")).toBe(false)
		expect(q.update(state(nil, false))).toBeNil()
	end)
	it("queues again on the next availability edge", function()
		local q = PopupQueue.new()
		expect(q.update(state(nil, true))).toBe("Daily")
		q.update(state(nil, false))
		expect(q.update(state(nil, true))).toBe("Daily")
	end)
	it("ignores states without daily; manual enqueue / remove", function()
		local q = PopupQueue.new()
		expect(q.update(state(nil))).toBeNil()
		q.enqueue("Daily")
		expect(q.has("Daily")).toBe(true)
		q.remove("Daily")
		expect(#q.queued()).toBe(0)
	end)
	it("never holds a daily popup without a claim to show", function()
		local q = PopupQueue.new()
		q.enqueue("Daily")
		expect(q.update(state(nil, false))).toBeNil()
		expect(q.has("Daily")).toBe(false)
	end)
end)
