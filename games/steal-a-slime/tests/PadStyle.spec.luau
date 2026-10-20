--!strict
-- v17: locked pads read as "not available" through colour + material only.
local PadStyle = require("../src/shared/PadStyle")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function sat(c: { number }): number
	return math.max(c[1], c[2], c[3]) - math.min(c[1], c[2], c[3])
end

local function lum(c: { number }): number
	return c[1] + c[2] + c[3]
end

describe("PadStyle (v17)", function()
	local base = { 90, 200, 120 }

	it("unlocked pads keep the exact base colour and material", function()
		local rgb, material = PadStyle.look(base, "SmoothPlastic", true)
		expect(rgb[1]).toBe(90)
		expect(rgb[2]).toBe(200)
		expect(rgb[3]).toBe(120)
		expect(material).toBe("SmoothPlastic")
	end)

	it("locked pads are desaturated, darker and Slate", function()
		local rgb, material = PadStyle.look(base, "SmoothPlastic", false)
		expect(material).toBe("Slate")
		expect(sat(rgb) < sat(base) / 2).toBe(true)
		expect(lum(rgb) < lum(base)).toBe(true)
	end)

	it("every plot colour gives a locked look distinct from its unlocked look", function()
		for _, c in { { 255, 255, 255 }, { 0, 0, 0 }, { 230, 90, 90 }, { 90, 110, 230 } } do
			local rgb = PadStyle.lockedColor(c)
			for i = 1, 3 do
				expect(rgb[i] >= 0 and rgb[i] <= 255).toBe(true)
			end
			expect(rgb[1] ~= c[1] or rgb[2] ~= c[2] or rgb[3] ~= c[3]).toBe(true)
		end
	end)

	it("lock then unlock returns the stored base look (transition)", function()
		local lockedRgb, lockedMat = PadStyle.look(base, "SmoothPlastic", false)
		expect(lockedMat).toBe("Slate")
		expect(lockedRgb[1] ~= base[1]).toBe(true)
		local rgb, material = PadStyle.look(base, "SmoothPlastic", true)
		expect(rgb[2]).toBe(200)
		expect(material).toBe("SmoothPlastic")
	end)

	it("free plot: every pad keeps the base look; owned: only locked pads are styled; leaving restores", function()
		local function padLook(owned: boolean, pad: number, padsUnlocked: number)
			return PadStyle.look(base, "SmoothPlastic", PadStyle.showsUnlocked(owned, pad <= padsUnlocked))
		end
		for pad = 1, 6 do
			local rgb, material = padLook(false, pad, 2)
			expect(rgb[1]).toBe(90)
			expect(material).toBe("SmoothPlastic")
		end
		local _, lockedMat = padLook(true, 5, 2)
		expect(lockedMat).toBe("Slate")
		local rgb, unlockedMat = padLook(true, 1, 2)
		expect(rgb[2]).toBe(200)
		expect(unlockedMat).toBe("SmoothPlastic")
		-- owner leaves: same pad, owned -> free
		local freed, freedMat = padLook(false, 5, 2)
		expect(freed[1]).toBe(90)
		expect(freedMat).toBe("SmoothPlastic")
	end)

	it("adds no parts: the pad stays one Pad + one Stand with the same size", function()
		local plots = WorldLayout.build()
		local count, pads = 0, 0
		local function walk(nodes: { WorldLayout.WorldNode }?)
			for _, n in nodes or {} do
				if n.name:match("^Pad_%d+$") then
					pads += 1
					count += #(n.children or {})
					expect(n.size[1]).toBe(WorldLayout.PAD_SIZE)
				end
				walk(n.children)
			end
		end
		walk(plots)
		expect(pads > 0).toBe(true)
		expect(count).toBe(pads)
	end)
end)
