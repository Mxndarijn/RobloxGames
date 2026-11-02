--!strict
-- Pet species (contract/pet-species.md): the slime on the follow pet's cloud, picked from the SlimeDex. Only a found
-- species with its own kit mesh; "" / nil = Auto (favourite, else best slime). The Request, save field, State and
-- the Player attribute the client reads.
local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local Constants = require("../src/shared/Constants")
local KitRequest = require("../src/shared/KitRequest")
local PetSpecies = require("../src/shared/PetSpecies")
local PlayerData = require("../src/shared/PlayerData")
local Remotes = require("../src/shared/Remotes")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local SlimeRoster = require("../src/shared/SlimeRoster")
local Snapshot = require("../src/server/Snapshot")
local SpeciesDex = require("../src/shared/SpeciesDex")
local TestRunner = require("./TestRunner")
local Validate = require("../src/shared/Validate")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

-- Two Dex species with a kit of their own, and one without (if the roster has one).
local withKit: { string } = {}
local noKit: string? = nil
for _, entry in SpeciesDex.ENTRIES do
	if KitRequest.kitOf(entry.id) then
		table.insert(withKit, entry.id)
	elseif noKit == nil then
		noKit = entry.id
	end
end
local A, B = withKit[1], withKit[2]
assert(A and B, "two Dex species with a kit")

local function found(...: string): PlayerData.Data
	local data = PlayerData.new()
	for _, id in { ... } do
		data.found[id] = true
	end
	return data
end

local ctx: Actions.Context = {
	distanceBetween = function()
		return 2
	end,
	positionOf = function()
		return nil
	end,
}

local function request(world: any, userId: number, id: any)
	world.sessions[userId].limiter = {}
	return Actions.handle(world, userId, "SetPetSpecies", { id }, T0 + 100, ctx)
end

describe("pet species: rule", function()
	it("allows a found species with a kit, and nothing else", function()
		local data = found(A)
		expect(PetSpecies.allowed(data, A)).toBe(true)
		local ok, reason = PetSpecies.allowed(data, B)
		expect(ok).toBe(false)
		expect(reason).toBe("slime not found yet")
		for _, bad in { "bogus", "", 7, true, string.rep("a", 40) } do
			local okBad, why = PetSpecies.allowed(data, bad)
			expect(okBad).toBe(false)
			expect(why).toBe("unknown slime")
		end
		if noKit then
			data.found[noKit] = true
			expect((PetSpecies.allowed(data, noKit))).toBe(false)
		end
	end)
	it("allows a found bonus entry with a kit", function()
		for _, entry in SpeciesDex.BONUS do
			if KitRequest.kitOf(entry.id) and SlimeRoster.get(entry.id) then
				expect(PetSpecies.allowed(found(entry.id), entry.id)).toBe(true)
				return
			end
		end
	end)
	it("set picks a species, and nil or empty goes back to Auto", function()
		local data = found(A, B)
		expect(PetSpecies.current(data)).toBe(nil)
		expect(PetSpecies.set(data, A)).toBe(true)
		expect(PetSpecies.current(data)).toBe(A)
		expect(PetSpecies.set(data, "")).toBe(true)
		expect(data.petSpecies).toBe(nil)
		expect(PetSpecies.set(data, B)).toBe(true)
		expect(PetSpecies.set(data, nil)).toBe(true)
		expect(PetSpecies.current(data)).toBe(nil)
	end)
	it("set refuses a species not found yet and keeps the old pick", function()
		local data = found(A)
		PetSpecies.set(data, A)
		local ok, reason = PetSpecies.set(data, B)
		expect(ok).toBe(false)
		expect(reason).toBe("slime not found yet")
		expect(PetSpecies.current(data)).toBe(A)
	end)
	it("clean drops a pick that is not allowed", function()
		local data = found(A)
		data.petSpecies = B
		PetSpecies.clean(data)
		expect(data.petSpecies).toBe(nil)
		data.petSpecies = A
		PetSpecies.clean(data)
		expect(data.petSpecies).toBe(A)
	end)
end)

describe("pet species: Request, State and attribute", function()
	it("is a rate-limited Request action that takes an id or empty", function()
		expect(Remotes.ACTIONS.SetPetSpecies.args[1]).toBe("cosmetic")
		expect(Validate.ACTIONS.SetPetSpecies).toBe(0.5)
	end)
	it("the Request picks a found species, refuses others, and goes back to Auto", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, {}, 0)
		session.data.found[A] = true
		local res = request(world, 1, B)
		expect(res.ok).toBe(false)
		expect(res.message).toBe("slime not found yet")
		expect(request(world, 1, "bogus").ok).toBe(false)
		expect(request(world, 1, 12).ok).toBe(false)
		res = request(world, 1, A)
		expect(res.ok).toBe(true)
		expect(session.data.petSpecies).toBe(A)
		expect(Snapshot.build(world, session, T0).petSpecies).toBe(A)
		res = request(world, 1, "")
		expect(res.ok).toBe(true)
		expect(Snapshot.build(world, session, T0).petSpecies).toBe(nil)
	end)
	it("names the Player attribute the client reads", function()
		expect(Constants.PET_SPECIES_ATTRIBUTE).toBe("PetSpecies")
	end)
end)

describe("pet species: save", function()
	it("round-trips a pick without a version bump", function()
		local data = found(A)
		data.petSpecies = A
		local out = SaveData.serialize(data, T0)
		expect(out.petSpecies).toBe(A)
		expect(out.version).toBe(Config.SAVE_VERSION)
		expect(SaveData.deserialize(out).petSpecies).toBe(A)
	end)
	it("saves Auto as nothing and loads old saves as Auto", function()
		local out = SaveData.serialize(PlayerData.new(), T0)
		expect(out.petSpecies).toBe(nil)
		expect(SaveData.deserialize(out).petSpecies).toBe(nil)
		expect(SaveData.deserialize({ Cash = 5, Rebirths = 0, Slimes = {} }).petSpecies).toBe(nil)
		expect(SaveData.deserialize(nil).petSpecies).toBe(nil)
	end)
	it("loads an unknown, junk or not-found pick as Auto", function()
		local stored = SaveData.serialize(found(A), T0)
		for _, bad in { B, "bogus", 7, true, "", {} } do
			stored.petSpecies = bad
			expect(SaveData.deserialize(stored).petSpecies).toBe(nil)
		end
		stored.petSpecies = A
		expect(SaveData.deserialize(stored).petSpecies).toBe(A)
	end)
end)
