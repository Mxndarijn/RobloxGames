--!strict
-- World sound rules (src/ui/WorldAudioLogic.luau): boss attacks, egg hatches, the ritual, the cue schedule.
local Config = require("../../src/shared/Config")
local EggHatchTimeline = require("../../src/visuals/shared/EggHatchTimeline")
local TestRunner = require("../TestRunner")
local WorldAudioLogic = require("../../src/ui/WorldAudioLogic")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local BOSS = Config.BOSS
local WORLD = Config.AUDIO.WORLD

local function move(kind: string, at: number, seconds: number, n: number?): any
	return {
		n = n or 7,
		kind = kind,
		slot = "start.1",
		at = at,
		seconds = seconds,
		fx = 0,
		fz = 0,
		tx = 0,
		tz = 0,
		hx = 1,
		hz = 0,
		ox = 0,
		oz = 0,
	}
end

local function names(cues: { any }): string
	local out = {}
	for _, cue in cues do
		table.insert(out, cue.name)
	end
	return table.concat(out, ",")
end

describe("WorldAudioLogic boss attacks", function()
	it("reads spit and rune lists, and nothing from junk", function()
		local spits = WorldAudioLogic.spitCues("10.00,-4.00,105.500;3.00,2.00,106.000")
		expect(names(spits)).toBe("BossGoo,BossGoo")
		expect(spits[1].at).toBe(105.5)
		expect(spits[1].x).toBe(10)
		expect(spits[1].z).toBe(-4)
		local runes = WorldAudioLogic.runeCues("1.00,2.00,50.000,10.00,16.00")
		expect(names(runes)).toBe("BossSlam")
		expect(runes[1].at).toBe(50)
		expect(#WorldAudioLogic.spitCues(nil)).toBe(0)
		expect(#WorldAudioLogic.spitCues("")).toBe(0)
		expect(#WorldAudioLogic.runeCues(42)).toBe(0)
	end)

	it("gives each spit its own key, so a re-sent list never replays one", function()
		local a = WorldAudioLogic.spitCues("1.00,1.00,10.000")
		local b = WorldAudioLogic.spitCues("1.00,1.00,10.000;2.00,2.00,11.000")
		expect(a[1].key).toBe(b[1].key)
		expect(a[1].key ~= b[2].key).toBe(true)
	end)

	it("rises at the start of a windup", function()
		local cues = WorldAudioLogic.moveCues(move("windup", 20, BOSS.WINDUP_SECONDS), nil)
		expect(names(cues)).toBe("BossWindup")
		expect(cues[1].at).toBe(20)
		expect(cues[1].x).toBeNil()
	end)

	it("slams once per wave of a ring attack", function()
		local attack = { kind = "ring", radius = 22, speed = 22, waves = 2, waveGap = 0.7 }
		local cues = WorldAudioLogic.moveCues(move("attack", 30, 3), attack)
		expect(names(cues)).toBe("BossSlam,BossSlam")
		expect(cues[1].at).toBeCloseTo(30 + BOSS.RING_DELAY, 1e-6)
		expect(cues[2].at).toBeCloseTo(30 + BOSS.RING_DELAY + 0.7, 1e-6)
		expect(cues[1].key ~= cues[2].key).toBe(true)
	end)

	it("slams when it lands: a hop, the arrival drop, the float down", function()
		expect(WorldAudioLogic.moveCues(move("hop", 10, 1.5), nil)[1].at).toBe(10 + BOSS.HOP_SECONDS)
		expect(WorldAudioLogic.moveCues(move("arrive", 10, BOSS.ARRIVE_SECONDS), nil)[1].at).toBe(10 + BOSS.ARRIVE_FALL)
		expect(WorldAudioLogic.moveCues(move("land", 10, BOSS.LAND_SECONDS), nil)[1].at).toBe(10 + BOSS.LAND_SECONDS)
	end)

	it("stays quiet for strolls, looks, a dazed boss and a cone", function()
		for _, kind in { "stroll", "look", "dazed", "rise", "down" } do
			expect(#WorldAudioLogic.moveCues(move(kind, 0, 1), nil)).toBe(0)
		end
		expect(#WorldAudioLogic.moveCues(move("attack", 0, 1), { kind = "cone" })).toBe(0)
	end)
end)

describe("WorldAudioLogic egg hatch", function()
	it("wobbles on each rock and cracks at the burst", function()
		local cues = WorldAudioLogic.hatchCues("egg1", 100)
		expect(names(cues)).toBe("EggWobble,EggWobble,EggWobble,EggCrack")
		local each = EggHatchTimeline.WOBBLE_END / EggHatchTimeline.WOBBLES
		expect(cues[1].at).toBe(100)
		expect(cues[2].at).toBeCloseTo(100 + each, 1e-6)
		expect(cues[3].at).toBeCloseTo(100 + 2 * each, 1e-6)
		expect(cues[4].at).toBe(100 + EggHatchTimeline.BURST)
		-- each rock really is a new rock of the show
		expect(EggHatchTimeline.wobble(cues[2].at - 100 + 1e-3)).toBe(2)
	end)

	it("pops when the hatched slime arrives, at the burst or later, and shares the crack's key", function()
		local burst = 100 + EggHatchTimeline.BURST
		local early = WorldAudioLogic.popCues("egg1", 100, burst - 0.3)
		expect(names(early)).toBe("EggCrack,EggHatch")
		expect(early[2].at).toBe(burst)
		expect(early[1].key).toBe(WorldAudioLogic.hatchCues("egg1", 100)[4].key)
		local late = WorldAudioLogic.popCues("egg1", 100, burst + 1)
		expect(late[2].at).toBe(burst + 1)
		expect(#WorldAudioLogic.popCues("egg1", 100, burst + EggHatchTimeline.LATE + 0.1)).toBe(0)
	end)
end)

describe("WorldAudioLogic ritual", function()
	it("never cues on the first look", function()
		expect(#WorldAudioLogic.ritualCues(nil, { phase = "Cooldown", taken = { true, true } })).toBe(0)
	end)

	it("chimes per spot taken and when the ritual completes", function()
		local idle = { phase = "Idle", taken = { false, false } }
		local one = { phase = "Idle", taken = { true, false } }
		local cues = WorldAudioLogic.ritualCues(idle, one)
		expect(names(cues)).toBe("RitualSpot")
		expect(cues[1].spot).toBe(1)
		expect(#WorldAudioLogic.ritualCues(one, one)).toBe(0)
		expect(#WorldAudioLogic.ritualCues(one, idle)).toBe(0)
		local charging = { phase = "Charging", taken = { true, true } }
		local done = { phase = "Cooldown", taken = { true, true } }
		local finish = WorldAudioLogic.ritualCues(charging, done)
		expect(names(finish)).toBe("RitualDone")
		expect(finish[1].spot).toBeNil()
		-- a charge broken off (back to Idle) is no completion
		expect(#WorldAudioLogic.ritualCues(charging, { phase = "Idle", taken = { true, true } })).toBe(0)
	end)

	it("hums only while charging", function()
		expect(WorldAudioLogic.humOn({ phase = "Charging", taken = {} })).toBe(true)
		expect(WorldAudioLogic.humOn({ phase = "Cooldown", taken = {} })).toBe(false)
		expect(WorldAudioLogic.humOn(nil)).toBe(false)
	end)
end)

describe("WorldAudioLogic schedule", function()
	it("plays each cue once, at its time", function()
		local s = WorldAudioLogic.newSchedule()
		local cues = {
			{ key = "b", name = "B", at = 12 },
			{ key = "a", name = "A", at = 11 },
		}
		WorldAudioLogic.schedule(s, cues, 10, WORLD)
		expect(#WorldAudioLogic.due(s, 10.5, WORLD)).toBe(0)
		expect(names(WorldAudioLogic.due(s, 11, WORLD))).toBe("A")
		WorldAudioLogic.schedule(s, cues, 12, WORLD)
		expect(names(WorldAudioLogic.due(s, 12.1, WORLD))).toBe("B")
		expect(#WorldAudioLogic.due(s, 13, WORLD)).toBe(0)
	end)

	it("drops a cue seen too late instead of playing it late", function()
		local s = WorldAudioLogic.newSchedule()
		WorldAudioLogic.schedule(s, { { key = "x", name = "X", at = 10 } }, 10 + WORLD.LATE_SECONDS + 0.1, WORLD)
		expect(#WorldAudioLogic.due(s, 20, WORLD)).toBe(0)
		local s2 = WorldAudioLogic.newSchedule()
		WorldAudioLogic.schedule(s2, { { key = "y", name = "Y", at = 10 } }, 9, WORLD)
		expect(#WorldAudioLogic.due(s2, 10 + WORLD.LATE_SECONDS + 1, WORLD)).toBe(0)
	end)

	it("plays cues due together in time order", function()
		local s = WorldAudioLogic.newSchedule()
		WorldAudioLogic.schedule(s, {
			{ key = "b", name = "B", at = 10.2 },
			{ key = "a", name = "A", at = 10.1 },
		}, 10, WORLD)
		expect(names(WorldAudioLogic.due(s, 10.25, WORLD))).toBe("A,B")
	end)

	it("forgets old keys", function()
		local s = WorldAudioLogic.newSchedule()
		WorldAudioLogic.schedule(s, { { key = "x", name = "X", at = 10 } }, 10, WORLD)
		WorldAudioLogic.due(s, 10, WORLD)
		expect(s.seen.x).toBe(10)
		WorldAudioLogic.due(s, 10 + WORLD.FORGET_SECONDS + 1, WORLD)
		expect(s.seen.x).toBeNil()
	end)
end)

describe("WorldAudioLogic config", function()
	it("has real ids for the looped beds and culls past CULL_DISTANCE", function()
		expect(WorldAudioLogic.loopId(WORLD.FOUNTAIN_ID)).toBe(WORLD.FOUNTAIN_ID)
		expect(WorldAudioLogic.loopId(WORLD.RITUAL_HUM_ID)).toBe(WORLD.RITUAL_HUM_ID)
		expect(WorldAudioLogic.loopId("rbxassetid://0")).toBeNil()
		expect(WorldAudioLogic.loopId("")).toBeNil()
		expect(WorldAudioLogic.audible(WORLD.CULL_DISTANCE, WORLD)).toBe(true)
		expect(WorldAudioLogic.audible(WORLD.CULL_DISTANCE + 1, WORLD)).toBe(false)
	end)

	it("flatVolume is full up close, falls off with distance and is silent at the far edge", function()
		expect(WorldAudioLogic.flatVolume(0, 12, 150)).toBe(1)
		expect(WorldAudioLogic.flatVolume(12, 12, 150)).toBe(1)
		expect(WorldAudioLogic.flatVolume(24, 12, 150)).toBe(0.5)
		expect(WorldAudioLogic.flatVolume(150, 12, 150)).toBe(0)
		expect(WorldAudioLogic.flatVolume(500, 12, 150)).toBe(0)
		local last = 1
		for d = 13, 149 do
			local v = WorldAudioLogic.flatVolume(d, 12, 150)
			expect(v < last).toBe(true)
			expect(v > 0).toBe(true)
			last = v
		end
	end)
end)
