--!strict
-- The tutorial steps TutorialService finishes: Leaderboard (standing near the board), Guide (Talk) and skipping.
local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local GameLoop = require("../src/server/GameLoop")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")
local TutorialProgress = require("../src/shared/TutorialProgress")
local TutorialService = require("../src/server/TutorialService")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

local BOARD = { X = 100, Y = 4, Z = -40 }

local function ctxAt(position: { X: number, Y: number, Z: number }?)
	return {
		pose = function(_userId: number)
			return position, nil
		end,
		propPosition = function(_name: string)
			return BOARD
		end,
	}
end

local function onStep(name: string)
	local world = ServerFixtures.world()
	local s = ServerFixtures.join(world, 1)
	s.data.tutorialStep = TutorialProgress.indexOf(name) :: number
	s.data.padsUnlocked = Config.PADS_START -- BuyPad not done yet
	return world, s
end

describe("tutorial Leaderboard step", function()
	it("finishes when the player stands within the radius of the board, height ignored", function()
		local world, s = onStep("Leaderboard")
		local r = Config.TUTORIAL_LEADERBOARD_RADIUS
		TutorialService.tick(world, ctxAt({ X = BOARD.X + r + 1, Y = 4, Z = BOARD.Z }))
		expect(TutorialProgress.currentId(s.data)).toBe("Leaderboard")
		TutorialService.tick(world, ctxAt({ X = BOARD.X + r - 1, Y = 40, Z = BOARD.Z }))
		expect(TutorialProgress.currentId(s.data)).toBe("Guide")
	end)

	it("runs from the game loop's one-second tick", function()
		local world, s = onStep("Leaderboard")
		local ctx = ctxAt({ X = BOARD.X, Y = 4, Z = BOARD.Z })
		GameLoop.step(world, T0 + 1, ctx :: any)
		GameLoop.step(world, T0 + 2, ctx :: any)
		expect(TutorialProgress.currentId(s.data)).toBe("Guide")
	end)

	it("does nothing without positions, or on another step", function()
		local world, s = onStep("Leaderboard")
		TutorialService.tick(world, nil)
		TutorialService.tick(world, ctxAt(nil))
		expect(TutorialProgress.currentId(s.data)).toBe("Leaderboard")
		s.data.tutorialStep = TutorialProgress.indexOf("Lock") :: number
		TutorialService.tick(world, ctxAt({ X = BOARD.X, Y = 4, Z = BOARD.Z }))
		expect(TutorialProgress.currentId(s.data)).toBe("Lock")
	end)
end)

describe("tutorial Guide step", function()
	it("finishes when the player talks to the Guide, and only on that step", function()
		local world, s = onStep("Lock")
		TutorialService.talkedToGuide(world, 1)
		expect(TutorialProgress.currentId(s.data)).toBe("Lock")
		s.data.tutorialStep = TutorialProgress.indexOf("Guide") :: number
		TutorialService.talkedToGuide(world, 1)
		expect(TutorialProgress.currentId(s.data)).toBe("BuyPad")
		TutorialService.talkedToGuide(world, 99) -- nobody: no error
	end)
end)

describe("Request SkipTutorial", function()
	it("ends the tutorial without a reward and refuses once it is over", function()
		local world, s = onStep("Merge")
		local cash = s.data.cash
		local res = Actions.handle(world, 1, "SkipTutorial", {}, T0, {} :: any)
		expect(res.ok).toBe(true)
		expect(s.data.tutorialStep).toBe(0)
		expect(s.data.cash).toBe(cash)
		s.limiter = {}
		expect(Actions.handle(world, 1, "SkipTutorial", {}, T0 + 5, {} :: any).ok).toBe(false)
	end)
end)
