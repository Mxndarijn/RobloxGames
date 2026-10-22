--!strict
-- The goo jar tower's geometry (CONTRACT.md §5.3, WorldLayout jar section): pads fit with walkways, the stair climbs
-- one stud a step and lands flush with the deck above, the deck ring and glass walls have no gaps, the door lets a
-- character through, and every jar stays inside the plot and the lock guard's height window.
local Config = require("../src/shared/Config")
local LayoutMath = require("../src/visuals/shared/LayoutMath")
local MeshAssets = require("../src/shared/MeshAssets")
local PlotLockGuard = require("../src/server/PlotLockGuard")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local FLOORS = #Config.BASE_FLOORS
local PER = Config.PADS_PER_FLOOR
local HALF = WorldLayout.PLOT_SIZE / 2

-- The round cork stand every pad wears: its foot's radius (the widest part, native size).
local STAND = (MeshAssets.get(WorldLayout.PAD_MESH) :: any).size[1] / 2

-- A part node in plot i's local frame: centre (x, y, z), size, and its local axes' yaw.
local function toLocal(node: any, i: number): ({ number }, number)
	local centre, yaw = WorldLayout.plotCentre(i)
	local back = LayoutMath.orientation({ 0, -yaw, 0 })
	local p = LayoutMath.apply(back, { node.pos[1] - centre[1], node.pos[2] - centre[2], node.pos[3] - centre[3] })
	return p, (node.rot or { 0, 0, 0 })[2] - yaw
end

-- True when plot-local (x, y, z) lies inside the box node.
local function insideBox(node: any, i: number, x: number, y: number, z: number): boolean
	local p, ry = toLocal(node, i)
	local a = math.rad(ry)
	-- local axes of a yaw rotation: +X = (cos, -sin), +Z = (sin, cos) in (x, z)
	local dx, dz = x - p[1], z - p[3]
	local lx = dx * math.cos(a) - dz * math.sin(a)
	local lz = dx * math.sin(a) + dz * math.cos(a)
	local s = node.size
	return math.abs(lx) <= s[1] / 2 + 1e-6 and math.abs(y - p[2]) <= s[2] / 2 + 1e-6 and math.abs(lz) <= s[3] / 2 + 1e-6
end

local function floorParts(i: number, f: number): ({ any }, { any })
	local nodes = WorldLayout.floor(i, f)
	return nodes[1].children, { table.unpack(nodes, 2) }
end

local function named(list: { any }, prefix: string): { any }
	local out = {}
	for _, n in list do
		if string.sub(n.name, 1, #prefix) == prefix then
			table.insert(out, n)
		end
	end
	return out
end

describe("jar tower: pads", function()
	it(
		"keeps a 2.5-stud walkway between neighbouring stands, and their habitat overlays apart, on every jar",
		function()
			for f = 1, FLOORS do
				for k = 1, PER do
					local j = (f - 1) * PER + k
					local nxt = (f - 1) * PER + k % PER + 1
					local ax, az = WorldLayout.padOffset(j)
					local bx, bz = WorldLayout.padOffset(nxt)
					local apart = math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
					expect(apart - 2 * STAND >= 2.5).toBe(true)
					expect(apart >= 2 * WorldLayout.PAD_DECK.half).toBe(true) -- an overlay is a ring on the dish
				end
			end
		end
	)
	it("keeps every stand 2.5 studs clear of the stair hole and 3.5 studs from the glass", function()
		for j = 1, Config.PADS_MAX do
			local f = WorldLayout.padFloor(j)
			local x, z = WorldLayout.padOffset(j)
			local r = math.sqrt(x * x + z * z)
			expect(r - STAND >= WorldLayout.STAIR.hole + 2.5).toBe(true)
			expect(r + STAND <= WorldLayout.jarRadius(f) - 3.5).toBe(true)
		end
	end)
	it("never puts a pad in front of the door", function()
		for k = 1, PER do
			local d = math.abs(((WorldLayout.padAngle(k) - WorldLayout.DOOR.angle + 180) % 360) - 180)
			expect(d >= 360 / PER / 2 - 1e-6).toBe(true)
		end
	end)
end)

describe("jar tower: stair", function()
	local st, ramp = WorldLayout.STAIR, WorldLayout.RAMP
	local span = st.angle * WorldLayout.stairSteps()
	-- Height above floor f of the ramp from floor f at plot-local angle `deg` (nil outside its turn).
	local function rampHeight(f: number, deg: number): number?
		local start = WorldLayout.treadAngle(f, 1) - st.angle
		local d = (deg - start) % 360
		return d / span * WorldLayout.FLOOR_HEIGHT
	end
	it("climbs from floor f to floor f + 1 in one turn of gentle ramp, ending where the next ramp starts", function()
		expect(WorldLayout.stairSteps()).toBe(WorldLayout.FLOOR_HEIGHT)
		expect(span).toBe(360)
		for f = 2, FLOORS do
			local parts = floorParts(1, f)
			expect(#named(parts, "Tread_")).toBe(0)
			local boxes = named(parts, "Ramp_")
			expect(#boxes).toBe(ramp.segments)
			local tilt = math.abs((boxes[1].rot :: any)[3])
			-- walkable on a thumbstick: well under Roblox's slope limit, gentler where feet go than the old steps
			expect(tilt > 15 and tilt < 40).toBe(true)
			for _, b in boxes do
				expect(b.canCollide ~= false).toBe(true)
				expect(math.abs((b.rot :: any)[3])).toBeCloseTo(tilt)
			end
			-- the first box starts at the floor, the last ends at the deck height
			local first, last = toLocal(boxes[1], 1), toLocal(boxes[#boxes], 1)
			local rise = WorldLayout.FLOOR_HEIGHT / ramp.segments
			expect(math.abs(first[2] - WorldLayout.floorTop(f - 1) - rise / 2) < 1).toBe(true)
			expect(math.abs(last[2] - (WorldLayout.floorTop(f) - rise / 2)) < 1).toBe(true)
			-- one unbroken spiral: no landing, and each floor's ramp starts at the angle the one below ends
			expect(#named(parts, "Landing")).toBe(0)
			expect(WorldLayout.treadAngle(f, 1)).toBe(WorldLayout.treadAngle(f - 1, 1))
		end
	end)
	it("keeps a rail along the outer edge, open at the bottom and before the top to step on and off", function()
		for f = 2, FLOORS do
			local rails = named(floorParts(1, f), "RampRail_")
			expect(#rails > 6).toBe(true)
			local start = WorldLayout.treadAngle(f - 1, 1) - st.angle
			for _, r in rails do
				expect(r.canCollide ~= false).toBe(true)
				expect(r.transparency).toBe(1)
				expect(r.canQuery).toBe(false)
				expect((r.rot :: any)[3]).toBe(0)
				local p = toLocal(r, 1)
				local deg = math.deg(math.atan2(p[3], p[1]))
				local d = (deg - start) % 360
				expect(d >= ramp.railStart and d <= span - ramp.railEnd).toBe(true)
				-- from just under the ramp to railHeight above it (too tall to step over), under the deck above
				local h = WorldLayout.FLOOR_HEIGHT
				local half = span / ramp.segments -- each rail piece is two ramp boxes wide
				local low, high = (d - half) / span * h, (d + half) / span * h
				local bottom = p[2] - r.size[2] / 2 - WorldLayout.floorTop(f - 1)
				local top = p[2] + r.size[2] / 2 - WorldLayout.floorTop(f - 1)
				expect(bottom <= low - 1 + 1e-6).toBe(true)
				expect(top >= math.min(high + 2.4, h - 1) - 1e-6).toBe(true)
				expect(top <= h - 1 + 1e-6).toBe(true)
				-- no invisible wall on the floor under the ramp's high part, nor round the hole in the deck
				if low > 6.5 then
					expect(bottom > 5).toBe(true)
				end
				expect(top - high <= ramp.railHeight + 1e-6).toBe(true)
				expect(math.sqrt(p[1] ^ 2 + p[3] ^ 2) >= st.outer).toBe(true)
			end
		end
	end)
	it("ends on the top jar with the ramp going on flat for a bit, as wide as the ramp, with no fence", function()
		local top = WorldLayout.STAIR_TOP
		for f = 2, FLOORS do
			local parts = floorParts(1, f)
			local start = WorldLayout.treadAngle(f - 1, 1) - st.angle
			local landing = named(parts, "StairLanding_")
			expect(#landing).toBe(top.landing // 15)
			expect(#named(parts, "HoleRail_")).toBe(0)
			for _, n in landing do
				-- shown and solid only while jar f is the top jar, flush with its floor, inside the hole
				expect(n.attributes.JarShow).toBe("top")
				expect(n.attributes.JarFloor).toBe(f)
				expect(n.attributes.JarCollide).toBe(true)
				expect(n.canCollide ~= false).toBe(true)
				expect(n.size[3]).toBe(st.outer - st.post + 0.4)
				local p = toLocal(n, 1)
				local d = (math.deg(math.atan2(p[3], p[1])) - start) % 360
				expect(d > 0 and d < top.landing).toBe(true)
				expect(math.sqrt(p[1] ^ 2 + p[3] ^ 2) + n.size[3] / 2 <= st.hole + 1e-6).toBe(true)
				expect(math.abs(p[2] + n.size[2] / 2 - WorldLayout.floorTop(f)) < 1e-6).toBe(true)
			end
		end
	end)
	it("fits inside the deck hole and leaves headroom under the next ramp", function()
		expect(st.outer + 0.3 <= st.hole).toBe(true)
		for f = 1, FLOORS - 2 do
			for deg = 0, 359, 5 do
				local below = WorldLayout.floorTop(f) + (rampHeight(f, deg) :: number)
				local above = WorldLayout.floorTop(f + 1) + (rampHeight(f + 1, deg) :: number) - 1
				expect(above - below >= 8).toBe(true)
			end
		end
	end)
end)

describe("jar tower: deck and glass", function()
	it("covers every upper deck from the stair hole out over the jar below, without gaps", function()
		for f = 2, FLOORS do
			local decks = named(floorParts(1, f), "Deck_")
			local y = WorldLayout.floorTop(f) - 0.5
			local outer = WorldLayout.jarRadius(f - 1)
			for r = WorldLayout.STAIR.hole + 0.2, outer, 1.3 do
				for deg = 0, 359, 3 do
					local x, z = WorldLayout.polar(r, deg)
					local hit = false
					for _, d in decks do
						if insideBox(d, 1, x, y, z) then
							hit = true
							break
						end
					end
					expect(hit).toBe(true)
				end
			end
		end
	end)
	it("closes every upper jar's wall all the way round, floor to deck, inside the glass", function()
		local n = WorldLayout.JAR_WALL_SEGMENTS
		for f = 2, FLOORS do
			local walls = named(floorParts(1, f), "Wall_")
			expect(#walls).toBe(n)
			local rc = WorldLayout.jarWallRadius(f)
			-- the inner faces' corners sit on the glass, never outside it
			expect((rc - WorldLayout.JAR_WALL / 2) / math.cos(math.pi / n) <= WorldLayout.jarRadius(f) + 1e-6).toBe(
				true
			)
			for _, h in { 0.5, 7, WorldLayout.FLOOR_HEIGHT - 1.5 } do
				for deg = 0, 359, 2 do
					local x, z = WorldLayout.jarWallPoint(f, deg)
					local hit = false
					for _, w in walls do
						if insideBox(w, 1, x, WorldLayout.floorTop(f) + h, z) then
							hit = true
							break
						end
					end
					expect(hit).toBe(true)
				end
			end
		end
	end)
	it("gives each upper jar one lid, tagged with its floor", function()
		for f = 2, FLOORS do
			local lids = named(floorParts(1, f), "Lid")
			expect(#lids).toBe(1)
			expect(lids[1].attributes.JarLid).toBe(f)
		end
	end)
	it("builds each upper jar's pads, named and indexed", function()
		for f = 2, FLOORS do
			local _, pads = floorParts(1, f)
			expect(#pads).toBe(PER)
			for k, pad in pads do
				expect(pad.name).toBe(`Pad_{(f - 1) * PER + k}`)
				expect(pad.attributes.PadIndex).toBe((f - 1) * PER + k)
			end
		end
	end)
end)

describe("jar tower: fits the plot", function()
	it("keeps every jar and the moat inside the plot, smaller jars on top", function()
		expect(#WorldLayout.JAR_RADII).toBe(FLOORS)
		for f = 1, FLOORS do
			expect(WorldLayout.jarRadius(f) + WorldLayout.JAR_WALL <= WorldLayout.MOAT.inner).toBe(true)
			if f > 1 then
				expect(WorldLayout.jarRadius(f) <= WorldLayout.jarRadius(f - 1)).toBe(true)
			end
		end
		expect(WorldLayout.MOAT.outer < HALF).toBe(true)
	end)
	it("lands the drop tube in the goo moat, on the round plot floor", function()
		local p = WorldLayout.dropLanding()
		local r = math.sqrt(p[1] * p[1] + p[3] * p[3])
		expect(r > WorldLayout.MOAT.inner and r < WorldLayout.MOAT.outer).toBe(true)
		expect(r < WorldLayout.PLOT_FLOOR_RADIUS).toBe(true)
		expect(math.abs(p[1]) < HALF and math.abs(p[3]) < HALF).toBe(true)
	end)
	it("keeps the top floor inside the lock guard's height window", function()
		expect(WorldLayout.floorTop(FLOORS) + 8 <= PlotLockGuard.MAX_Y).toBe(true)
	end)
	it("spawns players on the walkway between the stair and the pads, in front of the door", function()
		local s = WorldLayout.SPAWN_SPOT
		local r = math.sqrt(s[1] * s[1] + s[2] * s[2])
		expect(r > WorldLayout.STAIR.hole + 1).toBe(true)
		expect(r < WorldLayout.PAD_RINGS[1] - WorldLayout.PAD_SIZE / 2 - 1).toBe(true)
		expect(s[2] < 0).toBe(true)
	end)
	it("lets a character through the door", function()
		expect(WorldLayout.DOOR.width >= 6).toBe(true)
		expect(WorldLayout.DOOR.height >= 7).toBe(true)
	end)
end)
