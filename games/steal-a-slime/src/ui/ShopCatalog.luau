--!strict
--[[
	ShopCatalog

	Client-side shop row logic behind the world shops (WorldShopLogic.rows,
	Panels/WorldShop). Pure (tests/ui/ShopCatalog.spec.luau). Every purchase is `Request(action, ...)`;
	the client never decides outcomes.

	Locks are not sold here: the lock button on your own plot buys them. The
	Speed Coil uses "BuySpeedCoil" and reads its price from `State.shop`:

		shop: { [itemId]: { price: number?, level: number?, maxLevel: number?, owned: boolean? } }?

	Until `Remotes.ACTIONS` has an item's action the row shows "Coming soon"
	and its button is disabled (the UI's `send` asserts known actions).
]]

local Format = if script then require(script.Parent.Format) else require("./Format")

export type Item = {
	id: string,
	name: string,
	icon: string, -- emoji on the item's round badge (v28: icons over text)
	description: string, -- short: at most two lines on a phone
	action: string,
	args: { any },
}

-- Server-provided per-item status (expected `State.shop[id]`).
export type ItemStatus = { price: number?, level: number?, maxLevel: number?, owned: boolean? }

-- What a row's right side shows: a Buy button ("buy", also while unaffordable) or a state.
export type Status = "buy" | "locked" | "maxed" | "owned" | "soldOut" | "unavailable"

export type ItemView = {
	item: Item,
	status: Status,
	icon: string,
	description: string,
	price: number?,
	available: boolean, -- the server knows this action
	maxed: boolean, -- owned / max level
	enabled: boolean,
	buttonText: string,
	levelText: string?,
	progress: number?, -- level / maxLevel (0..1) of a leveled item
	level: number?, -- current level of a leveled item (one Upgrade Shop pip each)
	maxLevel: number?,
	stockText: string?, -- "2/3 left" of a restocking consumable
}

local ShopCatalog = {}

ShopCatalog.ITEMS = table.freeze({
	table.freeze({
		id = "SpeedCoil",
		name = "Speed Coil",
		icon = "⚡",
		description = "Hold it to run faster",
		action = "BuySpeedCoil",
		args = {},
	}),
} :: { Item })

-- Badge emoji per v13 upgrade id (Config.UPGRADES); unknown ids get ⬆️.
ShopCatalog.UPGRADE_ICONS = table.freeze({
	Income = "🍪",
	CarrySpeed = "💪",
	OfflineCap = "🌙",
	Luck = "🍀",
})

-- v28 short row text per upgrade id: the leading number of `text` (e.g.
-- "+4%") + this phrase. Unknown ids (or no number) keep the server text.
ShopCatalog.UPGRADE_SHORT = table.freeze({
	Luck = "rarity-up chance",
})

-- The one-line description of a v13 upgrade row.
function ShopCatalog.upgradeText(id: string, text: string): string
	local phrase = (ShopCatalog.UPGRADE_SHORT :: any)[id]
	local amount = string.match(text, "^([%+%-]%d+%.?%d*%%?)")
	return if phrase and amount then `{amount} {phrase}` else text
end

function ShopCatalog.find(id: string): Item?
	for _, item in ShopCatalog.ITEMS do
		if item.id == id then
			return item
		end
	end
	return nil
end

-- Status for one item from a State snapshot (`state.shop`).
function ShopCatalog.status(item: Item, state: any): ItemStatus?
	if type(state) ~= "table" then
		return nil
	end
	local shop = state.shop
	local entry = if type(shop) == "table" then shop[item.id] else nil
	return if type(entry) == "table" then entry :: ItemStatus else nil
end

-- Speed Coil copy from Config walk speeds (the coil also boosts while
-- carrying: v15 playtest measured 16 -> 22, carrying 13.6 -> 19.8).
function ShopCatalog.speedCoilText(config: any): string?
	local base = if type(config) == "table" then config.BASE_WALK_SPEED else nil
	local coil = if type(config) == "table" then config.SPEED_COIL_WALK_SPEED else nil
	if type(base) ~= "number" or type(coil) ~= "number" then
		return nil
	end
	return `Hold it: speed {base} → {coil}`
end

-- `config` (optional, Shared Config) fills in numbers for some descriptions.
function ShopCatalog.view(item: Item, state: any, actions: { [string]: any }, config: any?): ItemView
	local status = ShopCatalog.status(item, state)
	local available = actions[item.action] ~= nil
	local price = if status and type(status.price) == "number" then status.price else nil
	local level = if status then status.level else nil
	local maxLevel = if status then status.maxLevel else nil
	local maxed = status ~= nil
		and (status.owned == true or (type(level) == "number" and type(maxLevel) == "number" and level >= maxLevel))
	local cash = if type(state) == "table" and type(state.cash) == "number" then state.cash else 0
	local affordable = price == nil or cash >= price

	local description = item.description
	if item.id == "SpeedCoil" then
		description = ShopCatalog.speedCoilText(config) or description
	end

	local owned = status ~= nil and status.owned == true
	local buttonText
	local kind: Status = "buy"
	if not available then
		buttonText, kind = "Coming soon", "unavailable"
	elseif maxed then
		buttonText = if owned then "Owned" else "Max"
		kind = if owned then "owned" else "maxed"
	elseif price then
		buttonText = Format.formatCash(price)
	else
		buttonText = "Buy"
	end

	return {
		item = item,
		status = kind,
		icon = item.icon,
		description = description,
		price = price,
		available = available,
		maxed = maxed,
		enabled = available and not maxed and affordable,
		buttonText = buttonText,
		levelText = if type(level) == "number"
			then (if type(maxLevel) == "number" then `Lv {level}/{maxLevel}` else `Lv {level}`)
			else nil,
		progress = if type(level) == "number"
				and type(maxLevel) == "number"
				and maxLevel > 0
			then math.clamp(level / maxLevel, 0, 1)
			else nil,
		level = if type(level) == "number" then level else nil,
		maxLevel = if type(level) == "number" and type(maxLevel) == "number" then maxLevel else nil,
	}
end

-- v13 upgrades (CONTRACT §8.1 / §8.2): one row per `State.upgrades` entry,
-- bought with Request("BuyUpgrade", id). Empty when the field is missing.
-- Locked rows say which rebirth unlocks them (on the button).
function ShopCatalog.upgradeViews(state: any, actions: { [string]: any }): { ItemView }
	local out = {}
	local upgrades = if type(state) == "table" then state.upgrades else nil
	if type(upgrades) ~= "table" then
		return out
	end
	local available = actions.BuyUpgrade ~= nil
	local cash = if type(state.cash) == "number" then state.cash else 0
	for _, u in upgrades do
		if type(u) == "table" and type(u.id) == "string" then
			local level = if type(u.level) == "number" then u.level else 0
			local maxLevel = if type(u.maxLevel) == "number" then u.maxLevel else level
			local maxed = level >= maxLevel
			local unlocked = u.unlocked ~= false
			local price = if type(u.price) == "number" then u.price else nil
			local buttonText
			local kind: Status = "buy"
			if not available then
				buttonText, kind = "Coming soon", "unavailable"
			elseif maxed then
				buttonText, kind = "Max", "maxed"
			elseif not unlocked then
				buttonText, kind = `Rebirth {u.requires or "?"}`, "locked"
			elseif price then
				buttonText = Format.formatCash(price)
			else
				buttonText = "Buy"
			end
			local text = ShopCatalog.upgradeText(u.id, if type(u.text) == "string" then u.text else "")
			local icon = (ShopCatalog.UPGRADE_ICONS :: any)[u.id] or "⬆️"
			table.insert(out, {
				item = {
					id = `Upgrade_{u.id}`,
					name = if type(u.name) == "string" then u.name else u.id,
					icon = icon,
					description = text,
					action = "BuyUpgrade",
					args = { u.id },
				},
				status = kind,
				icon = icon,
				description = text,
				price = price,
				available = available,
				maxed = maxed,
				enabled = available and unlocked and not maxed and (price == nil or cash >= price),
				buttonText = buttonText,
				levelText = `Lv {level}/{maxLevel}`,
				progress = if maxLevel > 0 then math.clamp(level / maxLevel, 0, 1) else nil,
				level = level,
				maxLevel = maxLevel,
			})
		end
	end
	return out
end

-- Restocking consumables (FEATURES.Consumables, `State.consumables`): one row per stocked item, bought
-- with Request("BuyConsumable", id): it adds to the held stack.
-- Empty while the feature is off.
function ShopCatalog.consumableViews(state: any, actions: { [string]: any }): { ItemView }
	local out = {}
	local view = if type(state) == "table" then state.consumables else nil
	if type(view) ~= "table" then
		return out
	end
	local available = actions.BuyConsumable ~= nil
	local cash = if type(state.cash) == "number" then state.cash else 0
	for _, c in view.items do
		local soldOut = c.left <= 0
		local buttonText
		local kind: Status = "buy"
		if not available then
			buttonText, kind = "Coming soon", "unavailable"
		elseif soldOut then
			buttonText, kind = "Sold out", "soldOut"
		else
			buttonText = Format.formatCash(c.price)
		end
		table.insert(out, {
			item = {
				id = `Consumable_{c.id}`,
				name = c.name,
				icon = c.icon,
				description = c.text,
				action = "BuyConsumable",
				args = { c.id },
			},
			status = kind,
			icon = c.icon,
			description = c.text,
			price = c.price,
			available = available,
			maxed = soldOut,
			enabled = available and not soldOut and cash >= c.price,
			buttonText = buttonText,
			levelText = `{c.left}/{c.max} left`,
			stockText = `{c.left}/{c.max} left`,
		})
	end
	return out
end

-- "Restocks in 3:07" for the consumables header, from the unix restock time and the current server time.
function ShopCatalog.restockText(restockAt: number, now: number): string
	local left = math.max(0, math.ceil(restockAt - now))
	return `Restocks in {left // 60}:{string.format("%02d", left % 60)}`
end

return table.freeze(ShopCatalog)
