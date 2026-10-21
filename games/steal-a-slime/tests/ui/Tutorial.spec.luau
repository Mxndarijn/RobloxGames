--!strict
-- Tutorial overlay step text (src/ui/Tutorial.luau, CONTRACT §8.3).
local TestRunner = require("../TestRunner")
local Tutorial = require("../../src/ui/Tutorial")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

-- CONTRACT §8.3 TutorialProgress.STEPS (v13).
local V13 = { "Grab", "Deposit", "Lock", "BuyPad", "Merge", "Steal", "Rebirth" }

describe("Tutorial.STEPS", function()
	it("follows the CONTRACT §8.3 order", function()
		local ids = {}
		for i, step in Tutorial.STEPS do
			ids[i] = step.id
		end
		expect(table.concat(ids, ",")).toBe(table.concat(V13, ","))
	end)
	it("has non-empty text for every step, and copy for every legacy id", function()
		for _, step in Tutorial.STEPS do
			expect(#step.title > 0 and #step.body > 0).toBe(true)
		end
		for _, id in Tutorial.LEGACY_IDS do
			expect(Tutorial.find(id)).toBeTruthy()
		end
	end)
	it("teaches the lock (LOCKED / UNLOCKED) and buying pads", function()
		local lock = Tutorial.find("Lock") :: Tutorial.Step
		expect(string.find(lock.body, "LOCKED", 1, true) ~= nil).toBe(true)
		expect(string.find(lock.body, "UNLOCKED", 1, true) ~= nil).toBe(true)
		local pad = Tutorial.find("BuyPad") :: Tutorial.Step
		expect(pad.title).toBe("Buy a pad")
		expect(string.find(pad.body, "Buy pad", 1, true) ~= nil).toBe(true)
	end)
end)

describe("Tutorial copy matches the real prompts (v15 playtest)", function()
	local function body(id: string): string
		return (Tutorial.find(id) :: Tutorial.Step).body
	end
	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end
	it("Grab is a tap / E press, and explains Grab vs Buy $X", function()
		local grab = body("Grab")
		expect(has(string.lower(grab), "hold")).toBe(false)
		expect(has(grab, "press E")).toBe(true)
		expect(has(grab, "tap")).toBe(true)
		expect(has(grab, '"Grab"')).toBe(true)
		expect(has(grab, '"Buy $X"')).toBe(true)
	end)
	it("names the prompts players actually see", function()
		expect(has(body("Deposit"), "no button needed")).toBe(true)
		expect(has(body("Lock"), '"Lock base"')).toBe(true)
		expect(has(body("BuyPad"), '"Buy pad $X"')).toBe(true)
		expect(has(body("Steal"), 'hold E on "Steal"')).toBe(true)
		expect(has(body("Steal"), "bat")).toBe(true)
	end)
	it("fits the overlay card (about three lines)", function()
		for _, step in Tutorial.STEPS do
			expect(#step.body <= 160).toBe(true)
		end
	end)
end)

describe("Tutorial.stepOf", function()
	it("reads an optional numeric state.tutorialStep", function()
		expect(Tutorial.stepOf({ tutorialStep = 2 })).toBe(2)
		expect(Tutorial.stepOf({ tutorialStep = 2.7 })).toBe(2)
		expect(Tutorial.stepOf({})).toBeNil()
		expect(Tutorial.stepOf({ tutorialStep = "2" })).toBeNil()
		expect(Tutorial.stepOf({ tutorialStep = 0 / 0 })).toBeNil()
		expect(Tutorial.stepOf(nil)).toBeNil()
	end)
end)

describe("Tutorial.view", function()
	it("returns title, body and a counter for valid steps", function()
		local view = Tutorial.view(1) :: Tutorial.StepView
		expect(view.title).toBe(Tutorial.STEPS[1].title)
		expect(view.counter).toBe(`Step 1 of {#Tutorial.STEPS}`)
		expect((Tutorial.view(#Tutorial.STEPS) :: Tutorial.StepView).index).toBe(#Tutorial.STEPS)
	end)
	it("hides before the first and after the last step", function()
		expect(Tutorial.view(nil)).toBeNil()
		expect(Tutorial.view(0)).toBeNil()
		expect(Tutorial.view(#Tutorial.STEPS + 1)).toBeNil()
	end)
end)

describe("Tutorial.fromState", function()
	it("prefers tutorialStepId (v13)", function()
		local view = Tutorial.fromState({ tutorialStep = 4, tutorialStepId = "BuyPad" }) :: Tutorial.StepView
		expect(view.id).toBe("BuyPad")
		expect(view.counter).toBe("Step 4 of 7")
		expect(Tutorial.fromState({ tutorialStep = 4, tutorialStepId = "Nope" })).toBeNil()
	end)
	it("reads a v12 numeric step in the old 6-step order", function()
		local view = Tutorial.fromState({ tutorialStep = 4 }) :: Tutorial.StepView
		expect(view.id).toBe("Merge")
		expect(view.counter).toBe("Step 4 of 6")
		expect(Tutorial.fromState({ tutorialStep = 7 })).toBeNil()
	end)
	it("shows nothing when finished", function()
		expect(Tutorial.fromState({})).toBeNil()
		expect(Tutorial.fromState(nil)).toBeNil()
	end)
end)

describe("Tutorial device wording", function()
	local function body(id: string, kind: Tutorial.Kind): string
		return (Tutorial.viewById(id, kind) :: Tutorial.StepView).body
	end
	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end
	it("keyboard is the default and holds E for the hold prompts", function()
		expect(body("Lock", "keyboard")).toBe((Tutorial.find("Lock") :: Tutorial.Step).body)
		expect(Tutorial.fromState({ tutorialStepId = "Lock" }).body).toBe(body("Lock", "keyboard"))
		expect(has(body("Lock", "keyboard"), 'Hold E on "Lock base"')).toBe(true)
		expect(has(body("BuyPad", "keyboard"), 'Hold E on "Buy pad $X"')).toBe(true)
		expect(has(body("Merge", "keyboard"), "Hold E at the merge vat")).toBe(true)
		expect(has(body("Steal", "keyboard"), 'hold E on "Steal"')).toBe(true)
	end)
	it("touch taps and holds the prompt, gamepad uses X", function()
		expect(has(body("Grab", "touch"), "tap the prompt")).toBe(true)
		expect(has(body("Lock", "touch"), 'Tap and hold the prompt on "Lock base"')).toBe(true)
		expect(has(body("Steal", "touch"), 'tap and hold the prompt on "Steal"')).toBe(true)
		expect(has(body("Grab", "gamepad"), "press X")).toBe(true)
		expect(has(body("Lock", "gamepad"), 'Hold X on "Lock base"')).toBe(true)
		expect(has(body("Merge", "gamepad"), "Hold X at the merge vat")).toBe(true)
		expect(has(body("Steal", "gamepad"), 'hold X on "Steal"')).toBe(true)
	end)
	it("no key name leaks into the other devices and no placeholder is left", function()
		for _, step in Tutorial.STEPS do
			expect(has(step.bodies.touch, " E")).toBe(false)
			expect(has(step.bodies.gamepad, " E ")).toBe(false)
			for _, kind in Tutorial.KINDS do
				expect(string.find(step.bodies[kind], "{", 1, true)).toBeNil()
				expect(#step.bodies[kind] <= 160).toBe(true)
			end
		end
	end)
	it("only the prompt wording differs between devices", function()
		for _, id in { "Deposit", "Rebirth" } do
			expect(body(id, "touch")).toBe(body(id, "keyboard"))
			expect(body(id, "gamepad")).toBe(body(id, "keyboard"))
		end
	end)
end)
