--!strict
-- The boss card (src/ui/BossMeterLogic.luau + Panels/BossMeter, contract/boss-event.md State.boss).
local BossMeterLogic = require("../../src/ui/BossMeterLogic")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function boss(fields: { [string]: any }): any
	local out: { [string]: any } =
		{ active = true, name = "Goozilla", meter = 0, yourPoints = 0, yourShare = 0, trophies = 0 }
	for k, v in fields do
		out[k] = v
	end
	return out
end

describe("BossMeterLogic.view", function()
	it("shows nothing without an event", function()
		expect(BossMeterLogic.view(nil, 0)).toBeNil()
		expect(BossMeterLogic.view({ active = false, meter = 0 }, 0)).toBeNil()
	end)
	it("heads-up with the arrival countdown", function()
		local v = BossMeterLogic.view(boss({ phase = "warning", endsAt = 1065 }), 1000) :: BossMeterLogic.View
		expect(v.icon).toBe("👑")
		expect(v.title).toBe("BOSS INCOMING: Goozilla")
		expect(v.timer).toBe("1:05")
		expect(v.tone).toBe("warn")
	end)
	it("the fight shows the meter and your hits", function()
		local v = BossMeterLogic.view(
			boss({ phase = "fight", meter = 0.42, endsAt = 1090, yourPoints = 7, yourShare = 0.5 }),
			1000
		) :: BossMeterLogic.View
		expect(v.title).toBe("Goozilla: goo meter 42%")
		expect(v.detail).toBe("Your hits: 7 (50% of the top helper)")
		expect(v.meter).toBe(0.42)
		local idle = BossMeterLogic.view(boss({ phase = "fight", meter = 0 }), 1000) :: BossMeterLogic.View
		expect(idle.detail).toBe("Hit it with your bat to fill the goo meter!")
	end)
	it("the haul names the head start, then the carrier", function()
		local first = BossMeterLogic.view(boss({ phase = "haul", priorityName = "Ann" }), 0) :: BossMeterLogic.View
		expect(first.detail).toBe("Ann grabs first, then anyone!")
		local carried = BossMeterLogic.view(boss({ phase = "haul", carrierName = "Bo" }), 0) :: BossMeterLogic.View
		expect(carried.detail).toBe("Bo is carrying it! Bonk them to make them drop it!")
	end)
	it("the result: won or burst", function()
		local won = BossMeterLogic.view(boss({ phase = "won", winnerName = "Ann" }), 0) :: BossMeterLogic.View
		expect(won.icon).toBe("🏆")
		expect(won.title).toBe("Ann brought Goozilla home!")
		local failed = BossMeterLogic.view(boss({ phase = "failed" }), 0) :: BossMeterLogic.View
		expect(failed.icon).toBe("💥")
		expect(failed.title).toBe("Goozilla burst!")
	end)
end)

describe("Panels/BossMeter", function()
	it("is hidden without an event and fills its meter during the fight", function()
		local root = UiHarness.root()
		local panel = UiHarness.ui("Panels/BossMeter").new(root, {
			serverNow = function()
				return 1000
			end,
		})
		local frame = UiHarness.find(root, "BossMeter")
		panel.update({ boss = { active = false, meter = 0, yourPoints = 0, yourShare = 0, trophies = 0 } })
		expect(frame.Visible).toBe(false)
		panel.update({ boss = boss({ phase = "fight", meter = 0.5, endsAt = 1030 }) })
		expect(frame.Visible).toBe(true)
		expect(UiHarness.find(frame, "Title").Text).toBe("Goozilla: goo meter 50%")
		expect(UiHarness.find(frame, "Icon").Text).toBe("👑")
		expect(UiHarness.find(frame, "Timer").Text).toBe("0:30")
		local fill = UiHarness.find(frame, "Meter"):FindFirstChildOfClass("Frame")
		expect(fill.Size.X.Scale).toBe(0.5)
	end)
end)
