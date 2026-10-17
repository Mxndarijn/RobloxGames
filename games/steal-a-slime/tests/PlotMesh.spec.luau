--!strict
-- Plot kit meshes (v31): MeshSwap fits a mesh to its slot box, so every slot
-- must be the mesh's native size times one scale. Pad stands, gates and the
-- ranch hay bale were squashed (stand 1.03/0.23/1.03, gate 0.99/0.67/0.38,
-- hay bale 1.25/1.53/1.95), and the stand and gate slots ignored the plot yaw.
local Config = require("../src/shared/Config")
local LayoutMath = require("../src/visuals/shared/LayoutMath")
local MeshAssets = require("../src/shared/MeshAssets")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

type Node = WorldLayout.WorldNode
type Vec = LayoutMath.Vec

local function walk(nodes: { Node }?, visit: (Node) -> ())
	for _, node in nodes or {} do
		visit(node)
		walk(node.children, visit)
	end
end

local function child(node: Node, name: string): Node
	for _, c in node.children or {} do
		if c.name == name then
			return c
		end
	end
	error(`{node.name} has no {name}`)
end

local function native(mesh: string): Vec
	return (MeshAssets.get(mesh) :: any).size :: Vec
end

-- Per-axis slot / native ratios.
local function ratios(node: Node, mesh: string): Vec
	local size, n = node.size :: Vec, native(mesh)
	return { size[1] / n[1], size[2] / n[2], size[3] / n[3] }
end

local function uniform(r: Vec): boolean
	local lo, hi = math.min(r[1], r[2], r[3]), math.max(r[1], r[2], r[3])
	return hi / lo < 1.01
end

local function meshOf(node: Node): string?
	local attributes = node.attributes
	return attributes and attributes.MeshAsset
end

-- `pos` in the plot's own frame (entrance at local -Z).
local function toPlot(i: number, pos: Vec): Vec
	local centre, yaw = WorldLayout.plotCentre(i)
	local d = { pos[1] - centre[1], pos[2] - centre[2], pos[3] - centre[3] }
	return LayoutMath.apply(LayoutMath.orientation({ 0, -yaw, 0 }), d)
end

local function sameAngle(a: number, b: number): boolean
	return math.abs((a - b + 180) % 360 - 180) < 1e-6
end

local world = WorldLayout.build()
local plots = world[2].children :: { Node }
local BASE_TOP = 1

describe("kit mesh slots keep the mesh's proportions", function()
	it("sizes every block slot as the native mesh times one scale", function()
		local bad, checked = {}, 0
		walk(world, function(node)
			local mesh = meshOf(node)
			if node.class == "Part" and node.shape == "Block" and mesh and (MeshAssets.get(mesh) :: any).size then
				checked += 1
				local r = ratios(node, mesh)
				if not uniform(r) then
					table.insert(bad, `{node.name} ({mesh}) {r[1]}/{r[2]}/{r[3]}`)
				end
			end
		end)
		expect(table.concat(bad, "; ")).toBe("")
		-- 8 plots x (PADS_MAX stands + gate + 4 corner posts) + plaza + decor
		expect(checked >= Config.PLOT_COUNT * (Config.PADS_MAX + 5)).toBe(true)
	end)
	it("gives the ranch hay bale behind the plots its native proportions", function()
		local found = 0
		walk(world, function(node)
			if meshOf(node) == "ranch_hay_bale" then
				found += 1
				local r = ratios(node, "ranch_hay_bale")
				expect(uniform(r)).toBe(true)
				-- stands on the ground
				expect((node.pos :: Vec)[2] - (node.size :: Vec)[2] / 2).toBeCloseTo(0)
			end
		end)
		expect(found > 0).toBe(true)
	end)
end)

describe("pad stands", function()
	it("puts each stand on the Base at native size, turned with the plot", function()
		for i, plot in plots do
			local _, yaw = WorldLayout.plotCentre(i)
			for j = 1, Config.PADS_MAX do
				local pad = child(plot, `Pad_{j}`)
				local stand = child(pad, "Stand")
				local look = meshOf(stand) :: string
				local r = ratios(stand, look)
				expect(r[1]).toBeCloseTo(1)
				expect(r[2]).toBeCloseTo(1)
				expect(r[3]).toBeCloseTo(1)
				local p = toPlot(i, stand.pos :: Vec)
				expect(p[2] - (stand.size :: Vec)[2] / 2).toBeCloseTo(BASE_TOP)
				expect(sameAngle((stand.rot :: Vec)[2], yaw)).toBe(true)
				expect(sameAngle((pad.rot :: Vec)[2], yaw)).toBe(true)
				-- same spot as the Pad
				local q = toPlot(i, pad.pos :: Vec)
				expect(p[1]).toBeCloseTo(q[1])
				expect(p[3]).toBeCloseTo(q[3])
			end
		end
	end)
	it("tops the Pad at the stand's seat, so slimes rest on the mesh", function()
		for i, plot in plots do
			for j = 1, Config.PADS_MAX do
				local pad = child(plot, `Pad_{j}`)
				local look = meshOf(child(pad, "Stand")) :: string
				local seat = WorldLayout.PAD_SEAT_Y
				expect(seat > 0 and seat <= native(look)[2]).toBe(true)
				local p = toPlot(i, pad.pos :: Vec)
				local h = (pad.size :: Vec)[2]
				expect(p[2] - h / 2).toBeCloseTo(BASE_TOP)
				expect(p[2] + h / 2).toBeCloseTo(BASE_TOP + seat)
				-- the primitive Pad hides once its stand mesh lands (it keeps collision and the prompt)
				expect((pad.attributes :: any).MeshStandIn).toBe(look)
				expect((pad.attributes :: any).PadIndex).toBe(j)
				expect(pad.canCollide ~= false).toBe(true)
			end
		end
	end)
	it("uses the one crate pad on every spot, with a constant seat", function()
		expect(WorldLayout.PAD_MESH).toBe("phoenix_pad_crate")
		expect(WorldLayout.PAD_SEAT_Y).toBe(2.4)
		for _, plot in plots do
			for j = 1, Config.PADS_MAX do
				local pad = child(plot, `Pad_{j}`)
				expect(meshOf(child(pad, "Stand"))).toBe(WorldLayout.PAD_MESH)
				expect((pad.size :: Vec)[2]).toBeCloseTo(WorldLayout.PAD_SEAT_Y)
			end
		end
	end)
end)

describe("plot gate", function()
	local board = WorldLayout.GATE_BOARD
	it("fills the gate slot at native size, board facing out of the entrance", function()
		for i, plot in plots do
			local _, yaw = WorldLayout.plotCentre(i)
			local mesh = child(child(plot, "Gate"), "GateMesh")
			local r = ratios(mesh, "phoenix_gate")
			expect(r[1]).toBeCloseTo(1)
			expect(r[2]).toBeCloseTo(1)
			expect(r[3]).toBeCloseTo(1)
			expect(math.abs((mesh.size :: Vec)[1] - WorldLayout.GATE_SLOT) < 0.5).toBe(true)
			local p = toPlot(i, mesh.pos :: Vec)
			expect(p[1]).toBeCloseTo(0)
			expect(p[2] - (mesh.size :: Vec)[2] / 2).toBeCloseTo(BASE_TOP)
			expect(p[3]).toBeCloseTo(-WorldLayout.PLOT_SIZE / 2 + 0.5)
			-- kit fronts face Roblox +Z, the entrance is local -Z
			expect(sameAngle((mesh.rot :: Vec)[2], yaw + 180)).toBe(true)
		end
	end)
	it("puts the plot Sign on the mesh's name board, text on its front face only", function()
		local wallZ = -WorldLayout.PLOT_SIZE / 2 + 0.5
		for i, plot in plots do
			local sign = child(plot, "Sign")
			local size = sign.size :: Vec
			local p = toPlot(i, sign.pos :: Vec)
			expect(size[1]).toBeCloseTo(board.width)
			expect(size[2]).toBeCloseTo(board.height)
			expect(p[1]).toBeCloseTo(0)
			expect(p[2]).toBeCloseTo(BASE_TOP + board.centreY)
			-- bottom edge stays >= 9 above the walkway
			expect(p[2] - size[2] / 2 >= BASE_TOP + 9).toBe(true)
			-- front face just proud of the board, back face on the board's rim
			-- (in front of the beam, which spans the wall line +-0.5)
			local front, back = p[3] - size[3] / 2, p[3] + size[3] / 2
			expect(front < wallZ - board.front and front > wallZ - board.front - 0.2).toBe(true)
			expect(back).toBeCloseTo(wallZ - board.back)
			expect(back < wallZ - 0.3).toBe(true)
			-- inside the gate mesh's top, which ends 13.4 up
			expect(p[2] + size[2] / 2 < BASE_TOP + native("phoenix_gate")[2]).toBe(true)
		end
	end)
	it("hides the primitive sign board, posts and beam once the gate mesh lands", function()
		for _, plot in plots do
			local sign = child(plot, "Sign")
			expect((sign.attributes :: any).MeshStandIn).toBe("phoenix_gate")
			for _, c in sign.children or {} do
				expect((c.attributes :: any).MeshStandIn).toBe("phoenix_gate")
			end
			expect(#(sign.children or {})).toBe(3)
		end
	end)
end)

-- max / min of the per-axis slot / native ratios: 1 = the mesh's own proportions.
local function anisotropy(node: Node, mesh: string): number
	local r = ratios(node, mesh)
	return math.max(r[1], r[2], r[3]) / math.min(r[1], r[2], r[3])
end

describe("plot walls and DexBoard (C6)", function()
	local h = WorldLayout.PLOT_SIZE / 2
	it("skins every fence piece with a kit fence mesh at FENCE_SCALE, the Box meshes are the colliders", function()
		local fenceMeshes = {
			[WorldLayout.FENCE_SEGMENT] = true,
			[WorldLayout.FENCE_MESH] = true,
			[WorldLayout.GATE_POST_MESH] = true,
		}
		for _, plot in plots do
			local slots = 0
			walk(child(plot, "Fence").children, function(node)
				local mesh = meshOf(node)
				if node.class == "Part" then
					expect(mesh ~= nil and fenceMeshes[mesh] == true).toBe(true)
					slots += 1
					expect(anisotropy(node, mesh :: string)).toBeCloseTo(1)
					expect(ratios(node, mesh :: string)[1]).toBeCloseTo(WorldLayout.FENCE_SCALE)
					-- the slot box collides until MeshSwap lands the mesh (which has a Box fidelity and takes over)
					expect(node.canCollide ~= false).toBe(true)
					expect(MeshAssets.collision(mesh :: string)).toBe("Box")
				end
			end)
			-- + the GatePost closing the fence run at the gate's right stub
			expect(slots).toBe(if WorldLayout.fenceUploaded() then 17 else 31)
			for _, name in { "WallBack", "WallLeft", "WallRight", "WallFrontL", "WallFrontR" } do
				expect(pcall(child, plot, name)).toBe(false) -- the invisible walls were removed: the meshes collide
			end
		end
	end)
	it("skins the DexBoard with DEX_MESH at DEX_SCALE, on the Base, facing the entrance, clear of the fence", function()
		for i, plot in plots do
			local _, yaw = WorldLayout.plotCentre(i)
			local dex = child(plot, "DexBoard")
			local slot = child(dex, "DexMesh")
			expect(meshOf(slot)).toBe(WorldLayout.DEX_MESH)
			expect(anisotropy(slot, WorldLayout.DEX_MESH)).toBeCloseTo(1)
			expect(ratios(slot, WorldLayout.DEX_MESH)[2]).toBeCloseTo(WorldLayout.DEX_SCALE)
			-- invisible slot the mesh lands in; B9: its box is the (decor-mesh) board's collider, never queried or touched
			expect(slot.transparency).toBe(1)
			expect(slot.canCollide).toBe(true)
			expect(slot.canQuery).toBe(false)
			expect(slot.canTouch).toBe(false)
			expect(sameAngle((slot.rot :: Vec)[2], yaw + 180)).toBe(true)
			local p, size = toPlot(i, slot.pos :: Vec), slot.size :: Vec
			expect(p[1]).toBeCloseTo(0)
			expect(p[2] - size[2] / 2).toBeCloseTo(BASE_TOP)
			-- back face in front of the fence pieces (1.64 deep on the line h - 0.5)
			expect(p[3] + size[3] / 2 < h - 0.5 - 0.82).toBe(true)
		end
	end)
	it("keeps the dex text, bar and gems on the mesh's front panel and hides only the primitive frame", function()
		local k, face = WorldLayout.DEX_SCALE, WorldLayout.DEX_FACE
		for i, plot in plots do
			local dex = child(plot, "DexBoard")
			local slot = toPlot(i, child(dex, "DexMesh").pos :: Vec)
			local panelZ = slot[3] - face.front * k
			local fx, fy = -face.x * k, BASE_TOP + face.y * k
			local w, hh = face.width * k / 2, face.height * k / 2
			for _, c in dex.children or {} do
				if c.name == "DexMesh" then
					continue
				end
				local stand = (c.attributes or {} :: any).MeshStandIn
				local p, size = toPlot(i, c.pos :: Vec), c.size :: Vec
				if c.name == "Frame" or c.name == "LegL" or c.name == "LegR" or c.name == "Shelf" then
					expect(stand).toBe(WorldLayout.DEX_MESH)
				else
					-- PlotDecor draws on these: they stay, in front of the panel, inside it
					expect(stand).toBe(nil)
					expect(p[3] + size[3] / 2 <= panelZ + 1e-6).toBe(true)
					expect(math.abs(p[1] - fx) + size[1] / 2 <= w).toBe(true)
					expect(math.abs(p[2] - fy) + size[2] / 2 <= hh).toBe(true)
				end
				expect(c.canCollide).toBe(false)
			end
		end
	end)
	it("has no BuyStand / claim model on any plot (plots auto-assign; the stand is the plaza shop only)", function()
		for _, plot in plots do
			local found = 0
			walk({ plot }, function(node)
				if node.name == "BuyStand" or node.name == "StandMesh" or meshOf(node) == "ranch_shop_stand" then
					found += 1
				end
			end)
			expect(found).toBe(0)
		end
	end)
end)
