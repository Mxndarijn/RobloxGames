--!strict
local MovementGuard = require("../../src/anticheat/MovementGuard")
local T = require("../../testing/TestRunner")
local describe, it, expect = T.describe, T.it, T.expect

local function at(t: number, x: number, y: number?, z: number?): MovementGuard.Sample
	return { t = t, x = x, y = y or 5, z = z or 0 }
end

-- Walks from x = 0 at `speed` studs/s for `seconds`, sampling every 0.1 s; returns every flag seen.
local function walk(g: MovementGuard.Track, speed: number, seconds: number, maxSpeed: number): { string }
	local flags = {}
	for i = 0, math.floor(seconds * 10 + 0.5) do
		local flag = MovementGuard.step(g, at(i / 10, speed * i / 10), maxSpeed)
		if flag then
			table.insert(flags, flag)
		end
	end
	return flags
end

describe("MovementGuard", function()
	it("never flags walking at the allowed speed", function()
		expect(#walk(MovementGuard.new(), 28, 10, 28)).toBe(0)
	end)

	it("flags a long jump in one sample as a teleport", function()
		local g = MovementGuard.new()
		MovementGuard.step(g, at(0, 0), 16)
		expect(MovementGuard.step(g, at(0.1, 120), 16)).toBe("teleport")
		expect(MovementGuard.teleportedWithin(g, 0.1, 3)).toBe(true)
		expect(MovementGuard.teleportedWithin(g, 3.2, 3)).toBe(false)
	end)

	it("flags a held speed hack once per fast stretch", function()
		local flags = walk(MovementGuard.new(), 55, 2, 22)
		expect(#flags).toBe(1)
		expect(flags[1]).toBe("speed")
	end)

	it("forgives one fast sample", function()
		local g = MovementGuard.new()
		MovementGuard.step(g, at(0, 0), 16)
		expect(MovementGuard.step(g, at(0.1, 8), 16)).toBeNil()
		expect(MovementGuard.step(g, at(0.2, 9.5), 16)).toBeNil()
		expect(MovementGuard.step(g, at(0.3, 11), 16)).toBeNil()
	end)

	it("lets a lag freeze catch up without a flag", function()
		local g = MovementGuard.new()
		MovementGuard.step(g, at(0, 0), 16)
		for i = 1, 12 do
			expect(MovementGuard.step(g, at(i / 10, 0), 16)).toBeNil() -- the server hears nothing new
		end
		expect(MovementGuard.step(g, at(1.3, 20), 16)).toBeNil()
		expect(MovementGuard.step(g, at(1.4, 21.6), 16)).toBeNil()
	end)

	it("still flags a teleport after standing still", function()
		local g = MovementGuard.new()
		MovementGuard.step(g, at(0, 0), 16)
		for i = 1, 50 do
			MovementGuard.step(g, at(i / 10, 0), 16)
		end
		expect(MovementGuard.step(g, at(5.1, 100), 16)).toBe("teleport")
	end)

	it("lets a server launch through and ignores the rise inside it", function()
		local g = MovementGuard.new()
		MovementGuard.step(g, at(0, 0), 22)
		MovementGuard.allow(g, 0, 1.5, 120)
		for i = 1, 10 do
			expect(MovementGuard.step(g, at(i / 10, i * 10, 5 + i * 9), 22)).toBeNil()
		end
	end)

	it("flags flying straight up", function()
		local g = MovementGuard.new()
		MovementGuard.step(g, at(0, 0, 5), 16)
		expect(MovementGuard.step(g, at(0.1, 0.5, 15), 16)).toBe("fly")
	end)

	it("allows a normal jump", function()
		local g = MovementGuard.new()
		MovementGuard.step(g, at(0, 0, 5), 16)
		expect(MovementGuard.step(g, at(0.1, 1.6, 10), 16)).toBeNil()
	end)

	it("lets a slide run faster than walking while it loses height", function()
		local g = MovementGuard.new()
		for i = 0, 30 do -- 45 studs/s down a 30-degree slope
			local x = 4.5 * i
			expect(MovementGuard.step(g, at(i / 10, x, 100 - x * 0.58), 16)).toBeNil()
		end
	end)

	it("forgets the last point on reset", function()
		local g = MovementGuard.new()
		MovementGuard.step(g, at(0, 0), 16)
		MovementGuard.reset(g)
		expect(MovementGuard.step(g, at(0.1, 300), 16)).toBeNil()
		expect(MovementGuard.step(g, at(0.2, 301.5), 16)).toBeNil()
	end)

	it("takes option overrides and refuses unknown ones", function()
		local g = MovementGuard.new({ teleportStuds = 200 })
		MovementGuard.step(g, at(0, 0), 16)
		expect(MovementGuard.step(g, at(0.1, 120), 16)).toBeNil()
		expect(function()
			MovementGuard.new({ nope = 1 })
		end).toThrow()
	end)
end)
