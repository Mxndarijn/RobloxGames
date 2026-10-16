--!strict
--[[
	Shop

	Permanent upgrades bought with Request("BuyLockUpgrade") /
	Request("BuySpeedCoil") (CONTRACT.md §3), kept on rebirth:
	  * LockUpgrade: LOCK_UPGRADE_MAX levels, level n costs
	    LOCK_UPGRADE_COSTS[n]; each adds LOCK_UPGRADE_SECONDS to every lock
	    (Steal.lockDuration).
	  * SpeedCoil: bought once for SPEED_COIL_PRICE; base WalkSpeed is
	    SPEED_COIL_WALK_SPEED (the carry slowdown applies to it, Carry.walkSpeed).
	`view` is State.shop. Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local MysteryEgg = if script then require(script.Parent.MysteryEgg) else require("./MysteryEgg")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")
local Types = if script then require(script.Parent.Types) else require("./Types")

type Data = PlayerData.Data

local Shop = {}

-- Price of the next lock upgrade level, or nil when maxed.
function Shop.lockUpgradeCost(level: number): number?
	if level >= Config.LOCK_UPGRADE_MAX then
		return nil
	end
	return Config.LOCK_UPGRADE_COSTS[level + 1]
end

-- Returns (ok, priceOrReason).
function Shop.buyLockUpgrade(data: Data): (boolean, number | string)
	local cost = Shop.lockUpgradeCost(data.lockLevel)
	if not cost then
		return false, "locks are already maxed"
	end
	if not PlayerData.spend(data, cost) then
		return false, "not enough cash"
	end
	data.lockLevel += 1
	return true, cost
end

function Shop.speedCoilCost(data: Data): number?
	return if data.speedCoil then nil else Config.SPEED_COIL_PRICE
end

-- Returns (ok, priceOrReason).
function Shop.buySpeedCoil(data: Data): (boolean, number | string)
	local cost = Shop.speedCoilCost(data)
	if not cost then
		return false, "you already own the Speed Coil"
	end
	if not PlayerData.spend(data, cost) then
		return false, "not enough cash"
	end
	data.speedCoil = true
	return true, cost
end

-- Base WalkSpeed (Speed Coil included); Carry.walkSpeed applies the carry slowdown to it.
function Shop.walkSpeed(data: Data): number
	return if data.speedCoil then Config.SPEED_COIL_WALK_SPEED else Config.BASE_WALK_SPEED
end

function Shop.view(data: Data): Types.ShopView
	local egg = if Config.FEATURES.MysteryEgg then { price = MysteryEgg.price(data) } else nil
	return {
		MysteryEgg = egg,
		LockUpgrade = {
			price = Shop.lockUpgradeCost(data.lockLevel),
			level = data.lockLevel,
			maxLevel = Config.LOCK_UPGRADE_MAX,
		},
		SpeedCoil = { price = Shop.speedCoilCost(data), owned = data.speedCoil },
	}
end

return table.freeze(Shop)
