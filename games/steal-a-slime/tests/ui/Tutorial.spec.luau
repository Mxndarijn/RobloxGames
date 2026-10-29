--!strict
-- Tutorial card text (src/ui/Tutorial.luau): one step per TutorialProgress step, wording per device.
local TestRunner = require("../TestRunner")
local Tutorial = require("../../src/ui/Tutorial")
local TutorialProgress = require("../../src/shared/TutorialProgress")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function body(id: string, kind: Tutorial.Kind?, key: string?): string
	return (Tutorial.viewById(id, kind, key) :: Tutorial.StepView).body
end

describe("Tutorial.STEPS", function()
	it("has one card per server step, in the server's order", function()
		expect(#Tutorial.STEPS).toBe(#TutorialProgress.STEPS)
		for i, step in Tutorial.STEPS do
			expect(step.id).toBe(TutorialProgress.STEPS[i])
		end
	end)
	it("every step has an icon, a title, a done line and a hint", function()
		for _, step in Tutorial.STEPS do
			expect(#step.icon > 0).toBe(true)
			expect(#step.title > 0).toBe(true)
			expect(#step.done > 0).toBe(true)
			expect(#step.body > 0).toBe(true)
			expect(step.done ~= step.title).toBe(true)
		end
	end)
	it("find knows every step and nothing else", function()
		for _, step in Tutorial.STEPS do
			expect(Tutorial.find(step.id)).toBe(step)
		end
		expect(Tutorial.find("Steal")).toBeNil()
		expect(Tutorial.find("Rebirth")).toBeNil()
	end)
	it("hints stay one short line on the card", function()
		for _, step in Tutorial.STEPS do
			for _, text in Tutorial.texts(step) do
				expect(#text <= 60).toBe(true)
			end
		end
	end)
end)

describe("Tutorial.view / viewById", function()
	it("returns the step with an n/total counter", function()
		local total = #Tutorial.STEPS
		local view = Tutorial.view(1) :: Tutorial.StepView
		expect(view.id).toBe(Tutorial.STEPS[1].id)
		expect(view.title).toBe(Tutorial.STEPS[1].title)
		expect(view.icon).toBe(Tutorial.STEPS[1].icon)
		expect(view.counter).toBe(`1/{total}`)
		local last = Tutorial.view(total) :: Tutorial.StepView
		expect(last.index).toBe(total)
		expect(last.counter).toBe(`{total}/{total}`)
		local pad = Tutorial.viewById("BuyPad") :: Tutorial.StepView
		expect(pad.index).toBe(table.find(TutorialProgress.STEPS, "BuyPad"))
		expect(pad.counter).toBe(`{pad.index}/{total}`)
	end)
	it("is nil before the first step, after the last and for unknown ids", function()
		expect(Tutorial.view(nil)).toBeNil()
		expect(Tutorial.view(0)).toBeNil()
		expect(Tutorial.view(#Tutorial.STEPS + 1)).toBeNil()
		expect(Tutorial.viewById("Nope")).toBeNil()
		expect(Tutorial.viewById(nil)).toBeNil()
		expect(Tutorial.viewById(3)).toBeNil()
	end)
end)

describe("Tutorial.fromState", function()
	it("reads the step id the server sends", function()
		local view = Tutorial.fromState({ tutorialStepId = "Merge" }) :: Tutorial.StepView
		expect(view.id).toBe("Merge")
		expect(view.title).toBe((Tutorial.find("Merge") :: Tutorial.Step).title)
	end)
	it("shows nothing once finished, for an unknown id or a numeric step alone", function()
		expect(Tutorial.fromState({})).toBeNil()
		expect(Tutorial.fromState(nil)).toBeNil()
		expect(Tutorial.fromState({ tutorialStepId = "Done" })).toBeNil()
		expect(Tutorial.fromState({ tutorialStep = 2 })).toBeNil()
	end)
	it("passes the device and key through", function()
		local view = Tutorial.fromState({ tutorialStepId = "Grab" }, "gamepad", "Square") :: Tutorial.StepView
		expect(view.body).toBe(body("Grab", "gamepad", "Square"))
	end)
end)

describe("Tutorial device wording", function()
	it("keyboard is the default and names E", function()
		expect(body("Grab")).toBe((Tutorial.find("Grab") :: Tutorial.Step).body)
		expect(body("Grab", "keyboard")).toBe(body("Grab"))
		expect(has(body("Grab", "keyboard"), "press E")).toBe(true)
		expect(has(body("Guide", "keyboard"), "Press E")).toBe(true)
		expect(has(body("BuyPad", "keyboard"), "Hold E")).toBe(true)
	end)
	it("touch taps / holds the prompt, gamepad uses X", function()
		expect(has(body("Grab", "touch"), "tap the prompt")).toBe(true)
		expect(has(body("BuyPad", "touch"), "Hold the prompt")).toBe(true)
		expect(has(body("Grab", "gamepad"), "press X")).toBe(true)
		expect(has(body("BuyPad", "gamepad"), "Hold X")).toBe(true)
	end)
	it("no key name leaks into another device and no placeholder is left", function()
		for _, step in Tutorial.STEPS do
			-- "E" as a word (the key), not the E of "Earners"
			expect(string.find(step.bodies.touch, "%f[%w]E%f[%W]")).toBeNil()
			expect(string.find(step.bodies.gamepad, "%f[%w]E%f[%W]")).toBeNil()
			for _, kind in Tutorial.KINDS do
				expect(string.find(step.bodies[kind], "{", 1, true)).toBeNil()
			end
		end
	end)
	it("steps without a prompt read the same on every device", function()
		for _, id in { "Deposit", "Lock", "Leaderboard", "BuyItem" } do
			expect(body(id, "touch")).toBe(body(id, "keyboard"))
			expect(body(id, "gamepad")).toBe(body(id, "keyboard"))
		end
	end)
	it("the merge vat and the Guide open at a press, never a hold", function()
		for _, id in { "Merge", "Guide", "Grab" } do
			for _, kind in Tutorial.KINDS do
				expect(has(string.lower(body(id, kind)), "hold")).toBe(false)
			end
		end
	end)
	it("names the prompt's real button: PlayStation shapes and the keyboard layout's own letter", function()
		expect(Tutorial.PROMPT_KEYS.gamepad).toBe("ButtonX")
		expect(Tutorial.gamepadLabel("ButtonX")).toBe("X")
		expect(Tutorial.gamepadLabel("ButtonSquare")).toBe("Square")
		expect(Tutorial.gamepadLabel("ButtonCross")).toBe("Cross")
		expect(Tutorial.gamepadLabel("ButtonL3")).toBe("L3")
		local square = body("BuyPad", "gamepad", "Square")
		expect(has(square, "Hold Square")).toBe(true)
		expect(has(square, " X ")).toBe(false)
		expect(has(body("Grab", "keyboard", "Z"), "press Z")).toBe(true)
	end)
	it("touch ignores a key name", function()
		expect(body("BuyPad", "touch", "Square")).toBe(body("BuyPad", "touch"))
	end)
	it("the card is measured for every device and the longest button name", function()
		local texts = Tutorial.texts(Tutorial.find("BuyPad") :: Tutorial.Step)
		expect(#texts).toBe(#Tutorial.KINDS + 1)
		expect(has(texts[#texts], "Hold Triangle")).toBe(true)
	end)
end)
