--!strict
-- "Tap here" ring round a left-menu button (src/ui/Hint.luau): every tutorial step is in the world, so the only
-- hint is the Goals ring while the "Tutorial done" card shows.
local Hint = require("../../src/ui/Hint")
local Layout = require("../../src/ui/Layout")
local Nav = require("../../src/ui/Nav")
local TestRunner = require("../TestRunner")
local Tutorial = require("../../src/ui/Tutorial")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function navIndex(key: string): number
	for i, entry in Nav.ENTRIES do
		if entry.key == key then
			return i
		end
	end
	error(key)
end

describe("Hint.fromState", function()
	it("has no hint during any tutorial step: they all happen in the world", function()
		for _, step in Tutorial.STEPS do
			expect(Hint.fromState({ tutorialStepId = step.id })).toBeNil()
			expect(Hint.fromState({ tutorialStepId = step.id }, nil, true)).toBeNil()
		end
	end)
	it("rings Goals while the tutorial-done card shows, and not after", function()
		local view = Hint.fromState({}, nil, true) :: Hint.View
		expect(view.id).toBe("Finished")
		expect(view.target.kind).toBe("nav")
		expect(view.target.name).toBe("Goals")
		local goals = Nav.ENTRIES[navIndex("Goals")]
		expect(string.find(view.text, `{goals.icon} {goals.label}`, 1, true) ~= nil).toBe(true)
		expect(Hint.fromState({}, nil, false)).toBeNil()
		expect(Hint.fromState({})).toBeNil()
		expect(Hint.fromState(nil)).toBeNil()
	end)
	it("goes away once Goals is open", function()
		expect(Hint.fromState({}, "Goals", true)).toBeNil()
		expect(Hint.fromState({}, "Shop", true)).toBeTruthy()
	end)
end)

describe("Hint.place", function()
	it("rings the nav button and puts the bubble beside the nav", function()
		local s = Layout.screen(1920, 1080)
		local view = Hint.fromState({}, nil, true) :: Hint.View
		local p = Hint.place(s, view) :: Hint.Placement
		expect(p.target).toBe(s.navButtons[navIndex("Goals")])
		expect(p.ring.x).toBe(p.target.x - Hint.RING)
		expect(p.ring.w).toBe(p.target.w + Hint.RING * 2)
		expect(p.bubble.x).toBe(s.nav.x + s.nav.w + Hint.GAP)
	end)
	it("is nil for a target that is not in the nav", function()
		local s = Layout.screen(1920, 1080)
		expect(Hint.place(s, { id = "X", text = "Tap", target = { kind = "nav", name = "Nope" } })).toBeNil()
	end)
	it("wraps a bubble that is wider than the space", function()
		local w, h = Hint.bubbleSize(string.rep("Tap the button ", 10), 200)
		expect(w).toBe(200)
		expect(h > Hint.MIN_HEIGHT).toBe(true)
	end)
end)
