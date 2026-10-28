--!strict
-- The boss card (src/ui/BossMeterLogic.luau + Panels/BossMeter, contract/boss-event.md State.boss): a band with the
-- title and the time left, one row with the meter (or a name) and one short pill.
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

local function view(fields: { [string]: any }, now: number?, badgesBefore: number?): BossMeterLogic.View
	return BossMeterLogic.view(boss(fields), now or 1000, badgesBefore) :: BossMeterLogic.View
end

describe("BossMeterLogic.view", function()
	it("shows nothing without an event", function()
		expect(BossMeterLogic.view(nil, 0)).toBeNil()
		expect(BossMeterLogic.view({ active = false, meter = 0 }, 0)).toBeNil()
	end)
	it("on its way: the countdown and where to go", function()
		local v = view({ phase = "warning", endsAt = 1065 })
		expect(v.title).toBe("BOSS INCOMING")
		expect(v.timer).toBe("1:05")
		expect(v.tone).toBe("fight")
		expect(v.meter).toBeNil()
		expect(v.who).toBe("Goozilla")
		expect(v.pill).toBe("To the plaza")
	end)
	it("the fight: the meter and your share of the hits, or a nudge to hit it", function()
		local v = view({ phase = "fight", meter = 0.42, endsAt = 1090, yourPoints = 7, yourPercent = 0.35 })
		expect(v.title).toBe("Goozilla")
		expect(v.meter).toBe(0.42)
		expect(v.pill).toBe("You 35%")
		expect(view({ phase = "fight", yourPoints = 1, yourPercent = 0.001 }).pill).toBe("You 1%")
		expect(view({ phase = "fight", yourPoints = 3 }).pill).toBe("You 1%")
		expect(view({ phase = "fight" }).pill).toBe("Hit it!")
	end)
	it("what the boss does beats your hits: dodge, dazed, guards, then a hit on you beats them all", function()
		local fight = { phase = "fight", meter = 0.5, yourPoints = 4, yourPercent = 0.4, moveEndsAt = 1002 }
		local function with(extra: { [string]: any }): BossMeterLogic.View
			local f = table.clone(fight)
			for k, v in extra do
				f[k] = v
			end
			return view(f)
		end
		expect(with({ move = "windup" }).pill).toBe("Dodge!")
		expect(with({ move = "hop" }).pill).toBe("Dodge!") -- a bouncing stomp in the air
		local dazed = with({ move = "dazed", multiplier = 3 })
		expect(dazed.pill).toBe("Hits x3")
		expect(dazed.tone).toBe("gold")
		expect(with({ move = "rise", guardsLeft = 1, guardsTotal = 3 }).pill).toBe("Guards 1/3")
		expect(with({ move = "dazed", stunnedUntil = 1001.2 }).pill).toBe("Ouch! 2s")
		expect(with({ move = "dazed", moveEndsAt = 999 }).pill).toBe("You 40%") -- that daze is over
	end)
	it("the haul: grab it, the head start, then the carrier", function()
		local free = view({ phase = "haul", endsAt = 1045 })
		expect(free.title).toBe("Goozilla is down!")
		expect(free.tone).toBe("gold")
		expect(free.who).toBe("Grab it!")
		local first = view({ phase = "haul", priorityName = "Ann", priorityUntil = 1004 })
		expect(first.who).toBe("Ann grabs first")
		expect(first.pill).toBe("0:04")
		local carried = view({ phase = "haul", carrierName = "Bo" })
		expect(carried.who).toBe("Bo has it")
		expect(carried.pill).toBe("Bonk!")
	end)
	it("the result: a shared win with the badges it brought, or got away with the next one", function()
		local won = view({ phase = "won", winnerName = "Ann", badges = 3 }, 1000, 1)
		expect(won.title).toBe("Brought home!")
		expect(won.who).toBe("Ann + team")
		expect(won.pill).toBe("+2 badges")
		expect(view({ phase = "won", winnerName = "Ann", badges = 1 }, 1000, 1).pill).toBe("Shared win")
		local failed = view({ phase = "failed", meter = 0.72, nextAt = 1000 + 18 * 60 + 40 })
		expect(failed.title).toBe("Goozilla got away")
		expect(failed.tone).toBe("mute")
		expect(failed.meter).toBe(0.72)
		expect(failed.pill).toBe("Next 18:40")
	end)
end)

describe("Panels/BossMeter", function()
	local function mount(): (any, any)
		local root = UiHarness.root()
		local panel = UiHarness.ui("Panels/BossMeter").new(root, {
			serverNow = function()
				return 1000
			end,
		})
		return panel, UiHarness.find(root, "BossMeter")
	end

	it("is hidden without an event and fills its meter during the fight", function()
		local panel, frame = mount()
		panel.update({ boss = { active = false, meter = 0, yourPoints = 0, yourShare = 0, badges = 0 } })
		expect(frame.Visible).toBe(false)
		panel.update({ boss = boss({ phase = "fight", meter = 0.5, endsAt = 1030, yourPoints = 12, yourPercent = 1 }) })
		expect(frame.Visible).toBe(true)
		expect(UiHarness.find(frame, "Title").Text).toBe("Goozilla")
		expect(UiHarness.find(frame, "Timer").Text).toBe("0:30")
		expect(UiHarness.find(frame, "Percent").Text).toBe("50%")
		expect(UiHarness.find(frame, "Pill").Text).toBe("You 100%")
		expect(UiHarness.find(frame, "Who").Visible).toBe(false)
		local fill = UiHarness.find(frame, "Meter"):FindFirstChildOfClass("Frame")
		expect(fill.Size.X.Scale).toBe(0.5)
	end)
	it("paints the ring and tile by tone: pink to fight, gold when it's your moment, muted when it got away", function()
		local Theme = UiHarness.ui("Widgets").Theme
		local panel, frame = mount()
		local ring = frame:FindFirstChildOfClass("UIStroke")
		local tile = UiHarness.find(frame, "IconTile")
		local timer = UiHarness.find(frame, "Timer")
		panel.update({ boss = boss({ phase = "fight", meter = 0.4, endsAt = 1060 }) })
		expect(ring.Color).toBe(Theme.Bad)
		expect(tile.BackgroundColor3).toBe(Theme.Bad)
		expect(UiHarness.find(frame, "Band")).toBeNil() -- the notice-card look: no band, no drips
		panel.update({ boss = boss({ phase = "haul", meter = 1, endsAt = 1045, carrierName = "Bo" }) })
		expect(ring.Color).toBe(Theme.Gold)
		expect(tile.BackgroundColor3).toBe(Theme.Gold)
		expect(UiHarness.find(frame, "Title").Text).toBe("Goozilla is down!")
		expect(UiHarness.find(frame, "Who").Text).toBe("Bo has it")
		expect(UiHarness.find(frame, "Meter").Visible).toBe(false)
		expect(timer.Text).toBe("0:45")
		panel.update({ boss = boss({ phase = "won", meter = 1, winnerName = "Bo", badges = 1 }) })
		expect(UiHarness.find(frame, "Title").Text).toBe("Brought home!")
		expect(UiHarness.find(frame, "Pill").Text).toBe("+1 badge") -- 0 before the win, 1 now
		expect(timer.Visible).toBe(false)
		panel.update({ boss = boss({ phase = "failed", meter = 0.3 }) })
		expect(ring.Color).toBe(Theme.Info)
		expect(ring.Color == Theme.Good).toBe(false) -- a lost boss never looks like a win
		expect(timer.Visible).toBe(false)
	end)
end)
