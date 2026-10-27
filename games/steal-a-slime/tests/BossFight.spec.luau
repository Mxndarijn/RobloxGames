--!strict
-- The pure boss fight (src/shared/BossFight.luau, contract/boss-event.md): phases, the meter that scales with players,
-- the drain, stages, fail paths, the top contributor's head start and the slap drop.
local BossFight = require("../src/shared/BossFight")
local Config = require("../src/shared/Config")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local BOSS = Config.BOSS
local T0 = 1000

-- A fight that has just arrived (phase "fight") at T0.
local function fighting(): BossFight.State
	local state = BossFight.new("goozilla", T0 - BOSS.WARNING_SECONDS)
	local events = BossFight.step(state, T0, 0, 1)
	assert(#events == 1 and events[1].kind == "fight", "arrives")
	return state
end

-- `userId` lands `n` hits from `at`, one HIT_GAP apart; returns the time after the last.
local function hits(state: BossFight.State, userId: number, n: number, at: number): number
	local t = at
	for _ = 1, n do
		BossFight.hit(state, userId, t)
		t += BOSS.HIT_GAP
	end
	return t
end

local function kinds(events: { BossFight.Event }): string
	local out = {}
	for _, e in events do
		table.insert(out, e.kind)
	end
	return table.concat(out, ",")
end

describe("BossFight phases", function()
	it("warns for WARNING_SECONDS, then fights for at most FIGHT_SECONDS", function()
		local state = BossFight.new("queen_jelly", T0)
		expect(state.phase).toBe("warning")
		expect(state.endsAt).toBe(T0 + BOSS.WARNING_SECONDS)
		expect(BossFight.active(state)).toBe(true)
		expect(#BossFight.step(state, T0 + BOSS.WARNING_SECONDS - 0.1, 0.1, 3)).toBe(0)
		expect(kinds(BossFight.step(state, T0 + BOSS.WARNING_SECONDS, 0.1, 3))).toBe("fight")
		expect(state.phase).toBe("fight")
		expect(state.endsAt).toBe(T0 + BOSS.WARNING_SECONDS + BOSS.FIGHT_SECONDS)
	end)
	it("ignores hits outside the fight", function()
		local state = BossFight.new("goozilla", T0)
		expect((BossFight.hit(state, 1, T0))).toBe(false)
		expect(state.points).toBe(0)
	end)
end)

describe("BossFight meter", function()
	it("needs POINTS_PER_PLAYER x players, at least one player", function()
		expect(BossFight.target(0)).toBe(BOSS.POINTS_PER_PLAYER)
		expect(BossFight.target(1)).toBe(BOSS.POINTS_PER_PLAYER)
		expect(BossFight.target(6)).toBe(BOSS.POINTS_PER_PLAYER * 6)
		local state = fighting()
		hits(state, 1, 10, T0)
		expect(BossFight.meter(state, 1)).toBeCloseTo(10 / BOSS.POINTS_PER_PLAYER, 1e-9)
		expect(BossFight.meter(state, 4)).toBeCloseTo(10 / (BOSS.POINTS_PER_PLAYER * 4), 1e-9)
	end)
	it("counts one point per player per HIT_GAP", function()
		local state = fighting()
		expect((BossFight.hit(state, 1, T0))).toBe(true)
		local ok, reason = BossFight.hit(state, 1, T0 + BOSS.HIT_GAP / 2)
		expect(ok).toBe(false)
		expect(reason).toBe("too fast")
		expect((BossFight.hit(state, 2, T0 + 0.1))).toBe(true) -- another player is not rate limited by player 1
		expect((BossFight.hit(state, 1, T0 + BOSS.HIT_GAP))).toBe(true)
		expect(state.points).toBe(3)
		expect(state.contributions[1]).toBe(2)
		expect(state.contributions[2]).toBe(1)
	end)
	it("a solo player on a quiet server fills it in time", function()
		local state = fighting()
		local t = T0
		local events = {}
		while state.phase == "fight" do
			BossFight.hit(state, 1, t)
			for _, e in BossFight.step(state, t, BOSS.HIT_GAP, 1) do
				table.insert(events, e.kind)
			end
			t += BOSS.HIT_GAP
		end
		expect(state.phase).toBe("haul")
		expect(t - T0 < BOSS.FIGHT_SECONDS).toBe(true)
		expect(table.concat(events, ",")).toBe("stage,stage,stage,haul")
	end)
end)

describe("BossFight drain", function()
	it("drains DRAIN_PER_SECOND of the target per second once nobody hit for DRAIN_GRACE", function()
		local state = fighting()
		local t = hits(state, 1, 10, T0)
		local last = t - BOSS.HIT_GAP
		BossFight.step(state, last + BOSS.DRAIN_GRACE / 2, 1, 1)
		expect(state.points).toBe(10) -- inside the grace
		BossFight.step(state, last + BOSS.DRAIN_GRACE, 1, 1)
		expect(state.points).toBeCloseTo(10 - BOSS.DRAIN_PER_SECOND * BOSS.POINTS_PER_PLAYER, 1e-9)
		for i = 1, 100 do
			BossFight.step(state, last + BOSS.DRAIN_GRACE + i, 1, 1)
		end
		expect(state.points).toBe(0)
		expect(state.contributions[1]).toBe(10) -- contributions never drain
	end)
	it("never reaches the same stage twice after a drain", function()
		local state = fighting()
		local quarter = math.ceil(BOSS.POINTS_PER_PLAYER * BOSS.STAGE_EVERY)
		local t = hits(state, 1, quarter, T0)
		local events = BossFight.step(state, t, 0, 1)
		expect(kinds(events)).toBe("stage")
		BossFight.step(state, t + BOSS.DRAIN_GRACE + 5, 5, 1) -- drains below the quarter
		t = hits(state, 1, 3, t + BOSS.DRAIN_GRACE + 5)
		expect(#BossFight.step(state, t, 0, 1)).toBe(0)
		expect(state.stage).toBe(1)
	end)
end)

describe("BossFight fail paths", function()
	it("fails when the meter isn't full by the fight deadline", function()
		local state = fighting()
		hits(state, 1, 3, T0)
		local events = BossFight.step(state, T0 + BOSS.FIGHT_SECONDS, 0, 1)
		expect(kinds(events)).toBe("fail")
		expect((events[1] :: any).reason).toBe("fight")
		expect(state.phase).toBe("failed")
		expect(BossFight.active(state)).toBe(false)
		expect(BossFight.over(state, T0 + BOSS.FIGHT_SECONDS + BOSS.LINGER_SECONDS - 0.1)).toBe(false)
		expect(BossFight.over(state, T0 + BOSS.FIGHT_SECONDS + BOSS.LINGER_SECONDS)).toBe(true)
	end)
	it("fails when nobody brings it home by the haul deadline, carried or not", function()
		local state = fighting()
		local t = hits(state, 1, BOSS.POINTS_PER_PLAYER, T0)
		expect(kinds(BossFight.step(state, t, 0, 1))).toBe("stage,haul")
		BossFight.grab(state, 1)
		local events = BossFight.step(state, t + BOSS.HAUL_SECONDS, 0, 1)
		expect(kinds(events)).toBe("fail")
		expect((events[1] :: any).reason).toBe("haul")
		expect(state.carrierUserId).toBeNil()
	end)
end)

describe("BossFight haul", function()
	-- Player 1 hits 20, player 2 hits 6, player 3 hits 1: the meter fills on 2 players' target.
	local function hauled(): (BossFight.State, number)
		local state = fighting()
		local t = T0
		for i = 1, BOSS.POINTS_PER_PLAYER - 5 do -- with players 2 and 3 that fills the one-player meter
			BossFight.hit(state, 1, t)
			if i <= 6 then
				BossFight.hit(state, 2, t)
			end
			if i == 1 then
				BossFight.hit(state, 3, t)
			end
			t += BOSS.HIT_GAP
		end
		BossFight.step(state, t, 0, 1)
		assert(state.phase == "haul", "meter full")
		return state, t
	end
	it("the top contributor alone may grab for PRIORITY_SECONDS, then anyone", function()
		local state, t = hauled()
		expect(state.priorityUserId).toBe(1)
		expect(state.priorityUntil).toBe(t + BOSS.PRIORITY_SECONDS)
		local ok, reason = BossFight.canGrab(state, 2, t + 1, true)
		expect(ok).toBe(false)
		expect(reason).toBe("the top helper grabs first")
		expect((BossFight.canGrab(state, 1, t + 1, true))).toBe(true)
		expect((BossFight.canGrab(state, 2, t + BOSS.PRIORITY_SECONDS, true))).toBe(true)
	end)
	it("the head start ends early when the top contributor left", function()
		local state, t = hauled()
		expect((BossFight.canGrab(state, 2, t + 1, false))).toBe(true)
	end)
	it("a slap drop leaves it for anyone, and the deadline stays", function()
		local state, t = hauled()
		local deadline = state.endsAt
		BossFight.grab(state, 1)
		expect((BossFight.canGrab(state, 2, t + BOSS.PRIORITY_SECONDS, true))).toBe(false)
		BossFight.drop(state)
		expect(state.carrierUserId).toBeNil()
		expect((BossFight.canGrab(state, 2, t + BOSS.PRIORITY_SECONDS, true))).toBe(true)
		expect(state.endsAt).toBe(deadline)
	end)
	it("each player's share is their points over the top contribution", function()
		local state = hauled()
		expect(BossFight.share(state, 1)).toBe(1)
		expect(BossFight.share(state, 2)).toBeCloseTo(6 / (BOSS.POINTS_PER_PLAYER - 5), 1e-9)
		expect(BossFight.share(state, 99)).toBe(0)
	end)
	it("each player's percent is their points over everyone's", function()
		local state = hauled()
		expect(BossFight.percent(state, 2)).toBeCloseTo(6 / (BOSS.POINTS_PER_PLAYER + 2), 1e-9)
		local sum = BossFight.percent(state, 1) + BossFight.percent(state, 2) + BossFight.percent(state, 3)
		expect(sum).toBeCloseTo(1, 1e-9)
		expect(BossFight.percent(state, 99)).toBe(0)
	end)
	it("a win ends the event with the winner", function()
		local state, t = hauled()
		BossFight.win(state, 2, t + 10)
		expect(state.phase).toBe("won")
		expect(state.winnerUserId).toBe(2)
		expect(BossFight.meter(state, 5)).toBe(1)
		expect(BossFight.over(state, t + 10 + BOSS.LINGER_SECONDS)).toBe(true)
	end)
end)
