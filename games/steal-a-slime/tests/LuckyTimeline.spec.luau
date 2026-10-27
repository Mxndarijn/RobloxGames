--!strict
local Config = require("../src/shared/Config")
local LuckyTimeline = require("../src/visuals/shared/LuckyTimeline")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("LuckyTimeline", function()
	it("glows until the server's morph, bursts for a short while after it", function()
		local morph = Config.LUCKY_SHOW.MORPH_SECONDS
		expect(LuckyTimeline.phase(-0.1)).toBeNil()
		expect(LuckyTimeline.phase(0)).toBe("glow")
		expect(LuckyTimeline.phase(morph - 0.01)).toBe("glow")
		expect(LuckyTimeline.phase(morph)).toBe("burst")
		expect(LuckyTimeline.phase(morph + LuckyTimeline.LATE)).toBeNil()
	end)
	it("the burst and title end, and stay in range while they play", function()
		for i = 0, 20 do
			local s = i / 20 * LuckyTimeline.BURST_SECONDS
			local look = LuckyTimeline.burst(s)
			if look then
				expect(look.mix >= 0 and look.mix <= 1).toBe(true)
				expect(look.ringFade >= 0 and look.ringFade <= 1).toBe(true)
				expect(look.light >= 0).toBe(true)
			end
		end
		expect(LuckyTimeline.burst(LuckyTimeline.BURST_SECONDS)).toBeNil()
		expect((LuckyTimeline.titleLook(LuckyTimeline.TITLE_SECONDS))).toBeNil()
		for i = 0, 30 do
			local g = LuckyTimeline.glow(i / 30 * LuckyTimeline.MORPH)
			expect(g >= 0 and g <= 1).toBe(true)
		end
	end)
	it("names both rarities in the title", function()
		local top, step = LuckyTimeline.title(5, 6)
		expect(top).toBe("🍀 LUCKY!")
		expect(string.find(step, "Legendary", 1, true) ~= nil).toBe(true)
		expect(string.find(step, "Mythic", 1, true) ~= nil).toBe(true)
		expect(string.find(step, "#FFBE28", 1, true) ~= nil).toBe(true) -- Legendary's colour
	end)
end)

describe("LuckyTimeline title sign", function()
	local EggHatchTimeline = require("../src/visuals/shared/EggHatchTimeline")
	it("follows the hatch title: near only, and others see it only from Epic up", function()
		expect(LuckyTimeline.TITLE_DISTANCE).toBe(EggHatchTimeline.TITLE_DISTANCE)
		expect(LuckyTimeline.showsTitle(true, 2)).toBe(true)
		expect(LuckyTimeline.showsTitle(false, 2)).toBe(EggHatchTimeline.showsTitle(false, 2))
		expect(LuckyTimeline.showsTitle(false, 6)).toBe(true)
	end)
end)
