--!strict
-- A dropped wild egg's smash show as numbers (contract/mystery-egg.md 40.7).
local Config = require("../src/shared/Config")
local TestRunner = require("./TestRunner")
local Timeline = require("../src/visuals/shared/EggSmashTimeline")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("EggSmashTimeline", function()
	it("falls from its height to the ground, faster than it looks in real gravity, never for too long", function()
		local seconds = Timeline.fallSeconds(4)
		expect(seconds > 0).toBe(true)
		expect(Timeline.fallSeconds(500)).toBe(Timeline.MAX_FALL)
		expect(Timeline.fallSeconds(0)).toBe(Timeline.fallSeconds(Timeline.MIN_DROP))
		local top = Timeline.fall(0, 4)
		local bottom = Timeline.fall(seconds, 4)
		expect(top).toBe(4)
		expect(bottom).toBe(0)
		local mid = Timeline.fall(seconds / 2, 4)
		expect(mid > 2).toBe(true) -- slow at first, fast at the end
	end)
	it("squashes wider and flatter on impact", function()
		local wide0, tall0 = Timeline.squash(0)
		expect(wide0).toBe(1)
		expect(tall0).toBe(1)
		local wide, tall = Timeline.squash(Timeline.SQUASH_SECONDS)
		expect(wide).toBe(Timeline.SQUASH_WIDE)
		expect(tall).toBe(Timeline.SQUASH_TALL)
	end)
	it("throws every shard outwards above the ground, then lets it rest and fade out", function()
		for i = 1, Timeline.SHARDS do
			local lastDist = 0
			for k = 1, 40 do
				local s = Timeline.SHARD_SECONDS * k / 40
				local x, y, z, _, fade = Timeline.shard(i, Timeline.SHARDS, s)
				local dist = math.sqrt(x * x + z * z)
				expect(y >= 0).toBe(true)
				expect(dist >= lastDist - 1e-9).toBe(true)
				expect(fade >= 0 and fade <= 1).toBe(true)
				lastDist = dist
			end
			local _, yEnd, _, _, fadeEnd = Timeline.shard(i, Timeline.SHARDS, Timeline.SHARD_SECONDS)
			expect(yEnd).toBe(0)
			expect(fadeEnd).toBe(1)
			local _, _, _, _, fadeEarly = Timeline.shard(i, Timeline.SHARDS, 0.2)
			expect(fadeEarly).toBe(0)
		end
	end)
	it("spreads the splat to full size, then fades it with the shards", function()
		local small = Timeline.splat(0)
		local full, shown = Timeline.splat(Timeline.SPLAT_GROW)
		expect(small).toBe(0)
		expect(math.abs(full - Timeline.SPLAT_SIZE) < 1e-9).toBe(true)
		expect(shown < 0.5).toBe(true)
		local _, gone = Timeline.splat(Timeline.SHARD_SECONDS)
		expect(gone).toBe(1)
	end)
	it("is over well within the time the server keeps the egg plus the show", function()
		expect(Timeline.SERVER_SECONDS).toBe(Config.MYSTERY_EGG.SMASH_SECONDS)
		expect(Timeline.LATE_SECONDS < Timeline.SERVER_SECONDS).toBe(true)
		expect(Timeline.total(500) < 3).toBe(true)
	end)
end)
