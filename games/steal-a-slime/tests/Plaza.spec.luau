--!strict
-- Fountain / plaza wiring (v30): kit mesh slots in the plaza, the Crater
-- drop origin and the run-out from the spiral mouth to a rolled landing.
local Fountain = require("../src/shared/Fountain")
local MeshAssets = require("../src/shared/MeshAssets")
local Rng = require("../src/shared/Rng")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

type Node = WorldLayout.WorldNode

local function find(nodes: { Node }?, path: { string }): Node?
	local list = nodes
	local found: Node? = nil
	for _, name in path do
		found = nil
		for _, node in list or {} do
			if node.name == name then
				found = node
				break
			end
		end
		if not found then
			return nil
		end
		list = found.children
	end
	return found
end

local function walk(nodes: { Node }?, visit: (Node) -> ())
	for _, node in nodes or {} do
		visit(node)
		walk(node.children, visit)
	end
end

local world = WorldLayout.build()
local SILO_RADIUS = 13.4 -- slime_fountain plinth / silo footprint (FOUNTAIN_SIZES)

describe("plaza mesh slots", function()
	it("a visible placeholder that never collides has an uploaded mesh (else wilds land inside it)", function()
		local bad = {}
		walk(world, function(node)
			local mesh = node.attributes and node.attributes.MeshAsset
			if
				node.class == "Part"
				and type(mesh) == "string"
				and node.canCollide == false
				and (node.transparency or 0) < 1
				and MeshAssets.meshId(mesh) == nil
			then
				table.insert(bad, node.name)
			end
		end)
		expect(table.concat(bad, ", ")).toBe("")
	end)
	it("plaza props keep their mesh proportions (MeshSwap fits the mesh to the slot box)", function()
		for _, def in WorldLayout.PLAZA_PROPS do
			local node = find(world, { "Map", "Plaza", def.name })
			assert(node and node.size, def.name)
			local native = (MeshAssets.get(def.mesh) :: any).size
			local sx, sy, sz = node.size[1] / native[1], node.size[2] / native[2], node.size[3] / native[3]
			expect(math.abs(sx - sy) < 1e-3 and math.abs(sx - sz) < 1e-3).toBe(true)
		end
	end)
	it("neighbouring podiums don't overlap", function()
		local boxes = {}
		for _, name in { "Podium_1", "Podium_2", "Podium_3" } do
			local node = find(world, { "Map", "Plaza", name })
			assert(node and node.pos and node.size, name)
			table.insert(boxes, { pos = node.pos, r = math.max(node.size[1], node.size[3]) / 2 })
		end
		for i = 1, #boxes do
			for j = i + 1, #boxes do
				local a, b = boxes[i], boxes[j]
				local d = math.sqrt((a.pos[1] - b.pos[1]) ^ 2 + (a.pos[3] - b.pos[3]) ^ 2)
				-- footprint circles: conservative for the rotated boxes
				expect(d >= (a.r + b.r) * 0.75).toBe(true)
			end
		end
	end)
	it("plaza props stay outside the wild landing band", function()
		for _, def in WorldLayout.PLAZA_PROPS do
			local node = find(world, { "Map", "Plaza", def.name })
			assert(node and node.pos and node.size, def.name)
			local r = math.sqrt(node.pos[1] ^ 2 + node.pos[3] ^ 2)
			local half = math.max(node.size[1], node.size[3]) / 2
			expect(r - half > Fountain.MAX_RADIUS).toBe(true)
		end
	end)
end)

describe("fountain centre", function()
	it("Crater (drop origin, emitter host) sits on the fountain axis and hides with the stand-ins", function()
		local crater = find(world, { "Map", "Volcano", "Crater" })
		assert(crater and crater.pos, "Map.Volcano.Crater")
		expect(crater.pos[1]).toBe(0)
		expect(crater.pos[3]).toBe(0)
		expect(crater.canCollide).toBe(false)
		-- a neon plate wider than the mesh's centre bubble poked out of the crown
		expect((crater.attributes :: any).MeshStandIn).toBe("slime_fountain")
	end)
end)

describe("Fountain.runOut (spiral mouth -> rolled landing)", function()
	local mouth = WorldLayout.slidePosition(1)
	local path = WorldLayout.SLIDE_PATH
	local a, b = path[#path - 1], path[#path]
	local exit = { b[1] - a[1], b[3] - a[3] }

	local function landing(rng: Rng.Rng): { number }
		local drop = Fountain.roll(rng, "x", false)
		return { math.cos(drop.angle) * drop.radius, 0.15, math.sin(drop.angle) * drop.radius }
	end

	it("starts at the mouth and ends at the landing", function()
		local rng = Rng.new(7)
		for _ = 1, 50 do
			local to = landing(rng)
			local x0, y0, z0 = Fountain.runOut(mouth, to, 0)
			local x1, y1, z1 = Fountain.runOut(mouth, to, 1)
			expect(math.abs(x0 - mouth[1]) + math.abs(y0 - mouth[2]) + math.abs(z0 - mouth[3]) < 1e-6).toBe(true)
			expect(math.abs(x1 - to[1]) + math.abs(y1 - to[2]) + math.abs(z1 - to[3]) < 1e-6).toBe(true)
		end
	end)
	it("never cuts through the fountain silo", function()
		local rng = Rng.new(11)
		for _ = 1, 400 do
			local to = landing(rng)
			for k = 0, 40 do
				local x, _, z = Fountain.runOut(mouth, to, k / 40)
				expect(math.sqrt(x * x + z * z) > SILO_RADIUS).toBe(true)
			end
		end
	end)
	it("leaves the mouth the way the slide was going when the landing is ahead", function()
		local rng = Rng.new(3)
		local checked = 0
		for _ = 1, 200 do
			local to = landing(rng)
			local x0, _, z0 = Fountain.runOut(mouth, to, 0)
			local x1, _, z1 = Fountain.runOut(mouth, to, 0.02)
			local dx, dz = x1 - x0, z1 - z0
			local ahead = (dx * exit[1] + dz * exit[2]) > 0
			local len = math.sqrt(dx * dx + dz * dz)
			if len > 1e-3 and Fountain.runOutAhead(mouth, to) then
				checked += 1
				expect(ahead).toBe(true)
			end
		end
		expect(checked > 50).toBe(true)
	end)
end)
