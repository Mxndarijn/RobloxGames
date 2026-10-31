--!strict
-- The Upcoming Events sign (contract/slime-ladder.md §45.7): the pure rows (src/shared/EventBoard.luau) and what the
-- adapter reads from a World (src/server/EventBoardView.luau).
local BossEvent = require("../src/server/BossEvent")
local Config = require("../src/shared/Config")
local EventBoard = require("../src/shared/EventBoard")
local EventBoardView = require("../src/server/EventBoardView")
local ServerFixtures = require("./ServerFixtures")
local SlimeRoster = require("../src/shared/SlimeRoster")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local NOW = 1000

-- The card with id `id`, or nil.
local function row(rows: { EventBoard.Row }, id: string): EventBoard.Row?
	for _, r in rows do
		if r.id == id then
			return r
		end
	end
	return nil
end

local function ids(rows: { EventBoard.Row }): { string }
	local out = {}
	for _, r in rows do
		table.insert(out, r.id)
	end
	return out
end

describe("EventBoard.clock", function()
	it("writes m:ss, rounds up and never goes negative", function()
		expect(EventBoard.clock(0)).toBe("0:00")
		expect(EventBoard.clock(5)).toBe("0:05")
		expect(EventBoard.clock(59.2)).toBe("1:00")
		expect(EventBoard.clock(65)).toBe("1:05")
		expect(EventBoard.clock(900)).toBe("15:00")
		expect(EventBoard.clock(3725)).toBe("62:05")
		expect(EventBoard.clock(-30)).toBe("0:00")
	end)
end)

describe("EventBoard.rows", function()
	it("names a boss that is here, else counts down to the next one", function()
		local here = assert(row(EventBoard.rows({ bossHere = "King Goo", bossAt = NOW + 60 }, NOW), "boss"))
		expect(here.detail).toBe("King Goo is here!")
		expect(here.time).toBe("NOW")
		expect(here.live).toBe(true)
		local coming = assert(row(EventBoard.rows({ bossAt = NOW + 125 }, NOW), "boss"))
		expect(coming.time).toBe("2:05")
		expect(coming.live).toBe(false)
		expect(row(EventBoard.rows({}, NOW), "boss")).toBeNil()
	end)
	it("shows a running Slime Rain's time left, else when the next one starts", function()
		local running = assert(row(EventBoard.rows({ rainEndsAt = NOW + 90, rainAt = NOW + 500 }, NOW), "rain"))
		expect(running.time).toBe("1:30 left")
		expect(running.live).toBe(true)
		expect((assert(row(EventBoard.rows({ rainAt = NOW + 600 }, NOW), "rain"))).time).toBe("10:00")
		expect(row(EventBoard.rows({}, NOW), "rain")).toBeNil()
	end)
	it("never shows the weather", function()
		expect(EventBoard.rows({}, NOW)).toEqual({})
		for _, r in EventBoard.rows({ bossAt = NOW + 1, rainAt = NOW + 2, legendaryIn = 3, mythicIn = 4 }, NOW) do
			expect(r.id ~= "weather").toBe(true)
			expect(string.find(r.title, "Weather") == nil).toBe(true)
		end
	end)
	it("gives the guaranteed Legendary and Mythic a card each", function()
		local rows = EventBoard.rows({ legendaryIn = 125, mythicIn = 600 }, NOW)
		expect((assert(row(rows, "legendary"))).time).toBe("2:05")
		expect((assert(row(rows, "mythic"))).time).toBe("10:00")
		expect(row(EventBoard.rows({}, NOW), "legendary")).toBeNil()
	end)
	it("shows a running event with its time left when it has an end", function()
		local event = assert(row(EventBoard.rows({ event = "Double Goo", eventEndsAt = NOW + 300 }, NOW), "event"))
		expect(event.title).toBe("Double Goo")
		expect(event.time).toBe("5:00 left")
		expect((assert(row(EventBoard.rows({ event = "Shiny Week" }, NOW), "event"))).time).toBe("NOW")
	end)
	it("puts running events first, then the soonest", function()
		local rows = EventBoard.rows({
			bossAt = NOW + 400,
			rainAt = NOW + 120,
			legendaryIn = 10,
			mythicIn = 900,
			event = "Party",
		}, NOW)
		expect(ids(rows)).toEqual({ "event", "legendary", "rain", "boss", "mythic" })
		local live = EventBoard.rows({ bossHere = "King Goo", rainEndsAt = NOW + 50, legendaryIn = 5 }, NOW)
		expect(ids(live)).toEqual({ "boss", "rain", "legendary" })
	end)
	it("caps the wall at MAX_ROWS and keys the layout on the order", function()
		local rows = EventBoard.rows({
			bossAt = NOW + 1,
			rainAt = NOW + 2,
			legendaryIn = 3,
			mythicIn = 4,
			event = "Party",
		}, NOW)
		expect(#rows <= EventBoard.MAX_ROWS).toBe(true)
		local a = EventBoard.layoutKey(EventBoard.rows({ bossAt = NOW + 10, rainAt = NOW + 20 }, NOW))
		local b = EventBoard.layoutKey(EventBoard.rows({ bossAt = NOW + 11, rainAt = NOW + 21 }, NOW))
		local c = EventBoard.layoutKey(EventBoard.rows({ bossAt = NOW + 30, rainAt = NOW + 20 }, NOW))
		expect(a).toBe(b)
		expect(a ~= c).toBe(true)
	end)
	it("text writes one 'Title: detail (time)' line per card", function()
		expect(EventBoard.text(EventBoard.rows({ bossAt = NOW + 60 }, NOW))).toBe(
			"Boss: arrives at the fountain (1:00)"
		)
	end)
end)

describe("EventBoardView.input", function()
	it("reads the next boss and the rain clock from a fresh world", function()
		local world = ServerFixtures.world()
		local input = EventBoardView.input(world, T0)
		expect(input.bossHere).toBeNil()
		expect(input.bossAt).toBe(world.nextBossAt)
		local raining, endsAt, startsAt = Spawner.rain(world, T0)
		expect(input.rainEndsAt).toBe(if raining then endsAt else nil)
		expect(input.rainAt).toBe(if raining then nil else startsAt)
		expect(input.event).toBeNil()
		-- no drop yet: the guarantee clocks haven't started
		expect(input.legendaryIn).toBeNil()
		expect(input.mythicIn).toBeNil()
	end)
	it("reads the guarantee clocks after a drop, and leaves the live weather off the board", function()
		local world = ServerFixtures.world()
		world.weather = { id = "Snow", changeAt = T0 + 200 }
		local id = Spawner.spawnSlime(world, T0)
		local tier = world.wild[id].slime.tier
		local input = EventBoardView.input(world, T0 + 100)
		expect(input.legendaryIn).toBe(Spawner.guaranteeIn(world, 5, T0 + 100))
		expect(input.mythicIn).toBe(Spawner.guaranteeIn(world, 6, T0 + 100))
		if tier < 5 then
			expect(input.legendaryIn).toBe(Config.GUARANTEE_SECONDS[5] - 100)
		end
		for _, card in EventBoard.rows(input, T0 + 100) do
			expect(string.find(card.title, "Weather") == nil).toBe(true)
		end
	end)
	it("names a running admin event and its end", function()
		local world = ServerFixtures.world()
		world.adminEvent = {
			def = { id = "x", label = "Goo Frenzy", icon = "" },
			endsAt = T0 + 90,
			modifier = nil :: any,
		}
		local input = EventBoardView.input(world, T0)
		expect(input.event).toBe("Goo Frenzy")
		expect(input.eventEndsAt).toBe(T0 + 90)
	end)
	it("names the boss once it is on the plaza", function()
		local world = ServerFixtures.world()
		world.startedAt = T0 - Config.RAIN_FIRST_AT - Config.RAIN_DURATION - 600
		world.nextSpawnAt = math.huge
		ServerFixtures.join(world, 1, nil, 0)
		world.nextBossAt = T0 + Config.BOSS.WARNING_SECONDS
		BossEvent.step(world, T0)
		BossEvent.step(world, T0 + Config.BOSS.WARNING_SECONDS)
		local id = assert(BossEvent.bossId(world), "boss arrived")
		local species = assert(world.wild[id].slime.species, "boss species")
		local input = EventBoardView.input(world, T0 + Config.BOSS.WARNING_SECONDS + 1)
		expect(input.bossHere).toBe((SlimeRoster.get(species) :: SlimeRoster.Entry).name)
		expect(input.bossAt).toBeNil()
	end)
end)
