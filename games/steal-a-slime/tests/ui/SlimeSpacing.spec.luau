--!strict
-- SlimeSpacing (src/ui/SlimeSpacing.luau, contract/slime-life.md "Clean lane"): drawn slimes that overlap are eased
-- apart within a few frames, slimes with room keep their spot, and a push eases back once the other has passed.
local SlimeSpacing = require("../../src/ui/SlimeSpacing")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local DT = 1 / 60

local function gap(a: SlimeSpacing.Item, b: SlimeSpacing.Item): number
	return math.sqrt(((a.x + a.px) - (b.x + b.px)) ^ 2 + ((a.z + a.pz) - (b.z + b.pz)) ^ 2) - a.r - b.r
end

describe("SlimeSpacing", function()
	it("leaves slimes with room alone", function()
		local a = { x = 0, z = 0, r = 1.5, px = 0, pz = 0 }
		local b = { x = 4, z = 0, r = 1.5, px = 0, pz = 0 }
		for _ = 1, 60 do
			SlimeSpacing.step({ a, b }, DT)
		end
		expect(a.px).toBe(0)
		expect(b.px).toBe(0)
	end)

	it("eases two overlapping slimes apart within a few frames, half each", function()
		local a = { x = 0, z = 0, r = 1.5, px = 0, pz = 0 }
		local b = { x = 1.5, z = 0, r = 1.5, px = 0, pz = 0 }
		for _ = 1, 8 do
			SlimeSpacing.step({ a, b }, DT)
		end
		expect(gap(a, b) > -0.1).toBe(true)
		expect(a.px < 0 and b.px > 0).toBe(true)
		expect(math.abs(a.px + b.px) < 1e-6).toBe(true)
	end)

	it("never jumps: the first frame moves only part of the way", function()
		local a = { x = 0, z = 0, r = 1.5, px = 0, pz = 0 }
		local b = { x = 1, z = 0, r = 1.5, px = 0, pz = 0 }
		SlimeSpacing.step({ a, b }, DT)
		expect(math.abs(a.px) < 1.1).toBe(true)
		expect(math.abs(a.px) > 0.1).toBe(true)
	end)

	it("eases back slowly once the other slime has gone", function()
		local a = { x = 0, z = 0, r = 1.5, px = 0, pz = 0 }
		local b = { x = 1.5, z = 0, r = 1.5, px = 0, pz = 0 }
		for _ = 1, 30 do
			SlimeSpacing.step({ a, b }, DT)
		end
		local pushed = a.px
		b.x = 50
		SlimeSpacing.step({ a, b }, DT)
		expect(a.px < 0 and a.px > pushed * 0.95 - 1e-9).toBe(true) -- one frame later: still most of the way out
		for _ = 1, 120 do
			SlimeSpacing.step({ a, b }, DT)
		end
		expect(math.abs(a.px) < 0.01).toBe(true)
	end)

	it("parts two slimes drawn on the same spot, and caps the push", function()
		local a = { x = 3, z = 3, r = 1.5, px = 0, pz = 0 }
		local b = { x = 3, z = 3, r = 1.5, px = 0, pz = 0 }
		for _ = 1, 60 do
			SlimeSpacing.step({ a, b }, DT)
		end
		expect(gap(a, b) > -0.1).toBe(true)
		for _, item in { a, b } do
			expect(math.sqrt(item.px ^ 2 + item.pz ^ 2) <= SlimeSpacing.MAX_PUSH + 1e-6).toBe(true)
		end
	end)
end)
