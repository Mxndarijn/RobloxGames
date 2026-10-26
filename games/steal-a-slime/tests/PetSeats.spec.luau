--!strict
-- Pet seats (contract/pet-seats.md): what the follow pet rides on. Three seats every player can earn (the default
-- cloud, Jelly at 200 merges, Rainbow Cloud at 80 % of the SlimeDex), the rest Exclusive; the equip Request, the
-- save field, State and the Player attribute the client reads.
local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local Constants = require("../src/shared/Constants")
local MeshAssets = require("../src/shared/MeshAssets")
local PetSeats = require("../src/shared/PetSeats")
local PlayerData = require("../src/shared/PlayerData")
local Remotes = require("../src/shared/Remotes")
local SaveData = require("../src/shared/SaveData")
local ServerFixtures = require("./ServerFixtures")
local Snapshot = require("../src/server/Snapshot")
local SpeciesDex = require("../src/shared/SpeciesDex")
local TestRunner = require("./TestRunner")
local Validate = require("../src/shared/Validate")
local fs = require("@lune/fs")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0

local function seat(id: string): Config.PetSeat
	return PetSeats.get(id) :: Config.PetSeat
end

-- A profile with `merges` slimes merged and the first `found` SlimeDex entries found.
local function profile(merges: number?, found: number?): PlayerData.Data
	local data = PlayerData.new()
	data.stats.merges = merges or 0
	for i, entry in SpeciesDex.ENTRIES do
		if i <= (found or 0) then
			data.found[entry.id] = true
		end
	end
	return data
end

local DEX_80 = math.ceil(SpeciesDex.TOTAL * 0.8)

local ctx: Actions.Context = {
	distanceBetween = function()
		return 2
	end,
	positionOf = function()
		return nil
	end,
}

local function equip(world: any, userId: number, id: any)
	world.sessions[userId].limiter = {}
	return Actions.handle(world, userId, "EquipPetSeat", { id }, T0 + 100, ctx)
end

describe("pet seats: config", function()
	it("lists the default cloud first, then Jelly and Rainbow Cloud, then 16 Exclusives", function()
		expect(Config.PET_SEAT_DEFAULT).toBe("cloud")
		expect(Config.PET_SEATS[1].id).toBe("cloud")
		expect(Config.PET_SEATS[1].mesh).toBe("pet_cloud")
		expect(Config.PET_SEATS[2].id).toBe("jelly")
		expect(Config.PET_SEATS[3].id).toBe("rainbow_cloud")
		expect(#Config.PET_SEATS).toBe(19)
		local kinds: { [string]: number } = {}
		for _, s in Config.PET_SEATS do
			kinds[s.unlock.kind] = (kinds[s.unlock.kind] or 0) + 1
		end
		expect(kinds.free).toBe(1)
		expect(kinds.merges).toBe(1)
		expect(kinds.dex).toBe(1)
		expect(kinds.exclusive).toBe(16)
	end)
	it("unlocks Jelly at 200 merges and Rainbow Cloud at 80 % of the SlimeDex", function()
		expect(seat("jelly").unlock.kind).toBe("merges")
		expect(seat("jelly").unlock.count).toBe(200)
		expect(seat("rainbow_cloud").unlock.kind).toBe("dex")
		expect(seat("rainbow_cloud").unlock.percent).toBe(80)
	end)
	it("has unique ids, a modelled mesh each, and a seat inside the mesh", function()
		local ids = {}
		for _, s in Config.PET_SEATS do
			expect(ids[s.id]).toBeNil()
			ids[s.id] = true
			expect(fs.isFile(`../../shared/modeling-kit/models/{s.mesh}.py`)).toBe(true)
			expect(s.seat > 0 and s.seat <= 2.5).toBe(true)
		end
	end)
	it("the default cloud's mesh is uploaded, so every pet has a seat", function()
		expect(MeshAssets.meshId(seat("cloud").mesh) ~= nil).toBe(true)
	end)
end)

describe("pet seats: unlocks", function()
	it("the default cloud is always unlocked; an Exclusive never is, whatever the profile", function()
		local rich = profile(10000, SpeciesDex.TOTAL)
		expect(PetSeats.unlocked(PlayerData.new(), seat("cloud"))).toBe(true)
		expect(PetSeats.unlocked(rich, seat("storm_cloud"))).toBe(false)
		expect(PetSeats.unlocked(rich, seat("hoverboard"))).toBe(false)
	end)
	it("Jelly: 199 merges is locked, 200 is unlocked", function()
		expect(PetSeats.unlocked(profile(199), seat("jelly"))).toBe(false)
		expect(PetSeats.unlocked(profile(200), seat("jelly"))).toBe(true)
	end)
	it("Rainbow Cloud: one species short of 80 % is locked, exactly 80 % is unlocked", function()
		expect(PetSeats.unlocked(profile(0, DEX_80 - 1), seat("rainbow_cloud"))).toBe(false)
		expect(PetSeats.unlocked(profile(0, DEX_80), seat("rainbow_cloud"))).toBe(true)
	end)
	it("event Secrets and unknown ids don't count toward the SlimeDex percent", function()
		local data = profile(0, DEX_80 - 1)
		data.found.glitch = true
		data.found.nope = true
		expect(PetSeats.unlocked(data, seat("rainbow_cloud"))).toBe(false)
	end)
	it("view() reports progress per seat in Config order", function()
		local view = PetSeats.view(profile(136, 26))
		expect(#view).toBe(#Config.PET_SEATS)
		expect(view[1].id).toBe("cloud")
		expect(view[1].equipped and view[1].unlocked).toBe(true)
		expect(view[2].kind).toBe("merges")
		expect(view[2].have).toBe(136)
		expect(view[2].need).toBe(200)
		expect(view[2].unlocked).toBe(false)
		expect(view[3].kind).toBe("dex")
		expect(view[3].have).toBe(math.floor(26 * 100 / SpeciesDex.TOTAL))
		expect(view[3].need).toBe(80)
		expect(view[4].kind).toBe("exclusive")
		expect(view[4].need).toBe(0)
	end)
end)

describe("pet seats: equip", function()
	it("PetSeats.equip refuses unknown and locked seats and leaves the profile alone", function()
		local data = profile(10)
		local ok, why = PetSeats.equip(data, "nope")
		expect(ok).toBe(false)
		expect(why).toBe("unknown pet seat")
		ok, why = PetSeats.equip(data, "jelly")
		expect(ok).toBe(false)
		expect(why).toBe("pet seat is locked")
		expect(PetSeats.equip(data, "ufo")).toBe(false)
		expect(data.petSeat).toBe("cloud")
		expect(PetSeats.equip(data, 42 :: any)).toBe(false)
	end)
	it("equips an unlocked seat, and the default cloud always", function()
		local data = profile(200)
		expect(PetSeats.equip(data, "jelly")).toBe(true)
		expect(PetSeats.current(data)).toBe("jelly")
		expect(PetSeats.equip(data, "cloud")).toBe(true)
		expect(data.petSeat).toBe("cloud")
	end)
	it("current() never shows a seat the profile has not unlocked", function()
		local data = PlayerData.new()
		data.petSeat = "jelly"
		expect(PetSeats.current(data)).toBe("cloud")
		data.petSeat = "storm_cloud"
		expect(PetSeats.current(data)).toBe("cloud")
		data.petSeat = "bogus"
		expect(PetSeats.current(data)).toBe("cloud")
	end)
	it("is a rate-limited Request action", function()
		expect(Remotes.ACTIONS.EquipPetSeat.args[1]).toBe("string")
		expect(Validate.ACTIONS.EquipPetSeat ~= nil).toBe(true)
	end)
	it("the Request refuses a locked seat, and equips it once unlocked", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, {}, 0)
		local res = equip(world, 1, "jelly")
		expect(res.ok).toBe(false)
		expect(res.message).toBe("pet seat is locked")
		session.data.stats.merges = 200
		res = equip(world, 1, "jelly")
		expect(res.ok).toBe(true)
		expect(session.data.petSeat).toBe("jelly")
		expect(Snapshot.build(world, session, T0).petSeat).toBe("jelly")
	end)
	it("the Request refuses an Exclusive and rejects bad arguments", function()
		local world = ServerFixtures.world()
		ServerFixtures.join(world, 1, {}, 0)
		expect(equip(world, 1, "storm_cloud").message).toBe("pet seat is locked")
		expect(equip(world, 1, nil).ok).toBe(false)
		expect(equip(world, 1, 12).ok).toBe(false)
		expect(equip(world, 1, "bogus").message).toBe("unknown pet seat")
	end)
end)

describe("pet seats: State and attribute", function()
	it("State carries the seat and every seat's progress", function()
		local world = ServerFixtures.world()
		local session = ServerFixtures.join(world, 1, {}, 0)
		local state = Snapshot.build(world, session, T0)
		expect(state.petSeat).toBe("cloud")
		expect(#state.petSeats).toBe(#Config.PET_SEATS)
		expect(state.petSeats[1].equipped).toBe(true)
	end)
	it("names the Player attribute the client reads", function()
		expect(Constants.PET_SEAT_ATTRIBUTE).toBe("PetSeat")
	end)
end)

describe("pet seats: save", function()
	it("round-trips an unlocked seat without a version bump", function()
		local data = profile(200)
		data.petSeat = "jelly"
		local out = SaveData.serialize(data, T0)
		expect(out.petSeat).toBe("jelly")
		expect(out.version).toBe(Config.SAVE_VERSION)
		expect(SaveData.deserialize(out).petSeat).toBe("jelly")
	end)
	it("keeps Rainbow Cloud when the SlimeDex reaches 80 % through a won boss", function()
		local data = profile(0, DEX_80 - 1)
		local boss: string? = nil
		for _, entry in SpeciesDex.ENTRIES do
			if entry.kind == "boss" and not data.found[entry.id] then
				boss = entry.id
			end
		end
		assert(boss, "a boss species outside the first entries")
		data.boss.wins[boss] = 1
		local out = SaveData.serialize(data, T0)
		out.petSeat = "rainbow_cloud"
		expect(SaveData.deserialize(out).petSeat).toBe("rainbow_cloud")
	end)
	it("loads saves from before pet seats, and unknown, junk or locked seats, as the default cloud", function()
		expect(SaveData.deserialize({ Cash = 5, Rebirths = 0, Slimes = {} }).petSeat).toBe("cloud")
		expect(SaveData.deserialize(nil).petSeat).toBe("cloud")
		local stored = SaveData.serialize(PlayerData.new(), T0)
		for _, bad in { "jelly", "storm_cloud", "bogus", 7, true, "", {} } do
			stored.petSeat = bad
			expect(SaveData.deserialize(stored).petSeat).toBe("cloud")
		end
	end)
end)
