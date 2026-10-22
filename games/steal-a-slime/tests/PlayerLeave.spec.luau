--!strict
local Carry = require("../src/server/Carry")
local PlayerLeave = require("../src/server/PlayerLeave")
local SafeCall = require("../src/server/SafeCall")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")
local World = require("../src/server/World")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

type Env = {
	logs: { string },
	ran: { string },
	saved: { World.Session },
}

-- Hooks that record what ran and what was saved; `throwing` names the steps (or "refreshView") that error.
local function hooks(throwing: { [string]: boolean }): (Env, PlayerLeave.Hooks)
	local env: Env = { logs = {}, ran = {}, saved = {} }
	local function step(name: string): PlayerLeave.Step
		return {
			name = name,
			run = function()
				if throwing[name] then
					error(`{name} broke`)
				end
				table.insert(env.ran, name)
			end,
		}
	end
	return env,
		{
			safeCall = SafeCall.new(function(message)
				table.insert(env.logs, message)
			end),
			cleanup = { step("badges"), step("friends"), step("ritual") },
			refreshView = function()
				if throwing.refreshView then
					error("refreshView broke")
				end
				table.insert(env.ran, "refreshView")
			end,
			save = function(session)
				table.insert(env.saved, session)
			end,
		}
end

describe("PlayerLeave", function()
	it("removes the session, runs every cleanup step and the view refresh, then saves", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1)
		local env, h = hooks({})
		expect(PlayerLeave.run(world, 1, T0, h)).toBe(session)
		expect(world.sessions[1]).toBeNil()
		expect(env.ran).toEqual({ "badges", "friends", "ritual", "refreshView" })
		expect(env.saved).toEqual({ session })
		expect(#env.logs).toBe(0)
	end)

	it("a cleanup step or the view refresh that throws is logged; the other steps and the save still run", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1)
		local env, h = hooks({ friends = true, refreshView = true })
		PlayerLeave.run(world, 1, T0, h)
		expect(world.sessions[1]).toBeNil()
		expect(env.ran).toEqual({ "badges", "ritual" })
		expect(env.saved).toEqual({ session })
		expect(#env.logs).toBe(2)
	end)

	it("a carry release that throws still frees the plot and saves the session", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1)
		local env, h = hooks({})
		local original = Carry.release
		Carry.release = function(): boolean
			error("carry state broken")
		end
		local ok, err = pcall(PlayerLeave.run, world, 1, T0, h)
		Carry.release = original
		expect(ok).toBe(true)
		expect(err).toBe(session)
		expect(world.sessions[1]).toBeNil()
		expect(world.plots[session.plotIndex]).toBeNil()
		expect(env.saved).toEqual({ session })
		expect(#env.logs).toBe(1)
	end)

	it("a player without a session still has their caches cleaned up; nothing is saved", function()
		local world = ServerFixtures.world()
		local env, h = hooks({})
		expect(PlayerLeave.run(world, 1, T0, h)).toBeNil()
		expect(env.ran).toEqual({ "badges", "friends", "ritual" })
		expect(#env.saved).toBe(0)
	end)
end)
