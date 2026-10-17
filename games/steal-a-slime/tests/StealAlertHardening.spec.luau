--!strict
-- Full steal alerts hardening (FEATURES.StealAlerts, CONTRACT.md §17): hostile saved logs, old saves,
-- leaving players, degenerate geometry. Asserts both modes of the frozen flag
-- (tests/FeatureFlags.spec re-runs it flipped). Cloud-eligible: no Lune modules.
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local Sessions = require("../src/server/Sessions")
local Snapshot = require("../src/server/Snapshot")
local StealAlert = require("../src/shared/StealAlert")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local CFG = Config.STEAL_ALERT
local on = Config.FEATURES.StealAlerts == true

describe("StealAlert saved log is untrusted", function()
	it("clean never errors and always returns a capped list of well-formed entries", function()
		local hostile: { any } = {
			"x",
			12,
			true,
			{ 1, 2, 3 },
			{ { thief = 5, slime = {}, at = "no" } },
			{ { thief = "A", slime = "B", at = 0 / 0 } },
			{ { thief = "A", slime = "B", at = math.huge } },
			{ { thief = "A", slime = "B", at = -1e30 } },
			{ { thief = string.rep("n", 500), slime = "a\0b\nc", at = "12" } },
			{ thief = "dict", slime = "not a list" },
		}
		for _, raw in hostile do
			local out = StealAlert.clean(raw)
			expect(#out <= CFG.LOG_CAP).toBe(true)
			for _, e in out do
				expect(#e.thief >= 1 and #e.thief <= CFG.NAME_MAX).toBe(true)
				expect(#e.slime >= 1 and #e.slime <= CFG.NAME_MAX).toBe(true)
				expect(e.at == e.at and e.at >= 0 and e.at <= 1e11).toBe(true)
				expect(string.find(e.slime, "%c")).toBeNil()
			end
			StealAlert.summary(out)
		end
	end)
	it("a log far over the cap keeps the newest entries", function()
		local raw = {}
		for i = 1, CFG.LOG_CAP * 3 do
			table.insert(raw, { thief = `T{i}`, slime = "s", at = i })
		end
		local out = StealAlert.clean(raw)
		expect(#out).toBe(CFG.LOG_CAP)
		expect(out[#out].thief).toBe(`T{CFG.LOG_CAP * 3}`)
		expect(out[1].at).toBe(CFG.LOG_CAP * 2 + 1)
	end)
	it("summary is nil for nothing and names each thief once with a 'more' tail", function()
		expect(StealAlert.summary(nil)).toBeNil()
		expect(StealAlert.summary({})).toBeNil()
		local log = {}
		for i = 1, CFG.SUMMARY_NAMES + 3 do
			StealAlert.record(log, `T{i}`, "s", T0 + i)
			StealAlert.record(log, `T{i}`, "s", T0 + i) -- same thief twice
		end
		local text = StealAlert.summary(log) :: string
		expect(string.find(text, "and 3 more", 1, true) ~= nil).toBe(true)
		expect(string.find(text, `{(CFG.SUMMARY_NAMES + 3) * 2} slimes were`, 1, true) ~= nil).toBe(true)
	end)
end)

describe("StealAlert flag and saves", function()
	it("an old save without stealLog joins with no notice and an empty log", function()
		local stored = SaveData.serialize(Fixtures.data(), T0)
		stored.stealLog = nil
		local data = SaveData.deserialize(stored)
		expect(#data.stealLog).toBe(0)
		local world = ServerFixtures.world()
		local session = Sessions.join(world, 1, "P1", data, T0)
		assert(session, "join")
		expect(Snapshot.build(world, session, T0).stealAway).toBeNil()
		expect(session.awayLog == nil or #session.awayLog == 0).toBe(true)
	end)
	it("junk stealLog in a save loads clean, and the notice shows once per join", function()
		local stored = SaveData.serialize(Fixtures.data(), T0)
		stored.stealLog = { { thief = "Rex", slime = "Blob", at = T0 - 5 }, "junk", 9 }
		local data = SaveData.deserialize(stored)
		expect(#data.stealLog).toBe(1)
		local world = ServerFixtures.world()
		local session = Sessions.join(world, 1, "P1", data, T0)
		assert(session, "join")
		local state = Snapshot.build(world, session, T0 + 1)
		expect(state.stealAway ~= nil).toBe(on)
		expect(#session.data.stealLog).toBe(if on then 0 else 1)
		-- the saved log is empty after the join, so a rejoin shows nothing new
		local left = Sessions.leave(world, 1, T0 + 2)
		assert(left, "left")
		local back = Sessions.join(world, 1, "P1", SaveData.deserialize(SaveData.serialize(left.data, T0 + 2)), T0 + 3)
		assert(back, "rejoin")
		expect(Snapshot.build(world, back, T0 + 4).stealAway).toBeNil()
	end)
	it("a victim or thief leaving mid-theft logs nothing", function()
		for _, leaver in { 1, 2 } do
			local world = ServerFixtures.world()
			local victim = ServerFixtures.join(world, 1, { Fixtures.slime("gem", 4) })
			ServerFixtures.join(world, 2)
			ServerFixtures.unlock(victim)
			expect((Carry.grab(world, 2, "gem", 1, T0 + 100))).toBe(true)
			Sessions.leave(world, leaver, T0 + 101)
			expect(#victim.data.stealLog).toBe(0)
		end
	end)
end)

describe("StealAlert degenerate geometry", function()
	it("bearing and edgePoint never produce NaN for zero, vertical or NaN-free extreme input", function()
		local cases = {
			{ { x = 0, z = 0 }, { x = 0, z = 0 }, { x = 0, z = 0 } },
			{ { x = 0, z = 0 }, { x = 1e-9, z = 0 }, { x = 0, z = 0 } },
			{ { x = 5, z = 5 }, { x = 1e9, z = -1e9 }, { x = 1e-7, z = 1e-7 } },
			{ { x = -5, z = 5 }, { x = -5, z = 5 }, { x = 0, z = -1 } },
		}
		for _, c in cases do
			local angle, distance = StealAlert.bearing(c[1], c[2], c[3])
			expect(angle == angle and distance == distance).toBe(true)
			local x, y = StealAlert.edgePoint(angle, 0, 0, CFG.ARROW_MARGIN)
			expect(x == x and y == y).toBe(true)
		end
	end)
	it("flash and alarm stay in range for huge, negative and NaN time", function()
		for _, t in { -5, 0, CFG.FLASH_SECONDS, 1e12, math.huge, 0 / 0 } do
			local a = StealAlert.flashAlpha(t)
			expect(a >= 0 and a <= 0.55 + 1e-9).toBe(true)
			local due = StealAlert.alarmDue(t)
			expect(due >= 0 and due <= CFG.ALARM_REPEATS).toBe(true)
		end
	end)
end)
