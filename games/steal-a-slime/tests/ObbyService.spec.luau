--!strict
-- The Obby over World (src/server/ObbyService.luau, contract/obby.md): the portal, section progress in order, falls,
-- the finish and its boost, the cooldown, the rotation, the income bonus and State.obby.
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local ObbyCourse = require("../src/shared/ObbyCourse")
local ObbyLock = require("../src/server/ObbyLock")
local ObbyService = require("../src/server/ObbyService")
local Perks = require("../src/shared/Perks")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local Snapshot = require("../src/server/Snapshot")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local OBBY = Config.OBBY

-- 10 s into a rotation, so no test crosses into the next one by accident.
local T = ObbyCourse.slotStart(ObbyCourse.slot(ServerFixtures.T0) + 1) + 10

-- The portal in the yard, the course in its own world thousands of studs away.
local PLACE: ObbyService.Place = {
	frame = { origin = { 0, 400, -9000 }, yaw = 180 },
	portal = { -95, 0, 230 },
	portalRadius = 5,
	exit = { -92, 3, 222 },
	exitYaw = 337.5,
	zone = { centre = { 0, 400, -9150 }, radius = 1500 },
}

local function setup(): (any, any)
	local world = ServerFixtures.world(T)
	ServerFixtures.join(world, 1, nil, 0, T)
	ObbyService.setup(world, T)
	return world, world.sessions[1]
end

-- World position over section `i` (0 = the start pad, #spans + 1 = the finish pad), standing at its entry height.
local function onPad(world: any, i: number): { number }
	local course = world.obby
	local span = course.spans[i]
	local p
	if span then
		p = { (span.from + span.to) / 2, span.floor + 3, 0 }
	elseif i <= 0 then
		p = { course.start[1], 3, 0 }
	else
		p = { course.finish.pos[1], course.finish.pos[2] + 3, 0 }
	end
	return ObbyCourse.toWorld(PLACE.frame, p)
end

local function at(pos: { number }): { [number]: { number } }
	return { [1] = pos }
end

-- Steps into the portal at `now` (from outside it); returns the step result.
local function enter(world: any, now: number): ObbyService.Result
	ObbyService.step(world, PLACE, at({ 0, 3, 0 }), now - 0.1)
	return ObbyService.step(world, PLACE, at({ -95, 3, 230 }), now)
end

-- Walks every section, then the finish, `gap` seconds apart from `start`; returns the finish step's result and time.
local function runAll(world: any, start: number, gap: number): (ObbyService.Result, number)
	local now = start
	local result
	for i = 1, #world.obby.spans + 1 do
		now += gap
		result = ObbyService.step(world, PLACE, at(onPad(world, i)), now)
	end
	return result, now
end

-- The analytics events named `name` queued in world.outbox, oldest first.
local function analytics(world: any, name: string): { any }
	local out = {}
	for _, event in world.outbox do
		if event.type == "Analytics" and event.track and event.track.name == name then
			table.insert(out, event.track)
		end
	end
	return out
end

-- World position `extra` studs under the client's fall height over the middle of section `i`, plus the server's
-- slack unless `clientOnly`.
local function below(world: any, i: number, clientOnly: boolean?): { number }
	local span = world.obby.spans[i]
	local p = { (span.from + span.to) / 2, 0, 0 }
	local depth = OBBY.FALL_DEPTH + if clientOnly then 0 else OBBY.SERVER_FALL_SLACK
	p[2] = ObbyCourse.fallHeight(world.obby, p, depth) - 2
	return ObbyCourse.toWorld(PLACE.frame, p)
end

describe("ObbyService landing", function()
	it("leaves a standard avatar's move where it is", function()
		local spot = ObbyService.landing(PLACE.exit, OBBY.RESPAWN_LIFT)
		expect(spot[1]).toBe(PLACE.exit[1])
		expect(spot[2]).toBeCloseTo(PLACE.exit[2], 1e-9)
		expect(spot[3]).toBe(PLACE.exit[3])
	end)

	it("lifts a taller avatar so it lands on its feet, and lowers a smaller one", function()
		-- an R15 at body height 1.5: HipHeight 3.01 plus half its 3-stud root
		expect(ObbyService.landing(PLACE.exit, 4.51)[2]).toBeCloseTo(PLACE.exit[2] + 4.51 - OBBY.RESPAWN_LIFT, 1e-9)
		expect(ObbyService.landing(PLACE.exit, 2.4)[2]).toBeCloseTo(PLACE.exit[2] - (OBBY.RESPAWN_LIFT - 2.4), 1e-9)
	end)

	it("does not change the move it was given", function()
		local pos = { 1, 2, 3 }
		ObbyService.landing(pos, 5)
		expect(pos[2]).toBe(2)
	end)
end)

describe("ObbyService portal", function()
	it("stepping into the portal starts a run and lifts the player to the start pad", function()
		local world, session = setup()
		local result = enter(world, T)
		expect(session.obbyRun ~= nil).toBe(true)
		expect(session.obbyRun.section).toBe(0)
		expect(#result.moves).toBe(1)
		local start = ObbyCourse.toWorld(PLACE.frame, world.obby.start)
		expect(result.moves[1].pos[2]).toBe(start[2])
	end)

	it("standing in the portal does not start a second run, and needs a fresh step in", function()
		local world, session = setup()
		enter(world, T)
		ObbyService.cancel(session)
		local again = ObbyService.step(world, PLACE, at({ -95, 3, 230 }), T + 1)
		expect(#again.moves).toBe(0)
		expect(session.obbyRun).toBeNil()
	end)

	it("refuses a player carrying a slime", function()
		local world, session = setup()
		session.carry = { slimeId = "x", kind = "wild", slime = Fixtures.slime("x") } :: any
		local result = enter(world, T)
		expect(session.obbyRun).toBeNil()
		expect(#result.moves).toBe(0)
		local texts = ServerFixtures.notifications(world, 1)
		expect(texts[#texts]).toBe("Put your slime down first")
	end)
end)

describe("ObbyService runs", function()
	it("a clean run to the finish earns x1.5 income for 5 minutes and sets the player down by the portal", function()
		local world, session = setup()
		enter(world, T)
		local before = Perks.bonusMultiplier(session.data)
		local result, now = runAll(world, T, 8)
		expect(session.obbyRun).toBeNil()
		expect(session.data.obbyUntil).toBe(now + OBBY.BOOST_SECONDS)
		expect(session.data.obbyReadyAt).toBe(now + OBBY.BOOST_SECONDS + OBBY.COOLDOWN_SECONDS)
		expect(session.data.obbyBonus).toBe(OBBY.BONUS)
		expect(math.abs(Perks.bonusMultiplier(session.data) - before * (1 + OBBY.BONUS)) < 1e-9).toBe(true)
		expect(result.moves[1].pos[1]).toBe(PLACE.exit[1])
		expect(session.obbyBest.seconds).toBe(now - (T + 8)) -- the clock started on section 1
	end)

	it("counts the furthest section reached, in order", function()
		local world, session = setup()
		enter(world, T)
		ObbyService.step(world, PLACE, at(onPad(world, 1)), T + 5)
		expect(session.obbyRun.section).toBe(1)
		ObbyService.step(world, PLACE, at(onPad(world, 2)), T + 10)
		expect(session.obbyRun.section).toBe(2)
		ObbyService.step(world, PLACE, at(onPad(world, 1)), T + 12) -- walking back does not undo it
		expect(session.obbyRun.section).toBe(2)
		expect(session.obbyRun.invalid).toBeNil()
	end)

	it("skipping a section marks the run invalid: it finishes but earns nothing", function()
		local world, session = setup()
		enter(world, T)
		ObbyService.step(world, PLACE, at(onPad(world, 1)), T + 8)
		ObbyService.step(world, PLACE, at(onPad(world, 3)), T + 16)
		expect(session.obbyRun.invalid).toBe(true)
		runAll(world, T + 16, 8)
		expect(session.data.obbyUntil).toBe(0)
		local texts = ServerFixtures.notifications(world, 1)
		expect(texts[#texts]).toBe("That run didn't count. Try again!")
	end)

	it("teleporting straight to the finish earns nothing", function()
		local world, session = setup()
		enter(world, T)
		local result = ObbyService.step(world, PLACE, at(onPad(world, #world.obby.spans + 1)), T + 60)
		expect(session.obbyRun).toBeNil()
		expect(result.moves[1].pos[1]).toBe(PLACE.exit[1])
		expect(session.data.obbyUntil).toBe(0)
	end)

	it("a finish faster than the minimum run time earns nothing", function()
		local world, session = setup()
		enter(world, T)
		local gap = OBBY.MIN_RUN_SECONDS / (#world.obby.spans + 2)
		runAll(world, T + OBBY.MOVE_GRACE, gap)
		expect(session.data.obbyUntil).toBe(0)
		expect(session.data.obbyBonus).toBeNil()
		local texts = ServerFixtures.notifications(world, 1)
		expect(texts[#texts]).toBe("That run didn't count. Try again!")
	end)

	it("a finish during the cooldown counts the time but earns no boost", function()
		local world, session = setup()
		enter(world, T)
		-- a 72 s run, whatever the number of sections
		local _, now = runAll(world, T, 72 / (#world.obby.spans + 1))
		local untilAt = session.data.obbyUntil
		-- the next course (the cleared one refuses entry): boost over, still cooling down
		local later = ObbyCourse.slotStart(world.obby.slot + 1) + 10
		expect(later > untilAt and later + 60 < session.data.obbyReadyAt).toBe(true)
		ObbyService.refresh(world, later)
		enter(world, later)
		expect(session.obbyRun ~= nil).toBe(true)
		runAll(world, later, 5)
		expect(session.data.obbyUntil).toBe(untilAt)
		expect(session.data.obbyBonus).toBeNil()
		expect(now < later).toBe(true)
	end)

	it("a fall anywhere sends the runner back to the start pad; the clock and the sections done keep going", function()
		local world, session = setup()
		enter(world, T)
		ObbyService.step(world, PLACE, at(onPad(world, 1)), T + 8)
		ObbyService.step(world, PLACE, at(onPad(world, 2)), T + 16)
		local result = ObbyService.step(world, PLACE, at(below(world, 2)), T + 18)
		expect(#result.moves).toBe(1)
		local start = ObbyCourse.toWorld(PLACE.frame, world.obby.start)
		for k = 1, 3 do
			expect(math.abs(result.moves[1].pos[k] - start[k]) < 1e-9).toBe(true)
		end
		expect(session.obbyRun.section).toBe(2)
		expect(session.obbyRun.at).toBe(0)
		expect(session.obbyRun.startedAt).toBe(T + 8)
		local fell = analytics(world, "ObbyFell")
		expect(fell[#fell].fields[1]).toBe(`Section - {ObbyCourse.nameOf(world.obby.picks[2].id)}`)
		-- Back over sections 1 and 2, then on: the run is still valid and earns the boost.
		local now = T + 18 + OBBY.MOVE_GRACE
		ObbyService.step(world, PLACE, at(onPad(world, 0)), now)
		ObbyService.step(world, PLACE, at(onPad(world, 1)), now + 5)
		ObbyService.step(world, PLACE, at(onPad(world, 2)), now + 10)
		local _, finishedAt = runAll(world, now + 10, 8)
		expect(session.obbyRun).toBeNil()
		expect(session.data.obbyUntil).toBe(finishedAt + OBBY.BOOST_SECONDS)
		expect(session.obbyBest.seconds).toBe(finishedAt - (T + 8))
	end)

	it("just under the client's fall depth the server leaves the reset to the client", function()
		local world, session = setup()
		enter(world, T)
		ObbyService.step(world, PLACE, at(onPad(world, 1)), T + 8)
		local result = ObbyService.step(world, PLACE, at(below(world, 1, true)), T + 9)
		expect(#result.moves).toBe(0)
		expect(#result.resets).toBe(0)
		expect(session.obbyRun ~= nil).toBe(true)
		expect(#analytics(world, "ObbyFell")).toBe(0)
	end)

	it("the client's own jump back to the start pad counts as a fall and opens the server-move window", function()
		local world, session = setup()
		enter(world, T)
		ObbyService.step(world, PLACE, at(onPad(world, 1)), T + 8)
		ObbyService.step(world, PLACE, at(onPad(world, 3)), T + 16)
		local result = ObbyService.step(world, PLACE, at(onPad(world, 0)), T + 16.1)
		expect(#result.moves).toBe(0)
		expect(result.resets[1]).toBe(1)
		expect(session.obbyRun.section).toBe(3)
		expect(session.obbyRun.at).toBe(0)
		expect(session.obbyRun.startedAt).toBe(T + 8)
		local fell = analytics(world, "ObbyFell")
		expect(#fell).toBe(1)
		expect(fell[1].fields[1]).toBe(`Section - {ObbyCourse.nameOf(world.obby.picks[3].id)}`)
		-- Walking back onto the start pad is not a reset.
		local walk = ObbyService.step(world, PLACE, at(onPad(world, 1)), T + 20)
		expect(#walk.resets).toBe(0)
	end)

	it("the Goo Ring behind the start pad ends the run and sets the runner down in the yard", function()
		local world, session = setup()
		enter(world, T)
		local home = world.obby.home
		local spawn = ObbyService.step(world, PLACE, at(onPad(world, 0)), T + 2)
		expect(#spawn.moves).toBe(0) -- the runner appears out of the ring
		local p = ObbyCourse.toWorld(PLACE.frame, { home.pos[1], home.pos[2] + 3, home.pos[3] + home.radius * 0.5 })
		local result = ObbyService.step(world, PLACE, at(p), T + 4)
		expect(session.obbyRun).toBeNil()
		expect(#result.moves).toBe(1)
		expect(result.moves[1].pos[1]).toBe(PLACE.exit[1])
		expect(#analytics(world, "ObbyFell")).toBe(0)
	end)

	it("a fall right after a respawn is ignored until the move settles", function()
		local world, session = setup()
		enter(world, T)
		ObbyService.step(world, PLACE, at(onPad(world, 1)), T + 8)
		ObbyService.step(world, PLACE, at(below(world, 1)), T + 10)
		local again = ObbyService.step(world, PLACE, at(below(world, 1)), T + 10.5)
		expect(#again.moves).toBe(0)
		expect(session.obbyRun ~= nil).toBe(true)
	end)

	it("the old ground position arriving just after the lift does not end the run", function()
		local world, session = setup()
		enter(world, T)
		ObbyService.step(world, PLACE, at({ -95, 3, 230 }), T + 0.1) -- still at the portal on this tick
		expect(session.obbyRun ~= nil).toBe(true)
		ObbyService.step(world, PLACE, at(onPad(world, 0)), T + OBBY.MOVE_GRACE + 0.1)
		expect(session.obbyRun ~= nil).toBe(true)
	end)

	it("leaving the course or losing the character ends the run", function()
		local world, session = setup()
		enter(world, T)
		-- Well off to the side of the course, whatever its length.
		local away = { world.obby.length / 2, 3, ObbyService.OFF_COURSE + 20 }
		ObbyService.step(world, PLACE, at(ObbyCourse.toWorld(PLACE.frame, away)), T + 3)
		expect(session.obbyRun).toBeNil()
		enter(world, T + 5)
		ObbyService.step(world, PLACE, {}, T + 6)
		expect(session.obbyRun).toBeNil()
	end)

	it("wandering off the course in the obby world ends the run and sets the player down by the portal", function()
		local world, session = setup()
		enter(world, T)
		local off = ObbyCourse.toWorld(PLACE.frame, { 20, 3, ObbyService.OFF_COURSE + 30 })
		ObbyService.step(world, PLACE, at(off), T + 3)
		expect(session.obbyRun).toBeNil()
		local result = ObbyService.step(world, PLACE, at(off), T + 3.1)
		expect(#result.moves).toBe(1)
		expect(result.moves[1].pos[3]).toBe(PLACE.exit[3])
		expect(result.moves[1].yaw).toBe(PLACE.exitYaw)
	end)
end)

describe("ObbyService rotation and boost", function()
	it("a new rotation waits for runners, then sends them home and rebuilds", function()
		local world, session = setup()
		enter(world, T)
		local oldSlot = world.obby.slot
		local turn = ObbyCourse.slotStart(oldSlot + 1)
		local onStart = onPad(world, 0)
		local early = ObbyService.step(world, PLACE, at(onStart), turn + 1)
		expect(early.rebuilt).toBe(false)
		expect(session.obbyRun ~= nil).toBe(true)
		local late = ObbyService.step(world, PLACE, at(onStart), turn + OBBY.REBUILD_GRACE)
		expect(late.rebuilt).toBe(true)
		expect(world.obby.slot).toBe(oldSlot + 1)
		expect(session.obbyRun).toBeNil()
		expect(late.moves[1].pos[1]).toBe(PLACE.exit[1])
	end)

	it("an empty course rebuilds as soon as the rotation turns", function()
		local world = setup()
		local turn = ObbyCourse.slotStart(world.obby.slot + 1)
		expect(ObbyService.step(world, PLACE, {}, turn).rebuilt).toBe(true)
	end)

	it("the boost ends on time and survives a save round trip", function()
		local world, session = setup()
		enter(world, T)
		local _, now = runAll(world, T, 8)
		local copy = SaveData.deserialize(SaveData.serialize(session.data, now))
		expect(copy.obbyUntil).toBe(session.data.obbyUntil)
		expect(copy.obbyReadyAt).toBe(session.data.obbyReadyAt)
		expect(copy.obbyBonus).toBeNil() -- runtime only: refresh sets it again after a rejoin
		ObbyService.refresh(world, session.data.obbyUntil)
		expect(session.data.obbyBonus).toBeNil()
		local texts = ServerFixtures.notifications(world, 1)
		expect(string.find(texts[#texts], "Your obby boost ended", 1, true) ~= nil).toBe(true)
	end)

	it("State.obby shows the boost, the ready time, the course and the run", function()
		local world, session = setup()
		local idle = Snapshot.build(world, session, T).obby :: any
		expect(idle.endsAt).toBeNil()
		expect(idle.readyAt).toBeNil()
		expect(#idle.sections).toBe(#OBBY.ORDER)
		expect(idle.rotatesAt).toBe(ObbyCourse.slotStart(world.obby.slot + 1))
		enter(world, T)
		local running = Snapshot.build(world, session, T + 1).obby :: any
		expect(running.run.of).toBe(#OBBY.ORDER)
		runAll(world, T, 8)
		local boosted = Snapshot.build(world, session, T + 60).obby :: any
		expect(boosted.endsAt).toBe(session.data.obbyUntil)
		expect(boosted.readyAt).toBe(session.data.obbyReadyAt)
		expect(boosted.best ~= nil).toBe(true)
	end)
end)

-- Steps a runner standing on the start pad every 0.1 s (the server loop's rate) from `from` to `to`.
local function standOnStart(world: any, from: number, to: number)
	local start = onPad(world, 0)
	local now = from
	while now < to - 1e-9 do
		now = math.min(to, now + 0.1)
		ObbyService.step(world, PLACE, at(start), now)
	end
end

describe("ObbyService run clock and current section", function()
	it("the clock waits on the start pad and starts the first tick past its front edge", function()
		local world, session = setup()
		enter(world, T)
		standOnStart(world, T, T + 3)
		expect(session.obbyRun.startedAt).toBeNil()
		local view = Snapshot.build(world, session, T + 3).obby :: any
		expect(view.run.startedAt).toBeNil()
		expect(view.run.at).toBe(0)
		-- either side of the pad's front edge, where section 1 begins
		local front = world.obby.spans[1].from
		ObbyService.step(world, PLACE, at(ObbyCourse.toWorld(PLACE.frame, { front - 0.5, 3, 0 })), T + 3.1)
		expect(session.obbyRun.startedAt).toBeNil()
		ObbyService.step(world, PLACE, at(ObbyCourse.toWorld(PLACE.frame, { front + 0.5, 3, 0 })), T + 3.2)
		expect(session.obbyRun.startedAt).toBe(T + 3.2)
		expect(session.obbyRun.at).toBe(1)
		view = Snapshot.build(world, session, T + 3.2).obby :: any
		expect(view.run.startedAt).toBe(T + 3.2)
		expect(view.run.at).toBe(1)
	end)

	it("the time, the best and the analytics count from leaving the pad, not from the portal", function()
		local world, session = setup()
		enter(world, T)
		standOnStart(world, T, T + 30)
		local _, now = runAll(world, T + 30, 8)
		expect(session.obbyBest.seconds).toBe(now - (T + 38))
		local done = analytics(world, "ObbyFinished")
		expect(done[#done].value).toBe(math.floor(now - (T + 38) + 0.5))
		expect(done[#done].fields[1]).toBe("Boost - Earned")
	end)

	it("a long wait on the pad never makes a fast run count", function()
		local world, session = setup()
		enter(world, T)
		standOnStart(world, T, T + 30)
		local gap = OBBY.MIN_RUN_SECONDS / (#world.obby.spans + 2)
		runAll(world, T + 30, gap)
		expect(session.data.obbyUntil).toBe(0)
		local texts = ServerFixtures.notifications(world, 1)
		expect(texts[#texts]).toBe("That run didn't count. Try again!")
	end)

	it("a quick start inside the lift grace starts the clock; a stale yard position does not", function()
		local world, session = setup()
		enter(world, T)
		ObbyService.step(world, PLACE, at({ -95, 3, 230 }), T + 0.5) -- the portal position, still on its way
		expect(session.obbyRun.startedAt).toBeNil()
		ObbyService.step(world, PLACE, at(onPad(world, 1)), T + 1)
		expect(session.obbyRun.startedAt).toBe(T + 1)
	end)

	it("the current section follows the runner back; the furthest stays; a fall keeps the clock", function()
		local world, session = setup()
		enter(world, T)
		ObbyService.step(world, PLACE, at(onPad(world, 1)), T + 8)
		ObbyService.step(world, PLACE, at(onPad(world, 2)), T + 16)
		local result = ObbyService.step(world, PLACE, at(onPad(world, 0)), T + 16.1) -- the client's fall reset
		expect(result.resets[1]).toBe(1)
		local view = Snapshot.build(world, session, T + 16.1).obby :: any
		expect(view.run.at).toBe(0)
		expect(view.run.section).toBe(2)
		expect(view.run.startedAt).toBe(T + 8)
		ObbyService.step(world, PLACE, at(onPad(world, 1)), T + 20)
		view = Snapshot.build(world, session, T + 20).obby :: any
		expect(view.run.at).toBe(1)
		expect(view.run.section).toBe(2)
		expect(view.run.startedAt).toBe(T + 8)
	end)

	it("a new run starts fresh: on the start pad, no clock, nothing reached", function()
		local world, session = setup()
		enter(world, T)
		ObbyService.step(world, PLACE, at(onPad(world, 1)), T + 8)
		ObbyService.step(world, PLACE, at(onPad(world, 2)), T + 16)
		local home = world.obby.home
		ObbyService.step(world, PLACE, at(ObbyCourse.toWorld(PLACE.frame, { home.pos[1], 3, 0 })), T + 20)
		expect(session.obbyRun).toBeNil()
		enter(world, T + 30)
		local run = (Snapshot.build(world, session, T + 31).obby :: any).run
		expect(run.section).toBe(0)
		expect(run.at).toBe(0)
		expect(run.startedAt).toBeNil()
	end)
end)

describe("ObbyLock: the base lock runs at half speed during a run", function()
	it("the math: a tick of dt real seconds uses LOCK_RATE x dt lock seconds", function()
		expect(OBBY.LOCK_RATE).toBe(0.5)
		expect(ObbyLock.slowed(200, 0, 100, 110, 0.5)).toBeCloseTo(205, 1e-9) -- 100 s left, 10 s run: 95 s left
		expect(ObbyLock.slowed(200, 0, 100, 110, 1)).toBeCloseTo(200, 1e-9) -- rate 1 = no change
		expect(ObbyLock.slowed(50, 0, 100, 110, 0.5)).toBe(50) -- an expired lock stays as it is
		expect(ObbyLock.slowed(0, 0, 100, 110, 0.5)).toBe(0) -- no lock
		expect(ObbyLock.slowed(103, 0, 100, 110, 0.5)).toBeCloseTo(106, 1e-9) -- 3 s left runs out after 6 s
		expect(ObbyLock.slowed(120, 105, 100, 110, 0.5)).toBeCloseTo(122.5, 1e-9) -- began mid-tick: counts from 105
		expect(ObbyLock.slowed(200, 0, 100, 110, 0)).toBeCloseTo(209, 1e-9) -- the rate never goes under MIN_RATE (0.1)
	end)

	it("over a 10 s run the lock loses 5 s, and every tick in between counts at half speed", function()
		local world, session = setup()
		local lockUntil = session.lockUntil -- the join lock: 120 s from T
		enter(world, T)
		standOnStart(world, T, T + 10)
		expect(session.obbyRun ~= nil).toBe(true)
		local left = session.lockUntil - (T + 10)
		expect(left).toBeCloseTo(lockUntil - T - 5, 1e-6)
		standOnStart(world, T + 10, T + 30)
		expect(session.lockUntil - (T + 30)).toBeCloseTo(lockUntil - T - 15, 1e-6)
	end)

	it("a lock that runs out mid-run ends at the slow rate and stays ended", function()
		local world, session = setup()
		enter(world, T)
		session.lockUntil = T + 3 -- 3 s left as the run starts
		standOnStart(world, T, T + 10)
		expect(session.lockUntil).toBeCloseTo(T + 6, 1e-6)
		expect(session.lockUntil < T + 10).toBe(true) -- unlocked now
		standOnStart(world, T + 10, T + 20)
		expect(session.lockUntil).toBeCloseTo(T + 6, 1e-6) -- an expired lock is never revived
	end)

	it("a lock that starts mid-run counts from its start", function()
		local world, session = setup()
		session.lockUntil = 0
		enter(world, T)
		standOnStart(world, T, T + 5)
		expect(session.lockUntil).toBe(0) -- no lock, nothing to slow
		session.lockStartedAt = T + 5
		session.lockUntil = T + 5 + 30 -- e.g. the breather lock after a steal
		session.breatherUntil = session.lockUntil
		standOnStart(world, T + 5, T + 15)
		expect(session.lockUntil).toBeCloseTo(T + 5 + 30 + 5, 1e-6)
		expect(session.breatherUntil).toBe(session.lockUntil) -- still the breather (LockBreak.inBreather)
	end)

	it("no slowdown outside a run, nor after it ends", function()
		local world, session = setup()
		local lockUntil = session.lockUntil
		ObbyService.step(world, PLACE, at({ 0, 3, 0 }), T + 1)
		ObbyService.step(world, PLACE, at({ 0, 3, 0 }), T + 5)
		expect(session.lockUntil).toBe(lockUntil)
		enter(world, T + 10)
		standOnStart(world, T + 10, T + 14)
		ObbyService.step(world, PLACE, {}, T + 14.1) -- no character: the run is over
		expect(session.obbyRun).toBeNil()
		local after = session.lockUntil
		expect(after).toBeCloseTo(lockUntil + 2, 1e-6)
		ObbyService.step(world, PLACE, at({ 0, 3, 0 }), T + 20)
		expect(session.lockUntil).toBe(after)
	end)

	it("State.obby.run tells the client the lock's rate", function()
		local world, session = setup()
		enter(world, T)
		local running = Snapshot.build(world, session, T + 1).obby :: any
		expect(running.run.lockRate).toBe(OBBY.LOCK_RATE)
	end)
end)

describe("ObbyService entry: only on a course you have not cleared", function()
	it("refuses a player who cleared this course, with the time to the next one", function()
		local world, session = setup()
		enter(world, T)
		local _, now = runAll(world, T, 8)
		expect(ObbyService.cleared(session, world.obby.slot)).toBe(true)
		ObbyService.step(world, PLACE, at({ 0, 3, 0 }), now + 5) -- walk away from the exit
		local result = enter(world, now + 10)
		expect(session.obbyRun).toBeNil()
		expect(#result.moves).toBe(0)
		local texts = ServerFixtures.notifications(world, 1)
		local rotatesAt = ObbyCourse.slotStart(world.obby.slot + 1)
		local s = math.ceil(rotatesAt - (now + 10))
		expect(texts[#texts]).toBe(`You cleared this course! New one in {string.format("%d:%02d", s // 60, s % 60)}`)
		local sign = Snapshot.build(world, session, now + 10).obby :: any
		expect(sign.best ~= nil).toBe(true) -- the portal sign reads it: "Cleared! Next course soon"
	end)

	it("lets them in again on the next course", function()
		local world, session = setup()
		enter(world, T)
		runAll(world, T, 8)
		local nextSlot = world.obby.slot + 1
		enter(world, ObbyCourse.slotStart(nextSlot) + 5)
		expect(world.obby.slot).toBe(nextSlot)
		expect(session.obbyRun ~= nil).toBe(true)
	end)

	it("a run that didn't count does not block another try", function()
		local world, session = setup()
		enter(world, T)
		ObbyService.step(world, PLACE, at(onPad(world, #world.obby.spans + 1)), T + 60) -- straight to the finish
		expect(session.obbyRun).toBeNil()
		expect(ObbyService.cleared(session, world.obby.slot)).toBe(false)
		ObbyService.step(world, PLACE, at({ 0, 3, 0 }), T + 65)
		enter(world, T + 70)
		expect(session.obbyRun ~= nil).toBe(true)
	end)
end)
