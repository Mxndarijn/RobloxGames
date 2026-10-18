--!strict
-- v23 mobile performance budget (client UI only): the numbers from tests/ui/PerfMeasure stay inside
-- ui-perf-budget.json (ratchet), and the loops fixed for it stay event-driven.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Genome = require("../../src/shared/Genome")
local HudClusters = require("../../src/ui/HudClusters")
local PerfMeasure = require("./PerfMeasure")
local Remotes = require("../../src/shared/Remotes")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function ctx(extra: { [string]: any }?): any
	local c: { [string]: any } = {
		Config = Config,
		Constants = Constants,
		Genome = Genome,
		actions = Remotes.ACTIONS,
		send = function() end,
		request = function() end,
		serverNow = function()
			return 1000
		end,
		playerName = function()
			return "Tester"
		end,
		itemIcons = UiHarness.ui("ItemIcons").build(Config),
	}
	for k, v in extra or {} do
		c[k] = v
	end
	return c
end

local function sleeping(): number
	local total = 0
	for _, n in UiHarness.sleepers() do
		total += n
	end
	return total
end

describe("UI performance budget", function()
	it("the measured numbers match ui-perf-budget.json", function()
		local budget = serde.decode("json", fs.readFile("ui-perf-budget.json")) :: any
		local problems = PerfMeasure.compare(PerfMeasure.measure(), budget.limits)
		expect(table.concat(problems, "; ")).toBe("")
	end)

	it("frame connections do not leak when every menu opens and closes", function()
		local r = PerfMeasure.measure()
		expect(r.frame_conns_after_menus).toBe(r.frame_conns_idle)
		expect(r.gui_instances_after_close).toBe(r.gui_instances_idle)
	end)
end)

describe("event-driven loops", function()
	it("Shop: the restock countdown ticks only while the card is open", function()
		UiHarness.virtualTime(true)
		local shop = UiHarness.ui("Panels/Shop").new(UiHarness.root(), ctx())
		expect(sleeping()).toBe(0)
		shop.setOpen(true)
		shop.setOpen(true)
		expect(UiHarness.sleepers()["1"]).toBe(1)
		shop.setOpen(false)
		UiHarness.advance(2)
		expect(sleeping()).toBe(0)
		shop.setOpen(true)
		expect(sleeping()).toBe(1)
		shop.setOpen(false)
		UiHarness.virtualTime(false)
	end)

	it("Hud: the Slime Rain slot text is the same at every 0.1 s tick, rebuilt about once a second", function()
		local gui = UiHarness.root()
		local hud = UiHarness.ui("Hud").new(gui, ctx())
		hud.update({
			cash = 1,
			incomePerSec = 1,
			rebirths = 0,
			rebirthMultiplier = 1,
			padsUnlocked = 1,
			padsMax = 8,
			lockUntil = 0,
			lockStartedAt = 0,
			slimes = {},
			daily = {},
			rain = {},
		})
		local slot = UiHarness.find(gui, "Rain")
		local timer = UiHarness.find(slot, "Timer")
		UiHarness.workspaceAttributes.RainActive = false
		UiHarness.workspaceAttributes.RainNextAt = 1065.5
		-- the countdown shows for the last RainTimer.SOON_SECONDS only
		for i = 0, 800 do
			local now = 1000 + i * 0.1
			hud.tick(now)
			local want = HudClusters.rain({ active = false, nextAt = 1065.5 }, now)
			expect(slot.Visible).toBe(want ~= nil)
			if want then
				expect(timer.Text).toBe(want.text)
			end
		end
		-- an attribute change shows at once, without the second flipping
		UiHarness.workspaceAttributes.RainActive = true
		UiHarness.workspaceAttributes.RainEndsAt = 1200
		hud.tick(1080.05)
		expect(slot.Visible).toBe(true)
		expect(timer.Text).toBe("2:00")
		UiHarness.workspaceAttributes.RainActive = nil
		UiHarness.workspaceAttributes.RainEndsAt = nil
		UiHarness.workspaceAttributes.RainNextAt = nil
	end)
end)
