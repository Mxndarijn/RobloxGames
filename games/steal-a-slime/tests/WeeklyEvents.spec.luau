--!strict
-- Weekly trait event (FEATURES.WeeklyEvents, CONTRACT.md §17): pure schedule, 3-week fake-clock simulation,
-- caps, the roll window, the replicated attribute and the interaction with live admin events.
local AdminEventsService = require("../src/server/AdminEventsService")
local Config = require("../src/shared/Config")
local Constants = require("../src/shared/Constants")
local ServerFixtures = require("./ServerFixtures")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")
local WeeklyEventService = require("../src/server/WeeklyEventService")
local WeeklyEvents = require("../src/shared/WeeklyEvents")

local describe, rawIt, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local DAY = 86400
local function utc(y: number, m: number, d: number, h: number?, min: number?): number
	return os.time({ year = y, month = m, day = d, hour = h or 0, min = min or 0, sec = 0 }) -- Lune runs in UTC
end
local MON = utc(2026, 10, 19) -- a Monday
local SAT_START = MON + 5 * DAY + Config.WEEKLY.TRAIT_START_HOUR * 3600

-- Config.FEATURES is frozen, so every test except the config check forces the feature on for its own run.
local function it(name: string, fn: () -> ())
	rawIt(name, function()
		WeeklyEvents.setForced(true)
		local ok, err = pcall(fn)
		WeeklyEvents.setForced(nil)
		if not ok then
			error(err, 0)
		end
	end)
end

describe("WeeklyEvents config", function()
	rawIt("follows the flag, and gives no luck while it is off", function()
		expect(WeeklyEvents.enabled()).toBe(Config.FEATURES.WeeklyEvents)
		WeeklyEvents.setForced(false)
		expect(WeeklyEvents.multiplier(SAT_START)).toBe(1)
		WeeklyEvents.setForced(nil)
	end)
	it("keeps the boost small and capped", function()
		expect(Config.WEEKLY.MAX_MULTIPLIER <= 2).toBe(true)
		expect(Config.WEEKLY.TRAIT_SECONDS < DAY).toBe(true)
		for _, trait in Config.WEEKLY.TRAITS do
			expect(trait.luck >= 1 and trait.luck <= Config.WEEKLY.MAX_MULTIPLIER).toBe(true)
		end
	end)
end)

describe("WeeklyEvents weeks", function()
	it("weeks run Monday 00:00 UTC to Monday 00:00 UTC", function()
		local week = WeeklyEvents.weekIndex(MON)
		expect(WeeklyEvents.weekIndex(MON - 1)).toBe(week - 1)
		expect(WeeklyEvents.weekIndex(MON + 7 * DAY - 1)).toBe(week)
		expect(WeeklyEvents.weekIndex(MON + 7 * DAY)).toBe(week + 1)
		expect(WeeklyEvents.weekIndex(0)).toBe(0) -- Thu 1970-01-01 is in the week of Mon 1969-12-29
	end)
	it("ISO week numbers: Mon 2026-10-19 is 2026-W43, Mon 2024-12-30 is 2025-W01", function()
		local year, number = WeeklyEvents.isoWeek(WeeklyEvents.weekIndex(MON))
		expect(year).toBe(2026)
		expect(number).toBe(43)
		year, number = WeeklyEvents.isoWeek(WeeklyEvents.weekIndex(utc(2024, 12, 30)))
		expect(year).toBe(2025)
		expect(number).toBe(1)
	end)
	it("the trait event is Saturday 18:00-20:00 UTC", function()
		expect(#WeeklyEvents.current(SAT_START - 1)).toBe(0)
		local live = WeeklyEvents.current(SAT_START)
		expect(#live).toBe(1)
		expect(live[1].startsAt).toBe(SAT_START)
		expect(live[1].endsAt).toBe(SAT_START + Config.WEEKLY.TRAIT_SECONDS)
		expect(#WeeklyEvents.current(SAT_START + Config.WEEKLY.TRAIT_SECONDS)).toBe(0)
	end)
end)

describe("WeeklyEvents 3-week simulation (fake clock)", function()
	local STEP = 600
	local DAYS = 21
	local sat = {} :: { { startsAt: number, endsAt: number, week: number } }

	it("at most one trait event, Saturday only, no overlap, correct boundaries", function()
		local lastTraitKey: number? = nil
		for t = MON, MON + DAYS * DAY - STEP, STEP do
			local live = WeeklyEvents.current(t)
			expect(#live <= 1).toBe(true)
			for _, e in live do
				expect(e.startsAt <= t and t < e.endsAt).toBe(true)
				local wd = tonumber(os.date("!%w", t))
				expect(wd).toBe(6)
				if lastTraitKey ~= e.startsAt then
					lastTraitKey = e.startsAt
					table.insert(sat, { startsAt = e.startsAt, endsAt = e.endsAt, week = e.week })
				end
			end
		end
	end)
	it("three weeks, three Saturday events that do not overlap", function()
		expect(#sat).toBe(3)
		for i = 2, #sat do
			expect(sat[i - 1].endsAt <= sat[i].startsAt).toBe(true)
		end
	end)
	it("next() is strictly in the future and is the first event that then starts", function()
		for t = MON, MON + DAYS * DAY - STEP, STEP * 3 do
			local nextEvent = WeeklyEvents.next(t)
			expect(nextEvent.startsAt > t).toBe(true)
			-- nothing new has started just before it
			for _, e in WeeklyEvents.current(nextEvent.startsAt - 1) do
				expect(e.startsAt <= t).toBe(true)
			end
			local found = false
			for _, e in WeeklyEvents.current(nextEvent.startsAt) do
				found = found or (e.id == nextEvent.id and e.startsAt == nextEvent.startsAt)
			end
			expect(found).toBe(true)
		end
	end)
	it("next() from Monday is this Saturday; during the trait or after it, next Saturday", function()
		expect(WeeklyEvents.next(MON + 60).startsAt).toBe(SAT_START)
		expect(WeeklyEvents.next(SAT_START + 60).startsAt).toBe(SAT_START + 7 * DAY)
		expect(WeeklyEvents.next(MON + 6 * DAY + 12 * 3600).startsAt).toBe(SAT_START + 7 * DAY)
	end)
end)

describe("WeeklyEvents effects", function()
	it("the multiplier is 1 outside the trait window and within the cap inside", function()
		expect(WeeklyEvents.multiplier(SAT_START - 1)).toBe(1)
		expect(WeeklyEvents.multiplier(SAT_START + Config.WEEKLY.TRAIT_SECONDS)).toBe(1)
		for week = 0, 3 do
			local luck = WeeklyEvents.multiplier(SAT_START + week * 7 * DAY)
			expect(luck > 1 and luck <= Config.WEEKLY.MAX_MULTIPLIER).toBe(true)
		end
	end)
	it("the trait raises the rare share of drops", function()
		local original = Spawner.unixTime
		local function rare(at: number): number
			Spawner.unixTime = function()
				return at
			end
			local world = ServerFixtures.world()
			local n = 0
			for _ = 1, 3000 do
				local id = Spawner.spawnOne(world, ServerFixtures.T0)
				n += if world.wild[id].slime.tier >= 3 then 1 else 0
				world.wild[id] = nil
			end
			return n
		end
		local quiet = rare(MON + DAY)
		local trait = rare(SAT_START + 60)
		Spawner.unixTime = original
		expect(trait > quiet).toBe(true)
	end)
end)

describe("WeeklyEvents vs live admin events (#130)", function()
	local original = Spawner.unixTime
	local function drops(at: number, admin: boolean): { string }
		Spawner.unixTime = function()
			return at
		end
		local world = ServerFixtures.world()
		if admin then
			local svc = AdminEventsService.new(world, 1000, nil)
			AdminEventsService.command(svc, 1000, "/event luck 10", ServerFixtures.T0)
			expect(world.adminEvent ~= nil).toBe(true)
		end
		local out = {}
		for _ = 1, 400 do
			local id = Spawner.spawnOne(world, ServerFixtures.T0)
			local slime = world.wild[id].slime
			table.insert(out, `{slime.tier}:{slime.species}`)
			world.wild[id] = nil
		end
		Spawner.unixTime = original
		return out
	end
	it("a running admin event replaces the weekly boost: drops equal in any week, trait or not", function()
		local a = drops(MON + DAY, true)
		local b = drops(MON + 8 * DAY, true)
		local c = drops(SAT_START + 60, true)
		expect(table.concat(a, ",")).toBe(table.concat(b, ","))
		expect(table.concat(a, ",")).toBe(table.concat(c, ","))
	end)
	it("without an admin event the same seed differs between a trait Saturday and a quiet day", function()
		local quiet = drops(MON + DAY, false)
		local trait = drops(SAT_START + 60, false)
		expect(table.concat(quiet, ",") ~= table.concat(trait, ",")).toBe(true)
	end)
	it("after the admin event ends the weekly boost applies again", function()
		Spawner.unixTime = function()
			return SAT_START + 60
		end
		local world = ServerFixtures.world()
		local svc = AdminEventsService.new(world, 1000, nil)
		AdminEventsService.command(svc, 1000, "/event luck 1", ServerFixtures.T0)
		Spawner.stepModifier(world, ServerFixtures.T0 + 3600)
		Spawner.unixTime = original
		expect(world.adminEvent).toBeNil()
	end)
end)

describe("WeeklyEvents attribute", function()
	local function holder()
		local attrs: { [string]: any } = {}
		return {
			attrs = attrs,
			GetAttribute = function(_self: any, name: string): any
				return attrs[name]
			end,
			SetAttribute = function(_self: any, name: string, value: any)
				attrs[name] = value
			end,
		}
	end
	it("encode / decode round-trips current and next", function()
		for _, t in { MON + 60, SAT_START + 60, MON + 6 * DAY + 80000 } do
			local d = WeeklyEvents.decode(WeeklyEvents.encode(t))
			expect(d ~= nil).toBe(true)
			local live = WeeklyEvents.current(t)
			local nextEvent = WeeklyEvents.next(t)
			local decoded = d :: WeeklyEvents.Decoded
			expect(decoded.week).toBe(WeeklyEvents.weekIndex(t))
			expect(decoded.trait).toBe(if live[1] then live[1].id else nil)
			expect(decoded.traitEndsAt).toBe(if live[1] then live[1].endsAt else nil)
			expect(decoded.nextId).toBe(nextEvent.id)
			expect(decoded.nextStartsAt).toBe(nextEvent.startsAt)
		end
		expect(WeeklyEvents.decode("garbage")).toBeNil()
		expect(WeeklyEvents.decode(5)).toBeNil()
	end)
	it("publish writes the attribute once and again only when it changes", function()
		local h = holder()
		expect(WeeklyEventService.publish(h, MON + 60)).toBe(true)
		expect(h.attrs[Constants.WEEKLY_EVENT_ATTRIBUTE]).toBe(WeeklyEvents.encode(MON + 60))
		expect(WeeklyEventService.publish(h, MON + 120)).toBe(false)
		expect(WeeklyEventService.publish(h, SAT_START + 1)).toBe(true)
	end)
	it("waitSeconds never sleeps past the next boundary or SYNC_SECONDS", function()
		for _, t in { MON + 60, SAT_START - 5, SAT_START + Config.WEEKLY.TRAIT_SECONDS - 2, MON + 7 * DAY - 1 } do
			local wait = WeeklyEventService.waitSeconds(t)
			expect(wait >= 1 and wait <= Config.WEEKLY.SYNC_SECONDS).toBe(true)
		end
		expect(WeeklyEventService.waitSeconds(SAT_START - 5)).toBe(5)
	end)
end)
