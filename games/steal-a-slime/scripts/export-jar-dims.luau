--!strict
-- Writes the goo jar tower's numbers from WorldLayout to shared/modeling-kit/inputs/goo_jar_dims.json, so every kit
-- model of the tower (jar glass, frame, stand, door, stopper, tube, mascot) is built to the game's own sizes and the
-- assembled preview sits where the game puts things. Run from games/steal-a-slime:
--   lune run scripts/export-jar-dims
-- tests/JarMeshes.spec.luau fails when the committed JSON is stale.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Config = require("../src/shared/Config")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local OUT = "../../shared/modeling-kit/inputs/goo_jar_dims.json"

local function dims(): { [string]: any }
	local floors = {}
	for f = 1, #Config.BASE_FLOORS do
		local pads = {}
		for k = 1, Config.PADS_PER_FLOOR do
			local j = (f - 1) * Config.PADS_PER_FLOOR + k
			local x, z = WorldLayout.padOffset(j)
			table.insert(pads, { x = x, z = z, angle = WorldLayout.padAngle(j) })
		end
		local treads = {}
		if f < #Config.BASE_FLOORS then
			for k = 1, WorldLayout.stairSteps() do
				table.insert(treads, WorldLayout.treadAngle(f, k))
			end
		end
		table.insert(floors, {
			floor = f,
			top = WorldLayout.floorTop(f),
			radius = WorldLayout.jarRadius(f),
			padRing = WorldLayout.PAD_RINGS[f],
			pads = pads,
			treads = treads,
		})
	end
	local doorway = WorldLayout.doorway()
	return {
		floorHeight = WorldLayout.FLOOR_HEIGHT,
		plotFloorTop = WorldLayout.PLOT_FLOOR_TOP,
		plotSize = WorldLayout.PLOT_SIZE,
		jarWall = WorldLayout.JAR_WALL,
		glassTransparency = WorldLayout.JAR_GLASS_MESH_TRANSPARENCY,
		padSize = WorldLayout.PAD_SIZE,
		padSeatY = WorldLayout.PAD_SEAT_Y,
		padDeck = WorldLayout.PAD_DECK,
		stair = WorldLayout.STAIR,
		door = WorldLayout.DOOR,
		doorway = { zOuter = doorway.zOuter, zInner = doorway.zInner },
		moat = WorldLayout.MOAT,
		bridgeWidth = WorldLayout.BRIDGE_WIDTH,
		dropAngle = WorldLayout.DROP_ANGLE,
		dropTube = WorldLayout.DROP_TUBE,
		dropLanding = WorldLayout.dropLanding(),
		vatSpot = WorldLayout.VAT_SPOT,
		lockButtonSpot = WorldLayout.LOCK_BUTTON_SPOT,
		label = WorldLayout.LABEL,
		floors = floors,
	}
end

local text = serde.encode("json", dims(), true) .. "\n"
fs.writeFile(OUT, text)
print(`wrote {OUT}`)

return dims
