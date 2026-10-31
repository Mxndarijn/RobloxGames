--!strict
--[[
	ClawShowService (contract/exclusive-shop.md §7.2)

	Turns a granted Robux purchase into a claw show at the Exclusive Shop for everyone on the server. PurchaseService
	calls `granted` only after a receipt or a Game Pass is granted (and saved), so a show never plays for a purchase
	that didn't go through, and it never changes what the buyer gets. Engine access is injected (runs under Lune).

	  plan(key, isPass, featured)  what the show takes and says, or nil for no show:
	      { display, label?, gift? }: display i = the i-th shown featured seat (Visuals.ShopDisplay.seats) when the
	      bought seat is on show, else ClawShow.CAPSULE; label = the item's name for a seat or a cosmetic
	      (Purchases.itemName), nil otherwise; gift = bought as a gift. Only the grant kinds in
	      Config.EXCLUSIVE_SHOP.claw.showKinds and every Game Pass play a show.
	  new(options).granted(userId, key, isPass)  plans, queues (ClawShow.schedule) and fires one ClawShow.Event.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local ClawShow = if Shared then require(Shared.Parent.Visuals.ClawShow) else require("../visuals/shared/ClawShow")
local ShopDisplay = if Shared
	then require(Shared.Parent.Visuals.ShopDisplay)
	else require("../visuals/shared/ShopDisplay")
local Purchases = if script then require(script.Parent.Purchases) else require("./Purchases")

export type Plan = { display: number, label: string?, gift: boolean? }

export type Options = {
	clock: () -> number, -- the server clock the clients play from (workspace:GetServerTimeNow())
	fire: (event: ClawShow.Event) -> (), -- to every client (ClawShow remote)
	featured: (now: number) -> { string }, -- this week's featured seats (ExclusiveRotation)
	buyerName: (userId: number) -> string?, -- the buyer's display name; nil = they left (no show)
}

export type Service = {
	granted: (userId: number, key: string, isPass: boolean) -> (),
	queue: ClawShow.Queue,
}

local SHOP = Config.EXCLUSIVE_SHOP
-- Grant kinds Purchases.itemName names (the rest would come back as the raw key).
local NAMED = table.freeze({
	seat = true,
	trail = true,
	batSkin = true,
	plotSkin = true,
	plotBase = true,
	hat = true,
	lockStyle = true,
	fanfare = true,
})

local ClawShowService = {}

local function displayOf(seat: string?, featured: { string }): number
	if seat then
		for i, shown in ShopDisplay.seats(featured) do
			if shown == seat then
				return i
			end
		end
	end
	return ClawShow.CAPSULE
end

function ClawShowService.plan(key: string, isPass: boolean, featured: { string }): Plan?
	if isPass then
		return if SHOP.passes[key] then { display = ClawShow.CAPSULE } else nil
	end
	local def = Purchases.product(key)
	local grant = def and def.grant
	if not grant or not SHOP.claw.showKinds[grant.kind] then
		return nil
	end
	local gift = false
	local itemKey = key
	if grant.kind == "gift" then
		gift = true
		itemKey = grant.item
		local item = Purchases.product(itemKey)
		grant = item and item.grant
		if not grant then
			return nil
		end
	end
	local seat = if grant.kind == "seat" then grant.seat elseif grant.kind == "bundle" then grant.seats[1] else nil
	return {
		display = displayOf(seat, featured),
		label = if NAMED[grant.kind] then Purchases.itemName(itemKey) else nil,
		gift = if gift then true else nil,
	}
end

function ClawShowService.new(options: Options): Service
	local self = { queue = { nextFree = -math.huge } } :: Service
	function self.granted(userId: number, key: string, isPass: boolean)
		local now = options.clock()
		local plan = ClawShowService.plan(key, isPass, options.featured(now))
		local buyer = plan and options.buyerName(userId)
		if not plan or not buyer then
			return
		end
		local startAt = ClawShow.schedule(self.queue, now)
		if not startAt then
			return
		end
		options.fire({ startAt = startAt, display = plan.display, buyer = buyer, label = plan.label, gift = plan.gift })
	end
	return self
end

return ClawShowService
