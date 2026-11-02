--!strict
-- The server adapter driven through mock signals and an injected teleport.
local IdleRejoinServer = require("../../src/idle/IdleRejoinServer")
local TestRunner = require("../../testing/TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function signal()
	local handlers = {}
	local s = {}
	function s:Connect(fn)
		table.insert(handlers, fn)
		local c = {}
		function c.Disconnect(_self)
			local i = table.find(handlers, fn)
			if i then
				table.remove(handlers, i)
			end
		end
		return c
	end
	function s.fire(...)
		for _, fn in table.clone(handlers) do
			fn(...)
		end
	end
	function s.count()
		return #handlers
	end
	return s
end

local function setup(teleportOk: boolean?)
	local remote = { OnServerEvent = signal() }
	local players = { PlayerRemoving = signal() }
	local sent: { number } = {}
	local logs: { string } = {}
	local t = 0
	local handle = IdleRejoinServer.start({
		remote = remote :: any,
		players = players :: any,
		placeId = 1,
		jobId = "job",
		options = { rejoinAfter = 100, retryAfter = 30, maxTries = 3 },
		teleport = function(player: any)
			table.insert(sent, player.UserId)
			if teleportOk == false then
				return false, "Full"
			end
			return true, nil
		end,
		now = function()
			return t
		end,
		log = function(message: string)
			table.insert(logs, message)
		end,
		spawn = function(fn)
			fn()
		end,
	})
	return {
		handle = handle,
		report = function(userId: number, seconds: any, at: number)
			t = at
			remote.OnServerEvent.fire({ UserId = userId }, seconds)
		end,
		leave = function(userId: number)
			players.PlayerRemoving.fire({ UserId = userId })
		end,
		sent = sent,
		logs = logs,
		remote = remote,
		players = players,
	}
end

describe("IdleRejoinServer", function()
	it("teleports a player once their idle time passes rejoinAfter", function()
		local s = setup()
		s.report(7, 90, 0)
		expect(#s.sent).toBe(0)
		s.report(7, 120, 30)
		expect(#s.sent).toBe(1)
		expect(s.sent[1]).toBe(7)
		expect(string.find(s.logs[1], "rejoining", 1, true) ~= nil).toBe(true)
	end)

	it("retries on the next report after retryAfter when the teleport did not happen", function()
		local s = setup(false)
		s.report(7, 120, 0)
		s.report(7, 130, 10)
		s.report(7, 150, 30)
		expect(#s.sent).toBe(2)
		expect(string.find(s.logs[1], "failed", 1, true) ~= nil).toBe(true)
	end)

	it("ignores reports that are not a sane number", function()
		local s = setup()
		s.report(7, "999", 0)
		s.report(7, 0 / 0, 0)
		s.report(7, -5, 0)
		s.report(7, nil, 0)
		expect(#s.sent).toBe(0)
	end)

	it("forgets a player who leaves", function()
		local s = setup()
		s.report(7, 120, 0)
		s.leave(7)
		s.report(7, 120, 1)
		expect(#s.sent).toBe(2)
	end)

	it("only logs in dry-run mode", function()
		local remote = { OnServerEvent = signal() }
		local logs: { string } = {}
		IdleRejoinServer.start({
			remote = remote :: any,
			players = { PlayerRemoving = signal() } :: any,
			placeId = 1,
			jobId = "job",
			dryRun = true,
			options = { rejoinAfter = 100 },
			log = function(message: string)
				table.insert(logs, message)
			end,
			spawn = function(fn)
				fn()
			end,
		})
		remote.OnServerEvent.fire({ UserId = 3 }, 100)
		expect(#logs).toBe(1)
		expect(string.find(logs[1], "dry run", 1, true) ~= nil).toBe(true)
	end)

	it("disconnects everything on destroy", function()
		local s = setup()
		s.handle:destroy()
		expect(s.remote.OnServerEvent.count()).toBe(0)
		expect(s.players.PlayerRemoving.count()).toBe(0)
		s.report(7, 500, 0)
		expect(#s.sent).toBe(0)
	end)
end)
