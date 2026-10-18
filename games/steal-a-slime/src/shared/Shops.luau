--!strict
--[[
	Shops (CONTRACT.md §27.5)

	The catalogue of the two world shops, one source for the server (ShopBuy item membership, which existing
	action a purchase delegates to) and for the client UI. Names / icons / text come from Config (UPGRADES,
	CONSUMABLES, PVP_TOOLS); Lock, Longer locks, Speed Coil and Mystery Egg are the strings the HUD Shop already
	shows. Ids are action args and save keys: never rename. Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

export type Item = {
	id: string,
	name: string,
	icon: string,
	text: string,
	action: string, -- the existing Request action a purchase delegates to
	argIsItem: boolean, -- the item id is also that action's first argument (BuyUpgrade, BuyConsumable, BuyPvpItem)
	flag: string?, -- Config.FEATURES name that must be on for the item to be listed or bought
}

export type Shop = {
	id: string,
	name: string,
	stand: string, -- model name under workspace.Map
	items: { Item },
}

local Shops = {}

Shops.ITEM_SHOP = "ItemShop"
Shops.UPGRADE_SHOP = "UpgradeShop"

local function item(
	id: string,
	name: string,
	icon: string,
	text: string,
	action: string,
	argIsItem: boolean,
	flag: string?
): Item
	return table.freeze({
		id = id,
		name = name,
		icon = icon,
		text = text,
		action = action,
		argIsItem = argIsItem,
		flag = flag,
	})
end

local itemRows: { Item } = {
	item("Lock", "Lock base", "🔒", "Blocks thieves.", "Lock", false, nil),
	item("MysteryEgg", "Mystery Egg", "🥚", "Hatches a random slime. Cash only.", "BuyEgg", false, nil),
	-- An item, not an upgrade: it works while it is held in the hand (a Tool in the Backpack, a hotbar slot).
	item("SpeedCoil", "Speed Coil", "⚡", "Run faster, also while carrying", "BuySpeedCoil", false, nil),
}
for _, def in Config.CONSUMABLES do
	table.insert(itemRows, item(def.id, def.name, def.icon, def.text, "BuyConsumable", true, "Consumables"))
end
for _, tool in Config.PVP_TOOLS do
	table.insert(itemRows, item(tool.id, tool.name, "🎯", tool.name, "BuyPvpItem", true, "PvP"))
end

local upgradeRows: { Item } = {
	item("LockUpgrade", "Longer locks", "⏱️", "Every lock lasts longer.", "BuyLockUpgrade", false, nil),
}
local UPGRADE_ICONS: { [string]: string } =
	{ Income = "🍪", CarrySpeed = "💪", OfflineCap = "🌙", Luck = "🍀", RainMagnet = "🧲" }
for _, def in Config.UPGRADES do
	table.insert(
		upgradeRows,
		item(def.id, def.name, UPGRADE_ICONS[def.id] or "⬆️", def.text, "BuyUpgrade", true, def.flag)
	)
end

Shops.SHOPS = table.freeze({
	ItemShop = table.freeze({
		id = "ItemShop",
		name = "Item Shop",
		stand = "ItemShopStand",
		items = table.freeze(itemRows),
	}),
	UpgradeShop = table.freeze({
		id = "UpgradeShop",
		name = "Upgrade Shop",
		stand = "UpgradeShopStand",
		items = table.freeze(upgradeRows),
	}),
}) :: { [string]: Shop }

-- Display order of the shops.
Shops.ORDER = table.freeze({ "ItemShop", "UpgradeShop" })

function Shops.shop(shopId: any): Shop?
	if type(shopId) ~= "string" then
		return nil
	end
	return Shops.SHOPS[shopId]
end

local function listed(row: Item, features: { [string]: any }): boolean
	return row.flag == nil or features[row.flag] == true
end

-- The shop's items whose feature flags are on (`features` = Config.FEATURES), in display order.
function Shops.items(shopId: string, features: { [string]: any }?): { Item }
	local shop = Shops.shop(shopId)
	local out: { Item } = {}
	if not shop then
		return out
	end
	local on = features or Config.FEATURES
	for _, row in shop.items do
		if listed(row, on) then
			table.insert(out, row)
		end
	end
	return out
end

-- The item row `itemId` of `shopId` (flags ignored), or nil when that shop does not sell it.
function Shops.find(shopId: string, itemId: any): Item?
	local shop = Shops.shop(shopId)
	if not shop or type(itemId) ~= "string" then
		return nil
	end
	for _, row in shop.items do
		if row.id == itemId then
			return row
		end
	end
	return nil
end

-- The id of the shop that sells `itemId`, or nil.
function Shops.shopOf(itemId: any): string?
	for _, shopId in Shops.ORDER do
		if Shops.find(shopId, itemId) then
			return shopId
		end
	end
	return nil
end

-- The shop whose purchase action is `action` (Lock, BuyEgg, BuyUpgrade, ...), or nil for any other action.
function Shops.shopOfAction(action: any): string?
	for _, shopId in Shops.ORDER do
		for _, row in (Shops.SHOPS[shopId] :: Shop).items do
			if row.action == action then
				return shopId
			end
		end
	end
	return nil
end

return table.freeze(Shops)
