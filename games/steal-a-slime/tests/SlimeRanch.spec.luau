--!strict
-- Slime Ranch place wiring: kit mesh slots name real MeshAssets entries, the
-- 80-stud plots don't overlap, one gated entrance with a 14-stud opening,
-- and the map stays inside the MeshPart budget (THEME.md: <= 150).
local Config = require("../src/shared/Config")
local MeshAssets = require("../src/shared/MeshAssets")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function walk(node: any, visit: (any) -> ())
	visit(node)
	for _, c in node.children or {} do
		walk(c, visit)
	end
end

describe("Slime Ranch layout", function()
	local nodes = WorldLayout.build()
	it("tags only known kit meshes and stays under 150 mesh slots", function()
		local slots = 0
		for _, root in nodes do
			walk(root, function(n)
				local mesh = n.attributes and n.attributes.MeshAsset
				if mesh then
					slots += 1
					expect(MeshAssets.get(mesh) ~= nil).toBe(true)
				end
			end)
		end
		for _, mesh in WorldLayout.PROP_MESHES do
			slots += 1
			expect(MeshAssets.get(mesh) ~= nil).toBe(true)
		end
		expect(slots <= 150).toBe(true)
	end)
	it("has no volcano decor (lava, basalt, torches, crystals)", function()
		for _, root in nodes do
			walk(root, function(n)
				expect(n.material ~= "CrackedLava" and n.material ~= "Basalt").toBe(true)
				expect(string.find(n.name, "Torch") == nil and string.find(n.name, "Crystal") == nil).toBe(true)
			end)
		end
	end)
	it("keeps 80-stud plots apart (inner corners clear the bisector)", function()
		local half = WorldLayout.PLOT_SIZE / 2
		local bisector = math.rad(180 / Config.PLOT_COUNT)
		expect(math.atan(half / (WorldLayout.PLOT_RING_RADIUS - half)) <= bisector).toBe(true)
		expect(WorldLayout.PLOT_RING_RADIUS - half > WorldLayout.RING_PATH_RADIUS + WorldLayout.RING_PATH_WIDTH / 2).toBe(
			true
		)
	end)
	it("gives every plot one gate with a 14-stud opening", function()
		local plots = nodes[2].children
		expect(#plots).toBe(Config.PLOT_COUNT)
		local slot, clear = WorldLayout.GATE_SLOT, WorldLayout.GATE_CLEAR
		expect(clear).toBe(14)
		for _, plot in plots do
			local names = {}
			for _, c in plot.children do
				names[c.name] = c
			end
			expect(names.Gate ~= nil and names.WallFrontL ~= nil and names.WallFrontR ~= nil).toBe(true)
			expect(names.WallFrontL.size[1] + names.WallFrontR.size[1] + slot).toBe(WorldLayout.PLOT_SIZE)
			expect(names.WallBack.size[2]).toBe(WorldLayout.WALL_HEIGHT)
		end
	end)
end)
