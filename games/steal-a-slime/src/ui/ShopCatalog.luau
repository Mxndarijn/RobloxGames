--!strict
--[[
	ShopCatalog

	Client-side catalogue for the Shop panel (Panels/Shop). Pure
	(tests/ui/ShopCatalog.spec.luau). Every purchase is `Request(action, ...)`;
	the client never decides outcomes.

	CONTRACT gaps (UI-CONTRACT-GAPS.md): only "Lock" exists today. The lock
	upgrade and Speed Coil use the *expected* actions "BuyLockUpgrade" and
	"BuySpeedCoil", and read prices from an expected optional `State.shop`:

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

export type ItemView = {
	item: Item,
	icon: string,
	description: string,
	price: number?,
	available: boolean, -- the server knows this action
	maxed: boolean, -- owned / max level
	enabled: boolean,
	buttonText: string,
	levelText: string?,
}

local ShopCatalog = {}

ShopCatalog.ITEMS = table.freeze({
	table.freeze({
		id = "Lock",
		name = "Lock base",
		icon = "🔒",
		description = "Blocks thieves.",
		action = "Lock",
		args = {},
	}),
	table.freeze({
		id = "LockUpgrade",
		name = "Longer locks",
		icon = "⏱️",
		description = "Every lock lasts longer.",
		action = "BuyLockUpgrade", -- TODO(CONTRACT): expected action name
		args = {},
	}),
	table.freeze({
		id = "SpeedCoil",
		name = "Speed Coil",
		icon = "⚡",
		description = "Run faster, also while carrying",
		action = "BuySpeedCoil", -- TODO(CONTRACT): expected action name
		args = {},
	}),
	table.freeze({
		id = "MysteryEgg",
		name = "Mystery Egg",
		icon = "🥚",
		description = "Hatches a random slime. Cash only.",
		action = "BuyEgg", -- shown only while State.shop.MysteryEgg exists (FEATURES.MysteryEgg)
		args = {},
	}),
} :: { Item })

-- Badge emoji per v13 upgrade id (Config.UPGRADES); unknown ids get ⬆️.
ShopCatalog.UPGRADE_ICONS = table.freeze({
	Income = "🍪",
	CarrySpeed = "💪",
	OfflineCap = "🌙",
	Luck = "🍀",
	RainMagnet = "🧲",
})

-- v28 short row text per upgrade id: the leading number of `text` (e.g.
-- "+4%") + this phrase. Unknown ids (or no number) keep the server text.
ShopCatalog.UPGRADE_SHORT = table.freeze({
	Luck = "rarity-up chance",
	RainMagnet = "weather mutation chance",
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

-- Status for one item from a State snapshot. "Lock" is built from the real
-- lockCost / lockDuration fields; others read the expected `state.shop`.
function ShopCatalog.status(item: Item, state: any): ItemStatus?
	if type(state) ~= "table" then
		return nil
	end
	if item.id == "Lock" then
		return if type(state.lockCost) == "number" then { price = state.lockCost } else nil
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
	return `Speed {base} → {coil}, also while carrying`
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
	if item.id == "Lock" and type(state) == "table" and type(state.lockDuration) == "number" then
		description = `Blocks thieves +{math.floor(state.lockDuration)}s.`
	elseif item.id == "SpeedCoil" then
		description = ShopCatalog.speedCoilText(config) or description
	end

	local buttonText
	if not available then
		buttonText = "Coming soon"
	elseif maxed then
		buttonText = if status and status.owned then "Owned" else "Max"
	elseif price then
		buttonText = Format.formatCash(price)
	else
		buttonText = "Buy"
	end

	return {
		item = item,
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
			if not available then
				buttonText = "Coming soon"
			elseif maxed then
				buttonText = "Max"
			elseif not unlocked then
				buttonText = `Rebirth {u.requires or "?"}`
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
				icon = icon,
				description = text,
				price = price,
				available = available,
				maxed = maxed,
				enabled = available and unlocked and not maxed and (price == nil or cash >= price),
				buttonText = buttonText,
				levelText = `Lv {level}/{maxLevel}`,
			})
		end
	end
	return out
end

-- Static items, then the v13 upgrades.
function ShopCatalog.views(state: any, actions: { [string]: any }, config: any?): { ItemView }
	local out = {}
	for _, item in ShopCatalog.ITEMS do
		if item.id ~= "MysteryEgg" or ShopCatalog.status(item, state) then
			table.insert(out, ShopCatalog.view(item, state, actions, config))
		end
	end
	for _, view in ShopCatalog.upgradeViews(state, actions) do
		table.insert(out, view)
	end
	return out
end

return table.freeze(ShopCatalog)
