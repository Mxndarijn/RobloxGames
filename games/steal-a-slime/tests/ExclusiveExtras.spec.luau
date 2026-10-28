--!strict
-- Exclusive Shop extras (contract/exclusive-shop.md §9, §10, §12): carry trails and Bat skins (grant, equip, State,
-- what the player wears) and gifts (aim, grant to the target with their save written first, credits, SendGift).
local Actions = require("../src/server/Actions")
local Config = require("../src/shared/Config")
local PurchaseService = require("../src/server/PurchaseService")
local Purchases = require("../src/server/Purchases")
local ServerFixtures = require("./ServerFixtures")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local T0 = ServerFixtures.T0
local ON = { features = { ExclusiveShop = true } }
local OFF = { features = { ExclusiveShop = false } }

local function ctx(features: { [string]: boolean }, saveUser: ((number, any) -> boolean)?): Actions.Context
	return {
		distanceBetween = function()
			return 2
		end,
		positionOf = function()
			return "pos"
		end,
		features = features,
		saveUser = saveUser,
	}
end

local function call(world: any, userId: number, at: number, c: Actions.Context, action: string, ...: any): any
	return Actions.handle(world, userId, action, table.pack(...), at, c)
end

-- A save that records who was written and answers `ok`.
local function saver(ok: boolean): ({ number }, (number, any) -> boolean)
	local written = {}
	return written, function(userId: number, _data: any): boolean
		table.insert(written, userId)
		return ok
	end
end

describe("carry trails and Bat skins", function()
	it("a Trail_ / BatSkin_ purchase adds it to the owned list once", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		expect(Purchases.grant(world, s, "Trail_rainbow", T0, ON)).toBe(true)
		expect(Purchases.grant(world, s, "Trail_rainbow", T0, ON)).toBe(true)
		expect(Purchases.grant(world, s, "BatSkin_golden", T0, ON)).toBe(true)
		expect(s.data.ownedTrails).toEqual({ "rainbow" })
		expect(s.data.ownedBatSkins).toEqual({ "golden" })
		expect(s.data.trail).toBeNil()
		expect(select(2, Purchases.grant(world, s, "Trail_sparkle", T0, OFF))).toBe("the Exclusive Shop is off")
	end)

	it('EquipTrail / EquipBatSkin wear an owned one, "" takes it off, anything else is refused', function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		s.data.ownedTrails = { "hearts" }
		s.data.ownedBatSkins = { "fish" }
		local c = ctx({ ExclusiveShop = true })
		expect(call(world, 1, T0, c, "EquipTrail", "sparkle").message).toBe("you don't own that trail")
		expect(call(world, 1, T0 + 1, c, "EquipTrail", "hearts").ok).toBe(true)
		expect(s.data.trail).toBe("hearts")
		expect(call(world, 1, T0 + 2, c, "EquipBatSkin", "golden").message).toBe("you don't own that Bat skin")
		expect(call(world, 1, T0 + 3, c, "EquipBatSkin", "fish").ok).toBe(true)
		expect(s.data.batSkin).toBe("fish")
		local trail, skin = Purchases.worn(s, ON)
		expect(trail).toBe("hearts")
		expect(skin).toBe("fish")
		local offTrail, offSkin = Purchases.worn(s, OFF)
		expect(offTrail).toBeNil()
		expect(offSkin).toBeNil()
		expect(call(world, 1, T0 + 4, c, "EquipTrail", "").ok).toBe(true)
		expect(call(world, 1, T0 + 5, c, "EquipBatSkin", "").ok).toBe(true)
		expect(s.data.trail).toBeNil()
		expect(s.data.batSkin).toBeNil()
		expect(call(world, 1, T0 + 6, c, "EquipTrail", "bad id!").message).toBe("bad argument")
		expect(call(world, 1, T0 + 7, c, "EquipTrail", "hearts").ok).toBe(true)
		expect(call(world, 1, T0 + 7.1, c, "EquipTrail", "").message).toBe("too fast")
		local off = ctx({ ExclusiveShop = false })
		expect(call(world, 1, T0 + 9, off, "EquipBatSkin", "fish").message).toBe("the Exclusive Shop is off")
	end)

	it("State.exclusiveShop shows the owned and worn trail and skin and the credits", function()
		local world = ServerFixtures.world()
		local s = ServerFixtures.join(world, 1)
		s.data.ownedTrails = { "sparkle", "starfall" }
		s.data.trail = "starfall"
		s.data.ownedBatSkins = { "lollipop" }
		s.data.lockBreakCredits = 2
		s.data.giftCredits = { "Seat_ufo" }
		local view = Purchases.view(s, T0, world)
		expect(view.trails).toEqual({ sparkle = true, starfall = true })
		expect(view.trail).toBe("starfall")
		expect(view.batSkins).toEqual({ lollipop = true })
		expect(view.batSkin).toBeNil()
		expect(view.lockBreak).toBeNil()
		expect(view.lockBreakCredits).toBe(2)
		expect(view.giftCredits).toEqual({ "Seat_ufo" })
		table.insert(view.giftCredits, "x")
		expect(s.data.giftCredits).toEqual({ "Seat_ufo" }) -- a copy, not the saved list
	end)
end)

describe("gifts", function()
	local function setup(): (any, any, any)
		local world = ServerFixtures.world()
		return world, ServerFixtures.join(world, 1), ServerFixtures.join(world, 2)
	end

	it("AimGift refuses yourself, a player not in the server, an owner of it and what is not giftable", function()
		local world, buyer, target = setup()
		target.data.ownedTrails = { "hearts" }
		expect(select(2, Purchases.aimGift(world, buyer, "Seat_ufo", 1, T0))).toBe("you can't gift yourself")
		expect(select(2, Purchases.aimGift(world, buyer, "Seat_ufo", 9, T0))).toBe("that player isn't in this server")
		expect(select(2, Purchases.aimGift(world, buyer, "Trail_hearts", 2, T0))).toBe("they already have it")
		for _, key in { "LockBreak", "ServerLuckPotion", "FinishBrew_1", "StarterBundle", "Gift_Seat_ufo", "nope" } do
			expect(select(2, Purchases.aimGift(world, buyer, key, 2, T0))).toBe("that can't be gifted")
		end
		local c = ctx({ ExclusiveShop = true })
		expect(call(world, 1, T0, c, "AimGift", "Seat_ufo", "2").message).toBe("bad argument")
		expect(call(world, 1, T0 + 1, c, "AimGift", "Seat_ufo", 2).ok).toBe(true)
		expect(buyer.giftAim).toEqual({ item = "Seat_ufo", targetId = 2, at = T0 + 1 })
		local off = ctx({ ExclusiveShop = false })
		expect(call(world, 1, T0 + 5, off, "AimGift", "Seat_ufo", 2).message).toBe("the Exclusive Shop is off")
	end)

	it("gives the item to the aimed player, writes their save first and tells both", function()
		local world, buyer, target = setup()
		local written, save = saver(true)
		assert(Purchases.aimGift(world, buyer, "BatSkin_golden", 2, T0))
		expect(Purchases.grant(world, buyer, "Gift_BatSkin_golden", T0 + 1, { features = ON.features, save = save })).toBe(
			true
		)
		expect(target.data.ownedBatSkins).toEqual({ "golden" })
		expect(buyer.data.ownedBatSkins).toEqual({})
		expect(buyer.data.giftCredits).toEqual({})
		expect(written).toEqual({ 2 })
		expect(ServerFixtures.notifications(world, 2)).toEqual({ "P1 gave you the Golden Bat!" })
		expect(table.find(ServerFixtures.notifications(world, 1), "You gave P2 the Golden Bat!") ~= nil).toBe(true)
		expect(buyer.giftAim).toBeNil()
	end)

	it("a seat gift unlocks the seat for the target", function()
		local world, buyer, target = setup()
		local _, save = saver(true)
		assert(Purchases.aimGift(world, buyer, "Seat_ufo", 2, T0))
		Purchases.grant(world, buyer, "Gift_Seat_ufo", T0 + 1, { features = ON.features, save = save })
		expect(target.data.ownedSeats).toEqual({ "ufo" })
	end)

	it(
		"keeps a gift credit when the target's save fails, the target left, owns it by then, or nobody was aimed",
		function()
			local world, buyer, target = setup()
			local written, failing = saver(false)
			assert(Purchases.aimGift(world, buyer, "Trail_sparkle", 2, T0))
			Purchases.grant(world, buyer, "Gift_Trail_sparkle", T0 + 1, { features = ON.features, save = failing })
			expect(written).toEqual({ 2 })
			expect(target.data.ownedTrails).toEqual({}) -- taken back: the target never has an unsaved gift
			expect(buyer.data.giftCredits).toEqual({ "Trail_sparkle" })
			local _, save = saver(true)
			assert(Purchases.aimGift(world, buyer, "Trail_hearts", 2, T0 + 2))
			target.data.ownedTrails = { "hearts" }
			Purchases.grant(world, buyer, "Gift_Trail_hearts", T0 + 3, { features = ON.features, save = save })
			assert(Purchases.aimGift(world, buyer, "Seat_leaf", 2, T0 + 4))
			world.sessions[2] = nil
			Purchases.grant(world, buyer, "Gift_Seat_leaf", T0 + 5, { features = ON.features, save = save })
			Purchases.grant(world, buyer, "Gift_Seat_ufo", T0 + 6, { features = ON.features, save = save })
			expect(buyer.data.giftCredits).toEqual({ "Trail_sparkle", "Trail_hearts", "Seat_leaf", "Seat_ufo" })
			-- No save given at all: the same.
			world.sessions[2] = target
			assert(Purchases.aimGift(world, buyer, "BatSkin_fish", 2, T0 + 7))
			Purchases.grant(world, buyer, "Gift_BatSkin_fish", T0 + 8, ON)
			expect(target.data.ownedBatSkins).toEqual({})
			expect(buyer.data.giftCredits[5]).toBe("BatSkin_fish")
		end
	)

	it("an aim for another item or an old aim does not take the gift", function()
		local world, buyer, target = setup()
		local _, save = saver(true)
		assert(Purchases.aimGift(world, buyer, "Seat_ufo", 2, T0))
		Purchases.grant(world, buyer, "Gift_Seat_leaf", T0 + 1, { features = ON.features, save = save })
		assert(Purchases.aimGift(world, buyer, "Seat_ufo", 2, T0 + 2))
		local late = T0 + 3 + Config.EXCLUSIVE_SHOP.gift.aimSeconds
		Purchases.grant(world, buyer, "Gift_Seat_ufo", late, { features = ON.features, save = save })
		expect(target.data.ownedSeats).toEqual({})
		expect(buyer.data.giftCredits).toEqual({ "Seat_leaf", "Seat_ufo" })
	end)

	it("is refused, never lost, with the gift credits full", function()
		local world, buyer, _ = setup()
		local full = {}
		for i = 1, Config.EXCLUSIVE_SHOP.gift.creditMax do
			full[i] = "Seat_leaf"
		end
		buyer.data.giftCredits = full
		local ok, reason = Purchases.grant(world, buyer, "Gift_Seat_ufo", T0, ON)
		expect(ok).toBe(false)
		expect(reason).toBe("too many unsent gifts")
		expect(#buyer.data.giftCredits).toBe(Config.EXCLUSIVE_SHOP.gift.creditMax)
	end)

	it("SendGift spends a gift credit once the target's save is written; a failed save keeps it", function()
		local world, buyer, target = setup()
		buyer.data.giftCredits = { "Trail_rainbow", "Seat_ufo" }
		local written, failing = saver(false)
		local bad = call(world, 1, T0, ctx({ ExclusiveShop = true }, failing), "SendGift", "Trail_rainbow", 2)
		expect(bad.message).toBe("the gift couldn't be delivered, try again")
		expect(written).toEqual({ 2 })
		expect(target.data.ownedTrails).toEqual({})
		expect(buyer.data.giftCredits).toEqual({ "Trail_rainbow", "Seat_ufo" })
		local _, save = saver(true)
		local c = ctx({ ExclusiveShop = true }, save)
		expect(call(world, 1, T0 + 1, c, "SendGift", "Trail_rainbow", 2).ok).toBe(true)
		expect(target.data.ownedTrails).toEqual({ "rainbow" })
		expect(buyer.data.giftCredits).toEqual({ "Seat_ufo" })
		expect(call(world, 1, T0 + 2, c, "SendGift", "Trail_rainbow", 2).message).toBe(
			"you have no unsent gift of that"
		)
		expect(call(world, 1, T0 + 3, c, "SendGift", "Seat_ufo", 1).message).toBe("you can't gift yourself")
		local off = ctx({ ExclusiveShop = false }, save)
		expect(call(world, 1, T0 + 4, off, "SendGift", "Seat_ufo", 2).message).toBe("the Exclusive Shop is off")
		expect(buyer.data.giftCredits).toEqual({ "Seat_ufo" })
	end)
end)

describe("PurchaseService gifts", function()
	local function setup(targetSaves: boolean)
		local world = ServerFixtures.world()
		local saves: { number } = {}
		local service = PurchaseService.service({
			world = world,
			backend = {
				ownsPass = function(): boolean
					return false
				end,
				paidRandomRestricted = function(): boolean
					return false
				end,
			},
			save = function(userId: number, _data: any): boolean
				table.insert(saves, userId)
				return userId ~= 2 or targetSaves
			end,
			now = function()
				return T0
			end,
			wait = function() end,
			ctx = ON,
			attempts = 1,
		})
		return world, service, saves
	end

	it("saves the target through the receipt's own save path, then the buyer, before PurchaseGranted", function()
		local world, service, saves = setup(true)
		local buyer = ServerFixtures.join(world, 1)
		local target = ServerFixtures.join(world, 2)
		assert(Purchases.aimGift(world, buyer, "Seat_ufo", 2, T0))
		expect(service.grantProduct(1, "Gift_Seat_ufo", "g1")).toBe("PurchaseGranted")
		expect(saves).toEqual({ 2, 1 })
		expect(target.data.ownedSeats).toEqual({ "ufo" })
		expect(buyer.data.receipts).toEqual({ "g1" })
		expect(service.grantProduct(1, "Gift_Seat_ufo", "g1")).toBe("PurchaseGranted")
		expect(saves).toEqual({ 2, 1 }) -- a repeat receipt gives nothing twice
	end)

	it("a target save that fails leaves the buyer a gift credit and the receipt is still granted", function()
		local world, service, saves = setup(false)
		local buyer = ServerFixtures.join(world, 1)
		local target = ServerFixtures.join(world, 2)
		assert(Purchases.aimGift(world, buyer, "Seat_ufo", 2, T0))
		expect(service.grantProduct(1, "Gift_Seat_ufo", "g2")).toBe("PurchaseGranted")
		expect(saves).toEqual({ 2, 1 })
		expect(target.data.ownedSeats).toEqual({})
		expect(buyer.data.giftCredits).toEqual({ "Seat_ufo" })
	end)
end)
