--!strict
local Config = require("../src/shared/Config")
local TestRunner = require("./TestRunner")
local WeatherLook = require("../src/visuals/shared/WeatherLook")
local WeatherShelter = require("../src/visuals/shared/WeatherShelter")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local FLOOR = WorldLayout.PLOT_FLOOR_TOP
local footprints = WeatherShelter.footprints()

-- Flies one particle from (x, y, z) at `speed` along (dx, dy, dz) with the emitter's sideways pull until it lands
-- or dies; true when it ever comes inside a jar's glass.
local function entersJar(spec: any, x: number, y: number, z: number, dx: number, dy: number, dz: number, speed: number)
	local dt, t = 0.05, 0
	local vx, vy, vz = dx * speed, dy * speed, dz * speed
	while t < spec.lifetime and y > FLOOR do
		for _, f in footprints do
			local ox, oz = x - f.x, z - f.z
			if ox * ox + oz * oz < f.r * f.r then
				return true
			end
		end
		vx += spec.sideAccel * dt
		x, y, z = x + vx * dt, y + vy * dt, z + vz * dt
		t += dt
	end
	return false
end

-- Directions a SpreadAngle = (s, s) emitter pointing down can fire: like Roblox, each axis tilts on its own by up to
-- s, so the diagonals tilt further than s. A spread past 90 can fire anywhere: 16 headings at 0..180 degrees.
local function directions(spread: number): { { number } }
	local out = {}
	if spread < 90 then
		local steps = { -1, -0.5, 0, 0.5, 1 }
		for _, sx in steps do
			for _, sz in steps do
				local tx, tz = math.tan(math.rad(spread * sx)), math.tan(math.rad(spread * sz))
				local len = math.sqrt(tx * tx + 1 + tz * tz)
				table.insert(out, { tx / len, -1 / len, tz / len })
			end
		end
	else
		for _, tilt in { 0, 45, 90, 135, 180 } do
			local a = math.rad(tilt)
			for h = 0, 15 do
				local heading = h * math.pi / 8
				table.insert(out, { math.sin(a) * math.cos(heading), -math.cos(a), math.sin(a) * math.sin(heading) })
			end
		end
	end
	return out
end

-- Every way a particle can leave an open tile of the sheet over camera (camX, camY, camZ) (tile corners, edge
-- midpoints and centre; every direction the spread allows; slowest and fastest).
local function leaks(name: string, camX: number, camY: number, camZ: number, snow: boolean): number
	local spec = WeatherLook.EMITTERS[name]
	local y = if snow then WeatherShelter.SNOW_Y else camY + WeatherShelter.ABOVE_CAMERA
	local margin = WeatherShelter.reach(spec, y - FLOOR)
	local half = WeatherShelter.TILE / 2
	local dirs = directions(spec.spread)
	local count = 0
	for _, c in WeatherShelter.tiles(camX, camZ) do
		if WeatherShelter.open(c[1], c[2], margin, footprints) then
			for _, ox in { -half, 0, half } do
				for _, oz in { -half, 0, half } do
					for _, d in dirs do
						for _, speed in spec.speed do
							if entersJar(spec, c[1] + ox, y, c[2] + oz, d[1], d[2], d[3], speed) then
								count += 1
							end
						end
					end
				end
			end
		end
	end
	return count
end

describe("WeatherShelter", function()
	it("has one jar footprint per plot, round the plot centre and as wide as the bottom jar's glass", function()
		expect(#footprints).toBe(Config.PLOT_COUNT)
		for i, f in footprints do
			local centre = WorldLayout.plotCentre(i)
			expect(f.x).toBe(centre[1])
			expect(f.z).toBe(centre[3])
			for floor = 1, #WorldLayout.JAR_RADII do
				expect(f.r >= WorldLayout.jarRadius(floor)).toBe(true)
			end
		end
	end)

	it("lays a square sheet of world-snapped tiles round the camera", function()
		local size = WeatherShelter.TILE
		local a = WeatherShelter.tiles(3, -4)
		expect(#a).toBe(WeatherShelter.TILES * WeatherShelter.TILES)
		local b = WeatherShelter.tiles(3 + size * 0.1, -4 - size * 0.1) -- a small step: the same tiles
		for i, c in a do
			expect(c[1]).toBe(b[i][1])
			expect(c[2]).toBe(b[i][2])
			expect(c[1] % size).toBe(0)
		end
		local camX, camZ = 101.7, -55.2
		local under = false
		for _, c in WeatherShelter.tiles(camX, camZ) do
			if math.abs(c[1] - camX) <= size / 2 and math.abs(c[2] - camZ) <= size / 2 then
				under = true
			end
		end
		expect(under).toBe(true)
	end)

	it("shuts the tile over a jar for every weather and leaves the open plaza raining", function()
		for _, spec in WeatherLook.EMITTERS do
			local margin = WeatherShelter.reach(spec, 60)
			for _, f in footprints do
				expect(WeatherShelter.open(f.x, f.z, margin, footprints)).toBe(false)
			end
		end
		expect(WeatherShelter.open(0, 0, WeatherShelter.reach(WeatherLook.EMITTERS.Drops, 60), footprints)).toBe(true)
	end)

	it("rain falls straight, so only the jar itself is kept dry", function()
		expect(WeatherShelter.reach(WeatherLook.EMITTERS.Drops, 80)).toBe(0)
		expect(WeatherShelter.reach(WeatherLook.EMITTERS.Flakes, 41) > 0).toBe(true)
	end)

	it("no rain, snow or starfall particle from an open tile ever ends up inside a jar", function()
		local plot = WorldLayout.plotCentre(1)
		local r = footprints[1].r
		-- camera inside the jar, at its glass, just outside and up on a tall tower
		local spots = {
			{ plot[1], 6, plot[3] },
			{ plot[1] + r, 6, plot[3] },
			{ plot[1] + r + 15, 8, plot[3] - 20 },
			{ plot[1] - 10, 60, plot[3] + 10 },
		}
		for _, at in spots do
			expect(leaks("Flakes", at[1], at[2], at[3], true)).toBe(0)
			for _, name in { "Drops", "Stars", "Glints" } do
				expect(leaks(name, at[1], at[2], at[3], false)).toBe(0)
			end
		end
	end)
end)
