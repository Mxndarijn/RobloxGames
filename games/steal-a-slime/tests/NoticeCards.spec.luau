--!strict
-- Notice cards (contract/notice-cards.md): shared/NoticeCards and where the server adds them.
local Carry = require("../src/server/Carry")
local Fixtures = require("./Fixtures")
local NoticeCards = require("../src/shared/NoticeCards")
local ServerFixtures = require("./ServerFixtures")
local SlimeGuard = require("../src/server/SlimeGuard")
local Snapshot = require("../src/server/Snapshot")
local StealService = require("../src/server/StealService")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

-- Owner 1 has "gem" on an unlocked plot; thief 2 carries it off at T0 + 1.
local function stealing()
	local world = ServerFixtures.world()
	local owner = ServerFixtures.join(world, 1, { Fixtures.slime("gem", 4) })
	local thief = ServerFixtures.join(world, 2)
	ServerFixtures.unlock(owner)
	expect((Carry.grab(world, 2, "gem", 1, T0 + 1))).toBe(true)
	return world, owner, thief
end

local function ids(list: { NoticeCards.Notice }?): string
	local parts = {}
	for _, notice in list or {} do
		table.insert(parts, notice.id)
	end
	return table.concat(parts, ",")
end

describe("NoticeCards", function()
	it("keeps notices only while they show, and at most CAP", function()
		local list = {}
		NoticeCards.add(list, { id = "Bonked", at = 0 }, 0)
		NoticeCards.add(list, { id = "SlimeHome", at = 10, name = "Ann" }, 10) -- the Bonked one is over
		expect(ids(list)).toBe("SlimeHome")
		for i = 1, NoticeCards.CAP + 2 do
			NoticeCards.add(list, { id = "Bonked", at = 10 + i * 0.1 }, 10 + i * 0.1)
		end
		expect(#list).toBe(NoticeCards.CAP)
		expect(#NoticeCards.live(list, 10.5)).toBe(NoticeCards.CAP)
		expect(#NoticeCards.live(list, 100)).toBe(0)
		expect(#NoticeCards.live(nil, 0)).toBe(0)
	end)
end)

describe("notices from the server", function()
	it("a bonked thief gets Bonked and the owner SlimeHome with the thief's name", function()
		local world, owner, thief = stealing()
		StealService.escape(world, thief, T0 + 2, "slap")
		expect(ids(thief.notices)).toBe("Bonked")
		expect(ids(owner.notices)).toBe("SlimeHome")
		expect((owner.notices :: any)[1].name).toBe(thief.name)
		local state = Snapshot.build(world, owner, T0 + 2)
		expect(ids(state.notices)).toBe("SlimeHome")
		expect(#Snapshot.build(world, owner, T0 + 2 + NoticeCards.seconds("SlimeHome")).notices).toBe(0)
	end)

	it("a dropped stolen slime tells only the owner", function()
		local world, owner, thief = stealing()
		StealService.escape(world, thief, T0 + 2, "drop")
		expect(ids(thief.notices)).toBe("")
		expect(ids(owner.notices)).toBe("SlimeHome")
	end)

	it("walking into a locked base says when it opens", function()
		local world, owner, thief = stealing()
		owner.lockUntil = T0 + 40
		SlimeGuard.intruded(world, thief, owner.plotIndex, T0 + 3, false)
		local notices = Snapshot.build(world, thief, T0 + 3).notices
		expect(ids(notices)).toBe("BaseLocked") -- the carried slime went home (guard): no Bonked
		expect(notices[1].opensAt).toBe(T0 + 40)
		expect(ids(owner.notices)).toBe("SlimeHome")
	end)

	it("plotFull shows only while carrying", function()
		local world, _, thief = stealing()
		thief.plotFull = true
		expect(Snapshot.build(world, thief, T0 + 2).plotFull).toBe(true)
		thief.carry = nil
		expect(Snapshot.build(world, thief, T0 + 2).plotFull).toBe(false)
	end)
end)
