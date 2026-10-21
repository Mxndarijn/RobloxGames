--!strict
-- The key card over a pad slime (src/ui/SlimeKeyCard.luau): row order and key chip texts. The live card is checked
-- in a Studio playtest.
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local SlimeKeyCard = UiHarness.ui("SlimeKeyCard")

local function nameOf(p: any): string
	return p.Name
end

describe("SlimeKeyCard", function()
	it("orders the rows Hatch, Move, Favorite, Sell and leaves other prompts out", function()
		local list = {
			{ Name = "SellPrompt" },
			{ Name = "GrabPrompt" },
			{ Name = "MovePrompt" },
			{ Name = "HatchPrompt" },
			{ Name = "FavoritePrompt" },
		}
		local names = {}
		for _, p in SlimeKeyCard.ordered(list, nameOf) do
			table.insert(names, p.Name)
		end
		expect(table.concat(names, ",")).toBe("HatchPrompt,MovePrompt,FavoritePrompt,SellPrompt")
	end)
	it("shows the keyboard key, or the gamepad button's short name", function()
		expect(SlimeKeyCard.keyLabel("E", false)).toBe("E")
		expect(SlimeKeyCard.keyLabel("ButtonX", true)).toBe("X")
		expect(SlimeKeyCard.keyLabel("DPadUp", true)).toBe("Up")
		expect(SlimeKeyCard.keyLabel("DPadDown", true)).toBe("Dn")
	end)
end)
