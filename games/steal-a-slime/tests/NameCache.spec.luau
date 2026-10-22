--!strict
local NameCache = require("../src/server/NameCache")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("NameCache", function()
	it("a failed lookup answers the fallback and is retried next time", function()
		local calls = 0
		local function fetch(id: number): string
			calls += 1
			if calls == 1 then
				error("HTTP 429")
			end
			return `Real{id}`
		end
		local cache: NameCache.Cache = {}
		expect(NameCache.resolve(cache, 7, fetch)).toBe("Player 7")
		expect(NameCache.resolve(cache, 7, fetch)).toBe("Real7")
		expect(calls).toBe(2)
	end)
	it("a fetched name is kept and not fetched again", function()
		local calls = 0
		local function fetch(id: number): string
			calls += 1
			return `Real{id}`
		end
		local cache: NameCache.Cache = {}
		expect(NameCache.resolve(cache, 7, fetch)).toBe("Real7")
		expect(NameCache.resolve(cache, 7, fetch)).toBe("Real7")
		expect(calls).toBe(1)
	end)
	it("a non-string answer counts as a failure", function()
		local cache: NameCache.Cache = {}
		expect(NameCache.resolve(cache, 3, function(): any
			return nil
		end)).toBe("Player 3")
		expect(cache[3]).toBe(nil)
	end)
end)
