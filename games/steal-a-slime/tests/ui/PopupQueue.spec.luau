--!strict
-- One modal at a time; the tutorial holds the daily popup back (src/ui/PopupQueue.luau).
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
	it("is the tutorial while a step is shown, nil when finished", function()
		expect(PopupQueue.blocker(state("Grab"))).toBe("Tutorial")
		expect(PopupQueue.blocker(state("Rebirth"))).toBe("Tutorial")
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
		expect(q.update(state("Rebirth", true))).toBeNil()
		expect(q.queued()[1]).toBe("Daily")
		expect(q.update(state(nil, true))).toBe("Daily")
		expect(q.update(state(nil, true))).toBeNil()
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
