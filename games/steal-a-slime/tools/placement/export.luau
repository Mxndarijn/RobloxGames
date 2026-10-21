--!strict
-- lune run tools/placement/export  (from games/steal-a-slime)
-- Writes sheets/placement/placement.json: the kit prop placement, the plots'
-- ground jars (glass, moat, door), the world border (wall ring + edge pieces)
-- and keep-clear zones, in world studs (x, z), for tools/placement/render.py.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Config = require("../../src/shared/Config")
local PropClearance = require("../../src/visuals/shared/PropClearance")
local WorldBorder = require("../../src/visuals/shared/WorldBorder")
local WorldLayout = require("../../src/visuals/shared/WorldLayout")

local function axes(yaw: number): (number, number, number, number)
	local a = math.rad(yaw)
	return math.cos(a), -math.sin(a), math.sin(a), math.cos(a)
end

local function rect(cx: number, cz: number, hx: number, hz: number, yaw: number)
	return { cx = cx, cz = cz, hx = hx, hz = hz, yaw = yaw }
end

local plots = {}
for i in WorldLayout.build()[2].children do
	local centre, yaw = WorldLayout.plotCentre(i)
	local _, _, vx, vz = axes(yaw)
	local dz = -(WorldLayout.jarRadius(1) + WorldLayout.JAR_WALL)
	table.insert(plots, {
		index = i,
		rect = rect(centre[1], centre[3], WorldLayout.PLOT_SIZE / 2, WorldLayout.PLOT_SIZE / 2, yaw),
		jar = { x = centre[1], z = centre[3], radius = WorldLayout.jarRadius(1) + WorldLayout.JAR_WALL },
		moat = WorldLayout.MOAT.outer,
		door = { x = centre[1] + vx * dz, z = centre[3] + vz * dz, width = WorldLayout.DOOR.width, yaw = yaw },
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

local border = {}
for _, q in WorldBorder.pieces() do
	local f = PropClearance.footprint(q)
	table.insert(border, { kind = q.kind, row = q.row, uploaded = q.uploaded, rect = f })
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
	wallRadius = WorldBorder.RADIUS,
	border = border,
	margin = PropClearance.MARGIN,
	plots = plots,
	props = props,
	zones = zones,
}

if not fs.isDir("sheets/placement") then
	fs.writeDir("sheets/placement")
end
fs.writeFile("sheets/placement/placement.json", serde.encode("json", data, true))
print(`wrote sheets/placement/placement.json ({#props} props, {#plots} plots, {#border} border pieces)`)
