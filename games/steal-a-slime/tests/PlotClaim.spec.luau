--!strict
-- ClaimPrompt on the FREE PLOT stand (CONTRACT.md §9.1) and State.lockStartedAt (§9.3).
local Fixtures = require("./Fixtures")
local PlotClaim = require("../src/server/PlotClaim")
local ServerFixtures = require("./ServerFixtures")
local Sessions = require("../src/server/Sessions")
local Snapshot = require("../src/server/Snapshot")
local StealService = require("../src/server/StealService")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

describe("PlotClaim.describe", function()
	it("is enabled only on a free plot, with the auto-assign text", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		local owned = PlotClaim.describe(world, s.plotIndex)
		expect(owned.enabled).toBe(false)
		local free = PlotClaim.describe(world, 5)
		expect(free.enabled).toBe(true)
		expect(free.actionText).toBe("Claim plot")
		expect(free.objectText).toBe("Free plot: everyone gets one on join")
		Sessions.leave(world, 1, T0)
		expect(PlotClaim.describe(world, s.plotIndex).enabled).toBe(true)
	end)
end)

describe("PlotClaim.claim", function()
	it("sends a player who has a plot home and explains auto-assignment", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		world.outbox = {}
		local outcome, index = PlotClaim.claim(world, 1, 5)
		expect(outcome).toBe("home")
		expect(index).toBe(s.plotIndex)
		expect(world.plots[5]).toBeNil()
		expect(ServerFixtures.notifications(world, 1)[1]).toBe(
			`You already own Plot {s.plotIndex}: every player gets one when they join. Taking you there!`
		)
	end)
	it("does not teleport a carrying player", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		s.carry = {} :: any
		world.outbox = {}
		local outcome = PlotClaim.claim(world, 1, 5)
		expect(outcome).toBe("carrying")
		expect(ServerFixtures.notifications(world, 1)[1]).toBe(
			`You're carrying a slime: walk it home to Plot {s.plotIndex}`
		)
	end)
	it("reserves the plot for a player still loading; join honours it", function()
		local world = ServerFixtures.world()
		expect((PlotClaim.claim(world, 9, 6))).toBe("reserved")
		expect(ServerFixtures.notifications(world, 9)[1]).toBe("Plot 6 is yours once your data loads")
		-- Another joiner skips the reserved plot, another loader can't take it.
		local other = ServerFixtures.join(world, 2)
		expect(other.plotIndex).toBe(1)
		expect((PlotClaim.claim(world, 3, 6))).toBe("taken")
		local s = ServerFixtures.join(world, 9)
		expect(s.plotIndex).toBe(6)
		expect(world.claims[9]).toBeNil()
	end)
	it("falls back to the lowest free plot if the reserved one got taken", function()
		local world = ServerFixtures.world()
		PlotClaim.claim(world, 9, 1)
		for userId = 1, world.plotCount do
			ServerFixtures.join(world, userId) -- plots 2..n first, then the reserved 1 (nothing else left)
		end
		expect(world.plots[2]).toBe(1)
		expect(world.plots[1]).toBe(world.plotCount)
		local session, reason = Sessions.join(world, 9, "P9", Fixtures.data(), T0)
		expect(session).toBeNil()
		expect(reason).toBe("server is full")
	end)
	it("says taken for an owned plot and forgets a claim on leave", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1)
		expect((PlotClaim.claim(world, 9, 1))).toBe("taken")
		PlotClaim.claim(world, 9, 4)
		Sessions.leave(world, 9, T0)
		expect(world.claims[9]).toBeNil()
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
