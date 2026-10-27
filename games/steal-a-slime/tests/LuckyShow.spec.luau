--!strict
-- The Lucky Charm show on the pad (contract/lucky-charm.md).
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Genome = require("../src/shared/Genome")
local LuckyShow = require("../src/server/LuckyShow")
local Rng = require("../src/shared/Rng")
local Scene = require("../src/server/Scene")
local ServerFixtures = require("./ServerFixtures")
local SlimeRoster = require("../src/shared/SlimeRoster")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local T0 = ServerFixtures.T0
local MORPH = Config.LUCKY_SHOW.MORPH_SECONDS

-- A lucky deposit of a wild Legendary Ninja at T0; returns the world and the promoted slime.
local function luckyNinja(): (any, Genome.Slime)
	local world = ServerFixtures.world()
	local s = ServerFixtures.join(world, 1)
	s.data.slimes = {}
	s.data.upgrades.Luck = 5
	s.data.rebirths = Config.CATCH_REBIRTHS[6] or 0 -- Mythic is open to this player (luck never skips the ladder)
	world.rng = {
		float = function()
			return 0
		end,
	} :: any
	local wild = Genome.generate(Rng.new(3), { id = "w1", tier = 5 })
	wild.species, wild.name = "ninja", "Ninja"
	world.wild.w1 = { slime = wild, price = 0, spawnedAt = T0, expiresAt = T0 + 60, angle = 0, radius = 40 }
	assert((Carry.grab(world, 1, "w1", 1, T0)), "grab")
	ServerFixtures.clearEvents(world)
	assert((Carry.deposit(world, 1, T0)), "deposit")
	return world, s.data.slimes[1]
end

describe("LuckyShow", function()
	it("the pad shows the caught Ninja until the morph, then the Mythic species", function()
		local world, slime = luckyNinja()
		expect(slime.tier).toBe(6)
		expect((SlimeRoster.get(slime.species :: string) :: any).tier).toBe(6)
		local before = Scene.describe(world, T0 + MORPH / 2).w1
		expect(before.slime.species).toBe("ninja")
		expect(before.slime.tier).toBe(5)
		expect(before.slime.pad).toBe(slime.pad)
		expect(before.lucky ~= nil).toBe(true)
		local after = Scene.describe(world, T0 + MORPH).w1
		expect(after.slime).toBe(slime)
		expect(after.lucky ~= nil).toBe(true) -- the burst attributes stay on the new model
	end)
	it("the owner hears Lucky at the morph, and the show is forgotten after FX_SECONDS", function()
		local world, slime = luckyNinja()
		local function lucky(): { any }
			local out = {}
			for _, event in world.outbox do
				if event.type == "Notify" and event.sound == "Lucky" then
					table.insert(out, event)
				end
			end
			return out
		end
		LuckyShow.step(world, T0 + MORPH / 2)
		expect(#lucky()).toBe(0)
		LuckyShow.step(world, T0 + MORPH)
		local told = lucky()
		expect(#told).toBe(1)
		expect(told[1].userId).toBe(1)
		expect(told[1].text).toBe(`Lucky! Your Legendary Ninja became {Genome.displayName(slime)}!`)
		LuckyShow.step(world, T0 + Config.LUCKY_SHOW.FX_SECONDS)
		expect(world.lucky.w1).toBeNil()
		expect(Scene.describe(world, T0 + Config.LUCKY_SHOW.FX_SECONDS).w1.lucky).toBeNil()
	end)
end)
