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
local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Seasons = if Shared then require(Shared.Seasons) else require("../shared/Seasons")
local Text = if script then require(script.Parent.Text) else require("./Text")

local ExclusiveShopView = {}

local boostCredit: (state: any, card: any) -> string?

-- `id`: the Developer Product / Game Pass id; a subscription sells by `subscriptionId` ("EXP-...") and keeps id 0.
export type Purchase = { kind: "product" | "pass" | "subscription", id: number, subscriptionId: string? }

export type CardState = "buy" | "offsale" | "owned" | "equipped" | "info"

export type Kind =
	"seat"
	| "trail"
	| "batSkin"
	| "lockStyle"
	| "hat"
	| "plotSkin"
	| "plotBase"
	| "product"
	| "pass"
	| "subscription"
	| "info"

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

-- Request(request, table.unpack(args or { arg })): EquipPetSeat / EquipTrail / EquipBatSkin / EquipStyle / ClaimPerk ...
export type Equip = { request: string, arg: string, args: { any }? }

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

-- Strings keys (Strings/Shop), drawn with Text.t. The functions below return text in the player's language.
ExclusiveShopView.TITLE = "shop.exclusive.title"
ExclusiveShopView.OFF_SALE = "shop.exclusive.off_sale"
ExclusiveShopView.OWNED = "shop.exclusive.owned"
ExclusiveShopView.EQUIP = "shop.exclusive.equip"
ExclusiveShopView.EQUIPPED = "shop.exclusive.equipped"
ExclusiveShopView.EXCLUSIVE = "shop.exclusive.exclusive"
ExclusiveShopView.WAITING = "shop.exclusive.waiting"
ExclusiveShopView.BOUGHT = "shop.exclusive.bought"
ExclusiveShopView.BOUGHT_SEAT = "shop.exclusive.bought_seat"
ExclusiveShopView.USE_CREDIT = "shop.exclusive.use_credit"
ExclusiveShopView.DETAILS = "shop.exclusive.details"
ExclusiveShopView.HIDE_DETAILS = "shop.exclusive.hide_details"
ExclusiveShopView.EMPTY = "shop.exclusive.empty"
ExclusiveShopView.EMPTY_TAB = "shop.exclusive.empty_tab"
ExclusiveShopView.OPEN_LOCKED_DOOR = "shop.exclusive.open_locked_door"
ExclusiveShopView.USE_LOCK_BREAK = "shop.exclusive.use_lock_break"
ExclusiveShopView.LOCK_BREAK_REFUSED = "shop.exclusive.lock_break_refused"
ExclusiveShopView.GIFT = "shop.exclusive.gift"
ExclusiveShopView.SEND_GIFT = "shop.exclusive.send_gift"
ExclusiveShopView.GIFT_OFF_SALE = "shop.exclusive.gift_off_sale"
ExclusiveShopView.GIFT_HINT = "shop.exclusive.gift_hint"
ExclusiveShopView.GIFT_EMPTY = "shop.exclusive.gift_empty"
ExclusiveShopView.GIFT_REFUSED = "shop.exclusive.gift_refused"
ExclusiveShopView.BACK = "shop.exclusive.back"
ExclusiveShopView.FRIEND = "shop.exclusive.friend"
ExclusiveShopView.UNEQUIP_TRAIL = "shop.exclusive.unequip_trail"
ExclusiveShopView.DEFAULT_BAT = "shop.exclusive.default_bat"
ExclusiveShopView.LOCK_TEXT = "shop.exclusive.lock_text"
ExclusiveShopView.HAT_TEXT = "shop.exclusive.hat_text"
ExclusiveShopView.SKIN_TEXT = "shop.exclusive.skin_text"
ExclusiveShopView.BASE_TEXT = "shop.exclusive.base_text"
ExclusiveShopView.UNEQUIP_STYLE = "shop.exclusive.unequip_style"
ExclusiveShopView.TRAIL_TEXT = "shop.exclusive.trail_text"
ExclusiveShopView.BAT_TEXT = "shop.exclusive.bat_text"
ExclusiveShopView.VIP_POTION = "shop.exclusive.vip_potion"
ExclusiveShopView.VIP_POTION_USED = "shop.exclusive.vip_potion_used"
ExclusiveShopView.SUBSCRIBED = "shop.exclusive.subscribed"
ExclusiveShopView.LUCK_NOTE = "shop.exclusive.luck_note"
ExclusiveShopView.ODDS_NOTE = "shop.exclusive.odds_note"

-- Shop text keys per product / pass key (Config.EXCLUSIVE_SHOP keys).
ExclusiveShopView.TEXTS = table.freeze({
	StarterBundle = table.freeze({
		title = "shop.exclusive.starter_bundle.title",
		icon = "Gift",
		text = "shop.exclusive.starter_bundle.text",
	}),
	ServerLuckPotion = table.freeze({
		title = "shop.exclusive.server_luck_potion.title",
		icon = "Consumable_LuckPotion",
		text = "shop.exclusive.server_luck_potion.text",
	}),
	Income2x = table.freeze({
		title = "shop.exclusive.income2x.title",
		icon = "Perk_income",
		text = "shop.exclusive.income2x.text",
	}),
	Offline2x = table.freeze({
		title = "shop.exclusive.offline2x.title",
		icon = "Upgrade_OfflineCap",
		text = "shop.exclusive.offline2x.text",
	}),
	VIP = table.freeze({
		title = "shop.exclusive.vip.title",
		icon = "Boost_Mvp",
		text = "shop.exclusive.vip.text",
	}),
	FastBrew = table.freeze({
		title = "shop.exclusive.fast_brew.title",
		icon = "Upgrade_QuickBrew",
		text = "shop.exclusive.fast_brew.text",
	}),
	WarmNest = table.freeze({
		title = "shop.exclusive.warm_nest.title",
		icon = "MysteryEgg",
		text = "shop.exclusive.warm_nest.text",
	}),
	LuckyCharmPlus = table.freeze({
		title = "shop.exclusive.lucky_charm_plus.title",
		icon = "Upgrade_Luck",
		text = "shop.exclusive.lucky_charm_plus.text",
	}),
	ThiefRadar = table.freeze({
		title = "shop.exclusive.thief_radar.title",
		icon = "Goal_Steal",
		text = "shop.exclusive.thief_radar.text",
	}),
	AutoCollect = table.freeze({
		title = "shop.exclusive.auto_collect.title",
		icon = "Cash",
		text = "shop.exclusive.auto_collect.text",
	}),
	SlimeClub = table.freeze({
		title = "shop.exclusive.slime_club.title",
		icon = "Daily",
		text = "shop.exclusive.slime_club.text",
	}),
	SlimeRain = table.freeze({
		title = "shop.exclusive.slime_rain.title",
		icon = "Event_rain",
		text = "shop.exclusive.slime_rain.text",
	}),
	SummonBoss = table.freeze({
		title = "shop.exclusive.summon_boss.title",
		icon = "Slap",
		text = "shop.exclusive.summon_boss.text",
	}),
	WeatherTotem = table.freeze({
		title = "shop.exclusive.weather_totem.title",
		icon = "Consumable_WeatherTotem",
		text = "shop.exclusive.weather_totem.text",
	}),
	IncomeBoost15 = table.freeze({
		title = "shop.exclusive.income_boost15.title",
		icon = "Boost_Code",
		text = "shop.exclusive.income_boost15.text",
	}),
	IncomeBoost60 = table.freeze({
		title = "shop.exclusive.income_boost60.title",
		icon = "Boost_Code",
		text = "shop.exclusive.income_boost60.text",
	}),
	KeepStreak = table.freeze({
		title = "shop.exclusive.keep_streak.title",
		icon = "Daily",
		text = "shop.exclusive.keep_streak.text",
		where = "shop.exclusive.keep_streak.where",
		tag = "shop.exclusive.keep_streak.tag",
	}),
	GrowthSnack = table.freeze({
		title = "shop.exclusive.growth_snack.title",
		icon = "Pet",
		text = "shop.exclusive.growth_snack.text",
		where = "shop.exclusive.growth_snack.where",
		tag = "shop.exclusive.growth_snack.tag",
	}),
	BoutiqueBundle = table.freeze({
		title = "shop.exclusive.boutique_bundle.title",
		icon = "Gift",
		text = "shop.exclusive.boutique_bundle.text",
	}),
	SkyBundle = table.freeze({
		title = "shop.exclusive.sky_bundle.title",
		icon = "Gift",
		text = "shop.exclusive.sky_bundle.text",
	}),
	FinishBrew = table.freeze({
		title = "shop.exclusive.finish_brew.title",
		icon = "Upgrade_QuickBrew",
		text = "shop.exclusive.finish_brew.text",
		where = "shop.exclusive.finish_brew.where",
		tag = "shop.exclusive.finish_brew.tag",
	}),
	HatchNow = table.freeze({
		title = "shop.exclusive.hatch_now.title",
		icon = "MysteryEgg",
		text = "shop.exclusive.hatch_now.text",
		where = "shop.exclusive.hatch_now.where",
		tag = "shop.exclusive.hatch_now.tag",
	}),
	DoubleOffline = table.freeze({
		title = "shop.exclusive.double_offline.title",
		icon = "Cash",
		text = "shop.exclusive.double_offline.text",
		where = "shop.exclusive.double_offline.where",
		tag = "shop.exclusive.double_offline.tag",
	}),
})

ExclusiveShopView.SEAT_TEXT = "shop.exclusive.seat_text"

local INFO_KEYS = { "FinishBrew", "HatchNow", "DoubleOffline", "KeepStreak", "GrowthSnack" }

-- Boosts tab products, in order. `random`: changes the odds (hidden where paid random items are restricted).
-- `credit`: the State.exclusiveShop.credits kind a refused one is kept as (spent with UseCredit).
type Boost = { key: string, random: boolean, credit: string? }
local BOOSTS: { Boost } = table.freeze({
	table.freeze({ key = "ServerLuckPotion", random = true, credit = nil }),
	table.freeze({ key = "SlimeRain", random = true, credit = "rain" }),
	table.freeze({ key = "WeatherTotem", random = true, credit = "totem" }),
	table.freeze({ key = "SummonBoss", random = false, credit = "boss" }),
	table.freeze({ key = "IncomeBoost15", random = false, credit = nil }),
	table.freeze({ key = "IncomeBoost60", random = false, credit = nil }),
} :: { Boost })
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

-- A cosmetic sold outside the shop's cards (the Skins menu's rows): its price, the Buy text and, while on sale,
-- what Roblox's prompt sells. Nil without such a product.
export type Offer = { price: string, text: string, purchase: Purchase? }

function ExclusiveShopView.offer(config: any, key: string): Offer?
	local purchase = ExclusiveShopView.productPurchase(config, key)
	if purchase == nil then
		return nil
	end
	local price = Format.robux(robuxOf(config, key))
	return {
		price = price,
		text = Text.t("shop.exclusive.buy_price", { price = price }),
		purchase = if onSale(purchase) then purchase else nil,
	}
end

-- True for a pass that changes a roll (Lucky Charm+): hidden where paid random items are restricted.
local function paidRandomPass(config: any, key: string): boolean
	local cat = catalogueOf(config)
	local def = cat and cat.passes[key]
	return def ~= nil and def.luckBonus ~= nil
end

-- A data name in the player's language, sentence case in English (as the Skins menu shows it).
local function caseName(kind: string, id: string, english: string): string
	local name = Text.data(kind, id, "name", english)
	return if string.sub(Text.locale(), 1, 2) == "en" then Format.sentenceCase(name) else name
end

-- The Exclusive seat `id`'s name from Config.PET_SEATS.
function ExclusiveShopView.seatName(config: any, id: string): string
	for _, seat in config.PET_SEATS or {} do
		if seat.id == id then
			return caseName("petSeat", id, seat.name)
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
			then Text.t(ExclusiveShopView.EQUIPPED)
			elseif s == "owned" then Text.t(ExclusiveShopView.OWNED)
			else price,
	}
end

-- Config.EXCLUSIVE_SHOP.trails / batSkins / lockStyles / hats entries, or the Exclusive plot skins / bases.
local function styleDefs(config: any, kind: string): { any }
	local cat = catalogueOf(config)
	if kind == "plotSkin" or kind == "plotBase" then
		local out = {}
		for _, def in (if kind == "plotSkin" then config.PLOT_SKINS else config.PLOT_BASES) or {} do
			if def.exclusive then
				table.insert(out, def)
			end
		end
		return out
	end
	local field = if kind == "trail"
		then "trails"
		elseif kind == "batSkin" then "batSkins"
		elseif kind == "lockStyle" then "lockStyles"
		elseif kind == "hat" then "hats"
		else nil
	local list = cat and field and cat[field]
	return if type(list) == "table" then list else {}
end

-- Owned / worn of a style kind in State.exclusiveShop: trails and Bat skins have their own fields, the rest
-- live in `styles[kind]` / `worn[kind]` (a plot skin / base is worn as State.plotSkins' / plotBases' equipped one).
local function styleOwned(state: any, shop: any, kind: string, id: string): (boolean, boolean)
	if kind == "trail" then
		return type(shop.trails) == "table" and shop.trails[id] == true, shop.trail == id
	elseif kind == "batSkin" then
		return type(shop.batSkins) == "table" and shop.batSkins[id] == true, shop.batSkin == id
	end
	local set = type(shop.styles) == "table" and shop.styles[kind]
	local owned = type(set) == "table" and set[id] == true
	if kind == "plotSkin" or kind == "plotBase" then
		local views = if kind == "plotSkin" then state.plotSkins else state.plotBases
		local equipped = false
		for _, view in (if type(views) == "table" then views else {}) :: { any } do
			if type(view) == "table" and view.id == id and view.equipped == true then
				equipped = true
			end
		end
		return owned, equipped
	end
	return owned, type(shop.worn) == "table" and shop.worn[kind] == id
end

-- True while `productKey` may be shown for sale at `now` (State's serverNow): seasonal ones only in season.
local function inSeason(shop: any, productKey: string): boolean
	local season = Seasons.ofProduct(productKey)
	return season == nil or (type(shop.seasons) == "table" and shop.seasons[season] == true)
end

-- Per style kind: its product key prefix, the Strings data kind of its names (the Config table they live in),
-- and the keys of its pane text and its take-off button.
local STYLE_KINDS = table.freeze({
	lockStyle = table.freeze({
		prefix = "LockStyle_",
		data = "lockStyle",
		list = "lockStyles",
		style = true,
		text = ExclusiveShopView.LOCK_TEXT,
		unequip = ExclusiveShopView.UNEQUIP_STYLE,
	}),
	hat = table.freeze({
		prefix = "Hat_",
		data = "slimeHat",
		list = "hats",
		style = true,
		text = ExclusiveShopView.HAT_TEXT,
		unequip = ExclusiveShopView.UNEQUIP_STYLE,
	}),
	plotSkin = table.freeze({
		prefix = "Skin_",
		data = "plotSkin",
		style = true,
		text = ExclusiveShopView.SKIN_TEXT,
		unequip = ExclusiveShopView.UNEQUIP_STYLE,
	}),
	plotBase = table.freeze({
		prefix = "Base_",
		data = "plotBase",
		style = true,
		text = ExclusiveShopView.BASE_TEXT,
		unequip = ExclusiveShopView.UNEQUIP_STYLE,
	}),
	trail = table.freeze({
		prefix = "Trail_",
		data = "carryTrail",
		owned = "trails",
		worn = "trail",
		request = "EquipTrail",
		text = ExclusiveShopView.TRAIL_TEXT,
		unequip = ExclusiveShopView.UNEQUIP_TRAIL,
	}),
	batSkin = table.freeze({
		prefix = "BatSkin_",
		data = "batSkin",
		owned = "batSkins",
		worn = "batSkin",
		request = "EquipBatSkin",
		text = ExclusiveShopView.BAT_TEXT,
		unequip = ExclusiveShopView.DEFAULT_BAT,
	}),
})

-- The card of a style `def` of `kind` (trail, Bat skin, lock style, hat, Exclusive plot skin or base).
local function styleCard(state: any, shop: any, config: any, kind: string, def: any): Card
	local k = (STYLE_KINDS :: any)[kind]
	local key = `{k.prefix}{def.id}`
	local price = Format.robux(robuxOf(config, key))
	local owned, worn = styleOwned(state, shop, kind, def.id)
	local s: CardState = if owned and worn
		then "equipped"
		elseif owned then "owned"
		elseif onSale(ExclusiveShopView.productPurchase(config, key)) then "buy"
		else "offsale"
	return {
		key = `{kind}:{def.id}`,
		kind = kind :: Kind,
		id = def.id,
		title = Text.data(k.data, def.id, "name", def.name),
		icon = if kind == "plotSkin"
			then `PlotSkin_{def.id}`
			elseif kind == "plotBase" then `PlotBase_{def.id}`
			else key,
		priceText = price,
		state = s,
		tag = if s == "equipped"
			then Text.t(ExclusiveShopView.EQUIPPED)
			elseif s == "owned" then Text.t(ExclusiveShopView.OWNED)
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
		title = Text.t(t.title),
		icon = t.icon,
		priceText = price,
		state = s,
		tag = if owned then Text.t(ExclusiveShopView.OWNED) else price,
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
		title = Text.t(t.title),
		icon = t.icon,
		priceText = price,
		state = s,
		tag = if owned then Text.t(ExclusiveShopView.OWNED) else price,
	}
end

local function subscriptionCard(shop: any, config: any, key: string): Card
	local t = (ExclusiveShopView.TEXTS :: any)[key]
	local cat = catalogueOf(config) :: any
	-- Roblox's own price for this player (regional pricing: PurchasePrompt.subscriptionPrice), else Config's.
	local shown = type(shop.displayPrices) == "table" and shop.displayPrices[key]
	local price = Text.t("shop.exclusive.per_month", {
		price = if type(shown) == "string" and shown ~= "" then shown else Format.robux(cat.subscriptions[key].robux),
	})
	local active = type(shop.subscriptions) == "table" and shop.subscriptions[key] == true
	local s: CardState = if active
		then "owned"
		elseif onSale(ExclusiveShopView.subscriptionPurchase(config, key)) then "buy"
		else "offsale"
	return {
		key = `sub:{key}`,
		kind = "subscription",
		id = key,
		title = Text.t(t.title),
		icon = t.icon,
		priceText = price,
		state = s,
		tag = if active then Text.t(ExclusiveShopView.SUBSCRIBED) else price,
	}
end

local function infoCard(key: string): Card
	local t = (ExclusiveShopView.TEXTS :: any)[key]
	return {
		key = `info:{key}`,
		kind = "info",
		id = key,
		title = Text.t(t.title),
		icon = t.icon,
		priceText = "",
		state = "info",
		tag = Text.t(t.tag),
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
		for _, key in { "BoutiqueBundle", "SkyBundle" } do
			local def = (catalogueOf(config) :: any).products[key]
			if def and inSeason(shop, key) then
				table.insert(out, productCard(config, key, ExclusiveShopView.packOwned(shop, config, key)))
			end
		end
		for _, id in (if type(shop.featured) == "table" then shop.featured else {}) :: { any } do
			if type(id) == "string" and (catalogueOf(config) :: any).products[`Seat_{id}`] then
				table.insert(out, seatCard(state, shop, config, id))
			end
		end
	elseif tab == "Clouds" then
		for _, id in exclusiveSeats(config) do
			local card = seatCard(state, shop, config, id)
			if card.state == "owned" or card.state == "equipped" or inSeason(shop, `Seat_{id}`) then
				table.insert(out, card)
			end
		end
	elseif tab == "Style" then
		for _, kind in { "plotSkin", "plotBase", "lockStyle", "trail", "hat", "batSkin" } do
			for _, def in styleDefs(config, kind) do
				local key = `{(STYLE_KINDS :: any)[kind].prefix}{def.id}`
				if (catalogueOf(config) :: any).products[key] then
					local card = styleCard(state, shop, config, kind, def)
					if card.state == "owned" or card.state == "equipped" or inSeason(shop, key) then
						table.insert(out, card)
					end
				elseif def.daily and styleOwned(state, shop, kind, def.id) then
					-- A daily streak trail is never sold: it shows once owned, so it can be worn.
					table.insert(out, styleCard(state, shop, config, kind, def))
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

-- True when every item of bundle `key` is owned already (the bundle shows Owned).
function ExclusiveShopView.packOwned(shop: any, config: any, key: string): boolean
	local def = (catalogueOf(config) :: any).products[key]
	local items = def and def.grant.items
	if type(items) ~= "table" then
		return false
	end
	for _, item in items do
		local kind, id = string.match(item, "^(%a+)_(.+)$")
		local owned = false
		if kind == "Seat" then
			owned = type(shop.owned) == "table" and shop.owned[id] == true
		elseif kind == "Skin" then
			owned = type(shop.styles) == "table"
				and type(shop.styles.plotSkin) == "table"
				and shop.styles.plotSkin[id] == true
		end
		if not owned then
			return false
		end
	end
	return true
end

-- "3/16 owned" over the Clouds: the clouds the tab shows (seasonal ones only in season or when owned).
function ExclusiveShopView.ownedSummary(state: any, config: any): string
	local cards = ExclusiveShopView.cards("Clouds", state, config)
	local n = 0
	for _, card in cards do
		if card.state == "owned" or card.state == "equipped" then
			n += 1
		end
	end
	return Text.t("shop.exclusive.owned_summary", { owned = n, count = #cards })
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
			name = Text.data("rarity", r.name, "name", r.name),
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
			name = Text.data("upgrade", "Luck", "name", "Lucky Charm"),
			tier = 0,
			base = ExclusiveShopView.percent(base),
			boosted = ExclusiveShopView.percent(base + bonus),
		},
	}
	local effect = {
		Text.t("shop.exclusive.luck_now", { chance = ExclusiveShopView.percent(base) }),
		Text.t("shop.exclusive.luck_with", { chance = ExclusiveShopView.percent(base + bonus) }),
		Text.t(ExclusiveShopView.LUCK_NOTE),
	}
	return rows, effect
end

-- The potion's effect in numbers.
function ExclusiveShopView.potionEffect(config: any): { string }
	local rare = config.RARITIES[3]
	local rarity = if rare then rare.name else "Rare"
	return {
		Text.t("shop.exclusive.potion_rarer", {
			rarity = Text.data("rarity", rarity, "name", rarity),
			mult = config.LUCK_POTION_MULT,
		}),
		Text.t("shop.exclusive.potion_time", { minutes = config.LUCK_POTION_SECONDS // 60 }),
		Text.t("shop.exclusive.potion_queue", { minutes = config.LUCK_POTION_MAX_SECONDS // 60 }),
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
		text = Text.t(ExclusiveShopView.SEAT_TEXT)
	elseif style then
		purchase = ExclusiveShopView.productPurchase(config, `{style.prefix}{card.id}`)
		text = Text.t(style.text)
	elseif card.kind == "product" then
		purchase = ExclusiveShopView.productPurchase(config, card.id)
		text = Text.t((ExclusiveShopView.TEXTS :: any)[card.id].text)
	elseif card.kind == "pass" then
		purchase = ExclusiveShopView.passPurchase(config, card.id)
		text = Text.t((ExclusiveShopView.TEXTS :: any)[card.id].text)
	elseif card.kind == "subscription" then
		purchase = ExclusiveShopView.subscriptionPurchase(config, card.id)
		text = Text.t((ExclusiveShopView.TEXTS :: any)[card.id].text)
	else
		text = Text.t((ExclusiveShopView.TEXTS :: any)[card.id].text)
	end
	local action: Action
	if card.state == "equipped" then
		action = { kind = "well", text = Text.t(ExclusiveShopView.EQUIPPED) }
	elseif card.state == "owned" and card.kind == "pass" and card.id == "VIP" then
		local shop = shopOf(state) :: any
		action = if shop.vipPotion == true and shop.paidRandomAllowed == true
			then {
				kind = "equip",
				text = Text.t(ExclusiveShopView.VIP_POTION),
				equip = { request = "ClaimPerk", arg = "vipPotion" },
			}
			elseif shop.paidRandomAllowed == true then {
				kind = "well",
				text = Text.t(ExclusiveShopView.VIP_POTION_USED),
			}
			else { kind = "well", text = Text.t(ExclusiveShopView.OWNED) }
	elseif card.state == "owned" and card.kind == "subscription" then
		action = { kind = "well", text = Text.t(ExclusiveShopView.SUBSCRIBED) }
	elseif card.state == "owned" then
		local equip: Equip? = if card.kind == "seat"
			then { request = "EquipPetSeat", arg = card.id }
			elseif card.kind == "plotSkin" then { request = "EquipPlotSkin", arg = card.id }
			elseif card.kind == "plotBase" then { request = "EquipPlotBase", arg = card.id }
			elseif style and style.style then {
				request = "EquipStyle",
				arg = card.id,
				args = { card.kind :: any, card.id },
			}
			elseif style then { request = style.request, arg = card.id }
			else nil
		action = if equip
			then { kind = "equip", text = Text.t(ExclusiveShopView.EQUIP), equip = equip }
			else { kind = "well", text = Text.t(ExclusiveShopView.OWNED) }
	elseif card.state == "info" then
		action = { kind = "well", text = Text.t((ExclusiveShopView.TEXTS :: any)[card.id].where) }
	elseif card.state == "buy" and boostCredit(state, card) then
		action = {
			kind = "equip",
			text = Text.t(ExclusiveShopView.USE_CREDIT),
			equip = { request = "UseCredit", arg = boostCredit(state, card) :: string },
		}
	elseif card.state == "buy" then
		action = {
			kind = "buy",
			text = Text.t("shop.exclusive.buy_price", { price = card.priceText }),
			purchase = purchase,
		}
	else
		action = { kind = "offsale", text = Text.t(ExclusiveShopView.OFF_SALE) }
	end
	local potion = card.id == "ServerLuckPotion"
	local luckRows, luckEffect = nil, nil
	if card.kind == "pass" and paidRandomPass(config, card.id) then
		luckRows, luckEffect = ExclusiveShopView.luckOdds(state)
	end
	local itemKey = ExclusiveShopView.itemKeyOf(card.key)
	local worn = style ~= nil and card.state == "equipped" and card.kind ~= "plotSkin" and card.kind ~= "plotBase"
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
		unequip = if worn and style.style
			then { request = "EquipStyle", arg = "", args = { card.kind :: any, "" } }
			elseif worn then { request = style.request, arg = "" }
			else nil,
		unequipText = if worn then Text.t(style.unequip) else nil,
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
	elseif kind == "lockStyle" then
		return `LockStyle_{id}`
	elseif kind == "hat" then
		return `Hat_{id}`
	elseif kind == "plotSkin" then
		return `Skin_{id}`
	elseif kind == "plotBase" then
		return `Base_{id}`
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
		return { mode = "send", text = Text.t(ExclusiveShopView.SEND_GIFT), itemKey = itemKey }
	end
	local purchase = ExclusiveShopView.productPurchase(config, `Gift_{itemKey}`)
	if not onSale(purchase) then
		return { mode = "offsale", text = Text.t(ExclusiveShopView.GIFT_OFF_SALE), itemKey = itemKey }
	end
	return {
		mode = "buy",
		text = Text.t("shop.exclusive.gift_price", { price = Format.robux(robuxOf(config, `Gift_{itemKey}`)) }),
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
	elseif
		string.sub(key, 1, 9) == "plotSkin:"
		or string.sub(key, 1, 9) == "plotBase:"
		or string.sub(key, 1, 10) == "lockStyle:"
		or string.sub(key, 1, 6) == "trail:"
		or string.sub(key, 1, 8) == "batSkin:"
		or string.sub(key, 1, 4) == "hat:"
	then
		return "Style"
	elseif key == "product:StarterBundle" or key == "product:BoutiqueBundle" or key == "product:SkyBundle" then
		return "Featured"
	end
	return "Boosts"
end

-- `verb`: the Strings key of the button's action ("Finish now"); the price follows it ("Finish now · R$35").
local function quickBuy(config: any, key: string, verb: string, credit: boolean): QuickBuy
	if credit then
		return { mode = "credit", text = Text.t(ExclusiveShopView.USE_CREDIT), key = key }
	end
	local purchase = ExclusiveShopView.productPurchase(config, key)
	if not onSale(purchase) then
		return { mode = "offsale", text = Text.t(ExclusiveShopView.OFF_SALE), key = key }
	end
	return {
		mode = "buy",
		text = `{Text.t(verb)} · {Format.robux(robuxOf(config, key))}`,
		key = key,
		purchase = purchase,
	}
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
	return quickBuy(config, key, "shop.quick.finish_now", canUseCredit == true and credits(shop, "brew") > 0)
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
			return quickBuy(config, key, "shop.quick.hatch_now", canUseCredit == true and credits(shop, "hatch") > 0)
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
	return quickBuy(config, "DoubleOffline", "shop.quick.double_it", false)
end

-- The Daily reward's "Keep my streak · R$25" while State says the streak broke (State.exclusiveShop.streakKeepable).
function ExclusiveShopView.streakQuickBuy(state: any, config: any): QuickBuy?
	local shop = shopOf(state)
	if shop == nil or shop.streakKeepable ~= true then
		return nil
	end
	return quickBuy(config, "KeepStreak", "shop.quick.keep_streak", false)
end

-- A slime's "Growth snack · R$19" (or "Use credit" with a snack credit and `canUseCredit`): own slimes on a pad
-- that are not eggs and not fully grown.
function ExclusiveShopView.snackQuickBuy(state: any, slimeId: string, config: any, canUseCredit: boolean?): QuickBuy?
	local shop = shopOf(state)
	if shop == nil or type(state.slimes) ~= "table" or (catalogueOf(config) :: any).products.GrowthSnack == nil then
		return nil
	end
	if type(config.FEATURES) == "table" and config.FEATURES.GrowingSlimes ~= true then
		return nil -- slimes don't grow: nothing to sell
	end
	for _, view in state.slimes do
		local slime = if type(view) == "table" then view.slime else nil
		if type(slime) == "table" and slime.id == slimeId then
			if slime.egg ~= nil or (type(slime.growth) == "number" and slime.growth >= 1) then
				return nil
			end
			return quickBuy(
				config,
				"GrowthSnack",
				"shop.quick.growth_snack",
				canUseCredit == true and credits(shop, "snack") > 0
			)
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
		return { mode = "credit", text = Text.t(ExclusiveShopView.USE_LOCK_BREAK), key = "LockBreak" }
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
	return quickBuy(config, "ServerLuckPotion", "shop.quick.buy_for_server", false)
end

return table.freeze(ExclusiveShopView)
