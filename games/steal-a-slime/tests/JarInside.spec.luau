--!strict
-- Who stands inside which base, and the steal rule built on it: a thief must be inside the owner's base, on the
-- slime's floor. Every base has pads within STEAL_REACH of a spot just outside its glass, so distance alone is not
-- enough.
local BaseShapes = require("../src/visuals/shared/BaseShapes")
local Config = require("../src/shared/Config")
local JarInside = require("../src/shared/JarInside")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local DOORWAY = WorldLayout.doorway()
local BRIDGE = DOORWAY.zOuter - 3 -- on the bridge, just outside the stopper
local FLOORS = #Config.BASE_FLOORS
local JAR: JarInside.Jar = {
	radii = WorldLayout.JAR_RADII,
	floorTop = WorldLayout.PLOT_FLOOR_TOP,
	floorHeight = WorldLayout.FLOOR_HEIGHT,
	wall = WorldLayout.JAR_WALL,
}
local CHARACTER = 3 -- a character's root above the floor it stands on
local SLIME = 1.5 -- a pad slime's Body above its floor

describe("JarInside.inside", function()
	local floor1 = WorldLayout.PLOT_FLOOR_TOP + CHARACTER
	it("counts the middle of jar 1 as inside and the bridge as outside", function()
		expect(JarInside.inside(0, floor1, 0, JAR, 1, false)).toBe(true)
		expect(JarInside.inside(0, floor1, BRIDGE, JAR, 1, false)).toBe(false)
	end)
	it("keeps a character inside while it leans on the glass or the stopper", function()
		local r = WorldLayout.jarRadius(1)
		expect(JarInside.inside(0, floor1, -(r - 0.5), JAR, 1, false)).toBe(false)
		expect(JarInside.inside(0, floor1, -(r - 0.5), JAR, 1, true)).toBe(true)
		expect(JarInside.inside(0, floor1, BRIDGE, JAR, 1, true)).toBe(false)
	end)
	it("only counts floors that are built", function()
		local floor2 = WorldLayout.floorTop(2) + CHARACTER
		expect(JarInside.inside(0, floor2, 0, JAR, 1, false)).toBe(false)
		expect(JarInside.inside(0, floor2, 0, JAR, 2, false)).toBe(true)
	end)
end)

describe("JarInside floors", function()
	it("counts a free plot as one floor and grows with the pads", function()
		expect(JarInside.builtFloors(0)).toBe(1)
		expect(JarInside.builtFloors(Config.PADS_PER_FLOOR)).toBe(2)
		expect(JarInside.builtFloors(Config.PADS_MAX)).toBe(FLOORS)
	end)
	it("puts a jumping character on the floor it jumped from", function()
		local jumpTop = WorldLayout.floorTop(1) + CHARACTER + 7.5
		expect(JarInside.floorAt(jumpTop, JAR, FLOORS)).toBe(1)
		expect(JarInside.floorAt(WorldLayout.floorTop(2) + SLIME, JAR, FLOORS)).toBe(2)
		expect(JarInside.floorAt(WorldLayout.floorTop(FLOORS) + 40, JAR, 2)).toBe(2)
	end)
end)

describe("JarInside.canReach", function()
	it("lets a thief inside on the slime's floor reach it", function()
		local x, z = WorldLayout.padOffset(1)
		local slime = { x, WorldLayout.floorTop(1) + SLIME, z }
		expect(JarInside.canReach({ x * 0.8, WorldLayout.floorTop(1) + CHARACTER, z * 0.8 }, slime, JAR, 1)).toBe(true)
	end)
	it("refuses a thief jumping under an upper pad", function()
		local j = Config.PADS_PER_FLOOR + 1
		local x, z = WorldLayout.padOffset(j)
		local slime = { x, WorldLayout.floorTop(2) + SLIME, z }
		local jumping = { x, WorldLayout.floorTop(1) + CHARACTER + 7.5, z }
		local dy = slime[2] - jumping[2]
		expect(dy < Config.STEAL_REACH).toBe(true) -- in reach through the deck
		expect(JarInside.canReach(jumping, slime, JAR, 2)).toBe(false)
	end)
end)

-- The point 1 stud outside base `shape`'s floor-f wall, straight out from (x, z).
local function outsideOf(shape: BaseShapes.Shape, f: number, x: number, z: number): (number, number)
	local g = shape.guard
	local wall = g.radii[f] + g.wall + 1
	local norm = if g.square then math.max(math.abs(x), math.abs(z)) else math.sqrt(x * x + z * z)
	return x * wall / norm, z * wall / norm
end

describe("every base: the glass is not enough, the inside rule is", function()
	for _, base in Config.PLOT_BASES do
		local id = base.id
		it(`{id}: spots just outside the glass reach its pads, and the rule refuses every one`, function()
			local shape = BaseShapes.get(id)
			local reachable = 0
			for j = 1, Config.PADS_MAX do
				local f = WorldLayout.padFloor(j)
				local x, z = shape.padOffset(j)
				local slime = { x, WorldLayout.floorTop(f) + SLIME, z }
				local ox, oz = outsideOf(shape, f, x, z)
				local outside = { ox, WorldLayout.floorTop(f) + CHARACTER, oz }
				local dx, dy, dz = ox - x, outside[2] - slime[2], oz - z
				if math.sqrt(dx * dx + dy * dy + dz * dz) <= Config.STEAL_REACH then
					reachable += 1
				end
				expect(JarInside.canReach(outside, slime, shape.guard, FLOORS)).toBe(false)
				-- Standing next to the pad, inside, still works.
				local inside = { x * 0.85, WorldLayout.floorTop(f) + CHARACTER, z * 0.85 }
				expect(JarInside.canReach(inside, slime, shape.guard, FLOORS)).toBe(true)
			end
			-- Why the rule exists: distance alone lets a thief outside steal from this base.
			expect(reachable > 0).toBe(true)
		end)
	end
end)

-- A dome starts below the next storey's height: a player standing on it used to count as inside the base, and a
-- locked base reported them as an intruder again on every step (and kicked them).
describe("every base: standing on the roof is not being inside", function()
	it("jar: a player on the dome is outside, one jumping under it is inside", function()
		local jar = BaseShapes.get("jar").guard
		for top = 1, FLOORS do
			local profile = WorldLayout.topDomeProfile(top)
			local floor = WorldLayout.floorTop(top)
			for k = 1, #profile - 1 do
				local a, b = profile[k], profile[k + 1]
				local r, h = (a[1] + b[1]) / 2, (a[2] + b[2]) / 2 -- the middle of dome row k
				for _, was in { false, true } do
					expect(JarInside.inside(0, floor + h + CHARACTER, r, jar, top, was)).toBe(false)
					expect(JarInside.inside(r * 0.7, floor + CHARACTER + 7.5, 0, jar, top, was)).toBe(true)
				end
			end
		end
	end)
	-- the generated bases' roof pieces, read from their data (not from the guard's own roof sampling)
	local DATA = {
		factory = require("../src/visuals/shared/BaseShapeData/Factory"),
		pagoda = require("../src/visuals/shared/BaseShapeData/Pagoda"),
		carousel = require("../src/visuals/shared/BaseShapeData/Carousel"),
		rocket = require("../src/visuals/shared/BaseShapeData/Rocket"),
		treehouse = require("../src/visuals/shared/BaseShapeData/Treehouse"),
		lighthouse = require("../src/visuals/shared/BaseShapeData/Lighthouse"),
		snowglobe = require("../src/visuals/shared/BaseShapeData/Snowglobe"),
	} :: { [string]: any }
	for _, base in Config.PLOT_BASES do
		local id = base.id
		if id ~= "jar" then
			it(`{id}: a player standing on any roof piece is outside`, function()
				local data = DATA[id]
				expect(data ~= nil).toBe(true)
				local guard = BaseShapes.get(id).guard
				local tested = 0
				for top = 1, math.min(FLOORS, #guard.radii) do
					local floor = WorldLayout.floorTop(top)
					expect(JarInside.inside(0, floor + CHARACTER, 0, guard, top, false)).toBe(true)
					for _, p in data.parts do
						local roof = p.floor == top
							and p.show == "top"
							and p.collide
							and (p.role == "roof" or p.role == "dome")
						if roof then
							-- the middle of a thin roof piece, a standing root above it
							local x, y, z = p.pos[1], p.pos[2] + p.size[2] / 2 + CHARACTER, p.pos[3]
							tested += 1
							expect(JarInside.inside(x, y, z, guard, top, true)).toBe(false)
						end
					end
				end
				expect(tested > 0).toBe(true)
			end)
		end
	end
end)
