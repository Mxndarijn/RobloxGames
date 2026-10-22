--!strict
-- PlotLookup.allByIndex resolves every pad like PlotLookup.byIndex does, with one scan of the children
-- instead of one scan per index.
local PlotLookup = require("../src/server/PlotLookup")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

type Node = { name: string, attrs: { [string]: any }, kids: { Node } }

local calls = { children = 0, attributes = 0, finds = 0 }

local function wrap(node: Node): any
	return {
		Name = node.name,
		GetAttribute = function(_, attribute: string)
			calls.attributes += 1
			return node.attrs[attribute]
		end,
	}
end

local function parentOf(kids: { Node }): any
	local wrapped = {}
	local byName = {}
	for _, kid in kids do
		local w = wrap(kid)
		table.insert(wrapped, w)
		byName[kid.name] = byName[kid.name] or w
	end
	return {
		GetChildren = function()
			calls.children += 1
			return wrapped
		end,
		FindFirstChild = function(_, name: string)
			calls.finds += 1
			return byName[name]
		end,
	}
end

local function reset()
	calls.children, calls.attributes, calls.finds = 0, 0, 0
end

-- A plot with `pads` pads (attribute-indexed, in reverse order) plus filler children.
local function plotWith(pads: number, filler: number): any
	local kids: { Node } = {}
	for i = 1, filler do
		table.insert(kids, { name = `Part_{i}`, attrs = {}, kids = {} })
	end
	for j = pads, 1, -1 do
		table.insert(kids, { name = `Renamed_{j}`, attrs = { PadIndex = j }, kids = {} })
	end
	return parentOf(kids)
end

describe("PlotLookup.allByIndex", function()
	it("matches byIndex for every index", function()
		local plot = plotWith(12, 60)
		local all = PlotLookup.allByIndex(plot, "PadIndex", 32, "Pad_")
		for j = 1, 32 do
			expect(all[j]).toBe(PlotLookup.byIndex(plot, "PadIndex", j, `Pad_{j}`))
		end
	end)
	it("falls back to the child name for an index without attribute, first attribute match wins", function()
		local plot = parentOf({
			{ name = "Pad_2", attrs = {}, kids = {} },
			{ name = "A", attrs = { PadIndex = 1 }, kids = {} },
			{ name = "B", attrs = { PadIndex = 1 }, kids = {} },
		})
		local all = PlotLookup.allByIndex(plot, "PadIndex", 3, "Pad_")
		expect(all[1].Name).toBe("A")
		expect(all[2].Name).toBe("Pad_2")
		expect(all[3]).toBeNil()
	end)
	it("returns an empty table for a missing parent", function()
		expect(next(PlotLookup.allByIndex(nil, "PadIndex", 4, "Pad_"))).toBeNil()
	end)
	it("scans the children once instead of once per index", function()
		local plot = plotWith(12, 60)
		reset()
		for j = 1, 32 do
			PlotLookup.byIndex(plot, "PadIndex", j, `Pad_{j}`)
		end
		local before = calls.children + calls.attributes
		reset()
		PlotLookup.allByIndex(plot, "PadIndex", 32, "Pad_")
		local after = calls.children + calls.attributes
		print(`  PlotLookup calls per plot refresh: {before} -> {after}`)
		expect(calls.children).toBe(1)
		expect(after < before / 10).toBe(true)
	end)
end)
