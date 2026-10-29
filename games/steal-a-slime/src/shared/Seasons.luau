--!strict
--[[
	Seasons (pure, contract/exclusive-shop.md §15)

	Whether a Config.EXCLUSIVE_SHOP.seasons window (UTC month-day, inclusive, may wrap the new year) is open at a unix
	time, and which season a product sells in. A seasonal Exclusive is sold only while its season is open; owners keep
	it for good. The same answer on every server and client (UTC).
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

local Seasons = {}

local function monthDay(now: number): (number, number)
	local t = os.date("!*t", math.floor(now)) :: any
	return t.month, t.day
end

local function key(month: number, day: number): number
	return month * 100 + day
end

-- True while season `id` is open at `now`; false for an unknown id.
function Seasons.active(id: string?, now: number): boolean
	local def = if id then (Config.EXCLUSIVE_SHOP :: any).seasons[id] else nil
	if not def then
		return false
	end
	local m, d = monthDay(now)
	local at, from, to = key(m, d), key(def.from[1], def.from[2]), key(def.to[1], def.to[2])
	if from <= to then
		return at >= from and at <= to
	end
	return at >= from or at <= to -- wraps the new year
end

local function seasonOfStyle(list: { any }?, id: string): string?
	for _, def in (list or {}) :: { any } do
		if def.id == id then
			return def.season
		end
	end
	return nil
end

-- The season product `productKey` sells in, or nil (sold all year). A bundle is seasonal when an item in it is.
function Seasons.ofProduct(productKey: string): string?
	local shop = Config.EXCLUSIVE_SHOP :: any
	local def = shop.products[productKey]
	local grant = def and def.grant
	if not grant then
		return nil
	end
	local kind = grant.kind
	if kind == "seat" then
		for _, seat in Config.PET_SEATS do
			if seat.id == grant.seat then
				return (seat :: any).season
			end
		end
	elseif kind == "plotSkin" then
		for _, skin in Config.PLOT_SKINS do
			if skin.id == grant.style then
				return skin.season
			end
		end
	elseif kind == "hat" then
		return seasonOfStyle(shop.hats, grant.style)
	elseif kind == "fanfare" then
		return seasonOfStyle(shop.fanfares, grant.style)
	elseif kind == "lockStyle" then
		return seasonOfStyle(shop.lockStyles, grant.style)
	elseif kind == "gift" then
		return Seasons.ofProduct(grant.item)
	elseif kind == "pack" then
		for _, item in grant.items do
			local season = Seasons.ofProduct(item)
			if season then
				return season
			end
		end
	end
	return nil
end

-- True when `productKey` may be sold at `now`: not seasonal, or its season is open.
function Seasons.onSale(productKey: string, now: number): boolean
	local season = Seasons.ofProduct(productKey)
	return season == nil or Seasons.active(season, now)
end

return table.freeze(Seasons)
