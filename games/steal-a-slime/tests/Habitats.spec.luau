--!strict
local Carry = require("../src/server/Carry")
local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local HabitatPads = require("../src/server/HabitatPads")
local Habitats = require("../src/shared/Habitats")
local MeshAssets = require("../src/shared/MeshAssets")
local PlayerData = require("../src/shared/PlayerData")
local ServerFixtures = require("./ServerFixtures")
local Sessions = require("../src/server/Sessions")
local SlimeRoster = require("../src/shared/SlimeRoster")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local BASE = Habitats.BASE

local function species(id: string, speciesId: string)
	local entry = SlimeRoster.get(speciesId)
	assert(entry, speciesId)
	return Fixtures.slime(id, math.min(entry.tier, 6), { species = speciesId })
end

-- Pad state after one server view tick at `now` (flag on).
local function tick(state, world, now: number)
	return HabitatPads.step(state, world, now, true)
end

local function padId(state, plotIndex: number, pad: number): string?
	local s = HabitatPads.get(state, plotIndex, pad)
	return s and s.id
end

-- Client that watched the pad from the start: steps weights in 0.05 s frames.
local function run(weights: Habitats.Weights, id: string, seconds: number): Habitats.Weights
	local w = weights
	for _ = 1, math.round(seconds / 0.05) do
		w = Habitats.stepWeights(w, id, 0.05)
	end
	return w
end

describe("Habitats table", function()
	it("maps every slime type in the roster to a real, non-base habitat", function()
		for _, entry in SlimeRoster.ROSTER do
			local id = Habitats.forType(entry.id, nil)
			expect(id ~= BASE).toBe(true)
			expect(Habitats.get(id) ~= nil).toBe(true)
		end
	end)
	it("gives every rarity tier and the Secret tier a family habitat", function()
		for tier = 1, #Config.RARITIES do
			expect(Habitats.forType(nil, tier) ~= BASE).toBe(true)
		end
		expect(Habitats.forType(nil, SlimeRoster.SECRET_TIER)).toBe("crystal_grotto")
	end)
	it("falls back to the tier family for slimes without a type (merged / pre-v28)", function()
		expect(Habitats.forSlime(Fixtures.slime("m", 2))).toBe("flower_bed")
		expect(Habitats.forSlime(Fixtures.slime("m", 6))).toBe("crystal_grotto")
		expect(Habitats.forType("not_a_type", 0)).toBe(BASE)
	end)
	it("prefers a per-type habitat over the family", function()
		expect(Habitats.forSlime(species("a", "honey_queen"))).toBe("syrup_pool")
		expect(Habitats.forSlime(species("b", "harvest_king"))).toBe("show_stool")
	end)
	it("reuses an uploaded kit pad for every look except the new mesh slots", function()
		for _, habitat in Habitats.LIST do
			if habitat.id ~= BASE and not habitat.newMesh then
				expect(MeshAssets.meshId(habitat.kit :: string) ~= nil).toBe(true)
			end
		end
		expect(Habitats.MESH_SLOTS).toEqual({ "candy_patch", "crystal_grotto" })
	end)
end)

describe("HabitatPads (server pad state)", function()
	it("sets the slime's habitat on its pad when placed; empty pads stay base", function()
		local world = ServerFixtures.world()
		local state = HabitatPads.new()
		local owner = ServerFixtures.join(world, 1, { species("s1", "rock_candy") })
		tick(state, world, T0)
		expect(padId(state, owner.plotIndex, 1)).toBe("crystal_grotto")
		expect(padId(state, owner.plotIndex, 2)).toBe(BASE)
		expect(padId(state, owner.plotIndex % world.plotCount + 1, 1)).toBe(BASE)
		local s = HabitatPads.get(state, owner.plotIndex, 1) :: Habitats.PadState
		expect(s.from).toBe(BASE)
		expect(s.at).toBe(T0)
	end)
	it("reverts the pad to base when the owner leaves", function()
		local world = ServerFixtures.world()
		local state = HabitatPads.new()
		local owner = ServerFixtures.join(world, 1, { species("s1", "puddle") })
		tick(state, world, T0)
		Sessions.leave(world, 1, T0 + 5)
		tick(state, world, T0 + 5)
		local s = HabitatPads.get(state, owner.plotIndex, 1) :: Habitats.PadState
		expect(s.id).toBe(BASE)
		expect(s.from).toBe("syrup_pool")
		expect(s.at).toBe(T0 + 5)
	end)
	it("reverts the pad to base when the slime is stolen, and back when it escapes home", function()
		local world = ServerFixtures.world()
		local state = HabitatPads.new()
		local victim = ServerFixtures.join(world, 1, { species("gem", "billy_gum") })
		ServerFixtures.join(world, 2)
		ServerFixtures.unlock(victim)
		tick(state, world, T0)
		expect(padId(state, victim.plotIndex, 1)).toBe("candy_patch")
		expect((Carry.grab(world, 2, "gem", 1, T0 + 10))).toBe(true)
		tick(state, world, T0 + 10)
		expect(padId(state, victim.plotIndex, 1)).toBe(BASE)
		world.carriedBy.gem = nil -- bounced home and landed
		tick(state, world, T0 + 20)
		expect(padId(state, victim.plotIndex, 1)).toBe("candy_patch")
	end)
	it("steal mid-transform ends at base", function()
		local world = ServerFixtures.world()
		local state = HabitatPads.new()
		local victim = ServerFixtures.join(world, 1, { species("gem", "dewdrop_spirit") })
		ServerFixtures.join(world, 2)
		ServerFixtures.unlock(victim)
		tick(state, world, T0)
		local client = run(Habitats.initialWeights(BASE), "crystal_grotto", 0.5) -- half-grown
		expect(client.crystal_grotto).toBeCloseTo(0.5, 1e-6)
		expect((Carry.grab(world, 2, "gem", 1, T0 + 0.5))).toBe(true)
		tick(state, world, T0 + 0.5)
		local s = HabitatPads.get(state, victim.plotIndex, 1) :: Habitats.PadState
		expect(s.id).toBe(BASE)
		expect(s.from).toBe("crystal_grotto")
		client = run(client, s.id, Habitats.TRANSFORM_SECONDS)
		expect(Habitats.isSettled(client, BASE)).toBe(true)
		expect(Habitats.baseVisibility(client)).toBe(1)
	end)
	it("rapid swap ends at the latest habitat", function()
		local world = ServerFixtures.world()
		local state = HabitatPads.new()
		local owner = ServerFixtures.join(world, 1, { species("a", "pudding") })
		tick(state, world, T0)
		local client = Habitats.initialWeights(padId(state, owner.plotIndex, 1) :: string)
		local swaps = { { "b", "sprout" }, { "c", "moo_goo" }, { "d", "blue_ribbon" } }
		local now, last = T0, "a"
		for _, swap in swaps do
			PlayerData.removeSlime(owner.data, last)
			PlayerData.addSlime(owner.data, species(swap[1], swap[2]), 1)
			last = swap[1]
			now += 0.2
			tick(state, world, now)
			client = run(client, padId(state, owner.plotIndex, 1) :: string, 0.2)
		end
		local s = HabitatPads.get(state, owner.plotIndex, 1) :: Habitats.PadState
		expect(s.id).toBe("show_stool")
		expect(s.from).toBe("barn_crate")
		expect(s.at).toBe(now)
		client = run(client, s.id, Habitats.TRANSFORM_SECONDS)
		expect(Habitats.isSettled(client, "show_stool")).toBe(true)
	end)
	it("only reports pads that changed", function()
		local world = ServerFixtures.world()
		local state = HabitatPads.new()
		ServerFixtures.join(world, 1, { species("a", "pudding") })
		expect(#tick(state, world, T0)).toBe(world.plotCount * Config.PADS_MAX)
		expect(#tick(state, world, T0 + 1)).toBe(0)
	end)
end)

describe("Habitats client weights", function()
	it("join in progress shows the final state without animating", function()
		local w = Habitats.initialWeights("hay_nest")
		expect(Habitats.isSettled(w, "hay_nest")).toBe(true)
		expect(Habitats.isSettled(Habitats.initialWeights(BASE), BASE)).toBe(true)
	end)
	it("a transform takes TRANSFORM_SECONDS (about 1 s)", function()
		expect(Habitats.TRANSFORM_SECONDS).toBe(1)
		local w = run({}, "flower_bed", 0.9)
		expect(Habitats.isSettled(w, "flower_bed")).toBe(false)
		w = run(w, "flower_bed", 0.1)
		expect(Habitats.isSettled(w, "flower_bed")).toBe(true)
	end)
end)

describe("Habitats flag off (FEATURES.Habitats = false)", function()
	it("is off by default", function()
		expect(Config.FEATURES.Habitats).toBe(false)
	end)
	it("creates no pad state and leaves the world untouched", function()
		local world = ServerFixtures.world()
		local state = HabitatPads.new()
		local owner = ServerFixtures.join(world, 1, { species("a", "rock_candy") })
		local before = PlayerData.findSlime(owner.data, "a")
		local changes = HabitatPads.step(state, world, T0, false)
		expect(#changes).toBe(0)
		expect(next(state)).toBeNil()
		expect(PlayerData.findSlime(owner.data, "a")).toBe(before)
		expect((before :: any).pad).toBe(1)
		expect(next(world.carriedBy)).toBeNil()
		expect(next(world.escaping)).toBeNil()
	end)
end)
