--!strict
local ReceiptLedger = require("../src/data/ReceiptLedger")
local T = require("../testing/TestRunner")
local describe, it, expect = T.describe, T.it, T.expect

local function request(list: { string }, id: string, pending: { [string]: boolean }, saveOk: boolean)
	local calls = { grants = 0, saves = 0 }
	local req: ReceiptLedger.Request = {
		list = list,
		id = id,
		cap = 3,
		pending = pending,
		grant = function()
			calls.grants += 1
			return true, nil
		end,
		save = function()
			calls.saves += 1
			return saveOk
		end,
	}
	return req, calls
end

describe("ReceiptLedger list", function()
	it("cleans junk, duplicates and keeps the newest ids within the cap", function()
		expect(ReceiptLedger.clean(nil, 3)).toEqual({})
		expect(ReceiptLedger.clean({ "a", 5, "", "a", "b", "c", "d" }, 3)).toEqual({ "b", "c", "d" })
		expect(ReceiptLedger.clean({ string.rep("x", 200), "ok" }, 3)).toEqual({ "ok" })
	end)

	it("records once and drops the oldest past the cap", function()
		local list = {}
		expect(ReceiptLedger.record(list, "a", 2)).toBe(true)
		expect(ReceiptLedger.record(list, "a", 2)).toBe(false)
		ReceiptLedger.record(list, "b", 2)
		ReceiptLedger.record(list, "c", 2)
		expect(list).toEqual({ "b", "c" })
		expect(ReceiptLedger.seen(list, "a")).toBe(false)
		expect(ReceiptLedger.seen(list, "c")).toBe(true)
	end)
end)

describe("ReceiptLedger.process", function()
	it("grants a new receipt once, records it and answers Granted after the save", function()
		local list, pending = {}, {}
		local req, calls = request(list, "p1", pending, true)
		expect(ReceiptLedger.process(req)).toBe("Granted")
		expect(list).toEqual({ "p1" })
		expect(pending.p1).toBeNil()
		expect(ReceiptLedger.process(req)).toBe("Granted")
		expect(calls.grants).toBe(1)
		expect(calls.saves).toBe(1)
	end)

	it("answers NotProcessedYet when the save fails and never grants twice on the retry", function()
		local list, pending = {}, {}
		local req, calls = request(list, "p1", pending, false)
		local decision, reason = ReceiptLedger.process(req)
		expect(decision).toBe("NotProcessedYet")
		expect(reason).toBe("SaveFailed")
		expect(pending.p1).toBe(true)
		local retry, retryCalls = request(list, "p1", pending, true)
		expect(ReceiptLedger.process(retry)).toBe("Granted")
		expect(calls.grants + retryCalls.grants).toBe(1)
		expect(retryCalls.saves).toBe(1)
		expect(pending.p1).toBeNil()
	end)

	it("records nothing when the grant refuses", function()
		local list, pending = {}, {}
		local req = request(list, "p1", pending, true)
		req.grant = function()
			return false, "unknown"
		end
		local decision, reason = ReceiptLedger.process(req)
		expect(decision).toBe("NotProcessedYet")
		expect(reason).toBe("GrantFailed")
		expect(list).toEqual({})
	end)

	it("refuses a bad id without granting", function()
		local req, calls = request({}, "", {}, true)
		expect(ReceiptLedger.process(req)).toBe("NotProcessedYet")
		expect(calls.grants).toBe(0)
	end)
end)
