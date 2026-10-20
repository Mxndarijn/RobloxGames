--!strict
-- The goo jar tower's drop tube (CONTRACT.md §5.3): every upper jar has a DropHatch on the back with a tube down to
-- the splash pool outside the moat. Anyone may take it except a player carrying a slime.
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
	it("drops a player who carries nothing down their own or anyone's tube", function()
		local world, _, ctx, drops = setup()
		expect(Actions.useDropTube(world, 1, 1, ctx).ok).toBe(true)
		expect(Actions.useDropTube(world, 1, 3, ctx).ok).toBe(true)
		expect(#drops).toBe(2)
		expect(drops[2][2]).toBe(3)
	end)
	it("refuses a player carrying a slime, tells them to walk out, and never moves them", function()
		local world, session, ctx, drops = setup()
		session.carry = { slimeId = "x", kind = "wild", slime = Fixtures.slime("x") } :: any
		local res = Actions.useDropTube(world, 1, 1, ctx)
		expect(res.ok).toBe(false)
		expect(#drops).toBe(0)
		local said = notices(world, 1)
		expect(#said).toBe(1)
		expect(said[1].kind).toBe("bad")
	end)
	it("refuses with no world to move the character in, and for a player who is not loaded", function()
		local world, _, ctx = setup()
		ctx.dropDown = nil
		expect(Actions.useDropTube(world, 1, 1, ctx).ok).toBe(false)
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
	it("runs the tube outside jar 1's glass and inside the plot, and lands outside the moat", function()
		local tube = WorldLayout.DROP_TUBE
		expect(tube.radius - tube.width / 2 > WorldLayout.jarRadius(1) + WorldLayout.JAR_WALL).toBe(true)
		expect(tube.radius + tube.width / 2 < WorldLayout.PLOT_SIZE / 2).toBe(true)
		local land = WorldLayout.dropLanding()
		expect(math.sqrt(land[1] ^ 2 + land[3] ^ 2) > WorldLayout.MOAT.outer).toBe(true)
	end)
	it("keeps the landing clear of the trophy stands, the lock button and the rebirth pillars", function()
		local land = WorldLayout.dropLanding()
		local function far(x: number, z: number, clear: number)
			return math.abs(land[1] - x) > clear or math.abs(land[3] - z) > clear
		end
		for _, spot in WorldLayout.TROPHY_SPOTS do
			expect(far(spot[1], spot[2], 4.5 + 2)).toBe(true)
		end
		expect(far(WorldLayout.LOCK_BUTTON_SPOT[1], WorldLayout.LOCK_BUTTON_SPOT[2], 2.5 + 2)).toBe(true)
		local h = WorldLayout.PLOT_SIZE / 2 - 1
		for _, c in { { -h, h }, { h, h } } do
			expect(far(c[1], c[2], 1.1 + 2)).toBe(true)
		end
	end)
end)
