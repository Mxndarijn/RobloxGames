--!strict
local KitRequest = require("../../src/shared/KitRequest")
local SlimeLooks = require("../../src/shared/SlimeLooks")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local KitCache = UiHarness.ui("KitCache")

-- A cache whose delayed sender runs when `flush` is called; `answers` (true / false per call, default true) is what
-- the server says. `gaps()` counts the delays of GAP seconds between calls.
local function setup(answers: { boolean }?)
	local sent: { string } = {}
	local gaps = 0
	local pending: { () -> () } = {}
	local cache = KitCache.new({
		KitRequest = KitRequest,
		invoke = function(raw: string): boolean
			table.insert(sent, raw)
			local answer = if answers then answers[#sent] else nil
			return if answer == nil then true else answer
		end,
		delay = function(seconds: number, fn: () -> ())
			if seconds > 0 then
				gaps += 1
			end
			table.insert(pending, fn)
		end,
	})
	local function flush()
		while #pending > 0 do
			table.remove(pending, 1)()
		end
	end
	return cache, sent, flush, function()
		return gaps
	end
end

local function species(n: number): { string }
	local out = {}
	for i = 1, n do
		table.insert(out, string.sub(SlimeLooks.KITS[i], #"slime_" + 1))
	end
	return out
end

describe("KitCache", function()
	it("sends the wants of one moment together, and each species once", function()
		local cache, sent, flush = setup()
		cache.want("gummy")
		cache.want("mochi")
		cache.want("gummy")
		flush()
		expect(sent).toEqual({ "gummy,mochi" })
		cache.want("gummy")
		flush()
		expect(#sent).toBe(1)
		expect(cache.asked("gummy")).toBe(true)
	end)
	it("splits a big burst into calls of KitRequest.MAX, the gap between them", function()
		local cache, sent, flush, gaps = setup()
		for _, id in species(KitRequest.MAX + 3) do
			cache.want(id)
		end
		flush()
		expect(#sent).toBe(2)
		expect(gaps()).toBe(1)
	end)
	it("tries a refused call again, then gives up after TRIES", function()
		local cache, sent, flush = setup({ false, true })
		cache.want("gummy")
		flush()
		expect(sent).toEqual({ "gummy", "gummy" })
		expect(cache.asked("gummy")).toBe(true)
		local never, sentNever, flushNever = setup({ false, false, false, false })
		never.want("mochi")
		flushNever()
		expect(#sentNever).toBe(KitCache.TRIES)
		expect(never.asked("mochi")).toBe(true)
	end)
	it("never asks for a species without a kit", function()
		local cache, sent, flush = setup()
		cache.want("nope")
		flush()
		expect(sent).toEqual({})
		expect(cache.asked("nope")).toBe(true)
	end)
end)
