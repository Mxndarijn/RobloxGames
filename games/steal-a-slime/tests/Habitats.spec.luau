--!strict
local Actions = require("../src/server/Actions")
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
local StealService = require("../src/server/StealService")
local TestRunner = require("./TestRunner")
local World = require("../src/server/World")

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

local ctx: Actions.Context = {
	distanceBetween = function()
		return 2
	end,
	positionOf = function()
		return "pos"
	end,
}

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
	it("resolves unknown or missing habitat ids to the base pad", function()
		expect(Habitats.resolve("crystal_grotto")).toBe("crystal_grotto")
		expect(Habitats.resolve("not_a_habitat")).toBe(BASE)
		expect(Habitats.resolve(nil)).toBe(BASE)
		expect(Habitats.resolve(42)).toBe(BASE)
	end)
	it("maps every TYPE and FAMILY entry to a known habitat (no drift)", function()
		for _, id in Habitats.TYPE do
			expect(Habitats.get(id) ~= nil).toBe(true)
		end
		for _, id in Habitats.FAMILY do
			expect(Habitats.get(id) ~= nil).toBe(true)
		end
	end)
	it("prefers a per-type habitat over the family", function()
		expect(Habitats.forSlime(species("a", "octo"))).toBe("syrup_pool")
		expect(Habitats.forSlime(species("c", "moo"))).toBe("rodeo_barrel")
		expect(Habitats.forSlime(species("b", "king"))).toBe("show_stool")
	end)
	it("gives every habitat but base its own overlay mesh", function()
		for _, habitat in Habitats.LIST do
			if habitat.id == BASE then
				expect(habitat.overlay).toBe(nil)
			else
				expect(habitat.overlay).toBe(`habitat_{habitat.id}_overlay`)
				expect(MeshAssets.get(habitat.overlay :: string) ~= nil).toBe(true)
			end
		end
	end)
	it("maps every roster type and tier family to a habitat with an uploaded overlay", function()
		for _, entry in SlimeRoster.ROSTER do
			expect(Habitats.overlayMesh(Habitats.forType(entry.id, nil)) ~= nil).toBe(true)
		end
		for _, id in Habitats.FAMILY do
			expect(Habitats.overlayMesh(id) ~= nil).toBe(true)
		end
	end)
	it("every overlay fits the crate deck round the slime: <= 7.9 wide, 0.5-2.8 tall above the deck", function()
		for _, habitat in Habitats.LIST do
			if habitat.overlay then
				local size = (MeshAssets.get(habitat.overlay) :: MeshAssets.Entry).size :: { number }
				expect(size[1] <= 7.9 and size[3] <= 7.9).toBe(true)
				expect(habitat.drop >= 0 and habitat.drop < size[2]).toBe(true)
				local above = size[2] - habitat.drop
				expect(above >= 0.5 and above <= 2.8).toBe(true)
			end
		end
	end)
	it("draws the placeholder for an overlay with no uploaded meshId", function()
		local entry = MeshAssets.get("habitat_candy_patch_overlay") :: MeshAssets.Entry
		local saved = entry.meshId
		entry.meshId = nil
		expect(Habitats.overlayMesh("candy_patch")).toBe(nil)
		entry.meshId = saved
	end)
	it("resolves an overlay to its MeshAssets meshId, native size and drop", function()
		local entry = MeshAssets.get("habitat_crystal_grotto_overlay") :: MeshAssets.Entry
		local saved = entry.meshId
		entry.meshId = "rbxassetid://123"
		local overlay = Habitats.overlayMesh("crystal_grotto")
		entry.meshId = saved
		expect(overlay).toEqual({ meshId = "rbxassetid://123", size = entry.size, drop = 0 })
	end)
	it("never gives base or unknown ids an overlay mesh", function()
		expect(Habitats.overlayMesh(BASE)).toBe(nil)
		expect(Habitats.overlayMesh("not_a_habitat")).toBe(nil)
	end)
end)

describe("HabitatPads (server pad state)", function()
	it("sets the slime's habitat on its pad when placed; empty pads stay base", function()
		local world = ServerFixtures.world()
		local state = HabitatPads.new()
		local owner = ServerFixtures.join(world, 1, { species("s1", "cosmo") })
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
		local owner = ServerFixtures.join(world, 1, { species("s1", "bubbles") })
		tick(state, world, T0)
		Sessions.leave(world, 1, T0 + 5)
		tick(state, world, T0 + 5)
		local s = HabitatPads.get(state, owner.plotIndex, 1) :: Habitats.PadState
		expect(s.id).toBe(BASE)
		expect(s.from).toBe("syrup_pool")
		expect(s.at).toBe(T0 + 5)
	end)
	it("keeps the habitat while the slime is carried off: only the slime leaves", function()
		local world = ServerFixtures.world()
		local state = HabitatPads.new()
		local victim = ServerFixtures.join(world, 1, { species("gem", "blaze") })
		ServerFixtures.join(world, 2)
		ServerFixtures.unlock(victim)
		tick(state, world, T0)
		expect(padId(state, victim.plotIndex, 1)).toBe("candy_patch")
		expect((Carry.grab(world, 2, "gem", 1, T0 + 10))).toBe(true)
		expect(tick(state, world, T0 + 10)).toEqual({})
		expect(padId(state, victim.plotIndex, 1)).toBe("candy_patch")
	end)
	it("keeps the habitat while a stolen slime bounces home", function()
		local world = ServerFixtures.world()
		local state = HabitatPads.new()
		local victim = ServerFixtures.join(world, 1, { species("gem", "blaze") })
		local thief = ServerFixtures.join(world, 2)
		ServerFixtures.unlock(victim)
		tick(state, world, T0)
		expect((Carry.grab(world, 2, "gem", 1, T0 + 1))).toBe(true)
		tick(state, world, T0 + 1)
		expect(StealService.escape(world, thief, T0 + 2, "slap")).toBe("gem")
		expect(world.escaping.gem ~= nil).toBe(true)
		tick(state, world, T0 + 2)
		expect(padId(state, victim.plotIndex, 1)).toBe("candy_patch")
		local landed = T0 + 2 + World.ESCAPE_BOUNCE_SECONDS
		StealService.step(world, landed)
		expect(world.escaping.gem).toBeNil()
		tick(state, world, landed)
		local s = HabitatPads.get(state, victim.plotIndex, 1) :: Habitats.PadState
		expect({ s.id, s.from, s.at }).toEqual({ "candy_patch", BASE, T0 })
	end)
	it("moves with a stolen slime to the thief's pad; the victim's pad reverts", function()
		local world = ServerFixtures.world()
		local state = HabitatPads.new()
		local victim = ServerFixtures.join(world, 1, { species("gem", "blaze") })
		local thief = ServerFixtures.join(world, 2)
		ServerFixtures.unlock(victim)
		tick(state, world, T0)
		expect((Carry.grab(world, 2, "gem", 1, T0 + 1))).toBe(true)
		expect((Carry.deposit(world, 2))).toBe(true)
		tick(state, world, T0 + 2)
		local moved = PlayerData.findSlime(thief.data, "gem")
		assert(moved and moved.pad, "deposited on a pad")
		expect(padId(state, victim.plotIndex, 1)).toBe(BASE)
		local s = HabitatPads.get(state, thief.plotIndex, moved.pad) :: Habitats.PadState
		expect(s.id).toBe("candy_patch")
		expect(s.from).toBe(BASE)
		expect(s.at).toBe(T0 + 2)
	end)
	it("moves between pads of the same plot: old pad reverts, new pad updates", function()
		local world = ServerFixtures.world()
		local state = HabitatPads.new()
		local owner = ServerFixtures.join(world, 1, { species("a", "bubbles") })
		tick(state, world, T0)
		local slime = PlayerData.findSlime(owner.data, "a")
		assert(slime, "slime")
		expect(slime.pad).toBe(1)
		slime.pad = 3 -- rebirth / re-seat moves a slime's pad index
		tick(state, world, T0 + 1)
		local old = HabitatPads.get(state, owner.plotIndex, 1) :: Habitats.PadState
		local new = HabitatPads.get(state, owner.plotIndex, 3) :: Habitats.PadState
		expect({ old.id, old.from, old.at }).toEqual({ BASE, "syrup_pool", T0 + 1 })
		expect({ new.id, new.from, new.at }).toEqual({ "syrup_pool", BASE, T0 + 1 })
	end)
	it("reverts the pad to base when the slime is sold", function()
		local world = ServerFixtures.world()
		local state = HabitatPads.new()
		local owner = ServerFixtures.join(world, 1, { species("a", "cosmo"), species("b", "bubbles") })
		tick(state, world, T0)
		expect(padId(state, owner.plotIndex, 1)).toBe("crystal_grotto")
		local res = Actions.handle(world, 1, "Sell", { "a" }, T0 + 3, ctx)
		expect(res.ok).toBe(true)
		expect(PlayerData.findSlime(owner.data, "a")).toBeNil()
		tick(state, world, T0 + 3)
		local s = HabitatPads.get(state, owner.plotIndex, 1) :: Habitats.PadState
		expect({ s.id, s.from, s.at }).toEqual({ BASE, "crystal_grotto", T0 + 3 })
		expect(padId(state, owner.plotIndex, 2)).toBe("syrup_pool") -- the other pad is untouched
	end)
	it("a steal completed mid-transform ends at base", function()
		local world = ServerFixtures.world()
		local state = HabitatPads.new()
		local victim = ServerFixtures.join(world, 1, { species("gem", "cosmo") })
		ServerFixtures.join(world, 2)
		ServerFixtures.unlock(victim)
		tick(state, world, T0)
		local client = run(Habitats.initialWeights(BASE), "crystal_grotto", 0.5) -- half-grown
		expect(client.crystal_grotto).toBeCloseTo(0.5, 1e-6)
		expect((Carry.grab(world, 2, "gem", 1, T0 + 0.5))).toBe(true)
		expect((Carry.deposit(world, 2))).toBe(true)
		tick(state, world, T0 + 0.5)
		local s = HabitatPads.get(state, victim.plotIndex, 1) :: Habitats.PadState
		expect(s.id).toBe(BASE)
		expect(s.from).toBe("crystal_grotto")
		client = run(client, s.id, Habitats.TRANSFORM_SECONDS)
		expect(Habitats.isSettled(client, BASE)).toBe(true)
		expect(client).toEqual({})
	end)
	it("rapid swap ends at the latest habitat", function()
		local world = ServerFixtures.world()
		local state = HabitatPads.new()
		local owner = ServerFixtures.join(world, 1, { species("a", "bubbles") })
		tick(state, world, T0)
		local client = Habitats.initialWeights(padId(state, owner.plotIndex, 1) :: string)
		local swaps = { { "b", "bumble" }, { "c", "whiskers" }, { "d", "king" } }
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
		ServerFixtures.join(world, 1, { species("a", "bubbles") })
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

describe("Habitats flag off (step called with the flag false)", function()
	it("creates no pad state and leaves the world untouched", function()
		local world = ServerFixtures.world()
		local state = HabitatPads.new()
		local owner = ServerFixtures.join(world, 1, { species("a", "cosmo") })
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
