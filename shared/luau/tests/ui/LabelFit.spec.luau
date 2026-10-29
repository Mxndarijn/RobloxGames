--!strict
local LabelFit = require("../../src/ui/LabelFit")
local T = require("../../testing/TestRunner")
local describe, it, expect = T.describe, T.it, T.expect

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 0.05)
end

describe("LabelFit", function()
	it("covers fewer px per stud farther away and on a shorter screen", function()
		local at10 = LabelFit.pxPerStud(1080, 70, 10)
		expect(near(at10, 77.1, 0.1)).toBe(true)
		expect(near(LabelFit.pxPerStud(1080, 70, 20), at10 / 2)).toBe(true)
		expect(LabelFit.pxPerStud(390, 70, 10) < at10).toBe(true)
	end)

	it("never divides by zero at distance 0", function()
		expect(LabelFit.pxPerStud(720, 70, 0) > 0).toBe(true)
	end)

	it("reads text about 20x its height on a phone and 55x on 1080p", function()
		expect(near(LabelFit.readDistance(1, 390), 19.9, 0.2)).toBe(true)
		expect(near(LabelFit.readDistance(1, 1080), 55.1, 0.2)).toBe(true)
		expect(near(LabelFit.readDistance(2, 1080), 2 * LabelFit.readDistance(1, 1080))).toBe(true)
	end)

	it("takes a readablePx override", function()
		expect(LabelFit.readDistance(1, 720, { readablePx = 28 }) < LabelFit.readDistance(1, 720)).toBe(true)
	end)

	it("shrinks pixel tags on small screens, clamped to [minPxScale, 1]", function()
		expect(LabelFit.pxScale(1080)).toBe(1)
		expect(LabelFit.pxScale(720)).toBe(1)
		expect(LabelFit.pxScale(540)).toBe(0.75)
		expect(LabelFit.pxScale(390)).toBe(0.6)
		expect(near(LabelFit.pxScale(390, { minPxScale = 0.5 }), 390 / 720, 1e-9)).toBe(true)
	end)

	it("picks the phone distance only on a phone-sized viewport", function()
		expect(LabelFit.isSmall(390)).toBe(true)
		expect(LabelFit.isSmall(720)).toBe(false)
		expect(LabelFit.maxDistance(60, 40, 390)).toBe(40)
		expect(LabelFit.maxDistance(60, 40, 1080)).toBe(60)
		expect(LabelFit.maxDistance(60, nil, 390)).toBe(60)
	end)

	it("marks a gui with the tag and only the attributes asked for", function()
		local function fakeGui(): any
			local g = { tags = {}, attrs = {} }
			function g.AddTag(self: any, t: string)
				table.insert(self.tags, t)
			end
			function g.SetAttribute(self: any, k: string, v: any)
				self.attrs[k] = v
			end
			return g
		end
		local plain = fakeGui()
		LabelFit.mark(plain)
		expect(plain.tags[1]).toBe(LabelFit.TAG)
		expect(next(plain.attrs)).toBe(nil)
		local phone = fakeGui()
		LabelFit.mark(phone, { phoneDistance = 40, keepSize = true })
		expect(phone.attrs[LabelFit.PHONE_DISTANCE]).toBe(40)
		expect(phone.attrs[LabelFit.KEEP_SIZE]).toBe(true)
	end)

	it("scales a pixel size and rounds to whole px", function()
		local w, h = LabelFit.scalePx(220, 104, 0.6)
		expect(w).toBe(132)
		expect(h).toBe(62)
	end)
end)
