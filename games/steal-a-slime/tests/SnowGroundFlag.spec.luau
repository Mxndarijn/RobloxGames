--!strict
-- SnowGround v2 ships on (FEATURES.SnowGround): it tints the existing surfaces instead of laying the flat
-- snow sheet that was cut in #223. Snowfall particles stay with FEATURES.Weather.
local fs = require("@lune/fs")

local Config = require("../src/shared/Config")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("SnowGround flag", function()
	it("is on and WeatherFx checks it before SnowGround.start", function()
		expect(Config.FEATURES.SnowGround).toBe(true)
		local source = fs.readFile("src/visuals/client/WeatherFx.luau")
		local gate = string.find(source, "Config.FEATURES.SnowGround", 1, true)
		local start = string.find(source, "SnowGround.start(", 1, true)
		expect(gate ~= nil and start ~= nil and (gate :: number) < (start :: number)).toBe(true)
	end)
end)
