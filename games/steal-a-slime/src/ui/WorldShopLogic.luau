--!strict
--[[
	WorldShopLogic (FEATURES.WorldShops, CONTRACT.md §27)

	Pure client side of the two in-world shops (Panels/WorldShop renders it; tests/ui/WorldShop.spec.luau):
	  * rows(): the rows of one shop from Shared.Shops and the live State (price, level, owned / maxed,
	    sold out, rank-locked), reusing ShopCatalog's row logic;
	  * the friendly text of every deny code (ShopEvent Denied.code / Request result.code);
	  * controller(): which shop is open, from ShopEvent Open / Close / Purchased / Denied and the Player
	    attribute OpenShop; closing from the client sends Request("CloseShop").
	The client never decides outcomes: every purchase is Request("ShopBuy", shopId, itemId, arg?).
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
	arg: string?, -- ShopBuy arg: the slime id of a Mutation Spray
}

local WorldShopLogic = {}

WorldShopLogic.ICON_PREFIX = table.freeze({
	BuyUpgrade = "Upgrade_",
	BuyConsumable = "Consumable_",
	BuyPvpItem = "Pvp_",
})

-- Deny code -> toast text (CONTRACT.md §27.7). Unavailable shows the server's message when there is one.
WorldShopLogic.MESSAGES = table.freeze({
	FlagOff = "The shops are closed",
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
	MutationSpray = "Adds a mutation to a slime",
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

-- The line under the cash that says what kind of shop this is (the Item Shop's restock timer takes its place).
WorldShopLogic.TAGLINE = table.freeze({
	ItemShop = "Tools, eggs & potions",
	UpgradeShop = "Kept when you rebirth",
})

function WorldShopLogic.tagline(shopId: string): string
	return (WorldShopLogic.TAGLINE :: any)[shopId] or ""
end

function WorldShopLogic.title(shopId: string): string
	local shop = Shops.shop(shopId)
	return if shop then shop.name else "Shop"
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
	return out :: Row
end

-- Static items (Lock, Longer locks, Speed Coil, Mystery Egg): ShopCatalog.view.
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

-- PvP tools (FEATURES.PvP): owned / rank gate from State.pvp, price from PvpRules.price.
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
	local price = PvpRules.price(item.id)
	local kind: Status = "buy"
	local buttonText = Format.formatCash(price)
	local enabled = cashOf(state) >= price
	if actions.BuyPvpItem == nil then
		kind, buttonText, enabled = "unavailable", "Coming soon", false
	elseif owned then
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
			table.insert(out, built)
		end
	end
	return out
end

-- The restock time (unix seconds) shown in the Item Shop header; nil when the shop has no consumables.
function WorldShopLogic.restockAt(shopId: string, state: any, features: any): number?
	if shopId ~= Shops.ITEM_SHOP or features.Consumables ~= true then
		return nil
	end
	local view = if type(state) == "table" then state.consumables else nil
	return if type(view) == "table" and type(view.restockAt) == "number" then view.restockAt else nil
end

export type Slot = {
	kind: "buy" | "status" | "stamp", -- hold-to-buy button, sunken state well, or the small gold MAX stamp
	text: string,
	sub: string?, -- small second line of a status well
	good: boolean?, -- status text in the buy green ("✅ Owned")
}

-- What a row shows on its right: the Buy button while it can be bought (disabled when you can't afford it),
-- otherwise the state it is in. Takes a WorldShopLogic.Row or a ShopCatalog.ItemView.
function WorldShopLogic.slot(r: { status: Status, buttonText: string }): Slot
	local status = r.status
	if status == "buy" then
		return { kind = "buy", text = r.buttonText }
	elseif status == "maxed" then
		return { kind = "stamp", text = "MAX" }
	elseif status == "owned" then
		return { kind = "status", text = "✅ Owned", good = true }
	elseif status == "locked" then
		return { kind = "status", text = `🔒 {r.buttonText}`, sub = "to unlock" }
	end
	return { kind = "status", text = r.buttonText }
end

-- Request("ShopBuy", ...) arguments of a row: shopId, itemId, arg (MutationSpray: the slime).
function WorldShopLogic.buyArgs(r: Row): { any }
	return { r.shopId, r.id, r.arg }
end

-- "Lock base bought!" / "Slime Snacks bought! Lv 3" for ShopEvent Purchased.
function WorldShopLogic.purchasedText(shopId: any, itemId: any, level: any): string
	local item = Shops.find(shopId, itemId)
	local name = if item then item.name else "Item"
	if type(level) == "number" then
		return `{name} bought! Lv {level}`
	end
	return `{name} bought!`
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
