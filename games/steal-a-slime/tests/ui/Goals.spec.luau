--!strict
-- Local goals derived from State (src/ui/Goals.luau).
local Goals = require("../../src/ui/Goals")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local TIERS = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

local function slimes(tiers: { number }): { any }
	local out = {}
	for i, tier in tiers do
		out[i] = { slime = { id = `s{i}`, tier = tier } }
	end
	return out
end

local function base(): any
	return {
		cash = 1000,
		rebirths = 0,
		rebirthCost = 5000,
		canRebirth = false,
		padsUnlocked = 4,
		padsMax = 8,
		nextPadCost = 500,
		slimes = slimes({ 1, 2 }),
		dex = { found = 2, total = 50 },
		daily = { available = true, streak = 2, amount = 300, day = 3 },
		shop = {
			SpeedCoil = { price = nil, owned = true },
		},
	}
end

local function byId(goals: { Goals.Goal }): { [string]: Goals.Goal }
	local out = {}
	for _, g in goals do
		out[g.id] = g
	end
	return out
end

describe("Goals.derive", function()
	it("derives pad, daily, tier, rebirth, dex and shop goals from State", function()
		local g = byId(Goals.derive(base(), TIERS))
		expect(g.FillPads.detail).toBe("2/4 pads used")
		expect(g.FillPads.fraction).toBeCloseTo(0.5)
		expect(g.AllPads.detail).toBe("4/8 · next $500")
		local s = base()
		s.padsUnlocked, s.padsMax, s.nextPadCost = 16, 32, nil
		expect(byId(Goals.derive(s, TIERS)).AllPads.detail).toBe("16/32 · next: rebirth")
		expect(g.AllPads.done).toBe(false)
		expect(g.Daily.done).toBe(false)
		expect(g.Daily.detail).toBe("Day 3 pays $300")
		expect(g.BestTier.title).toBe("Own a Rare slime")
		expect(g.Rebirth.title).toBe("Reach your first rebirth")
		expect(g.Rebirth.fraction).toBeCloseTo(0.2)
		expect(g.Dex.title).toBe("Discover 5% of the SlimeDex")
		expect(g.Dex.detail).toBe("2/3 species (4%)")
		expect(g.SpeedCoil.done).toBe(true)
		expect(g.LockUpgrade).toBeNil() -- locks have no upgrade to max out
	end)
	it("marks finished goals and moves the dex milestone on", function()
		local s = base()
		s.padsUnlocked, s.nextPadCost = 8, nil
		s.slimes = slimes({ 6, 6, 6, 6, 6, 6, 6, 6 })
		s.daily.available = false
		s.canRebirth = true
		s.rebirths = 2
		s.dex = { found = 3, total = 50 }
		local g = byId(Goals.derive(s, TIERS))
		expect(g.FillPads.done).toBe(true)
		expect(g.AllPads.done).toBe(true)
		expect(g.Daily.detail).toBe("Claimed · streak 2")
		expect(g.BestTier.title).toBe("Own a Mythic slime")
		expect(g.BestTier.done).toBe(true)
		expect(g.Rebirth.title).toBe("Reach rebirth 3")
		expect(g.Rebirth.done).toBe(true)
		expect(g.Dex.title).toBe("Discover 10% of the SlimeDex")
	end)
	it("skips goals whose State fields are missing", function()
		local g = byId(Goals.derive({ padsUnlocked = 4, padsMax = 8 }, TIERS))
		expect(g.Daily).toBeNil()
		expect(g.Dex).toBeNil()
		expect(g.SpeedCoil).toBeNil()
		expect(g.BestTier.title).toBe("Own a Common slime")
		expect(#Goals.derive(nil, TIERS)).toBe(0)
	end)
end)

describe("Goals.sorted / summary", function()
	it("puts open goals first (closest first) and counts done ones", function()
		local goals: { Goals.Goal } = {
			{ id = "a", title = "", detail = "", fraction = 1, done = true },
			{ id = "b", title = "", detail = "", fraction = 0.2, done = false },
			{ id = "c", title = "", detail = "", fraction = 0.8, done = false },
			{ id = "d", title = "", detail = "", fraction = 0.2, done = false },
		}
		local ids = {}
		for i, g in Goals.sorted(goals) do
			ids[i] = g.id
		end
		expect(table.concat(ids, ",")).toBe("c,b,d,a")
		expect(Goals.summary(goals)).toBe("1/4 done")
	end)
end)

describe("Goals.fromServer (v13 State.goals)", function()
	it("maps staged server goals to rows", function()
		local rows = Goals.fromServer({
			{
				id = "Catch",
				title = "Catch 10 slimes",
				stat = "caught",
				progress = 4,
				stage = 1,
				stages = 5,
				target = 10,
				reward = 500,
				nextTitle = "Catch 50 slimes",
				done = false,
			},
			{
				id = "Lock",
				title = "Lock your base 100 times",
				stat = "locks",
				progress = 120,
				stage = 3,
				stages = 3,
				done = true,
			},
		}) :: { Goals.Goal }
		expect(#rows).toBe(2)
		expect(rows[1].title).toBe("Catch 10 slimes")
		expect(rows[1].detail).toBe("4/10 · reward $500 · stage 2/5")
		expect(rows[1].next).toBe("Next: Catch 50 slimes")
		expect(rows[2].next).toBeNil()
		expect(rows[1].fraction).toBeCloseTo(0.4)
		expect(rows[2].done).toBe(true)
		expect(rows[2].detail).toBe("All 3 stages done")
	end)
	it("returns nil on a server without goals and skips junk", function()
		expect(Goals.fromServer(nil)).toBeNil()
		expect(#(Goals.fromServer({ 1, { title = "no id" } }) :: { Goals.Goal })).toBe(0)
	end)
end)

describe("Goals.quests", function()
	local daily = {
		resetsIn = 3700,
		quests = {
			{
				id = "Catch",
				title = "Catch 5 slimes",
				icon = "Catch",
				progress = 9,
				target = 5,
				done = true,
				claimed = false,
				reward = "+$400",
			},
			{
				id = "Merge",
				title = "Merge 2 times",
				icon = "Merge",
				progress = 1,
				target = 2,
				done = false,
				claimed = false,
				reward = "2x income for 5m",
			},
			{
				id = "Lock",
				title = "x",
				icon = "Lock",
				progress = 3,
				target = 3,
				done = true,
				claimed = true,
				reward = "+$300",
			},
		},
	}
	it("maps State.dailyQuests to cards with slot index, capped progress and a reset line", function()
		local quests, resets = Goals.quests(daily)
		expect(#quests).toBe(3)
		expect(quests[1].index).toBe(1)
		expect(quests[1].detail).toBe("5/5")
		expect(quests[1].fraction).toBeCloseTo(1)
		expect(quests[2].fraction).toBeCloseTo(0.5)
		expect(quests[2].reward).toBe("2x income for 5m")
		expect(quests[3].claimed).toBe(true)
		expect(resets).toBe("Resets in 1:01:40")
	end)
	it("is empty on a server without daily quests", function()
		local quests, resets = Goals.quests(nil)
		expect(#quests).toBe(0)
		expect(resets).toBe("")
	end)
end)

describe("Goals row parts (reward, meta, next target, quest order)", function()
	local CONFIG =
		{ GOALS = { { id = "Catch", targets = { 1, 10, 50 } }, { id = "Earn", targets = { 1e9, 1e10 }, cash = true } } }
	it("splits a server goal into reward, meta line and the next stage's target", function()
		local rows = Goals.fromServer({
			{ id = "Catch", title = "Catch 10 slimes", progress = 4, stage = 1, stages = 3, target = 10, reward = 500 },
			{ id = "Earn", title = "Earn $10B", progress = 4.98e9, stage = 1, stages = 2, target = 1e10, reward = 5e8 },
			{ id = "Lock", title = "Lock 100 times", progress = 120, stage = 3, stages = 3, done = true },
		}, CONFIG) :: { Goals.Goal }
		expect(rows[1].reward).toBe("+$500")
		expect(rows[1].meta).toBe("4/10 · Stage 2 of 3")
		expect(rows[1].nextShort).toBe("Next: 50")
		expect(rows[2].meta).toBe("4.98B/10B · Last stage")
		expect(rows[2].nextShort).toBeNil()
		expect(rows[3].reward).toBeNil()
		expect(rows[3].meta).toBe("All 3 stages done")
		local plain = (Goals.fromServer({ { id = "Catch", progress = 4, stage = 0, stages = 3, target = 10 } }) :: any)[1]
		expect(plain.nextShort).toBeNil() -- no config: no next target
	end)
	it("flags boost rewards and sinks claimed quests below the open ones", function()
		local quests = Goals.quests({
			resetsIn = 10,
			quests = {
				{
					id = "A",
					progress = 1,
					target = 1,
					done = true,
					claimed = true,
					reward = "+$1",
					rewardKind = "cash",
				},
				{ id = "B", progress = 0, target = 2, reward = "2x income for 5m", rewardKind = "boost" },
				{ id = "C", progress = 0, target = 2, reward = "+$2", rewardKind = "cash" },
			},
		})
		expect(quests[1].boost).toBe(false)
		expect(quests[2].boost).toBe(true)
		local ids = {}
		for i, q in Goals.sortedQuests(quests) do
			ids[i] = q.id
		end
		expect(table.concat(ids, ",")).toBe("B,C,A")
	end)
end)
