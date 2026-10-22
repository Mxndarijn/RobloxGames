--!strict
-- B1: important actions need a HOLD, not a tap. Server prompts (Config.HOLD_CONFIRM_SECONDS
-- on every steal / buy / lock / pad / merge / claim prompt) and UI buttons (Widgets.holdButton
-- with a visible HoldFill). Instant on purpose: Open Shop, Talk, and a FREE Grab of a wild
-- slime (costs nothing, takes nothing from anyone). Server checks are unchanged.
local Carry = require("../../src/server/Carry")
local Config = require("../../src/shared/Config")
local Fixtures = require("../Fixtures")
local Scene = require("../../src/server/Scene")
local ServerFixtures = require("../ServerFixtures")
local Spawner = require("../../src/server/Spawner")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")
local roblox = require("@lune/roblox") :: any
local Enum = roblox.Enum

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

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
end)

describe("B1: hold-to-confirm buttons", function()
	it("a built hold button carries the hold seconds and a HoldFill bar that starts empty and hidden", function()
		local Widgets = UiHarness.ui("Widgets")
		local btn = Widgets.holdButton({ Name = "T" }, nil, function() end, Config.HOLD_CONFIRM_SECONDS)
		expect(btn.instance:GetAttribute("HoldConfirm")).toBe(Config.HOLD_CONFIRM_SECONDS)
		local fill = btn.instance:FindFirstChild("HoldFill")
		expect(fill ~= nil).toBe(true)
		expect(fill.Visible).toBe(false)
		expect(fill.Size.X.Scale).toBe(0)
	end)
	it("a hold stops when its panel is hidden or the button is destroyed, and never confirms", function()
		local Widgets = UiHarness.ui("Widgets")
		UiHarness.virtualTime(true)
		local confirms = 0
		local function build(): (any, any)
			local root = UiHarness.root()
			local panel = UiHarness.Instance.new("Frame")
			panel.Parent = root
			local btn = Widgets.holdButton({ Name = "T", Parent = panel }, nil, function()
				confirms += 1
			end, 0.5)
			return btn.instance, panel
		end
		-- baseline: a full hold confirms
		local inst, _ = build()
		UiHarness.fire(inst, "InputBegan", { UserInputType = Enum.UserInputType.MouseButton1 })
		UiHarness.advance(0.6)
		UiHarness.renderStep()
		expect(confirms).toBe(1)
		-- panel hidden mid-hold
		local inst2, panel2 = build()
		UiHarness.fire(inst2, "InputBegan", { UserInputType = Enum.UserInputType.MouseButton1 })
		panel2.Visible = false
		UiHarness.advance(0.6)
		UiHarness.renderStep()
		expect(confirms).toBe(1)
		expect(inst2:FindFirstChild("HoldFill").Visible).toBe(false)
		-- button destroyed mid-hold
		local inst3, _ = build()
		UiHarness.fire(inst3, "InputBegan", { UserInputType = Enum.UserInputType.MouseButton1 })
		inst3.Parent = nil
		UiHarness.advance(0.6)
		UiHarness.renderStep()
		expect(confirms).toBe(1)
		-- the hold also dies if it is hidden at the moment it would confirm
		expect(Widgets.holdAlive(inst3)).toBe(false)
		UiHarness.virtualTime(false)
	end)
	it("hold progress runs 0 -> 1 over the duration", function()
		local Widgets = UiHarness.ui("Widgets")
		expect(Widgets.holdProgress(10, 10, 0.8)).toBe(0)
		expect(Widgets.holdProgress(10, 10.4, 0.8)).toBeCloseTo(0.5)
		expect(Widgets.holdProgress(10, 12, 0.8)).toBe(1)
	end)
	it("the Studio PcwHold pause freezes the fill at the fraction and never reaches a confirm", function()
		local Widgets = UiHarness.ui("Widgets")
		local fill, paused = Widgets.holdPause(0.3, 0.5)
		expect(fill).toBe(0.3)
		expect(paused).toBe(false)
		fill, paused = Widgets.holdPause(0.7, 0.5)
		expect(fill).toBe(0.5)
		expect(paused).toBe(true)
		fill, paused = Widgets.holdPause(1, 0.5)
		expect(fill).toBe(0.5)
		expect(paused).toBe(true)
		fill, paused = Widgets.holdPause(1, nil)
		expect(fill).toBe(1)
		expect(paused).toBe(false)
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
