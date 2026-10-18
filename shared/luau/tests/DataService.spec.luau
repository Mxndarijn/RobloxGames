--!strict
local DataService = require("../src/data/DataService")
local T = require("../testing/TestRunner")
local describe, it, expect = T.describe, T.it, T.expect

local KEY = "u_1"
local STALE = 100

type Harness = {
	service: DataService.DataService,
	backend: DataService.MemoryBackend,
	clock: { t: number },
	waits: { number },
	logs: { string },
	failures: { n: number },
}

local function steps()
	return {
		[1] = function(raw)
			raw.coins = raw.cash or 0
			raw.cash = nil
			return raw
		end,
	}
end

-- A service on a memory backend whose update errors `failures.n` more times before working.
local function harness(jobId: string?, shared: DataService.MemoryBackend?, overrides: { [string]: any }?): Harness
	local backend = shared or DataService.memoryBackend()
	local clock = { t = 1000 }
	local waits: { number } = {}
	local logs: { string } = {}
	local failures = { n = 0 }
	local flaky: DataService.Backend = {
		update = function(key, transform)
			if failures.n > 0 then
				failures.n -= 1
				error("backend down")
			end
			return backend.update(key, transform)
		end,
	}
	local options: any = {
		backend = flaky,
		jobId = jobId or "A",
		now = function()
			return clock.t
		end,
		wait = function(seconds: number)
			table.insert(waits, seconds)
			clock.t += seconds
		end,
		defaultData = function()
			return { coins = 0 }
		end,
		serialize = function(data, _now)
			return { version = 2, coins = data.coins }
		end,
		deserialize = function(raw)
			if raw.explode then
				error("cannot read")
			end
			return { coins = if type(raw.coins) == "number" then raw.coins else 0 }
		end,
		migrations = { steps = steps(), latest = 2 },
		staleAfter = STALE,
		log = function(message: string)
			table.insert(logs, message)
		end,
	}
	for k, v in overrides or {} do
		options[k] = v
	end
	return {
		service = DataService.new(options),
		backend = backend,
		clock = clock,
		waits = waits,
		logs = logs,
		failures = failures,
	}
end

describe("DataService.load", function()
	it("gives default data for a new key and takes the lock", function()
		local h = harness()
		local ok, data, readOnly = h.service:load(KEY)
		expect(ok).toBe(true)
		expect(data).toEqual({ coins = 0 })
		expect(readOnly).toBe(false)
		expect(h.backend.records[KEY].session).toEqual({ jobId = "A", time = 1000 })
	end)

	it("migrates an old record before deserializing it", function()
		local h = harness()
		h.backend.records[KEY] = { data = { version = 1, cash = 40 } }
		local ok, data, readOnly = h.service:load(KEY)
		expect(ok).toBe(true)
		expect(data).toEqual({ coins = 40 })
		expect(readOnly).toBe(false)
	end)

	it("reads a legacy unwrapped record", function()
		local h = harness()
		h.backend.records[KEY] = { version = 2, coins = 9 }
		local ok, data = h.service:load(KEY)
		expect(ok).toBe(true)
		expect(data).toEqual({ coins = 9 })
	end)

	it("retries backend errors with backoff through the injected wait", function()
		local h = harness()
		h.failures.n = 2
		local ok, data = h.service:load(KEY)
		expect(ok).toBe(true)
		expect(data).toEqual({ coins = 0 })
		expect(h.waits).toEqual({ 2, 4 })
	end)

	it("gives up with BackendError after loadAttempts and does not wait after the last try", function()
		local h = harness(nil, nil, { loadAttempts = 3 })
		h.failures.n = 10
		local ok, reason = h.service:load(KEY)
		expect(ok).toBe(false)
		expect(reason).toBe("BackendError")
		expect(h.waits).toEqual({ 2, 4 })
	end)

	it("retries while another live server holds the lock, then gives up with Locked", function()
		local h = harness(nil, nil, { loadAttempts = 3 })
		h.backend.records[KEY] = { data = { version = 2, coins = 5 }, session = { jobId = "B", time = 1000 } }
		local ok, reason = h.service:load(KEY)
		expect(ok).toBe(false)
		expect(reason).toBe("Locked")
		expect(h.waits).toEqual({ 2, 4 })
		expect(h.backend.records[KEY].session.jobId).toBe("B")
	end)

	it("gets the record once the other server releases it between retries", function()
		local h = harness()
		h.backend.records[KEY] = { data = { version = 2, coins = 5 }, session = { jobId = "B", time = 1000 } }
		local releasing: any = {
			update = h.backend.update,
		}
		local service = DataService.new({
			backend = releasing,
			jobId = "A",
			now = function()
				return 1000
			end,
			wait = function(_)
				h.backend.records[KEY].session = nil
			end,
			defaultData = function()
				return { coins = 0 }
			end,
			serialize = function(data, _)
				return data
			end,
			deserialize = function(raw)
				return { coins = raw.coins }
			end,
			staleAfter = STALE,
		})
		local ok, data = service:load(KEY)
		expect(ok).toBe(true)
		expect(data).toEqual({ coins = 5 })
	end)

	it("takes over a lock older than staleAfter", function()
		local h = harness()
		h.backend.records[KEY] =
			{ data = { version = 2, coins = 5 }, session = { jobId = "B", time = 1000 - STALE - 1 } }
		local ok, data = h.service:load(KEY)
		expect(ok).toBe(true)
		expect(data).toEqual({ coins = 5 })
		expect(h.backend.records[KEY].session.jobId).toBe("A")
	end)

	it("uses the staleAfter option instead of a fixed number", function()
		local h = harness(nil, nil, { staleAfter = 5000, loadAttempts = 1 })
		h.backend.records[KEY] = { data = { version = 2 }, session = { jobId = "B", time = 1000 - STALE - 1 } }
		local ok, reason = h.service:load(KEY)
		expect(ok).toBe(false)
		expect(reason).toBe("Locked")
	end)
end)

describe("DataService.save", function()
	it("serializes the data and keeps the lock", function()
		local h = harness()
		h.service:load(KEY)
		h.clock.t = 1010
		local ok, reason = h.service:save(KEY, { coins = 12 }, false)
		expect(ok).toBe(true)
		expect(reason).toBeNil()
		expect(h.backend.records[KEY]).toEqual({
			data = { version = 2, coins = 12 },
			session = { jobId = "A", time = 1010 },
		})
	end)

	it("releases the lock so another server can load at once", function()
		local h = harness()
		h.service:load(KEY)
		expect(h.service:save(KEY, { coins = 3 }, true)).toBe(true)
		expect(h.backend.records[KEY].session).toBeNil()
		local other = harness("B", h.backend, { loadAttempts = 1 })
		local ok, data = other.service:load(KEY)
		expect(ok).toBe(true)
		expect(data).toEqual({ coins = 3 })
	end)

	it("retries backend errors and then succeeds", function()
		local h = harness()
		h.service:load(KEY)
		h.failures.n = 1
		expect(h.service:save(KEY, { coins = 1 }, false)).toBe(true)
		expect(h.waits).toEqual({ 2 })
	end)

	it("gives up with BackendError after saveAttempts", function()
		local h = harness(nil, nil, { saveAttempts = 2 })
		h.service:load(KEY)
		h.failures.n = 5
		local ok, reason = h.service:save(KEY, { coins = 1 }, false)
		expect(ok).toBe(false)
		expect(reason).toBe("BackendError")
		expect(h.waits).toEqual({ 2 })
		expect(h.service:isLost(KEY)).toBe(false)
	end)

	it("refuses and stops saving once another server took the session over", function()
		local h = harness()
		h.service:load(KEY)
		h.backend.records[KEY].session = { jobId = "B", time = 1000 }
		local ok, reason = h.service:save(KEY, { coins = 99 }, false)
		expect(ok).toBe(false)
		expect(reason).toBe("SessionLost")
		expect(h.service:isLost(KEY)).toBe(true)
		expect(h.backend.records[KEY].data).toBeNil()
		local calls = 0
		local before = h.backend.update
		h.backend.update = function(key, transform)
			calls += 1
			return before(key, transform)
		end
		expect(select(2, h.service:save(KEY, { coins = 99 }, true))).toBe("SessionLost")
		expect(calls).toBe(0)
	end)

	it("refuses a save after the session was already released", function()
		local h = harness()
		h.service:load(KEY)
		h.service:save(KEY, { coins = 1 }, true)
		local ok, reason = h.service:save(KEY, { coins = 2 }, false)
		expect(ok).toBe(false)
		expect(reason).toBe("SessionLost")
		expect(h.backend.records[KEY].data.coins).toBe(1)
	end)

	it("clears the lost state on the next successful load", function()
		local h = harness()
		h.service:load(KEY)
		h.backend.records[KEY].session = { jobId = "B", time = 0 }
		h.service:save(KEY, { coins = 1 }, false)
		expect(h.service:isLost(KEY)).toBe(true)
		h.clock.t = 1000 + STALE * 10
		expect((h.service:load(KEY))).toBe(true)
		expect(h.service:isLost(KEY)).toBe(false)
		expect(h.service:save(KEY, { coins = 2 }, false)).toBe(true)
	end)
end)

describe("DataService read-only sessions", function()
	it("loads a newer-schema record read-only with a best-effort value", function()
		local h = harness()
		h.backend.records[KEY] = { data = { version = 3, coins = 77, future = true } }
		local ok, data, readOnly = h.service:load(KEY)
		expect(ok).toBe(true)
		expect(data).toEqual({ coins = 77 })
		expect(readOnly).toBe(true)
		expect(h.service:readOnly(KEY)).toBe("newer")
		expect(#h.logs).toBe(1)
	end)

	it("never saves over a newer-schema record but keeps and releases the lock", function()
		local h = harness()
		local stored = { version = 3, coins = 77, future = true }
		h.backend.records[KEY] = { data = stored }
		h.service:load(KEY)
		h.clock.t = 1020
		local ok, reason = h.service:save(KEY, { coins = 0 }, false)
		expect(ok).toBe(false)
		expect(reason).toBe("ReadOnly")
		expect(h.backend.records[KEY].data).toEqual({ version = 3, coins = 77, future = true })
		expect(h.backend.records[KEY].session).toEqual({ jobId = "A", time = 1020 })
		local released, why = h.service:save(KEY, { coins = 0 }, true)
		expect(released).toBe(false)
		expect(why).toBe("ReadOnly")
		expect(h.backend.records[KEY]).toEqual({ data = { version = 3, coins = 77, future = true } })
		expect(h.service:readOnly(KEY)).toBeNil()
	end)

	it("falls back to default data when deserialize cannot read a newer record", function()
		local h = harness()
		h.backend.records[KEY] = { data = { version = 3, explode = true } }
		local ok, data, readOnly = h.service:load(KEY)
		expect(ok).toBe(true)
		expect(data).toEqual({ coins = 0 })
		expect(readOnly).toBe(true)
	end)

	it("treats a garbage record as unreadable and read-only", function()
		local h = harness()
		h.backend.records[KEY] = { data = "garbage" }
		local ok, data, readOnly = h.service:load(KEY)
		expect(ok).toBe(true)
		expect(data).toEqual({ coins = 0 })
		expect(readOnly).toBe(true)
		expect(h.service:readOnly(KEY)).toBe("unreadable")
		h.service:save(KEY, { coins = 5 }, false)
		expect(h.backend.records[KEY].data).toBe("garbage")
	end)

	it("treats a record deserialize rejects as unreadable", function()
		local h = harness()
		h.backend.records[KEY] = { data = { version = 2, explode = true } }
		local _, data, readOnly = h.service:load(KEY)
		expect(data).toEqual({ coins = 0 })
		expect(readOnly).toBe(true)
		expect(h.service:readOnly(KEY)).toBe("unreadable")
	end)

	it("keeps keys independent", function()
		local h = harness()
		h.backend.records[KEY] = { data = { version = 3 } }
		h.service:load(KEY)
		h.service:load("u_2")
		expect(h.service:save("u_2", { coins = 4 }, false)).toBe(true)
		expect(h.backend.records["u_2"].data.coins).toBe(4)
	end)
end)

describe("DataService without migrations", function()
	it("deserializes any table and treats non-tables as unreadable", function()
		local h = harness(nil, nil, { migrations = false })
		h.backend.records[KEY] = { data = { coins = 2 } }
		local ok, data, readOnly = h.service:load(KEY)
		expect(ok).toBe(true)
		expect(data).toEqual({ coins = 2 })
		expect(readOnly).toBe(false)
		h.backend.records["u_2"] = { data = 5 }
		expect(select(3, h.service:load("u_2"))).toBe(true)
	end)
end)

describe("DataService.new", function()
	it("rejects missing functions or backend", function()
		expect(function()
			DataService.new({} :: any)
		end).toThrow()
		local h = harness()
		expect(function()
			DataService.new({
				backend = h.backend,
				jobId = "A",
				now = os.time,
				wait = function() end,
				serialize = function(d)
					return d
				end,
				deserialize = function(d)
					return d
				end,
			} :: any)
		end).toThrow()
	end)
end)
