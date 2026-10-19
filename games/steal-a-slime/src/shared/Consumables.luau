--!strict
--[[
	Consumables (pure, FEATURES.Consumables)

	The restocking Shop section (competitor-gaps.md #13). The stock of a time slot
	(`floor(unix time / CONSUMABLES_RESTOCK_SECONDS)`) is a pure function of the slot, so every
	server shows the same stock without talking to the others. Each player may buy up to the slot's
	stock of an item; the counts live in `data.consumables` and reset when the slot changes.
	A purchase adds to the held stack (`data.consumables.held`, saved, never reset by a restock); the item's
	effect happens when one is used (`ConsumableShop.use`), which takes one off the stack.
	The weather totem is only stocked where the Weather service can take a request.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Economy = if script then require(script.Parent.Economy) else require("./Economy")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")
local Types = if script then require(script.Parent.Types) else require("./Types")

type Data = PlayerData.Data

local Consumables = {}

Consumables.TOTEM = "WeatherTotem"

function Consumables.enabled(): boolean
	return Config.FEATURES.Consumables == true
end

function Consumables.def(id: any): Config.Consumable?
	for _, def in Config.CONSUMABLES do
		if def.id == id then
			return def
		end
	end
	return nil
end

function Consumables.slotAt(now: number): number
	return math.floor(now / Config.CONSUMABLES_RESTOCK_SECONDS)
end

-- Unix time of the next restock.
function Consumables.restockAt(now: number): number
	return (Consumables.slotAt(now) + 1) * Config.CONSUMABLES_RESTOCK_SECONDS
end

function Consumables.secondsLeft(now: number): number
	return Consumables.restockAt(now) - now
end

-- Weather ids a totem may call (everything but Clear).
local function totemWeathers(): { string }
	local out = {}
	for _, id in Config.WEATHER_ORDER do
		if id ~= "Clear" then
			table.insert(out, id)
		end
	end
	return out
end

--[[
	Stock of `slot`: ({ [itemId] = quantity }, weather id the totem calls). Draws happen in
	Config order whatever the quantities are, so editing one item never reshuffles the others.
]]
function Consumables.stock(slot: number): ({ [string]: number }, string)
	local rng = Rng.new(slot * 7919 + 31337)
	rng:float() -- the first draws of a Park-Miller LCG are correlated with nearby seeds
	rng:float()
	local out: { [string]: number } = {}
	for _, def in Config.CONSUMABLES do
		out[def.id] = rng:int(def.minStock, def.maxStock)
	end
	local weathers = totemWeathers()
	return out, weathers[rng:int(1, #weathers)] or "Rain"
end

-- Cash price for this player (x the rebirth multiplier).
function Consumables.price(data: Data, id: string): number?
	local def = Consumables.def(id)
	if not def then
		return nil
	end
	return math.floor(def.price * Economy.rebirthMultiplier(data.rebirths))
end

-- Quantity this player may still buy of `id` in `slot`; 0 when unknown, unsupported or sold out.
function Consumables.remaining(data: Data, slot: number, id: string, weatherOk: boolean): number
	if id == Consumables.TOTEM and not weatherOk then
		return 0
	end
	local stock = Consumables.stock(slot)
	local total = stock[id]
	if not total then
		return 0
	end
	local bought = if data.consumables.slot == slot then (data.consumables.bought[id] or 0) else 0
	return math.max(0, total - bought)
end

-- Records one purchase in `slot` (a new slot forgets the old counts).
function Consumables.record(data: Data, slot: number, id: string)
	if data.consumables.slot ~= slot then
		data.consumables = { slot = slot, bought = {}, held = data.consumables.held }
	end
	data.consumables.bought[id] = (data.consumables.bought[id] or 0) + 1
end

-- The stack of `id` this player holds.
function Consumables.held(data: Data, id: string): number
	return data.consumables.held[id] or 0
end

-- Adds one to the held stack of `id`.
function Consumables.addHeld(data: Data, id: string)
	data.consumables.held[id] = Consumables.held(data, id) + 1
end

-- Takes one off the held stack of `id`; false (nothing changes) when the stack is empty.
function Consumables.takeHeld(data: Data, id: string): boolean
	local n = Consumables.held(data, id)
	if n < 1 then
		return false
	end
	if n > 1 then
		data.consumables.held[id] = n - 1
	else
		data.consumables.held[id] = nil
	end
	return true
end

--[[
	Checks a purchase without changing anything: (true, price) or (false, reason).
	Effects with their own preconditions (spray target, weather request) are checked by the server.
]]
function Consumables.check(data: Data, id: any, now: number, weatherOk: boolean): (boolean, number | string)
	if not Consumables.enabled() then
		return false, "the shop is closed"
	end
	local def = Consumables.def(id)
	if not def then
		return false, "unknown item"
	end
	if id == Consumables.TOTEM and not weatherOk then
		return false, "no weather here"
	end
	if Consumables.remaining(data, Consumables.slotAt(now), def.id, weatherOk) <= 0 then
		return false, "sold out until the restock"
	end
	if Consumables.held(data, def.id) >= Config.CONSUMABLE_HELD_MAX then
		return false, "you can't hold more of these"
	end
	local price = Consumables.price(data, def.id) :: number
	if data.cash < price then
		return false, "not enough cash"
	end
	return true, price
end

-- The fountain luck multiplier: cycle modifier x potion, capped at SPAWN_LUCK_CAP (a modifier alone is never cut).
function Consumables.spawnLuck(modifierLuck: number, potionActive: boolean): number
	if not (potionActive and Consumables.enabled()) then
		return modifierLuck
	end
	return math.max(modifierLuck, math.min(Config.SPAWN_LUCK_CAP, modifierLuck * Config.LUCK_POTION_MULT))
end

-- New potion end time: each potion adds LUCK_POTION_SECONDS to what is left, up to LUCK_POTION_MAX_SECONDS.
function Consumables.extendPotion(untilAt: number, now: number): number
	local left = math.max(0, untilAt - now)
	return now + math.min(Config.LUCK_POTION_MAX_SECONDS, left + Config.LUCK_POTION_SECONDS)
end

function Consumables.potionFull(untilAt: number, now: number): boolean
	return untilAt - now >= Config.LUCK_POTION_MAX_SECONDS
end

--[[
	State.consumables for one player: the slot's items with their price and what is left to
	buy, the restock time and the active luck potion. `weatherOk` = the Weather service takes requests.
]]
function Consumables.view(data: Data, now: number, weatherOk: boolean, potionUntil: number): Types.ConsumablesView?
	if not Consumables.enabled() then
		return nil
	end
	local slot = Consumables.slotAt(now)
	local stock, weather = Consumables.stock(slot)
	local items: { Types.ConsumableItemView } = {}
	for _, def in Config.CONSUMABLES do
		if def.id ~= Consumables.TOTEM or weatherOk then
			table.insert(items, {
				id = def.id,
				name = def.name,
				icon = def.icon,
				text = if def.id == Consumables.TOTEM then `Calls {weather} next.` else def.text,
				price = Consumables.price(data, def.id) :: number,
				left = Consumables.remaining(data, slot, def.id, weatherOk),
				max = stock[def.id] or 0,
				held = Consumables.held(data, def.id),
			})
		end
	end
	local held: { [string]: number } = {}
	for _, def in Config.CONSUMABLES do
		local n = Consumables.held(data, def.id)
		if n > 0 then
			held[def.id] = n
		end
	end
	return {
		slot = slot,
		restockAt = Consumables.restockAt(now),
		items = items,
		luckUntil = if potionUntil > now then potionUntil else 0,
		luckMult = Config.LUCK_POTION_MULT,
		totemWeather = weather,
		held = held,
	}
end

return table.freeze(Consumables)
