--!strict
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local PlayerData = require("../src/shared/PlayerData")
local ServerFixtures = require("./ServerFixtures")
local SlimeGuard = require("../src/server/SlimeGuard")
local StealService = require("../src/server/StealService")
local TestRunner = require("./TestRunner")
local World = require("../src/server/World")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local G = Config.SLIME_GUARD

-- Victim 1 owns "gem" on an unlocked plot; thief 2 is ready to steal it. Guard in `mode`.
local function setup(mode: "watch" | "enforce")
	local world = ServerFixtures.world()
	world.guardMode = mode
	local victim = ServerFixtures.join(world, 1, { Fixtures.slime("gem", 4) })
	local thief = ServerFixtures.join(world, 2)
	ServerFixtures.unlock(victim)
	ServerFixtures.unlock(thief)
	return world, victim, thief
end

-- Feeds the thief walking from x0 to x1 at `speed`, every 0.1 s from `t0`; returns the time of the last sample.
local function walk(world: World.World, s: World.Session, t0: number, x0: number, x1: number, speed: number): number
	local seconds = math.abs(x1 - x0) / speed
	local steps = math.max(1, math.ceil(seconds * 10))
	for i = 0, steps do
		local f = i / steps
		SlimeGuard.observe(world, s, x0 + (x1 - x0) * f, 5, 0, t0 + seconds * f, Carry.targetWalkSpeed(s, t0))
	end
	return t0 + seconds
end

describe("SlimeGuard carry watch", function()
	it("sends a stolen slime home when the thief teleports (enforce)", function()
		local world, victim, thief = setup("enforce")
		local t = walk(world, thief, T0, 0, 140, 16)
		expect((Carry.grab(world, 2, "gem", 1, t + 0.1))).toBe(true)
		SlimeGuard.observe(world, thief, 140, 5, 0, t + 0.2, Carry.targetWalkSpeed(thief, t))
		local report = SlimeGuard.observe(world, thief, 0, 5, 0, t + 0.3, Carry.targetWalkSpeed(thief, t))
		expect(report and report.kind).toBe("teleport")
		expect(thief.carry).toBeNil()
		expect(PlayerData.findSlime(victim.data, "gem") ~= nil).toBe(true)
	end)

	it("only logs in watch mode", function()
		local world, _, thief = setup("watch")
		local t = walk(world, thief, T0, 0, 140, 16)
		Carry.grab(world, 2, "gem", 1, t + 0.1)
		SlimeGuard.observe(world, thief, 140, 5, 0, t + 0.2, 10)
		local report = SlimeGuard.observe(world, thief, 0, 5, 0, t + 0.3, 10)
		expect(report and report.enforced).toBe(false)
		expect(thief.carry ~= nil).toBe(true)
	end)

	it("never flags an honest steal", function()
		local world, victim, thief = setup("enforce")
		local t = walk(world, thief, T0, 0, 140, 16)
		expect((Carry.grab(world, 2, "gem", 1, t + 0.1))).toBe(true)
		local speed = Carry.targetWalkSpeed(thief, t)
		t = walk(world, thief, t + 0.2, 140, 0, speed)
		expect((SlimeGuard.depositCheck(world, thief, 0, 0, t))).toBe(true)
		expect((Carry.deposit(world, 2, t))).toBe(true)
		expect(PlayerData.findSlime(thief.data, "gem") ~= nil).toBe(true)
		expect(SlimeGuard.entry(world, 2, t).suspicion.points).toBe(0)
		expect(#world.stealLedger).toBe(1)
		expect(StealService.isLocked(victim, t + G.BREATHER_SECONDS - 1)).toBe(true)
	end)
end)

describe("SlimeGuard deposit check", function()
	it("refuses a stolen slime that got home too fast and sends it back (enforce)", function()
		local world, victim, thief = setup("enforce")
		SlimeGuard.observe(world, thief, 140, 5, 0, T0, 16)
		Carry.grab(world, 2, "gem", 1, T0 + 0.1)
		SlimeGuard.observe(world, thief, 140, 5, 0, T0 + 0.2, 10)
		local ok, report = SlimeGuard.depositCheck(world, thief, 0, 0, T0 + 1)
		expect(ok).toBe(false)
		expect(report and report.kind).toBe("earlyDeposit")
		expect(thief.carry).toBeNil()
		expect(PlayerData.findSlime(victim.data, "gem") ~= nil).toBe(true)
	end)
end)

describe("SlimeGuard steal gate", function()
	it("refuses a steal right after a teleport and while paused (enforce)", function()
		local world, _, thief = setup("enforce")
		SlimeGuard.observe(world, thief, 0, 5, 0, T0, 16)
		SlimeGuard.observe(world, thief, 140, 5, 0, T0 + 0.1, 16) -- teleport: 3 points, paused
		expect(select(2, Carry.grab(world, 2, "gem", 1, T0 + 1))).toBe("stealing is paused for a moment")
	end)

	it("says too far away within the teleport cooldown", function()
		local world = setup("enforce")
		local e = SlimeGuard.entry(world, 2, T0)
		e.track.teleportAt = T0
		expect(select(2, Carry.grab(world, 2, "gem", 1, T0 + 1))).toBe("too far away")
		expect((Carry.grab(world, 2, "gem", 1, T0 + G.TELEPORT_COOLDOWN + 0.1))).toBe(true)
	end)

	it("does not block steals in watch mode", function()
		local world, _, thief = setup("watch")
		SlimeGuard.observe(world, thief, 0, 5, 0, T0, 16)
		SlimeGuard.observe(world, thief, 140, 5, 0, T0 + 0.1, 16)
		expect((Carry.grab(world, 2, "gem", 1, T0 + 1))).toBe(true)
	end)
end)

describe("SlimeGuard kick and undo", function()
	it("gives a cheater's recent steals back on a kick (enforce)", function()
		local world, victim, thief = setup("enforce")
		local t = walk(world, thief, T0, 0, 140, 16)
		Carry.grab(world, 2, "gem", 1, t + 0.1)
		t = walk(world, thief, t + 0.2, 140, 0, Carry.targetWalkSpeed(thief, t))
		expect((Carry.deposit(world, 2, t))).toBe(true)
		local report = SlimeGuard.report(world, thief, "teleport", "x", t + 1)
		SlimeGuard.report(world, thief, "teleport", "x", t + 2)
		report = SlimeGuard.report(world, thief, "teleport", "x", t + 3)
		expect(report.level).toBe("kick")
		expect(PlayerData.findSlime(thief.data, "gem")).toBeNil()
		expect(PlayerData.findSlime(victim.data, "gem") ~= nil).toBe(true)
	end)
end)

describe("SlimeGuard locked-base intruders", function()
	it("flags a player who got into a locked plot after the lock started, once per visit", function()
		local world, victim, thief = setup("watch")
		victim.lockStartedAt = T0 + 10
		victim.lockUntil = T0 + 100
		expect(SlimeGuard.trackPlot(world, thief, victim.plotIndex, T0 + 20)).toBe(victim.plotIndex)
		expect(SlimeGuard.trackPlot(world, thief, victim.plotIndex, T0 + 20.1)).toBeNil() -- still inside: not again
		expect(SlimeGuard.trackPlot(world, thief, nil, T0 + 21)).toBeNil()
		expect(SlimeGuard.trackPlot(world, thief, victim.plotIndex, T0 + 22)).toBe(victim.plotIndex)
	end)

	it("leaves a player trapped who was inside before the lock", function()
		local world, victim, thief = setup("watch")
		expect(SlimeGuard.trackPlot(world, thief, victim.plotIndex, T0 + 5)).toBeNil() -- unlocked: just tracked
		victim.lockStartedAt = T0 + 10
		victim.lockUntil = T0 + 100
		expect(SlimeGuard.trackPlot(world, thief, victim.plotIndex, T0 + 20)).toBeNil()
	end)

	it("sends a stolen slime home and adds points for an intruder, none when a launch put them there", function()
		local world, _, thief = setup("watch")
		local t = walk(world, thief, T0, 0, 140, 16)
		Carry.grab(world, 2, "gem", 1, t + 0.1)
		local report = SlimeGuard.intruded(world, thief, 1, t + 1, false)
		expect(thief.carry).toBeNil()
		expect(report and report.kind).toBe("lockedEntry")
		expect(SlimeGuard.intruded(world, thief, 1, t + 2, true)).toBeNil()
	end)
end)

describe("SlimeGuard off", function()
	it("does nothing with the flag off", function()
		local world, _, thief = setup("watch")
		world.guardMode = "off"
		SlimeGuard.observe(world, thief, 0, 5, 0, T0, 16)
		expect(SlimeGuard.observe(world, thief, 300, 5, 0, T0 + 0.1, 16)).toBeNil()
		expect(world.guard[2]).toBeNil()
	end)
end)
