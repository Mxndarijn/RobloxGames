--!strict
--[[
	PlayerAttributes (Roblox adapter)

	Player attributes that follow the World right away, not only on the 0.1 s view tick:
	  * `Carrying` (and `Stealing` with FEATURES.StealAlerts): pickup, drop, deposit, escape, death;
	  * `OpenShop`: the session's open world shop, nil = closed;
	  * `CarryTrail` / `BatSkin` (FEATURES.ExclusiveShop): the equipped carry trail and Bat skin (Purchases.worn).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Carry = require(script.Parent.Carry)
local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Purchases = require(script.Parent.Purchases)
local World = require(script.Parent.World)
local WorldView = require(script.Parent.WorldView)

local PlayerAttributes = {}

function PlayerAttributes.syncCarrying(world: World.World)
	for _, player in Players:GetPlayers() do
		WorldView.setCarrying(player, Carry.carryingId(world, player.UserId))
		if Config.FEATURES.StealAlerts then
			local session = World.session(world, player.UserId)
			local stealing = session ~= nil and session.carry ~= nil and session.carry.kind == "stolen"
			local value = if stealing then true else nil
			if player:GetAttribute(Constants.STEALING_ATTRIBUTE) ~= value then
				player:SetAttribute(Constants.STEALING_ATTRIBUTE, value)
			end
		end
	end
end

function PlayerAttributes.syncOpenShop(world: World.World, player: Player)
	local session = World.session(world, player.UserId)
	local value = session and session.openShop
	if player:GetAttribute(Constants.OPEN_SHOP_ATTRIBUTE) ~= value then
		player:SetAttribute(Constants.OPEN_SHOP_ATTRIBUTE, value)
	end
end

function PlayerAttributes.syncCosmetics(world: World.World, player: Player)
	local session = World.session(world, player.UserId)
	local trail, skin = nil, nil
	if session then
		trail, skin = Purchases.worn(session)
	end
	if player:GetAttribute(Constants.CARRY_TRAIL_ATTRIBUTE) ~= trail then
		player:SetAttribute(Constants.CARRY_TRAIL_ATTRIBUTE, trail)
	end
	if player:GetAttribute(Constants.BAT_SKIN_ATTRIBUTE) ~= skin then
		player:SetAttribute(Constants.BAT_SKIN_ATTRIBUTE, skin)
	end
end

return PlayerAttributes
