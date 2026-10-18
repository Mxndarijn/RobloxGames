--!strict
local Migrations = require("../src/core/Migrations")
local T = require("../testing/TestRunner")
local describe, it, expect = T.describe, T.it, T.expect

local STEPS: Migrations.Steps = {
	[0] = function(raw)
		raw.coins = raw.cash or 0
		raw.cash = nil
		return raw
	end,
	[1] = function(raw)
		raw.pets = raw.pets or {}
		return raw
	end,
}

describe("Migrations.run", function()
	it("treats nil and non-tables as fresh", function()
		local data, status = Migrations.run(nil, STEPS, 2)
		expect(data).toBeNil()
		expect(status).toBe("fresh")
		expect(select(2, Migrations.run("junk", STEPS, 2))).toBe("fresh")
		expect(select(2, Migrations.run(5, STEPS, 2))).toBe("fresh")
	end)

	it("treats an unusable version as fresh", function()
		expect(select(2, Migrations.run({ version = "two" }, STEPS, 2))).toBe("fresh")
		expect(select(2, Migrations.run({ version = 1.5 }, STEPS, 2))).toBe("fresh")
		expect(select(2, Migrations.run({ version = -1 }, STEPS, 2))).toBe("fresh")
		expect(select(2, Migrations.run({ version = 0 / 0 }, STEPS, 2))).toBe("fresh")
	end)

	it("runs every step from an unversioned table and stamps the version", function()
		local data, status = Migrations.run({ cash = 7 }, STEPS, 2)
		expect(status).toBe("ok")
		expect(data).toEqual({ coins = 7, pets = {}, version = 2 })
	end)

	it("runs only the steps above the stored version", function()
		local data, status = Migrations.run({ version = 1, coins = 3, cash = 99 }, STEPS, 2)
		expect(status).toBe("ok")
		expect(data).toEqual({ version = 2, coins = 3, cash = 99, pets = {} })
	end)

	it("returns a current table unchanged in content", function()
		local raw = { version = 2, coins = 1, pets = { "a" } }
		local data, status = Migrations.run(raw, STEPS, 2)
		expect(status).toBe("ok")
		expect(data).toEqual(raw)
	end)

	it("does not modify the caller's top-level table", function()
		local raw = { cash = 7 }
		Migrations.run(raw, STEPS, 2)
		expect(raw).toEqual({ cash = 7 })
	end)

	it("returns a newer record untouched with status newer", function()
		local raw = { version = 3, futureField = true }
		local data, status = Migrations.run(raw, STEPS, 2)
		expect(status).toBe("newer")
		expect(data).toBe(raw)
		expect(raw).toEqual({ version = 3, futureField = true })
	end)

	it("uses a custom version field", function()
		local data, status = Migrations.run({ schema = 1 }, STEPS, 2, "schema")
		expect(status).toBe("ok")
		expect(data).toEqual({ schema = 2, pets = {} })
		expect(select(2, Migrations.run({ schema = 9 }, STEPS, 2, "schema"))).toBe("newer")
	end)

	it("raises on a missing step", function()
		expect(function()
			Migrations.run({ version = 0 }, { [1] = STEPS[1] }, 2)
		end).toThrow()
	end)

	it("raises when a step does not return a table", function()
		expect(function()
			Migrations.run({ version = 1 }, {
				[1] = function(_)
					return nil :: any
				end,
			}, 2)
		end).toThrow()
	end)

	it("raises on a bad latest", function()
		expect(function()
			Migrations.run({}, STEPS, -1)
		end).toThrow()
	end)
end)

describe("Migrations sanitizers", function()
	it("num keeps finite numbers and clamps them", function()
		expect(Migrations.num(5, 0)).toBe(5)
		expect(Migrations.num(-3, 0, 0)).toBe(0)
		expect(Migrations.num(500, 0, 0, 100)).toBe(100)
	end)

	it("num falls back to the default for junk", function()
		expect(Migrations.num("5", 1)).toBe(1)
		expect(Migrations.num(nil, 1)).toBe(1)
		expect(Migrations.num(0 / 0, 1)).toBe(1)
		expect(Migrations.num(math.huge, 1)).toBe(1)
	end)

	it("str keeps strings, cuts long ones and defaults junk", function()
		expect(Migrations.str("hello", "")).toBe("hello")
		expect(Migrations.str("hello", "", 3)).toBe("hel")
		expect(Migrations.str(12, "none")).toBe("none")
		expect(Migrations.str(nil, "none")).toBe("none")
	end)

	it("enum accepts values from a list", function()
		local allowed = { "red", "blue" }
		expect(Migrations.enum("blue", allowed, "red")).toBe("blue")
		expect(Migrations.enum("green", allowed, "red")).toBe("red")
		expect(Migrations.enum(nil, allowed, "red")).toBe("red")
	end)

	it("enum accepts values from a set", function()
		local allowed = { red = true, blue = true }
		expect(Migrations.enum("blue", allowed, "red")).toBe("blue")
		expect(Migrations.enum("green", allowed, "red")).toBe("red")
	end)
end)
