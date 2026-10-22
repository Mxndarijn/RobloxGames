--!strict
local Config = require("../src/shared/Config")
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
		expect(DataService.canSave(svc, 9)).toBe(false)
		expect(select(2, DataService.save(svc, 9, Fixtures.data(nil, 1), true))).toBe("session lost")
	end)
end)

describe("DataService read-only sessions", function()
	local function logged(backend: any, jobId: string?)
		local logs = {}
		local svc = DataService.new({
			backend = backend,
			jobId = jobId or "job-A",
			now = function()
				return clock
			end,
			wait = function() end,
			loadAttempts = 3,
			saveAttempts = 3,
			log = function(message)
				table.insert(logs, message)
			end,
		})
		return svc, logs
	end
	local newer = { version = Config.SAVE_VERSION + 1, cash = 777, futureField = { "keep me" } }

	it("never overwrites a record from a newer save version, but still refreshes and releases the lock", function()
		local backend = DataService.memoryBackend()
		backend.records["u_3"] = { data = table.clone(newer), session = nil }
		local svc, logs = logged(backend)
		local ok, data = DataService.load(svc, 3)
		expect(ok).toBe(true)
		expect((data :: PlayerData.Data).cash).toBe(777) -- best-effort read
		expect(DataService.readOnly(svc, 3)).toBe("newer")
		expect(#logs).toBe(1)
		expect(DataService.canSave(svc, 3)).toBe(false)
		local played = data :: PlayerData.Data
		played.cash = 1
		local saved, reason = DataService.save(svc, 3, played, false)
		expect(saved).toBe(true)
		expect(reason).toBe("read-only")
		local record = backend.records["u_3"]
		expect(record.data.version).toBe(Config.SAVE_VERSION + 1)
		expect(record.data.cash).toBe(777)
		expect(record.data.futureField[1]).toBe("keep me")
		expect(record.session.jobId).toBe("job-A")
		expect((DataService.save(svc, 3, played, true))).toBe(true)
		expect(backend.records["u_3"].session).toBeNil()
		expect(backend.records["u_3"].data.cash).toBe(777)
		expect(DataService.readOnly(svc, 3)).toBeNil()
		expect((DataService.load(logged(backend, "job-B"), 3))).toBe(true) -- lock was released
	end)
	it("never overwrites an unreadable record", function()
		for _, junk in { "corrupt", 42, {}, { version = "x" } } do
			local backend = DataService.memoryBackend()
			backend.records["u_4"] = { data = junk, session = nil }
			local svc, logs = logged(backend)
			local ok, data = DataService.load(svc, 4)
			expect(ok).toBe(true)
			expect(DataService.readOnly(svc, 4)).toBe("unreadable")
			expect(#logs).toBe(1)
			DataService.save(svc, 4, data :: PlayerData.Data, true)
			expect(backend.records["u_4"].data).toBe(junk)
		end
	end)
	it("saves normally for new players and current saves", function()
		local backend = DataService.memoryBackend()
		local svc, logs = logged(backend)
		DataService.load(svc, 6)
		expect(DataService.readOnly(svc, 6)).toBeNil()
		expect(DataService.canSave(svc, 6)).toBe(true)
		local data = Fixtures.data(nil, 1)
		data.cash = 12345
		expect(select(2, DataService.save(svc, 6, data, false))).toBeNil()
		expect(backend.records["u_6"].data.cash).toBe(12345)
		expect(backend.records["u_6"].data.version).toBe(Config.SAVE_VERSION)
		expect(#logs).toBe(0)
		local again = logged(backend, "job-A")
		DataService.load(again, 6)
		expect(DataService.readOnly(again, 6)).toBeNil()
	end)
end)
