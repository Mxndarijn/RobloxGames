--!strict
-- The Mystery Egg hatch show timeline (contract/mystery-egg.md §40.6) and the label that waits for its reveal.
local Config = require("../src/shared/Config")
local SlimeLabel = require("../src/shared/SlimeLabel")
local TestRunner = require("./TestRunner")
local Timeline = require("../src/visuals/shared/EggHatchTimeline")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("EggHatchTimeline", function()
	it("runs wobble, hold, pop, reveal, done in order and reveals when the server does", function()
		expect(Timeline.phase(0)).toBe("wobble")
		expect(Timeline.phase(Timeline.WOBBLE_END)).toBe("hold")
		expect(Timeline.phase(Timeline.BURST)).toBe("pop")
		expect(Timeline.phase(Timeline.REVEAL)).toBe("reveal")
		expect(Timeline.phase(Timeline.END)).toBe("done")
		expect(Timeline.REVEAL).toBe(Config.MYSTERY_EGG.HATCH_REVEAL_SECONDS)
		expect(Timeline.WOBBLE_END < Timeline.BURST and Timeline.BURST < Timeline.REVEAL).toBe(true)
		expect(Timeline.END <= Config.MYSTERY_EGG.HATCH_FX_SECONDS).toBe(true)
	end)
	it("rocks three times, each harder, then shivers and stands still after the burst", function()
		local peaks = {}
		for n = 1, Timeline.WOBBLES do
			local each = Timeline.WOBBLE_END / Timeline.WOBBLES
			peaks[n] = Timeline.tilt((n - 1) * each + each / 4)
			expect(Timeline.wobble((n - 1) * each + 0.01)).toBe(n)
		end
		expect(peaks[1] < peaks[2] and peaks[2] < peaks[3]).toBe(true)
		expect(math.abs(Timeline.tilt(Timeline.WOBBLE_END + 0.02)) <= math.rad(3)).toBe(true)
		expect(Timeline.tilt(Timeline.BURST + 0.1)).toBe(0)
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
		expect(Timeline.glowTier(Timeline.WOBBLE_END + 0.1, steps)).toBe(7)
		expect(Timeline.steps(5, 3)).toEqual({ 3 })
	end)
	it("keeps the slime tiny until the burst, overshoots, and lands on its own size", function()
		expect(Timeline.slimeScale(0)).toBe(Timeline.HIDDEN_SCALE)
		expect(Timeline.slimeScale(Timeline.BURST - 0.01)).toBe(Timeline.HIDDEN_SCALE)
		local most = 0
		for t = Timeline.BURST, Timeline.REVEAL, 0.01 do
			most = math.max(most, Timeline.slimeScale(t))
		end
		expect(most > 1.1).toBe(true)
		expect(Timeline.slimeScale(Timeline.REVEAL)).toBe(1)
	end)
	it("lands every shard on the ground, near the pad", function()
		for i = 1, Timeline.SHARDS do
			local x, y, z = Timeline.shard(i, Timeline.SHARDS, Timeline.SHARD_SECONDS)
			expect(y >= 0.2).toBe(true)
			expect(math.sqrt(x * x + z * z) < 8).toBe(true)
		end
	end)
	it("titles the hatch by rarity, with LUCKY! in front for a lucky one", function()
		expect(Timeline.title(5, false)).toBe("LEGENDARY!")
		expect(Timeline.title(6, true)).toBe("LUCKY! MYTHIC!")
		expect(Timeline.beam(Timeline.BURST + 0.5, 3)).toBeNil()
		expect(Timeline.beam(Timeline.BURST + 0.5, 4) ~= nil).toBe(true)
	end)
	it("zooms the owner's camera only around the burst and gives it back", function()
		expect(Timeline.zoom(0)).toBe(0)
		expect(Timeline.zoom(Timeline.BURST) > 0).toBe(true)
		expect(Timeline.zoom(Timeline.END)).toBe(0)
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
