--!strict
-- The server side of the claw show (server/ClawShowService, contract/exclusive-shop.md §7.2): which purchases play a
-- show, what the claw takes and what the banner says, and that a show goes to every client with a queued start.
local ClawShow = require("../src/visuals/shared/ClawShow")
local ClawShowService = require("../src/server/ClawShowService")
local Config = require("../src/shared/Config")
local Purchases = require("../src/server/Purchases")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local SHOP = Config.EXCLUSIVE_SHOP
local FEATURED = { "ufo", "sunset_cloud", "magic_carpet", "leaf" }

-- The first product key whose grant is of `kind` (and passes `pick`).
local function keyOf(kind: string, pick: ((grant: any) -> boolean)?): string
	local keys = {}
	for key, def in SHOP.products do
		if def.grant.kind == kind and (pick == nil or pick(def.grant)) then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	assert(keys[1], `no product of kind {kind}`)
	return keys[1]
end

describe("plan", function()
	it("takes a bought seat on show from its pedestal and names it", function()
		local key = keyOf("seat", function(g)
			return g.seat == "sunset_cloud"
		end)
		local plan = ClawShowService.plan(key, false, FEATURED) :: any
		expect(plan.display).toBe(2)
		expect(plan.label).toBe(Purchases.itemName(key))
		expect(plan.gift).toBeNil()
	end)
	it("takes a capsule for a seat that is not on show (the 4th featured one too)", function()
		local key = keyOf("seat", function(g)
			return g.seat == "leaf"
		end)
		local plan = ClawShowService.plan(key, false, FEATURED) :: any
		expect(plan.display).toBe(ClawShow.CAPSULE)
		expect(plan.label).toBe(Purchases.itemName(key))
	end)
	it("plays a gift as the item, marked as a gift", function()
		local seatKey = keyOf("seat", function(g)
			return g.seat == "ufo"
		end)
		local giftKey = "Gift_" .. seatKey
		if SHOP.products[giftKey] then
			local plan = ClawShowService.plan(giftKey, false, FEATURED) :: any
			expect(plan.display).toBe(1)
			expect(plan.gift).toBe(true)
			expect(plan.label).toBe(Purchases.itemName(seatKey))
		end
	end)
	it("plays every Game Pass with a capsule and no label", function()
		for key in SHOP.passes do
			local plan = ClawShowService.plan(key, true, FEATURED) :: any
			expect(plan.display).toBe(ClawShow.CAPSULE)
			expect(plan.label).toBeNil()
		end
		expect(ClawShowService.plan("NoSuchPass", true, FEATURED)).toBeNil()
	end)
	it("plays no show for time skips and quick-buys", function()
		for _, kind in { "finishBrew", "hatchNow", "doubleOffline" } do
			expect(ClawShowService.plan(keyOf(kind), false, FEATURED)).toBeNil()
		end
		expect(ClawShowService.plan("NoSuchProduct", false, FEATURED)).toBeNil()
	end)
	it("names cosmetics, and only gives the generic prize to kinds it can't name", function()
		for key, def in SHOP.products do
			local plan = ClawShowService.plan(key, false, FEATURED)
			if plan and plan.label then
				expect(plan.label ~= key).toBe(true) -- never the raw product key on screen
			end
			if not SHOP.claw.showKinds[def.grant.kind] then
				expect(plan).toBeNil()
			end
		end
	end)
end)

describe("granted", function()
	it("fires one queued show to everyone with the buyer's name", function()
		local fired = {}
		local clock = 500
		local service = ClawShowService.new({
			clock = function()
				return clock
			end,
			fire = function(event)
				table.insert(fired, event)
			end,
			featured = function()
				return FEATURED
			end,
			buyerName = function(userId)
				return if userId == 1 then "Mila" else nil
			end,
		})
		local key = keyOf("seat", function(g)
			return g.seat == "ufo"
		end)
		service.granted(1, key, false)
		service.granted(1, "VIP", true)
		service.granted(2, key, false) -- the buyer left: no show
		service.granted(1, keyOf("finishBrew"), false) -- no show for a time skip
		expect(#fired).toBe(2)
		expect(fired[1].buyer).toBe("Mila")
		expect(fired[1].display).toBe(1)
		expect(fired[1].startAt).toBeCloseTo(clock + SHOP.claw.lead, 6)
		expect(fired[2].display).toBe(ClawShow.CAPSULE)
		expect(fired[2].startAt).toBeCloseTo(fired[1].startAt + ClawShow.DURATION + SHOP.claw.gap, 6)
	end)
end)
