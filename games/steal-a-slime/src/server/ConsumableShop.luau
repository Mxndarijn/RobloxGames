--!strict
--[[
	ConsumableShop (server, FEATURES.Consumables)

	`buy` is the `BuyConsumable` action: validates stock, cash and the item's own precondition
	through Shared.Consumables, then charges, records the purchase and applies the effect.
	Nothing is charged when the effect cannot happen. Pure: no Roblox APIs.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Consumables = if Shared then require(Shared.Consumables) else require("../shared/Consumables")
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local Rng = if Shared then require(Shared.Rng) else require("../shared/Rng")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

export type Hooks = {
	rng: Rng.Rng?, -- spray rolls; nil = the world's
	requestWeather: ((id: string) -> boolean)?, -- Weather service; nil = no totem
}

local ConsumableShop = {}

local function spray(world: World, session: Session, slimeId: string?, rng: Rng.Rng): (boolean, string?)
	if slimeId == nil then
		return false, "pick a slime"
	end
	local slime = PlayerData.findSlime(session.data, slimeId)
	if not slime then
		return false, "not your slime"
	end
	if World.isBusy(world, slimeId) then
		return false, "slime is busy"
	end
	local list = Consumables.spray(slime, rng)
	if not list then
		return false, "this slime can't take another mutation"
	end
	Genome.setMutations(slime, list)
	PlayerData.discover(session.data, slime)
	World.notify(world, session.userId, `Sprayed! Now {Genome.displayName(slime)}.`, "good", "Cash")
	return true, nil
end

-- Returns (ok, reason?).
function ConsumableShop.buy(
	world: World,
	session: Session,
	itemId: string,
	slimeId: string?,
	now: number,
	hooks: Hooks
): (boolean, string?)
	local data = session.data
	local weatherOk = hooks.requestWeather ~= nil and Config.FEATURES.Weather == true
	local ok, value = Consumables.check(data, itemId, now, weatherOk)
	if not ok then
		return false, value :: string
	end
	local price = value :: number
	local def = Consumables.def(itemId) :: Config.Consumable
	local slot = Consumables.slotAt(now)
	if itemId == "MutationSpray" then
		-- Applied first because it can fail (bad slime, nothing to add); cash was verified above.
		local good, reason = spray(world, session, slimeId, hooks.rng or world.rng)
		if not good then
			return false, reason
		end
	elseif itemId == "LuckPotion" then
		if Consumables.potionFull(world.potionUntil, now) then
			return false, "the luck potion is already at its longest"
		end
		world.potionUntil = Consumables.extendPotion(world.potionUntil, now)
		World.notify(world, nil, `{def.name}! Better rarity odds in the fountain.`, "good", nil)
		World.markAllDirty(world)
	elseif itemId == Consumables.TOTEM then
		local _, weather = Consumables.stock(slot)
		if not (hooks.requestWeather :: (string) -> boolean)(weather) then
			return false, "the weather can't change that way right now"
		end
		World.notify(world, nil, `Weather Totem: {weather} is next!`, "good", nil)
	end
	assert(PlayerData.spend(data, price), "cash vanished")
	Consumables.record(data, slot, itemId)
	return true, nil
end

return ConsumableShop
