--!strict
local SessionLock = require("../src/data/SessionLock")
local T = require("../testing/TestRunner")
local describe, it, expect = T.describe, T.it, T.expect

local STALE = 100

describe("SessionLock.unwrap", function()
	it("reads non-tables as nothing", function()
		local data, session = SessionLock.unwrap(nil)
		expect(data).toBeNil()
		expect(session).toBeNil()
		expect((SessionLock.unwrap("junk"))).toBeNil()
	end)

	it("reads an unwrapped table as unlocked data", function()
		local raw = { coins = 5 }
		local data, session = SessionLock.unwrap(raw)
		expect(data).toBe(raw)
		expect(session).toBeNil()
	end)

	it("reads a wrapped record", function()
		local data, session = SessionLock.unwrap({ data = { coins = 1 }, session = { jobId = "A", time = 10 } })
		expect(data).toEqual({ coins = 1 })
		expect(session).toEqual({ jobId = "A", time = 10 })
	end)

	it("ignores a malformed session", function()
		local data, session = SessionLock.unwrap({ data = 1, session = { jobId = 5 } })
		expect(data).toBe(1)
		expect(session).toBeNil()
	end)
end)

describe("SessionLock.status", function()
	it("is free without a session and own for this job", function()
		expect(SessionLock.status(nil, "A", 0, STALE)).toBe("free")
		expect(SessionLock.status({ jobId = "A", time = 0 }, "A", 1000, STALE)).toBe("own")
	end)

	it("is locked by a live server and stale after staleAfter seconds", function()
		local s = { jobId = "B", time = 0 }
		expect(SessionLock.status(s, "A", STALE, STALE)).toBe("locked")
		expect(SessionLock.status(s, "A", STALE + 1, STALE)).toBe("stale")
	end)
end)

describe("SessionLock.acquire", function()
	it("takes a free record and stamps the session", function()
		local record, status, data = SessionLock.acquire({ coins = 3 }, "A", 50, STALE)
		expect(status).toBe("free")
		expect(data).toEqual({ coins = 3 })
		expect(record).toEqual({ data = { coins = 3 }, session = { jobId = "A", time = 50 } })
	end)

	it("cancels the write while another live server holds the lock", function()
		local old = { data = { coins = 3 }, session = { jobId = "B", time = 40 } }
		local record, status, data = SessionLock.acquire(old, "A", 50, STALE)
		expect(record).toBeNil()
		expect(status).toBe("locked")
		expect(data).toEqual({ coins = 3 })
	end)

	it("takes over a stale lock", function()
		local old = { data = 1, session = { jobId = "B", time = 0 } }
		local record, status = SessionLock.acquire(old, "A", STALE + 5, STALE)
		expect(status).toBe("stale")
		expect(record).toEqual({ data = 1, session = { jobId = "A", time = STALE + 5 } })
	end)
end)

describe("SessionLock.write", function()
	local owned = { data = 1, session = { jobId = "A", time = 0 } }

	it("writes and refreshes the lock time when this job owns it", function()
		local record, ok = SessionLock.write(owned, "A", 30, 2, false, STALE)
		expect(ok).toBe(true)
		expect(record).toEqual({ data = 2, session = { jobId = "A", time = 30 } })
	end)

	it("drops the session on release", function()
		local record, ok = SessionLock.write(owned, "A", 30, 2, true, STALE)
		expect(ok).toBe(true)
		expect(record).toEqual({ data = 2 })
	end)

	it("refuses when another server took the session over", function()
		local taken = { data = 1, session = { jobId = "B", time = 10 } }
		local record, ok = SessionLock.write(taken, "A", 30, 2, false, STALE)
		expect(ok).toBe(false)
		expect(record).toBeNil()
	end)

	it("refuses when the session was already released", function()
		local record, ok = SessionLock.write({ data = 1 }, "A", 30, 2, true, STALE)
		expect(ok).toBe(false)
		expect(record).toBeNil()
	end)
end)

describe("SessionLock.backoff", function()
	it("doubles per attempt up to the cap", function()
		expect(SessionLock.backoff(1)).toBe(2)
		expect(SessionLock.backoff(2)).toBe(4)
		expect(SessionLock.backoff(3)).toBe(8)
		expect(SessionLock.backoff(4)).toBe(10)
		expect(SessionLock.backoff(4, 30)).toBe(16)
	end)
end)
