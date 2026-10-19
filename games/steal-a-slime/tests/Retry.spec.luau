--!strict
-- Retry: bounded tries with waits between them (src/shared/Retry), used for the pet cloud template load.
local Retry = require("../src/shared/Retry")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function harness(succeedOn: number)
	local run = { calls = 0, waits = {} :: { number } }
	local function attempt(): string?
		run.calls += 1
		if run.calls >= succeedOn then
			return "made"
		end
		return nil
	end
	local function wait(seconds: number)
		table.insert(run.waits, seconds)
	end
	return run, attempt, wait
end

describe("Retry.run", function()
	it("returns at once on the first success, without waiting", function()
		local run, attempt, wait = harness(1)
		expect(Retry.run(attempt, { 2, 5 }, wait)).toBe("made")
		expect(run.calls).toBe(1)
		expect(#run.waits).toBe(0)
	end)
	it("retries after each delay until it succeeds", function()
		local run, attempt, wait = harness(3)
		expect(Retry.run(attempt, { 2, 5, 15 }, wait)).toBe("made")
		expect(run.calls).toBe(3)
		expect(run.waits[1]).toBe(2)
		expect(run.waits[2]).toBe(5)
		expect(#run.waits).toBe(2)
	end)
	it("gives up after 1 + #delays tries", function()
		local run, attempt, wait = harness(math.huge)
		expect(Retry.run(attempt, { 2, 5, 15 }, wait)).toBeNil()
		expect(run.calls).toBe(4)
		expect(#run.waits).toBe(3)
	end)
	it("never retries with no delays", function()
		local run, attempt, wait = harness(math.huge)
		expect(Retry.run(attempt, {}, wait)).toBeNil()
		expect(run.calls).toBe(1)
	end)
	it("counts a throwing attempt as a failed try", function()
		local calls = 0
		local result = Retry.run(function(): string?
			calls += 1
			if calls < 2 then
				error("boom")
			end
			return "made"
		end, { 1 }, function() end)
		expect(result).toBe("made")
		expect(calls).toBe(2)
	end)
end)
