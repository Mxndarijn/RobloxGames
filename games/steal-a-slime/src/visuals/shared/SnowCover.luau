--!strict
--[[
	SnowCover (owner: Archer, FEATURES.Weather, v30 F2)

	The ground snow cover as pure maths, so the Lune tests can pin it. `level` is 0..1: it builds up while it
	snows (BUILD_SECONDS from bare to full) and melts away after (MELT_SECONDS from full to bare). The client
	draws it as ONE flat translucent Snow-material part over the Ground (SnowGround), its Transparency going
	from CLEAR_TRANSPARENCY (bare) to FULL_TRANSPARENCY (full cover). No per-flake parts, no meshes.
]]

local SnowCover = {}

SnowCover.BUILD_SECONDS = 50
SnowCover.MELT_SECONDS = 35
SnowCover.CLEAR_TRANSPARENCY = 1
SnowCover.FULL_TRANSPARENCY = 0.22

-- Runtime cost, checked against WorldLayout's budgets by tests/SnowCover.spec: one Part, no MeshPart.
SnowCover.PART_COUNT = 1
SnowCover.MESH_SLOTS = 0

-- Same footprint as the Ground block (WorldLayout: 640 x 640, top at y 0); the layer sits above the path tops
-- (<= 0.05) so paths and plaza are covered too, and below every pad / prop.
SnowCover.SIZE = table.freeze({ 640, 0.1, 640 })
SnowCover.TOP = 0.08

function SnowCover.step(level: number, dt: number, snowing: boolean): number
	if snowing then
		return math.min(1, level + dt / SnowCover.BUILD_SECONDS)
	end
	return math.max(0, level - dt / SnowCover.MELT_SECONDS)
end

-- Smooth-stepped so the cover eases in and out instead of popping at the ends.
function SnowCover.transparency(level: number): number
	local x = math.clamp(level, 0, 1)
	local e = x * x * (3 - 2 * x)
	return SnowCover.CLEAR_TRANSPARENCY + (SnowCover.FULL_TRANSPARENCY - SnowCover.CLEAR_TRANSPARENCY) * e
end

-- The part is only needed while there is something to show.
function SnowCover.visible(level: number): boolean
	return level > 0.001
end

-- True while level still has to move (Heartbeat can stop otherwise).
function SnowCover.settled(level: number, snowing: boolean): boolean
	return (snowing and level >= 1) or (not snowing and level <= 0)
end

return table.freeze(SnowCover)
