--!strict
--[[
	WorldShopLogic (CONTRACT.md §27)

	Pure client side of the two in-world shops (Panels/WorldShop renders it; tests/ui/WorldShop.spec.luau):
	  * rows(): the rows of one shop from Shared.Shops and the live State (price, level, owned / maxed,
	    sold out, rank-locked), reusing ShopCatalog's row logic;
	  * view(): what the card draws from those rows: the Item Shop's tabs (Items / PvP / Fun), group
	    labels, one ladder card per PvP line showing only the tier that matters, the fun item grid, and
	    the Upgrade Shop's groups with "now -> next" text and thin rows for maxed or not-yet-unlocked;
	  * the friendly text of every deny code (ShopEvent Denied.code / Request result.code);
	  * controller(): which shop is open, from ShopEvent Open / Close / Purchased / Denied and the Player
	    attribute OpenShop; closing from the client sends Request("CloseShop").
	The client never decides outcomes: every purchase is Request("ShopBuy", shopId, itemId).
]]

local Shared = if script then game:GetService("ReplicatedStorage"):WaitForChild("Shared") :: any else nil
local PvpRules = if Shared then require(Shared:WaitForChild("PvpRules")) else require("../shared/PvpRules")
local Shops = if Shared then require(Shared:WaitForChild("Shops")) else require("../shared/Shops")
local Format = if script then require(script.Parent.Format) else require("./Format")
local ShopCatalog = if script then require(script.Parent.ShopCatalog) else require("./ShopCatalog")
local Text = if script then require(script.Parent.Text) else require("./Text")

export type Status = "buy" | "locked" | "maxed" | "owned" | "soldOut" | "unavailable" -- ShopCatalog.Status

export type Row = {
	id: string, -- Shared.Shops item id (the ShopBuy itemId)
	shopId: string,
	name: string,
	icon: string, -- ItemIcons registry id
	description: string,
	status: Status,
	enabled: boolean,
	buttonText: string,
	levelText: string?,
	progress: number?, -- level / maxLevel of a leveled upgrade
	level: number?, -- leveled upgrades: one pip per maxLevel, the first `level` filled
	maxLevel: number?,
	stockText: string?, -- restocking consumables: the "2/3 left" tag under the icon
	price: number?,
}

local WorldShopLogic = {}

WorldShopLogic.ICON_PREFIX = table.freeze({
	BuyUpgrade = "Upgrade_",
	BuyConsumable = "Consumable_",
	BuyPvpItem = "Pvp_",
})

-- Deny code -> the Strings key of its toast (CONTRACT.md §27.7). Unavailable shows the server's message when
-- there is one.
WorldShopLogic.MESSAGES = table.freeze({
	BadShop = "shop.deny.bad_shop",
	NotInShop = "shop.deny.not_in_shop",
	NotOpen = "shop.deny.not_open",
	OutOfRange = "shop.deny.out_of_range",
	Dead = "shop.deny.dead",
	NoCash = "shop.deny.no_cash",
	Maxed = "shop.deny.maxed",
	Locked = "shop.deny.locked",
	SoldOut = "shop.deny.sold_out",
	Owned = "shop.deny.owned",
	BadTarget = "shop.deny.bad_target",
	Busy = "shop.deny.busy",
	Unavailable = "shop.deny.unavailable",
})

-- True for a server message worth showing: a non-empty string or a Localize message.
local function hasText(value: any): boolean
	return (type(value) == "string" and value ~= "") or (type(value) == "table" and type(value.key) == "string")
end

function WorldShopLogic.messageFor(code: any, serverMessage: any): string
	local hasServerText = hasText(serverMessage)
	if code == "Unavailable" and hasServerText then
		return Text.text(serverMessage)
	end
	local key = if type(code) == "string" then (WorldShopLogic.MESSAGES :: any)[code] else nil
	if key then
		return Text.t(key)
	end
	return if hasServerText then Text.text(serverMessage) else Text.t(WorldShopLogic.MESSAGES.Unavailable)
end

-- The toast of a failed Request result: a shop code is mapped, any other failure keeps its message.
function WorldShopLogic.failText(result: any, fallback: string): string
	if type(result) == "table" and type(result.code) == "string" then
		return WorldShopLogic.messageFor(result.code, result.message)
	end
	return if type(result) == "table" and hasText(result.message) then Text.text(result.message) else fallback
end

-- A denial reaches the client twice (the Request result and ShopEvent Denied): one toast per code per window.
WorldShopLogic.DUPLICATE_WINDOW = 1

function WorldShopLogic.toastGate(window: number?)
	local lastCode: string? = nil
	local lastAt = -math.huge
	return function(code: string, now: number): boolean
		if code == lastCode and now - lastAt < (window or WorldShopLogic.DUPLICATE_WINDOW) then
			return false
		end
		lastCode, lastAt = code, now
		return true
	end
end

-- Two lines of 13 px fit beside the badge and the Buy button on a phone; the server texts of the consumables
-- do not, so the rows say it shorter (Strings keys).
WorldShopLogic.CONSUMABLE_SHORT = table.freeze({
	LuckPotion = "shop.consumable_short.luck_potion",
	WeatherTotem = "shop.consumable_short.weather_totem",
})

-- Item names longer than this get the smaller size so they stay on one line beside the Buy button.
WorldShopLogic.NAME_SIZE = 17
WorldShopLogic.NAME_SIZE_LONG = 15
WorldShopLogic.NAME_LONG = 15

function WorldShopLogic.nameSize(name: string): number
	return if (utf8.len(name) or #name) > WorldShopLogic.NAME_LONG
		then WorldShopLogic.NAME_SIZE_LONG
		else WorldShopLogic.NAME_SIZE
end

-- A data name as the shop shows it: sentence case in English ("Speed coil"); other languages keep the
-- translation's own casing.
function WorldShopLogic.caseName(name: string): string
	return if string.sub(Text.locale(), 1, 2) == "en" then Format.sentenceCase(name) else name
end

-- A word field that may come from the server as a Localize message.
local function word(value: any): string?
	if value == nil then
		return nil
	end
	return if type(value) == "string" then value else Text.text(value)
end

function WorldShopLogic.title(shopId: string): string
	local shop = Shops.shop(shopId)
	return if shop
		then WorldShopLogic.caseName(Text.data("shops", shop.id, "name", shop.name))
		else Text.t("shop.world.title")
end

-- A shop item's name in the player's language (the Shared.Shops row's data name; `english`: the server's
-- name, else the row's).
function WorldShopLogic.itemName(item: Shops.Item, english: any): string
	local fallback = word(english) or item.name
	return WorldShopLogic.caseName(Text.data("shopItem", item.id, "name", fallback))
end

-- The ItemIcons registry id of a shop item.
function WorldShopLogic.iconId(item: Shops.Item): string
	local prefix = (WorldShopLogic.ICON_PREFIX :: any)[item.action]
	return if prefix then prefix .. item.id else item.id
end

local function cashOf(state: any): number
	return if type(state) == "table" and type(state.cash) == "number" then state.cash else 0
end

local function row(shopId: string, item: Shops.Item, fields: { [string]: any }): Row
	local out: any = {
		id = item.id,
		shopId = shopId,
		name = item.name,
		icon = WorldShopLogic.iconId(item),
		description = Text.data("shopItem", item.id, "text", item.text),
	}
	for key, value in fields do
		out[key] = value
	end
	out.name = WorldShopLogic.itemName(item, fields.name)
	return out :: Row
end

-- Static items (Speed Coil): ShopCatalog.view.
local function staticRow(shopId: string, item: Shops.Item, state: any, actions: any, config: any): Row?
	local catalogItem = ShopCatalog.find(item.id)
	if not catalogItem then
		return nil
	end
	local view = ShopCatalog.view(catalogItem, state, actions, config)
	return row(shopId, item, {
		description = view.description,
		status = view.status,
		enabled = view.enabled,
		buttonText = view.buttonText,
		levelText = view.levelText,
		progress = view.progress,
		level = view.level,
		maxLevel = view.maxLevel,
		price = view.price,
	})
end

-- v13 upgrades: the entry of State.upgrades (nil entry = the server does not offer it, no row).
local function upgradeRow(shopId: string, item: Shops.Item, state: any, actions: any): Row?
	local entry: any = nil
	for _, u in if type(state) == "table" and type(state.upgrades) == "table" then state.upgrades else {} do
		if type(u) == "table" and u.id == item.id then
			entry = u
		end
	end
	if entry == nil then
		return nil
	end
	local view = ShopCatalog.upgradeViews({ cash = cashOf(state), upgrades = { entry } }, actions)[1]
	if not view then
		return nil
	end
	return row(shopId, item, {
		name = view.item.name,
		description = view.description,
		status = view.status,
		enabled = view.enabled,
		buttonText = view.buttonText,
		levelText = view.levelText,
		progress = view.progress,
		level = view.level,
		maxLevel = view.maxLevel,
		price = view.price,
	})
end

-- Restocking consumables: the entry of State.consumables.items; no entry (or no consumables view) = sold out.
local function consumableRow(shopId: string, item: Shops.Item, state: any, actions: any): Row
	local shortKey = (WorldShopLogic.CONSUMABLE_SHORT :: any)[item.id]
	local short = if shortKey then Text.t(shortKey) else nil
	local entry: any = nil
	local view = if type(state) == "table" then state.consumables else nil
	for _, c in if type(view) == "table" and type(view.items) == "table" then view.items else {} do
		if c.id == item.id then
			entry = c
		end
	end
	if entry == nil then
		return row(shopId, item, {
			description = short or Text.data("consumable", item.id, "text", item.text),
			status = "soldOut",
			enabled = false,
			buttonText = Text.t("shop.button.sold_out"),
		})
	end
	local catalog = ShopCatalog.consumableViews({
		cash = cashOf(state),
		consumables = { items = { entry } },
		slimes = state.slimes,
		favoriteId = state.favoriteId,
	}, actions)[1]
	return row(shopId, item, {
		name = entry.name or item.name,
		description = short or catalog.description,
		status = catalog.status,
		enabled = catalog.enabled,
		buttonText = catalog.buttonText,
		levelText = catalog.levelText,
		stockText = catalog.stockText,
		price = catalog.price,
	})
end

-- The Strings key of a PvP line's "<line> tool, tier N" text; a line missing here shows its Config name.
WorldShopLogic.LINE_TIER = table.freeze({
	Knockback = "shop.pvp.knockback_tier",
	Trap = "shop.pvp.trap_tier",
	Blaster = "shop.pvp.blaster_tier",
})

-- A PvP tool's description: "Fun item", or "Knockback tool, tier 2".
function WorldShopLogic.pvpLine(tool: any): string
	if tool.kind == "fun" then
		return Text.t("shop.pvp.fun_item")
	end
	local key = (WorldShopLogic.LINE_TIER :: any)[tool.line]
	if key then
		return Text.t(key, { tier = tool.tier })
	end
	return Text.t("shop.pvp.line_tier", { line = tostring(tool.line), tier = tool.tier })
end

-- PvP tools (FEATURES.PvP): owned / rank gate from State.pvp, price from PvpRules.price. A Goo Trap is a stack of
-- charges (State.pvp.charges): buyable until Config.PVP.TRAP_MAX_HELD, with the "2/5 held" tag.
local function pvpRow(shopId: string, item: Shops.Item, state: any, actions: any, config: any): Row?
	local tool: any = nil
	for _, t in config.PVP_TOOLS do
		if t.id == item.id then
			tool = t
		end
	end
	if tool == nil then
		return nil
	end
	local pvp = if type(state) == "table" then state.pvp else nil
	local rank = if type(pvp) == "table" and type(pvp.rank) == "number" then pvp.rank else 0
	local owned = type(pvp) == "table" and type(pvp.owned) == "table" and pvp.owned[item.id] == true
	local stack = PvpRules.usesCharges(tool)
	local held = 0
	if stack and type(pvp) == "table" and type(pvp.charges) == "table" and type(pvp.charges[item.id]) == "number" then
		held = pvp.charges[item.id]
	end
	local price = PvpRules.price(item.id)
	local kind: Status = "buy"
	local buttonText = Format.formatCash(price)
	local enabled = cashOf(state) >= price
	if actions.BuyPvpItem == nil then
		kind, buttonText, enabled = "unavailable", Text.t("shop.button.coming_soon"), false
	elseif stack and held >= config.PVP.TRAP_MAX_HELD then
		kind, buttonText, enabled = "maxed", Text.t("shop.button.full"), false
	elseif owned and not stack then
		kind, buttonText, enabled = "owned", Text.t("shop.button.owned"), false
	elseif rank < tool.rebirths then
		kind, buttonText, enabled = "locked", Text.t("shop.button.rebirth", { rebirths = tool.rebirths }), false
	end
	return row(shopId, item, {
		description = WorldShopLogic.pvpLine(tool),
		status = kind,
		enabled = enabled,
		buttonText = buttonText,
		levelText = nil,
		stockText = if stack then Text.t("shop.pvp.held", { held = held, max = config.PVP.TRAP_MAX_HELD }) else nil,
		price = price,
	})
end

-- The rows of `shopId` for the live State, in the display order of Shared.Shops, filtered by `features`
-- (Config.FEATURES). `actions` = Remotes.ACTIONS, `config` = Shared Config.
function WorldShopLogic.rows(
	shopId: string,
	state: any,
	actions: { [string]: any },
	features: any,
	config: any
): { Row }
	local out: { Row } = {}
	for _, item in Shops.items(shopId, features) do
		local built: Row? = nil
		if item.action == "BuyUpgrade" then
			built = upgradeRow(shopId, item, state, actions)
		elseif item.action == "BuyConsumable" then
			built = consumableRow(shopId, item, state, actions)
		elseif item.action == "BuyPvpItem" then
			built = pvpRow(shopId, item, state, actions, config)
		else
			built = staticRow(shopId, item, state, actions, config)
		end
		if built then
			built.buttonText = WorldShopLogic.buyText(built, cashOf(state))
			table.insert(out, built)
		end
	end
	return out
end

-- A buyable row's button: "Buy $1.5K" when you can pay, "Need $10.8K more" (disabled) when you can't. Any
-- other row keeps its state text ("Owned", "Rebirth 5").
function WorldShopLogic.buyText(r: Row, cash: number): string
	if r.status ~= "buy" or type(r.price) ~= "number" then
		return r.buttonText
	end
	local price = r.price :: number
	if cash < price then
		return Text.t("shop.button.need_more", { amount = Format.formatCash(price - cash) })
	end
	return Text.t("shop.button.buy_price", { price = Format.formatCash(price) })
end

-- The restock time (unix seconds) shown in the Item Shop header; nil when the shop has no consumables.
function WorldShopLogic.restockAt(shopId: string, state: any, features: any): number?
	if shopId ~= Shops.ITEM_SHOP or features.Consumables ~= true then
		return nil
	end
	local view = if type(state) == "table" then state.consumables else nil
	return if type(view) == "table" and type(view.restockAt) == "number" then view.restockAt else nil
end

-- Card layout (view) -------------------------------------------------------------------------------------

export type Tab = { id: string, label: string, dot: boolean } -- dot: something in it can be bought now
export type Step = { tier: number, id: string, state: "owned" | "locked" | "open", selected: boolean }
export type Ladder = { line: string, title: string, steps: { Step }, row: Row }
export type Entry = {
	key: string, -- stable per thing drawn (Panels/WorldShop rebuilds an entry whose key is new)
	kind: "label" | "row" | "ladder" | "grid",
	text: string?, -- label
	aside: string?, -- label: "restock" = the live restock countdown on its right
	row: Row?, -- row
	thin: boolean?, -- row: a one-line row (maxed, owned, not yet unlocked)
	ladder: Ladder?,
	tiles: { Row }?, -- grid
}
export type View = { tabs: { Tab }, tab: string?, entries: { Entry } }

-- Item Shop tabs; `label` is a Strings key (view() gives each Tab its text).
WorldShopLogic.TABS = table.freeze({
	table.freeze({ id = "Items", label = "shop.tab.items" }),
	table.freeze({ id = "PvP", label = "shop.tab.pvp" }),
	table.freeze({ id = "Fun", label = "shop.tab.fun" }),
})

-- PvP lines in card order, with the Strings keys of their card title (`title`), their "every tier owned" row
-- (`maxed`) and, for a stack line, its "other ... held" line (`others`). A line missing here gets a card after
-- these, titled by its line.
WorldShopLogic.LADDERS = table.freeze({
	table.freeze({ line = "Knockback", title = "shop.ladder.gloves", maxed = "shop.ladder.gloves_maxed" }),
	table.freeze({
		line = "Trap",
		title = "shop.ladder.traps",
		maxed = "shop.ladder.traps_maxed",
		others = "shop.ladder.traps_others",
	}),
	table.freeze({ line = "Blaster", title = "shop.ladder.blasters", maxed = "shop.ladder.blasters_maxed" }),
})

-- The Strings key of one short line per PvP tool for its ladder card (one line on a phone; the second line says what you own).
WorldShopLogic.PVP_SHORT = table.freeze({
	KnockGlove1 = "shop.pvp_short.knock_glove1",
	KnockGlove2 = "shop.pvp_short.knock_glove2",
	KnockGlove3 = "shop.pvp_short.knock_glove3",
	KnockGlove4 = "shop.pvp_short.knock_glove4",
	KnockGlove5 = "shop.pvp_short.knock_glove5",
	GooTrap1 = "shop.pvp_short.goo_trap1",
	GooTrap2 = "shop.pvp_short.goo_trap2",
	GooTrap3 = "shop.pvp_short.goo_trap3",
	GooBlaster1 = "shop.pvp_short.goo_blaster1",
	GooBlaster2 = "shop.pvp_short.goo_blaster2",
	GooBlaster3 = "shop.pvp_short.goo_blaster3",
})

-- Upgrade Shop groups (label: a Strings key), in order. An upgrade missing here goes in a last "More" group.
WorldShopLogic.UPGRADE_GROUPS = table.freeze({
	table.freeze({ label = "shop.group.earn_more", ids = table.freeze({ "Income", "OfflineCap" }) }),
	table.freeze({ label = "shop.group.faster", ids = table.freeze({ "CarrySpeed", "QuickBrew" }) }),
	table.freeze({ label = "shop.group.luck", ids = table.freeze({ "Luck" }) }),
})

-- Section label keys.
WorldShopLogic.LABELS = table.freeze({
	gear = "shop.label.gear",
	consumables = "shop.label.consumables",
	owned = "shop.label.owned",
	ladders = "shop.label.ladders",
	fun = "shop.label.fun",
	more = "shop.label.more",
})

-- The effect of `level` levels of an upgrade whose per-level text is `text` ("+10% income", "+1h offline income
-- cap"): the amount scaled by level, then the rest. Returns amount, rest; nil when the text has no leading amount.
function WorldShopLogic.upgradeAmount(text: string, level: number): (string?, string?)
	local sign, number, unit, rest = string.match(text, "^([%+%-])(%d+%.?%d*)([%%h]?)%s*(.*)$")
	local n = tonumber(number)
	if not sign or not n then
		return nil, nil
	end
	local total = n * level
	local shown = if total == math.floor(total) then string.format("%d", total) else string.format("%.1f", total)
	return `{sign}{shown}{unit}`, rest
end

-- An upgrade row's line: "+120% -> +130% income", "Next: +10% income" at level 0, the full effect when maxed.
function WorldShopLogic.upgradeEffect(id: string, text: string, level: number, maxLevel: number): string
	local now, rest = WorldShopLogic.upgradeAmount(text, level)
	local nextAmount = WorldShopLogic.upgradeAmount(text, level + 1)
	if not now or not nextAmount or not rest then
		return ShopCatalog.upgradeText(id, text)
	end
	local phrase = ShopCatalog.effectPhrase(id, rest)
	if level >= maxLevel then
		return Text.t("shop.upgrade.amount", { amount = now, effect = phrase })
	elseif level <= 0 then
		return Text.t("shop.upgrade.next", { amount = nextAmount, effect = phrase })
	end
	return Text.t("shop.upgrade.change", { from = now, to = nextAmount, effect = phrase })
end

local function toolOf(config: any, id: string): any
	for _, t in config.PVP_TOOLS do
		if t.id == id then
			return t
		end
	end
	return nil
end

-- Which Item Shop tab sells `itemId`.
function WorldShopLogic.tabOf(itemId: string, config: any): string
	local tool = toolOf(config, itemId)
	if tool == nil then
		return "Items"
	end
	return if tool.kind == "fun" then "Fun" else "PvP"
end

local function buyable(r: Row): boolean
	return r.status == "buy" and r.enabled
end

local function withFields(r: Row, fields: { [string]: any }): Row
	local out: any = table.clone(r)
	for k, v in fields do
		out[k] = v
	end
	return out :: Row
end

-- The ladder card of one PvP line: the tier on show and the steps. nil when the line has no rows.
-- Gloves / blasters show the best tier above the owned one that the rebirths reach, else the next one (locked).
-- Traps (a stack of charges per tier) show the best tier the rebirths reach, else tier 1. `pick` (a tier the
-- player tapped) wins when that tier exists. Owning the top glove / blaster turns the card into a thin Max row.
function WorldShopLogic.ladder(
	line: string,
	title: string,
	rowsById: { [string]: Row },
	state: any,
	config: any,
	pick: number?
): Entry?
	local tools = {}
	for _, t in config.PVP_TOOLS do
		if t.line == line and rowsById[t.id] then
			table.insert(tools, t)
		end
	end
	if #tools == 0 then
		return nil
	end
	table.sort(tools, function(a, b)
		return a.tier < b.tier
	end)
	local pvp = if type(state) == "table" and type(state.pvp) == "table" then state.pvp else {}
	local rank = if type(pvp.rank) == "number" then pvp.rank else 0
	local owned = if type(pvp.owned) == "table" then pvp.owned else {}
	local charges = if type(pvp.charges) == "table" then pvp.charges else {}
	local stack = PvpRules.usesCharges(tools[1])
	local def: any = nil
	for _, l in WorldShopLogic.LADDERS do
		if l.line == line then
			def = l
		end
	end
	local function held(t: any): number
		return if type(charges[t.id]) == "number" then charges[t.id] else 0
	end
	local ownTier, ownTool = 0, nil
	if not stack then
		for _, t in tools do
			if owned[t.id] == true and t.tier > ownTier then
				ownTier, ownTool = t.tier, t
			end
		end
	end
	local shown: any = nil
	for _, t in tools do
		if pick ~= nil and t.tier == pick then
			shown = t
		end
	end
	if shown == nil then
		local candidates = {}
		for _, t in tools do
			if stack or t.tier > ownTier then
				table.insert(candidates, t)
			end
		end
		if #candidates == 0 then
			local top = tools[#tools]
			return {
				key = `ladder_{line}_max`,
				kind = "row",
				thin = true,
				row = withFields(rowsById[top.id], {
					description = if def then Text.t(def.maxed) else Text.t("shop.ladder.line_maxed", { line = title }),
					status = "maxed",
					enabled = false,
					buttonText = Text.t("shop.button.max"),
					stockText = nil,
				}),
			}
		end
		for _, t in candidates do
			if rank >= t.rebirths then
				shown = t
			end
		end
		shown = shown or candidates[1]
	end
	local steps: { Step } = {}
	local others = 0
	for _, t in tools do
		local isOwned = if stack then held(t) > 0 else t.tier <= ownTier
		table.insert(steps, {
			tier = t.tier,
			id = t.id,
			state = if isOwned then "owned" elseif rank < t.rebirths then "locked" else "open",
			selected = t == shown,
		})
		if stack and t ~= shown then
			others += held(t)
		end
	end
	local shortKey = (WorldShopLogic.PVP_SHORT :: any)[shown.id]
	local short = if shortKey then Text.t(shortKey) else rowsById[shown.id].description
	local second
	if stack and others > 0 then
		second = if def and def.others
			then Text.t(def.others, { count = others })
			else Text.t("shop.ladder.line_others", { line = title, count = others })
	elseif stack then
		second = Text.t("shop.ladder.tier_of", { tier = shown.tier, count = #tools })
	elseif ownTool then
		second = Text.t("shop.ladder.yours", {
			name = WorldShopLogic.caseName(Text.data("pvpTool", ownTool.id, "name", ownTool.name)),
		})
	else
		second = Text.t("shop.ladder.yours_none")
	end
	return {
		key = `ladder_{line}`,
		kind = "ladder",
		ladder = {
			line = line,
			title = title,
			steps = steps,
			row = withFields(rowsById[shown.id], { description = `{short}\n{second}` }),
		},
	}
end

local function itemEntries(tab: string, rows: { Row }, state: any, config: any, picks: { [string]: number }): { Entry }
	local out: { Entry } = {}
	if tab == "Items" then
		local gear, consumables, ownedRows = {}, {}, {}
		for _, r in rows do
			local item = Shops.find(r.shopId, r.id)
			if item and item.action == "BuyConsumable" then
				table.insert(consumables, r)
			elseif r.status == "owned" then
				table.insert(ownedRows, r)
			else
				table.insert(gear, r)
			end
		end
		local function section(key: string, label: string, list: { Row }, thin: boolean, aside: string?)
			if #list == 0 then
				return
			end
			table.insert(out, { key = `label_{key}`, kind = "label", text = Text.t(label), aside = aside })
			for _, r in list do
				table.insert(
					out,
					{ key = `row_{r.id}{if thin then "_thin" else ""}`, kind = "row", row = r, thin = thin }
				)
			end
		end
		section("gear", WorldShopLogic.LABELS.gear, gear, false)
		section("consumables", WorldShopLogic.LABELS.consumables, consumables, false, "restock")
		section("owned", WorldShopLogic.LABELS.owned, ownedRows, true)
	elseif tab == "PvP" then
		local byId: { [string]: Row } = {}
		for _, r in rows do
			byId[r.id] = r
		end
		local cards: { Entry } = {}
		local seen: { [string]: boolean } = {}
		local function add(line: string, title: string)
			seen[line] = true
			local e = WorldShopLogic.ladder(line, title, byId, state, config, picks[line])
			if e then
				table.insert(cards, e)
			end
		end
		for _, l in WorldShopLogic.LADDERS do
			add(l.line, Text.t(l.title))
		end
		for _, t in config.PVP_TOOLS do
			if t.kind ~= "fun" and not seen[t.line] then
				add(t.line, t.line)
			end
		end
		if #cards > 0 then
			table.insert(out, { key = "label_ladders", kind = "label", text = Text.t(WorldShopLogic.LABELS.ladders) })
			for _, e in cards do
				table.insert(out, e)
			end
		end
	else
		local tiles: { Row } = {}
		for _, r in rows do
			-- A tile has room for the price only; it stays disabled until you can pay it.
			local text = if r.status == "buy" and type(r.price) == "number"
				then Format.formatCash(r.price)
				else r.buttonText
			table.insert(tiles, withFields(r, { buttonText = text }))
		end
		if #tiles > 0 then
			table.insert(out, { key = "label_fun", kind = "label", text = Text.t(WorldShopLogic.LABELS.fun) })
			table.insert(out, { key = "grid_fun", kind = "grid", tiles = tiles })
		end
	end
	return out
end

local function upgradeEntries(rows: { Row }, state: any): { Entry }
	local entries: { [string]: any } = {}
	for _, u in if type(state) == "table" and type(state.upgrades) == "table" then state.upgrades else {} do
		if type(u) == "table" and type(u.id) == "string" then
			entries[u.id] = u
		end
	end
	local byId: { [string]: Row } = {}
	for _, r in rows do
		byId[r.id] = r
	end
	local out: { Entry } = {}
	local placed: { [string]: boolean } = {}
	local function group(key: string, label: string, ids: { string })
		local full, thin = {}, {}
		for _, id in ids do
			local r = byId[id]
			if r and not placed[id] then
				placed[id] = true
				local u = entries[id] or {}
				local level = r.level or 0
				local maxLevel = r.maxLevel or level
				local notYet = level <= 0 and r.status == "locked"
				-- The server's English text: upgradeEffect reads the amount from it.
				local text = if type(u.text) == "string" then u.text else r.description
				local fields: { [string]: any } =
					{ description = WorldShopLogic.upgradeEffect(id, text, level, maxLevel) }
				if notYet then
					fields.description = Text.t("shop.upgrade.unlocks_at", { rebirths = u.requires or "?" })
				end
				local shown = withFields(r, fields)
				if r.status == "maxed" or notYet then
					table.insert(thin, shown)
				else
					table.insert(full, shown)
				end
			end
		end
		if #full + #thin == 0 then
			return
		end
		table.insert(out, { key = `label_{key}`, kind = "label", text = Text.t(label) })
		for _, r in full do
			table.insert(out, { key = `row_{r.id}`, kind = "row", row = r })
		end
		for _, r in thin do
			table.insert(out, { key = `row_{r.id}_thin`, kind = "row", row = r, thin = true })
		end
	end
	for i, g in WorldShopLogic.UPGRADE_GROUPS do
		group(`group{i}`, g.label, g.ids)
	end
	local rest = {}
	for _, r in rows do
		if not placed[r.id] then
			table.insert(rest, r.id)
		end
	end
	group("more", WorldShopLogic.LABELS.more, rest)
	return out
end

-- What the card draws for `shopId`. `opts.tab` = the Item Shop tab the player picked (unknown or nil = the
-- first one), `opts.picks` = line -> tier the player tapped on a ladder card.
function WorldShopLogic.view(
	shopId: string,
	state: any,
	actions: { [string]: any },
	features: any,
	config: any,
	opts: { tab: string?, picks: { [string]: number }? }?
): View
	local rows = WorldShopLogic.rows(shopId, state, actions, features, config)
	if shopId ~= Shops.ITEM_SHOP then
		return { tabs = {}, tab = nil, entries = upgradeEntries(rows, state) }
	end
	local o = opts or {}
	local byTab: { [string]: { Row } } = {}
	for _, r in rows do
		local t = WorldShopLogic.tabOf(r.id, config)
		byTab[t] = byTab[t] or {}
		table.insert(byTab[t], r)
	end
	local tabs: { Tab } = {}
	local current: string? = nil
	for _, def in WorldShopLogic.TABS do
		local list = byTab[def.id]
		if list then
			local dot = false
			for _, r in list do
				dot = dot or buyable(r)
			end
			table.insert(tabs, { id = def.id, label = Text.t(def.label), dot = dot })
			if def.id == o.tab then
				current = def.id
			end
		end
	end
	if current == nil and #tabs > 0 then
		current = tabs[1].id
	end
	local entries = if current then itemEntries(current, byTab[current], state, config, o.picks or {}) else {}
	return { tabs = tabs, tab = current, entries = entries }
end

export type Slot = {
	kind: "buy" | "status" | "stamp", -- hold-to-buy button, sunken state well, or the small gold MAX stamp
	text: string,
	sub: string?, -- small second line of a status well
	good: boolean?, -- status text in the buy green ("Owned")
	check: boolean?, -- the game's check left of the text (Widgets.setStatusCheck)
}

-- What a row shows on its right: the Buy button while it can be bought (disabled when you can't afford it),
-- otherwise the state it is in. Takes a WorldShopLogic.Row or a ShopCatalog.ItemView.
function WorldShopLogic.slot(r: { status: Status, buttonText: string }): Slot
	local status = r.status
	if status == "buy" then
		return { kind = "buy", text = r.buttonText }
	elseif status == "maxed" then
		return { kind = "stamp", text = Text.t("shop.button.max") }
	elseif status == "owned" then
		return { kind = "status", text = Text.t("shop.button.owned"), good = true, check = true }
	elseif status == "locked" then
		return { kind = "status", text = `🔒 {r.buttonText}`, sub = Text.t("shop.button.to_unlock") }
	end
	return { kind = "status", text = r.buttonText }
end

-- Request("ShopBuy", ...) arguments of a row: shopId, itemId.
function WorldShopLogic.buyArgs(r: Row): { any }
	return { r.shopId, r.id }
end

-- "Speed coil bought" / "Slime snacks bought, Lv 3" for ShopEvent Purchased (the row's sentence-case name).
function WorldShopLogic.purchasedText(shopId: any, itemId: any, level: any): string
	local item = Shops.find(shopId, itemId)
	local name = if item then WorldShopLogic.itemName(item, nil) else Text.t("shop.world.item")
	if type(level) == "number" then
		return Text.t("shop.world.bought_level", { name = name, level = level })
	end
	return Text.t("shop.world.bought", { name = name })
end

export type Deps = {
	open: (shopId: string) -> (), -- show the shop card
	close: () -> (), -- hide it
	toast: (text: string, kind: string, itemId: string?) -> (),
	send: (action: string, ...any) -> (),
	clock: () -> number,
}

-- Which shop the client shows. The server opens a shop (prompt) and tells the client with ShopEvent Open and
-- the OpenShop attribute; both end here and are idempotent. A close started on the client (X, Esc, backdrop,
-- another menu) sends Request("CloseShop"); a close the server announced does not.
function WorldShopLogic.controller(deps: Deps)
	local current: string? = nil
	local gate = WorldShopLogic.toastGate()
	local self = {}

	function self.current(): string?
		return current
	end

	local function show(shopId: any)
		if Shops.shop(shopId) == nil or shopId == current then
			return
		end
		current = shopId
		deps.open(shopId)
	end

	local function hide()
		if current == nil then
			return
		end
		current = nil
		deps.close()
	end

	function self.denied(code: any, message: any)
		local key = if type(code) == "string" then code else "?"
		if gate(key, deps.clock()) then
			deps.toast(WorldShopLogic.messageFor(code, message), "bad", nil)
		end
	end

	-- A failed Request result (nil when the failure is not a shop denial).
	function self.failed(result: any): boolean
		if type(result) == "table" and type(result.code) == "string" then
			self.denied(result.code, result.message)
			return true
		end
		return false
	end

	function self.onEvent(event: any)
		if type(event) ~= "table" then
			return
		end
		if event.kind == "Open" then
			show(event.shopId)
		elseif event.kind == "Close" then
			if current ~= nil and (event.shopId == nil or event.shopId == current) then
				hide()
			end
		elseif event.kind == "Purchased" then
			local item = Shops.find(event.shopId, event.itemId)
			deps.toast(
				WorldShopLogic.purchasedText(event.shopId, event.itemId, event.level),
				"good",
				if item then WorldShopLogic.iconId(item) else nil
			)
		elseif event.kind == "Denied" then
			self.denied(event.code, event.message)
		end
	end

	function self.onAttribute(value: any)
		if type(value) == "string" then
			show(value)
		else
			hide()
		end
	end

	-- The card was hidden on the client: the server still has the shop open.
	function self.onHidden()
		if current ~= nil then
			current = nil
			deps.send("CloseShop")
		end
	end

	return self
end

return WorldShopLogic
