--!strict
--[[
	ExclusiveShopView (pure)

	What the Exclusive shop and its quick-buys show (contract/exclusive-shop.md §1, §5, §8), from
	Config.EXCLUSIVE_SHOP (the catalogue: keys, Robux prices, Roblox ids) and State.exclusiveShop (what this player
	owns). Panels/ExclusiveShop renders `cards` / `detail`; Merge, Welcome, WorldShop and SlimeKeys ask the
	`*QuickBuy` functions whether their button shows and what it says. Nothing here grants or decides: a Buy hands
	a `Purchase` to the PurchasePrompt adapter, and State says what was bought. Without State.exclusiveShop
	(before the first State) every function returns nothing to show.

	Style (§9, §10): carry trails and Bat skins, bought, equipped with EquipTrail / EquipBatSkin and taken off with
	"" (no trail / the default Bat). Gifts (§12): every cosmetic card's pane also has a Gift button (Gift_<key>, or
	"Send gift" for an unsent gift credit); `giftTargets` orders the players the picker offers.

	Fairness (contract §1): the shop sells looks, comfort and time. The paid Luck Potion is the one paid
	probability modifier: it hides where paid random items are restricted (`paidRandomAllowed`), and its card
	explains the effect in numbers and lists the fountain odds with and without it behind "Details".
]]

local Format = if script then require(script.Parent.Format) else require("./Format")

local ExclusiveShopView = {}

local boostCredit: (state: any, card: any) -> string?

-- `id`: the Developer Product / Game Pass id; a subscription sells by `subscriptionId` ("EXP-...") and keeps id 0.
export type Purchase = { kind: "product" | "pass" | "subscription", id: number, subscriptionId: string? }

export type CardState = "buy" | "offsale" | "owned" | "equipped" | "info"

export type Kind = "seat" | "trail" | "batSkin" | "product" | "pass" | "subscription" | "info"

export type Card = {
	key: string, -- "seat:<id>", "trail:<id>", "batSkin:<id>", "product:<key>", "pass:<key>", "sub:<key>", "info:<key>"
	kind: Kind,
	id: string, -- seat id, product key or pass key
	title: string,
	icon: string, -- ItemIcons registry id
	priceText: string, -- "R$99"; "" for an info card
	state: CardState,
	tag: string, -- the card's chip: the price, "Owned", "Equipped" or where it is sold
}

export type Equip = { request: string, arg: string } -- Request(request, arg): EquipPetSeat / EquipTrail / EquipBatSkin / ClaimPerk

export type Action = {
	kind: "buy" | "offsale" | "equip" | "well",
	text: string,
	purchase: Purchase?, -- kind "buy": what Roblox's prompt sells
	equip: Equip?, -- kind "equip"
}

-- A cosmetic's Gift button: buy Gift_<key> for a picked player, send an unsent gift credit, or not on sale yet.
export type Gift = {
	mode: "buy" | "send" | "offsale",
	text: string,
	itemKey: string, -- the cosmetic's product key ("Seat_ufo", "Trail_sparkle", "BatSkin_fish")
	purchase: Purchase?, -- mode "buy": Gift_<itemKey>
}

-- A player the gift picker offers (players on this server, not you).
export type GiftTarget = { userId: number, name: string, friend: boolean }

export type OddsRow = { name: string, base: string, boosted: string, tier: number }

export type Detail = {
	key: string,
	kind: Kind,
	id: string,
	title: string,
	icon: string,
	text: string,
	priceText: string,
	state: CardState,
	exclusive: boolean, -- an Exclusive seat: the gold tag
	action: Action,
	odds: { OddsRow }?, -- a paid probability modifier (Luck Potion, Lucky Charm+): the odds without / with it
	effect: { string }?, -- a paid probability modifier: its effect in numbers
	unequip: Equip?, -- an equipped trail / Bat skin: Request(request, "") takes it off
	unequipText: string?,
	gift: Gift?, -- every cosmetic (seat, trail, Bat skin); never a pass or a boost
}

export type QuickBuy = {
	mode: "buy" | "credit" | "offsale",
	text: string,
	key: string, -- the product key ("FinishBrew_2", "HatchNow_golden", ...)
	purchase: Purchase?, -- mode "buy"
}

ExclusiveShopView.TITLE = "Exclusive shop"
ExclusiveShopView.OFF_SALE = "Not on sale yet"
ExclusiveShopView.OWNED = "Owned"
ExclusiveShopView.EQUIP = "Equip"
ExclusiveShopView.EQUIPPED = "Equipped"
ExclusiveShopView.EXCLUSIVE = "Exclusive"
ExclusiveShopView.WAITING = "Waiting for Roblox"
ExclusiveShopView.BOUGHT = "Bought"
ExclusiveShopView.BOUGHT_SEAT = "It is in Skins, Cloud tab. Equip it here or there."
ExclusiveShopView.USE_CREDIT = "Use credit"
ExclusiveShopView.DETAILS = "Details"
ExclusiveShopView.HIDE_DETAILS = "Hide details"
ExclusiveShopView.EMPTY = "The Exclusive shop is closed on this server."
ExclusiveShopView.EMPTY_TAB = "Nothing here right now. Look again next week."
ExclusiveShopView.OPEN_LOCKED_DOOR = "Open locked door"
ExclusiveShopView.USE_LOCK_BREAK = "Use lock break"
ExclusiveShopView.LOCK_BREAK_REFUSED = "This door can't be opened right now."
ExclusiveShopView.GIFT = "Gift"
ExclusiveShopView.SEND_GIFT = "Send gift"
ExclusiveShopView.GIFT_OFF_SALE = "Gift not on sale"
ExclusiveShopView.GIFT_TITLE = "Gift to"
ExclusiveShopView.GIFT_HINT = "Pick a player on this server. Friends are first."
ExclusiveShopView.GIFT_EMPTY = "Nobody else is on this server right now."
ExclusiveShopView.GIFT_REFUSED = "They can't get this gift."
ExclusiveShopView.BACK = "Back"
ExclusiveShopView.FRIEND = "Friend"
ExclusiveShopView.UNEQUIP_TRAIL = "Unequip"
ExclusiveShopView.DEFAULT_BAT = "Use default Bat"
ExclusiveShopView.TRAIL_TEXT = "Streams behind you while you carry a slime. Everyone can see it."
ExclusiveShopView.BAT_TEXT = "A new look for your Bat. It hits exactly like the default Bat."
ExclusiveShopView.VIP_POTION = "Give the server a potion"
ExclusiveShopView.VIP_POTION_USED = "Potion given today"
ExclusiveShopView.SUBSCRIBED = "Member"
ExclusiveShopView.LUCK_NOTE = "Only for wild slimes you bring home. Stolen slimes never get the Lucky Charm."
ExclusiveShopView.ODDS_NOTE = "Fountain drops before rain and events. Each potion adds time; the boost never stacks."

-- Shop texts per product / pass key (Config.EXCLUSIVE_SHOP keys).
ExclusiveShopView.TEXTS = table.freeze({
	StarterBundle = table.freeze({
		title = "Starter bundle",
		icon = "Gift",
		text = "The Leaf cloud for your pet and x2 income for 15 minutes. Once per player.",
	}),
	ServerLuckPotion = table.freeze({
		title = "Server Luck Potion",
		icon = "Consumable_LuckPotion",
		text = "Gives everyone on this server a Luck Potion: rarer slimes from the fountain.",
	}),
	Income2x = table.freeze({
		title = "x2 income",
		icon = "Perk_income",
		text = "Every slime on your pads earns twice as much, for good.",
	}),
	Offline2x = table.freeze({
		title = "x2 offline cash",
		icon = "Upgrade_OfflineCap",
		text = "Earn half your income while you are away instead of a quarter, for good.",
	}),
	VIP = table.freeze({
		title = "VIP",
		icon = "Badge_Millionaire",
		text = "A gold VIP tag over your name and in chat, +10% income, and one free Luck Potion for the whole server every day.",
	}),
	FastBrew = table.freeze({
		title = "Fast brew",
		icon = "Upgrade_QuickBrew",
		text = "Every merge brews in half the time, for good. Stacks with the Quick Brew upgrade.",
	}),
	WarmNest = table.freeze({
		title = "Warm nest",
		icon = "MysteryEgg",
		text = "Mystery Eggs on your pads incubate at the warm speed even while you are away from home.",
	}),
	LuckyCharmPlus = table.freeze({
		title = "Lucky Charm+",
		icon = "Upgrade_Luck",
		text = "+5% chance that a wild slime you bring home turns one rarity higher.",
	}),
	ThiefRadar = table.freeze({
		title = "Thief radar",
		icon = "Goal_Steal",
		text = "Tells you when someone walks into your base while you are away, and points you to them. Information only.",
	}),
	SlimeClub = table.freeze({
		title = "Slime Club",
		icon = "Daily",
		text = "Monthly: a CLUB tag, and a free Finish now and Hatch now credit every day while you are a member.",
	}),
	SlimeRain = table.freeze({
		title = "Slime Rain",
		icon = "Event_rain",
		text = "Starts a Slime Rain for the whole server right now: more slimes and rarer ones. At most one paid rain per server every 20 minutes, never during a boss. If it can't start, you keep it as a credit.",
	}),
	SummonBoss = table.freeze({
		title = "Summon the boss",
		icon = "Slap",
		text = "The boss comes to this server after its usual warning. Once per server every 20 minutes. If it can't come now, you keep it as a credit.",
	}),
	WeatherTotem = table.freeze({
		title = "Weather Totem",
		icon = "Consumable_WeatherTotem",
		text = "Makes the Item shop totem's weather the next one, for everyone on the server. If the weather can't change now, you keep it as a credit.",
	}),
	IncomeBoost15 = table.freeze({
		title = "x2 income, 15 min",
		icon = "Boost_Code",
		text = "Doubles your income for 15 minutes. Adds to a running boost, up to the boost cap.",
	}),
	IncomeBoost60 = table.freeze({
		title = "x2 income, 1 hour",
		icon = "Boost_Code",
		text = "Doubles your income for an hour. Adds to a running boost, up to the boost cap.",
	}),
	KeepStreak = table.freeze({
		title = "Keep my streak",
		icon = "Daily",
		text = "Missed a day? Your daily streak carries on as if you had not.",
		where = "Buy it on the Daily reward",
		tag = "Daily",
	}),
	GrowthSnack = table.freeze({
		title = "Growth snack",
		icon = "Pet",
		text = "One slime of yours grows 3 hours at once. Pick the slime on its pad.",
		where = "Buy it on a slime's card",
		tag = "On slime",
	}),
	FinishBrew = table.freeze({
		title = "Finish now",
		icon = "Upgrade_QuickBrew",
		text = "Ends a brewing merge right away. The slime it makes is set when the brew starts.",
		where = "Buy it at the Merge vat",
		tag = "Merge vat",
	}),
	HatchNow = table.freeze({
		title = "Hatch now",
		icon = "MysteryEgg",
		text = "Makes an incubating Mystery Egg ready to hatch. What is inside is set when it starts.",
		where = "Buy it at your egg",
		tag = "Your egg",
	}),
	DoubleOffline = table.freeze({
		title = "Double it",
		icon = "Cash",
		text = "Doubles the cash you earned while you were away, once per return.",
		where = "Buy it on Welcome back",
		tag = "On return",
	}),
})

ExclusiveShopView.SEAT_TEXT = "Your follow pet rides on it, everywhere you go."

local INFO_KEYS = { "FinishBrew", "HatchNow", "DoubleOffline", "KeepStreak", "GrowthSnack" }

-- Boosts tab products, in order. `random`: changes the odds (hidden where paid random items are restricted).
-- `credit`: the State.exclusiveShop.credits kind a refused one is kept as (spent with UseCredit).
local BOOSTS = table.freeze({
	table.freeze({ key = "ServerLuckPotion", random = true }),
	table.freeze({ key = "SlimeRain", random = true, credit = "rain" }),
	table.freeze({ key = "WeatherTotem", random = true, credit = "totem" }),
	table.freeze({ key = "SummonBoss", credit = "boss" }),
	table.freeze({ key = "IncomeBoost15" }),
	table.freeze({ key = "IncomeBoost60" }),
})
ExclusiveShopView.BOOSTS = BOOSTS

local function shopOf(state: any): any?
	return if type(state) == "table" and type(state.exclusiveShop) == "table" then state.exclusiveShop else nil
end

local function catalogueOf(config: any): any?
	return if type(config) == "table" then config.EXCLUSIVE_SHOP else nil
end

-- The product `key`'s Purchase, or nil without such a product.
function ExclusiveShopView.productPurchase(config: any, key: string): Purchase?
	local cat = catalogueOf(config)
	local def = cat and cat.products[key]
	return if def then { kind = "product", id = def.productId } else nil
end

function ExclusiveShopView.passPurchase(config: any, key: string): Purchase?
	local cat = catalogueOf(config)
	local def = cat and cat.passes[key]
	return if def then { kind = "pass", id = def.passId } else nil
end

local function onSale(p: Purchase?): boolean
	if p ~= nil and p.kind == "subscription" then
		return type(p.subscriptionId) == "string" and p.subscriptionId ~= ""
	end
	return p ~= nil and type(p.id) == "number" and p.id > 0
end

function ExclusiveShopView.subscriptionPurchase(config: any, key: string): Purchase?
	local cat = catalogueOf(config)
	local def = cat and cat.subscriptions and cat.subscriptions[key]
	return if def then { kind = "subscription", id = 0, subscriptionId = def.subscriptionId } else nil
end

local function robuxOf(config: any, key: string, pass: boolean?): number
	local cat = catalogueOf(config)
	local def = if cat then (if pass then cat.passes[key] else cat.products[key]) else nil
	return if def then def.robux else 0
end

-- True for a pass that changes a roll (Lucky Charm+): hidden where paid random items are restricted.
local function paidRandomPass(config: any, key: string): boolean
	local cat = catalogueOf(config)
	local def = cat and cat.passes[key]
	return def ~= nil and def.luckBonus ~= nil
end

-- The Exclusive seat `id`'s name from Config.PET_SEATS (sentence case, as the Skins menu shows it).
function ExclusiveShopView.seatName(config: any, id: string): string
	for _, seat in config.PET_SEATS or {} do
		if seat.id == id then
			return Format.sentenceCase(seat.name)
		end
	end
	return Format.sentenceCase(id)
end

local function exclusiveSeats(config: any): { string }
	local out = {}
	for _, seat in config.PET_SEATS or {} do
		if seat.unlock and seat.unlock.kind == "exclusive" then
			table.insert(out, seat.id)
		end
	end
	return out
end

local function equippedSeat(state: any): string?
	return if type(state) == "table" and type(state.petSeat) == "string" then state.petSeat else nil
end

-- The card of Exclusive seat `id`.
local function seatCard(state: any, shop: any, config: any, id: string): Card
	local key = `Seat_{id}`
	local purchase = ExclusiveShopView.productPurchase(config, key)
	local price = Format.robux(robuxOf(config, key))
	local owned = type(shop.owned) == "table" and shop.owned[id] == true
	local s: CardState = if owned and equippedSeat(state) == id
		then "equipped"
		elseif owned then "owned"
		elseif onSale(purchase) then "buy"
		else "offsale"
	return {
		key = `seat:{id}`,
		kind = "seat",
		id = id,
		title = ExclusiveShopView.seatName(config, id),
		icon = `PetSeat_{id}`,
		priceText = price,
		state = s,
		tag = if s == "equipped"
			then ExclusiveShopView.EQUIPPED
			elseif s == "owned" then ExclusiveShopView.OWNED
			else price,
	}
end

-- Config.EXCLUSIVE_SHOP.trails / batSkins entries.
local function styleDefs(config: any, kind: "trail" | "batSkin"): { any }
	local cat = catalogueOf(config)
	local list = cat and (if kind == "trail" then cat.trails else cat.batSkins)
	return if type(list) == "table" then list else {}
end

local STYLE_KINDS = table.freeze({
	trail = table.freeze({
		prefix = "Trail_",
		owned = "trails",
		worn = "trail",
		request = "EquipTrail",
		text = ExclusiveShopView.TRAIL_TEXT,
		unequip = ExclusiveShopView.UNEQUIP_TRAIL,
	}),
	batSkin = table.freeze({
		prefix = "BatSkin_",
		owned = "batSkins",
		worn = "batSkin",
		request = "EquipBatSkin",
		text = ExclusiveShopView.BAT_TEXT,
		unequip = ExclusiveShopView.DEFAULT_BAT,
	}),
})

-- The card of carry trail / Bat skin `def` (Config.EXCLUSIVE_SHOP.trails / batSkins).
local function styleCard(shop: any, config: any, kind: "trail" | "batSkin", def: any): Card
	local k = STYLE_KINDS[kind]
	local key = `{k.prefix}{def.id}`
	local price = Format.robux(robuxOf(config, key))
	local ownedSet = shop[k.owned]
	local owned = type(ownedSet) == "table" and ownedSet[def.id] == true
	local s: CardState = if owned and shop[k.worn] == def.id
		then "equipped"
		elseif owned then "owned"
		elseif onSale(ExclusiveShopView.productPurchase(config, key)) then "buy"
		else "offsale"
	return {
		key = `{kind}:{def.id}`,
		kind = kind,
		id = def.id,
		title = def.name,
		icon = key,
		priceText = price,
		state = s,
		tag = if s == "equipped"
			then ExclusiveShopView.EQUIPPED
			elseif s == "owned" then ExclusiveShopView.OWNED
			else price,
	}
end

local function productCard(config: any, key: string, owned: boolean): Card
	local t = (ExclusiveShopView.TEXTS :: any)[key]
	local price = Format.robux(robuxOf(config, key))
	local s: CardState = if owned
		then "owned"
		elseif onSale(ExclusiveShopView.productPurchase(config, key)) then "buy"
		else "offsale"
	return {
		key = `product:{key}`,
		kind = "product",
		id = key,
		title = t.title,
		icon = t.icon,
		priceText = price,
		state = s,
		tag = if owned then ExclusiveShopView.OWNED else price,
	}
end

local function passCard(shop: any, config: any, key: string): Card
	local t = (ExclusiveShopView.TEXTS :: any)[key]
	local price = Format.robux(robuxOf(config, key, true))
	local owned = type(shop.passes) == "table" and shop.passes[key] == true
	local s: CardState = if owned
		then "owned"
		elseif onSale(ExclusiveShopView.passPurchase(config, key)) then "buy"
		else "offsale"
	return {
		key = `pass:{key}`,
		kind = "pass",
		id = key,
		title = t.title,
		icon = t.icon,
		priceText = price,
		state = s,
		tag = if owned then ExclusiveShopView.OWNED else price,
	}
end

local function subscriptionCard(shop: any, config: any, key: string): Card
	local t = (ExclusiveShopView.TEXTS :: any)[key]
	local cat = catalogueOf(config) :: any
	local price = `{Format.robux(cat.subscriptions[key].robux)}/mo`
	local active = type(shop.subscriptions) == "table" and shop.subscriptions[key] == true
	local s: CardState = if active
		then "owned"
		elseif onSale(ExclusiveShopView.subscriptionPurchase(config, key)) then "buy"
		else "offsale"
	return {
		key = `sub:{key}`,
		kind = "subscription",
		id = key,
		title = t.title,
		icon = t.icon,
		priceText = price,
		state = s,
		tag = if active then ExclusiveShopView.SUBSCRIBED else price,
	}
end

local function infoCard(key: string): Card
	local t = (ExclusiveShopView.TEXTS :: any)[key]
	return {
		key = `info:{key}`,
		kind = "info",
		id = key,
		title = t.title,
		icon = t.icon,
		priceText = "",
		state = "info",
		tag = t.tag,
	}
end

-- The tab keys in their order (Config.EXCLUSIVE_SHOP.tabs); none without State.exclusiveShop.
function ExclusiveShopView.tabs(state: any, config: any): { string }
	local cat = catalogueOf(config)
	if shopOf(state) == nil or cat == nil then
		return {}
	end
	return table.clone(cat.tabs)
end

-- The pass keys in their Perks tab order (Config.EXCLUSIVE_SHOP.passes[key].order, then by key).
local function passKeys(config: any): { string }
	local passes = (catalogueOf(config) :: any).passes
	local keys = {}
	for key in passes do
		table.insert(keys, key)
	end
	table.sort(keys, function(a: string, b: string): boolean
		local oa, ob = passes[a].order or math.huge, passes[b].order or math.huge
		if oa ~= ob then
			return oa < ob
		end
		return a < b
	end)
	return keys
end

local function subscriptionKeys(config: any): { string }
	local keys = {}
	for key in (catalogueOf(config) :: any).subscriptions or {} do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

-- The cards of `tab` for `state`, in display order. Empty without State.exclusiveShop.
function ExclusiveShopView.cards(tab: string, state: any, config: any): { Card }
	local shop = shopOf(state)
	local out: { Card } = {}
	if shop == nil or catalogueOf(config) == nil then
		return out
	end
	if tab == "Featured" then
		if shop.starterClaimed ~= true then
			table.insert(out, productCard(config, "StarterBundle", false))
		end
		for _, id in (if type(shop.featured) == "table" then shop.featured else {}) :: { any } do
			if type(id) == "string" and (catalogueOf(config) :: any).products[`Seat_{id}`] then
				table.insert(out, seatCard(state, shop, config, id))
			end
		end
	elseif tab == "Clouds" then
		for _, id in exclusiveSeats(config) do
			table.insert(out, seatCard(state, shop, config, id))
		end
	elseif tab == "Style" then
		for _, kind in { "trail", "batSkin" } :: { "trail" | "batSkin" } do
			for _, def in styleDefs(config, kind) do
				if (catalogueOf(config) :: any).products[`{STYLE_KINDS[kind].prefix}{def.id}`] then
					table.insert(out, styleCard(shop, config, kind, def))
				end
			end
		end
	elseif tab == "Perks" then
		for _, key in passKeys(config) do
			if shop.paidRandomAllowed == true or not paidRandomPass(config, key) then
				table.insert(out, passCard(shop, config, key))
			end
		end
		for _, key in subscriptionKeys(config) do
			table.insert(out, subscriptionCard(shop, config, key))
		end
	elseif tab == "Boosts" then
		local products = (catalogueOf(config) :: any).products
		for _, boost in BOOSTS do
			if products[boost.key] and (shop.paidRandomAllowed == true or not boost.random) then
				table.insert(out, productCard(config, boost.key, false))
			end
		end
		for _, key in INFO_KEYS do
			table.insert(out, infoCard(key))
		end
	end
	return out
end

-- "3/16 owned" over the Clouds.
function ExclusiveShopView.ownedSummary(state: any, config: any): string
	local shop = shopOf(state)
	local seats = exclusiveSeats(config)
	local n = 0
	for _, id in seats do
		if shop and type(shop.owned) == "table" and shop.owned[id] == true then
			n += 1
		end
	end
	return `{n}/{#seats} owned`
end

-- "52%" / "0.4%" / "0.004%": enough digits that a rare tier never reads 0%.
function ExclusiveShopView.percent(share: number): string
	local p = share * 100
	local text = if p >= 10
		then string.format("%.0f", p)
		elseif p >= 1 then string.format("%.1f", p)
		elseif p >= 0.1 then string.format("%.2f", p)
		else string.format("%.3f", p)
	text = string.gsub(text, "(%.%d-)0+$", "%1")
	text = string.gsub(text, "%.$", "")
	return `{text}%`
end

-- The fountain's rarity odds without and with a Luck Potion (Config.RARITIES weights; tier >= 3 weights
-- x LUCK_POTION_MULT, as Genome.rollTier does). Each column adds up to 100 %.
function ExclusiveShopView.potionOdds(config: any): { OddsRow }
	local mult = config.LUCK_POTION_MULT or 1
	local base, boosted = 0, 0
	for _, r in config.RARITIES do
		base += r.weight
		boosted += if r.tier >= 3 then r.weight * mult else r.weight
	end
	local out: { OddsRow } = {}
	for _, r in config.RARITIES do
		local b = if r.tier >= 3 then r.weight * mult else r.weight
		table.insert(out, {
			name = r.name,
			tier = r.tier,
			base = ExclusiveShopView.percent(r.weight / base),
			boosted = ExclusiveShopView.percent(b / boosted),
		})
	end
	return out
end

-- The Lucky Charm odds without and with the Lucky Charm+ pass (State.exclusiveShop.luck: this player's chance).
function ExclusiveShopView.luckOdds(state: any): ({ OddsRow }, { string })
	local shop = shopOf(state)
	local luck = shop and shop.luck
	local base = if type(luck) == "table" and type(luck.base) == "number" then luck.base else 0
	local bonus = if type(luck) == "table" and type(luck.bonus) == "number" then luck.bonus else 0
	local rows = {
		{
			name = "Lucky Charm",
			tier = 0,
			base = ExclusiveShopView.percent(base),
			boosted = ExclusiveShopView.percent(base + bonus),
		},
	}
	local effect = {
		`Your chance now: {ExclusiveShopView.percent(base)}`,
		`With Lucky Charm+: {ExclusiveShopView.percent(base + bonus)}`,
		ExclusiveShopView.LUCK_NOTE,
	}
	return rows, effect
end

-- The potion's effect in numbers.
function ExclusiveShopView.potionEffect(config: any): { string }
	local rare = config.RARITIES[3]
	return {
		`{if rare then rare.name else "Rare"} and rarer: x{config.LUCK_POTION_MULT} chance`,
		`+{config.LUCK_POTION_SECONDS // 60} min for everyone on the server`,
		`Up to {config.LUCK_POTION_MAX_SECONDS // 60} min queued`,
	}
end

-- The credit kind a Boosts card spends instead of buying ("rain", "boss", "totem"), when State holds one.
function boostCredit(state: any, card: Card): string?
	if card.kind ~= "product" then
		return nil
	end
	for _, boost in BOOSTS do
		if boost.key == card.id and boost.credit then
			local shop = shopOf(state)
			local n = shop and type(shop.credits) == "table" and shop.credits[boost.credit]
			return if type(n) == "number" and n > 0 then boost.credit else nil
		end
	end
	return nil
end

local function findCard(key: string, state: any, config: any): Card?
	local cat = catalogueOf(config)
	for _, tab in (if cat then cat.tabs else {}) :: { string } do
		for _, card in ExclusiveShopView.cards(tab, state, config) do
			if card.key == key then
				return card
			end
		end
	end
	return nil
end

-- The detail pane of card `key`, or nil when no tab has it (any more).
function ExclusiveShopView.detail(key: string, state: any, config: any): Detail?
	local card = findCard(key, state, config)
	if card == nil then
		return nil
	end
	local purchase: Purchase? = nil
	local text = ""
	local style = (STYLE_KINDS :: any)[card.kind]
	if card.kind == "seat" then
		purchase = ExclusiveShopView.productPurchase(config, `Seat_{card.id}`)
		text = ExclusiveShopView.SEAT_TEXT
	elseif style then
		purchase = ExclusiveShopView.productPurchase(config, `{style.prefix}{card.id}`)
		text = style.text
	elseif card.kind == "product" then
		purchase = ExclusiveShopView.productPurchase(config, card.id)
		text = (ExclusiveShopView.TEXTS :: any)[card.id].text
	elseif card.kind == "pass" then
		purchase = ExclusiveShopView.passPurchase(config, card.id)
		text = (ExclusiveShopView.TEXTS :: any)[card.id].text
	elseif card.kind == "subscription" then
		purchase = ExclusiveShopView.subscriptionPurchase(config, card.id)
		text = (ExclusiveShopView.TEXTS :: any)[card.id].text
	else
		text = (ExclusiveShopView.TEXTS :: any)[card.id].text
	end
	local action: Action
	if card.state == "equipped" then
		action = { kind = "well", text = ExclusiveShopView.EQUIPPED }
	elseif card.state == "owned" and card.kind == "pass" and card.id == "VIP" then
		local shop = shopOf(state) :: any
		action = if shop.vipPotion == true and shop.paidRandomAllowed == true
			then {
				kind = "equip",
				text = ExclusiveShopView.VIP_POTION,
				equip = { request = "ClaimPerk", arg = "vipPotion" },
			}
			elseif shop.paidRandomAllowed == true then { kind = "well", text = ExclusiveShopView.VIP_POTION_USED }
			else { kind = "well", text = ExclusiveShopView.OWNED }
	elseif card.state == "owned" and card.kind == "subscription" then
		action = { kind = "well", text = ExclusiveShopView.SUBSCRIBED }
	elseif card.state == "owned" then
		local equip: Equip? = if card.kind == "seat"
			then { request = "EquipPetSeat", arg = card.id }
			elseif style then { request = style.request, arg = card.id }
			else nil
		action = if equip
			then { kind = "equip", text = ExclusiveShopView.EQUIP, equip = equip }
			else { kind = "well", text = ExclusiveShopView.OWNED }
	elseif card.state == "info" then
		action = { kind = "well", text = (ExclusiveShopView.TEXTS :: any)[card.id].where }
	elseif card.state == "buy" and boostCredit(state, card) then
		action = {
			kind = "equip",
			text = ExclusiveShopView.USE_CREDIT,
			equip = { request = "UseCredit", arg = boostCredit(state, card) :: string },
		}
	elseif card.state == "buy" then
		action = { kind = "buy", text = `Buy · {card.priceText}`, purchase = purchase }
	else
		action = { kind = "offsale", text = ExclusiveShopView.OFF_SALE }
	end
	local potion = card.id == "ServerLuckPotion"
	local luckRows, luckEffect = nil, nil
	if card.kind == "pass" and paidRandomPass(config, card.id) then
		luckRows, luckEffect = ExclusiveShopView.luckOdds(state)
	end
	local itemKey = ExclusiveShopView.itemKeyOf(card.key)
	local worn = style ~= nil and card.state == "equipped"
	return {
		key = card.key,
		kind = card.kind,
		id = card.id,
		title = card.title,
		icon = card.icon,
		text = text,
		priceText = card.priceText,
		state = card.state,
		exclusive = card.kind == "seat",
		action = action,
		odds = if potion then ExclusiveShopView.potionOdds(config) else luckRows,
		effect = if potion then ExclusiveShopView.potionEffect(config) else luckEffect,
		unequip = if worn then { request = style.request, arg = "" } else nil,
		unequipText = if worn then style.unequip else nil,
		gift = if itemKey then ExclusiveShopView.gift(itemKey, state, config) else nil,
	}
end

-- The cosmetic product key of a card ("seat:ufo" -> "Seat_ufo", "trail:hearts" -> "Trail_hearts"); nil for
-- anything that is not giftable (passes, boosts, the bundle, info cards).
function ExclusiveShopView.itemKeyOf(cardKey: string): string?
	local kind, id = string.match(cardKey, "^(%a+):(.+)$")
	if kind == "seat" then
		return `Seat_{id}`
	elseif kind == "trail" then
		return `Trail_{id}`
	elseif kind == "batSkin" then
		return `BatSkin_{id}`
	end
	return nil
end

-- True while State holds an unsent gift credit for `itemKey`.
function ExclusiveShopView.hasGiftCredit(state: any, itemKey: string): boolean
	local shop = shopOf(state)
	local list = shop and shop.giftCredits
	return type(list) == "table" and table.find(list, itemKey) ~= nil
end

-- The Gift button of cosmetic `itemKey`: "Send gift" with an unsent credit, "Gift · R$99" when Gift_<key> is on
-- sale, else a disabled "Gift not on sale". nil for a key that is not giftable or with the shop off.
function ExclusiveShopView.gift(itemKey: string, state: any, config: any): Gift?
	local cat = catalogueOf(config)
	if shopOf(state) == nil or cat == nil or cat.products[`Gift_{itemKey}`] == nil then
		return nil
	end
	if ExclusiveShopView.hasGiftCredit(state, itemKey) then
		return { mode = "send", text = ExclusiveShopView.SEND_GIFT, itemKey = itemKey }
	end
	local purchase = ExclusiveShopView.productPurchase(config, `Gift_{itemKey}`)
	if not onSale(purchase) then
		return { mode = "offsale", text = ExclusiveShopView.GIFT_OFF_SALE, itemKey = itemKey }
	end
	return {
		mode = "buy",
		text = `{ExclusiveShopView.GIFT} · {Format.robux(robuxOf(config, `Gift_{itemKey}`))}`,
		itemKey = itemKey,
		purchase = purchase,
	}
end

-- The players the gift picker offers: everyone in `players` but `me`, friends first, then by name.
function ExclusiveShopView.giftTargets(players: { GiftTarget }, me: number?): { GiftTarget }
	local out: { GiftTarget } = {}
	for _, p in players do
		if p.userId ~= me then
			table.insert(out, p)
		end
	end
	table.sort(out, function(a: GiftTarget, b: GiftTarget): boolean
		if a.friend ~= b.friend then
			return a.friend
		end
		local an, bn = string.lower(a.name), string.lower(b.name)
		if an ~= bn then
			return an < bn
		end
		return a.userId < b.userId
	end)
	return out
end

-- The card to show first on `tab`: `want` when the tab has it, else the first.
function ExclusiveShopView.firstSelected(cards: { Card }, want: string?): string?
	for _, card in cards do
		if card.key == want then
			return want
		end
	end
	return if cards[1] then cards[1].key else nil
end

-- The tab a card key lives on ("seat:leaf" is on Clouds, a pass on Perks, ...): the open path from Skins.
function ExclusiveShopView.tabOf(key: string): string
	if string.sub(key, 1, 5) == "seat:" then
		return "Clouds"
	elseif string.sub(key, 1, 5) == "pass:" or string.sub(key, 1, 4) == "sub:" then
		return "Perks"
	elseif string.sub(key, 1, 6) == "trail:" or string.sub(key, 1, 8) == "batSkin:" then
		return "Style"
	elseif key == "product:StarterBundle" then
		return "Featured"
	end
	return "Boosts"
end

local function quickBuy(config: any, key: string, verb: string, credit: boolean): QuickBuy
	if credit then
		return { mode = "credit", text = ExclusiveShopView.USE_CREDIT, key = key }
	end
	local purchase = ExclusiveShopView.productPurchase(config, key)
	if not onSale(purchase) then
		return { mode = "offsale", text = ExclusiveShopView.OFF_SALE, key = key }
	end
	return { mode = "buy", text = `{verb} · {Format.robux(robuxOf(config, key))}`, key = key, purchase = purchase }
end

-- FinishBrew_<i> for a brew with `secondsLeft` to go: the first bracket it fits (finishBrewBrackets).
function ExclusiveShopView.finishBrewKey(secondsLeft: number, config: any): string
	local brackets = (catalogueOf(config) :: any).finishBrewBrackets
	for i, limit in brackets do
		if secondsLeft <= limit then
			return `FinishBrew_{i}`
		end
	end
	return `FinishBrew_{#brackets}`
end

local function credits(shop: any, kind: string): number
	local c = if type(shop.credits) == "table" then shop.credits[kind] else nil
	return if type(c) == "number" then c else 0
end

-- The Merge vat's quick-buy while it brews: "Finish now · R$35" (the bracket of the time left), "Use credit"
-- with a brew credit and `canUseCredit` (Request UseCredit exists), nil when not brewing.
function ExclusiveShopView.brewQuickBuy(state: any, now: number, config: any, canUseCredit: boolean?): QuickBuy?
	local shop = shopOf(state)
	local vat = if type(state) == "table" then state.vat else nil
	local endsAt = if type(vat) == "table" and type(vat.endsAt) == "number" then vat.endsAt else nil
	if shop == nil or endsAt == nil or now >= endsAt then
		return nil
	end
	local key = ExclusiveShopView.finishBrewKey(endsAt - now, config)
	return quickBuy(config, key, "Finish now", canUseCredit == true and credits(shop, "brew") > 0)
end

-- The egg `slimeId`'s "Hatch now" while it incubates (State.slimes[i].slime.egg, hatchAt still ahead), nil
-- when it is ready, not an egg, not this player's.
function ExclusiveShopView.hatchQuickBuy(
	state: any,
	slimeId: string,
	now: number,
	config: any,
	canUseCredit: boolean?
): QuickBuy?
	local shop = shopOf(state)
	if shop == nil or type(state.slimes) ~= "table" then
		return nil
	end
	for _, view in state.slimes do
		local slime = if type(view) == "table" then view.slime else nil
		if type(slime) == "table" and slime.id == slimeId then
			local egg = slime.egg
			if type(egg) ~= "table" or type(egg.hatchAt) ~= "number" or egg.hatchAt <= now then
				return nil
			end
			local key = `HatchNow_{egg.kind}`
			if (catalogueOf(config) :: any).products[key] == nil then
				return nil
			end
			return quickBuy(config, key, "Hatch now", canUseCredit == true and credits(shop, "hatch") > 0)
		end
	end
	return nil
end

-- The Welcome back card's "Double it · R$49" while the last payout can still be doubled.
function ExclusiveShopView.doubleQuickBuy(state: any, config: any): QuickBuy?
	local shop = shopOf(state)
	local double = shop and shop.offlineDouble
	if
		type(double) ~= "table"
		or double.available ~= true
		or not (type(double.cash) == "number" and double.cash > 0)
	then
		return nil
	end
	return quickBuy(config, "DoubleOffline", "Double it", false)
end

-- The Daily reward's "Keep my streak · R$25" while State says the streak broke (State.exclusiveShop.streakKeepable).
function ExclusiveShopView.streakQuickBuy(state: any, config: any): QuickBuy?
	local shop = shopOf(state)
	if shop == nil or shop.streakKeepable ~= true then
		return nil
	end
	return quickBuy(config, "KeepStreak", "Keep my streak", false)
end

-- A slime's "Growth snack · R$19" (or "Use credit" with a snack credit and `canUseCredit`): own slimes on a pad
-- that are not eggs and not fully grown.
function ExclusiveShopView.snackQuickBuy(state: any, slimeId: string, config: any, canUseCredit: boolean?): QuickBuy?
	local shop = shopOf(state)
	if shop == nil or type(state.slimes) ~= "table" or (catalogueOf(config) :: any).products.GrowthSnack == nil then
		return nil
	end
	for _, view in state.slimes do
		local slime = if type(view) == "table" then view.slime else nil
		if type(slime) == "table" and slime.id == slimeId then
			if slime.egg ~= nil or (type(slime.growth) == "number" and slime.growth >= 1) then
				return nil
			end
			return quickBuy(config, "GrowthSnack", "Growth snack", canUseCredit == true and credits(shop, "snack") > 0)
		end
	end
	return nil
end

-- What the client knows about a base door (Plot_<i> attributes) for the lock break quick-buy.
export type Door = {
	index: number, -- PlotIndex
	owner: number?, -- OwnerUserId; 0 / nil = a free plot
	locked: boolean, -- Locked
	lockUntil: number?, -- LockUntil (server time); when set, the lock ends then
	guests: string?, -- Guests: ",<id>,<id>," the locked door already lets through
}

-- The active lock break (State.exclusiveShop.lockBreak) while it runs: the plot and the seconds left.
function ExclusiveShopView.lockBreakLeft(state: any, now: number): (number?, number)
	local shop = shopOf(state)
	local pass = shop and shop.lockBreak
	if type(pass) ~= "table" or type(pass.plot) ~= "number" or type(pass.untilTime) ~= "number" then
		return nil, 0
	end
	local left = pass.untilTime - now
	if left <= 0 then
		return nil, 0
	end
	return pass.plot, left
end

-- "Open locked door · R$499" (or "Use lock break" with a saved lock break and `canUseCredit`) on someone else's
-- locked base door; nil on your own or a free base, an open door, a door that already lets you in (a friend guest,
-- your running lock break), without AimLockBreak (`canAim`) or with the shop off. The server still decides.
function ExclusiveShopView.lockBreakQuickBuy(
	state: any,
	door: Door,
	me: number,
	now: number,
	config: any,
	canAim: boolean?,
	canUseCredit: boolean?
): QuickBuy?
	local shop = shopOf(state)
	if shop == nil or catalogueOf(config) == nil or (catalogueOf(config) :: any).products.LockBreak == nil then
		return nil
	end
	if type(door.owner) ~= "number" or door.owner == 0 or door.owner == me then
		return nil
	end
	if door.locked ~= true or (type(door.lockUntil) == "number" and door.lockUntil <= now) then
		return nil
	end
	if type(door.guests) == "string" and string.find(door.guests, `,{me},`, 1, true) then
		return nil
	end
	if ExclusiveShopView.lockBreakLeft(state, now) == door.index then
		return nil
	end
	local saved = if type(shop.lockBreakCredits) == "number" then shop.lockBreakCredits else 0
	if saved > 0 and canUseCredit == true then
		return { mode = "credit", text = ExclusiveShopView.USE_LOCK_BREAK, key = "LockBreak" }
	end
	if canAim ~= true then
		return nil
	end
	return quickBuy(config, "LockBreak", ExclusiveShopView.OPEN_LOCKED_DOOR, false)
end

-- The Item shop's Luck Potion row: "Buy for the server · R$79", nil where paid random items are restricted.
function ExclusiveShopView.potionQuickBuy(state: any, config: any): QuickBuy?
	local shop = shopOf(state)
	if shop == nil or shop.paidRandomAllowed ~= true then
		return nil
	end
	return quickBuy(config, "ServerLuckPotion", "Buy for the server", false)
end

return table.freeze(ExclusiveShopView)
