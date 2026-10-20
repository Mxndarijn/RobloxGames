--!strict
-- Slime life on the lane (contract/slime-life.md): SlimePersona covers every species, ParadeChoreo plans keep every
-- slime on its timetable (back on its spot between beats and at the drain, inside the leash, never backwards), and
-- the server hands lane wilds a plan that a grab takes away.
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local ParadeChoreo = require("../src/shared/ParadeChoreo")
local ParadeLane = require("../src/shared/ParadeLane")
local ServerFixtures = require("./ServerFixtures")
local SlimePersona = require("../src/shared/SlimePersona")
local SlimeRoster = require("../src/shared/SlimeRoster")
local Spawner = require("../src/server/Spawner")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

local function walk(lifetime: number): (number, number)
	local _, seconds, lead = ParadeLane.walkTimes(0, lifetime)
	return seconds, lead
end

describe("SlimePersona", function()
	it("gives every roster species a gait, a temperament and a hop style", function()
		local gaits, tempers = {}, {}
		for _, g in SlimePersona.GAITS do
			gaits[g] = true
		end
		for _, t in SlimePersona.TEMPERS do
			tempers[t] = true
		end
		for _, entry in SlimeRoster.ROSTER do
			local p = SlimePersona.BY_SPECIES[entry.id]
			expect(p ~= nil).toBe(true)
			expect(gaits[p.gait]).toBe(true)
			expect(tempers[p.temper]).toBe(true)
			expect(p.hop.height > 0 and p.hop.air > 0 and p.hop.wait > 0 and p.hop.settle >= 0).toBe(true)
		end
		for id in SlimePersona.BY_SPECIES do
			expect(SlimeRoster.get(id) ~= nil).toBe(true)
		end
	end)
	it("falls back to DEFAULT for an unknown or missing species", function()
		expect(SlimePersona.of(nil)).toBe(SlimePersona.DEFAULT)
		expect(SlimePersona.of("no_such_slime")).toBe(SlimePersona.DEFAULT)
		expect(SlimePersona.of("froggo").gait).toBe("Hop")
	end)
end)

describe("ParadeChoreo plans", function()
	local seconds, lead = walk(Config.WILD_LIFETIME)

	it("are the same plan for the same seed (server and client build it apart)", function()
		local a = ParadeChoreo.plan(12345, "Curious", seconds, lead)
		local b = ParadeChoreo.plan(12345, "Curious", seconds, lead)
		expect(#a.beats > 0).toBe(true)
		expect(#a.beats).toBe(#b.beats)
		for i, beat in a.beats do
			expect(beat.kind).toBe(b.beats[i].kind)
			expect(beat.s0).toBe(b.beats[i].s0)
		end
	end)

	it("keep every slime on its timetable for many seeds and every temperament", function()
		local leash = ParadeChoreo.LEASH + 1e-6
		for _, temper in SlimePersona.TEMPERS do
			for seed = 1, 150 do
				local plan = ParadeChoreo.plan(seed * 7919, temper, seconds, lead)
				expect(math.abs(ParadeChoreo.offset(plan, seconds))).toBeCloseTo(0, 1e-6)
				expect(math.abs(ParadeChoreo.offset(plan, seconds + 5))).toBeCloseTo(0, 1e-6)
				local last = -math.huge
				for _, beat in plan.beats do
					expect(beat.t0 >= lead + ParadeChoreo.FIRST_AFTER - 1e-9).toBe(true)
					expect(beat.e <= seconds - ParadeChoreo.QUIET_END + 1e-9).toBe(true)
					expect(beat.t0 >= last).toBe(true)
					expect(beat.s0 < beat.s1 and beat.s1 < beat.e).toBe(true)
					expect(math.abs(ParadeChoreo.offset(plan, beat.e))).toBeCloseTo(0, 1e-6)
					expect(ParadeChoreo.speed(plan, (beat.s0 + beat.s1) / 2)).toBeCloseTo(0, 1e-9)
					last = beat.e
				end
				for t = 0, seconds, 0.1 do
					local o = ParadeChoreo.offset(plan, t)
					local m = ParadeChoreo.speed(plan, t)
					expect(math.abs(o) <= leash).toBe(true)
					expect(m >= 0 and m <= ParadeChoreo.CATCH_SPEED + 1e-9).toBe(true)
				end
			end
		end
	end)

	it("pick only beats their temperament has", function()
		for _, temper in SlimePersona.TEMPERS do
			local weights = ParadeChoreo.WEIGHTS[temper]
			for seed = 1, 60 do
				for _, beat in ParadeChoreo.plan(seed * 31, temper, seconds, lead).beats do
					expect((weights[beat.kind] or 0) > 0).toBe(true)
				end
			end
		end
	end)

	it("say which beat runs, its phase and how far through it", function()
		local plan = ParadeChoreo.plan(424242, "Lazy", seconds, lead)
		local b = plan.beats[1]
		local before = ParadeChoreo.beatAt(plan, b.t0 - 0.01)
		expect(before == nil or before ~= b).toBe(true)
		local pre, phase = ParadeChoreo.beatAt(plan, (b.t0 + b.s0) / 2)
		expect(pre).toBe(b)
		expect(phase).toBe("pre")
		local mid, phase2, u = ParadeChoreo.beatAt(plan, b.s0 + b.stop / 2)
		expect(mid).toBe(b)
		expect(phase2).toBe("stop")
		expect(u).toBeCloseTo(0.5, 1e-9)
		local _, phase3 = ParadeChoreo.beatAt(plan, (b.s1 + b.e) / 2)
		expect(phase3).toBe("post")
	end)

	it("seeds fit a float32 attribute and about COPY_PERCENT of ids are copycats", function()
		local copies = 0
		for i = 1, 4000 do
			local id = `w{i}`
			local seed = ParadeChoreo.seedFor(id)
			expect(seed >= 0 and seed < 2 ^ 24).toBe(true)
			if ParadeChoreo.copies(id) then
				copies += 1
			end
		end
		expect(math.abs(copies / 4000 - ParadeChoreo.COPY_PERCENT / 100) < 0.04).toBe(true)
	end)
end)

describe("ParadeLane with lane beats", function()
	it("moves a slime ahead or behind its plain spot by the plan, clamped to the lane", function()
		local plain = ParadeLane.pose(0, 100, 0, 40)
		local ahead = ParadeLane.pose(0, 100, 0, 40, 3)
		local s = ParadeLane.distance(0, 100, 40)
		local x, z = ParadeLane.offsetAt(s + 3, 0)
		expect(ahead.position[1]).toBeCloseTo(x, 1e-9)
		expect(ahead.position[3]).toBeCloseTo(z, 1e-9)
		expect(plain.position[1] ~= ahead.position[1] or plain.position[3] ~= ahead.position[3]).toBe(true)
		local endX, endZ = ParadeLane.offsetAt(ParadeLane.LENGTH, 0)
		local late = ParadeLane.pose(0, 100, 0, 100 - ParadeLane.DRAIN_SECONDS - 0.01, 50)
		expect(late.position[1]).toBeCloseTo(endX, 1e-6)
		expect(late.position[3]).toBeCloseTo(endZ, 1e-6)
	end)
	it("walkTimes: the walk starts at the slide mouth and the lead-in is its first share", function()
		local startAt, seconds, lead = ParadeLane.walkTimes(10, 10 + Config.WILD_LIFETIME)
		expect(startAt).toBeCloseTo(10 + ParadeLane.RIDE_SECONDS, 1e-9)
		expect(seconds).toBeCloseTo(Config.WILD_LIFETIME - ParadeLane.RIDE_SECONDS - ParadeLane.DRAIN_SECONDS, 1e-9)
		expect(lead > 0 and lead < seconds).toBe(true)
	end)
end)

describe("Spawner lane beats", function()
	it("gives a lane wild a plan seed, none with the feature off", function()
		local world = ServerFixtures.world()
		local id = Spawner.spawnOne(world, T0)
		local wild = world.wild[id]
		if Config.FEATURES.SlimeChoreo and Config.FEATURES.Parade then
			expect(wild.choreo ~= nil).toBe(true)
		end
		expect(Spawner.choreoFor(world, "x", wild.slime, T0, false)).toBeNil()
	end)
	it("a copycat of the same species right behind takes the seed of the slime ahead", function()
		if not Config.FEATURES.Parade then
			return
		end
		local world = ServerFixtures.world()
		local leaderId = Spawner.spawnOne(world, T0)
		local leader = world.wild[leaderId]
		leader.choreo = { seed = 777 }
		local copyId = nil
		for i = 1, 200 do
			if ParadeChoreo.copies(`c{i}`) then
				copyId = `c{i}`
				break
			end
		end
		assert(copyId, "some id is a copycat")
		local same = table.clone(leader.slime)
		local copy = Spawner.choreoFor(world, copyId, same, T0 + Config.SPAWN_INTERVAL, true)
		expect(copy and copy.seed).toBe(777)
		local other = table.clone(leader.slime)
		other.species = if leader.slime.species == "gummy" then "mochi" else "gummy"
		local own = Spawner.choreoFor(world, copyId, other, T0 + Config.SPAWN_INTERVAL, true)
		expect(own and own.seed).toBe(ParadeChoreo.seedFor(copyId))
		-- too far behind: its own beats
		local late = Spawner.choreoFor(world, copyId, same, T0 + ParadeChoreo.COPY_WINDOW + 1, true)
		expect(late and late.seed).toBe(ParadeChoreo.seedFor(copyId))
	end)
	it("a grab takes the plan away (it walks back with a plain glide)", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1, nil, 0)
		local id = Spawner.spawnOne(world, T0)
		world.wild[id].price = 0
		world.wild[id].choreo = { seed = 5 }
		expect((Carry.grab(world, 1, id, 5, T0))).toBe(true)
		expect(world.wild[id].choreo).toBeNil()
	end)
end)
