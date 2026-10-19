--!strict
-- The new-player shield badge (ui/PvpShield, CONTRACT.md §26.7): when a badge shows, and the module starts, ticks and
-- stops cleanly with nobody shielded. The HUD's Shield slot is covered by HudV2.spec (HudClusters.shield).
local Config = require("../../src/shared/Config")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local PvpShield = UiHarness.ui("PvpShield")
local ItemIcons = UiHarness.ui("ItemIcons")

describe("PvpShield", function()
	it("shows while the attribute is a future server time", function()
		expect(PvpShield.active(1100, 1000)).toBe(true)
		expect(PvpShield.active(1000, 1000)).toBe(false)
		expect(PvpShield.active(nil, 1000)).toBe(false)
		expect(PvpShield.active("1100", 1000)).toBe(false)
		expect(PvpShield.active(0 / 0, 1000)).toBe(false)
	end)
	it("uses a registered icon", function()
		expect(ItemIcons.build(Config).get(PvpShield.BADGE.icon) ~= nil).toBe(true)
	end)
	it("starts, ticks and stops with no badge when nobody is shielded", function()
		local handle = PvpShield.start({
			attribute = "PvpShieldUntil",
			registry = ItemIcons.build(Config),
			serverNow = function()
				return 1000
			end,
			parent = UiHarness.root(),
		})
		handle.tick(1000)
		handle.tick(1001)
		expect(handle.count()).toBe(0)
		handle.stop()
	end)
end)
