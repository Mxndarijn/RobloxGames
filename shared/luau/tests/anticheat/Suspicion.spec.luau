--!strict
local Suspicion = require("../../src/anticheat/Suspicion")
local T = require("../../testing/TestRunner")
local describe, it, expect = T.describe, T.it, T.expect

describe("Suspicion", function()
	it("stays ok below the pause level", function()
		local s = Suspicion.new(0)
		expect(Suspicion.add(s, 2, 0)).toBe("ok")
		expect(Suspicion.paused(s, 1)).toBe(false)
	end)

	it("pauses at pauseAt for pauseSeconds", function()
		local s = Suspicion.new(0)
		expect(Suspicion.add(s, 3, 10)).toBe("pause")
		expect(Suspicion.paused(s, 69)).toBe(true)
		expect(Suspicion.paused(s, 70)).toBe(false)
	end)

	it("kicks at kickAt", function()
		local s = Suspicion.new(0)
		Suspicion.add(s, 3, 0)
		Suspicion.add(s, 3, 1)
		expect(Suspicion.add(s, 3, 2)).toBe("kick")
	end)

	it("drains points over time", function()
		local s = Suspicion.new(0)
		Suspicion.add(s, 3, 0)
		expect(Suspicion.points(s, 60)).toBeCloseTo(2, 1e-6)
		expect(Suspicion.points(s, 600)).toBe(0)
		expect(Suspicion.add(s, 2, 600)).toBe("ok")
	end)

	it("takes option overrides", function()
		local s = Suspicion.new(0, { kickAt = 4 })
		expect(Suspicion.add(s, 4, 0)).toBe("kick")
	end)
end)
