--!strict
-- The tutorial notice cards above the hotbar (src/ui/TutorialCard.luau): the step card and its Hide button,
-- the mint done card between steps and the "Tutorial done" card at the end.
local TestRunner = require("../TestRunner")
local Tutorial = require("../../src/ui/Tutorial")
local UiHarness = require("./UiHarness")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local TutorialCard = UiHarness.ui("TutorialCard")

local GRAB = { tutorialStepId = "Grab" }
local DEPOSIT = { tutorialStepId = "Deposit" }

local function newCard(): any
	return UiHarness.ui("TutorialCard").new(UiHarness.root(), {}, 2)
end

local function stepCard(card: any): any
	return UiHarness.find(card.frame, "Step")
end

local function doneCard(card: any): any
	return UiHarness.find(card.frame, "Done")
end

local function hide(card: any)
	UiHarness.fire(UiHarness.find(stepCard(card), "Hide"), "Activated")
end

-- Runs `body` on the virtual clock (os.clock in loaded modules follows UiHarness.advance).
local function onVirtualTime(body: () -> ())
	UiHarness.virtualTime(true)
	local ok, err = pcall(body)
	UiHarness.virtualTime(false)
	if not ok then
		error(err, 0)
	end
end

describe("TutorialCard step card", function()
	it("starts hidden and shows the step's icon, title, hint and counter", function()
		local card = newCard()
		expect(card.frame.Visible).toBe(false)
		card.update({ tutorialStepId = "BuyPad" })
		local view = Tutorial.viewById("BuyPad") :: Tutorial.StepView
		local step = stepCard(card)
		expect(card.frame.Visible).toBe(true)
		expect(step.Visible).toBe(true)
		expect(UiHarness.find(step, "Icon").Text).toBe(view.icon)
		expect(UiHarness.find(step, "Title").Text).toBe(view.title)
		expect(UiHarness.find(step, "Sub").Text).toBe(view.body)
		expect(UiHarness.find(step, "Counter").Text).toBe(view.counter)
		expect(card.shown()).toBe(true)
		expect(card.hidden()).toBe(false)
	end)
	it("shows nothing with no tutorial running", function()
		local card = newCard()
		card.update({})
		expect(card.frame.Visible).toBe(false)
		expect(card.shown()).toBe(false)
		expect(card.hidden()).toBe(false)
		card.update(nil)
		expect(card.frame.Visible).toBe(false)
	end)
	it("the hint follows the last input device", function()
		local card = newCard()
		card.update(GRAB)
		local sub = UiHarness.find(stepCard(card), "Sub")
		expect(sub.Text).toBe((Tutorial.find("Grab") :: Tutorial.Step).bodies.keyboard)
		local before = UiHarness.lastInputType
		UiHarness.lastInputType = roblox.Enum.UserInputType.Touch
		for _, handler in table.clone(UiHarness.userInput.LastInputTypeChanged.handlers) do
			handler(UiHarness.lastInputType)
		end
		expect(sub.Text).toBe((Tutorial.find("Grab") :: Tutorial.Step).bodies.touch)
		UiHarness.lastInputType = before
		card.update(GRAB)
		expect(sub.Text).toBe((Tutorial.find("Grab") :: Tutorial.Step).bodies.keyboard)
	end)
end)

describe("TutorialCard Hide", function()
	it("the card itself takes no taps; Hide puts the whole card away", function()
		local card = newCard()
		card.update(GRAB)
		local step = stepCard(card)
		for _, d in step:GetDescendants() do
			if d:IsA("GuiButton") then
				expect(d.Name == "Hide" or d.Name == "HideButton").toBe(true)
			end
		end
		expect(UiHarness.find(step, "HideButton").Text).toBe(TutorialCard.HIDE_TEXT)
		hide(card)
		expect(step.Visible).toBe(false)
		expect(card.frame.Visible).toBe(false)
		expect(card.hidden()).toBe(true)
		expect(card.shown()).toBe(false)
		card.update(GRAB) -- a State push on the same step keeps it hidden
		expect(card.hidden()).toBe(true)
		expect(card.frame.Visible).toBe(false)
	end)
	it("the Hide pill hides it too", function()
		local card = newCard()
		card.update(GRAB)
		UiHarness.fire(UiHarness.find(stepCard(card), "HideButton"), "Activated")
		expect(card.hidden()).toBe(true)
	end)
	it("showAgain brings a hidden card back, and it stays on the next push", function()
		local card = newCard()
		card.update(GRAB)
		hide(card)
		card.showAgain()
		expect(card.hidden()).toBe(false)
		expect(stepCard(card).Visible).toBe(true)
		card.update(GRAB)
		expect(card.hidden()).toBe(false)
	end)
	it("showAgain under an open menu shows the card once the menu closes", function()
		local card = newCard()
		card.update(GRAB)
		hide(card)
		card.setMenuOpen(true)
		card.showAgain()
		expect(card.frame.Visible).toBe(false)
		card.setMenuOpen(false)
		expect(card.frame.Visible).toBe(true)
		expect(stepCard(card).Visible).toBe(true)
	end)
	it("a new step shows again; nothing counts as hidden once the tutorial is done", function()
		local card = newCard()
		card.update(GRAB)
		hide(card)
		card.update(DEPOSIT)
		expect(card.hidden()).toBe(false)
		expect(card.shown()).toBe(true)
		expect(stepCard(card).Visible).toBe(true)
		hide(card)
		card.update({})
		expect(card.hidden()).toBe(false)
		expect(card.shown()).toBe(false)
	end)
end)

describe("TutorialCard done cards", function()
	it("a step change shows the finished step's done line for a moment", function()
		onVirtualTime(function()
			local card = newCard()
			card.update(GRAB)
			expect(doneCard(card).Visible).toBe(false)
			card.update(DEPOSIT)
			local done = doneCard(card)
			expect(done.Visible).toBe(true)
			expect(UiHarness.find(done, "Title").Text).toBe((Tutorial.find("Grab") :: Tutorial.Step).done)
			expect(UiHarness.find(done, "Sub").Visible).toBe(false)
			expect(stepCard(card).Visible).toBe(true) -- the next step shows under it
			expect(card.finishedShowing()).toBe(false)
			UiHarness.advance(TutorialCard.DONE_SECONDS + 0.1)
			card.tick(0)
			expect(done.Visible).toBe(false)
			expect(stepCard(card).Visible).toBe(true)
		end)
	end)
	it("the first State on join shows no done card", function()
		local card = newCard()
		card.update({ tutorialStepId = "Merge" })
		expect(doneCard(card).Visible).toBe(false)
	end)
	it("after the last step the Tutorial done card shows with its pointer to Goals, then goes", function()
		onVirtualTime(function()
			local last = Tutorial.STEPS[#Tutorial.STEPS].id
			local card = newCard()
			card.update({ tutorialStepId = last })
			card.update({})
			local done = doneCard(card)
			expect(card.frame.Visible).toBe(true)
			expect(stepCard(card).Visible).toBe(false)
			expect(done.Visible).toBe(true)
			expect(UiHarness.find(done, "Title").Text).toBe(Tutorial.FINISHED)
			expect(UiHarness.find(done, "Sub").Text).toBe(Tutorial.FINISHED_SUB)
			expect(card.finishedShowing()).toBe(true)
			UiHarness.advance(TutorialCard.FINISHED_SECONDS + 0.1)
			card.tick(0)
			expect(card.finishedShowing()).toBe(false)
			expect(card.frame.Visible).toBe(false)
		end)
	end)
	it("a skipped tutorial ends without the Tutorial done card", function()
		local card = newCard()
		card.update({ tutorialStepId = "Lock" })
		card.skipping()
		card.update({})
		expect(card.frame.Visible).toBe(false)
		expect(card.finishedShowing()).toBe(false)
	end)
	it("done cards hide while a menu is open", function()
		onVirtualTime(function()
			local card = newCard()
			card.update(GRAB)
			card.update(DEPOSIT)
			card.setMenuOpen(true)
			expect(card.frame.Visible).toBe(false)
			card.setMenuOpen(false)
			expect(doneCard(card).Visible).toBe(true)
		end)
	end)
	it("the Tutorial done card waits behind a popup and still shows its full time after", function()
		onVirtualTime(function()
			local card = newCard()
			card.update({ tutorialStepId = Tutorial.STEPS[#Tutorial.STEPS].id })
			card.update({})
			card.setMenuOpen(true) -- the daily popup opens as the tutorial ends
			for _ = 1, 20 do
				UiHarness.advance(TutorialCard.FINISHED_SECONDS / 10)
				card.tick(0)
			end
			card.setMenuOpen(false)
			card.tick(0)
			expect(card.finishedShowing()).toBe(true)
			expect(doneCard(card).Visible).toBe(true)
			UiHarness.advance(TutorialCard.FINISHED_SECONDS + 0.1)
			card.tick(0)
			expect(card.finishedShowing()).toBe(false)
		end)
	end)
end)
