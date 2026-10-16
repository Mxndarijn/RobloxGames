--!strict
-- B1: important actions need a HOLD, not a tap. Server prompts (Config.HOLD_CONFIRM_SECONDS
-- on every steal / buy / lock / pad / merge / claim prompt) and UI buttons (Widgets.holdButton
-- with a visible HoldFill). Instant on purpose: Open Shop, Talk, and a FREE Grab of a wild
-- slime (costs nothing, takes nothing from anyone). Server checks are unchanged.
local fs = require("@lune/fs")

local Carry = require("../../src/server/Carry")
local Config = require("../../src/shared/Config")
local Fixtures = require("../Fixtures")
local Scene = require("../../src/server/Scene")
local ServerFixtures = require("../ServerFixtures")
local Spawner = require("../../src/server/Spawner")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

local function read(path: string): string
	return fs.readFile(path)
end

-- Every `HoldDuration = <rhs>` in a source file.
local function holdAssignments(path: string): { string }
	local out = {}
	for rhs in string.gmatch(read(path), "HoldDuration = ([^\n]+)") do
		table.insert(out, rhs)
	end
	return out
end

describe("B1: hold-to-confirm prompts", function()
	it("the constant is between 0.6 and 1.0 seconds", function()
		expect(Config.HOLD_CONFIRM_SECONDS >= 0.6).toBe(true)
		expect(Config.HOLD_CONFIRM_SECONDS <= 1.0).toBe(true)
	end)
	it("buying or stealing a slime needs the hold; only a free grab is instant", function()
		expect(Carry.holdDuration(nil)).toBe(Config.HOLD_CONFIRM_SECONDS)
		expect(Carry.holdDuration(40)).toBe(Config.HOLD_CONFIRM_SECONDS)
		expect(Carry.holdDuration(0)).toBe(0)
	end)
	it("every scene entry's prompt hold matches its text (Steal / Buy >= 0.6, Grab 0)", function()
		local world = ServerFixtures.world()
		local id = Spawner.spawnOne(world, T0)
		world.wild[id].price = 40
		ServerFixtures.join(world, 1, { Fixtures.slime("a") })
		for _, e in Scene.describe(world, T0) do
			if e.promptText == "Grab" then
				expect(e.promptHold).toBe(0)
			else
				expect(e.promptHold >= 0.6).toBe(true)
			end
		end
	end)
	it("slime, plot (Lock / Merge / BuyPad) and Claim prompts all take the constant, never a literal", function()
		local view = holdAssignments("src/server/WorldView.luau")
		expect(#view).toBe(4) -- slime (initial), slime (reconcile), plot prompts, claim prompt
		for _, rhs in view do
			expect(string.find(rhs, "HOLD_CONFIRM_SECONDS", 1, true) ~= nil or rhs == "entry.promptHold").toBe(true)
		end
	end)
	it("only Open Shop and Talk (no cost, no steal) stay instant", function()
		local props = holdAssignments("src/server/WorldProps.luau")
		expect(#props).toBe(1)
		expect(props[1]).toBe("0")
		local src = read("src/server/WorldProps.luau")
		local names = {}
		for name in string.gmatch(src, "name = Constants%.([%w_]+)") do
			table.insert(names, name)
		end
		table.sort(names)
		expect(table.concat(names, ",")).toBe("GUIDE_PROMPT_NAME,SHOP_PROMPT_NAME")
	end)
end)

describe("B1: hold-to-confirm buttons", function()
	local function importantButtons(path: string, name: string): string?
		-- The constructor used for the button whose props contain Name = "<name>".
		local src = read(path)
		local at = string.find(src, `Name = "{name}"`, 1, true)
		expect(at ~= nil).toBe(true)
		local ctor
		for c in string.gmatch(string.sub(src, 1, at :: number), "Widgets%.(%w+)%(") do
			ctor = c
		end
		return ctor
	end
	it("HUD Lock / Extend and Buy next pad, Sell, Rebirth, shop Buy and Merge use Widgets.holdButton", function()
		expect(importantButtons("src/ui/Hud.luau", "Lock")).toBe("holdButton")
		expect(importantButtons("src/ui/Hud.luau", "BuyPad")).toBe("holdButton")
		expect(importantButtons("src/ui/Panels/Plot.luau", "Sell")).toBe("holdButton")
		-- Appraise rerolls spend cash: both popup buttons are built by popupButton -> holdButton.
		expect(importantButtons("src/ui/Panels/Plot.luau", "Appraise")).toBe("button") -- opener is free
		local plot = read("src/ui/Panels/Plot.luau")
		local popupFn = string.match(plot, "local function popupButton.-\n\tend\n")
		expect(popupFn ~= nil and string.find(popupFn, "Widgets.holdButton(", 1, true) ~= nil).toBe(true)
		expect(importantButtons("src/ui/Panels/Rebirth.luau", "RebirthButton")).toBe("holdButton")
		expect(importantButtons("src/ui/Panels/Shop.luau", "Buy")).toBe("holdButton")
		expect(importantButtons("src/ui/Panels/Merge.luau", "MergeButton")).toBe("holdButton")
	end)
	it("the two-click confirmButton is gone", function()
		expect(string.find(read("src/ui/Widgets.luau"), "confirmButton", 1, true)).toBeNil()
	end)
	it("a built hold button carries the hold seconds and a HoldFill bar that starts empty and hidden", function()
		local Widgets = UiHarness.ui("Widgets")
		local btn = Widgets.holdButton({ Name = "T" }, nil, function() end, Config.HOLD_CONFIRM_SECONDS)
		expect(btn.instance:GetAttribute("HoldConfirm")).toBe(Config.HOLD_CONFIRM_SECONDS)
		local fill = btn.instance:FindFirstChild("HoldFill")
		expect(fill ~= nil).toBe(true)
		expect(fill.Visible).toBe(false)
		expect(fill.Size.X.Scale).toBe(0)
	end)
	it("hold progress runs 0 -> 1 over the duration", function()
		local Widgets = UiHarness.ui("Widgets")
		expect(Widgets.holdProgress(10, 10, 0.8)).toBe(0)
		expect(Widgets.holdProgress(10, 10.4, 0.8)).toBeCloseTo(0.5)
		expect(Widgets.holdProgress(10, 12, 0.8)).toBe(1)
	end)
	it("the real Rebirth button is a hold button", function()
		local Rebirth = UiHarness.ui("Panels/Rebirth")
		local panel = Rebirth.new(UiHarness.root(), {
			Config = Config,
			send = function() end,
		})
		local button = UiHarness.find(panel.frame, "RebirthButton")
		expect(button:GetAttribute("HoldConfirm") >= 0.6).toBe(true)
		expect(button:FindFirstChild("HoldFill") ~= nil).toBe(true)
	end)
end)
