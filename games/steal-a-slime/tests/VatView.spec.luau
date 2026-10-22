--!strict
-- How the merge vat reads in the world (VatView, CONTRACT.md §21): the pill over the vat, the pad sign status of
-- a slime in the vat and where the three spots sit.
local Fixtures = require("./Fixtures")
local TestRunner = require("./TestRunner")
local VatState = require("../src/shared/VatState")
local VatView = require("../src/server/VatView")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local NOW = 1_800_000_000

local function plot(ids: { string }): any
	local data = Fixtures.data({ Fixtures.slime("a", 1), Fixtures.slime("b", 1), Fixtures.slime("c", 1) })
	for _, id in ids do
		assert(VatState.add(data, id), id)
	end
	return data
end

describe("VatView.tagLine", function()
	it("says how to fill an empty vat, then the load", function()
		expect(VatView.tagLine(plot({}), NOW).text).toBe("Move slimes in")
		local line = VatView.tagLine(plot({ "a" }), NOW)
		expect(line.text).toBe("1/3 Common")
		expect(line.color).toBe("Mint")
	end)

	it("counts down while brewing and turns gold when ready", function()
		local data = plot({ "a", "b", "c" })
		VatState.start(data, NOW)
		expect(VatView.tagLine(data, NOW + 18).text).toBe("Brewing 0:12")
		local ready = VatView.tagLine(data, NOW + 30)
		expect(ready.text).toBe("Ready")
		expect(ready.color).toBe("Gold")
	end)
end)

describe("VatView.labelStatus", function()
	it("In vat while it waits, IN VAT while it brews, nothing for other slimes", function()
		local data = plot({ "a", "b", "c" })
		expect(VatView.labelStatus(data, "a")).toBe("In vat")
		VatState.start(data, NOW)
		expect(VatView.labelStatus(data, "a")).toBe("IN VAT")
		expect(VatView.labelStatus(plot({ "a" }), "b")).toBe(nil)
	end)
end)

describe("VatView.spotOffset", function()
	it("puts the three spots apart on the goo, inside the vat", function()
		local points = {}
		for i = 1, 3 do
			local x, z = VatView.spotOffset(i)
			expect(math.sqrt(x * x + z * z) <= VatView.SPOT_RADIUS + 1e-6).toBe(true)
			points[i] = { x, z }
		end
		for i = 1, 3 do
			local j = i % 3 + 1
			local dx, dz = points[i][1] - points[j][1], points[i][2] - points[j][2]
			expect(math.sqrt(dx * dx + dz * dz) >= VatView.SPOT_WIDTH).toBe(true)
		end
	end)
end)
