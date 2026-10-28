--!strict
local GuideMarker = require("../../src/guide/GuideMarker")
local T = require("../../testing/TestRunner")
local describe, it, expect = T.describe, T.it, T.expect

-- A label anchored at y = 10 whose bottom edge sits on the anchor (SizeOffset.Y 0.5), 1 stud plus 40 px tall.
local function tag(overrides: { [string]: any }?): GuideMarker.Label
	local label: { [string]: any } = { y = 10, scaleY = 1, offsetY = 40, sizeOffsetY = 0.5 }
	for k, v in overrides or {} do
		label[k] = v
	end
	return label :: any
end

describe("GuideMarker.labelTop", function()
	it("puts the top of a bottom-anchored label one label height above its anchor", function()
		-- 40 px at 20 px per stud is 2 studs, plus the 1 stud: 3 studs tall
		expect(GuideMarker.labelTop(tag(), 20)).toBeCloseTo(13)
	end)

	it("puts the top of a centred label half a height above its anchor", function()
		expect(GuideMarker.labelTop(tag({ sizeOffsetY = 0 }), 20)).toBeCloseTo(11.5)
	end)

	it("grows in studs as the camera moves away (the px part covers more of the world)", function()
		local near = GuideMarker.labelTop(tag(), 40)
		local far = GuideMarker.labelTop(tag(), 5)
		expect(far > near).toBe(true)
	end)

	it("uses the label's own px per stud when it has one", function()
		expect(GuideMarker.labelTop(tag({ pxPerStud = 40 }), 20)).toBeCloseTo(12)
	end)
end)

describe("GuideMarker.top", function()
	it("keeps the target's top with no labels", function()
		expect(GuideMarker.top(4, {}, 20)).toBe(4)
	end)

	it("keeps the target's top when every label is below it", function()
		expect(GuideMarker.top(20, { tag() }, 20)).toBe(20)
	end)

	it("lifts to the highest label", function()
		local low, high = tag(), tag({ y = 12 })
		expect(GuideMarker.top(4, { low, high }, 20)).toBeCloseTo(15)
	end)
end)

describe("GuideMarker.pxPerStud", function()
	it("halves when the depth doubles", function()
		local a = GuideMarker.pxPerStud(720, 70, 10)
		local b = GuideMarker.pxPerStud(720, 70, 20)
		expect(a / b).toBeCloseTo(2)
	end)

	it("fills the viewport height with the visible height at that depth", function()
		local depth, fov, h = 10, 70, 720
		local visible = 2 * depth * math.tan(math.rad(fov) / 2)
		expect(GuideMarker.pxPerStud(h, fov, depth) * visible).toBeCloseTo(h)
	end)
end)
