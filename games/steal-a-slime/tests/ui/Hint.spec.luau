--!strict
-- "Tap here" hint for tutorial steps that need a HUD / menu button (src/ui/Hint.luau).
local Hint = require("../../src/ui/Hint")
local Layout = require("../../src/ui/Layout")
local TestRunner = require("../TestRunner")
local Tutorial = require("../../src/ui/Tutorial")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("Hint.fromState", function()
	it("points at the top-bar Lock / Buy pad and the menu's Merge / Rebirth", function()
		local lock = Hint.fromState({ tutorialStepId = "Lock" }) :: Hint.View
		expect(lock.text).toBe("Tap 🔒 Lock in the top bar")
		expect(lock.target.kind).toBe("hud")
		expect(lock.target.name).toBe("Lock")
		expect((Hint.fromState({ tutorialStepId = "BuyPad" }) :: Hint.View).target.name).toBe("BuyPad")
		local merge = Hint.fromState({ tutorialStepId = "Merge" }) :: Hint.View
		expect(merge.text).toBe("Tap 🧪 Merge in the left menu")
		expect(merge.target.kind).toBe("nav")
		expect((Hint.fromState({ tutorialStepId = "Rebirth" }) :: Hint.View).target.name).toBe("Rebirth")
	end)
	it("has no hint for world steps (Archer's arrow) or a finished tutorial", function()
		for _, id in { "Grab", "Deposit", "Steal" } do
			expect(Hint.fromState({ tutorialStepId = id })).toBeNil()
		end
		expect(Hint.fromState({})).toBeNil()
		expect(Hint.fromState(nil)).toBeNil()
	end)
	it("goes away once the menu panel it points at is open", function()
		expect(Hint.fromState({ tutorialStepId = "Merge" }, "Merge")).toBeNil()
		expect(Hint.fromState({ tutorialStepId = "Merge" }, "Shop")).toBeTruthy()
		expect(Hint.fromState({ tutorialStepId = "Lock" }, "Shop")).toBeTruthy()
	end)
	it("reads v12 numeric steps through Tutorial", function()
		local view = Hint.fromState({ tutorialStep = 3 }) :: Hint.View -- LEGACY_IDS[3] = Lock
		expect(view.id).toBe("Lock")
	end)
	it("only names tutorial steps that exist", function()
		for id in Hint.STEPS do
			expect(Tutorial.find(id)).toBeTruthy()
		end
	end)
end)

describe("Hint.place", function()
	it("rings the HUD button and puts the bubble under the bar", function()
		local s = Layout.screen(390, 844)
		local view = Hint.fromState({ tutorialStepId = "Lock" }) :: Hint.View
		local p = Hint.place(s, s.hud, view) :: Hint.Placement
		local lock = s.hud.items.Lock
		expect(p.target).toBe(lock)
		expect(p.ring.x).toBe(lock.x - Hint.RING)
		expect(p.ring.w).toBe(lock.w + Hint.RING * 2)
		expect(p.bubble.y).toBe(s.hud.rect.y + s.hud.rect.h + Hint.GAP)
	end)
	it("rings the nav button (after the toggle) and puts the bubble beside the nav", function()
		local s = Layout.screen(1920, 1080)
		local view = Hint.fromState({ tutorialStepId = "Merge" }) :: Hint.View
		local p = Hint.place(s, s.hud, view) :: Hint.Placement
		expect(p.target).toBe(s.navButtons[3]) -- toggle, Plot, Merge
		expect(p.bubble.x).toBe(s.nav.x + s.nav.w + Hint.GAP)
	end)
	it("is nil when the HUD target is hidden (all pads bought)", function()
		local s = Layout.screen(1920, 1080)
		local hud = Layout.hud(s.width, false, { BuyPad = false })
		local view = Hint.fromState({ tutorialStepId = "BuyPad" }) :: Hint.View
		expect(Hint.place(s, hud, view)).toBeNil()
	end)
	it("wraps a bubble that is wider than the space", function()
		local w, h = Hint.bubbleSize(string.rep("Tap the button ", 10), 200)
		expect(w).toBe(200)
		expect(h > Hint.MIN_HEIGHT).toBe(true)
	end)
end)
