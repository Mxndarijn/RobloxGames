--!strict
-- Plot kit meshes: MeshSwap fits a mesh to its slot box, so every slot must be
-- the mesh's native size times one scale, turned with the plot. Also the plot
-- Sign (the jar's name label) and the DexBoard placement.
local Config = require("../src/shared/Config")
local LayoutMath = require("../src/visuals/shared/LayoutMath")
local MeshAssets = require("../src/shared/MeshAssets")
local PlotSigns = require("../src/server/PlotSigns")
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
		-- every plot's PADS_PER_FLOOR stands and DexBoard, + plaza + decor
		expect(checked >= Config.PLOT_COUNT * (Config.PADS_PER_FLOOR + 1)).toBe(true)
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
	it("puts each stand on the Base at native size, turned square to the jar's centre", function()
		for i, plot in plots do
			local _, yaw = WorldLayout.plotCentre(i)
			for j = 1, Config.PADS_PER_FLOOR do
				local pad = child(plot, `Pad_{j}`)
				local stand = child(pad, "Stand")
				local look = meshOf(stand) :: string
				local r = ratios(stand, look)
				expect(r[1]).toBeCloseTo(1)
				expect(r[2]).toBeCloseTo(1)
				expect(r[3]).toBeCloseTo(1)
				local p = toPlot(i, stand.pos :: Vec)
				expect(p[2] - (stand.size :: Vec)[2] / 2).toBeCloseTo(BASE_TOP)
				local turn = yaw + WorldLayout.padYaw(j)
				expect(sameAngle((stand.rot :: Vec)[2], turn)).toBe(true)
				expect(sameAngle((pad.rot :: Vec)[2], turn)).toBe(true)
				-- same spot as the Pad
				local q = toPlot(i, pad.pos :: Vec)
				expect(p[1]).toBeCloseTo(q[1])
				expect(p[3]).toBeCloseTo(q[3])
				-- its local Z axis runs along the line to the jar's centre
				local rel = math.rad((stand.rot :: Vec)[2] - yaw)
				local d = math.sqrt(p[1] ^ 2 + p[3] ^ 2)
				expect(math.abs(math.sin(rel) * p[1] + math.cos(rel) * p[3]) / d).toBeCloseTo(1)
			end
		end
	end)
	it("tops the Pad at the stand's seat, so slimes rest on the mesh", function()
		for i, plot in plots do
			for j = 1, Config.PADS_PER_FLOOR do
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
	it("uses the one cork stand on every spot, with a constant seat", function()
		expect(WorldLayout.PAD_MESH).toBe("goo_cork_stand")
		expect(WorldLayout.PAD_SEAT_Y).toBe(2.4)
		for _, plot in plots do
			for j = 1, Config.PADS_PER_FLOOR do
				local pad = child(plot, `Pad_{j}`)
				expect(meshOf(child(pad, "Stand"))).toBe(WorldLayout.PAD_MESH)
				expect((pad.size :: Vec)[2]).toBeCloseTo(WorldLayout.PAD_SEAT_Y)
			end
		end
	end)
end)

describe("plot sign", function()
	it(
		"hangs the name label just outside jar 1's glass, its Front face (the text face) pointing out of the jar",
		function()
			expect(PlotSigns.FACES).toEqual({ "Front" })
			local label = WorldLayout.LABEL
			local glass = WorldLayout.jarRadius(1) + WorldLayout.JAR_WALL
			for i, plot in plots do
				local _, yaw = WorldLayout.plotCentre(i)
				local sign = child(plot, "Sign")
				local size = sign.size :: Vec
				local p = toPlot(i, sign.pos :: Vec)
				expect(size[1]).toBeCloseTo(label.width)
				expect(size[2]).toBeCloseTo(label.height)
				expect(p[2]).toBeCloseTo(label.y)
				-- above a character's head, within jar 1's storey
				expect(p[2] - size[2] / 2 >= BASE_TOP + 5).toBe(true)
				expect(p[2] + size[2] / 2 <= WorldLayout.floorTop(2)).toBe(true)
				-- on the label's angle, its back face clear of the glass
				local d = math.sqrt(p[1] ^ 2 + p[3] ^ 2)
				local a = math.deg(math.atan2(p[3], p[1]))
				expect(math.abs((a - label.angle + 180) % 360 - 180) < 1e-4).toBe(true)
				expect(d - size[3] / 2 >= glass - 1e-6).toBe(true)
				expect(d - size[3] / 2 <= glass + 0.5).toBe(true)
				-- Roblox's Front face is local -Z: it points along the outward radial
				local rel = math.rad((sign.rot :: Vec)[2] - yaw)
				local fx, fz = -math.sin(rel), -math.cos(rel)
				expect((fx * p[1] + fz * p[3]) / d).toBeCloseTo(1)
				-- a plain board: no mesh, no stand-ins
				expect(meshOf(sign)).toBe(nil)
				expect((sign.attributes or {} :: any).MeshStandIn).toBe(nil)
				expect(#(sign.children or {})).toBe(0)
			end
		end
	)
end)

-- max / min of the per-axis slot / native ratios: 1 = the mesh's own proportions.
local function anisotropy(node: Node, mesh: string): number
	local r = ratios(node, mesh)
	return math.max(r[1], r[2], r[3]) / math.min(r[1], r[2], r[3])
end

describe("plot DexBoard", function()
	local h = WorldLayout.PLOT_SIZE / 2
	it("skins the DexBoard with DEX_MESH at DEX_SCALE, on the Base behind the jar, facing the entrance", function()
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
			-- on the Base, behind jar 1's glass
			expect(p[3] + size[3] / 2 <= h).toBe(true)
			expect(p[3] - size[3] / 2 >= WorldLayout.jarRadius(1) + WorldLayout.JAR_WALL).toBe(true)
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
