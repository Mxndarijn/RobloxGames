--!strict
local DataService = require("../src/server/DataService")
local Fixtures = require("./Fixtures")
local PlayerData = require("../src/shared/PlayerData")
local SaveData = require("../src/shared/SaveData")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local clock = 1_700_000_000

local function service(backend: any, jobId: string?)
	local waits = {}
	local svc = DataService.new({
		backend = backend,
		jobId = jobId or "job-A",
		now = function()
			return clock
		end,
		wait = function(seconds)
			table.insert(waits, seconds)
		end,
		loadAttempts = 3,
		saveAttempts = 3,
	})
	return svc, waits
end

-- Memory backend whose first `n` calls error.
local function flaky(n: number)
	local inner = DataService.memoryBackend()
	local calls = 0
	return {
		records = inner.records,
		update = function(key: string, transform: any): any
			calls += 1
			if calls <= n then
				error("503: DataStore throttled")
			end
			return inner.update(key, transform)
		end,
	}
end

describe("DataService.load", function()
	it("gives a fresh profile for new players and takes the session lock", function()
		local backend = DataService.memoryBackend()
		local svc = service(backend)
		local ok, data = DataService.load(svc, 42)
		expect(ok).toBe(true)
		expect((data :: PlayerData.Data).cash).toBe(PlayerData.new().cash)
		local record = backend.records["u_42"]
		expect(record.session.jobId).toBe("job-A")
	end)
	it("retries DataStore errors with backoff", function()
		local svc, waits = service(flaky(2))
		local ok = DataService.load(svc, 1)
		expect(ok).toBe(true)
		expect(#waits).toBe(2)
		expect(waits[1] < waits[2]).toBeTruthy()
	end)
	it("gives up after loadAttempts", function()
		local svc, waits = service(flaky(99))
		local ok, reason = DataService.load(svc, 1)
		expect(ok).toBe(false)
		expect(reason).toBe("DataStore error")
		expect(#waits).toBe(2)
	end)
	it("refuses while another live server holds the session", function()
		local backend = DataService.memoryBackend()
		DataService.load(service(backend, "job-B"), 7)
		local ok, reason = DataService.load(service(backend, "job-A"), 7)
		expect(ok).toBe(false)
		expect(reason).toBe("your data is open on another server")
	end)
	it("takes over a stale session from a crashed server", function()
		local backend = DataService.memoryBackend()
		DataService.load(service(backend, "job-B"), 7)
		clock += 10_000
		local ok = DataService.load(service(backend, "job-A"), 7)
		expect(ok).toBe(true)
		expect(backend.records["u_7"].session.jobId).toBe("job-A")
	end)
end)

describe("DataService.save", function()
	it("round-trips data and stamps lastOnline", function()
		local backend = DataService.memoryBackend()
		local svc = service(backend)
		DataService.load(svc, 5)
		local data = Fixtures.data({ Fixtures.slime("a", 3) }, 999)
		expect((DataService.save(svc, 5, data, false))).toBe(true)
		expect(backend.records["u_5"].session ~= nil).toBeTruthy()
		local back = SaveData.deserialize(backend.records["u_5"].data)
		expect(back.cash).toBe(999)
		expect(back.lastOnline).toBe(clock)
		expect(back.slimes[1].id).toBe("a")
	end)
	it("releases the session lock on leave so another server can load", function()
		local backend = DataService.memoryBackend()
		local svc = service(backend)
		DataService.load(svc, 5)
		DataService.save(svc, 5, PlayerData.new(), true)
		expect(backend.records["u_5"].session).toBeNil()
		expect((DataService.load(service(backend, "job-B"), 5))).toBe(true)
	end)
	it("retries errors, then gives up", function()
		local backend = flaky(1)
		local svc, waits = service(backend)
		backend.records["u_1"] = { data = {}, session = { jobId = "job-A", time = clock } }
		expect((DataService.save(svc, 1, PlayerData.new(), false))).toBe(true)
		expect(#waits).toBe(1)
		local svc2 = service(flaky(99))
		expect(select(2, DataService.save(svc2, 1, PlayerData.new(), false))).toBe("DataStore error")
	end)
	it("stops saving once another server took the session over", function()
		local backend = DataService.memoryBackend()
		local svc = service(backend)
		DataService.load(svc, 9)
		backend.records["u_9"].session = { jobId = "job-B", time = clock }
		local ok, reason = DataService.save(svc, 9, Fixtures.data(nil, 1), false)
		expect(ok).toBe(false)
		expect(reason).toBe("session lost")
		expect(svc.lost[9]).toBe(true)
		expect(select(2, DataService.save(svc, 9, Fixtures.data(nil, 1), true))).toBe("session lost")
	end)
end)
