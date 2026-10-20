--!strict
-- Server <-> world integration contracts: the Player `Carrying` attribute
-- (CONTRACT.md §5.2), plot / pad lookup by PlotIndex / PadIndex (§5.3) and
-- the shared folder names that src/visuals hardcodes.
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Constants = require("../src/shared/Constants")
local Fixtures = require("./Fixtures")
local GameLoop = require("../src/server/GameLoop")
local PlotLookup = require("../src/server/PlotLookup")
local ServerFixtures = require("./ServerFixtures")
local Sessions = require("../src/server/Sessions")
local Snapshot = require("../src/server/Snapshot")
local Spawner = require("../src/server/Spawner")
local StealService = require("../src/server/StealService")
local TestRunner = require("./TestRunner")
local World = require("../src/server/World")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

local function freeWild(world: any): string
	local id = Spawner.spawnOne(world, T0)
	world.wild[id].price = 0
	return id
end

-- Victim 1 owns "gem" (unlocked plot); thief 2 is empty-handed.
local function stealSetup()
	local world = ServerFixtures.world()
	local victim = ServerFixtures.join(world, 1, { Fixtures.slime("gem", 4) })
	local thief = ServerFixtures.join(world, 2)
	ServerFixtures.unlock(victim)
	return world, victim, thief
end

describe("Carrying attribute (Carry.carryingId)", function()
	it("is nil for unknown and empty-handed players", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1)
		expect(Carry.carryingId(world, 1)).toBeNil()
		expect(Carry.carryingId(world, 99)).toBeNil()
	end)
	it("is set to the slime id on pickup (wild and stolen)", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1)
		local id = freeWild(world)
		Carry.grab(world, 1, id, 1, T0)
		expect(Carry.carryingId(world, 1)).toBe(id)

		local world2 = stealSetup()
		expect((Carry.grab(world2, 2, "gem", 1, T0))).toBe(true)
		expect(Carry.carryingId(world2, 2)).toBe("gem")
	end)
	it("clears on drop", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1)
		local id = freeWild(world)
		Carry.grab(world, 1, id, 1, T0)
		Carry.release(world, 1, T0 + 1, nil, "drop")
		expect(Carry.carryingId(world, 1)).toBeNil()
	end)
	it("clears on deposit", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1)
		local id = freeWild(world)
		Carry.grab(world, 1, id, 1, T0)
		expect((Carry.deposit(world, 1))).toBe(true)
		expect(Carry.carryingId(world, 1)).toBeNil()
	end)
	it("stays set while the plot is full (the slime stays in your arms)", function()
		local world = ServerFixtures.world()
		local slimes = {}
		for i = 1, Config.PADS_MAX do
			table.insert(slimes, Fixtures.slime(`own{i}`, 1))
		end
		ServerFixtures.join(world, 1, slimes)
		local id = freeWild(world)
		Carry.grab(world, 1, id, 1, T0)
		expect(select(2, Carry.deposit(world, 1))).toBe("plot full")
		expect(Carry.carryingId(world, 1)).toBe(id)
	end)
	it("clears when a stolen slime escapes (timeout or slap)", function()
		local world, _, thief = stealSetup()
		Carry.grab(world, 2, "gem", 1, T0)
		local carry = thief.carry
		assert(carry, "carry")
		StealService.tickEscapes(world, carry.timer.escapeAt :: number)
		expect(Carry.carryingId(world, 2)).toBeNil()

		local world2 = stealSetup()
		Carry.grab(world2, 2, "gem", 1, T0)
		local slapper = ServerFixtures.join(world2, 3)
		expect((StealService.slap(world2, slapper, 2, 1, T0 + 1))).toBe(true)
		expect(Carry.carryingId(world2, 2)).toBeNil()
	end)
	it("clears when a stolen slime wriggles free", function()
		local world, _, thief = stealSetup()
		Carry.grab(world, 2, "gem", 1, T0)
		world.rng = {
			float = function()
				return 0
			end,
		} :: any
		StealService.tickEscapes(world, T0 + 1)
		expect(thief.carry).toBeNil()
		expect(Carry.carryingId(world, 2)).toBeNil()
	end)
	it("clears on death (released as a drop)", function()
		local world = stealSetup()
		Carry.grab(world, 2, "gem", 1, T0)
		expect((Carry.release(world, 2, T0 + 2, nil, "drop"))).toBe(true)
		expect(Carry.carryingId(world, 2)).toBeNil()
	end)
	it("clears when the carrier or the owner leaves", function()
		local world = stealSetup()
		Carry.grab(world, 2, "gem", 1, T0)
		Sessions.leave(world, 2, T0 + 1)
		expect(Carry.carryingId(world, 2)).toBeNil()

		local world2 = stealSetup()
		Carry.grab(world2, 2, "gem", 1, T0)
		Sessions.leave(world2, 1, T0 + 1)
		expect(Carry.carryingId(world2, 2)).toBeNil()
	end)
end)

-- Minimal Instance stand-in: GetChildren / GetAttribute / FindFirstChild.
local function node(name: string, attributes: { [string]: any }?, children: { any }?): any
	local inst = { Name = name, attributes = attributes or {}, children = children or {} }
	function inst:GetChildren()
		return self.children
	end
	function inst:GetAttribute(key: string)
		return self.attributes[key]
	end
	function inst:FindFirstChild(childName: string)
		for _, child in self.children do
			if child.Name == childName then
				return child
			end
		end
		return nil
	end
	return inst
end

describe("PlotLookup.byIndex", function()
	it("finds plots by PlotIndex even when names don't match", function()
		local plots = node("Plots", nil, {
			node("Plot_1", { PlotIndex = 2 }),
			node("Plot_2", { PlotIndex = 1 }),
		})
		local found = PlotLookup.byIndex(plots, Constants.PLOT_INDEX_ATTRIBUTE, 1, "Plot_1")
		expect(found and found.Name).toBe("Plot_2")
	end)
	it("finds pads by PadIndex", function()
		local plot = node("Plot_1", { PlotIndex = 1 }, { node("PadA", { PadIndex = 3 }), node("Pad_3") })
		local found = PlotLookup.byIndex(plot, Constants.PAD_INDEX_ATTRIBUTE, 3, "Pad_3")
		expect(found and found.Name).toBe("PadA")
	end)
	it("falls back to the name, and handles a missing parent", function()
		local plots = node("Plots", nil, { node("Plot_4") })
		local found = PlotLookup.byIndex(plots, Constants.PLOT_INDEX_ATTRIBUTE, 4, "Plot_4")
		expect(found and found.Name).toBe("Plot_4")
		expect(PlotLookup.byIndex(plots, Constants.PLOT_INDEX_ATTRIBUTE, 5, "Plot_5")).toBeNil()
		expect(PlotLookup.byIndex(nil, Constants.PLOT_INDEX_ATTRIBUTE, 1, "Plot_1")).toBeNil()
	end)
end)

describe("WorldLayout matches the server's expectations", function()
	local layout = WorldLayout.build()
	local function child(n: any, name: string): any
		for _, c in n.children or {} do
			if c.name == name then
				return c
			end
		end
		return nil
	end

	it("uses the shared folder names", function()
		expect(WorldLayout.MAP_NAME).toBe(Constants.MAP_FOLDER)
		expect(WorldLayout.SLIMES_FOLDER).toBe(Constants.PLOT_SLIMES_FOLDER)
		expect(layout[1].name).toBe(Constants.MAP_FOLDER)
		expect(layout[2].name).toBe(Constants.PLOTS_FOLDER)
	end)
	it("has a Volcano with a Crater in the Map", function()
		local volcano = child(layout[1], "Volcano")
		expect(volcano ~= nil).toBe(true)
		expect(child(volcano, "Crater") ~= nil).toBe(true)
	end)
	it("tags Plot_1..PLOT_COUNT with PlotIndex and every pad with PadIndex", function()
		local plots = layout[2].children
		expect(#plots).toBe(Config.PLOT_COUNT)
		for i, plot in plots do
			expect(plot.attributes[Constants.PLOT_INDEX_ATTRIBUTE]).toBe(i)
			expect(child(plot, Constants.HOME_ZONE) ~= nil).toBe(true)
			expect(child(plot, Constants.PLOT_SLIMES_FOLDER) ~= nil).toBe(true)
			for j = 1, Config.PADS_MAX do
				local pad = child(plot, `Pad_{j}`)
				expect(pad and pad.attributes[Constants.PAD_INDEX_ATTRIBUTE]).toBe(j)
			end
		end
	end)
	it("has a HomeZone that is non-colliding and invisible", function()
		local zone = child(layout[2].children[1], Constants.HOME_ZONE)
		expect(zone.canCollide).toBe(false)
		expect(zone.transparency).toBe(1)
	end)
end)

-- The adapter's Heartbeat on a fake clock: GameLoop.step every 0.1 s, then
-- push State when Snapshot.due and drain the outbox (Notify).
describe("live pushes during gameplay", function()
	local function run(world: any, from: number, seconds: number, onPush: (number, any) -> (), onEvent: (any) -> ())
		local t = from
		while t < from + seconds do
			t += 0.1
			GameLoop.step(world, t)
			for _, session in world.sessions do
				if Snapshot.due(session, t) then
					onPush(t, Snapshot.build(world, session, t))
					Snapshot.pushed(session, t)
				end
			end
			for _, event in World.drain(world) do
				onEvent(event)
			end
		end
	end

	it("an earning player gets a full State at least once a second, never faster than STATE_MIN_INTERVAL", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1, { Fixtures.slime("a", 1) })
		local times = {}
		run(world, T0, 10, function(t, state)
			expect(state.plotIndex).toBe(1)
			expect(#state.slimes).toBe(1)
			table.insert(times, t)
		end, function() end)
		expect(#times >= 10).toBeTruthy()
		for i = 2, #times do
			local gap = times[i] - times[i - 1]
			expect(gap >= Config.STATE_MIN_INTERVAL - 1e-9).toBeTruthy()
			expect(gap <= 1.1 + 1e-9).toBeTruthy()
		end
	end)

	it("lock expiry pushes State and a Notify to the owner", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1)
		local pushes, notes = 0, {}
		run(world, T0 + 0.5, Config.JOIN_LOCK_SECONDS + 1, function()
			pushes += 1
		end, function(event)
			if event.type == "Notify" and event.userId == 1 then
				table.insert(notes, event.sound)
			end
		end)
		expect(pushes >= 1).toBeTruthy()
		expect(table.find(notes, "Unlock") ~= nil).toBeTruthy()
	end)
end)
