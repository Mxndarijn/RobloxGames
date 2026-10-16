--!strict
-- Fountain / plaza wiring (v30): kit mesh slots in the plaza, the Crater
-- drop origin (the slide ride itself: FountainRide.spec).
local fs = require("@lune/fs")

local Effects = require("../src/visuals/shared/Effects")
local Fountain = require("../src/shared/Fountain")
local MeshAssets = require("../src/shared/MeshAssets")
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

describe("VisualsClient fountain wiring", function()
	local src = fs.readFile("src/visuals/client/init.client.luau")
	it("only attaches emitter presets Effects defines", function()
		local n = 0
		for preset in string.gmatch(src, 'addEmitter%(%w+, "(%w+)"') do
			n += 1
			expect(Effects.EMITTERS[preset] ~= nil).toBe(true)
		end
		expect(n >= 3).toBe(true)
	end)
	it("never looks up map parts the generated world doesn't have (old volcano decor)", function()
		local names: { [string]: boolean } = {}
		walk(world, function(node)
			names[node.name] = true
		end)
		for pattern in string.gmatch(src, 'string%.find%(child%.Name, "%^(%w+)"%)') do
			local hit = false
			for name in names do
				hit = hit or string.find(name, "^" .. pattern) ~= nil
			end
			expect(hit).toBe(true)
		end
		for name in string.gmatch(src, ':WaitForChild%("(%w+)"') do
			if name == "Volcano" or name == "Crater" then
				expect(names[name]).toBe(true)
			end
		end
		expect(string.find(src, "LavaCrack", 1, true)).toBeNil()
	end)
end)
