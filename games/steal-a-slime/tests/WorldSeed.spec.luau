--!strict
local Rng = require("../src/shared/Rng")
local TestRunner = require("./TestRunner")
local World = require("../src/server/World")
local WorldSeed = require("../src/server/WorldSeed")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("WorldSeed.pick", function()
	it("takes both seeds from the given random source, in range", function()
		local asked = {}
		local feed = { 123456, 654321 }
		local seeds = WorldSeed.pick(function(min, max)
			table.insert(asked, { min, max })
			return table.remove(feed, 1) :: number
		end)
		expect(seeds.world).toBe(123456)
		expect(seeds.egg).toBe(654321)
		expect(asked).toEqual({ { 1, WorldSeed.MAX }, { 1, WorldSeed.MAX } })
	end)
	it("gives the egg generator a seed that is not an offset of the world seed", function()
		local source = Rng.new(99)
		local seeds = WorldSeed.pick(function(min, max)
			return source:int(min, max)
		end)
		expect(seeds.egg ~= seeds.world + 7919).toBe(true)
	end)
end)

describe("World.new seeds", function()
	it("uses the egg seed it is given", function()
		local world = World.new({ now = 0, seed = 5, eggSeed = 777 })
		expect(world.rng.state).toBe(5)
		expect(world.eggRng.state).toBe(777)
	end)
	it("still derives the egg seed from the world seed when none is given", function()
		local a = World.new({ now = 0, seed = 5 })
		local b = World.new({ now = 0, seed = 5 })
		expect(a.eggRng.state).toBe(b.eggRng.state)
	end)
end)
