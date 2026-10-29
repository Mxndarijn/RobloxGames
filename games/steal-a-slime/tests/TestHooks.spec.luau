--!strict
-- TestHooks guard (CONTRACT.md §8.12): off by default, only AdminService in src/ calls it, place check refuses memory mode.
local fs = require("@lune/fs")

local Fixtures = require("./Fixtures")
local ServerFixtures = require("./ServerFixtures")
local TestHooks = require("../src/server/TestHooks")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function luauFiles(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			luauFiles(path, out)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(out, path)
		end
	end
	return out
end

describe("TestHooks", function()
	it("errors until enabled", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1)
		expect(TestHooks.isEnabled(world)).toBe(false)
		expect(function()
			TestHooks.grantCash(world, 1, 100)
		end).toThrow()
		expect(function()
			TestHooks.skipTime(world, 10)
		end).toThrow()
	end)
	it("grants cash (not counted as earned) and skips time with income", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, { Fixtures.slime("a", 1) }, 0)
		expect(TestHooks.enable(world)).toBe(true)
		TestHooks.grantCash(world, 1, 1000)
		expect(s.data.cash).toBe(1000)
		expect(s.data.totalEarned).toBe(0)
		local lock = s.lockUntil
		TestHooks.skipTime(world, 100)
		expect(s.data.cash > 1000).toBe(true)
		expect(s.lockUntil).toBe(lock - 100)
	end)
	it("is referenced by no src/ file but AdminService (the admin menu)", function()
		local offenders = {}
		for _, path in luauFiles("src", {}) do
			if
				not string.find(path, "TestHooks.luau", 1, true)
				and not string.find(path, "server/AdminService.luau", 1, true)
				and string.find(fs.readFile(path), "TestHooks", 1, true)
			then
				table.insert(offenders, path)
			end
		end
		expect(offenders).toEqual({})
	end)
end)
