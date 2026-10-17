--!strict
-- "Tap here" hint for tutorial steps that need a menu button (src/ui/Hint.luau).
local Hint = require("../../src/ui/Hint")
local Layout = require("../../src/ui/Layout")
local TestRunner = require("../TestRunner")
local Tutorial = require("../../src/ui/Tutorial")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("Hint.fromState", function()
	it("points only at the menu's Rebirth: no top bar (B7), Lock / Buy pad / Merge are world prompts", function()
		expect(Hint.fromState({ tutorialStepId = "Lock" })).toBeNil()
		expect(Hint.fromState({ tutorialStepId = "BuyPad" })).toBeNil()
		expect(Hint.fromState({ tutorialStepId = "Merge" })).toBeNil() -- the vat in the world, H1 HUD
		local rebirth = Hint.fromState({ tutorialStepId = "Rebirth" }) :: Hint.View
		expect(rebirth.text).toBe("Tap ♻️ Rebirth in the left menu")
		expect(rebirth.target.kind).toBe("nav")
		expect(rebirth.target.name).toBe("Rebirth")
	end)
	it("has no hint for world steps (Archer's arrow) or a finished tutorial", function()
		for _, id in { "Grab", "Deposit", "Lock", "BuyPad", "Steal" } do
			expect(Hint.fromState({ tutorialStepId = id })).toBeNil()
		end
		expect(Hint.fromState({})).toBeNil()
		expect(Hint.fromState(nil)).toBeNil()
	end)
	it("goes away once the menu panel it points at is open", function()
		expect(Hint.fromState({ tutorialStepId = "Rebirth" }, "Rebirth")).toBeNil()
		expect(Hint.fromState({ tutorialStepId = "Rebirth" }, "Shop")).toBeTruthy()
	end)
	it("reads v12 numeric steps through Tutorial", function()
		local view = Hint.fromState({ tutorialStep = 6 }) :: Hint.View -- LEGACY_IDS[6] = Rebirth
		expect(view.id).toBe("Rebirth")
	end)
	it("only names tutorial steps that exist", function()
		for id in Hint.STEPS do
			expect(Tutorial.find(id)).toBeTruthy()
		end
	end)
end)

describe("Hint.place", function()
	it("rings the nav button and puts the bubble beside the nav", function()
		local s = Layout.screen(1920, 1080)
		local view = Hint.fromState({ tutorialStepId = "Rebirth" }) :: Hint.View
		local p = Hint.place(s, view) :: Hint.Placement
		expect(p.target).toBe(s.navButtons[2]) -- Plot, Rebirth
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
