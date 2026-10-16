--!strict
-- Look fixes from the whole-world render review (tools/render):
-- Map.Decor scattered rocks (WorldLayout rock()) are low boulders and flat
-- stones (Balls) sunk into the Ground, never an upright grey box or a slab
-- that reads as a paving tile; the plot lock sign and button pedestal are ranch wood, not gunmetal.
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
	it("keeps the scatter (boulders and flat stones, same count, no slabs)", function()
		local boulders, flats = 0, 0
		for _, n in all do
			-- Blocks read as paving tiles in the renders: Balls only
			expect(n.shape).toBe("Ball")
			local show = (n.pos[2] + n.size[2] / 2) / n.size[2]
			if show > 0.25 then
				boulders += 1
			elseif show <= 0.21 then
				flats += 1
			end
		end
		expect(#all >= 30).toBe(true)
		expect(boulders >= 10).toBe(true)
		expect(flats >= 10).toBe(true)
		expect(boulders + flats).toBe(#all)
	end)
	it("stands low: never taller above the Ground than half its width", function()
		for _, n in all do
			local top = n.pos[2] + n.size[2] / 2
			expect(top <= 0.5 * math.max(n.size[1], n.size[3])).toBe(true)
		end
	end)
	it("is sunk: every rock's centre is under the Ground top", function()
		for _, n in all do
			expect(n.pos[2] < 0).toBe(true)
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
