--!strict
local fs = require("@lune/fs")

local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("PlotDecor LockSign text", function()
	it("a free plot shows no sign text; owned plots keep LOCKED / UNLOCKED", function()
		local src = fs.readFile("src/visuals/shared/PlotDecor.luau")
		expect(string.find(string.lower(src), "free plot", 1, true)).toBeNil()
		expect(string.find(src, 'if not owned then "" elseif locked then "LOCKED" else "UNLOCKED"', 1, true) ~= nil).toBe(
			true
		)
	end)
end)
