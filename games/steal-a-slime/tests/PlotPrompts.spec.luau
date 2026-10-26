--!strict
-- Owner-only plot prompts and lock / pad attributes (CONTRACT.md §8.4-§8.5).
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local PlotPrompts = require("../src/server/PlotPrompts")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

describe("PlotPrompts.describe", function()
	it("disables everything on a free plot", function()
		local world = ServerFixtures.world()
		local view = PlotPrompts.describe(world, 3, T0)
		expect(view.ownerUserId).toBeNil()
		expect(view.lock.enabled or view.buyPad.enabled or view.merge.enabled).toBe(false)
		expect(view.padsUnlocked).toBe(0)
	end)
	it("says LOCKED m:ss and Extend while locked, OPEN and Lock base once it expires", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		local view = PlotPrompts.describe(world, s.plotIndex, T0)
		expect(view.ownerUserId).toBe(1)
		expect(view.locked).toBe(true)
		expect(view.lock.objectText).toBe(`P1's base: LOCKED {PlotPrompts.clock(Config.JOIN_LOCK_SECONDS)}`)
		expect(view.lock.actionText).toBe("Extend lock")
		local open = PlotPrompts.describe(world, s.plotIndex, T0 + Config.JOIN_LOCK_SECONDS + 1)
		expect(open.locked).toBe(false)
		expect(open.lock.objectText).toBe("P1's base: OPEN")
		expect(open.lock.actionText).toBe("Lock base")
		s.lockUntil = T0 + Config.LOCK_MAX_REMAINING
		expect(PlotPrompts.describe(world, s.plotIndex, T0).lock.actionText).toBe("Lock is maxed")
	end)
	it("puts Buy pad on the lowest locked pad and turns it off when all are unlocked", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		s.data.padsUnlocked = Config.PADS_START
		local view = PlotPrompts.describe(world, s.plotIndex, T0)
		expect(view.buyPad.pad).toBe(Config.PADS_START + 1)
		local first = Config.PAD_START_COSTS[1]
		expect(view.buyPad.actionText).toBe(`Buy pad ${Economy.formatNumber(first)}`)
		expect(view.buyPad.objectText).toBe(`Pad {Config.PADS_START + 1} of {Config.PADS_MAX}`)
		expect(view.nextPadCost).toBe(first)
		s.data.padsUnlocked = Config.PADS_MAX
		local full = PlotPrompts.describe(world, s.plotIndex, T0)
		expect(full.buyPad.enabled).toBe(false)
		expect(full.nextPadCost).toBeNil()
		expect(full.buyPad.pad).toBe(Config.PADS_MAX)
	end)
	it("sells a floor's first pad as building that floor", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		s.data.padsUnlocked = Config.PADS_PER_FLOOR
		s.data.rebirths = Config.MAX_REBIRTHS
		local view = PlotPrompts.describe(world, s.plotIndex, T0)
		expect(view.buyPad.pad).toBe(Config.PADS_PER_FLOOR + 1)
		local cost = Economy.padCost(Config.PADS_PER_FLOOR) :: number
		expect(view.buyPad.actionText).toBe(`Build floor 2 ${Economy.formatNumber(cost)}`)
		s.data.padsUnlocked = Config.PADS_PER_FLOOR + 1
		expect(string.sub(PlotPrompts.describe(world, s.plotIndex, T0).buyPad.actionText, 1, 8)).toBe("Buy pad ")
	end)
	it("shows a disabled 'Rebirth N to unlock' on a next pad the owner hasn't rebirthed enough for", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		s.data.padsUnlocked = Config.PADS_PER_FLOOR
		local need = Economy.padRebirths(s.data.padsUnlocked) :: number
		s.data.rebirths = need - 1
		local view = PlotPrompts.describe(world, s.plotIndex, T0)
		expect(view.buyPad.pad).toBe(Config.PADS_PER_FLOOR + 1)
		expect(view.buyPad.actionText).toBe(`Rebirth {need} to unlock`)
		expect(view.buyPad.enabled).toBe(false)
		s.data.rebirths = need
		local open = PlotPrompts.describe(world, s.plotIndex, T0)
		expect(open.buyPad.enabled).toBe(true)
		expect(open.buyPad.actionText).toBe(
			`Build floor 2 ${Economy.formatNumber(Economy.padCost(Config.PADS_PER_FLOOR) :: number)}`
		)
	end)
	it("formats clocks", function()
		expect(PlotPrompts.clock(0)).toBe("0:00")
		expect(PlotPrompts.clock(61.2)).toBe("1:02")
		expect(PlotPrompts.clock(300)).toBe("5:00")
	end)
end)
