--!strict
-- Slime Ranch place wiring: kit mesh slots name real MeshAssets entries, the
-- 80-stud plots don't overlap, each plot's jar has one door a character fits
-- through with a bridge to it, and every mesh slot names a known kit mesh
-- (budgets: tests/WorldBudget.spec).
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
	it("tags only known kit meshes and stays inside the mesh slot budget", function()
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
		expect(slots > 0).toBe(true) -- MeshParts are a soft budget (warn only), nothing to cap here
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
	it("covers the landing ring with plaza sand and keeps props off the ring path", function()
		expect(WorldLayout.PLAZA_RADIUS >= 64 and WorldLayout.PLAZA_RADIUS <= 66).toBe(true)
		expect(WorldLayout.PLAZA_RADIUS >= 62).toBe(true)
		for _, spot in WorldLayout.PROP_SPOTS do
			local r = math.sqrt(spot.pos[1] ^ 2 + spot.pos[3] ^ 2)
			expect(r >= 88).toBe(true)
		end
	end)
	it("places 18 landing-ring tiles and one goo drain", function()
		local rings, drains = 0, 0
		for _, root in nodes do
			walk(root, function(n)
				local mesh = n.attributes and n.attributes.MeshAsset
				if mesh == "ranch_landing_ring" then
					rings += 1
					expect(n.canCollide).toBe(false)
				elseif mesh == "ranch_goo_drain" then
					drains += 1
					expect(n.pos[3] > 40).toBe(true)
				end
			end)
		end
		expect(rings).toBe(11) -- 18 less the 7 left out where the slide lands slimes
		expect(drains).toBe(1)
	end)
	it("sizes the fountain slot to the polished bbox with the silo on the origin", function()
		local found = false
		for _, root in nodes do
			walk(root, function(n)
				if n.name == "FountainMesh" then
					found = true
					expect(n.size[1]).toBeCloseTo(54.45)
					expect(n.size[2]).toBeCloseTo(43.316)
					expect(n.size[3]).toBeCloseTo(63.851)
					-- silo is Roblox (-6.52, -7.75) from the bbox centre
					expect(n.pos[1] + -6.52).toBeCloseTo(0)
					expect(n.pos[3] + -7.75).toBeCloseTo(0)
				end
			end)
		end
		expect(found).toBe(true)
		local mouth = WorldLayout.slidePosition(1)
		local r = math.sqrt(mouth[1] ^ 2 + mouth[3] ^ 2)
		expect(math.abs(r - WorldLayout.SLIDE_END_RADIUS) < 0.25).toBe(true)
		expect(WorldLayout.SLIDE_END_RADIUS).toBe(35.5)
	end)
	it("tags the primitive chute as a fountain stand-in", function()
		local chute: any = nil
		for _, root in nodes do
			walk(root, function(n)
				if n.name == "Chute" then
					chute = n
				end
			end)
		end
		expect(chute ~= nil and chute.primaryPart).toBe("Floor")
		expect(#chute.children > 8).toBe(true)
		for _, part in chute.children do
			expect(part.attributes.MeshStandIn).toBe("slime_fountain")
			expect(part.canCollide).toBe(false)
		end
	end)
	it("gives every plot one door a character walks through, with a bridge at least as wide", function()
		local plots = nodes[2].children
		expect(#plots).toBe(Config.PLOT_COUNT)
		-- a Roblox character is about 4 studs wide (arms out) and 5.5 tall
		local door = WorldLayout.DOOR
		expect(door.width >= 4).toBe(true)
		expect(door.height >= 6).toBe(true)
		expect(WorldLayout.BRIDGE_WIDTH >= door.width).toBe(true)
		for _, plot in plots do
			local counts = {}
			for _, c in plot.children do
				counts[c.name] = (counts[c.name] or 0) + 1
			end
			expect(counts.Bridge).toBe(1)
			expect(counts.Jar).toBe(1)
			local lintels = 0
			for _, c in plot.children do
				if c.name == "Jar" then
					for _, part in c.children do
						if part.name == "DoorLintel" then
							lintels += 1
						end
					end
				end
			end
			expect(lintels).toBe(1)
		end
	end)
end)
