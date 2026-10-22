--!strict
-- The key card over a pad slime (src/ui/SlimeKeyCard.luau): row order, key chip texts and the Goo card the real
-- module draws for shown prompts. The live card is checked in a Studio playtest.
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")
local roblox = require("@lune/roblox") :: any

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

	it("draws a glass card with a glass row per prompt and jelly key chips: E mint, R gold, X pink", function()
		local Theme = UiHarness.ui("Widgets").Theme
		local handlers: { [string]: { (...any) -> () } } = {}
		local function signal(name: string): any
			handlers[name] = {}
			return {
				Connect = function(_self: any, fn: (...any) -> ())
					table.insert(handlers[name], fn)
					return { Disconnect = function() end }
				end,
			}
		end
		local service = {
			PromptShown = signal("PromptShown"),
			PromptHidden = signal("PromptHidden"),
			PromptButtonHoldBegan = signal("PromptButtonHoldBegan"),
			PromptButtonHoldEnded = signal("PromptButtonHoldEnded"),
		}
		local body = UiHarness.Instance.new("Part")
		body.Name = "Body"
		local grab = UiHarness.Instance.new("ProximityPrompt")
		grab.Name = "GrabPrompt"
		grab.ObjectText = "Common Mochi"
		grab.Parent = body
		local function prompt(name: string, key: string, action: string, hold: number): any
			local p = UiHarness.Instance.new("ProximityPrompt")
			p.Name = name
			p.KeyboardKeyCode = (roblox.Enum.KeyCode :: any)[key]
			p.ActionText = action
			p.HoldDuration = hold
			p.Style = roblox.Enum.ProximityPromptStyle.Custom
			p.Parent = body
			return p
		end
		local shown = {
			prompt("MovePrompt", "E", "Move", 0),
			prompt("FavoritePrompt", "R", "Favorite", 0),
			prompt("SellPrompt", "X", "Sell $45", 1),
		}
		local playerGui = UiHarness.Instance.new("Folder")
		local stop = SlimeKeyCard.start({ prompts = service :: any, playerGui = playerGui, tweens = {} :: any })
		for _, p in shown do
			for _, fn in handlers.PromptShown do
				fn(p, roblox.Enum.ProximityPromptInputType.Keyboard)
			end
		end
		local card = playerGui:FindFirstChild("SlimeKeyCard")
		expect(card.Enabled).toBe(true)
		local frame = card:FindFirstChild("Card")
		expect(frame.BackgroundColor3).toBe(Theme.Bg)
		expect(frame:FindFirstChildOfClass("UIStroke").Color).toBe(Theme.Ink)
		expect(frame:FindFirstChild("Title").Text).toBe("Common Mochi")
		local want = { MovePrompt = Theme.Good, FavoritePrompt = Theme.Gold, SellPrompt = Theme.Bad }
		for name, color in want do
			local row = frame:FindFirstChild(name)
			expect(row.BackgroundColor3).toBe(Theme.Glass)
			local chip = row:FindFirstChild("Key")
			expect(chip.BackgroundColor3).toBe(color)
			expect(chip:FindFirstChild("Shine")).toBeNil()
			expect(chip:FindFirstChildOfClass("UIStroke").Color).toBe(Theme.Ink)
			-- only the hold prompt says "Hold"
			expect(row:FindFirstChild("Hint") ~= nil).toBe(name == "SellPrompt")
		end
		expect(frame:FindFirstChild("SellPrompt"):FindFirstChild("Key"):FindFirstChild("KeyText").Text).toBe("X")
		stop()
		expect(playerGui:FindFirstChild("SlimeKeyCard")).toBeNil()
	end)
end)
