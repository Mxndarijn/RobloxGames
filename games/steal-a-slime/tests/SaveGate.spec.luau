--!strict
local DataService = require("../src/server/DataService")
local SaveGate = require("../src/server/SaveGate")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

-- Memory backend whose `holdCall`-th update yields the calling thread until the test resumes it, like a
-- DataStore call still in flight.
local function slowBackend(holdCall: number)
	local inner = DataService.memoryBackend()
	local calls = 0
	return {
		records = inner.records,
		update = function(key: string, transform: any): any
			calls += 1
			if calls == holdCall then
				coroutine.yield()
			end
			return inner.update(key, transform)
		end,
	}
end

local function service(backend: any)
	return DataService.new({
		backend = backend,
		jobId = "job-A",
		now = function()
			return 1_700_000_000
		end,
		wait = function() end,
	})
end

-- A gate whose clock moves only when it waits; each wait runs `onWait` (the DataStore answering).
local function gate(onWait: () -> ())
	local t = 0
	local waits = 0
	local g = SaveGate.new({
		clock = function()
			return t
		end,
		wait = function(seconds: number)
			waits += 1
			t += seconds
			onWait()
		end,
	})
	return g, function()
		return waits, t
	end
end

local function present()
	return true
end

describe("SaveGate shutdown", function()
	it("releases the lock of a load that finishes after shutdown started, and shutdown waits for it", function()
		local backend = slowBackend(1)
		local svc = service(backend)
		local loader: thread
		local g, stats = gate(function()
			if coroutine.status(loader) == "suspended" then
				coroutine.resume(loader)
			end
		end)
		local results = {}
		loader = coroutine.create(function()
			results = { SaveGate.load(g, svc, 7, present) }
		end)
		coroutine.resume(loader) -- the load is in flight
		expect(SaveGate.busy(g)).toBe(true)

		SaveGate.close(g)
		SaveGate.wait(g, 25)

		expect(coroutine.status(loader)).toBe("dead")
		expect(results[1]).toBe(false)
		expect(results[2]).toBe("closing")
		expect(backend.records["u_7"].session).toBe(nil) -- lock released
		expect(SaveGate.busy(g)).toBe(false)
		local waits, elapsed = stats()
		expect(waits >= 1).toBe(true)
		expect(elapsed < 25).toBe(true)
	end)

	it("counts the release of a player who left mid-load as a save in flight", function()
		local backend = slowBackend(2) -- the load answers, the release save is still in flight
		local svc = service(backend)
		local g = gate(function() end)
		local results = {}
		local loader = coroutine.create(function()
			results = { SaveGate.load(g, svc, 9, function()
				return false
			end) }
		end)
		coroutine.resume(loader)
		expect(g.pending).toBe(1)
		expect(SaveGate.busy(g)).toBe(true)

		coroutine.resume(loader)
		expect(results[1]).toBe(false)
		expect(results[2]).toBe("left")
		expect(backend.records["u_9"].session).toBe(nil)
		expect(SaveGate.busy(g)).toBe(false)
	end)

	it("lets a player whose load finishes before shutdown join with the lock held", function()
		local backend = DataService.memoryBackend()
		local g = gate(function() end)
		local ok = SaveGate.load(g, service(backend), 3, present)
		expect(ok).toBe(true)
		expect(backend.records["u_3"].session.jobId).toBe("job-A")
		expect(SaveGate.busy(g)).toBe(false)
	end)

	it("does not take the lock for a load that starts after shutdown", function()
		local backend = DataService.memoryBackend()
		local g = gate(function() end)
		SaveGate.close(g)
		local ok, reason = SaveGate.load(g, service(backend), 5, present)
		expect(ok).toBe(false)
		expect(reason).toBe("closing")
		expect(backend.records["u_5"]).toBe(nil)
	end)

	it("stops waiting at the timeout when a save never finishes", function()
		local g, stats = gate(function() end)
		local saver = coroutine.create(function()
			SaveGate.track(g, function()
				coroutine.yield()
			end)
		end)
		coroutine.resume(saver)
		SaveGate.wait(g, 2)
		local _, elapsed = stats()
		expect(elapsed >= 2).toBe(true)
		expect(elapsed < 2.5).toBe(true)
		expect(SaveGate.busy(g)).toBe(true)
	end)
end)

return nil
