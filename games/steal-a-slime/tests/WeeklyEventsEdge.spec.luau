--!strict
-- Weekly events hardening (FEATURES.WeeklyEvents, CONTRACT.md §18): flag off, week / trait boundaries with
-- fractional server time, ISO year edges, bad attributes, publish / start with the feature off.
-- Cloud-eligible: pure require paths, no @lune, UTC maths done by hand (no os.time table).
local Config = require("../src/shared/Config")
local Constants = require("../src/shared/Constants")
local Genome = require("../src/shared/Genome")
local ServerFixtures = require("./ServerFixtures")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")
local WeeklyEventService = require("../src/server/WeeklyEventService")
local WeeklyEvents = require("../src/shared/WeeklyEvents")

local describe, rawIt, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local DAY = 86400
local MON = 1_792_368_000 -- 2026-10-19 00:00 UTC, a Monday (20015 days after the epoch)
local SAT_START = MON + 5 * DAY + Config.WEEKLY.TRAIT_START_HOUR * 3600
local TRAIT = Config.WEEKLY.TRAIT_SECONDS

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

local function holder()
	local attrs: { [string]: any } = {}
	local sets = 0
	return {
		attrs = attrs,
		sets = function()
			return sets
		end,
		GetAttribute = function(_self: any, name: string): any
			return attrs[name]
		end,
		SetAttribute = function(_self: any, name: string, value: any)
			sets += 1
			attrs[name] = value
		end,
	}
end

describe("WeeklyEvents anchors", function()
	it("the hand-written Monday really is a Monday", function()
		expect(os.date("!%w %H:%M:%S", MON)).toBe("1 00:00:00")
		expect(WeeklyEvents.weekIndex(MON) * 7 * DAY - 3 * DAY).toBe(MON)
	end)
end)

describe("WeeklyEvents flag off", function()
	rawIt("the real config flag is off and publish clears a stale attribute without writing twice", function()
		expect(WeeklyEvents.enabled()).toBe(Config.FEATURES.WeeklyEvents)
		WeeklyEvents.setForced(false)
		local h = holder()
		h.attrs[Constants.WEEKLY_EVENT_ATTRIBUTE] = "stale"
		expect(WeeklyEventService.publish(h, MON)).toBe(true)
		expect(h.attrs[Constants.WEEKLY_EVENT_ATTRIBUTE]).toBeNil()
		expect(WeeklyEventService.publish(h, MON + 1)).toBe(false)
		expect(h.sets()).toBe(1)
		WeeklyEvents.setForced(nil)
	end)
	rawIt("start with the feature off publishes nothing and spawns no clock loop", function()
		WeeklyEvents.setForced(false)
		local h = holder()
		WeeklyEventService.start(h, function()
			return MON
		end)
		expect(h.attrs[Constants.WEEKLY_EVENT_ATTRIBUTE]).toBeNil()
		expect(h.sets()).toBe(0)
		WeeklyEvents.setForced(nil)
	end)
	rawIt("drops are identical on a trait Saturday and with no schedule while the flag is off", function()
		WeeklyEvents.setForced(false)
		local original = Spawner.unixTime
		local function run(at: number?): string
			Spawner.unixTime = function()
				return at
			end
			local world = ServerFixtures.world()
			local out = {}
			for _ = 1, 200 do
				local id = Spawner.spawnOne(world, ServerFixtures.T0)
				local slime = world.wild[id].slime
				table.insert(out, `{slime.tier}:{table.concat(Genome.mutationList(slime), "+")}`)
				world.wild[id] = nil
			end
			return table.concat(out, ",")
		end
		local none, trait = run(nil), run(SAT_START + 60)
		Spawner.unixTime = original
		WeeklyEvents.setForced(nil)
		expect(trait).toBe(none)
	end)
end)

describe("WeeklyEvents boundaries", function()
	it("fractional server time (GetServerTimeNow) switches exactly at the boundary", function()
		expect(WeeklyEvents.weekIndex(MON - 0.001)).toBe(WeeklyEvents.weekIndex(MON) - 1)
		expect(WeeklyEvents.weekIndex(MON + 0.001)).toBe(WeeklyEvents.weekIndex(MON))
		expect(#WeeklyEvents.current(SAT_START - 0.5)).toBe(1)
		expect(#WeeklyEvents.current(SAT_START + 0.5)).toBe(2)
		expect(#WeeklyEvents.current(SAT_START + TRAIT - 0.5)).toBe(2)
		expect(#WeeklyEvents.current(SAT_START + TRAIT)).toBe(1)
		local d = WeeklyEvents.decode(WeeklyEvents.encode(SAT_START + 0.5))
		expect(d ~= nil).toBe(true)
		expect((d :: WeeklyEvents.Decoded).trait ~= nil).toBe(true)
	end)
	it("the multipliers drop back to 1 on the exact end second and on the week switch", function()
		expect(
			select(1, WeeklyEvents.multipliers(SAT_START + TRAIT - 1))
					* select(2, WeeklyEvents.multipliers(SAT_START + TRAIT - 1))
				> 1
		).toBe(true)
		expect(select(1, WeeklyEvents.multipliers(SAT_START + TRAIT))).toBe(1)
		expect(select(2, WeeklyEvents.multipliers(SAT_START + TRAIT))).toBe(1)
		local before = WeeklyEvents.mutationBoost(MON + 7 * DAY - 1)
		local after = WeeklyEvents.mutationBoost(MON + 7 * DAY)
		expect(before ~= after).toBe(true)
	end)
	it("times before the epoch and far in the future still give one valid mutation week", function()
		for _, t in { -5 * DAY, 0, 4_000_000_000 } do
			local e = WeeklyEvents.mutationEvent(t)
			expect(e.startsAt <= t and t < e.endsAt).toBe(true)
			expect(e.endsAt - e.startsAt).toBe(7 * DAY)
			expect(WeeklyEvents.next(t).startsAt > t).toBe(true)
			expect(WeeklyEvents.decode(WeeklyEvents.encode(t)) ~= nil).toBe(true)
		end
	end)
	it("trait ends inside its week and every trait id / mutation survives the attribute format", function()
		for w = 0, 11 do
			local t = MON + w * 7 * DAY
			local trait = WeeklyEvents.current(t + 5 * DAY + 19 * 3600)[2]
			expect(trait ~= nil).toBe(true)
			expect(trait.endsAt <= t + 7 * DAY).toBe(true)
			expect(WeeklyEvents.decode(WeeklyEvents.encode(t + 5 * DAY + 19 * 3600)) ~= nil).toBe(true)
			expect(WeeklyEvents.decode(WeeklyEvents.encode(t + 60)) ~= nil).toBe(true)
		end
	end)
	it("ISO weeks across a year edge: 2020-12-28 is W53, 2021-01-04 is W01, 2026-12-28 is W53", function()
		local function iso(t: number): (number, number)
			return WeeklyEvents.isoWeek(WeeklyEvents.weekIndex(t))
		end
		local y, n = iso(1_609_113_600) -- Mon 2020-12-28
		expect(y).toBe(2020)
		expect(n).toBe(53)
		y, n = iso(1_609_718_400) -- Mon 2021-01-04
		expect(y).toBe(2021)
		expect(n).toBe(1)
		y, n = iso(1_798_416_000) -- Mon 2026-12-28
		expect(y).toBe(2026)
		expect(n).toBe(53)
	end)
	it("waitSeconds stays within 1..SYNC_SECONDS for every minute of a week, fractional or not", function()
		for t = MON, MON + 7 * DAY, 997 do
			local w = WeeklyEventService.waitSeconds(t + 0.25)
			expect(w >= 1 and w <= Config.WEEKLY.SYNC_SECONDS).toBe(true)
		end
	end)
end)

describe("WeeklyEvents attribute decode", function()
	it("rejects malformed and hostile values without erroring", function()
		local good = WeeklyEvents.encode(MON + 60)
		for _, bad in
			{
				"",
				"|||||||",
				"1|Gold|5|-|0|trait|lucky",
				good .. "|extra",
				good .. "\n",
				string.rep("x", 5000),
				"1|Gold|5|-|0|trait|lucky|x",
				"1|Gold|abc|-|0|trait|lucky|5",
			}
		do
			expect(WeeklyEvents.decode(bad)).toBeNil()
		end
		for _, notString in { true, 1, {}, false } do
			expect(WeeklyEvents.decode(notString)).toBeNil()
		end
		expect(WeeklyEvents.decode(nil)).toBeNil()
		expect(WeeklyEvents.decode(good) ~= nil).toBe(true)
	end)
end)
