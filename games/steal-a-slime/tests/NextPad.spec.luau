--!strict
local NextPad = require("../src/visuals/shared/NextPad")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("NextPad.tag", function()
	it("says Buy pad once you can afford the next pad", function()
		local t = NextPad.tag(1500, 2000) :: NextPad.Tag
		expect(t.affordable).toBe(true)
		expect(t.text).toBe("Buy pad $1.5K")
	end)
	it("says Next pad with the price while you are short, or your cash is unknown", function()
		local short = NextPad.tag(1500, 1499) :: NextPad.Tag
		expect(short.affordable).toBe(false)
		expect(short.verb).toBe("Next pad")
		expect(short.price).toBe("$1.5K")
		expect((NextPad.tag(1500, nil) :: NextPad.Tag).affordable).toBe(false)
	end)
	it("shows nothing when no pad is left to buy", function()
		expect(NextPad.tag(nil, 100)).toBeNil()
	end)
end)
