--!strict
-- Which slime sounds play (src/ui/SlimeAudioLogic.luau, ui/SlimeAudio): nearest first within the budget, one sound
-- per slime per gap, pickup and put-down always, rare blips, lower pitch for bigger slimes.
local Config = require("../../src/shared/Config")
local SlimeAudioLogic = require("../../src/ui/SlimeAudioLogic")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
-- The budget rules run against a fixed cap of 2 per second, so tuning the shipped value keeps these tests meaningful.
local cfg = table.clone(Config.AUDIO.SLIME)
cfg.MAX_PER_SECOND = 2

local function always(): number
	return 0
end
local function never(): number
	return 0.999
end

local function land(key: string, distance: number): SlimeAudioLogic.Cue
	return { key = key, kind = "land", distance = distance, size = 1 }
end

describe("SlimeAudioLogic budget", function()
	it("plays at most MAX_PER_SECOND squishes, nearest first", function()
		local st = SlimeAudioLogic.new()
		for i = 1, 30 do
			SlimeAudioLogic.offer(st, land(`s{i}`, 31 - i))
		end
		local out = SlimeAudioLogic.pick(st, 10, cfg, always)
		expect(#out).toBe(cfg.MAX_PER_SECOND)
		expect(out[1].key).toBe("s30")
		expect(out[2].key).toBe("s29")
		expect(#st.queue).toBe(0)
	end)

	it("keeps the cap over a whole second, then lets new ones through", function()
		local st = SlimeAudioLogic.new()
		local played = 0
		for f = 0, 9 do
			SlimeAudioLogic.offer(st, land(`a{f}`, 5))
			SlimeAudioLogic.offer(st, land(`b{f}`, 6))
			played += #SlimeAudioLogic.pick(st, 10 + f * 0.1, cfg, always)
		end
		expect(played).toBe(cfg.MAX_PER_SECOND)
		SlimeAudioLogic.offer(st, land("late", 5))
		expect(#SlimeAudioLogic.pick(st, 11.5, cfg, always)).toBe(1)
	end)

	it("gives one slime at most one sound per SLIME_GAP", function()
		local st = SlimeAudioLogic.new()
		SlimeAudioLogic.offer(st, land("s", 5))
		expect(#SlimeAudioLogic.pick(st, 10, cfg, always)).toBe(1)
		SlimeAudioLogic.offer(st, land("s", 5))
		expect(#SlimeAudioLogic.pick(st, 10 + cfg.SLIME_GAP / 2, cfg, always)).toBe(0)
		SlimeAudioLogic.offer(st, land("s", 5))
		expect(#SlimeAudioLogic.pick(st, 10 + cfg.SLIME_GAP + 0.01, cfg, always)).toBe(1)
	end)

	it("drops slimes past MAX_DISTANCE", function()
		local st = SlimeAudioLogic.new()
		SlimeAudioLogic.offer(st, land("far", cfg.MAX_DISTANCE + 1))
		SlimeAudioLogic.offer(st, { key = "farCarry", kind = "pickup", distance = cfg.MAX_DISTANCE + 1 })
		expect(#SlimeAudioLogic.pick(st, 10, cfg, always)).toBe(0)
	end)

	it("plays pickup and put-down past the cap and the gap, before squishes", function()
		local st = SlimeAudioLogic.new()
		for i = 1, 10 do
			SlimeAudioLogic.offer(st, land(`s{i}`, i))
		end
		SlimeAudioLogic.pick(st, 10, cfg, always)
		SlimeAudioLogic.offer(st, land("s1", 1))
		SlimeAudioLogic.offer(st, { key = "s1", kind = "putdown", distance = 1 })
		SlimeAudioLogic.offer(st, { key = "x", kind = "pickup", distance = cfg.MAX_DISTANCE - 1 })
		local out = SlimeAudioLogic.pick(st, 10.1, cfg, always)
		expect(#out).toBe(2)
		expect(out[1].kind).toBe("putdown")
		expect(out[2].kind).toBe("pickup")
	end)

	it("a put-down holds that slime's squish back for SLIME_GAP", function()
		local st = SlimeAudioLogic.new()
		SlimeAudioLogic.offer(st, { key = "s", kind = "putdown", distance = 3 })
		SlimeAudioLogic.pick(st, 10, cfg, always)
		SlimeAudioLogic.offer(st, land("s", 3))
		expect(#SlimeAudioLogic.pick(st, 10.3, cfg, always)).toBe(0)
	end)

	it("blips only on a lucky roll and BLIP_GAP apart", function()
		local st = SlimeAudioLogic.new()
		SlimeAudioLogic.offer(st, { key = "a", kind = "blip", distance = 3 })
		expect(#SlimeAudioLogic.pick(st, 10, cfg, never)).toBe(0)
		SlimeAudioLogic.offer(st, { key = "a", kind = "blip", distance = 3 })
		expect(#SlimeAudioLogic.pick(st, 10.1, cfg, always)).toBe(1)
		SlimeAudioLogic.offer(st, { key = "b", kind = "blip", distance = 3 })
		expect(#SlimeAudioLogic.pick(st, 10.2, cfg, always)).toBe(0)
		SlimeAudioLogic.offer(st, { key = "b", kind = "blip", distance = 3 })
		expect(#SlimeAudioLogic.pick(st, 10.1 + cfg.BLIP_GAP, cfg, always)).toBe(1)
	end)

	it("keeps one cue per slime per frame, the squish over the blip", function()
		local st = SlimeAudioLogic.new()
		SlimeAudioLogic.offer(st, { key = "a", kind = "blip", distance = 3 })
		SlimeAudioLogic.offer(st, land("a", 3))
		local out = SlimeAudioLogic.pick(st, 10, cfg, always)
		expect(#out).toBe(1)
		expect(out[1].kind).toBe("land")
	end)

	it("forget clears a slime's gap", function()
		local st = SlimeAudioLogic.new()
		SlimeAudioLogic.offer(st, land("s", 5))
		SlimeAudioLogic.pick(st, 10, cfg, always)
		SlimeAudioLogic.forget(st, "s")
		SlimeAudioLogic.offer(st, land("s", 5))
		expect(#SlimeAudioLogic.pick(st, 10.1, cfg, always)).toBe(1)
	end)
end)

describe("SlimeAudioLogic cues", function()
	it("turns State changes into pickup and put-down", function()
		expect(SlimeAudioLogic.stateCue("Pad", "Carried")).toBe("pickup")
		expect(SlimeAudioLogic.stateCue("Wild", "Carried")).toBe("pickup")
		expect(SlimeAudioLogic.stateCue("Carried", "Pad")).toBe("putdown")
		expect(SlimeAudioLogic.stateCue("Carried", "Wild")).toBe("putdown")
		expect(SlimeAudioLogic.stateCue("Carried", nil)).toBeNil()
		expect(SlimeAudioLogic.stateCue(nil, "Carried")).toBeNil()
		expect(SlimeAudioLogic.stateCue("Wild", "Pad")).toBeNil()
	end)

	it("pitches bigger slimes lower, inside SPEED_MIN..SPEED_MAX", function()
		local small = SlimeAudioLogic.speedFor(Config.MIN_SIZE, cfg)
		local big = SlimeAudioLogic.speedFor(Config.MAX_SIZE, cfg)
		expect(small > big).toBe(true)
		expect(SlimeAudioLogic.speedFor(1, cfg)).toBeCloseTo(cfg.SPEED_AT_SIZE_1)
		expect(SlimeAudioLogic.speedFor(100, cfg)).toBe(cfg.SPEED_MIN)
		expect(SlimeAudioLogic.speedFor(-100, cfg)).toBe(cfg.SPEED_MAX)
		expect(SlimeAudioLogic.speedFor(nil, cfg)).toBeCloseTo(cfg.SPEED_AT_SIZE_1)
	end)
end)
