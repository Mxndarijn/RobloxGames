--!strict
-- v30 C11: rare-spawn beams must stay small markers over their slime. At night the Neon beams (up to 150 x 3
-- studs, visible from 600 studs) read as huge glowing yellow / pink / blue streaks shooting into the sky.
-- Locks the preset data (no Instance needed) and the cleanup contract of PlotVisuals' source.
local RareSpawn = require("../src/visuals/shared/RareSpawn")
local TestRunner = require("./TestRunner")
local fs = require("@lune/fs")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("RareSpawn beams", function()
	it("keeps every tier's beam short, thin and see-through", function()
		for tier, fx in RareSpawn.TIERS do
			local b = fx.beam
			if b then
				expect(b.height <= RareSpawn.MAX_BEAM_HEIGHT).toBe(true)
				expect(b.width <= RareSpawn.MAX_BEAM_WIDTH).toBe(true)
				expect(b.height <= 24).toBe(true)
				expect(b.width <= 1).toBe(true)
				expect(tier >= 3).toBe(true)
			end
		end
		expect(RareSpawn.BEAM_TRANSPARENCY >= 0.6).toBe(true)
	end)

	it("grows the beam with the tier but never past the cap", function()
		local last = 0
		for _, fx in RareSpawn.TIERS do
			if fx.beam then
				expect(fx.beam.height >= last).toBe(true)
				last = fx.beam.height
			end
		end
		expect(last > 0).toBe(true)
	end)
end)

describe("PlotVisuals rare fx lifetime", function()
	local src = fs.readFile("src/visuals/client/PlotVisuals.luau")

	it("only draws fx near the camera and parks the rest", function()
		local range = tonumber(string.match(src, "MAX_FX_DISTANCE = (%d+)"))
		expect(range ~= nil and range <= 200).toBe(true)
		expect(string.find(src, "model.Parent = nil", 1, true) ~= nil).toBe(true)
	end)

	it("destroys the fx when its slime goes away", function()
		expect(string.find(src, "model:Destroy()", 1, true) ~= nil).toBe(true)
		expect(string.find(src, "GetInstanceRemovedSignal", 1, true) ~= nil).toBe(true)
	end)
end)
