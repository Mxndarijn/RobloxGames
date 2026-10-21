--!strict
-- The boss card (src/ui/BossMeterLogic.luau + Panels/BossMeter, contract/boss-event.md State.boss).
local BossMeterLogic = require("../../src/ui/BossMeterLogic")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function boss(fields: { [string]: any }): any
	local out: { [string]: any } =
		{ active = true, name = "Goozilla", meter = 0, yourPoints = 0, yourShare = 0, badges = 0 }
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
	it("the result: won or got away", function()
		local won = BossMeterLogic.view(boss({ phase = "won", winnerName = "Ann" }), 0) :: BossMeterLogic.View
		expect(won.icon).toBe("🏆")
		expect(won.title).toBe("Ann brought Goozilla home!")
		local failed = BossMeterLogic.view(boss({ phase = "failed" }), 0) :: BossMeterLogic.View
		expect(failed.icon).toBe("💨")
		expect(failed.title).toBe("Goozilla got away!")
		expect(failed.detail).toBe("Better luck with the next one!")
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
		panel.update({ boss = { active = false, meter = 0, yourPoints = 0, yourShare = 0, badges = 0 } })
		expect(frame.Visible).toBe(false)
		panel.update({ boss = boss({ phase = "fight", meter = 0.5, endsAt = 1030 }) })
		expect(frame.Visible).toBe(true)
		expect(UiHarness.find(frame, "Title").Text).toBe("Goozilla: goo meter 50%")
		expect(UiHarness.find(frame, "Icon").Text).toBe("👑")
		expect(UiHarness.find(frame, "Timer").Text).toBe("0:30")
		local fill = UiHarness.find(frame, "Meter"):FindFirstChildOfClass("Frame")
		expect(fill.Size.X.Scale).toBe(0.5)
	end)
	it("shows the haul, the win and the escape with their icon, tile colour and timer chip", function()
		local Theme = UiHarness.ui("Widgets").Theme
		local root = UiHarness.root()
		local panel = UiHarness.ui("Panels/BossMeter").new(root, {
			serverNow = function()
				return 1000
			end,
		})
		local frame = UiHarness.find(root, "BossMeter")
		local tile = UiHarness.find(frame, "IconTile")
		local timer = UiHarness.find(frame, "Timer")
		local fill = UiHarness.find(frame, "Meter"):FindFirstChildOfClass("Frame")
		panel.update({ boss = boss({ phase = "haul", meter = 1, endsAt = 1045, carrierName = "Bo" }) })
		expect(UiHarness.find(frame, "Icon").Text).toBe("👑")
		expect(UiHarness.find(frame, "Title").Text).toBe("Goozilla is down!")
		expect(tile.BackgroundColor3).toBe(Theme.Gold)
		expect(timer.Visible).toBe(true)
		expect(timer.Text).toBe("0:45")
		expect(fill.Size.X.Scale).toBe(1)
		panel.update({ boss = boss({ phase = "won", meter = 1, winnerName = "Bo" }) })
		expect(UiHarness.find(frame, "Icon").Text).toBe("🏆")
		expect(UiHarness.find(frame, "Title").Text).toBe("Bo brought Goozilla home!")
		expect(tile.BackgroundColor3).toBe(Theme.Good)
		expect(timer.Visible).toBe(false)
		panel.update({ boss = boss({ phase = "failed", meter = 0.3 }) })
		expect(UiHarness.find(frame, "Icon").Text).toBe("💨")
		expect(tile.BackgroundColor3).toBe(Theme.Info)
		expect(fill.BackgroundColor3).toBe(Theme.Info)
		expect(tile.BackgroundColor3 == Theme.Good).toBe(false) -- a lost boss never looks like a win
		expect(timer.Visible).toBe(false)
	end)
end)
