--!strict
-- Mystery Egg luck (contract/mystery-egg.md §40.3, §40.4, §40.6): lucky eggs, hatchling size, the lucky meter,
-- its save field, and the hatch record the show plays from.
local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local EggKind = require("../src/shared/EggKind")
local Fixtures = require("./Fixtures")
local Genome = require("../src/shared/Genome")
local MysteryEgg = require("../src/shared/MysteryEgg")
local PlayerData = require("../src/shared/PlayerData")
local Rng = require("../src/shared/Rng")
local SaveData = require("../src/shared/SaveData")
local Scene = require("../src/server/Scene")
local ServerEgg = require("../src/server/MysteryEgg")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")
local World = require("../src/server/World")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local CFG = Config.MYSTERY_EGG

local ctx: Actions.Context = {
	distanceBetween = function()
		return 2
	end,
	positionOf = function()
		return "pos"
	end,
}

local function kind(id: string): EggKind.Kind
	return assert(EggKind.get(id))
end

local function egg(id: string, kindId: string, inner: number, hatchAt: number?, lucky: boolean?): Genome.Slime
	return Fixtures.slime(id, inner, { species = "lop", egg = { kind = kindId, hatchAt = hatchAt, lucky = lucky } })
end

local function owner(slimes: { Genome.Slime }): (World.World, World.Session)
	local world = ServerFixtures.world()
	return world, ServerFixtures.join(world, 1, slimes)
end

describe("Lucky eggs and hatchlings", function()
	it("about LUCKY_CHANCE of eggs are lucky, one tier above a drop of their kind", function()
		local rng = Rng.new(40)
		local n, lucky = 4000, 0
		for i = 1, n do
			local slime, k = MysteryEgg.rollWild(rng, `e{i}`)
			local sealed = assert(slime.egg, "egg")
			local probs = EggKind.probabilities(k)
			if sealed.lucky then
				lucky += 1
				local below = probs[slime.tier - 1] ~= nil
				local capped = slime.tier == Config.MAX_TIER and probs[Config.MAX_TIER] ~= nil
				expect(below or capped).toBe(true)
			else
				expect(probs[slime.tier] ~= nil).toBe(true)
			end
		end
		expect(math.abs(lucky / n - CFG.LUCKY_CHANCE) < 0.015).toBe(true)
	end)
	it("hatchlings are born bigger than wild slimes, never under the tier's floor", function()
		local rng = Rng.new(41)
		for i = 1, 600 do
			local slime = MysteryEgg.rollWild(rng, `e{i}`)
			local low = math.max(CFG.HATCH_SIZE_MIN, Genome.sizeFloor(slime.tier))
			expect(slime.size >= low - 1e-9).toBe(true)
			expect(slime.size <= math.max(CFG.HATCH_SIZE_MIN + CFG.HATCH_SIZE_SPAN, low) + 1e-9).toBe(true)
		end
		expect(MysteryEgg.hatchSize(1, 0)).toBe(CFG.HATCH_SIZE_MIN)
		expect(MysteryEgg.hatchSize(1, 1)).toBe(CFG.HATCH_SIZE_MIN + CFG.HATCH_SIZE_SPAN)
	end)
	it("never shows `lucky` to a client and keeps it through sanitize and a save", function()
		local slime = egg("e", "golden", 6, T0 + 60, true)
		expect(EggKind.mask(slime).egg.lucky).toBeNil()
		expect((slime.egg :: any).lucky).toBe(true)
		expect((EggKind.sanitize({ kind = "golden", lucky = true }) :: any).lucky).toBe(true)
		expect((EggKind.sanitize({ kind = "golden", lucky = "yes" }) :: any).lucky).toBeNil()
		local data = Fixtures.data({ slime }, 100)
		local back = SaveData.deserialize(SaveData.serialize(data))
		expect((back.slimes[1].egg :: any).lucky).toBe(true)
	end)
	it("each kind's top tier is its best drop", function()
		expect(EggKind.topTier(kind("speckled"))).toBe(4)
		expect(EggKind.topTier(kind("cosmic"))).toBe(Config.SECRET_TIER)
		for _, k in EggKind.list() do
			expect(k.pity >= 2).toBe(true)
		end
	end)
end)

describe("Lucky meter", function()
	it("counts misses per kind and resets on the top tier", function()
		local data = PlayerData.new()
		data.slimes = { egg("a", "speckled", 2, T0), egg("b", "speckled", 4, T0) }
		data.slimes[1].pad, data.slimes[2].pad = 1, 2
		local rng = Rng.new(1)
		expect((MysteryEgg.hatchEgg(data, "a", T0, rng))).toBe(true)
		expect((data.eggLuck :: any).speckled).toBe(1)
		expect(MysteryEgg.meterText(data, kind("speckled"))).toBe(`Lucky 1/{kind("speckled").pity - 1}`)
		expect((MysteryEgg.hatchEgg(data, "b", T0, rng))).toBe(true)
		expect((data.eggLuck :: any).speckled).toBe(0)
	end)
	it("a full meter turns a miss into the kind's top tier, same id and pad, and resets", function()
		local k = kind("golden")
		local data = PlayerData.new()
		data.slimes = { egg("g", "golden", 4, T0) }
		data.slimes[1].pad = 3
		data.eggLuck = { golden = k.pity - 1 }
		expect(MysteryEgg.guaranteed(data, k)).toBe(true)
		expect(MysteryEgg.meterText(data, k)).toBe(`Lucky {k.pity - 1}/{k.pity - 1}`)
		local ok, slime, info = MysteryEgg.hatchEgg(data, "g", T0, Rng.new(2))
		expect(ok).toBe(true)
		local hatched = slime :: Genome.Slime
		expect(hatched.tier).toBe(EggKind.topTier(k))
		expect(hatched.id).toBe("g")
		expect(hatched.pad).toBe(3)
		expect(hatched.egg).toBeNil()
		expect(hatched.size >= CFG.HATCH_SIZE_MIN).toBe(true)
		expect(PlayerData.findSlime(data, "g")).toBe(hatched)
		expect((info :: any).guaranteed).toBe(true)
		expect((data.eggLuck :: any).golden).toBe(0)
	end)
	it("one short of full changes nothing about the slime inside", function()
		local k = kind("golden")
		local data = PlayerData.new()
		data.slimes = { egg("g", "golden", 4, T0) }
		data.slimes[1].pad = 1
		data.eggLuck = { golden = k.pity - 2 }
		local _, slime, info = MysteryEgg.hatchEgg(data, "g", T0, Rng.new(3))
		expect((slime :: Genome.Slime).tier).toBe(4)
		expect((info :: any).guaranteed).toBe(false)
		expect((data.eggLuck :: any).golden).toBe(k.pity - 1)
	end)
	it("saves known kinds only, whole and in range; missing is empty", function()
		local clean = SaveData.cleanEggLuck({ golden = 3.7, cosmic = 999, nope = 2, shiny = "x", speckled = -4 })
		expect(clean).toEqual({ golden = 3, cosmic = kind("cosmic").pity - 1, speckled = 0 })
		expect(SaveData.cleanEggLuck(nil)).toEqual({})
		local data = Fixtures.data({}, 100)
		data.eggLuck = { shiny = 5 }
		expect(SaveData.deserialize(SaveData.serialize(data)).eggLuck).toEqual({ shiny = 5 })
	end)
end)

describe("Hatch show record", function()
	it("records the hatch for the show and toasts the owner only at the reveal", function()
		local world, session = owner({ egg("e", "golden", 4, T0, true) })
		expect(Actions.handle(world, 1, "HatchEgg", table.pack("e"), T0, ctx).ok).toBe(true)
		local hatch = assert(world.hatches.e, "hatch")
		expect(hatch.at).toBe(T0)
		expect(hatch.kind).toBe("golden")
		expect(hatch.lucky).toBe(true)
		expect(Scene.describe(world, T0).e.hatch).toBe(hatch)
		expect(#ServerFixtures.notifications(world, 1)).toBe(0)
		ServerEgg.step(world, 1, T0 + CFG.HATCH_REVEAL_SECONDS)
		local notes = ServerFixtures.notifications(world, 1)
		expect(#notes).toBe(1)
		expect(string.sub(notes[1], 1, 11)).toBe("Lucky egg! ")
		expect(session.egg ~= nil).toBe(true)
		ServerEgg.step(world, 1, T0 + CFG.HATCH_FX_SECONDS)
		expect(world.hatches.e).toBeNil()
		expect(Scene.describe(world, T0 + CFG.HATCH_FX_SECONDS).e.hatch).toBeNil()
	end)
	it("shows the lucky meter on a ready egg's hatch prompt", function()
		local world, session = owner({ egg("e", "golden", 4, T0) })
		session.data.eggLuck = { golden = 2 }
		expect(Scene.describe(world, T0).e.hatchText).toBe(`Golden Mystery Egg · Lucky 2/{kind("golden").pity - 1}`)
		expect(Scene.describe(world, T0 - 10).e.hatchText).toBeNil()
	end)
	it("the ready toast names a full lucky meter", function()
		local k = kind("shiny")
		local world, session = owner({ egg("e", "shiny", 3, T0) })
		session.data.eggLuck = { shiny = k.pity - 1 }
		ServerEgg.step(world, 1, T0)
		local notes = ServerFixtures.notifications(world, 1)
		expect(#notes).toBe(1)
		expect(string.find(notes[1], "lucky meter is full: it hatches a Legendary or better", 1, true) ~= nil).toBe(
			true
		)
	end)
end)
