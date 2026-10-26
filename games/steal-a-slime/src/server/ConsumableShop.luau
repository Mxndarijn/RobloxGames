--!strict
--[[
	ConsumableShop (server, FEATURES.Consumables)

	`buy` is the `BuyConsumable` action: validates stock, cash and the held-stack cap through
	Shared.Consumables, then charges, records the purchase and adds one to the held stack. Nothing is applied.
	`use` is the `UseConsumable` action: validates the item and that the player holds one, applies the effect
	(the potion / totem code below) and only then takes one off the stack, so a refused
	effect costs nothing. Pure: no Roblox APIs.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Consumables = if Shared then require(Shared.Consumables) else require("../shared/Consumables")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

export type Hooks = {
	requestWeather: ((id: string) -> boolean)?, -- Weather service; nil = no totem
}

local ConsumableShop = {}

-- Returns (ok, reason?).
function ConsumableShop.buy(
	world: World,
	session: Session,
	itemId: string,
	_slimeId: string?, -- kept for the BuyConsumable arguments: the target is chosen when the item is used
	now: number,
	hooks: Hooks
): (boolean, string?)
	local data = session.data
	local weatherOk = hooks.requestWeather ~= nil and Config.FEATURES.Weather == true
	local ok, value = Consumables.check(data, itemId, now, weatherOk)
	if not ok then
		return false, value :: string
	end
	assert(PlayerData.spend(data, value :: number), "cash vanished")
	Consumables.record(data, Consumables.slotAt(now), itemId)
	Consumables.addHeld(data, itemId)
	local def = Consumables.def(itemId) :: Config.Consumable
	World.notify(world, session.userId, `{def.name} added to your bag.`, "good", "Bag")
	return true, nil
end

-- Returns (ok, reason?).
function ConsumableShop.use(
	world: World,
	session: Session,
	itemId: string,
	_slimeId: string?,
	now: number,
	hooks: Hooks
): (boolean, string?)
	local data = session.data
	if not Consumables.enabled() then
		return false, "the shop is closed"
	end
	local def = Consumables.def(itemId)
	if not def then
		return false, "unknown item"
	end
	if Consumables.held(data, itemId) < 1 then
		return false, "you don't have any"
	end
	if itemId == "LuckPotion" then
		if Consumables.potionFull(world.potionUntil, now) then
			return false, "the luck potion is already at its longest"
		end
		world.potionUntil = Consumables.extendPotion(world.potionUntil, now)
		World.notify(world, nil, `{def.name}! Better rarity odds in the fountain.`, "good", nil)
		World.markAllDirty(world)
	elseif itemId == Consumables.TOTEM then
		local _, weather = Consumables.stock(Consumables.slotAt(now))
		if not (hooks.requestWeather and Config.FEATURES.Weather == true) then
			return false, "no weather here"
		end
		if not hooks.requestWeather(weather) then
			return false, "the weather can't change that way right now"
		end
		World.notify(world, nil, `Weather Totem: {weather} is next!`, "good", nil)
	end
	assert(Consumables.takeHeld(data, itemId), "stack vanished")
	return true, nil
end

return ConsumableShop
