--!strict
-- lune run tools/placement/export  (from games/steal-a-slime)
-- Writes sheets/placement/placement.json: the kit prop placement, plot fences
-- and keep-clear zones, in world studs (x, z), for tools/placement/render.py.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Config = require("../../src/shared/Config")
local PropClearance = require("../../src/visuals/shared/PropClearance")
local WorldLayout = require("../../src/visuals/shared/WorldLayout")

local function axes(yaw: number): (number, number, number, number)
	local a = math.rad(yaw)
	return math.cos(a), -math.sin(a), math.sin(a), math.cos(a)
end

local function rect(cx: number, cz: number, hx: number, hz: number, yaw: number)
	return { cx = cx, cz = cz, hx = hx, hz = hz, yaw = yaw }
end

local function walk(node: any, visit: (any) -> ())
	visit(node)
	for _, c in node.children or {} do
		walk(c, visit)
	end
end

local plots = {}
for i, plot in WorldLayout.build()[2].children do
	local centre, yaw = WorldLayout.plotCentre(i)
	local fence, walls = {}, {}
	walk(plot, function(n)
		if n.attributes and n.attributes.MeshAsset == WorldLayout.FENCE_SEGMENT then
			table.insert(fence, rect(n.pos[1], n.pos[3], n.size[1] / 2, n.size[3] / 2, n.rot[2]))
		elseif n.attributes and n.attributes.FenceCollider then
			table.insert(walls, rect(n.pos[1], n.pos[3], n.size[1] / 2, n.size[3] / 2, n.rot[2]))
		end
	end)
	local _, _, vx, vz = axes(yaw)
	local gz = -WorldLayout.PLOT_SIZE / 2
	table.insert(plots, {
		index = i,
		rect = rect(centre[1], centre[3], WorldLayout.PLOT_SIZE / 2, WorldLayout.PLOT_SIZE / 2, yaw),
		gate = { x = centre[1] + vx * gz, z = centre[3] + vz * gz, slot = WorldLayout.GATE_SLOT, yaw = yaw },
		fence = fence,
		walls = walls,
	})
end

local props = {}
for _, p in WorldLayout.RANCH_PROPS do
	table.insert(props, {
		name = p.name,
		mesh = p.mesh,
		cluster = p.cluster,
		scale = p.scale,
		rect = PropClearance.footprint(p),
	})
end

local zones = {}
for _, z in PropClearance.ZONES do
	table.insert(zones, z)
end

local slide = {}
for _, p in WorldLayout.SLIDE_PATH do
	table.insert(slide, { p[1], p[3] })
end

local data = {
	plotCount = Config.PLOT_COUNT,
	ringPath = { radius = WorldLayout.RING_PATH_RADIUS, width = WorldLayout.RING_PATH_WIDTH },
	lane = { inner = PropClearance.LANE_INNER, outer = PropClearance.LANE_OUTER, gateAngleDeg = 90 },
	landing = { inner = 34, outer = 62 },
	fountain = { plinth = WorldLayout.FOUNTAIN_PROFILE.plinthRadius },
	slide = slide,
	edge = PropClearance.EDGE_RADIUS,
	margin = PropClearance.MARGIN,
	plots = plots,
	props = props,
	zones = zones,
}

if not fs.isDir("sheets/placement") then
	fs.writeDir("sheets/placement")
end
fs.writeFile("sheets/placement/placement.json", serde.encode("json", data, true))
print(`wrote sheets/placement/placement.json ({#props} props, {#plots} plots)`)
