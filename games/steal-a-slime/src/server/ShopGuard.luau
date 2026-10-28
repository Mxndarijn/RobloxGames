--!strict
--[[
	ShopGuard (CONTRACT.md §27)

	The pure checks behind OpenShop / ShopBuy: range, the validation order and the deny codes. Holds no
	state and no Roblox APIs; Actions wires it to the session and the world (`access` = what the adapter measured:
	the character's distance to the stand's Counter and whether it is alive).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Constants = if Shared then require(Shared.Constants) else require("../shared/Constants")
local Shops = if Shared then require(Shared.Shops) else require("../shared/Shops")

export type Access = { distance: number?, alive: boolean? } -- distance nil = no character / no stand

local ShopGuard = {}

-- ShopEvent Denied.code -> the text shown (CONTRACT.md §27.7). Codes from a delegated action keep their own text.
ShopGuard.MESSAGES = table.freeze({
	BadShop = "no such shop",
	NotInShop = "that isn't sold here",
	NotOpen = "open the shop first",
	OutOfRange = "too far from the shop",
	Dead = "you can't shop right now",
	Busy = "too fast",
})

-- Whether `distance` studs is within `range` (default Config.SHOP_RANGE); exactly the range counts as in range.
function ShopGuard.inRange(distance: number?, range: number?): boolean
	if type(distance) ~= "number" or distance ~= distance then
		return false
	end
	return distance <= (range or Config.SHOP_RANGE)
end

-- nil when the player may use a shop, else the deny code: Dead (no / dead character state), OutOfRange.
function ShopGuard.access(access: Access?, range: number?): string?
	if not access or access.distance == nil then
		return "OutOfRange" -- no character or no stand
	end
	if access.alive == false then
		return "Dead"
	end
	if not ShopGuard.inRange(access.distance, range) then
		return "OutOfRange"
	end
	return nil
end

export type Check = {
	shopId: any,
	itemId: any?, -- ShopBuy only
	openShop: string?, -- the session's open shop
	access: Access?,
}

-- Shops that only open a panel: OpenShop / CloseShop and the range close work as for a cash shop, ShopBuy does not
-- (the Exclusive Shop's carousel; its panel buys through MarketplaceService, contract/exclusive-shop.md §7).
ShopGuard.PANEL_SHOPS = table.freeze({ [Constants.EXCLUSIVE_SHOP_ID] = true }) :: { [string]: boolean }

-- Validation order of OpenShop (no itemId) and ShopBuy: shop id, item membership, open (ShopBuy only), alive,
-- range. Returns nil when everything holds, else the deny code.
function ShopGuard.check(c: Check): string?
	local panel = c.itemId == nil and type(c.shopId) == "string" and ShopGuard.PANEL_SHOPS[c.shopId] == true
	if Shops.shop(c.shopId) == nil and not panel then
		return "BadShop"
	end
	if c.itemId ~= nil and Shops.find(c.shopId, c.itemId) == nil then
		return "NotInShop"
	end
	if c.itemId ~= nil and c.openShop ~= c.shopId then
		return "NotOpen"
	end
	return ShopGuard.access(c.access)
end

-- Maps the refusal text of a delegated action to a deny code; anything unknown is Unavailable.
local PATTERNS: { { string } } = {
	{ "not enough cash", "NoCash" },
	{ "sold out", "SoldOut" },
	{ "already maxed", "Maxed" },
	{ "already at max", "Maxed" },
	{ "already at its longest", "Maxed" },
	{ "already own the speed coil", "Maxed" },
	{ "already owned", "Owned" },
	{ "locked: reach", "Locked" },
	{ "needs %d+ rebirths", "Locked" },
	{ "pvp is not open yet", "Locked" },
	{ "pick a slime", "BadTarget" },
	{ "not your slime", "BadTarget" },
	{ "slime is busy", "BadTarget" },
	{ "too fast", "Busy" },
}

function ShopGuard.classify(message: string?): string
	local text = string.lower(message or "")
	for _, row in PATTERNS do
		if string.find(text, row[1]) then
			return row[2]
		end
	end
	return "Unavailable"
end

-- The OpenShop attribute / session state after the shop left range, died or was closed: the Close reason,
-- or nil to stay open.
function ShopGuard.closeReason(openShop: string?, access: Access?, range: number?): string?
	if openShop == nil then
		return nil
	end
	local code = ShopGuard.access(access, range)
	if code == "Dead" then
		return "dead"
	elseif code ~= nil then
		return "range"
	end
	return nil
end

return table.freeze(ShopGuard)
