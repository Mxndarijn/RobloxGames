--!strict
-- v30 C5: fence pieces abut exactly: the 10/11 slot scale makes every kit
-- piece (ranch_fence_20: 22 native, phoenix_fence_segment: 11) as long as its
-- grid step, so neighbours neither overlap (z-fight) nor leave a gap, and a
-- side is covered from corner to corner (the gate slot is the one opening).
local Config = require("../src/shared/Config")
local MeshAssets = require("../src/shared/MeshAssets")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function span(seg: any): (number, number)
	-- coordinate along the side (x for Back/Front, z for Left/Right)
	local t = if seg.side == "Back" or seg.side == "Front" then seg.x else seg.z
	return t - seg.length / 2, t + seg.length / 2
end

describe("fence joints (v30 C5)", function()
	local segs = WorldLayout.fenceSegments()
	it("kit piece lengths at FENCE_SCALE equal their grid step", function()
		expect(
			math.abs(MeshAssets.get("ranch_fence_20").size[1] * WorldLayout.FENCE_SCALE - WorldLayout.FENCE_GRID) < 1e-9
		).toBe(true)
		local seg = MeshAssets.get("phoenix_fence_segment").size[1] * WorldLayout.FENCE_SCALE
		expect(math.abs(seg - WorldLayout.FENCE_SEGMENT_GRID) < 1e-9).toBe(true)
	end)
	it("neighbouring pieces on a side touch exactly: no overlap, no gap", function()
		local sides: { [string]: { any } } = {}
		for _, seg in segs do
			sides[seg.side] = sides[seg.side] or {}
			table.insert(sides[seg.side], seg)
		end
		for side, list in sides do
			table.sort(list, function(a, b)
				return (span(a)) < (span(b))
			end)
			for i = 2, #list do
				local _, prevEnd = span(list[i - 1])
				local start = span(list[i])
				-- the gate slot is the one allowed opening, on the front
				local gap = start - prevEnd
				if side == "Front" and math.abs(gap - WorldLayout.GATE_SLOT) < 1e-9 then
					continue
				end
				expect(math.abs(gap) < 1e-9).toBe(true)
			end
		end
	end)
	it("every side runs corner to corner", function()
		local half = WorldLayout.PLOT_SIZE / 2
		local lo, hi = {}, {}
		for _, seg in segs do
			local a, b = span(seg)
			lo[seg.side] = math.min(lo[seg.side] or math.huge, a)
			hi[seg.side] = math.max(hi[seg.side] or -math.huge, b)
		end
		for _, side in { "Back", "Left", "Right", "Front" } do
			expect(math.abs(lo[side] + half) < 1e-9).toBe(true)
			expect(math.abs(hi[side] - half) < 1e-9).toBe(true)
		end
		expect(Config.PLOT_COUNT > 0).toBe(true)
	end)
end)
