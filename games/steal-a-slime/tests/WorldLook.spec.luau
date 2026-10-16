--!strict
-- Look fixes from the whole-world render review (tools/render):
-- Map.Decor scattered rocks (WorldLayout rock()) are low boulders and slabs
-- sunk into the Ground, never an upright grey box or a corner floating over
-- it; the ring path's overlapping segments never share a top face; the plot
-- lock sign and button pedestal are ranch wood, not gunmetal.
local LayoutMath = require("../src/visuals/shared/LayoutMath")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function folder(name: string, pattern: string): { any }
	local out = {}
	for _, c in WorldLayout.build()[1].children do
		if c.name == name then
			for _, n in c.children do
				if string.match(n.name, pattern) then
					table.insert(out, n)
				end
			end
		end
	end
	return out
end

describe("decor rocks", function()
	local all = folder("Decor", "^Rock%d+$")
	it("keeps the scatter (boulders and slabs, same count)", function()
		local balls, blocks = 0, 0
		for _, n in all do
			if n.shape == "Ball" then
				balls += 1
			else
				blocks += 1
			end
		end
		expect(#all >= 30).toBe(true)
		expect(balls >= 10).toBe(true)
		expect(blocks >= 10).toBe(true)
	end)
	it("stands low: never taller above the Ground than half its width", function()
		for _, n in all do
			local top = n.pos[2] + n.size[2] / 2
			expect(top <= 0.5 * math.max(n.size[1], n.size[3])).toBe(true)
		end
	end)
	it("is sunk: every bottom corner of a slab is at or under the Ground top", function()
		for _, n in all do
			if n.shape == "Ball" then
				expect(n.pos[2] < 0).toBe(true)
			else
				local m = LayoutMath.orientation(n.rot)
				local h = { n.size[1] / 2, n.size[2] / 2, n.size[3] / 2 }
				for _, s in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
					local corner = LayoutMath.apply(m, { h[1] * s[1], -h[2], h[3] * s[2] })
					expect(n.pos[2] + corner[2] <= 0.001).toBe(true)
				end
			end
		end
	end)
end)

describe("ring path", function()
	it("staggers neighbouring segment tops (no coplanar overlap) on one bottom", function()
		local ring = folder("Paths", "^Ring%d+$")
		local function index(n: any): number
			return tonumber(string.match(n.name, "%d+")) or 0
		end
		table.sort(ring, function(a, b)
			return index(a) < index(b)
		end)
		expect(#ring >= 16).toBe(true)
		for k, n in ring do
			local nxt = ring[k % #ring + 1]
			local top, nextTop = n.pos[2] + n.size[2] / 2, nxt.pos[2] + nxt.size[2] / 2
			expect(math.abs(top - nextTop) >= 0.02).toBe(true)
			expect(n.pos[2] - n.size[2] / 2).toBeCloseTo(0.02)
		end
	end)
end)

describe("plot lock pieces", function()
	it("builds the LockSign, its Post and the LockButton Pedestal in wood", function()
		local function child(n: any, name: string): any
			for _, c in n.children or {} do
				if c.name == name then
					return c
				end
			end
			error(`no {name} under {n.name}`)
		end
		for _, plot in WorldLayout.build()[2].children do
			local sign = child(plot, "LockSign")
			for _, n in { sign, child(sign, "Post"), child(child(plot, "LockButton"), "Pedestal") } do
				expect(string.find(n.material, "Wood") ~= nil).toBe(true)
			end
			-- Dark enough that the FREE / LOCKED / UNLOCKED text stays readable.
			expect(math.max(sign.color[1], sign.color[2], sign.color[3]) <= 80).toBe(true)
		end
	end)
end)
