--!strict
-- The Obby over World (src/server/ObbyService.luau, contract/obby.md): the portal, section progress in order, falls,
-- the finish and its boost, the cooldown, the rotation, the income bonus and State.obby.
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local ObbyCourse = require("../src/shared/ObbyCourse")
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

-- World position below the fall height over section `i`.
local function below(world: any, i: number): { number }
	local span = world.obby.spans[i]
	return ObbyCourse.toWorld(PLACE.frame, { (span.from + span.to) / 2, ObbyCourse.fallHeight(world.obby, i) - 2, 0 })
end

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
		expect(session.obbyBest.seconds).toBe(now - T)
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
		local _, now = runAll(world, T, 8)
		local untilAt = session.data.obbyUntil
		local later = untilAt + 30 -- boost over, cooling down
		ObbyService.refresh(world, later)
		enter(world, later)
		runAll(world, later, 8)
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
		expect(session.obbyRun.startedAt).toBe(T)
		local fell = analytics(world, "ObbyFell")
		expect(fell[#fell].fields[1]).toBe(`Section - {ObbyCourse.NAMES[world.obby.picks[2].id]}`)
		-- Back over sections 1 and 2, then on: the run is still valid and earns the boost.
		local now = T + 18 + OBBY.MOVE_GRACE
		ObbyService.step(world, PLACE, at(onPad(world, 0)), now)
		ObbyService.step(world, PLACE, at(onPad(world, 1)), now + 5)
		ObbyService.step(world, PLACE, at(onPad(world, 2)), now + 10)
		local _, finishedAt = runAll(world, now + 10, 8)
		expect(session.obbyRun).toBeNil()
		expect(session.data.obbyUntil).toBe(finishedAt + OBBY.BOOST_SECONDS)
		expect(session.obbyBest.seconds).toBe(finishedAt - T)
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
