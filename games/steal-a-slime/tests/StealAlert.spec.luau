--!strict
-- v21 full steal alerts (FEATURES.StealAlerts, CONTRACT.md §17): pure maths, the capped saved log,
-- the join notice, and the server wiring (log on theft, notice on join, slap reason). The server
-- wiring asserts both modes of the flag (Config.FEATURES is frozen), so the suite passes either way.
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local PlayerData = require("../src/shared/PlayerData")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local Sessions = require("../src/server/Sessions")
local Snapshot = require("../src/server/Snapshot")
local StealAlert = require("../src/shared/StealAlert")
local StealService = require("../src/server/StealService")
local TestRunner = require("./TestRunner")
local World = require("../src/server/World")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local CFG = Config.STEAL_ALERT
local enabled = Config.FEATURES.StealAlerts

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

describe("StealAlert config", function()
	it("keeps the trail short and the log capped", function()
		expect(CFG.TRAIL_LIFETIME <= 2).toBe(true) -- pc-watcher fx_streaks cap
		expect(CFG.LOG_CAP >= 1 and CFG.LOG_CAP <= 50).toBe(true)
		expect(CFG.FLASH_SECONDS <= 3).toBe(true)
	end)
end)

describe("StealAlert.bearing", function()
	local origin = { x = 0, z = 0 }
	it("is 0 straight ahead and counts the distance", function()
		local angle, d = StealAlert.bearing(origin, { x = 0, z = -30 }, { x = 0, z = -1 })
		expect(near(angle, 0)).toBe(true)
		expect(near(d, 30)).toBe(true)
	end)
	it("is +90 degrees to the right, -90 to the left, 180 behind", function()
		-- looking along -Z (north), +X is the camera's right
		local right = StealAlert.bearing(origin, { x = 10, z = 0 }, { x = 0, z = -1 })
		local left = StealAlert.bearing(origin, { x = -10, z = 0 }, { x = 0, z = -1 })
		local behind = StealAlert.bearing(origin, { x = 0, z = 10 }, { x = 0, z = -1 })
		expect(near(right, math.pi / 2)).toBe(true)
		expect(near(left, -math.pi / 2)).toBe(true)
		expect(near(math.abs(behind), math.pi)).toBe(true)
	end)
	it("follows the look direction (looking +X, +Z is on the right)", function()
		local angle = StealAlert.bearing(origin, { x = 0, z = 10 }, { x = 1, z = 0 })
		expect(near(angle, math.pi / 2)).toBe(true)
	end)
	it("ignores the look vector's length and survives a straight-up look and a zero distance", function()
		local a = StealAlert.bearing(origin, { x = 5, z = 0 }, { x = 0, z = -7 })
		expect(near(a, math.pi / 2)).toBe(true)
		local up = StealAlert.bearing(origin, { x = 5, z = 0 }, { x = 0, z = 0 })
		expect(up == up).toBe(true)
		local angle, d = StealAlert.bearing(origin, origin, { x = 0, z = -1 })
		expect(angle).toBe(0)
		expect(d).toBe(0)
	end)
end)

describe("StealAlert.edgePoint", function()
	it("puts ahead at the top and right at the right edge, inside the margin", function()
		local x, y = StealAlert.edgePoint(0, 1000, 600, 50)
		expect(near(x, 500)).toBe(true)
		expect(near(y, 50)).toBe(true)
		local rx, ry = StealAlert.edgePoint(math.pi / 2, 1000, 600, 50)
		expect(near(rx, 950)).toBe(true)
		expect(near(ry, 300)).toBe(true)
		local bx, by = StealAlert.edgePoint(math.pi, 1000, 600, 50)
		expect(near(bx, 500)).toBe(true)
		expect(near(by, 550)).toBe(true)
	end)
	it("never leaves the viewport, even for a tiny one", function()
		for i = -8, 8 do
			local x, y = StealAlert.edgePoint(i * 0.4, 80, 60, 56)
			expect(x >= 0 and x <= 80 and y >= 0 and y <= 60).toBe(true)
		end
	end)
	it("rotates an up-pointing arrow glyph by the angle in degrees", function()
		expect(near(StealAlert.arrowRotation(math.pi / 2), 90)).toBe(true)
	end)
end)

describe("StealAlert flash and alarm", function()
	it("is 0 before, after and at nonsense times, and peaks below 0.6", function()
		expect(StealAlert.flashAlpha(-1)).toBe(0)
		expect(StealAlert.flashAlpha(CFG.FLASH_SECONDS)).toBe(0)
		expect(StealAlert.flashAlpha(0 / 0)).toBe(0)
		local peak = 0
		for i = 0, 120 do
			local a = StealAlert.flashAlpha(i * CFG.FLASH_SECONDS / 120)
			expect(a >= 0 and a <= 0.55 + 1e-9).toBe(true)
			peak = math.max(peak, a)
		end
		expect(peak > 0.5).toBe(true)
	end)
	it("pulses FLASH_PULSES times (dips to 0 between pulses)", function()
		local mid = CFG.FLASH_SECONDS / CFG.FLASH_PULSES
		expect(near(StealAlert.flashAlpha(mid), 0)).toBe(true)
	end)
	it("owes repeat alarms every ALARM_REPEAT s, at most ALARM_REPEATS", function()
		expect(StealAlert.alarmDue(0)).toBe(0)
		expect(StealAlert.alarmDue(CFG.ALARM_REPEAT - 0.01)).toBe(0)
		expect(StealAlert.alarmDue(CFG.ALARM_REPEAT)).toBe(1)
		expect(StealAlert.alarmDue(1e6)).toBe(CFG.ALARM_REPEATS)
		expect(StealAlert.alarmDue(-5)).toBe(0)
	end)
end)

describe("StealAlert log and summary", function()
	it("records thefts and drops the oldest past LOG_CAP", function()
		local log: { StealAlert.Entry } = {}
		for i = 1, CFG.LOG_CAP + 5 do
			StealAlert.record(log, `T{i}`, "Blob", 100 + i)
		end
		expect(#log).toBe(CFG.LOG_CAP)
		expect(log[1].thief).toBe("T6")
		expect(log[#log].thief).toBe(`T{CFG.LOG_CAP + 5}`)
	end)
	it("cleans junk: wrong types, control characters, long names, over-long lists", function()
		local raw: { any } = { 5, "x", { thief = 7 }, { thief = "A\n\0B", slime = string.rep("s", 99), at = "12" } }
		for i = 1, 40 do
			table.insert(raw, { thief = `P{i}`, slime = "S", at = i })
		end
		local log = StealAlert.clean(raw)
		expect(#log <= CFG.LOG_CAP).toBe(true)
		for _, e in log do
			expect(#e.thief <= CFG.NAME_MAX and #e.slime <= CFG.NAME_MAX).toBe(true)
			expect(string.find(e.thief, "%c")).toBeNil()
		end
		expect(#StealAlert.clean(nil)).toBe(0)
		expect(#StealAlert.clean("nope")).toBe(0)
		local small = StealAlert.clean({ { thief = "A\n\0B", slime = "s", at = "12" }, { thief = 7 } })
		expect(small[1].thief).toBe("AB")
		expect(small[1].at).toBe(12)
		expect(small[2].thief).toBe("someone")
	end)
	it("has no notice for an empty or missing log", function()
		expect(StealAlert.summary(nil)).toBeNil()
		expect(StealAlert.summary({})).toBeNil()
	end)
	it("words one, two and many thefts", function()
		local one: { StealAlert.Entry } = { { thief = "Rex", slime = "Blob", at = 1 } }
		expect(StealAlert.summary(one)).toBe("While you were away 1 slime was stolen by Rex.")
		local two: { StealAlert.Entry } =
			{ { thief = "Rex", slime = "A", at = 1 }, { thief = "Mia", slime = "B", at = 2 } }
		expect(StealAlert.summary(two)).toBe("While you were away 2 slimes were stolen by Mia and Rex.")
		local same: { StealAlert.Entry } =
			{ { thief = "Rex", slime = "A", at = 1 }, { thief = "Rex", slime = "B", at = 2 } }
		expect(StealAlert.summary(same)).toBe("While you were away 2 slimes were stolen by Rex.")
	end)
	it("lists at most SUMMARY_NAMES thieves, most recent first, then 'and N more'", function()
		local log: { StealAlert.Entry } = {}
		for i = 1, 6 do
			StealAlert.record(log, `T{i}`, "Blob", i)
		end
		expect(StealAlert.summary(log)).toBe("While you were away 6 slimes were stolen by T6, T5, T4 and 3 more.")
	end)
end)

describe("StealAlert save", function()
	it("round-trips the log through SaveData and tolerates old saves without it", function()
		local data = PlayerData.new()
		StealAlert.record(data.stealLog, "Rex", "Blob", 1234)
		local back = SaveData.deserialize(SaveData.serialize(data))
		expect(#back.stealLog).toBe(1)
		expect(back.stealLog[1].thief).toBe("Rex")
		expect(back.stealLog[1].at).toBe(1234)
		local raw = SaveData.serialize(PlayerData.new())
		raw.stealLog = nil
		expect(#SaveData.deserialize(raw).stealLog).toBe(0)
		raw.stealLog = { { thief = {}, at = "x" }, 3 }
		expect(#SaveData.deserialize(raw).stealLog).toBe(1)
	end)
	it("caps a hostile save", function()
		local raw = SaveData.serialize(PlayerData.new())
		local big = {}
		for i = 1, 500 do
			big[i] = { thief = `P{i}`, slime = "S", at = i }
		end
		raw.stealLog = big
		expect(#SaveData.deserialize(raw).stealLog <= CFG.LOG_CAP).toBe(true)
	end)
end)

describe("StealAlert server wiring", function()
	local function theft()
		local world = ServerFixtures.world()
		local victim = ServerFixtures.join(world, 1, { Fixtures.slime("gem", 4) })
		local thief = ServerFixtures.join(world, 2)
		ServerFixtures.unlock(victim)
		expect((Carry.grab(world, 2, "gem", 1, T0 + 100))).toBe(true)
		return world, victim, thief
	end

	it("logs a finished theft on the victim only with the flag on", function()
		local world, victim = theft()
		expect((Carry.deposit(world, 2))).toBe(true)
		expect(#victim.data.stealLog).toBe(if enabled then 1 else 0)
		if enabled then
			expect(victim.data.stealLog[1].thief).toBe("P2")
			expect(victim.data.stealLog[1].slime).toBe("Epic Blorp") -- Carry logs the slime's display name
		end
		expect(#world.sessions[2].data.stealLog).toBe(0)
	end)
	it("does not log an escape or a slap", function()
		local world, victim, thief = theft()
		StealService.escape(world, thief, T0 + 101, "drop")
		expect(#victim.data.stealLog).toBe(0)
	end)
	it("tags the Escaped event with its reason, so a slap can be told apart", function()
		local world, victim, thief = theft()
		World.drain(world)
		thief.lastSlapAt = -math.huge
		expect((StealService.slap(world, victim, 2, 3, T0 + 101))).toBe(true)
		local reasons = {}
		for _, event in World.drain(world) do
			if event.type == "Escaped" then
				table.insert(reasons, event.reason)
			end
		end
		expect(#reasons).toBe(1)
		expect(reasons[1]).toBe("slap")
	end)
	it("turns the saved log into this join's notice once, and starts the saved log empty", function()
		local world = ServerFixtures.world()
		local data = Fixtures.data()
		StealAlert.record(data.stealLog, "Rex", "Blob", T0 - 500)
		StealAlert.record(data.stealLog, "Mia", "Pip", T0 - 400)
		local session = Sessions.join(world, 1, "P1", data, T0)
		assert(session, "join")
		local state = Snapshot.build(world, session, T0 + 1)
		if enabled then
			expect(state.stealAway).toBe("While you were away 2 slimes were stolen by Mia and Rex.")
			expect(#session.data.stealLog).toBe(0)
		else
			expect(state.stealAway).toBeNil()
			expect(#session.data.stealLog).toBe(2) -- untouched while the flag is off
		end
	end)
	it("has no notice without saved thefts", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1)
		expect(Snapshot.build(world, session, T0 + 1).stealAway).toBeNil()
	end)
end)
