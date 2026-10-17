--!strict
-- Daily quests hardening (Quests, CONTRACT.md §8.8): old saves without the field, UTC day boundaries with
-- fractional server time, odd user ids, join / leave, repeated and bad ClaimQuest requests, Snapshot.
-- Cloud-eligible: pure require paths, no @lune.
local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local Milestones = require("../src/server/Milestones")
local PlayerData = require("../src/shared/PlayerData")
local Quests = require("../src/shared/Quests")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local Sessions = require("../src/server/Sessions")
local Snapshot = require("../src/server/Snapshot")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local DAY = 86400
local T0 = ServerFixtures.T0

local ctx: Actions.Context = {
	distanceBetween = function()
		return 2
	end,
	positionOf = function()
		return "pos"
	end,
}

-- Raises the stat behind slot `i` to its target.
local function finish(data: PlayerData.Data, i: number)
	local slot = data.quests.slots[i]
	if slot.id == "Catch" then
		data.stats.caught += slot.target
	elseif slot.id == "Steal" then
		data.totalStolen += slot.target
	elseif slot.id == "Earn" then
		data.totalEarned += slot.target
	elseif slot.id == "Merge" then
		data.stats.merges += slot.target
	elseif slot.id == "Lock" then
		data.stats.locks += slot.target
	elseif slot.id == "Rebirth" then
		data.rebirths += slot.target
	end
end

local function key(data: PlayerData.Data): string
	local out = {}
	for _, s in data.quests.slots do
		table.insert(out, `{s.id}:{s.target}`)
	end
	return table.concat(out, ",")
end

describe("Quests old and fresh saves", function()
	it("a fresh PlayerData has nothing rolled and its view is empty, not an error", function()
		local data = PlayerData.new()
		expect(data.quests.day).toBe(0)
		expect(#data.quests.slots).toBe(0)
		local view = Quests.view(data, T0)
		expect(#view.quests).toBe(0)
		expect(view.resetsIn > 0 and view.resetsIn <= DAY).toBe(true)
	end)
	it("an old save without the quests field (or with junk) loads, then rolls on the first sync", function()
		local raw = SaveData.serialize(PlayerData.new(), T0)
		for _, junk in { "nil", "string", "number", "slots-not-table", "slot-junk" } do
			local copy = table.clone(raw)
			if junk == "nil" then
				copy.quests = nil
			elseif junk == "string" then
				copy.quests = "x"
			elseif junk == "number" then
				copy.quests = 5
			elseif junk == "slots-not-table" then
				copy.quests = { day = "later", slots = 4 }
			else
				copy.quests = { day = -3, slots = { 1, "a", { id = 5 }, { id = "Catch" } } }
			end
			local data = SaveData.deserialize(copy)
			expect(type(data.quests.day)).toBe("number")
			Quests.sync(data, T0, 42)
			expect(#data.quests.slots).toBe(Config.DAILY_QUESTS.count)
			expect(data.quests.day).toBe(Quests.day(T0))
		end
	end)
	it("a saved slot with a missing target / base gets safe defaults and cannot be claimed for free", function()
		local raw = SaveData.serialize(PlayerData.new(), T0)
		raw.quests = { day = Quests.day(T0), slots = { { id = "Catch" } } }
		local data = SaveData.deserialize(raw)
		expect(#data.quests.slots).toBe(1)
		local slot = data.quests.slots[1]
		expect(slot.target >= 1).toBe(true)
		expect(slot.claimed).toBe(false)
		expect(Quests.claim(data, 1, T0, 1)).toBe(false)
	end)
	it("a claimed state survives a save / load on the same day and does not pay twice", function()
		local data = PlayerData.new()
		Quests.sync(data, T0, 9)
		finish(data, 1)
		expect(Quests.claim(data, 1, T0, 9)).toBe(true)
		local back = SaveData.deserialize(SaveData.serialize(data, T0))
		expect(Quests.sync(back, T0 + 60, 9)).toBe(false)
		local cash = back.cash
		local ok, message = Quests.claim(back, 1, T0 + 60, 9)
		expect(ok).toBe(false)
		expect(message).toBe("already claimed")
		expect(back.cash).toBe(cash)
	end)
end)

describe("Quests UTC day boundary", function()
	it("fractional server time rolls exactly at midnight, resetsIn never reaches 0 inside the day", function()
		local data = PlayerData.new()
		local midnight = 12 * DAY
		Quests.sync(data, midnight - 0.001, 3)
		expect(data.quests.day).toBe(11)
		expect(Quests.sync(data, midnight - 0.0005, 3)).toBe(false)
		expect(Quests.sync(data, midnight, 3)).toBe(true)
		expect(data.quests.day).toBe(12)
		expect(Quests.view(data, midnight).resetsIn).toBe(DAY)
		expect(Quests.view(data, midnight + DAY - 0.5).resetsIn).toBe(0.5)
	end)
	it("a view on a stale day is empty and a claim syncs first (cannot pay yesterday's quest)", function()
		local data = PlayerData.new()
		Quests.sync(data, 10 * DAY + 5, 3)
		finish(data, 1)
		expect(#Quests.view(data, 11 * DAY).quests).toBe(0)
		local cash = data.cash
		local ok = Quests.claim(data, 1, 11 * DAY, 3)
		expect(ok).toBe(false)
		expect(data.cash).toBe(cash)
		expect(data.quests.day).toBe(11)
	end)
	it("a player offline for weeks gets one fresh roll for the current day", function()
		local data = PlayerData.new()
		Quests.sync(data, 10 * DAY, 3)
		finish(data, 1)
		expect(Quests.sync(data, 40 * DAY + 1, 3)).toBe(true)
		expect(data.quests.day).toBe(40)
		for _, slot in data.quests.slots do
			expect(slot.claimed).toBe(false)
		end
	end)
	it("the clock going backwards keeps the saved quests and never pays them twice", function()
		local data = PlayerData.new()
		Quests.sync(data, 20 * DAY, 3)
		local before = key(data)
		expect(Quests.sync(data, 19 * DAY, 3)).toBe(true) -- day mismatch: re-rolls for the earlier day, deterministically
		expect(data.quests.day).toBe(19)
		expect(Quests.sync(data, 20 * DAY, 3)).toBe(true)
		expect(key(data)).toBe(before)
	end)
	it("rolls for odd user ids (Studio guests are negative, 0, huge) without erroring", function()
		for _, userId in { -1, -987654, 0, 1, 2 ^ 40, 1e10 } do
			local data = PlayerData.new()
			Quests.sync(data, T0, userId)
			expect(#data.quests.slots).toBe(Config.DAILY_QUESTS.count)
			local again = PlayerData.new()
			Quests.sync(again, T0 + 1000, userId)
			expect(key(again)).toBe(key(data))
		end
	end)
	it("every pool quest has a view: title without placeholders, positive target, known reward kind", function()
		for _, def in Config.DAILY_QUESTS.pool do
			for _, target in def.choices do
				local data = PlayerData.new()
				data.quests =
					{ day = Quests.day(T0), slots = { { id = def.id, target = target, base = 0, claimed = false } } }
				local q = Quests.view(data, T0).quests[1]
				expect(string.find(q.title, "<", 1, true)).toBeNil()
				expect(q.target).toBe(target)
				expect(q.rewardKind == "cash" or q.rewardKind == "boost").toBe(true)
				expect(#q.reward > 0).toBe(true)
			end
		end
	end)
end)

describe("Quests server integration", function()
	it("joining rolls today's quests and marks nothing claimed; State carries dailyQuests", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		expect(#s.data.quests.slots).toBe(Config.DAILY_QUESTS.count)
		local state = Snapshot.build(world, s, T0 + 1)
		expect(state.dailyQuests ~= nil).toBe(true)
		expect(#(state.dailyQuests :: any).quests).toBe(Config.DAILY_QUESTS.count)
	end)
	it("the Milestones step re-rolls after midnight, marks the session dirty, and State follows", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		local day = Quests.day(T0)
		local nextDay = (day + 1) * DAY + 0.5
		expect(#Snapshot.build(world, s, nextDay).dailyQuests.quests).toBe(0) -- stale until the step
		s.dirty = false
		Milestones.step(world, nextDay)
		expect(s.data.quests.day).toBe(day + 1)
		expect(s.dirty).toBe(true)
		expect(#Snapshot.build(world, s, nextDay).dailyQuests.quests).toBe(Config.DAILY_QUESTS.count)
	end)
	it("a player who left is a clean 'unknown' for ClaimQuest, and rejoining keeps the day's quests", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		local keyBefore = key(s.data)
		Sessions.leave(world, 1, T0 + 10)
		local result = Actions.handle(world, 1, "ClaimQuest", { 1 }, T0 + 11, ctx)
		expect(result.ok).toBe(false)
		local again = Sessions.join(world, 1, "P1", s.data, T0 + 20)
		expect(again ~= nil).toBe(true)
		expect(key((again :: any).data)).toBe(keyBefore)
	end)
	it("bad arguments are refused without erroring or paying", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		for i = 1, #s.data.quests.slots do
			finish(s.data, i)
		end
		local cash = s.data.cash
		local t = T0 + 100
		for _, bad in { "1", true, {}, 0, -1, 4, 1.5, 0 / 0, math.huge, -math.huge, 2 ^ 53 } do
			s.limiter = {}
			local r = Actions.handle(world, 1, "ClaimQuest", { bad }, t, ctx)
			expect(r.ok).toBe(false)
		end
		s.limiter = {}
		expect(Actions.handle(world, 1, "ClaimQuest", {}, t, ctx).ok).toBe(false)
		expect(Actions.handle(world, 1, "ClaimQuest", { 1, 2, 3 }, t + 1, ctx).ok).toBe(true) -- extra args ignored
		expect(s.data.cash >= cash).toBe(true)
	end)
	it("is rate limited: a second claim inside the interval is refused, then goes through", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		for i = 1, #s.data.quests.slots do
			finish(s.data, i)
		end
		local t = T0 + 100
		expect(Actions.handle(world, 1, "ClaimQuest", { 1 }, t, ctx).ok).toBe(true)
		local fast = Actions.handle(world, 1, "ClaimQuest", { 2 }, t + 0.05, ctx)
		expect(fast.ok).toBe(false)
		expect(s.data.quests.slots[2].claimed).toBe(false)
		expect(Actions.handle(world, 1, "ClaimQuest", { 2 }, t + 1, ctx).ok).toBe(true)
		expect(Actions.handle(world, 1, "ClaimQuest", { 2 }, t + 2, ctx).ok).toBe(false)
	end)
	it("a claim pays exactly once and notifies only the claimer", function()
		local world = ServerFixtures.world()
		local a = ServerFixtures.join(world, 1)
		local b = ServerFixtures.join(world, 2)
		finish(a.data, 1)
		local cashB = b.data.cash
		local ok = Actions.handle(world, 1, "ClaimQuest", { 1 }, T0 + 100, ctx).ok
		expect(ok).toBe(true)
		expect(#ServerFixtures.notifications(world, 1) >= 1).toBe(true)
		expect(b.data.cash).toBe(cashB)
		expect(b.data.quests.slots[1].claimed).toBe(false)
	end)
	it("a boost reward stacks onto a running boost instead of replacing it", function()
		local data = PlayerData.new()
		data.quests = { day = Quests.day(T0), slots = { { id = "Merge", target = 1, base = 0, claimed = false } } }
		data.stats.merges = 1
		data.boostMult, data.boostUntil = 2, T0 + 600
		expect(Quests.claim(data, 1, T0, 1)).toBe(true)
		expect(data.boostUntil).toBe(T0 + 600 + 5 * 60)
		expect(data.boostMult).toBe(2)
	end)
end)
