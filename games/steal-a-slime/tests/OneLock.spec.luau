--!strict
-- Lune only (reads src/ as text). One lock gives the full time and cannot be extended while it runs
-- (CONTRACT.md §6 Steal and lock): no "Extend lock" / "Lock is maxed" text and no stacking cap may come back.
local fs = require("@lune/fs")

local Config = require("../src/shared/Config")
local PlotPrompts = require("../src/server/PlotPrompts")
local ServerFixtures = require("./ServerFixtures")
local StealService = require("../src/server/StealService")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

local function collect(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			collect(path, out)
		elseif string.match(name, "%.luau?$") then
			table.insert(out, path)
		end
	end
end

describe("one lock, no extending", function()
	it(
		"a single lock gives the full duration; a second request while locked is refused with no state change",
		function()
			local world = ServerFixtures.world()
			local s = ServerFixtures.join(world, 1)
			s.data.rebirths = 2
			local t1 = s.lockUntil
			expect((StealService.buyLock(world, s, t1 - 1))).toBe(false)
			expect(s.lockUntil).toBe(t1)
			expect((StealService.buyLock(world, s, t1))).toBe(true)
			local full = Config.LOCK_SECONDS + 2 * Config.LOCK_SECONDS_PER_REBIRTH
			expect(s.lockUntil).toBe(t1 + full)
			local ok, reason = StealService.buyLock(world, s, t1 + full / 2)
			expect(ok).toBe(false)
			expect(reason).toBe("your base is already locked")
			expect(s.lockUntil).toBe(t1 + full)
			expect((StealService.buyLock(world, s, t1 + full))).toBe(true)
			expect(s.lockUntil).toBe(t1 + 2 * full)
		end
	)
	it("the lock prompt is off while locked, on again at expiry, and always says Lock base", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		local running = PlotPrompts.describe(world, s.plotIndex, T0)
		expect(running.lock.enabled).toBe(false)
		expect(running.lock.actionText).toBe("Lock base")
		local over = PlotPrompts.describe(world, s.plotIndex, s.lockUntil)
		expect(over.lock.enabled).toBe(true)
		expect(over.lock.actionText).toBe("Lock base")
	end)
	it("the locked prompt shows the time left (LOCKED m:ss)", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		local view = PlotPrompts.describe(world, s.plotIndex, T0 + 30)
		expect(view.lock.objectText).toBe(`P1's base: LOCKED {PlotPrompts.clock(Config.JOIN_LOCK_SECONDS - 30)}`)
	end)
	it("no 'Extend lock', 'Lock is maxed' or LOCK_MAX_REMAINING is left in src/", function()
		local files = {}
		collect("src", files)
		local bad = {}
		for _, path in files do
			local text = fs.readFile(path)
			for _, needle in { "Extend lock", "Lock is maxed", "LOCK_MAX_" .. "REMAINING" } do
				if string.find(text, needle, 1, true) then
					table.insert(bad, `{path}: {needle}`)
				end
			end
		end
		expect(table.concat(bad, "; ")).toBe("")
	end)
end)
