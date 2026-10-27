--!strict
-- The weekly featured event Secret (CONTRACT.md §34): rotation, the spawn pool, State and ownership.
local Economy = require("../src/shared/Economy")
local EventSecrets = require("../src/shared/EventSecrets")
local Fixtures = require("./Fixtures")
local Fountain = require("../src/shared/Fountain")
local Genome = require("../src/shared/Genome")
local Rng = require("../src/shared/Rng")
local ServerFixtures = require("./ServerFixtures")
local SlimeRoster = require("../src/shared/SlimeRoster")
local Snapshot = require("../src/server/Snapshot")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")
local TripleMerge = require("../src/shared/TripleMerge")
local WeeklyEvents = require("../src/shared/WeeklyEvents")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local DAY = 86400
local SECRET = SlimeRoster.SECRET_TIER
local WEEK0 = WeeklyEvents.weekIndex(ServerFixtures.T0)
local MON = WeeklyEvents.weekStart(WEEK0) -- a Monday 00:00 UTC

local function isEvent(id: string?): boolean
	local entry = id and SlimeRoster.get(id)
	return entry ~= nil and entry.kind == "event"
end

describe("EventSecrets rotation", function()
	it("rotates through every event Secret of the roster, one per week", function()
		local seen: { [string]: boolean } = {}
		local count = 0
		for w = 0, #EventSecrets.ROTATION - 1 do
			local id = EventSecrets.featured(MON + w * 7 * DAY + DAY).id
			expect(isEvent(id)).toBe(true)
			if not seen[id] then
				seen[id] = true
				count += 1
			end
		end
		expect(count).toBe(7)
		expect(#EventSecrets.ROTATION).toBe(#SlimeRoster.ofKind("event"))
	end)
	it("is a pure function of the clock: the same all week, a different one next week", function()
		local first = EventSecrets.featured(MON)
		expect(EventSecrets.featured(MON + 3 * DAY + 4321).id).toBe(first.id)
		expect(EventSecrets.featured(MON + 7 * DAY - 1).id).toBe(first.id)
		expect(EventSecrets.featured(MON + 7 * DAY).id ~= first.id).toBe(true)
		expect(EventSecrets.featured(MON - 1).id ~= first.id).toBe(true)
		-- Repeats after a full cycle.
		expect(EventSecrets.featured(MON + #EventSecrets.ROTATION * 7 * DAY).id).toBe(first.id)
	end)
	it("runs Monday 00:00 to the next Monday 00:00 UTC", function()
		local f = EventSecrets.featured(MON + 2 * DAY)
		expect(f.startsAt).toBe(MON)
		expect(f.endsAt).toBe(MON + 7 * DAY)
		expect(os.date("!%A %H:%M", f.startsAt)).toBe("Monday 00:00")
		expect(f.week).toBe(WEEK0)
		expect(f.name).toBe((SlimeRoster.get(f.id) :: SlimeRoster.Entry).name)
	end)
end)

describe("EventSecrets.featuredWeek", function()
	it("is this week for the featured Secret and the next featured week for the others", function()
		local now = MON + 2 * DAY
		expect(EventSecrets.featuredWeek(EventSecrets.featured(now).id, now)).toBe(MON)
		for offset = 1, #EventSecrets.ROTATION - 1 do
			local later = MON + offset * 7 * DAY
			expect(EventSecrets.featuredWeek(EventSecrets.featured(later).id, now)).toBe(later)
		end
		expect(EventSecrets.featuredWeek("midas", now)).toBeNil()
		expect(EventSecrets.featuredWeek("nope", now)).toBeNil()
	end)
end)

describe("EventSecrets in the spawn pool", function()
	it("rollSpecies adds the extra Secret as one equal slot of its own tier only", function()
		local extra = EventSecrets.extraSpecies(MON)
		local classic = SlimeRoster.forTier(SECRET)
		local last = Genome.rollSpecies(SECRET, 0.9999, nil, extra) :: SlimeRoster.Entry
		expect(last.id).toBe(extra[1].id)
		local first = Genome.rollSpecies(SECRET, 0, nil, extra) :: SlimeRoster.Entry
		expect(first.id).toBe(classic[1].id)
		-- Starlight open: midas, eclipse, boo plus the featured one, a quarter each.
		local starlight = { "starlight" }
		expect(#Genome.speciesPool(SECRET, starlight, extra)).toBe(4)
		expect((Genome.rollSpecies(SECRET, 0.9999, starlight, extra) :: SlimeRoster.Entry).id).toBe(extra[1].id)
		expect((Genome.rollSpecies(SECRET, 0.7, starlight, extra) :: SlimeRoster.Entry).id ~= extra[1].id).toBe(true)
		for tier = 1, SECRET - 1 do
			for _, roll in { 0, 0.5, 0.9999 } do
				local entry = Genome.rollSpecies(tier, roll, nil, extra)
				expect(entry and entry.kind).toBe("spawn")
			end
		end
	end)
	it("only the featured event Secret drops from a tier-7 fountain roll, at its species weight", function()
		for w = 0, #EventSecrets.ROTATION - 1 do
			local now = MON + w * 7 * DAY + DAY
			local featured = EventSecrets.featured(now).id
			local rng = Rng.new(11 + w)
			local hits = 0
			for i = 1, 400 do
				local drop = Fountain.roll(rng, `s{i}`, false, SECRET, nil, nil, EventSecrets.extraSpecies(now))
				local species = drop.slime.species :: string
				expect(drop.slime.tier).toBe(SECRET)
				if isEvent(species) then
					expect(species).toBe(featured)
					hits += 1
				end
			end
			-- Classic has one Secret (midas); the event Secret earns more, so it is rarer (Genome.speciesWeight).
			local we = Genome.speciesWeight(SlimeRoster.get(featured) :: any)
			local share = we / (we + Genome.speciesWeight(SlimeRoster.get("midas") :: any))
			expect(math.abs(hits / 400 - share) < 0.06).toBe(true)
		end
	end)
	it("no event Secret drops without the featured list (merges, boss, no clock)", function()
		local rng = Rng.new(5)
		for i = 1, 300 do
			local drop = Fountain.roll(rng, `n{i}`, false, SECRET)
			expect(isEvent(drop.slime.species)).toBe(false)
		end
		local inputs = {
			Fixtures.slime("a", SECRET, { species = "kitsune" }),
			Fixtures.slime("b", SECRET, { species = "kitsune" }),
			Fixtures.slime("c", SECRET, { species = "kitsune" }),
		}
		for i = 1, 100 do
			local child = TripleMerge.merge(inputs, rng, `m{i}`)
			expect(child.tier).toBe(SECRET)
			expect(isEvent(child.species)).toBe(false)
		end
	end)
	it("Spawner.spawnOne passes this week's featured Secret, and none without a clock", function()
		local seen: { any } = {}
		local calls = 0
		local fountain: any = Fountain
		local roll = Fountain.roll
		local original = Spawner.unixTime
		fountain.roll = function(...)
			calls += 1
			seen[calls] = select(7, ...)
			return roll(...)
		end
		local world = ServerFixtures.world()
		Spawner.spawnOne(world, ServerFixtures.T0)
		Spawner.unixTime = function()
			return MON + DAY
		end
		Spawner.spawnOne(world, ServerFixtures.T0)
		Spawner.unixTime = original
		fountain.roll = roll
		expect(calls).toBe(2)
		expect(seen[1]).toBeNil()
		expect(seen[2][1].id).toBe(EventSecrets.featured(MON + DAY).id)
	end)
end)

describe("EventSecrets after the week", function()
	it("an owned event Secret keeps its species, earns and shows in State", function()
		local slime = Fixtures.slime("k", SECRET, { species = "glitch", name = "Gl1tch" })
		local kept = Genome.sanitize(slime) :: Genome.Slime
		expect(kept.species).toBe("glitch")
		expect(kept.tier).toBe(SECRET)
		expect(Economy.slimeIncome(kept, 0) > 0).toBe(true)
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, { kept }, 0)
		local state = Snapshot.build(world, session, ServerFixtures.T0)
		local found = false
		for _, view in state.slimes do
			if view.slime.species == "glitch" then
				found = true
			end
		end
		expect(found).toBe(true)
	end)
	it("State.featuredSecret is this week's Secret with its end time", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, {}, 0)
		local now = MON + 2 * DAY
		local state = Snapshot.build(world, session, now)
		local featured = EventSecrets.featured(now)
		local view = state.featuredSecret :: any
		expect(view.id).toBe(featured.id)
		expect(view.name).toBe(featured.name)
		expect(view.endsAt).toBe(MON + 7 * DAY)
	end)
end)
