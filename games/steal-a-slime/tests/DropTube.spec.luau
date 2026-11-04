--!strict
-- The goo jar tower's drop tube (CONTRACT.md §5.3): every upper jar has a DropHatch on the back with a tube down to
-- the splash pool outside the moat. Only the plot's owner may take it, from inside the top jar, and not while carrying
-- a slime.
local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local LayoutMath = require("../src/visuals/shared/LayoutMath")
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
	local function pieces(nodes: { any }): { any }
		local out = {}
		for _, n in nodes do
			if string.match(n.name, "^Tube_%d+$") then
				table.insert(out, n)
			end
		end
		return out
	end
	-- Plot 1's world point for a tube line point { r, height } (WorldLayout's plot frame: centre, then yaw).
	local function onPlot(p: { number }): { number }
		local centre, yaw = WorldLayout.plotCentre(1)
		local x, z = WorldLayout.polar(p[1], WorldLayout.DROP_ANGLE)
		return LayoutMath.add(centre, LayoutMath.apply(LayoutMath.orientation({ 0, yaw, 0 }), { x, p[2], z }))
	end
	-- Distance from point q to the axis (a segment) of cylinder node n.
	local function offAxis(n: any, q: { number }): number
		local axis = LayoutMath.apply(LayoutMath.orientation(n.rot), { 1, 0, 0 })
		local half = n.size[1] / 2
		local d = { q[1] - n.pos[1], q[2] - n.pos[2], q[3] - n.pos[3] }
		local t = math.clamp(d[1] * axis[1] + d[2] * axis[2] + d[3] * axis[3], -half, half)
		return math.sqrt((d[1] - axis[1] * t) ^ 2 + (d[2] - axis[2] * t) ^ 2 + (d[3] - axis[3] * t) ^ 2)
	end
	it("gives every upper jar one hatch and a tube no ray hits; floor 2 also has the splash pool", function()
		for f = 2, #Config.BASE_FLOORS do
			local parts = WorldLayout.floor(1, f)[1].children
			expect(named(parts, "DropHatch") ~= nil).toBe(true)
			expect(named(parts, "TubeArm").canQuery).toBe(false)
			expect(#pieces(parts) > 0).toBe(true)
			for _, node in pieces(parts) do
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
	it("runs the tube outside every jar's glass and inside the plot, and lands in the goo moat", function()
		local tube = WorldLayout.DROP_TUBE
		for f = 2, #Config.BASE_FLOORS do
			for _, p in WorldLayout.dropTubeStretch(f) do
				-- clear of the glass of the jar beside it; the last 4 studs under a jar's floor are the bend over the
				-- shoulder of the jar below, already beside the jar above
				local up = p[2] - WorldLayout.PLOT_FLOOR_TOP + 4
				local jar = math.clamp(math.floor(up / WorldLayout.FLOOR_HEIGHT) + 1, 1, f)
				expect(p[1] - tube.width / 2 > WorldLayout.jarRadius(jar) + WorldLayout.JAR_WALL).toBe(true)
				expect(p[1] + tube.width / 2 < WorldLayout.PLOT_SIZE / 2).toBe(true)
			end
		end
		local land = WorldLayout.dropLanding()
		local r = math.sqrt(land[1] ^ 2 + land[3] ^ 2)
		expect(r > WorldLayout.MOAT.inner and r < WorldLayout.MOAT.outer).toBe(true)
	end)
	it(
		"splits the tube's line into one stretch per floor, from each hatch down to the mouth, on the mesh's line",
		function()
			local top = #Config.BASE_FLOORS
			local path = WorldLayout.dropTubePath(top)
			local mouth = path[#path]
			for f = 2, top do
				local stretch = WorldLayout.dropTubeStretch(f)
				expect(#stretch >= 2).toBe(true)
				expect(stretch[1][2]).toBe(WorldLayout.floorTop(f) + 2)
				for k = 2, #stretch do
					expect(stretch[k][2] < stretch[k - 1][2]).toBe(true)
				end
				local last = stretch[#stretch]
				if f == 2 then
					expect(last[1]).toBe(mouth[1])
					expect(last[2]).toBe(mouth[2])
				else
					expect(last[2]).toBe(WorldLayout.dropTubeStretch(f - 1)[1][2])
				end
			end
			-- below the elbow every tower height has the same line, so a floor's stretch holds as jars are added
			-- (points 1-3 are the lower tower's elbow; from point 4 on its line is the tail of the tallest tower's)
			for v = 2, top - 1 do
				local lower = WorldLayout.dropTubePath(v)
				local shift = #path - #lower
				for k = 4, #lower do
					local p, q = lower[k], path[k + shift]
					expect(math.abs(p[1] - q[1]) < 1e-9 and math.abs(p[2] - q[2]) < 1e-9).toBe(true)
				end
			end
		end
	)
	it(
		"makes the tube solid along its line (nobody stands inside it) and keeps the arm out of reach as decor",
		function()
			for f = 2, #Config.BASE_FLOORS do
				local parts = WorldLayout.floor(1, f)[1].children
				expect(named(parts, "TubeArm").canCollide).toBe(false)
				local solid = pieces(parts)
				local stretch = WorldLayout.dropTubeStretch(f)
				expect(#solid).toBe(#stretch - 1)
				for k, node in solid do
					expect(node.canCollide).toBe(true)
					expect(node.shape).toBe("Cylinder")
					expect(node.size[2]).toBe(WorldLayout.DROP_TUBE.width)
					-- both ends of its stretch lie on the piece's axis
					expect(offAxis(node, onPlot(stretch[k])) < 1e-6).toBe(true)
					expect(offAxis(node, onPlot(stretch[k + 1])) < 1e-6).toBe(true)
				end
				-- and so does every point in between: no point of the line is off the solid tube
				for k = 1, #stretch - 1 do
					for t = 0, 1, 0.1 do
						local a, b = stretch[k], stretch[k + 1]
						local q = onPlot({ a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t })
						local best = math.huge
						for _, node in solid do
							best = math.min(best, offAxis(node, q))
						end
						expect(best < 1e-6).toBe(true)
					end
				end
			end
		end
	)
	it("lands the drop on the splash pool beside the tube's mouth, not inside it", function()
		local tube = WorldLayout.DROP_TUBE
		local land, pool = WorldLayout.dropLanding(), WorldLayout.dropPool()
		local function flat(x: number, z: number): number
			return math.sqrt((land[1] - x) ^ 2 + (land[3] - z) ^ 2)
		end
		-- a character is about 2 wide: its root lands at least half a body clear of the solid tube at any height
		for _, p in WorldLayout.dropTubeStretch(2) do
			local x, z = WorldLayout.polar(p[1], WorldLayout.DROP_ANGLE)
			expect(flat(x, z) >= tube.width / 2 + 1 - 1e-9).toBe(true)
		end
		-- still on the pool (6 across), whose middle is under the tube's mouth
		expect(flat(pool[1], pool[3]) < 3).toBe(true)
		local mouth = WorldLayout.dropTubeStretch(2)
		local mx, mz = WorldLayout.polar(mouth[#mouth][1], WorldLayout.DROP_ANGLE)
		expect(math.sqrt((pool[1] - mx) ^ 2 + (pool[3] - mz) ^ 2) < 1e-6).toBe(true)
	end)
	it("keeps the landing clear of the lock button", function()
		local land = WorldLayout.dropLanding()
		local function far(x: number, z: number, clear: number)
			return math.abs(land[1] - x) > clear or math.abs(land[3] - z) > clear
		end
		expect(far(WorldLayout.LOCK_BUTTON_SPOT[1], WorldLayout.LOCK_BUTTON_SPOT[2], 2.5 + 2)).toBe(true)
	end)
end)
