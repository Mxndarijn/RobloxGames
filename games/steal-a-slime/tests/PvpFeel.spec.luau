--!strict
-- PvP hit feel (FEATURES.PvP, CONTRACT.md §26 "Knockback feel"): launch velocity with the friction boost, the shared
-- client clamp, map-edge landing, trap hold / blaster slow values from the docs, applySlow / applyControl clamps and
-- the pure void-guard decision. All pure; flag-independent.
local Config = require("../src/shared/Config")
local PvpKnockbackRules = require("../src/shared/PvpKnockbackRules")
local PvpRules = require("../src/shared/PvpRules")
local Rescue = require("../src/server/Rescue")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local P = Config.PVP

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

describe("Knockback launch velocity", function()
	it("covers the push in KNOCKBACK_SECONDS times the friction boost, and rises the arc", function()
		local v = PvpKnockbackRules.velocity({ X = 5, Y = 2, Z = 0 }, 196.2)
		expect(near(v.X, 5 / P.KNOCKBACK_SECONDS * P.KNOCKBACK_FRICTION_BOOST)).toBe(true)
		expect(near(v.Y, math.sqrt(2 * 196.2 * 2))).toBe(true)
		expect(v.Z).toBe(0)
	end)
	it("defaults to Roblox gravity", function()
		expect(near(PvpKnockbackRules.velocity({ X = 0, Y = 2, Z = 0 }).Y, math.sqrt(2 * 196.2 * 2))).toBe(true)
	end)
	it("the strongest tier stays within the max horizontal speed (max push <= 8 studs)", function()
		expect(P.KNOCKBACK_MAX_PUSH <= 8).toBe(true)
		for _, tool in Config.PVP_TOOLS do
			if tool.line == "Knockback" then
				local _, push = PvpKnockbackRules.plan(tool, { X = 0, Y = 3, Z = 0 }, { X = 3, Y = 3, Z = 4 })
				local v = PvpKnockbackRules.velocity(push)
				expect(math.sqrt(v.X * v.X + v.Z * v.Z) <= PvpKnockbackRules.maxHorizontalSpeed() + 1e-6).toBe(true)
			end
		end
	end)
	it("the friction-boosted overshoot stays inside the map margin", function()
		local worst = P.KNOCKBACK_MAX_PUSH * (P.KNOCKBACK_FRICTION_BOOST - 1)
		expect(worst < P.KNOCKBACK_BOUNDS_MARGIN).toBe(true)
	end)
	it("a push at the map edge is clamped to the bounds minus the margin", function()
		local tool = PvpRules.tool("KnockGlove5") :: any
		local edge = P.MAP_BOUNDS.maxX - 1
		local landing, push = PvpKnockbackRules.plan(tool, { X = edge - 3, Y = 3, Z = 0 }, { X = edge, Y = 3, Z = 0 })
		expect(landing.X <= P.MAP_BOUNDS.maxX - P.KNOCKBACK_BOUNDS_MARGIN + 1e-9).toBe(true)
		expect(push.Y <= P.KNOCKBACK_ARC_HEIGHT).toBe(true)
	end)
end)

describe("Knockback client clamp", function()
	it("passes a legal velocity through", function()
		local v = PvpKnockbackRules.velocity({ X = 4, Y = 2, Z = 3 })
		local c = PvpKnockbackRules.clampVelocity(v)
		expect(near(c.X, v.X) and near(c.Y, v.Y) and near(c.Z, v.Z)).toBe(true)
	end)
	it("caps horizontal speed and vertical speed, and refuses junk", function()
		local c = PvpKnockbackRules.clampVelocity({ X = 1e6, Y = 1e6, Z = 0 })
		expect(near(c.X, PvpKnockbackRules.maxHorizontalSpeed())).toBe(true)
		expect(c.Y).toBe(P.KNOCKBACK_MAX_SPEED_Y)
		expect(PvpKnockbackRules.clampVelocity({ X = 0 / 0, Y = 1, Z = 1 }).Y).toBe(0)
		expect(PvpKnockbackRules.clampVelocity("x").X).toBe(0)
		expect(PvpKnockbackRules.clampVelocity({ X = 1, Y = -50, Z = 1 }).Y).toBe(0)
	end)
	it("the Bounce Pad lift fits the vertical cap", function()
		local pad = PvpRules.tool("FunBouncePad") :: any
		local v = PvpKnockbackRules.velocity({ X = 0, Y = pad.height, Z = 0 })
		expect(v.Y <= P.KNOCKBACK_MAX_SPEED_Y).toBe(true)
	end)
end)

describe("Trap hold and blaster slow values (docs/PVP.md)", function()
	local function tool(id: string): any
		return PvpRules.tool(id)
	end
	it("trap freeze is 1 / 1.5 / 2 s", function()
		expect(tool("GooTrap1").control).toBe(1)
		expect(tool("GooTrap2").control).toBe(1.5)
		expect(tool("GooTrap3").control).toBe(2)
	end)
	it("blaster slow is 30 % 2 s, 40 % 2.5 s, 50 % 3 s", function()
		expect(tool("GooBlaster1").slow).toBe(0.3)
		expect(tool("GooBlaster1").slowSeconds).toBe(2)
		expect(tool("GooBlaster2").slow).toBe(0.4)
		expect(tool("GooBlaster2").slowSeconds).toBe(2.5)
		expect(tool("GooBlaster3").slow).toBe(0.5)
		expect(tool("GooBlaster3").slowSeconds).toBe(3)
	end)
	it("applyControl / applySlow clamp to the Config caps, then immunity", function()
		local s = PvpRules.newState()
		expect(PvpRules.applyControl(s, 99, 100)).toBe(P.CONTROL_MAX_SECONDS)
		expect(PvpRules.applyControl(s, 1, 100.5)).toBe(0) -- still controlled
		expect(PvpRules.canControl(s, 100 + P.CONTROL_MAX_SECONDS + 1)).toBe(false) -- immune
		expect(PvpRules.canControl(s, 100 + P.CONTROL_MAX_SECONDS + P.CONTROL_IMMUNITY_SECONDS + 0.01)).toBe(true)
		local t = PvpRules.newState()
		expect(PvpRules.applySlow(t, 99, 100)).toBe(P.SLOW_MAX_SECONDS)
		expect(PvpRules.applySlow(PvpRules.newState(), 0, 100)).toBe(0)
	end)
end)

describe("PvP void guard (Rescue)", function()
	it("no PvP guard: only the kill plane rescues", function()
		expect(Rescue.shouldRescuePvp(-30, true, false)).toBe(false)
		expect(Rescue.shouldRescuePvp(Rescue.KILL_PLANE_Y - 1, true, false)).toBe(true)
	end)
	it("with the guard armed the safe floor is higher; the dead and NaN are never moved", function()
		expect(Rescue.shouldRescuePvp(Rescue.PVP_SAFE_Y - 1, true, true)).toBe(true)
		expect(Rescue.shouldRescuePvp(Rescue.PVP_SAFE_Y + 1, true, true)).toBe(false)
		expect(Rescue.shouldRescuePvp(-500, false, true)).toBe(false)
		expect(Rescue.shouldRescuePvp(0 / 0, true, true)).toBe(false)
	end)
	it("the guard floor is above the kill plane and well below the ground", function()
		expect(Rescue.PVP_SAFE_Y > Rescue.KILL_PLANE_Y).toBe(true)
		expect(Rescue.PVP_SAFE_Y < -5).toBe(true)
	end)
	it("is armed under control or within LAUNCH_GUARD_SECONDS of a launch", function()
		local g = P.LAUNCH_GUARD_SECONDS
		expect(Rescue.pvpActive(10, nil, nil, g)).toBe(false)
		expect(Rescue.pvpActive(10, 8, nil, g)).toBe(true)
		expect(Rescue.pvpActive(10 + g, 10, nil, g)).toBe(true)
		expect(Rescue.pvpActive(10 + g + 0.1, 10, nil, g)).toBe(false)
		expect(Rescue.pvpActive(10, nil, 11, g)).toBe(true)
		expect(Rescue.pvpActive(10, nil, 10, g)).toBe(false)
	end)
end)
