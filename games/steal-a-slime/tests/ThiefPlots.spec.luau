--!strict
-- Thief plots (CONTRACT.md §16): while a thief carries your slime you see their plot in red
-- (StealService.thiefPlots -> Player attribute ThiefPlots), and it clears the moment the steal ends.
local Carry = require("../src/server/Carry")
local Economy = require("../src/shared/Economy")
local Fixtures = require("./Fixtures")
local ServerFixtures = require("./ServerFixtures")
local Sessions = require("../src/server/Sessions")
local Snapshot = require("../src/server/Snapshot")
local StealService = require("../src/server/StealService")
local TestRunner = require("./TestRunner")
local ThiefPlots = require("../src/shared/ThiefPlots")
local World = require("../src/server/World")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local LATER = T0 + 1000 -- join locks long gone

-- Victims `1` and `3` own slimes; `2` is the thief. Everyone's join lock is lifted.
local function setup()
	local world = ServerFixtures.world()
	local v1 = ServerFixtures.join(world, 1, { Fixtures.slime("gem1", 4), Fixtures.slime("gem1b", 4) })
	local thief = ServerFixtures.join(world, 2, nil, 1e12)
	local v3 = ServerFixtures.join(world, 3, { Fixtures.slime("gem3", 4) })
	for _, s in { v1, thief, v3 } do
		ServerFixtures.unlock(s)
	end
	return world, v1, thief, v3
end

local function thiefSession(world: World.World): World.Session
	return World.session(world, 2) :: World.Session
end

describe("StealService.thiefPlots", function()
	it("shows the thief's plot to the victim only, while they carry the slime", function()
		local world, _, thief = setup()
		expect(#StealService.thiefPlots(world, 1)).toBe(0)
		expect((Carry.grab(world, 2, "gem1", 1, LATER))).toBe(true)
		local plots = StealService.thiefPlots(world, 1)
		expect(#plots).toBe(1)
		expect(plots[1]).toBe(thief.plotIndex)
		expect(#StealService.thiefPlots(world, 2)).toBe(0) -- the thief sees nothing
		expect(#StealService.thiefPlots(world, 3)).toBe(0) -- bystanders neither
	end)
	it("clears the moment the slime is stolen", function()
		local world = setup()
		expect((Carry.grab(world, 2, "gem1", 1, LATER))).toBe(true)
		expect((Carry.deposit(world, 2, LATER + 1))).toBe(true)
		expect(#StealService.thiefPlots(world, 1)).toBe(0)
	end)
	it("clears the moment the slime goes home", function()
		for _, reason in { "slap", "drop" } do
			local world = setup()
			expect((Carry.grab(world, 2, "gem1", 1, LATER))).toBe(true)
			StealService.escape(world, thiefSession(world), LATER + 1, reason)
			expect(#StealService.thiefPlots(world, 1)).toBe(0)
		end
	end)
	it("clears when the thief leaves", function()
		local world = setup()
		expect((Carry.grab(world, 2, "gem1", 1, LATER))).toBe(true)
		Sessions.leave(world, 2, LATER + 1)
		expect(#StealService.thiefPlots(world, 1)).toBe(0)
	end)
	it("lists several thieves' plots in ascending order, each victim only their own", function()
		local world, _, thief, v3 = setup()
		local thief4 = ServerFixtures.join(world, 4)
		local thief5 = ServerFixtures.join(world, 5)
		expect((Carry.grab(world, 5, "gem1", 1, LATER))).toBe(true)
		expect((Carry.grab(world, 2, "gem1b", 1, LATER))).toBe(true)
		expect((Carry.grab(world, 4, "gem3", 1, LATER))).toBe(true)
		local plots = StealService.thiefPlots(world, 1)
		expect(#plots).toBe(2)
		expect(plots[1] < plots[2]).toBe(true)
		expect(table.find(plots, thief.plotIndex) ~= nil and table.find(plots, thief5.plotIndex) ~= nil).toBe(true)
		local plots3 = StealService.thiefPlots(world, 3)
		expect(#plots3).toBe(1)
		expect(plots3[1]).toBe(thief4.plotIndex)
		expect(v3.userId).toBe(3)
	end)
end)

describe("Lock price after a theft", function()
	it("a thief pays the normal lock price right after robbing", function()
		local world, _, thief = setup()
		expect((Carry.grab(world, 2, "gem1", 1, LATER))).toBe(true)
		expect((Carry.deposit(world, 2, LATER))).toBe(true)
		local base = Economy.lockCost(World.incomeOf(world, thief))
		expect(Snapshot.build(world, thief, LATER).lockCost).toBe(base)
		local cash = thief.data.cash
		expect((StealService.buyLock(world, thief, LATER))).toBe(true)
		expect(cash - thief.data.cash).toBe(base)
	end)
end)

describe("ThiefPlots wire format", function()
	it("round-trips plot indexes and treats empty as nil", function()
		expect(ThiefPlots.format({})).toBeNil()
		expect(ThiefPlots.format({ 3 })).toBe("3")
		expect(ThiefPlots.format({ 3, 5 })).toBe("3,5")
		local back = ThiefPlots.parse("3,5")
		expect(#back).toBe(2)
		expect(back[1]).toBe(3)
		expect(back[2]).toBe(5)
	end)
	it("parse ignores junk, duplicates and non-strings", function()
		expect(#ThiefPlots.parse(nil)).toBe(0)
		expect(#ThiefPlots.parse(7)).toBe(0)
		expect(#ThiefPlots.parse("")).toBe(0)
		expect(#ThiefPlots.parse("a,0,-2,1.5,,4,4")).toBe(1)
		expect(ThiefPlots.parse("a,0,-2,1.5,,4,4")[1]).toBe(4)
	end)
end)
