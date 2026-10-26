--!strict
--[[
	WeatherShelter (owner: Archer, FEATURES.Weather)

	Keeps rain, snow and the starfall out of the goo jar towers. Roblox particles never collide, so one sheet
	over the camera would drop them straight through a jar's lid and glass. WeatherFx instead splits the sheet
	into TILES x TILES tiles of TILE studs, snapped to a world grid, and a tile only emits a kind of particle when
	nothing it drops can drift into a jar: its square stays clear of every plot's floor-1 glass (the widest jar)
	by that emitter's sideways reach.

	Pure maths (no Roblox APIs), so tests/WeatherShelter.spec checks it under Lune.
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")
local WorldLayout = if script then require(script.Parent.WorldLayout) else require("./WorldLayout")

local WeatherShelter = {}

WeatherShelter.TILE = 13
WeatherShelter.TILES = 7 -- per side, odd so the camera's tile is the middle one
-- Snow starts at a fixed height so every flake lands on the ground (tests/SnowCover.spec); the other weathers
-- start ABOVE_CAMERA studs over the camera.
WeatherShelter.SNOW_Y = 42
WeatherShelter.ABOVE_CAMERA = 40

export type Footprint = { x: number, z: number, r: number }
export type Motion = { lifetime: number, speed: { number }, spread: number, sideAccel: number }

-- Every plot's jar as a circle on the ground: the outside of floor 1's glass.
function WeatherShelter.footprints(): { Footprint }
	local r = WorldLayout.jarRadius(1) + WorldLayout.JAR_WALL
	local out = {}
	for i = 1, Config.PLOT_COUNT do
		local centre = WorldLayout.plotCentre(i)
		table.insert(out, { x = centre[1], z = centre[3], r = r })
	end
	return out
end

-- The largest tilt off straight down for SpreadAngle = (spread, spread): Roblox picks each axis on its own, so a
-- diagonal tilts further than `spread` (atan(sqrt 2 * tan spread)).
function WeatherShelter.maxTilt(spread: number): number
	if spread >= 90 then
		return 90
	end
	return math.deg(math.atan(math.sqrt(2) * math.tan(math.rad(spread))))
end

-- How far sideways (studs) a particle can drift while it falls `fall` studs or until it dies, at the worst angle.
function WeatherShelter.reach(e: Motion, fall: number): number
	local spread = math.rad(WeatherShelter.maxTilt(e.spread))
	local down = e.speed[1] * math.cos(spread)
	local t = if down > 1e-6 then math.min(e.lifetime, math.max(fall, 0) / down) else e.lifetime
	return e.speed[2] * math.sin(spread) * t + 0.5 * math.abs(e.sideAccel) * t * t
end

-- Centres (x, z) of the sheet's tiles round the camera, snapped to the world grid.
function WeatherShelter.tiles(camX: number, camZ: number): { { number } }
	local size, half = WeatherShelter.TILE, (WeatherShelter.TILES - 1) // 2
	local cx, cz = math.floor(camX / size + 0.5), math.floor(camZ / size + 0.5)
	local out = {}
	for i = -half, half do
		for k = -half, half do
			table.insert(out, { (cx + i) * size, (cz + k) * size })
		end
	end
	return out
end

-- True when a tile centred at (x, z) stays `margin` studs clear of every footprint.
function WeatherShelter.open(x: number, z: number, margin: number, footprints: { Footprint }): boolean
	local half = WeatherShelter.TILE / 2
	for _, f in footprints do
		local dx = math.max(math.abs(f.x - x) - half, 0)
		local dz = math.max(math.abs(f.z - z) - half, 0)
		local clear = f.r + margin
		if dx * dx + dz * dz < clear * clear then
			return false
		end
	end
	return true
end

return table.freeze(WeatherShelter)
