--!strict
-- The floating price tag over the next buyable pad (visuals/client/PadPriceTag): what it says.
local PadPriceTagLook = require("../src/visuals/shared/PadPriceTagLook")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("PadPriceTagLook.view", function()
	it("splits the prompt into a title and a price, green when the player can pay", function()
		expect(PadPriceTagLook.view("Buy pad $625", 625, 1000)).toEqual({
			title = "BUY PAD",
			price = "$625",
			affordable = true,
		})
		expect(PadPriceTagLook.view("Build floor 2 $30K", 30000, 100)).toEqual({
			title = "BUILD FLOOR 2",
			price = "$30K",
			affordable = false,
		})
	end)
	it("shows nothing without a price (every cash pad bought, or a free plot)", function()
		expect(PadPriceTagLook.view("Rebirth for +2 pads", nil, 5)).toBeNil()
		expect(PadPriceTagLook.view(nil, 100, 5)).toBeNil()
	end)
end)
