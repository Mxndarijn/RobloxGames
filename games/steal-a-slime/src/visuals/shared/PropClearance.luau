--!strict
--[[
	PropClearance (owner: Archer)

	The ground the kit props must keep clear, and the footprint tests for it.
	Pure (no Roblox APIs); tests/RanchProps.spec and the placement map
	exporter use it on WorldLayout.RANCH_PROPS.

	Keep-clear zones (MARGIN studs of air round each):
	  ring   fountain plinth (r 13.1), slide (spiral to r 35.5), wild landing
	         band (r 34-62), parade lane (r 64.75-71.25, gate arch posts
	         62.25-73.75), ring path (r 74-82)
	  rect   each plot (80 x 80, props stay outside the fence) and its
	         entrance corridor (the 20-stud gate slot out to the ring path)
	  circle PROP_SPOTS (shops, Hall of Fame boards, arch, Professor Goo: 12 like WorldLayout's
	         decor; the tutorial NPC only its own footprint, SPOT_RADII, so its
	         corner can be dressed), the plaza showpieces (signpost, podiums =
	         the leaderboard stands), the Hall of Fame plaza (r 50), the obby
	         portal (WorldLayout.OBBY.clearRadius)
	  rect   the Hall of Fame path from the ring path out to the plaza, and the obby path out to its portal
	  edge   the WorldBorder wall ring (inner face r 292) and its edge decor:
	         props stay inside r EDGE_RADIUS (12 studs short of the walls)
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")
local ParadeLane = if script
	then require(script.Parent.Parent.Shared.ParadeLane)
	else require("../../shared/ParadeLane")
local WorldBorder = if script then require(script.Parent.WorldBorder) else require("./WorldBorder")
local WorldLayout = if script then require(script.Parent.WorldLayout) else require("./WorldLayout")

export type Rect = { cx: number, cz: number, hx: number, hz: number, yaw: number }
export type Zone = {
	name: string,
	kind: string, -- "ring" | "rect" | "circle"
	inner: number?, -- ring
	outer: number?,
	rect: Rect?,
	x: number?, -- circle
	z: number?,
	radius: number?,
}

local PropClearance = {}

PropClearance.MARGIN = 1
PropClearance.EDGE_RADIUS = WorldBorder.RADIUS - 12
PropClearance.SPOT_RADIUS = 12
-- Spots whose own corner is dressed (RanchProps "Guide*" rows stand round the Guide): their circle is the prop's own
-- footprint, and the rows keep the walk-up side towards the plaza open.
-- The Upcoming Events board (WorldLayout.EVENT_BOARD) is a flat 16-stud board: half its width.
-- The Exclusive Shop's claw shop (WorldLayout.EXCLUSIVE_CLAW): the kit's footprint radius (half the shop's diagonal
-- from above, counter included) at the stand's scale.
local spotRadii: { [string]: number } = { TutorialNpc = 3, EventBoard = 9 }
do
	local claw = WorldLayout.EXCLUSIVE_CLAW
	spotRadii[claw.model] = claw.footprint * claw.scale
end
PropClearance.SPOT_RADII = table.freeze(spotRadii)

function PropClearance.spotRadius(name: string): number
	return PropClearance.SPOT_RADII[name] or PropClearance.SPOT_RADIUS
end
-- Lane half width incl. edging (kit: r 64.75..71.25) and the gate arch posts.
PropClearance.LANE_INNER = ParadeLane.LANE_RADIUS - 3.25
PropClearance.LANE_OUTER = ParadeLane.LANE_RADIUS + 3.25
PropClearance.LANE_POSTS_INNER = 62.25
PropClearance.LANE_POSTS_OUTER = 73.75
-- Entrance corridor in front of the bridge, from the plot's front edge out to
-- the ring path centreline, in plot-local coordinates.
PropClearance.CORRIDOR_HALF = WorldLayout.ENTRANCE_CLEAR / 2

-- Unit axes of a slot turned `yaw` degrees (Roblox: +Z -> (sin, cos)).
local function axes(yaw: number): (number, number, number, number)
	local a = math.rad(yaw)
	return math.cos(a), -math.sin(a), math.sin(a), math.cos(a)
end

function PropClearance.footprint(prop: { pos: { number }, size: { number }, yaw: number }): Rect
	return { cx = prop.pos[1], cz = prop.pos[3], hx = prop.size[1] / 2, hz = prop.size[3] / 2, yaw = prop.yaw }
end

-- Plot-local rect -> world rect.
local function plotRect(i: number, x: number, z: number, hx: number, hz: number): Rect
	local centre, yaw = WorldLayout.plotCentre(i)
	local ux, uz, vx, vz = axes(yaw)
	return { cx = centre[1] + ux * x + vx * z, cz = centre[3] + uz * x + vz * z, hx = hx, hz = hz, yaw = yaw }
end

-- Separating axis test for two turned rectangles, grown by `pad`.
function PropClearance.rectsOverlap(a: Rect, b: Rect, pad: number?): boolean
	local grow = pad or 0
	local aux, auz, avx, avz = axes(a.yaw)
	local bux, buz, bvx, bvz = axes(b.yaw)
	local dx, dz = b.cx - a.cx, b.cz - a.cz
	for _, axis in { { aux, auz }, { avx, avz }, { bux, buz }, { bvx, bvz } } do
		local x, z = axis[1], axis[2]
		local ra = (a.hx + grow) * math.abs(aux * x + auz * z) + (a.hz + grow) * math.abs(avx * x + avz * z)
		local rb = b.hx * math.abs(bux * x + buz * z) + b.hz * math.abs(bvx * x + bvz * z)
		if math.abs(dx * x + dz * z) >= ra + rb then
			return false
		end
	end
	return true
end

-- Nearest and farthest distance from the fountain axis over a rectangle.
local function radialRange(r: Rect): (number, number)
	local ux, uz, vx, vz = axes(r.yaw)
	local far = 0
	for _, c in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		local x = r.cx + ux * r.hx * c[1] + vx * r.hz * c[2]
		local z = r.cz + uz * r.hx * c[1] + vz * r.hz * c[2]
		far = math.max(far, math.sqrt(x * x + z * z))
	end
	-- Closest point of the rect to the origin: clamp the origin into it.
	local ox, oz = -r.cx, -r.cz
	local lu = math.clamp(ox * ux + oz * uz, -r.hx, r.hx)
	local lv = math.clamp(ox * vx + oz * vz, -r.hz, r.hz)
	local nx, nz = r.cx + ux * lu + vx * lv, r.cz + uz * lu + vz * lv
	return math.sqrt(nx * nx + nz * nz), far
end

local function circleHits(r: Rect, x: number, z: number, radius: number): boolean
	local ux, uz, vx, vz = axes(r.yaw)
	local dx, dz = x - r.cx, z - r.cz
	local lu = math.clamp(dx * ux + dz * uz, -r.hx, r.hx)
	local lv = math.clamp(dx * vx + dz * vz, -r.hz, r.hz)
	local px, pz = r.cx + ux * lu + vx * lv, r.cz + uz * lu + vz * lv
	return (px - x) ^ 2 + (pz - z) ^ 2 < radius * radius
end

local zones: { Zone } = {}
local function ring(name: string, inner: number, outer: number)
	table.insert(zones, { name = name, kind = "ring", inner = inner, outer = outer })
end
local fp = WorldLayout.FOUNTAIN_PROFILE
local ringOuter = WorldLayout.RING_PATH_RADIUS + WorldLayout.RING_PATH_WIDTH / 2
ring("fountain", 0, fp.plinthRadius)
ring("slide", 0, WorldLayout.SLIDE_END_RADIUS + 1)
ring("landing band", 34, 62)
ring("parade lane", PropClearance.LANE_INNER, PropClearance.LANE_OUTER)
ring("parade gate posts", PropClearance.LANE_POSTS_INNER, PropClearance.LANE_POSTS_OUTER)
ring("ring path", WorldLayout.RING_PATH_RADIUS - WorldLayout.RING_PATH_WIDTH / 2, ringOuter)
local half = WorldLayout.PLOT_SIZE / 2
for i = 1, Config.PLOT_COUNT do
	table.insert(zones, { name = `plot {i}`, kind = "rect", rect = plotRect(i, 0, 0, half, half) })
	-- Corridor from the front fence (local z -40) to the ring path centreline.
	local front = -half
	local outer = WorldLayout.RING_PATH_RADIUS - WorldLayout.PLOT_RING_RADIUS
	local hz = (front - outer) / 2
	table.insert(zones, {
		name = `plot {i} entrance`,
		kind = "rect",
		rect = plotRect(i, 0, (front + outer) / 2, PropClearance.CORRIDOR_HALF, hz),
	})
end
local spotNames = {}
for name in WorldLayout.PROP_SPOTS do
	table.insert(spotNames, name)
end
table.sort(spotNames)
for _, name in spotNames do
	local spot = WorldLayout.PROP_SPOTS[name]
	table.insert(
		zones,
		{ name = name, kind = "circle", x = spot.pos[1], z = spot.pos[3], radius = PropClearance.spotRadius(name) }
	)
end
for _, def in WorldLayout.PLAZA_PROPS do
	local a = math.rad(def.yaw)
	local size = def.size :: { number }
	table.insert(zones, {
		name = def.name,
		kind = "circle",
		x = math.sin(a) * def.r,
		z = math.cos(a) * def.r,
		radius = math.sqrt(size[1] ^ 2 + size[3] ^ 2) / 2,
	})
end
-- The Hall of Fame plaza and the path out to it.
do
	local hall = WorldLayout.HALL_OF_FAME
	local centre = WorldLayout.hallPoint(0, 0)
	table.insert(zones, { name = "Hall of Fame", kind = "circle", x = centre[1], z = centre[3], radius = hall.radius })
	local from, to = ringOuter, hall.distance - hall.radius
	local mid = WorldLayout.hallPoint(0, (from + to) / 2 - hall.distance)
	table.insert(zones, {
		name = "Hall of Fame path",
		kind = "rect",
		rect = { cx = mid[1], cz = mid[3], hx = hall.pathWidth / 2, hz = (to - from) / 2, yaw = hall.bearing },
	})
end
-- The obby portal and its sign, and the path out to it.
do
	local portal = WorldLayout.obbyPortal()
	table.insert(
		zones,
		{ name = "Obby portal", kind = "circle", x = portal[1], z = portal[3], radius = WorldLayout.OBBY.clearRadius }
	)
	local path = WorldLayout.obbyPath()
	table.insert(zones, {
		name = "Obby path",
		kind = "rect",
		rect = { cx = path.x, cz = path.z, hx = path.width / 2, hz = path.length / 2, yaw = path.bearing },
	})
end
PropClearance.ZONES = table.freeze(zones)

-- Names of the zones a prop's footprint enters (with MARGIN), empty when clear.
function PropClearance.conflicts(prop: { pos: { number }, size: { number }, yaw: number }): { string }
	local m = PropClearance.MARGIN
	local rect = PropClearance.footprint(prop)
	local near, far = radialRange(rect)
	local out = {}
	for _, zone in zones do
		local hit = false
		if zone.kind == "ring" then
			hit = near < (zone.outer :: number) + m and far > (zone.inner :: number) - m
		elseif zone.kind == "rect" then
			hit = PropClearance.rectsOverlap(zone.rect :: Rect, rect, m)
		else
			hit = circleHits(rect, zone.x :: number, zone.z :: number, (zone.radius :: number) + m)
		end
		if hit then
			table.insert(out, zone.name)
		end
	end
	if far > PropClearance.EDGE_RADIUS then
		table.insert(out, "world edge")
	end
	return out
end

return table.freeze(PropClearance)
