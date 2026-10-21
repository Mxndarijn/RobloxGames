--!strict
-- Wild Mystery Eggs (contract/mystery-egg.md): fountain drops, carrying, incubation, warm-up, stealing, hatching,
-- what clients see and saves.
local Actions = require("../src/server/Actions")
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local EggKind = require("../src/shared/EggKind")
local Fixtures = require("./Fixtures")
local Genome = require("../src/shared/Genome")
local Merge = require("../src/shared/Merge")
local MergePlan = require("../src/shared/MergePlan")
local PlayerData = require("../src/shared/PlayerData")
local Rng = require("../src/shared/Rng")
local SaveData = require("../src/shared/SaveData")
local Scene = require("../src/server/Scene")
local ServerEgg = require("../src/server/MysteryEgg")
local ServerFixtures = require("./ServerFixtures")
local SlimeLabel = require("../src/shared/SlimeLabel")
local Snapshot = require("../src/server/Snapshot")
local Spawner = require("../src/server/Spawner")
local SpeciesDex = require("../src/shared/SpeciesDex")
local StealService = require("../src/server/StealService")
local TestRunner = require("./TestRunner")
local World = require("../src/server/World")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

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

-- A hand-built egg record: a tier-`inner` slime sealed in a `kindId` egg.
local function egg(id: string, kindId: string, inner: number?, hatchAt: number?): Genome.Slime
	return Fixtures.slime(id, inner or 5, { species = "lop", egg = { kind = kindId, hatchAt = hatchAt } })
end

describe("EggKind table", function()
	it("every kind has a unique id, a positive weight and hatch time, and drops that sum to 1", function()
		local seen = {}
		for _, k in EggKind.list() do
			expect(seen[k.id]).toBeNil()
			seen[k.id] = true
			expect(k.weight > 0 and k.hatchSeconds > 0 and k.price > 0 and k.sell > 0).toBe(true)
			local total = 0
			for tier, p in EggKind.probabilities(k) do
				expect(tier >= 1 and tier <= Config.MAX_TIER).toBe(true)
				total += p
			end
			expect(math.abs(total - 1) < 1e-9).toBe(true)
		end
	end)
	it("rarer kinds hatch slower and only the Cosmic egg can hold a Secret (5 %)", function()
		local list = EggKind.list()
		for i = 2, #list do
			expect(list[i].hatchSeconds > list[i - 1].hatchSeconds).toBe(true)
			expect(list[i].weight < list[i - 1].weight).toBe(true)
		end
		for _, k in list do
			local secret = EggKind.probabilities(k)[Config.SECRET_TIER] or 0
			expect(secret).toBe(if k.id == "cosmic" then 0.05 else 0)
		end
	end)
	it("rolls kinds by weight under seeded sampling", function()
		local rng = Rng.new(99)
		local counts: { [string]: number } = {}
		local n = 20000
		for _ = 1, n do
			local k = EggKind.rollKind(rng:float())
			counts[k.id] = (counts[k.id] or 0) + 1
		end
		local total = 0
		for _, k in EggKind.list() do
			total += k.weight
		end
		for _, k in EggKind.list() do
			expect(math.abs((counts[k.id] or 0) / n - k.weight / total) < 0.015).toBe(true)
		end
	end)
	it("sanitizes saved egg fields: unknown kinds and non-finite times are dropped", function()
		expect(EggKind.sanitize({ kind = "golden", hatchAt = 5 })).toEqual({ kind = "golden", hatchAt = 5 })
		expect(EggKind.sanitize({ kind = "golden" })).toEqual({ kind = "golden" })
		expect(EggKind.sanitize({ kind = "golden", hatchAt = 0 / 0 })).toEqual({ kind = "golden" })
		expect(EggKind.sanitize({ kind = "dragon", hatchAt = 5 })).toBeNil()
		expect(EggKind.sanitize("golden")).toBeNil()
	end)
end)

describe("an egg record", function()
	it("earns nothing, shows its egg name and sells for its kind's price x the rebirth multiplier", function()
		local e = egg("e", "golden", 6)
		expect(Genome.baseIncome(e)).toBe(0)
		expect(Genome.displayName(e)).toBe("Golden Mystery Egg")
		expect(Economy.sellPrice(e, 0)).toBe(kind("golden").sell)
		expect(Economy.sellPrice(e, 2)).toBe(math.floor(kind("golden").sell * Economy.rebirthMultiplier(2)))
	end)
	it("is masked for clients: egg name and tier, no species, the real record untouched", function()
		local e = egg("e", "cosmic", 7, T0 + 60)
		local m = EggKind.mask(e)
		expect(m.name).toBe("Cosmic Mystery Egg")
		expect(m.tier).toBe(kind("cosmic").tier)
		expect(m.species).toBeNil()
		expect(m.egg.hatchAt).toBe(T0 + 60)
		expect(e.tier).toBe(7)
		expect(e.species).toBe("lop")
		local plain = Fixtures.slime("s", 3)
		expect(EggKind.mask(plain)).toBe(plain)
	end)
	it("is never merged, never a favourite, never grows and is not in the SlimeDex", function()
		local data = Fixtures.data({ egg("e1", "shiny", 3), egg("e2", "shiny", 3), Fixtures.slime("s", 3) })
		expect((Merge.canMerge(data.slimes[1], data.slimes[2]))).toBe(false)
		expect((Merge.findPair(data.slimes))).toBeNil()
		for _, c in MergePlan.fromData(data) do
			expect(MergePlan.excluded(c)).toBe(if c.id == "s" then nil else "egg")
		end
		expect(PlayerData.setFavorite(data, "e1")).toBe(false)
		expect(SpeciesDex.record(data, data.slimes[1])).toBe(false)
		expect(data.found.lop).toBeNil()
	end)
	it("labels with its countdown: on a pad, ready, and not yet incubating", function()
		local k = kind("speckled")
		expect(SlimeLabel.eggStatus(egg("e", "speckled"), T0)).toBe(
			`Hatches in {SlimeLabel.clock(k.hatchSeconds)} on a pad`
		)
		expect(SlimeLabel.eggStatus(egg("e", "speckled", 2, T0 + 125), T0)).toBe("Hatches in 2:05")
		expect(SlimeLabel.eggStatus(egg("e", "speckled", 2, T0), T0)).toBe("Ready to hatch!")
		expect(SlimeLabel.eggStatus(Fixtures.slime("s"), T0)).toBeNil()
		local name, tier = SlimeLabel.attributes(egg("e", "golden", 6))
		expect(name).toBe("Golden Mystery Egg")
		expect(tier).toBe(kind("golden").tier)
	end)
	it("survives a save round trip with its kind and hatch time", function()
		local data = Fixtures.data({ egg("e", "golden", 6, T0 + 300) })
		local back = SaveData.deserialize(SaveData.serialize(data, T0))
		local e = assert(PlayerData.findSlime(back, "e"))
		expect(e.egg).toEqual({ kind = "golden", hatchAt = T0 + 300 })
		expect(e.tier).toBe(6)
		expect(back.found.lop).toBeNil()
	end)
end)

describe("fountain eggs", function()
	it("drop now and then, never past the loose-egg cap, and never with the flag off", function()
		local world = ServerFixtures.world()
		world.eggRng = Rng.new(1)
		local eggs = 0
		for i = 1, 4000 do
			if Spawner.rollEgg(world, true) then
				eggs += 1
			end
			if i == 1 then
				expect(Spawner.rollEgg(world, false)).toBe(false)
			end
		end
		local rate = eggs / 4000
		expect(math.abs(rate - Config.MYSTERY_EGG.DROP_CHANCE) < 0.006).toBe(true)
		Spawner.spawnEgg(world, T0)
		for _ = 1, 500 do
			expect(Spawner.rollEgg(world, true)).toBe(false) -- MAX_WILD = 1 egg already loose
		end
	end)
	it("spawns a sealed egg on the lane with no hatch clock, a free or kind price and its tier's lifetime", function()
		local world = ServerFixtures.world()
		for _ = 1, 40 do
			local id = Spawner.spawnEgg(world, T0)
			local wild = world.wild[id]
			local k = assert(EggKind.of(wild.slime))
			expect(wild.slime.egg and wild.slime.egg.hatchAt).toBeNil()
			expect(wild.price == 0 or wild.price == k.price).toBe(true)
			-- A lucky egg holds one tier above its roll.
			local rolled = if wild.slime.egg and wild.slime.egg.lucky then wild.slime.tier - 1 else wild.slime.tier
			expect(EggKind.probabilities(k)[rolled] ~= nil).toBe(true)
			world.wild[id] = nil
		end
	end)
	it("announces Golden and Cosmic eggs to everyone, never the others", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1)
		for _ = 1, 200 do
			ServerFixtures.clearEvents(world)
			local id = Spawner.spawnEgg(world, T0)
			local k = assert(EggKind.of(world.wild[id].slime))
			local notes = ServerFixtures.notifications(world, nil)
			expect(#notes).toBe(if k.announce then 1 else 0)
			world.wild[id] = nil
		end
	end)
end)

-- A world with player 1 (home, empty plot) carrying a fresh speckled egg.
local function carryingEgg(): (World.World, World.Session, string)
	local world = ServerFixtures.world()
	local session = ServerFixtures.join(world, 1)
	local id = Spawner.spawnEgg(world, T0)
	local wild = world.wild[id]
	wild.slime.egg = { kind = "speckled" }
	wild.price = 0
	expect((Carry.grab(world, 1, id, 2, T0))).toBe(true)
	return world, session, id
end

describe("carrying and incubating", function()
	it("starts the hatch clock on the first pad and toasts that it is incubating", function()
		local world, session, id = carryingEgg()
		ServerFixtures.clearEvents(world)
		expect((Carry.deposit(world, 1, T0 + 10))).toBe(true)
		local e = assert(PlayerData.findSlime(session.data, id))
		expect(e.pad).toBe(1)
		expect((e.egg :: any).hatchAt).toBe(T0 + 10 + kind("speckled").hatchSeconds)
		expect(string.find(ServerFixtures.notifications(world, 1)[1], "is incubating", 1, true) ~= nil).toBe(true)
		expect(PlayerData.incomePerSecond(session.data)).toBe(0)
	end)
	it("never gets the Lucky Charm upgrade", function()
		for seed = 1, 30 do
			local world, session, id = carryingEgg()
			local inner = world.wild[id].slime.tier
			session.data.upgrades.Luck = 5 -- a 20 % chance per slime brought home
			world.rng = Rng.new(seed)
			Carry.deposit(world, 1, T0 + 1)
			expect(assert(PlayerData.findSlime(session.data, id)).tier).toBe(inner)
		end
	end)
	it("slows the carrier by the egg's shown tier, not the hidden one", function()
		local world, session, id = carryingEgg()
		local carry = assert(session.carry, "carrying")
		expect(carry.timer.tier).toBe(kind("speckled").tier)
		expect(carry.slimeId).toBe(id)
		expect(world.carriedBy[id]).toBe(1)
	end)
end)

-- Player 1 owns `slimes`; player 2 joins empty.
local function twoPlayers(slimes: { Genome.Slime }): (World.World, World.Session, World.Session)
	local world = ServerFixtures.world()
	local owner = ServerFixtures.join(world, 1, slimes)
	local thief = ServerFixtures.join(world, 2)
	return world, owner, thief
end

describe("MysteryEgg.step", function()
	it("warms the eggs of an owner at home and leaves the others", function()
		local world, owner, thief = twoPlayers({ egg("e", "golden", 5, T0 + 600) })
		thief.data.slimes = { egg("t", "golden", 5, T0 + 600) }
		thief.data.slimes[1].pad = 1
		owner.home = true
		ServerEgg.step(world, 10, T0)
		local warm = (Config.MYSTERY_EGG.WARM_SPEED - 1) * 10
		expect((owner.data.slimes[1].egg :: any).hatchAt).toBe(T0 + 600 - warm)
		expect((thief.data.slimes[1].egg :: any).hatchAt).toBe(T0 + 600)
	end)
	it("never warms past now and toasts the owner once when an egg turns ready", function()
		local world, owner = twoPlayers({ egg("e", "speckled", 2, T0 + 1) })
		owner.home = true
		ServerEgg.step(world, 60, T0)
		expect((owner.data.slimes[1].egg :: any).hatchAt).toBe(T0)
		local notes = ServerFixtures.notifications(world, 1)
		expect(#notes).toBe(1)
		expect(string.find(notes[1], "ready to hatch", 1, true) ~= nil).toBe(true)
		ServerFixtures.clearEvents(world)
		ServerEgg.step(world, 1, T0 + 1)
		expect(#ServerFixtures.notifications(world, 1)).toBe(0)
	end)
	it("starts the clock of a pad egg that has none (an old save)", function()
		local world, owner = twoPlayers({ egg("e", "shiny", 3) })
		ServerEgg.step(world, 1, T0)
		expect((owner.data.slimes[1].egg :: any).hatchAt).toBe(T0 + kind("shiny").hatchSeconds)
	end)
end)

describe("stealing an egg", function()
	it("moves the egg with its hatch time to the thief's plot", function()
		local world, owner, thief = twoPlayers({ egg("e", "golden", 6, T0 + 42) })
		ServerFixtures.unlock(owner)
		ServerFixtures.clearEvents(world)
		expect((StealService.steal(world, thief, "e", 2, T0))).toBe(true)
		local alarm = ServerFixtures.notifications(world, 1)[1]
		expect(string.find(alarm, "Golden Mystery Egg", 1, true) ~= nil).toBe(true)
		expect((Carry.deposit(world, 2, T0 + 5))).toBe(true)
		local e = assert(PlayerData.findSlime(thief.data, "e"))
		expect((e.egg :: any).hatchAt).toBe(T0 + 42)
		expect(PlayerData.findSlime(owner.data, "e")).toBeNil()
	end)
	it("can't be hatched while a thief carries it", function()
		local world, owner, thief = twoPlayers({ egg("e", "golden", 6, T0) })
		ServerFixtures.unlock(owner)
		StealService.steal(world, thief, "e", 2, T0)
		local ok, reason = ServerEgg.hatch(world, owner, "e", T0 + 1)
		expect(ok).toBe(false)
		expect(reason).toBe("egg is being stolen")
	end)
end)

describe("HatchEgg", function()
	it("refuses before the egg is ready, then hatches it in place into the slime inside", function()
		local world, owner = twoPlayers({ egg("e", "cosmic", 6, T0 + 200) })
		local early = Actions.handle(world, 1, "HatchEgg", table.pack("e"), T0 + 100, ctx)
		expect(early.ok).toBe(false)
		expect(early.message).toBe("egg is not ready")
		ServerFixtures.clearEvents(world)
		local res = Actions.handle(world, 1, "HatchEgg", table.pack("e"), T0 + 200, ctx)
		expect(res.ok).toBe(true)
		local slime = assert(PlayerData.findSlime(owner.data, "e"))
		expect(slime.egg).toBeNil()
		expect(slime.pad).toBe(1)
		expect(slime.tier).toBe(6)
		expect(owner.data.found.lop).toBe(true)
		expect(PlayerData.incomePerSecond(owner.data) > 0).toBe(true)
		local state = Snapshot.build(world, owner, T0 + 200)
		expect((state.egg :: any).hatched.slime.id).toBe("e")
		-- The toasts wait for the hatch show to reveal the slime; a Legendary+ hatch is toasted to the whole server.
		expect(#ServerFixtures.notifications(world, nil)).toBe(0)
		expect(#ServerFixtures.notifications(world, 1)).toBe(0)
		ServerEgg.step(world, 1, T0 + 200 + Config.MYSTERY_EGG.HATCH_REVEAL_SECONDS)
		expect(#ServerFixtures.notifications(world, nil)).toBe(1)
		expect(#ServerFixtures.notifications(world, 1)).toBe(1)
	end)
	it("refuses another player's egg and a slime that is not an egg", function()
		local world = twoPlayers({ egg("e", "speckled", 2, T0), Fixtures.slime("s", 2) })
		expect(Actions.handle(world, 2, "HatchEgg", table.pack("e"), T0, ctx).message).toBe("not your egg")
		expect(Actions.handle(world, 1, "HatchEgg", table.pack("s"), T0, ctx).message).toBe("not your egg")
	end)
	it("turns on the owner's hatch prompt only while the egg rests ready on its pad", function()
		local world = twoPlayers({ egg("e", "speckled", 2, T0 + 30) })
		expect(Scene.describe(world, T0)["e"].hatchReady).toBe(false)
		expect(Scene.describe(world, T0 + 30)["e"].hatchReady).toBe(true)
	end)
end)

describe("State for eggs", function()
	it("never shows the slime inside", function()
		local world, owner = twoPlayers({ egg("e", "golden", 6, T0 + 60) })
		local state = Snapshot.build(world, owner, T0)
		local view = state.slimes[1]
		expect(view.slime.name).toBe("Golden Mystery Egg")
		expect(view.slime.tier).toBe(kind("golden").tier)
		expect(view.slime.species).toBeNil()
		expect(view.income).toBe(0)
		expect(view.sellPrice).toBe(kind("golden").sell)
	end)
end)
