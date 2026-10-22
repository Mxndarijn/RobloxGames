--!strict
--[[
	Shop

	The Speed Coil, bought with Request("BuySpeedCoil") (CONTRACT.md §3), kept on rebirth:
	  * SpeedCoil: bought once for SPEED_COIL_PRICE; while the coil Tool is held,
	    base WalkSpeed is SPEED_COIL_WALK_SPEED (Carry.walkSpeed).
	`view` is State.shop. Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")
local Types = if script then require(script.Parent.Types) else require("./Types")

type Data = PlayerData.Data

local Shop = {}

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

-- Base WalkSpeed: SPEED_COIL_WALK_SPEED only while the owned coil is held (equipped).
-- Carry.walkSpeed applies the carry slowdown to it.
function Shop.walkSpeed(data: Data, coilHeld: boolean?): number
	return if data.speedCoil and coilHeld then Config.SPEED_COIL_WALK_SPEED else Config.BASE_WALK_SPEED
end

function Shop.view(data: Data): Types.ShopView
	return {
		SpeedCoil = { price = Shop.speedCoilCost(data), owned = data.speedCoil },
	}
end

return table.freeze(Shop)
