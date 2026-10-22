--!strict
-- The goo jar tower's drop tube (CONTRACT.md §5.3): every upper jar has a DropHatch on the back with a tube down to
-- the splash pool outside the moat. Only the plot's owner may take it, and not while carrying a slime.
local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function setup()
	local world = ServerFixtures.world()
	local session = ServerFixtures.join(world, 1, { Fixtures.slime("a") })
	local drops: { { number } } = {}
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
	}
	return world, session, ctx, drops
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
	it("gives every upper jar one hatch and a ghost tube; floor 2 also has the splash pool", function()
		for f = 2, #Config.BASE_FLOORS do
			local parts = WorldLayout.floor(1, f)[1].children
			expect(named(parts, "DropHatch") ~= nil).toBe(true)
			for _, name in { "TubeArm", "Tube" } do
				local node = named(parts, name)
				expect(node ~= nil).toBe(true)
				expect(node.canCollide).toBe(false)
				expect(node.canQuery).toBe(false)
			end
			expect(named(parts, "SplashPool") ~= nil).toBe(f == 2)
		end
	end)
	it("runs the tube outside jar 1's glass and inside the plot, and lands in the goo moat", function()
		local tube = WorldLayout.DROP_TUBE
		expect(tube.radius - tube.width / 2 > WorldLayout.jarRadius(1) + WorldLayout.JAR_WALL).toBe(true)
		expect(tube.radius + tube.width / 2 < WorldLayout.PLOT_SIZE / 2).toBe(true)
		local land = WorldLayout.dropLanding()
		local r = math.sqrt(land[1] ^ 2 + land[3] ^ 2)
		expect(r > WorldLayout.MOAT.inner and r < WorldLayout.MOAT.outer).toBe(true)
	end)
	it("keeps the landing clear of the lock button", function()
		local land = WorldLayout.dropLanding()
		local function far(x: number, z: number, clear: number)
			return math.abs(land[1] - x) > clear or math.abs(land[3] - z) > clear
		end
		expect(far(WorldLayout.LOCK_BUTTON_SPOT[1], WorldLayout.LOCK_BUTTON_SPOT[2], 2.5 + 2)).toBe(true)
	end)
end)
