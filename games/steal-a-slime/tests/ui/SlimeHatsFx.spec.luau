--!strict
-- SlimeHatsFx (src/ui/SlimeHatsFx.luau): Exclusive slime hats on the owner's pad slimes (contract/exclusive-shop.md §15).
local Config = require("../../src/shared/Config")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local SlimeHatsFx = UiHarness.ui("SlimeHatsFx")
local HATS = Config.EXCLUSIVE_SHOP.hats

describe("SlimeHatsFx", function()
	it(
		"puts the owner's plot hat on a slime standing on a pad, never on an egg, a carried slime or a bare plot",
		function()
			local plotHats = { [7] = "party" }
			expect(SlimeHatsFx.want(7, "Pad", false, plotHats, HATS)).toBe("slime_hat_party")
			expect(SlimeHatsFx.want(7, "Pad", true, plotHats, HATS)).toBeNil() -- an egg
			expect(SlimeHatsFx.want(7, "Carried", false, plotHats, HATS)).toBeNil() -- the hat belongs to the pad
			expect(SlimeHatsFx.want(8, "Pad", false, plotHats, HATS)).toBeNil() -- that owner wears none
			expect(SlimeHatsFx.want(7, "Pad", false, { [7] = "nope" }, HATS)).toBeNil()
			expect(SlimeHatsFx.want(nil, "Pad", false, plotHats, HATS)).toBeNil()
		end
	)
	it("scales the hat to WIDTH of the slime and seats it SINK below the slime's top", function()
		local size, up = SlimeHatsFx.fit({ 2.5, 1.7, 2.5 }, { 2, 2, 2 })
		expect(math.abs(size[1] - 2.5 * SlimeHatsFx.WIDTH) < 1e-9).toBe(true)
		expect(math.abs(size[2] - size[1]) < 1e-9).toBe(true) -- one uniform scale
		expect(math.abs(up - (1.7 / 2 - 1.7 * SlimeHatsFx.SINK + size[2] / 2)) < 1e-9).toBe(true)
	end)
end)
