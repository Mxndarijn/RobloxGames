--!strict
-- Config with every Exclusive Shop id cleared (product / pass 0, subscription ""): the "not created on Roblox yet"
-- state the shop specs start from. The real ids live in src/shared/ExclusiveIds.luau.
local Config = require("../../src/shared/Config")

local function zeroed(map: { [string]: any }, field: string, empty: any): { [string]: any }
	local out = {}
	for key, def in map do
		local copy = table.clone(def)
		copy[field] = empty
		out[key] = copy
	end
	return out
end

local shop = table.clone(Config.EXCLUSIVE_SHOP) :: any
shop.products = zeroed(Config.EXCLUSIVE_SHOP.products, "productId", 0)
shop.passes = zeroed(Config.EXCLUSIVE_SHOP.passes, "passId", 0)
shop.subscriptions = zeroed(Config.EXCLUSIVE_SHOP.subscriptions, "subscriptionId", "")
local config = table.clone(Config) :: any
config.EXCLUSIVE_SHOP = shop
return config
