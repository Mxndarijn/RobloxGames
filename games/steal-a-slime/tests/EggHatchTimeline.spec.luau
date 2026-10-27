--!strict
-- The Mystery Egg hatch show timeline (contract/mystery-egg.md §40.6) and the label that waits for its reveal.
local Config = require("../src/shared/Config")
local SlimeLabel = require("../src/shared/SlimeLabel")
local TestRunner = require("./TestRunner")
local Timeline = require("../src/visuals/shared/EggHatchTimeline")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("EggHatchTimeline", function()
	it("wobbles, holds, then bursts when the server swaps the egg for the slime", function()
		expect(Timeline.phase(0)).toBe("wobble")
		expect(Timeline.phase(Timeline.WOBBLE_END)).toBe("hold")
		expect(Timeline.phase(Timeline.BURST)).toBe("burst")
		expect(Timeline.BURST).toBe(Config.MYSTERY_EGG.HATCH_BURST_SECONDS)
		expect(Timeline.BURST < Config.MYSTERY_EGG.HATCH_REVEAL_SECONDS).toBe(true)
		expect(Config.MYSTERY_EGG.HATCH_REVEAL_SECONDS < Config.MYSTERY_EGG.HATCH_FX_SECONDS).toBe(true)
	end)
	it("rocks three times, each harder and with a higher hop, then shakes fast", function()
		local peaks, hops = {}, {}
		local each = Timeline.WOBBLE_END / Timeline.WOBBLES
		for n = 1, Timeline.WOBBLES do
			local most, high = 0, 0
			for k = 0, 40 do
				local t = (n - 1) * each + each * k / 40 * 0.999
				most = math.max(most, math.abs(Timeline.tilt(t)))
				high = math.max(high, Timeline.hop(t))
			end
			peaks[n], hops[n] = most, high
			expect(Timeline.wobble((n - 1) * each + 0.01)).toBe(n)
			expect(Timeline.crackSets((n - 1) * each + 0.01)).toBe(n)
		end
		expect(peaks[1] < peaks[2] and peaks[2] < peaks[3]).toBe(true)
		expect(hops[1] < hops[2] and hops[2] < hops[3]).toBe(true)
		expect(math.abs(Timeline.tilt(Timeline.WOBBLE_END + 0.02)) <= math.rad(5)).toBe(true)
		expect(Timeline.crackSets(Timeline.WOBBLE_END + 0.1)).toBe(Timeline.WOBBLES)
		expect(Timeline.swell(Timeline.BURST - 0.01) > 1.1).toBe(true)
		expect(Timeline.swell(0)).toBe(1)
	end)
	it("climbs the rarity colours from the kind's lowest drop to the hatched tier", function()
		local steps = Timeline.steps(4, 7)
		expect(steps).toEqual({ 4, 5, 6, 7 })
		expect(Timeline.glowTier(0.1, steps)).toBe(4)
		local last = 0
		for t = 0, Timeline.BURST, 0.05 do
			local tier = Timeline.glowTier(t, steps)
			expect(tier >= last).toBe(true)
			last = tier
		end
		expect(Timeline.glowTier(Timeline.WOBBLE_END - 0.05, steps)).toBe(7)
		expect(Timeline.steps(5, 3)).toEqual({ 3 })
	end)
	it("pops the slime copy from tiny past full size and lands on its own size", function()
		expect(Timeline.popScale(0)).toBe(Timeline.HIDDEN_SCALE)
		local most = 0
		for s = 0, Timeline.POP_SECONDS, 0.01 do
			most = math.max(most, Timeline.popScale(s))
		end
		expect(most > 1.1).toBe(true)
		expect(Timeline.popScale(Timeline.POP_SECONDS)).toBe(1)
	end)
	it("lands every shard and the lid on the ground, near the pad", function()
		for i = 1, Timeline.SHARDS do
			local x, y, z = Timeline.shard(i, Timeline.SHARDS, Timeline.SHARD_SECONDS)
			expect(y >= 0.2).toBe(true)
			expect(math.sqrt(x * x + z * z) < 12).toBe(true)
		end
		expect((Timeline.lid(Timeline.SHARD_SECONDS))).toBe(0.2)
	end)
	it("shows the owner a screen title for any hatch and others a world sign only for Epic and up", function()
		expect(Timeline.titleView(true, 1)).toBe("screen")
		expect(Timeline.titleView(true, Config.MAX_TIER)).toBe("screen")
		expect(Timeline.titleView(false, Timeline.OTHERS_TITLE_TIER - 1)).toBeNil()
		expect(Timeline.titleView(false, Timeline.OTHERS_TITLE_TIER)).toBe("world")
		expect(Timeline.titleView(false, Config.MAX_TIER)).toBe("world")
		expect(Config.RARITIES[Timeline.OTHERS_TITLE_TIER].name).toBe("Epic")
	end)
	it("titles the hatch by rarity, with LUCKY! in front for a lucky one", function()
		expect(Timeline.title(5, false)).toBe("LEGENDARY!")
		expect(Timeline.title(6, true)).toBe("LUCKY! MYTHIC!")
		expect(Timeline.beam(0.5, 3)).toBeNil()
		expect(Timeline.beam(0.5, 4) ~= nil).toBe(true)
		expect((Timeline.titleLook(Timeline.TITLE_SECONDS))).toBeNil()
	end)
	it("zooms the owner's camera only around the burst and gives it back", function()
		expect(Timeline.zoom(0)).toBe(0)
		expect(Timeline.zoom(Timeline.BURST) > 0).toBe(true)
		expect(Timeline.zoom(Timeline.BURST + 2)).toBe(0)
	end)
end)

describe("SlimeLabel.hiddenByHatch", function()
	it("hides a hatched slime's label until the reveal, never a plain slime's", function()
		local at = 1000
		expect(SlimeLabel.hiddenByHatch(at, at)).toBe(true)
		expect(SlimeLabel.hiddenByHatch(at, at + Config.MYSTERY_EGG.HATCH_REVEAL_SECONDS - 0.01)).toBe(true)
		expect(SlimeLabel.hiddenByHatch(at, at + Config.MYSTERY_EGG.HATCH_REVEAL_SECONDS)).toBe(false)
		expect(SlimeLabel.hiddenByHatch(nil, at)).toBe(false)
	end)
end)
