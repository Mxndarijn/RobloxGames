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

-- An event whose handlers the test runs itself.
local function fakeSignal(): any
	local s = { handlers = {} :: { (...any) -> () } }
	function s.Connect(_self: any, fn: (...any) -> ()): any
		table.insert(s.handlers, fn)
		return {
			Disconnect = function()
				local i = table.find(s.handlers, fn)
				if i then
					table.remove(s.handlers, i)
				end
			end,
		}
	end
	function s.fire(...: any)
		for _, fn in table.clone(s.handlers) do
			fn(...)
		end
	end
	return s
end

-- A hold prompt on a slime Body that counts InputHoldBegin / InputHoldEnd.
local function holdPrompt(name: string, body: any): any
	local p = {
		Name = name,
		Style = roblox.Enum.ProximityPromptStyle.Custom,
		Parent = body,
		Changed = fakeSignal(),
		ActionText = name,
		ObjectText = "",
		HoldDuration = 0.8,
		KeyboardKeyCode = roblox.Enum.KeyCode.X,
		GamepadKeyCode = roblox.Enum.KeyCode.ButtonX,
		begins = 0,
		ends = 0,
	}
	function p.InputHoldBegin(self: any)
		self.begins += 1
	end
	function p.InputHoldEnd(self: any)
		self.ends += 1
	end
	return p
end

-- A started card with fake prompt service, UserInputService, clock and tweens (each Create recorded).
local function startCard(): any
	local env = {
		playerGui = UiHarness.root(),
		body = UiHarness.Instance.new("Part"),
		service = {
			PromptShown = fakeSignal(),
			PromptHidden = fakeSignal(),
			PromptButtonHoldBegan = fakeSignal(),
			PromptButtonHoldEnded = fakeSignal(),
		},
		userInput = { InputEnded = fakeSignal() },
		now = 0,
		tweens = {} :: { { instance: any, time: number } },
	}
	env.stop = SlimeKeyCard.start({
		prompts = env.service :: any,
		playerGui = env.playerGui,
		userInput = env.userInput :: any,
		clock = function()
			return env.now
		end,
		tweens = {
			Create = function(_self: any, instance: any, info: any)
				table.insert(env.tweens, { instance = instance, time = info.Time or info[1] })
				return { Play = function() end, Cancel = function() end }
			end,
		} :: any,
	})
	function env.show(p: any)
		env.service.PromptShown.fire(p, roblox.Enum.ProximityPromptInputType.Keyboard)
	end
	function env.row(name: string): any
		return UiHarness.find(env.playerGui, name)
	end
	return env
end

-- A mouse or touch press whose state the test moves to End.
local function press(kind: string): any
	return {
		UserInputType = roblox.Enum.UserInputType[kind],
		UserInputState = roblox.Enum.UserInputState.Begin,
		Changed = fakeSignal(),
	}
end

local function release(input: any)
	input.UserInputState = roblox.Enum.UserInputState.End
	input.Changed.fire("UserInputState")
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

	it("ends a click/tap hold when its prompt is hidden, so it cannot Sell after the release", function()
		local env = startCard()
		local sell = holdPrompt("SellPrompt", env.body)
		env.show(sell)
		local input = press("MouseButton1")
		UiHarness.fire(env.row("SellPrompt"), "InputBegan", input)
		expect(sell.begins).toBe(1)
		env.service.PromptHidden.fire(sell)
		expect(sell.ends).toBe(1)
		-- the release after that ends nothing more
		release(input)
		expect(sell.ends).toBe(1)
		-- a normal press + release over the row ends once, not twice
		env.show(sell)
		local touch = press("Touch")
		UiHarness.fire(env.row("SellPrompt"), "InputBegan", touch)
		UiHarness.fire(env.row("SellPrompt"), "InputEnded", touch)
		release(touch)
		expect(sell.ends).toBe(2)
		env.stop()
		expect(sell.ends).toBe(2)
	end)

	it("carries a click/tap hold over a redraw: no InputHoldEnd, the fill resumes, the release ends it once", function()
		local env = startCard()
		local sell = holdPrompt("SellPrompt", env.body)
		env.show(sell)
		local input = press("MouseButton1")
		UiHarness.fire(env.row("SellPrompt"), "InputBegan", input)
		env.service.PromptButtonHoldBegan.fire(sell)
		local oldRow = env.row("SellPrompt")
		-- halfway through the hold the price changes and the card redraws
		env.now = 0.4
		sell.ActionText = "Sell $50"
		sell.Changed.fire("ActionText")
		local newRow = env.row("SellPrompt")
		expect(newRow ~= oldRow).toBe(true)
		expect(sell.ends).toBe(0)
		expect(newRow:FindFirstChild("Fill").Size.X.Scale).toBe(0.5)
		local last = env.tweens[#env.tweens]
		expect(last.instance).toBe(newRow:FindFirstChild("Fill"))
		expect(math.abs(last.time - 0.4) < 1e-9).toBe(true)
		-- another prompt showing up redraws too; the hold still carries on
		local move = holdPrompt("MovePrompt", env.body)
		move.HoldDuration = 0
		env.show(move)
		expect(sell.ends).toBe(0)
		-- the release ends it exactly once, however many release signals arrive
		release(input)
		expect(sell.ends).toBe(1)
		env.userInput.InputEnded.fire(input)
		UiHarness.fire(env.row("SellPrompt"), "InputEnded", input)
		expect(sell.ends).toBe(1)
		expect(sell.begins).toBe(1)
		env.stop()
		expect(sell.ends).toBe(1)
	end)

	it("ends a held prompt that a redraw no longer shows, and keeps the card for the rest", function()
		local env = startCard()
		local sell = holdPrompt("SellPrompt", env.body)
		local move = holdPrompt("MovePrompt", env.body)
		move.HoldDuration = 0
		env.show(move)
		env.show(sell)
		UiHarness.fire(env.row("SellPrompt"), "InputBegan", press("Touch"))
		env.service.PromptHidden.fire(sell)
		expect(sell.ends).toBe(1)
		expect(env.row("SellPrompt")).toBeNil()
		expect(env.row("MovePrompt") ~= nil).toBe(true)
		env.stop()
		expect(sell.ends).toBe(1)
	end)

	it("ends a tap hold released off the card (UserInputService.InputEnded)", function()
		local env = startCard()
		local sell = holdPrompt("SellPrompt", env.body)
		env.show(sell)
		local touch = { UserInputType = roblox.Enum.UserInputType.Touch }
		UiHarness.fire(env.row("SellPrompt"), "InputBegan", touch)
		env.userInput.InputEnded.fire({ UserInputType = roblox.Enum.UserInputType.Touch })
		expect(sell.ends).toBe(0) -- another finger
		env.userInput.InputEnded.fire(touch)
		expect(sell.ends).toBe(1)
		env.stop()
		expect(sell.ends).toBe(1)
	end)
end)
