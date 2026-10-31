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
	it("gives every species in the roster a theme, its rarity frame and its signature prop", function()
		for _, entry in SlimeRoster.ROSTER do
			local id = Habitats.forType(entry.id, nil)
			local look = Habitats.look(id)
			assert(look, `{entry.id}: {id}`)
			expect(look.theme.id).toBe(Habitats.SPECIES_THEME[entry.id])
			expect(look.frame.tier).toBe(entry.tier)
			expect(look.prop).toBe(entry.id)
		end
	end)
	it("names theme, tier and species in the id; the slime's own tier picks the frame", function()
		expect(Habitats.forSlime(species("a", "captain_goo"))).toBe("reef.5.captain_goo")
		expect(Habitats.forSlime(species("b", "blaze"))).toBe("ember.4.blaze")
		expect(Habitats.forType("pengoo", 3)).toBe("ice.3.pengoo")
		expect(Habitats.forType("lunara", nil)).toBe("space.8.lunara")
		expect(Habitats.forType("midas", SlimeRoster.SECRET_TIER)).toBe("vault.7.midas")
	end)
	it("puts fire, ice, sea and ghost slimes in a theme that fits them", function()
		local function theme(speciesId: string): string
			return (Habitats.look(Habitats.forType(speciesId, nil)) :: Habitats.Look).theme.id
		end
		expect(theme("blaze")).toBe("ember")
		expect(theme("frostbite")).toBe("ice")
		expect(theme("chomp")).toBe("reef")
		expect(theme("pengoo")).toBe("ice")
		expect(theme("phoenix")).toBe("ember")
		expect(theme("boo")).toBe("spooky")
	end)
	it("falls back to the tier's theme, without a prop, for slimes without a species", function()
		expect(Habitats.forSlime(Fixtures.slime("m", 2))).toBe("garden.2")
		expect(Habitats.forSlime(Fixtures.slime("m", 6))).toBe("arcane.6")
		for tier = 1, #Config.RARITIES do
			expect(Habitats.forType(nil, tier) ~= BASE).toBe(true)
		end
		expect(Habitats.forType("not_a_type", 0)).toBe(BASE)
	end)
	it("resolves unknown, malformed or missing habitat ids to the base pad", function()
		expect(Habitats.resolve("reef.5.captain_goo")).toBe("reef.5.captain_goo")
		expect(Habitats.resolve("arcane.6")).toBe("arcane.6")
		for _, bad in { "crystal_grotto", "reef", "reef.10", "reef.05", "magma.4", "reef.5.not_a_type", "reef.5.x.y" } do
			expect(Habitats.resolve(bad)).toBe(BASE)
		end
		expect(Habitats.resolve(nil)).toBe(BASE)
		expect(Habitats.resolve(42)).toBe(BASE)
	end)
	it("has no drift: every theme in the tables exists, every frame tier is a rarity", function()
		for speciesId, themeId in Habitats.SPECIES_THEME do
			expect(SlimeRoster.get(speciesId) ~= nil).toBe(true)
			expect(Habitats.theme(themeId) ~= nil).toBe(true)
		end
		for _, themeId in Habitats.TIER_THEME do
			expect(Habitats.theme(themeId) ~= nil).toBe(true)
		end
		expect(#Habitats.FRAMES).toBe(#Config.RARITIES)
		for tier = 1, #Config.RARITIES do
			expect((Habitats.frame(tier) :: Habitats.Frame).tier).toBe(tier)
		end
	end)
	it("lists the layers bed and frame first, prop last; only the top tiers get the glowing lip", function()
		local function kinds(id: string): { string }
			local out = {}
			for _, layer in Habitats.layers(id) do
				table.insert(out, layer.kind)
			end
			return out
		end
		expect(kinds("ember.4.blaze")).toEqual({ "bed", "frame", "theme", "prop" })
		expect(kinds("vault.7.midas")).toEqual({ "bed", "frame", "glow", "theme", "prop" })
		expect(kinds("arcane.6")).toEqual({ "bed", "frame", "theme" })
		expect(kinds(BASE)).toEqual({})
		local glow = Habitats.layers("vault.7.midas")[3]
		expect(glow.shimmer).toBe(true)
		expect(Habitats.layers("space.8.lunara")[3].shimmer).toBe(false)
	end)
	it("gives every theme a bed colour and a real Roblox material for the disc over the goo bed", function()
		local materials = {
			"Sand",
			"SmoothPlastic",
			"Grass",
			"LeafyGrass",
			"Glass",
			"Fabric",
			"Marble",
			"Basalt",
			"Snow",
			"Slate",
			"DiamondPlate",
			"Foil",
		}
		for _, t in Habitats.THEMES do
			expect(#t.bed).toBe(3)
			expect(table.find(materials, t.bedMaterial) ~= nil).toBe(true)
		end
		local bed = Habitats.layers("reef.5.captain_goo")[1]
		expect({ bed.kind, bed.mesh, bed.material }).toEqual({ "bed", "", "Sand" })
	end)
	it("publishes a template name for every layer mesh", function()
		local meshes: { [string]: boolean } = {}
		for _, mesh in Habitats.MESHES do
			meshes[mesh] = true
		end
		for _, entry in SlimeRoster.ROSTER do
			for _, layer in Habitats.layers(Habitats.forType(entry.id, nil)) do
				expect(layer.kind == "bed" or meshes[layer.mesh] == true).toBe(true) -- the bed is a primitive
			end
		end
		expect(#Habitats.MESHES).toBe(1 + #Habitats.FRAMES + #Habitats.THEMES + #SlimeRoster.ROSTER)
	end)
	it("every uploaded layer fits the dish: frame and theme <= 7.9 wide and 0.1-2.8 tall, props small", function()
		for _, mesh in Habitats.MESHES do
			local entry = MeshAssets.get(mesh)
			local size = entry and entry.size
			if size then
				if string.find(mesh, "^habitat_prop_") then
					expect(size[1] <= 1.95 and size[3] <= 1.2 and size[2] <= 1.45).toBe(true)
				else
					expect(size[1] <= 7.9 and size[3] <= 7.9 and size[2] <= 2.8).toBe(true)
				end
			end
		end
	end)
	it("resolves an uploaded mesh to its meshId, native size and drop; none while not uploaded", function()
		expect(Habitats.overlayMesh("habitat_theme_not_uploaded")).toBe(nil)
		local entries = (MeshAssets :: any).get
		local fake = { meshId = "rbxassetid://123", size = { 7.5, 1.2, 7.5 } }
		(MeshAssets :: any).get = function(name: string)
			return if name == "habitat_theme_reef" then fake else entries(name)
		end
		local overlay = Habitats.overlayMesh("habitat_theme_reef", 0.5);
		(MeshAssets :: any).get = entries
		expect(overlay).toEqual({ meshId = "rbxassetid://123", size = fake.size, drop = 0.5, offset = { 0, 0 } })
	end)
end)

describe("HabitatPads (server pad state)", function()
	it("sets the slime's habitat on its pad when placed; empty pads stay base", function()
		local world = ServerFixtures.world()
		local state = HabitatPads.new()
		local owner = ServerFixtures.join(world, 1, { species("s1", "cosmo") })
		tick(state, world, T0)
		expect(padId(state, owner.plotIndex, 1)).toBe("space.6.cosmo")
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
		expect(s.from).toBe("pond.1.bubbles")
		expect(s.at).toBe(T0 + 5)
	end)
	it("keeps the habitat while the slime is carried off: only the slime leaves", function()
		local world = ServerFixtures.world()
		local state = HabitatPads.new()
		local victim = ServerFixtures.join(world, 1, { species("gem", "blaze") })
		ServerFixtures.join(world, 2)
		ServerFixtures.unlock(victim)
		tick(state, world, T0)
		expect(padId(state, victim.plotIndex, 1)).toBe("ember.4.blaze")
		expect((Carry.grab(world, 2, "gem", 1, T0 + 10))).toBe(true)
		expect(tick(state, world, T0 + 10)).toEqual({})
		expect(padId(state, victim.plotIndex, 1)).toBe("ember.4.blaze")
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
		expect(padId(state, victim.plotIndex, 1)).toBe("ember.4.blaze")
		local landed = T0 + 2 + World.ESCAPE_BOUNCE_SECONDS
		StealService.step(world, landed)
		expect(world.escaping.gem).toBeNil()
		tick(state, world, landed)
		local s = HabitatPads.get(state, victim.plotIndex, 1) :: Habitats.PadState
		expect({ s.id, s.from, s.at }).toEqual({ "ember.4.blaze", BASE, T0 })
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
		expect(s.id).toBe("ember.4.blaze")
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
		expect({ old.id, old.from, old.at }).toEqual({ BASE, "pond.1.bubbles", T0 + 1 })
		expect({ new.id, new.from, new.at }).toEqual({ "pond.1.bubbles", BASE, T0 + 1 })
	end)
	it("reverts the pad to base when the slime is sold", function()
		local world = ServerFixtures.world()
		local state = HabitatPads.new()
		local owner = ServerFixtures.join(world, 1, { species("a", "cosmo"), species("b", "bubbles") })
		tick(state, world, T0)
		expect(padId(state, owner.plotIndex, 1)).toBe("space.6.cosmo")
		local res = Actions.handle(world, 1, "Sell", { "a" }, T0 + 3, ctx)
		expect(res.ok).toBe(true)
		expect(PlayerData.findSlime(owner.data, "a")).toBeNil()
		tick(state, world, T0 + 3)
		local s = HabitatPads.get(state, owner.plotIndex, 1) :: Habitats.PadState
		expect({ s.id, s.from, s.at }).toEqual({ BASE, "space.6.cosmo", T0 + 3 })
		expect(padId(state, owner.plotIndex, 2)).toBe("pond.1.bubbles") -- the other pad is untouched
	end)
	it("a steal completed mid-transform ends at base", function()
		local world = ServerFixtures.world()
		local state = HabitatPads.new()
		local victim = ServerFixtures.join(world, 1, { species("gem", "cosmo") })
		ServerFixtures.join(world, 2)
		ServerFixtures.unlock(victim)
		tick(state, world, T0)
		local client = run(Habitats.initialWeights(BASE), "space.6.cosmo", 0.5) -- half-grown
		expect(client["space.6.cosmo"]).toBeCloseTo(0.5, 1e-6)
		expect((Carry.grab(world, 2, "gem", 1, T0 + 0.5))).toBe(true)
		expect((Carry.deposit(world, 2))).toBe(true)
		tick(state, world, T0 + 0.5)
		local s = HabitatPads.get(state, victim.plotIndex, 1) :: Habitats.PadState
		expect(s.id).toBe(BASE)
		expect(s.from).toBe("space.6.cosmo")
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
		expect(s.id).toBe("royal.5.king")
		expect(s.from).toBe("barnyard.3.whiskers")
		expect(s.at).toBe(now)
		client = run(client, s.id, Habitats.TRANSFORM_SECONDS)
		expect(Habitats.isSettled(client, "royal.5.king")).toBe(true)
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
		local w = Habitats.initialWeights("barnyard.1.moo")
		expect(Habitats.isSettled(w, "barnyard.1.moo")).toBe(true)
		expect(Habitats.isSettled(Habitats.initialWeights(BASE), BASE)).toBe(true)
	end)
	it("a transform takes TRANSFORM_SECONDS (about 1 s)", function()
		expect(Habitats.TRANSFORM_SECONDS).toBe(1)
		local w = run({}, "garden.2.bumble", 0.9)
		expect(Habitats.isSettled(w, "garden.2.bumble")).toBe(false)
		w = run(w, "garden.2.bumble", 0.1)
		expect(Habitats.isSettled(w, "garden.2.bumble")).toBe(true)
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
