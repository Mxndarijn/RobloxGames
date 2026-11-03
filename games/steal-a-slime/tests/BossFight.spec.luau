--!strict
-- The pure boss fight (src/shared/BossFight.luau, contract/boss-event.md): phases, the meter that scales with fighters,
-- the drain and its stage floor, stages, fail paths, who may grab, the top contributor's head start and the slap drop.
local BossFight = require("../src/shared/BossFight")
local Config = require("../src/shared/Config")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local BOSS = Config.BOSS
local T0 = 1000

-- A fight that has just arrived (phase "fight") at T0.
local function fighting(): BossFight.State
	local state = BossFight.new("goozilla", T0 - BOSS.WARNING_SECONDS)
	local events = BossFight.step(state, T0, 0)
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
		expect(#BossFight.step(state, T0 + BOSS.WARNING_SECONDS - 0.1, 0.1)).toBe(0)
		expect(kinds(BossFight.step(state, T0 + BOSS.WARNING_SECONDS, 0.1))).toBe("fight")
		expect(state.phase).toBe("fight")
		expect(state.endsAt).toBe(T0 + BOSS.WARNING_SECONDS + BOSS.FIGHT_SECONDS)
	end)
	it("ignores hits outside the fight", function()
		local state = BossFight.new("goozilla", T0)
		expect((BossFight.hit(state, 1, T0))).toBe(false)
		expect(state.meter).toBe(0)
	end)
end)

describe("BossFight meter", function()
	it("a lone fighter needs POINTS_PER_PLAYER hits, whoever else is on the server", function()
		local state = fighting()
		expect(BossFight.fighters(state, T0)).toBe(1)
		hits(state, 1, 10, T0)
		expect(BossFight.meter(state)).toBeCloseTo(10 / BOSS.POINTS_PER_PLAYER, 1e-9)
	end)
	it("counts a fighter from FIGHTER_MIN_HITS hits in FIGHTER_WINDOW, until they stop", function()
		local state = fighting()
		local t = hits(state, 1, 10, T0)
		hits(state, 2, BOSS.FIGHTER_MIN_HITS - 1, T0)
		expect(BossFight.fighters(state, t)).toBe(1) -- one hit short
		hits(state, 2, 1, t)
		expect(BossFight.fighters(state, t)).toBe(2)
		expect(BossFight.fighters(state, T0 + BOSS.FIGHTER_WINDOW + 10)).toBe(1) -- both stopped long ago: at least one
	end)
	it("each hit is worth less with more fighters, so a group needs the same hits each", function()
		local state = fighting()
		local t = hits(state, 1, BOSS.FIGHTER_MIN_HITS, T0)
		hits(state, 2, BOSS.FIGHTER_MIN_HITS, T0)
		local before = state.meter
		BossFight.hit(state, 1, t)
		expect(state.meter - before).toBeCloseTo(1 / (BOSS.POINTS_PER_PLAYER * 2), 1e-9)
	end)
	it("the bar never drops when a fighter joins or leaves", function()
		local state = fighting()
		local t = hits(state, 1, 40, T0)
		local before = state.meter
		hits(state, 2, BOSS.FIGHTER_MIN_HITS, t) -- player 2 joins: only their own hits move it
		local joined = state.meter
		expect(joined > before).toBe(true)
		local later = t + BOSS.FIGHTER_WINDOW + 1
		BossFight.step(state, later, 0) -- both stopped: dt 0 drains nothing
		expect(BossFight.fighters(state, later)).toBe(1)
		expect(BossFight.meter(state)).toBeCloseTo(joined, 1e-9)
	end)
	it("counts one point per player per HIT_GAP", function()
		local state = fighting()
		expect((BossFight.hit(state, 1, T0))).toBe(true)
		local ok, reason = BossFight.hit(state, 1, T0 + BOSS.HIT_GAP / 2)
		expect(ok).toBe(false)
		expect(reason).toBe("too fast")
		expect((BossFight.hit(state, 2, T0 + 0.1))).toBe(true) -- another player is not rate limited by player 1
		expect((BossFight.hit(state, 1, T0 + BOSS.HIT_GAP))).toBe(true)
		expect(state.meter).toBeCloseTo(3 / BOSS.POINTS_PER_PLAYER, 1e-9)
		expect(state.contributions[1]).toBe(2)
		expect(state.contributions[2]).toBe(1)
	end)
	it("a solo player fills it in time", function()
		local state = fighting()
		local t = T0
		local events = {}
		while state.phase == "fight" do
			BossFight.hit(state, 1, t)
			for _, e in BossFight.step(state, t, BOSS.HIT_GAP) do
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
	it("drains DRAIN_PER_SECOND of the meter per second once nobody hit for DRAIN_GRACE", function()
		local state = fighting()
		local t = hits(state, 1, 10, T0)
		local last = t - BOSS.HIT_GAP
		local full = 10 / BOSS.POINTS_PER_PLAYER
		BossFight.step(state, last + BOSS.DRAIN_GRACE / 2, 1)
		expect(state.meter).toBeCloseTo(full, 1e-9) -- inside the grace
		BossFight.step(state, last + BOSS.DRAIN_GRACE, 1)
		expect(state.meter).toBeCloseTo(full - BOSS.DRAIN_PER_SECOND, 1e-9)
		for i = 1, 100 do
			BossFight.step(state, last + BOSS.DRAIN_GRACE + i, 1)
		end
		expect(state.meter).toBe(0)
		expect(state.contributions[1]).toBe(10) -- contributions never drain
	end)
	it("never drains below the last stage reached", function()
		local state = fighting()
		local quarter = math.ceil(BOSS.POINTS_PER_PLAYER * BOSS.STAGE_EVERY)
		local t = hits(state, 1, quarter + 4, T0)
		BossFight.step(state, t, 0)
		expect(state.stage).toBe(1)
		BossFight.step(state, t + BOSS.DRAIN_GRACE + 300, 300)
		expect(state.meter).toBeCloseTo(BOSS.STAGE_EVERY, 1e-9)
	end)
	it("never reaches the same stage twice after a heal", function()
		local state = fighting()
		local quarter = math.ceil(BOSS.POINTS_PER_PLAYER * BOSS.STAGE_EVERY)
		local t = hits(state, 1, quarter, T0)
		expect(kinds(BossFight.step(state, t, 0))).toBe("stage")
		BossFight.heal(state, 0.1) -- Queen Jelly's heal may take it below the quarter
		expect(state.meter < BOSS.STAGE_EVERY).toBe(true)
		t = hits(state, 1, 15, t + 1)
		expect(#BossFight.step(state, t, 0)).toBe(0)
		expect(state.stage).toBe(1)
	end)
end)

describe("BossFight fail paths", function()
	it("fails when the meter isn't full by the fight deadline", function()
		local state = fighting()
		hits(state, 1, 3, T0)
		local events = BossFight.step(state, T0 + BOSS.FIGHT_SECONDS, 0)
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
		expect(kinds(BossFight.step(state, t, 0))).toBe("stage,haul")
		BossFight.grab(state, 1)
		local events = BossFight.step(state, t + BOSS.HAUL_SECONDS, 0)
		expect(kinds(events)).toBe("fail")
		expect((events[1] :: any).reason).toBe("haul")
		expect(state.carrierUserId).toBeNil()
	end)
end)

describe("BossFight haul", function()
	-- Player 2 hits 6 and player 3 hits once at the start; player 1 hits until the meter is full. Player 4 never hits.
	local function hauled(): (BossFight.State, number)
		local state = fighting()
		hits(state, 2, 6, T0)
		BossFight.hit(state, 3, T0)
		local t = T0
		while state.phase == "fight" do
			BossFight.hit(state, 1, t)
			BossFight.step(state, t, 0)
			t += BOSS.HIT_GAP
		end
		assert(state.phase == "haul", "meter full")
		return state, t
	end
	it("after the head start anyone may grab it, even a player who never hit it", function()
		local state, t = hauled()
		expect((BossFight.canGrab(state, 4, t + BOSS.PRIORITY_SECONDS, true))).toBe(true)
	end)
	it("the top contributor alone may grab for PRIORITY_SECONDS, then anyone", function()
		local state, t = hauled()
		t -= BOSS.HIT_GAP -- the hit that filled it
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
		expect((BossFight.canGrab(state, 2, t, false))).toBe(true)
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
		expect(BossFight.share(state, 2)).toBeCloseTo(6 / state.contributions[1], 1e-9)
		expect(BossFight.share(state, 99)).toBe(0)
	end)
	it("each player's percent is their points over everyone's", function()
		local state = hauled()
		expect(BossFight.percent(state, 2)).toBeCloseTo(6 / (state.contributions[1] + 7), 1e-9)
		local sum = BossFight.percent(state, 1) + BossFight.percent(state, 2) + BossFight.percent(state, 3)
		expect(sum).toBeCloseTo(1, 1e-9)
		expect(BossFight.percent(state, 99)).toBe(0)
	end)
	it("a win ends the event with the winner", function()
		local state, t = hauled()
		BossFight.win(state, 2, t + 10)
		expect(state.phase).toBe("won")
		expect(state.winnerUserId).toBe(2)
		expect(BossFight.meter(state)).toBe(1)
		expect(BossFight.over(state, t + 10 + BOSS.LINGER_SECONDS)).toBe(true)
	end)
end)
