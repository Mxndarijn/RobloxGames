--!strict
-- C6 (v30): no "claim free plot" option. Plots are assigned automatically on join (and on
-- leave / rejoin); there is no ClaimPrompt, no PlotClaim module and no claim reservation.
-- Also State.lockStartedAt (CONTRACT.md §9.3), which lived in the old PlotClaim spec.
local Config = require("../src/shared/Config")
local Constants = require("../src/shared/Constants")
local ServerFixtures = require("./ServerFixtures")
local Sessions = require("../src/server/Sessions")
local Snapshot = require("../src/server/Snapshot")
local StealService = require("../src/server/StealService")
local TestRunner = require("./TestRunner")
local World = require("../src/server/World")
local fs = require("@lune/fs")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

describe("plots auto-assign on join (no claim)", function()
	it("gives each joining player the lowest free plot with no prompt", function()
		local world = ServerFixtures.world()
		for userId = 1, Config.PLOT_COUNT do
			expect(ServerFixtures.join(world, userId).plotIndex).toBe(userId)
		end
		expect(World.freePlot(world)).toBeNil()
	end)
	it("frees the plot on leave and hands it to the next joiner (rejoin gets a plot again)", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1)
		ServerFixtures.join(world, 2)
		ServerFixtures.join(world, 3)
		Sessions.leave(world, 2, T0)
		expect(world.plots[2]).toBeNil()
		expect(World.freePlot(world)).toBe(2)
		expect(ServerFixtures.join(world, 2).plotIndex).toBe(2)
		Sessions.leave(world, 1, T0)
		expect(ServerFixtures.join(world, 9).plotIndex).toBe(1)
	end)
	it("has no claim reservation state on the world", function()
		local world = ServerFixtures.world() :: any
		expect(world.claims).toBeNil()
	end)
	it("has no PlotClaim module and no CLAIM_PROMPT_NAME constant", function()
		expect(fs.isFile("src/server/PlotClaim.luau")).toBe(false)
		expect((Constants :: any).CLAIM_PROMPT_NAME).toBeNil()
	end)
end)

describe("State.lockStartedAt", function()
	it("starts at join, resets on a new lock, stays on an extension", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, nil, 1e6)
		expect(Snapshot.build(world, s, T0).lockStartedAt).toBe(T0)
		expect((StealService.buyLock(world, s, T0 + 5))).toBe(true) -- extends the join lock
		expect(s.lockStartedAt).toBe(T0)
		local later = s.lockUntil + 10
		expect((StealService.buyLock(world, s, later))).toBe(true)
		expect(s.lockStartedAt).toBe(later)
		expect(Snapshot.build(world, s, later).lockStartedAt).toBe(later)
	end)
end)
