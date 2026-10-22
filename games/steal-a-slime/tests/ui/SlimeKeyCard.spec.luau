--!strict
-- The key card over a pad slime (src/ui/SlimeKeyCard.luau): row order and key chip texts. The live card is checked
-- in a Studio playtest.
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")
local roblox = require("@lune/roblox") :: any
local Enum = roblox.Enum

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
	it("clearing the rows ends a hold that started, so it cannot Sell after the release", function()
		local playerGui = UiHarness.root()
		local body = UiHarness.Instance.new("Part")
		local prompt = {
			Name = "SellPrompt",
			Style = Enum.ProximityPromptStyle.Custom,
			Parent = body,
			Changed = {
				Connect = function()
					return { Disconnect = function() end }
				end,
			},
			ActionText = "Sell",
			ObjectText = "",
			HoldDuration = 0.8,
			KeyboardKeyCode = Enum.KeyCode.E,
			GamepadKeyCode = Enum.KeyCode.ButtonA,
			begins = 0,
			ends = 0,
		}
		function prompt.InputHoldBegin(self: any)
			self.begins += 1
		end
		function prompt.InputHoldEnd(self: any)
			self.ends += 1
		end
		local handlers: { [string]: any } = {}
		local service = {}
		for _, name in { "PromptShown", "PromptHidden", "PromptButtonHoldBegan", "PromptButtonHoldEnded" } do
			service[name] = {
				Connect = function(_self: any, fn: any)
					handlers[name] = fn
					return { Disconnect = function() end }
				end,
			}
		end
		local stop = SlimeKeyCard.start({
			prompts = service :: any,
			playerGui = playerGui,
			tweens = {
				Create = function()
					return { Play = function() end, Cancel = function() end }
				end,
			} :: any,
		})
		handlers.PromptShown(prompt, Enum.ProximityPromptInputType.Keyboard)
		local card = UiHarness.find(playerGui, "SellPrompt")
		expect(card ~= nil).toBe(true)
		UiHarness.fire(card, "InputBegan", { UserInputType = Enum.UserInputType.MouseButton1 })
		expect(prompt.begins).toBe(1)
		-- the row is rebuilt (or the card closes) while the press is still down
		handlers.PromptHidden(prompt)
		expect(prompt.ends).toBe(1)
		-- a normal press + release ends once, not twice
		handlers.PromptShown(prompt, Enum.ProximityPromptInputType.Keyboard)
		card = UiHarness.find(playerGui, "SellPrompt")
		UiHarness.fire(card, "InputBegan", { UserInputType = Enum.UserInputType.Touch })
		UiHarness.fire(card, "InputEnded", { UserInputType = Enum.UserInputType.Touch })
		expect(prompt.ends).toBe(2)
		stop()
		expect(prompt.ends).toBe(2)
	end)
end)
