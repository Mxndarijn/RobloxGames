--!nocheck
-- lune run tools/render/lane_centreline   (from games/steal-a-slime)
-- Writes the goo lane's centreline for shared/modeling-kit/models/slime_lane.py:
-- the slide mouth, the lead-in to ENTRY, then every ParadeLane waypoint ({ x, z } in world studs),
-- with LANE_Y, HALF_WIDTH, the lane colour and `cut`, the point where the mesh ends (the drain taper starts).
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

-- The mesh ends where the drain taper starts (ParadeLane.stripEndPoints' last point); the taper strips carry on from there.
local stripEnd = ParadeLane.stripEndPoints()
local cut = stripEnd[#stripEnd]

local OUT = "../../shared/modeling-kit/inputs/slime_lane_centreline.json"
fs.writeFile(
	OUT,
	serde.encode("json", {
		laneY = ParadeLane.LANE_Y,
		halfWidth = ParadeLane.HALF_WIDTH,
		color = ParadeLane.COLOR,
		points = points,
		cut = { cut[1], cut[2] },
	})
)
print(`wrote {OUT}: {#points} points`)
