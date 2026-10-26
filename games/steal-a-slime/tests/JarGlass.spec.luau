--!strict
-- The jar tower's glass (WorldLayout glass slots, read by server/MeshSwap): see-through, never the Glass material.
-- Roblox draws nothing partly see-through behind a Glass part, so with Glass a faded "In vat" pad slime, a steal
-- ghost or a sign inside the jar vanished for a camera outside it.
local Config = require("../src/shared/Config")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function walk(node: any, fn: (any) -> ())
	fn(node)
	for _, c in node.children or {} do
		walk(c, fn)
	end
end

-- Every glass slot in the map and in each jar floor of plot 1.
local function glassSlots(): { any }
	local out = {}
	local function visit(n: any)
		local a = n.attributes
		if a and a.MeshMaterial ~= nil then
			table.insert(out, n)
		end
	end
	for _, root in WorldLayout.build() do
		walk(root, visit)
	end
	for f = 2, Config.PADS_MAX // Config.PADS_PER_FLOOR do
		for _, node in WorldLayout.floor(1, f) do
			walk(node, visit)
		end
	end
	return out
end

describe("jar glass", function()
	local slots = glassSlots()

	it("has glass slots on every jar floor and the drop tube", function()
		local names: { [string]: boolean } = {}
		for _, n in slots do
			names[n.name] = true
		end
		expect(names.GlassTop).toBe(true)
		expect(names.GlassBelow).toBe(true)
		expect(#slots > Config.PADS_MAX // Config.PADS_PER_FLOOR).toBe(true)
	end)

	it("never wears Glass, which hides see-through slimes and signs behind it", function()
		for _, n in slots do
			expect(n.attributes.MeshMaterial).toBe(WorldLayout.JAR_GLASS_MATERIAL)
		end
		expect(WorldLayout.JAR_GLASS_MATERIAL ~= "Glass").toBe(true)
	end)

	it("stays see-through", function()
		for _, n in slots do
			local clear = n.attributes.MeshTransparency
			expect(type(clear) == "number" and clear > 0 and clear < 1).toBe(true)
		end
	end)
end)
