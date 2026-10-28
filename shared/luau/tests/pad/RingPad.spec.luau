--!strict
local RingPad = require("../../src/pad/RingPad")
local T = require("../../testing/TestRunner")
local describe, it, expect = T.describe, T.it, T.expect

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

describe("RingPad.shape", function()
	it("fills the defaults and reaches to the ring's outer edge", function()
		local s = RingPad.shape({ radius = 5, width = 2 })
		expect(s.style).toBe("ring")
		expect(s.segments).toBe(RingPad.DEFAULTS.segments.ring)
		expect(s.reach).toBe(6)
		local p = RingPad.shape({ style = "pieces" })
		expect(p.segments).toBe(RingPad.DEFAULTS.segments.pieces)
		expect(p.curve).toBe(RingPad.DEFAULTS.curve)
	end)
	it("keeps a given reach", function()
		expect(RingPad.shape({ reach = 9 }).reach).toBe(9)
	end)
	it("refuses sizes that make no ring", function()
		expect(pcall(RingPad.shape, { radius = 0 })).toBe(false)
		expect(pcall(RingPad.shape, { segments = 2.5 })).toBe(false)
		expect(pcall(RingPad.shape, { radius = 1, width = 2 })).toBe(false)
		expect(pcall(RingPad.shape, { style = "pieces", gap = -1 })).toBe(false)
		expect(pcall(RingPad.shape, { width = 0 / 0 })).toBe(false)
		expect(pcall(RingPad.shape, { style = "square" :: any })).toBe(false)
		expect(pcall(RingPad.shape, { segments = 2 })).toBe(false)
	end)
end)

-- a point `r` studs out from the centre at `angle` (clockwise from the front), then `e` studs round the ring
local function at(angle: number, r: number, e: number): (number, number)
	return r * math.sin(angle) + e * math.cos(angle), -r * math.cos(angle) + e * math.sin(angle)
end

local function coverage(blocks: { RingPad.Block }): (number, number) -> boolean
	return function(x: number, z: number): boolean
		for _, b in blocks do
			local a = -b.yaw
			local dx, dz = x - b.x, z - b.z
			local along = dx * math.cos(a) + dz * math.sin(a)
			local across = dx * math.sin(a) - dz * math.cos(a)
			if math.abs(along) <= b.length / 2 and math.abs(across) <= b.width / 2 then
				return true
			end
		end
		return false
	end
end

describe("RingPad.blocks, ring style", function()
	local shape = RingPad.shape({ radius = 4.6, width = 1.6 })
	local blocks = RingPad.blocks(shape)
	local covered = coverage(blocks)
	local inner, outer = shape.radius - shape.width / 2, shape.radius + shape.width / 2

	it("is one block per segment, starting at the front, clockwise", function()
		expect(#blocks).toBe(shape.segments)
		expect(blocks[1].z < 0).toBe(true)
		expect(blocks[2].x > blocks[1].x).toBe(true)
	end)
	it("is one closed circle: no gaps anywhere round it", function()
		for step = 0, 719 do
			local angle = 2 * math.pi * step / 720
			for _, r in { inner + 0.03, shape.radius, outer - 0.03 } do
				expect(covered(at(angle, r, 0))).toBe(true)
			end
		end
	end)
	it("stays on the ring: nothing past the edges", function()
		for step = 0, 71 do
			local angle = 2 * math.pi * (step + 0.5) / 72
			expect(covered(at(angle, outer + 0.06, 0))).toBe(false)
			expect(covered(at(angle, inner - 0.06, 0))).toBe(false)
		end
	end)
end)

describe("RingPad.blocks, pieces style", function()
	local shape = RingPad.shape({ style = "pieces", segments = 12, curve = 4, radius = 4.6, width = 1.6, gap = 0.2 })
	local blocks = RingPad.blocks(shape)
	local covered = coverage(blocks)
	local piece = 2 * math.pi / shape.segments
	local inner, outer = shape.radius - shape.width / 2, shape.radius + shape.width / 2

	it("has curve blocks for every piece, in order", function()
		expect(#blocks).toBe(48)
		expect(blocks[1].segment).toBe(1)
		expect(blocks[4].segment).toBe(1)
		expect(blocks[5].segment).toBe(2)
		expect(blocks[48].index).toBe(4)
	end)
	it("starts at the front and runs clockwise seen from above", function()
		local first, second = blocks[1], blocks[5]
		expect(first.z < 0).toBe(true)
		expect(math.abs(first.x) < 1.5).toBe(true)
		expect(second.x > first.x).toBe(true)
	end)
	it("every cut is open and gap wide, the same at the inner edge, the middle and the outer edge", function()
		for s = 0, shape.segments - 1 do
			local cut = s * piece
			for _, r in { inner + 0.03, shape.radius, outer - 0.03 } do
				expect(covered(at(cut, r, 0))).toBe(false)
				expect(covered(at(cut, r, shape.gap / 2 - 0.02))).toBe(false)
				expect(covered(at(cut, r, -(shape.gap / 2 - 0.02)))).toBe(false)
				expect(covered(at(cut, r, shape.gap / 2 + 0.02))).toBe(true)
				expect(covered(at(cut, r, -(shape.gap / 2 + 0.02)))).toBe(true)
			end
		end
	end)
	it("has no holes inside a piece", function()
		for s = 0, shape.segments - 1 do
			for step = 1, 39 do
				local angle = s * piece + piece * step / 40
				for _, r in { inner + 0.03, shape.radius, outer - 0.03 } do
					local x, z = r * math.sin(angle), -r * math.cos(angle)
					local cutDistance = r * math.sin(math.min(angle - s * piece, (s + 1) * piece - angle))
					if cutDistance > shape.gap / 2 + 0.02 then
						expect(covered(x, z)).toBe(true)
					end
				end
			end
		end
	end)
	it("stays on the ring: nothing sticks out past the edges", function()
		expect(covered(at(piece / 2, outer + 0.06, 0))).toBe(false)
		expect(covered(at(piece / 2, inner - 0.06, 0))).toBe(false)
	end)
	it("sits lift above the floor", function()
		expect(near(blocks[1].y, shape.lift + shape.thickness / 2)).toBe(true)
	end)
	it("refuses a gap wider than a piece's inner edge", function()
		expect(pcall(RingPad.shape, { style = "pieces", radius = 4.6, width = 1.6, gap = 3 })).toBe(false)
		expect(pcall(RingPad.shape, { style = "pieces", curve = 1 })).toBe(false)
	end)
end)

describe("RingPad.inside", function()
	local shape = RingPad.shape({ radius = 4, width = 2, height = 5 })
	it("counts the ring, the middle and up to height", function()
		expect(RingPad.inside(shape, 5, 1, 0)).toBe(true)
		expect(RingPad.inside(shape, 0, 4.9, 0)).toBe(true)
		expect(RingPad.inside(shape, 3.5, 0, 3.5)).toBe(true)
	end)
	it("not outside the reach, below the floor or too high", function()
		expect(RingPad.inside(shape, 5.1, 1, 0)).toBe(false)
		expect(RingPad.inside(shape, 0, -1.5, 0)).toBe(false)
		expect(RingPad.inside(shape, 0, 5.1, 0)).toBe(false)
		expect(RingPad.inside(shape, 0 / 0, 0, 0)).toBe(false)
	end)
end)

describe("RingPad.hold", function()
	it("fires after standing on it for the full time", function()
		local fired, since = RingPad.hold(nil, true, false, 10, 1)
		expect(fired).toBe(false)
		expect(since).toBe(10)
		fired, since = RingPad.hold(since, true, false, 10.5, 1)
		expect(fired).toBe(false)
		expect(since).toBe(10)
		fired, since = RingPad.hold(since, true, false, 11, 1)
		expect(fired).toBe(true)
		expect(since).toBeNil()
	end)
	it("stepping off or being blocked starts again", function()
		local _, since = RingPad.hold(nil, true, false, 10, 1)
		local fired, after = RingPad.hold(since, false, false, 10.5, 1)
		expect(fired).toBe(false)
		expect(after).toBeNil()
		fired, after = RingPad.hold(10, true, true, 12, 1)
		expect(fired).toBe(false)
		expect(after).toBeNil()
	end)
end)

describe("RingPad.charge and countdown", function()
	it("charge lights a piece per 1/n of the time, all at the end", function()
		expect(RingPad.charge(12, 0, 0, 1)).toBe(0)
		expect(RingPad.charge(12, 0, 0.5, 1)).toBe(6)
		expect(RingPad.charge(12, 0, 3, 1)).toBe(12)
		expect(RingPad.charge(12, 0, 0, 0)).toBe(12)
	end)
	it("countdown starts full, keeps one piece to the end, then none", function()
		expect(RingPad.countdown(12, 0, 120, 0)).toBe(12)
		expect(RingPad.countdown(12, 0, 120, 60)).toBe(6)
		expect(RingPad.countdown(12, 0, 120, 119.9)).toBe(1)
		expect(RingPad.countdown(12, 0, 120, 120)).toBe(0)
		expect(RingPad.countdown(12, 5, 5, 0)).toBe(12)
	end)
end)
