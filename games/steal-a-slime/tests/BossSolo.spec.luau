--!strict
-- One player clears every boss alone on a full server (src/server/BossEvent.luau, contract/boss-event.md "Meter"):
-- the other players stay at their bases, the fighter never dodges, eats every attack (knockback and stun) and pops
-- the guards when the boss calls them.
local BossChoreo = require("../src/shared/BossChoreo")
local BossEvent = require("../src/server/BossEvent")
local Config = require("../src/shared/Config")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local BOSS = Config.BOSS
local FPS = 30

type Vec = { X: number, Y: number, Z: number }

-- Seconds a lone fighter takes to fill the meter of the boss at rotation slot `index`, on a server of `players`.
local function soloClear(index: number, players: number): (string, number?)
	local w = ServerFixtures.world()
	w.startedAt = T0 - Config.RAIN_FIRST_AT - Config.RAIN_DURATION - 600
	w.nextSpawnAt = math.huge
	for userId = 1, players do
		ServerFixtures.join(w, userId, nil, 0)
	end
	w.bossIndex = index
	w.fountainTier = BOSS.SECRET_FOUNTAIN_TIER
	w.nextBossAt = T0 + BOSS.WARNING_SECONDS
	local at: { [number]: Vec } = {}
	local ctx = {
		pose = function(userId: number): (Vec?, Vec?)
			return at[userId], { X = 1, Y = 0, Z = 0 }
		end,
		plazaOrigin = function(): Vec
			return { X = 0, Y = 0, Z = 0 }
		end,
		airborne = function(_userId: number): boolean
			return false
		end,
		launch = function(_userId: number, _push: Vec, _landing: Vec): boolean
			return true
		end,
	}
	BossEvent.step(w, T0, ctx)
	local start = T0 + BOSS.WARNING_SECONDS
	BossEvent.step(w, start, ctx)
	local species = w.boss.fight.species
	local s = w.sessions[1]
	local nextSwing = start
	local t = start
	while w.boss.fight.phase == "fight" and t < start + BOSS.FIGHT_SECONDS do
		t += 1 / FPS
		local wild = w.wild[BossEvent.bossId(w) :: string]
		if wild and wild.move then
			local x, z, hx, hz = BossChoreo.pose(wild.move, t)
			at[1] = { X = x + hx * 8, Y = 3, Z = z + hz * 8 } -- in front of it, in bat reach
		end
		BossEvent.step(w, t, ctx)
		if t >= nextSwing then
			nextSwing = t + BOSS.HIT_GAP
			local guard: Vec? = nil
			for _, g in BossEvent.guardSpots(w, ctx) do
				guard = g
				break
			end
			if guard then
				BossEvent.hitGuard(w, s, t, { X = guard.X - 3, Y = 3, Z = guard.Z }, { X = 1, Y = 0, Z = 0 }, ctx)
			else
				BossEvent.hit(w, s, t, at[1], ctx)
			end
		end
	end
	return species, if w.boss.fight.phase == "haul" then t - start else nil
end

describe("BossEvent solo clear", function()
	-- One rotation slot per boss species (the Secret ones at slots 5 and 10).
	for _, index in { 1, 2, 3, 4, 5, 10 } do
		it(`a lone fighter on a full server clears rotation slot {index} in time`, function()
			local species, seconds = soloClear(index, Config.PLOT_COUNT)
			expect(BOSS.ROTATION[index]).toBe(species)
			expect(seconds ~= nil).toBe(true)
		end)
	end
end)
