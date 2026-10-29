--!strict
-- Plot kit meshes: MeshSwap fits a mesh to its slot box, so every slot must be
-- the mesh's native size times one scale, turned with the plot. Also the plot
-- Sign (the plot's sign on its SignPost).
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
		-- every plot's PADS_PER_FLOOR stands and jar looks, + plaza + decor
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
				-- the primitive Pad hides once its stand mesh lands (it keeps the prompt); the stand, standing on
				-- the floor, is what collides and what ground raycasts land dropped slimes on
				expect((pad.attributes :: any).MeshStandIn).toBe(look)
				expect((pad.attributes :: any).PadIndex).toBe(j)
				expect(pad.canCollide).toBe(false)
				local stand = child(pad, "Stand")
				expect(stand.canCollide ~= false).toBe(true)
				expect(stand.canQuery ~= false).toBe(true)
				expect((stand.attributes :: any).MeshCanQuery).toBe(true)
				local c = toPlot(i, stand.pos :: Vec)
				expect(c[2] - (stand.size :: Vec)[2] / 2).toBeCloseTo(BASE_TOP)
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
		"puts the sign on its post by the bridge at eye level, its Front face (the drawn face) out of the plot",
		function()
			expect(PlotSigns.FACES).toEqual({ "Front" })
			local board = WorldLayout.NAME_BOARD
			local spot = WorldLayout.SIGN_SPOT
			for i, plot in plots do
				local _, yaw = WorldLayout.plotCentre(i)
				local sign = child(plot, "Sign")
				local post = child(plot, "SignPost")
				local size = sign.size :: Vec
				local p = toPlot(i, sign.pos :: Vec)
				local q = toPlot(i, post.pos :: Vec)
				local postSize = post.size :: Vec
				expect(size[1]).toBeCloseTo(board.width)
				expect(size[2]).toBeCloseTo(board.height)
				expect(p[2]).toBeCloseTo(board.y)
				-- invisible: only the sign PlotSigns draws shows, no square board behind it
				expect(sign.transparency).toBe(1)
				-- on its post (the post stands behind the board and reaches into it), over the moat in front of the jar
				expect(p[1]).toBeCloseTo(q[1])
				expect(p[3] < q[3]).toBe(true)
				expect(p[1]).toBeCloseTo(spot[1] + 1.5)
				expect(q[2] + postSize[2] / 2 > p[2] - size[2] / 2).toBe(true)
				-- at eye level: off the ground, its top no higher than a player's head (about 5 studs up)
				expect(p[2] - size[2] / 2 > BASE_TOP).toBe(true)
				expect(p[2] + size[2] / 2 - BASE_TOP <= 5).toBe(true)
				expect(math.abs(p[3]) > WorldLayout.jarRadius(1) + WorldLayout.JAR_WALL).toBe(true)
				-- Roblox's Front face is local -Z: it points out of the plot (plot-local -Z, the entrance side)
				local rel = math.rad((sign.rot :: Vec)[2] - yaw)
				expect(-math.cos(rel)).toBeCloseTo(-1)
				-- a plain board: no mesh, no stand-ins
				expect(meshOf(sign)).toBe(nil)
				expect((sign.attributes or {} :: any).MeshStandIn).toBe(nil)
				expect(#(sign.children or {})).toBe(0)
			end
		end
	)
end)

describe("plot stands", function()
	it("has no BuyStand / claim model on any plot (plots auto-assign)", function()
		for _, plot in plots do
			local found = 0
			walk({ plot }, function(node)
				if node.name == "BuyStand" or node.name == "StandMesh" then
					found += 1
				end
			end)
			expect(found).toBe(0)
		end
	end)
end)
