--!strict
-- The goo jar tower's drop tube (CONTRACT.md §5.3): every upper jar has a DropHatch on the back with a tube down to
-- the splash pool outside the moat. Only the plot's owner may take it, from inside the top jar, and not while carrying
-- a slime.
local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

-- An owner with jar 2 standing (one full floor of pads), stood in jar `f` at radius `r` (plot-local, the drop
-- hatch's side), root 3 studs over that floor.
local TOP = 2
local function at(f: number, r: number): { number }
	local a = math.rad(WorldLayout.DROP_ANGLE)
	return { r * math.cos(a), WorldLayout.floorTop(f) + 3, r * math.sin(a) }
end

local function setup()
	local world = ServerFixtures.world()
	local session = ServerFixtures.join(world, 1, { Fixtures.slime("a") })
	session.data.padsUnlocked = Config.PADS_PER_FLOOR * (TOP - 1)
	local drops: { { number } } = {}
	local stand: { number }? = at(TOP, WorldLayout.jarRadius(TOP) - 3)
	local ctx: Actions.Context = {
		distanceBetween = function()
			return 2
		end,
		positionOf = function()
			return nil
		end,
		dropDown = function(userId: number, plotIndex: number): boolean
			table.insert(drops, { userId, plotIndex })
			return true
		end,
		plotPointOf = function(): { number }?
			return stand
		end,
	}
	local function standAt(p: { number }?)
		stand = p
	end
	return world, session, ctx, drops, standAt
end

local function notices(world: any, userId: number): { any }
	local out = {}
	for _, event in world.outbox do
		if event.type == "Notify" and event.userId == userId then
			table.insert(out, event)
		end
	end
	return out
end

describe("Actions.useDropTube", function()
	it("drops the owner down their own tube, and refuses anyone else's with a toast", function()
		local world, session, ctx, drops = setup()
		local own = session.plotIndex
		expect(Actions.useDropTube(world, 1, own, ctx).ok).toBe(true)
		expect(#drops).toBe(1)
		expect(drops[1][2]).toBe(own)
		local other = own % Config.PLOT_COUNT + 1
		expect(Actions.useDropTube(world, 1, other, ctx).ok).toBe(false)
		expect(#drops).toBe(1)
		local said = notices(world, 1)
		expect(#said).toBe(1)
		expect(said[1].kind).toBe("bad")
	end)
	it("refuses a player carrying a slime, tells them to walk out, and never moves them", function()
		local world, session, ctx, drops = setup()
		session.carry = { slimeId = "x", kind = "wild", slime = Fixtures.slime("x") } :: any
		local res = Actions.useDropTube(world, 1, session.plotIndex, ctx)
		expect(res.ok).toBe(false)
		expect(#drops).toBe(0)
		local said = notices(world, 1)
		expect(#said).toBe(1)
		expect(said[1].kind).toBe("bad")
	end)
	it("refuses an owner outside the top jar's glass, on the deck ledge over the jar below, with a toast", function()
		local world, session, ctx, drops, standAt = setup()
		local ledge = (WorldLayout.jarRadius(TOP) + WorldLayout.JAR_WALL + WorldLayout.jarRadius(TOP - 1)) / 2
		expect(ledge > WorldLayout.jarRadius(TOP) + WorldLayout.JAR_WALL).toBe(true)
		standAt(at(TOP, ledge))
		expect(Actions.useDropTube(world, 1, session.plotIndex, ctx).ok).toBe(false)
		expect(#drops).toBe(0)
		local said = notices(world, 1)
		expect(#said).toBe(1)
		expect(said[1].kind).toBe("bad")
	end)
	it("refuses an owner in a lower jar, under the top jar's hatch", function()
		local world, session, ctx, drops, standAt = setup()
		standAt(at(TOP - 1, WorldLayout.jarRadius(TOP) - 3))
		expect(Actions.useDropTube(world, 1, session.plotIndex, ctx).ok).toBe(false)
		expect(#drops).toBe(0)
	end)
	it("refuses with only jar 1 standing, and with no character to place", function()
		local world, session, ctx, drops, standAt = setup()
		standAt(nil)
		expect(Actions.useDropTube(world, 1, session.plotIndex, ctx).ok).toBe(false)
		standAt(at(1, 10))
		session.data.padsUnlocked = 0
		expect(Actions.useDropTube(world, 1, session.plotIndex, ctx).ok).toBe(false)
		expect(#drops).toBe(0)
	end)
	it("refuses with no world to move the character in, and for a player who is not loaded", function()
		local world, session, ctx = setup()
		ctx.dropDown = nil
		expect(Actions.useDropTube(world, 1, session.plotIndex, ctx).ok).toBe(false)
		expect(Actions.useDropTube(world, 99, 1, ctx).ok).toBe(false)
	end)
end)

describe("drop tube geometry", function()
	local function named(nodes: { any }, name: string): any
		for _, n in nodes do
			if n.name == name then
				return n
			end
		end
		return nil
	end
	it("gives every upper jar one hatch and a tube no ray hits; floor 2 also has the splash pool", function()
		for f = 2, #Config.BASE_FLOORS do
			local parts = WorldLayout.floor(1, f)[1].children
			expect(named(parts, "DropHatch") ~= nil).toBe(true)
			for _, name in { "TubeArm", "Tube" } do
				local node = named(parts, name)
				expect(node ~= nil).toBe(true)
				expect(node.canQuery).toBe(false)
			end
			expect(named(parts, "SplashPool") ~= nil).toBe(f == 2)
		end
	end)
	it(
		"shields the hatch from outside the glass: queryable, invisible, never collides, either side of the hatch",
		function()
			for f = 2, #Config.BASE_FLOORS do
				local shields = 0
				for _, node in WorldLayout.floor(1, f)[1].children do
					if string.match(node.name, "^DropShield_%d$") then
						shields += 1
						expect(node.canQuery ~= false).toBe(true)
						expect(node.canCollide).toBe(false)
						expect(node.transparency).toBe(1)
					end
				end
				expect(shields).toBe(2)
			end
			local angles = WorldLayout.dropShieldAngles()
			expect(angles[1] < WorldLayout.DROP_ANGLE and WorldLayout.DROP_ANGLE < angles[2]).toBe(true)
		end
	)
	it("runs the tube outside jar 1's glass and inside the plot, and lands in the goo moat", function()
		local tube = WorldLayout.DROP_TUBE
		expect(tube.radius - tube.width / 2 > WorldLayout.jarRadius(1) + WorldLayout.JAR_WALL).toBe(true)
		expect(tube.radius + tube.width / 2 < WorldLayout.PLOT_SIZE / 2).toBe(true)
		local land = WorldLayout.dropLanding()
		local r = math.sqrt(land[1] ^ 2 + land[3] ^ 2)
		expect(r > WorldLayout.MOAT.inner and r < WorldLayout.MOAT.outer).toBe(true)
	end)
	it("makes the upright tube solid (nobody stands inside it) and keeps the arm out of reach as decor", function()
		for f = 2, #Config.BASE_FLOORS do
			local tube, arm = nil, nil
			for _, node in WorldLayout.floor(1, f)[1].children do
				if node.name == "Tube" then
					tube = node
				elseif node.name == "TubeArm" then
					arm = node
				end
			end
			expect(tube ~= nil and arm ~= nil).toBe(true)
			expect(tube.canCollide).toBe(true)
			expect(arm.canCollide).toBe(false)
		end
	end)
	it("lands the drop on the splash pool beside the tube's solid foot, not inside it", function()
		local tube = WorldLayout.DROP_TUBE
		local tx, tz = WorldLayout.polar(tube.radius, WorldLayout.DROP_ANGLE)
		local land, pool = WorldLayout.dropLanding(), WorldLayout.dropPool()
		local function flat(x: number, z: number): number
			return math.sqrt((land[1] - x) ^ 2 + (land[3] - z) ^ 2)
		end
		-- a character is about 2 wide: its root lands at least half a body clear of the tube
		expect(flat(tx, tz) >= tube.width / 2 + 1).toBe(true)
		-- still on the pool (6 across), whose middle is under the tube's foot
		expect(flat(pool[1], pool[3]) < 3).toBe(true)
		expect(math.sqrt((pool[1] - tx) ^ 2 + (pool[3] - tz) ^ 2) < tube.width / 2).toBe(true)
	end)
	it("keeps the landing clear of the lock button", function()
		local land = WorldLayout.dropLanding()
		local function far(x: number, z: number, clear: number)
			return math.abs(land[1] - x) > clear or math.abs(land[3] - z) > clear
		end
		expect(far(WorldLayout.LOCK_BUTTON_SPOT[1], WorldLayout.LOCK_BUTTON_SPOT[2], 2.5 + 2)).toBe(true)
	end)
end)
