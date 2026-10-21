--!strict
-- The goo jar tower's geometry (CONTRACT.md §5.3, WorldLayout jar section): pads fit with walkways, the stair climbs
-- one stud a step and lands flush with the deck above, the deck ring and glass walls have no gaps, the door lets a
-- character through, and every jar stays inside the plot and the lock guard's height window.
local Config = require("../src/shared/Config")
local LayoutMath = require("../src/visuals/shared/LayoutMath")
local MeshAssets = require("../src/shared/MeshAssets")
local PlotLockGuard = require("../src/server/PlotLockGuard")
local SlimeRoster = require("../src/shared/SlimeRoster")
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
	it("climbs one stud a step from floor f and lands flush with floor f + 1", function()
		expect(WorldLayout.stairSteps()).toBe(WorldLayout.FLOOR_HEIGHT)
		for f = 2, FLOORS do
			local parts = floorParts(1, f)
			local treads = named(parts, "Tread_")
			expect(#treads).toBe(WorldLayout.stairSteps())
			for k, t in treads do
				local p = toLocal(t, 1)
				expect(math.abs(p[2] + t.size[2] / 2 - (WorldLayout.floorTop(f - 1) + k)) < 1e-6).toBe(true)
			end
			local last = toLocal(treads[#treads], 1)
			expect(math.abs(last[2] + 0.5 - WorldLayout.floorTop(f)) < 1e-6).toBe(true)
		end
	end)
	it("fits inside the deck hole and leaves headroom under the next stair", function()
		local st = WorldLayout.STAIR
		expect(st.outer + 0.3 <= st.hole).toBe(true)
		for f = 1, FLOORS - 2 do
			for k = 1, WorldLayout.stairSteps() do
				local a = WorldLayout.treadAngle(f, k)
				for k2 = 1, WorldLayout.stairSteps() do
					local d = math.abs(((WorldLayout.treadAngle(f + 1, k2) - a + 180) % 360) - 180)
					if d < st.angle then
						local headroom = (WorldLayout.floorTop(f + 1) + k2 - 1) - (WorldLayout.floorTop(f) + k)
						expect(headroom >= 8).toBe(true)
					end
				end
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
	it("lands the drop tube outside the moat and inside the plot", function()
		local p = WorldLayout.dropLanding()
		local r = math.sqrt(p[1] * p[1] + p[3] * p[3])
		expect(r > WorldLayout.MOAT.outer).toBe(true)
		expect(math.abs(p[1]) < HALF and math.abs(p[3]) < HALF).toBe(true)
	end)
	it("keeps the top floor inside the lock guard's height window", function()
		expect(WorldLayout.floorTop(FLOORS) + 8 <= PlotLockGuard.MAX_Y).toBe(true)
	end)
	it("stands a trophy pedestal for every boss species on the Base, clear of the moat", function()
		expect(#WorldLayout.TROPHY_SPOTS >= #SlimeRoster.ofKind("boss")).toBe(true)
		local half = 4.5 -- the 9 x 9 pedestal
		for _, spot in WorldLayout.TROPHY_SPOTS do
			local nearX, nearZ = math.abs(spot[1]) - half, math.abs(spot[2]) - half
			expect(math.sqrt(nearX * nearX + nearZ * nearZ) > WorldLayout.MOAT.inner).toBe(true)
			expect(math.abs(spot[1]) + half <= HALF and math.abs(spot[2]) + half <= HALF).toBe(true)
		end
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
