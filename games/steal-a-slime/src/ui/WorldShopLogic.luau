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

-- Deny code -> toast text (CONTRACT.md §27.7). Unavailable shows the server's message when there is one.
WorldShopLogic.MESSAGES = table.freeze({
	BadShop = "That shop doesn't exist",
	NotInShop = "Not sold here",
	NotOpen = "Open the shop first",
	OutOfRange = "Walk closer to the shop",
	Dead = "You can't shop right now",
	NoCash = "Not enough cash",
	Maxed = "Already maxed",
	Locked = "Rebirth to unlock",
	SoldOut = "Sold out - restocks soon",
	Owned = "You already own this",
	BadTarget = "Pick one of your slimes",
	Busy = "Slow down a little",
	Unavailable = "Can't buy that right now",
})

function WorldShopLogic.messageFor(code: any, serverMessage: any): string
	local hasServerText = type(serverMessage) == "string" and serverMessage ~= ""
	if code == "Unavailable" and hasServerText then
		return serverMessage :: string
	end
	local text = if type(code) == "string" then (WorldShopLogic.MESSAGES :: any)[code] else nil
	if text then
		return text
	end
	return if hasServerText then serverMessage :: string else WorldShopLogic.MESSAGES.Unavailable
end

-- The toast of a failed Request result: a shop code is mapped, any other failure keeps its message.
function WorldShopLogic.failText(result: any, fallback: string): string
	if type(result) == "table" and type(result.code) == "string" then
		return WorldShopLogic.messageFor(result.code, result.message)
	end
	return if type(result) == "table" and type(result.message) == "string" then result.message else fallback
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
-- do not, so the rows say it shorter.
WorldShopLogic.CONSUMABLE_SHORT = table.freeze({
	LuckPotion = "Better fountain rarity odds",
	WeatherTotem = "Calls the next weather",
})

-- Item names longer than this get the smaller size so they stay on one line beside the Buy button.
WorldShopLogic.NAME_SIZE = 17
WorldShopLogic.NAME_SIZE_LONG = 15
WorldShopLogic.NAME_LONG = 15

function WorldShopLogic.nameSize(name: string): number
	return if #name > WorldShopLogic.NAME_LONG then WorldShopLogic.NAME_SIZE_LONG else WorldShopLogic.NAME_SIZE
end

function WorldShopLogic.title(shopId: string): string
	local shop = Shops.shop(shopId)
	return if shop then Format.sentenceCase(shop.name) else "Shop"
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
		description = item.text,
	}
	for key, value in fields do
		out[key] = value
	end
	out.name = Format.sentenceCase(out.name)
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
	local entry: any = nil
	local view = if type(state) == "table" then state.consumables else nil
	for _, c in if type(view) == "table" and type(view.items) == "table" then view.items else {} do
		if c.id == item.id then
			entry = c
		end
	end
	if entry == nil then
		return row(shopId, item, {
			description = (WorldShopLogic.CONSUMABLE_SHORT :: any)[item.id] or item.text,
			status = "soldOut",
			enabled = false,
			buttonText = "Sold out",
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
		description = (WorldShopLogic.CONSUMABLE_SHORT :: any)[item.id] or catalog.description,
		status = catalog.status,
		enabled = catalog.enabled,
		buttonText = catalog.buttonText,
		levelText = catalog.levelText,
		stockText = catalog.stockText,
		price = catalog.price,
	})
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
		kind, buttonText, enabled = "unavailable", "Coming soon", false
	elseif stack and held >= config.PVP.TRAP_MAX_HELD then
		kind, buttonText, enabled = "maxed", "Full", false
	elseif owned and not stack then
		kind, buttonText, enabled = "owned", "Owned", false
	elseif rank < tool.rebirths then
		kind, buttonText, enabled = "locked", `Rebirth {tool.rebirths}`, false
	end
	local line = if tool.kind == "fun" then "Fun item" else `{tool.line} tool`
	return row(shopId, item, {
		description = if tool.kind == "fun" then line else `{line}, tier {tool.tier}`,
		status = kind,
		enabled = enabled,
		buttonText = buttonText,
		levelText = nil,
		stockText = if stack then `{held}/{config.PVP.TRAP_MAX_HELD} held` else nil,
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
		return `Need {Format.formatCash(price - cash)} more`
	end
	return `Buy {Format.formatCash(price)}`
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

WorldShopLogic.TABS = table.freeze({
	table.freeze({ id = "Items", label = "Items" }),
	table.freeze({ id = "PvP", label = "PvP" }),
	table.freeze({ id = "Fun", label = "Fun" }),
})

-- PvP lines in card order, with their card titles. A line missing here gets a card after these, titled by its line.
WorldShopLogic.LADDERS = table.freeze({
	table.freeze({ line = "Knockback", title = "Gloves" }),
	table.freeze({ line = "Trap", title = "Traps" }),
	table.freeze({ line = "Blaster", title = "Blasters" }),
})

-- One short line per PvP tool for its ladder card (one line on a phone; the second line says what you own).
WorldShopLogic.PVP_SHORT = table.freeze({
	KnockGlove1 = "A plain bonk",
	KnockGlove2 = "Bonks bounce you up",
	KnockGlove3 = "Blast pushes a crowd",
	KnockGlove4 = "Chains to 2 more",
	KnockGlove5 = "Sweeps a wide arc",
	GooTrap1 = "Slows a thief",
	GooTrap2 = "Sticks a thief",
	GooTrap3 = "Pulls in and sticks",
	GooBlaster1 = "Quick slowing shots",
	GooBlaster2 = "Three-blob spread",
	GooBlaster3 = "Splash and puddle",
})

-- Upgrade Shop groups, in order. An upgrade missing here goes in a last "More" group.
WorldShopLogic.UPGRADE_GROUPS = table.freeze({
	table.freeze({ label = "Earn more", ids = table.freeze({ "Income", "OfflineCap" }) }),
	table.freeze({ label = "Faster", ids = table.freeze({ "CarrySpeed", "QuickBrew" }) }),
	table.freeze({ label = "Luck", ids = table.freeze({ "Luck" }) }),
})

WorldShopLogic.LABELS = table.freeze({
	gear = "Gear",
	consumables = "Potions and totems",
	owned = "Owned",
	ladders = "Tap a number to see that tier",
	fun = "Fun items",
	more = "More",
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
	local phrase = (ShopCatalog.UPGRADE_SHORT :: any)[id] or rest
	if level >= maxLevel then
		return `{now} {phrase}`
	elseif level <= 0 then
		return `Next: {nextAmount} {phrase}`
	end
	return `{now} → {nextAmount} {phrase}`
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
					description = `{title}: every tier owned`,
					status = "maxed",
					enabled = false,
					buttonText = "Max",
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
	local short = (WorldShopLogic.PVP_SHORT :: any)[shown.id] or rowsById[shown.id].description
	local second = if stack
		then (if others > 0 then `Other {string.lower(title)} held: {others}` else `Tier {shown.tier} of {#tools}`)
		else `Yours: {if ownTool then Format.sentenceCase(ownTool.name) else "none yet"}`
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
			table.insert(out, { key = `label_{key}`, kind = "label", text = label, aside = aside })
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
			add(l.line, l.title)
		end
		for _, t in config.PVP_TOOLS do
			if t.kind ~= "fun" and not seen[t.line] then
				add(t.line, t.line)
			end
		end
		if #cards > 0 then
			table.insert(out, { key = "label_ladders", kind = "label", text = WorldShopLogic.LABELS.ladders })
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
			table.insert(out, { key = "label_fun", kind = "label", text = WorldShopLogic.LABELS.fun })
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
				local text = if type(u.text) == "string" then u.text else r.description
				local fields: { [string]: any } =
					{ description = WorldShopLogic.upgradeEffect(id, text, level, maxLevel) }
				if notYet then
					fields.description = `Unlocks at Rebirth {u.requires or "?"}`
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
		table.insert(out, { key = `label_{key}`, kind = "label", text = label })
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
			table.insert(tabs, { id = def.id, label = def.label, dot = dot })
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
		return { kind = "stamp", text = "Max" }
	elseif status == "owned" then
		return { kind = "status", text = "Owned", good = true, check = true }
	elseif status == "locked" then
		return { kind = "status", text = `🔒 {r.buttonText}`, sub = "to unlock" }
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
	local name = Format.sentenceCase(if item then item.name else "Item")
	if type(level) == "number" then
		return `{name} bought, Lv {level}`
	end
	return `{name} bought`
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
