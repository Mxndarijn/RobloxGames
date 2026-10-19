--!nocheck
-- lune run tools/render/lane_centreline   (from games/steal-a-slime)
-- Writes the goo lane's centreline for shared/modeling-kit/models/slime_lane.py:
-- the slide mouth, the lead-in to ENTRY, then every ParadeLane waypoint ({ x, z } in world studs),
-- with LANE_Y, HALF_WIDTH, the lane colour and the drain curb the end touches.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local ParadeLane = require("../../src/shared/ParadeLane")

local points = { { ParadeLane.MOUTH[1], ParadeLane.MOUTH[2] } }
for i = 2, #ParadeLane.LEAD - 1 do
	table.insert(points, { ParadeLane.LEAD[i][1], ParadeLane.LEAD[i][2] })
end
for _, p in ParadeLane.WAYPOINTS do
	table.insert(points, { p[1], p[2] })
end

local OUT = "../../shared/modeling-kit/inputs/slime_lane_centreline.json"
fs.writeFile(
	OUT,
	serde.encode("json", {
		laneY = ParadeLane.LANE_Y,
		halfWidth = ParadeLane.HALF_WIDTH,
		-- the width eases to endHalfWidth over the last taperLength studs before this circle (ParadeLane.halfWidthAt)
		taper = {
			endHalfWidth = ParadeLane.END_HALF_WIDTH,
			length = ParadeLane.TAPER_LENGTH,
			x = ParadeLane.DRAIN.x,
			z = ParadeLane.DRAIN.z,
			radius = ParadeLane.DRAIN.lipRadius,
		},
		color = ParadeLane.COLOR,
		points = points,
		-- the drain's outer curb disc (WorldLayout DrainCurb, centre z 52.475): the mesh end stops on its outer face
		drain = { x = ParadeLane.DRAIN.x, z = 52.475, radius = ParadeLane.DRAIN.lipRadius },
	})
)
print(`wrote {OUT}: {#points} points`)
