--!strict
-- Daily quests (src/shared/Quests): roll determinism per UTC day, progress, claim once, reset.
local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local PlayerData = require("../src/shared/PlayerData")
local Quests = require("../src/shared/Quests")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local DAY = 86400
local D10 = 10 * DAY + 100 -- some time on UTC day 10

local function ids(data: PlayerData.Data): { string }
	local out = {}
	for _, slot in data.quests.slots do
		table.insert(out, `{slot.id}:{slot.target}`)
	end
	return out
end

local function rolled(userId: number, now: number): PlayerData.Data
	local data = PlayerData.new()
	Quests.sync(data, now, userId)
	return data
end

-- Raises the stat behind slot `i` to its target and returns the slot's pool def.
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

describe("Quests.sync / roll", function()
	it("rolls count distinct pool quests with valid targets", function()
		local data = rolled(7, D10)
		expect(#data.quests.slots).toBe(Config.DAILY_QUESTS.count)
		expect(data.quests.day).toBe(10)
		local seen = {}
		for _, slot in data.quests.slots do
			expect(seen[slot.id]).toBe(nil)
			seen[slot.id] = true
			local ok = false
			for _, def in Config.DAILY_QUESTS.pool do
				if def.id == slot.id then
					ok = table.find(def.choices, slot.target) ~= nil
				end
			end
			expect(ok).toBe(true)
		end
	end)
	it("is deterministic per day and player, and keeps the day's quests when synced again", function()
		local a, b = rolled(7, D10), rolled(7, D10 + 5000)
		expect(ids(a)).toEqual(ids(b))
		expect(Quests.sync(a, D10 + 9000, 7)).toBe(false)
		local changes = 0
		for day = 11, 40 do
			if table.concat(ids(rolled(7, day * DAY)), ",") ~= table.concat(ids(a), ",") then
				changes += 1
			end
		end
		expect(changes > 20).toBe(true)
		local others = 0
		for userId = 100, 140 do
			if table.concat(ids(rolled(userId, D10)), ",") ~= table.concat(ids(a), ",") then
				others += 1
			end
		end
		expect(others > 20).toBe(true)
	end)
	it("resets at UTC midnight: new day, new slots, nothing claimed", function()
		local data = rolled(7, D10)
		finish(data, 1)
		expect(Quests.claim(data, 1, D10, 7)).toBe(true)
		expect(Quests.sync(data, 11 * DAY - 1, 7)).toBe(false)
		expect(Quests.sync(data, 11 * DAY, 7)).toBe(true)
		expect(data.quests.day).toBe(11)
		for _, slot in data.quests.slots do
			expect(slot.claimed).toBe(false)
		end
		expect(Quests.view(data, 11 * DAY).resetsIn).toBe(DAY)
	end)
end)

describe("Quests progress and claim", function()
	it("counts only what was gained since the roll", function()
		local data = PlayerData.new()
		data.stats.caught, data.stats.merges, data.stats.locks = 50, 50, 50
		data.totalStolen, data.totalEarned, data.rebirths = 50, 5e9, 3
		Quests.sync(data, D10, 1)
		local view = Quests.view(data, D10)
		for _, q in view.quests do
			expect(q.progress).toBe(0)
			expect(q.done).toBe(false)
		end
		finish(data, 1)
		local first = Quests.view(data, D10).quests[1]
		expect(first.progress).toBe(first.target)
		expect(first.done).toBe(true)
	end)
	it("claims a finished quest once, pays cash x rebirth multiplier or a boost", function()
		local data = rolled(7, D10)
		expect(Quests.claim(data, 1, D10, 7)).toBe(false) -- not finished
		for i = 1, #data.quests.slots do
			finish(data, i)
		end
		local cash0 = data.cash
		for i, slot in data.quests.slots do
			local def
			for _, d in Config.DAILY_QUESTS.pool do
				if d.id == slot.id then
					def = d
				end
			end
			local cash, boostUntil = data.cash, data.boostUntil
			local ok = Quests.claim(data, i, D10, 7)
			expect(ok).toBe(true)
			if def.reward.kind == "cash" then
				expect(data.cash - cash).toBe(math.floor(def.reward.amount * Economy.rebirthMultiplier(data.rebirths)))
			else
				expect(data.boostMult).toBe(def.reward.mult)
				expect(data.boostUntil > boostUntil).toBe(true)
			end
			local again, message = Quests.claim(data, i, D10, 7)
			expect(again).toBe(false)
			expect(message).toBe("already claimed")
		end
		expect(data.cash >= cash0).toBe(true)
		expect(select(2, Quests.claim(data, 9, D10, 7))).toBe("no such quest")
	end)
	it("does not let yesterday's finished quest pay after the reset", function()
		local data = rolled(7, D10)
		finish(data, 1)
		local ok = Quests.claim(data, 1, 11 * DAY + 5, 7) -- syncs first: the progress is gone
		expect(ok).toBe(false)
	end)
end)

describe("Quests save and action", function()
	it("round-trips through SaveData and defaults when missing or bad", function()
		local data = rolled(7, D10)
		finish(data, 2)
		Quests.claim(data, 2, D10, 7)
		local back = SaveData.deserialize(SaveData.serialize(data, D10))
		expect(back.quests).toEqual(data.quests)
		local old = SaveData.serialize(data, D10)
		old.quests = nil
		expect(SaveData.deserialize(old).quests).toEqual({ day = 0, slots = {} })
		old.quests = { day = 5, slots = { { id = "Gone", target = 3 }, "x" } }
		expect(#SaveData.deserialize(old).quests.slots).toBe(0)
	end)
	it("ClaimQuest routes through Actions, validates the slot and claims once", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1, nil, 0)
		local ctx: Actions.Context = {
			distanceBetween = function()
				return 2
			end,
			positionOf = function()
				return "pos"
			end,
		}
		local now = ServerFixtures.T0 + 100
		local function claim(index: any)
			s.limiter = {}
			return Actions.handle(world, 1, "ClaimQuest", { index }, now, ctx)
		end
		Quests.sync(s.data, now, 1)
		expect(claim(1).message).toBe("not finished yet")
		expect(claim(1.5).message).toBe("no such quest")
		expect(claim(0).message).toBe("no such quest")
		finish(s.data, 1)
		expect(claim(1).ok).toBe(true)
		expect(claim(1).message).toBe("already claimed")
	end)
end)
