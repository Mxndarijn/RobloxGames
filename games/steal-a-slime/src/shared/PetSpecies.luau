--!strict
--[[
	PetSpecies

	Which slime rides the follow pet's cloud (contract/pet-species.md). `data.petSpecies` is a species id the player
	picked from their SlimeDex, or nil for Auto (the favourite, else the best owned slime: World.pet). A species can
	be picked when it is a SlimeRoster species with its own kit mesh (KitRequest.kitOf) and the player has found it
	(`data.found`, Dex and bonus entries alike). The pick is looks only: the pet perk stays on the favourite.
	Pure: no Roblox APIs.
]]

local KitRequest = if script then require(script.Parent.KitRequest) else require("./KitRequest")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")
local SlimeRoster = if script then require(script.Parent.SlimeRoster) else require("./SlimeRoster")

type Data = PlayerData.Data

local PetSpecies = {}

PetSpecies.MAX_ID_LENGTH = 32

-- (true, nil) when `id` can ride the cloud for this player; else (false, reason).
function PetSpecies.allowed(data: Data, id: any): (boolean, string?)
	if
		type(id) ~= "string"
		or #id > PetSpecies.MAX_ID_LENGTH
		or SlimeRoster.get(id) == nil
		or KitRequest.kitOf(id) == nil
	then
		return false, "unknown slime"
	end
	if not (data.found and data.found[id] == true) then
		return false, "slime not found yet"
	end
	return true, nil
end

-- The picked species, or nil for Auto (also when the saved pick is no longer allowed).
function PetSpecies.current(data: Data): string?
	local id = data.petSpecies
	if id ~= nil and PetSpecies.allowed(data, id) then
		return id
	end
	return nil
end

-- Picks `id`; nil or "" goes back to Auto.
function PetSpecies.set(data: Data, id: string?): (boolean, string?)
	if id == nil or id == "" then
		data.petSpecies = nil
		return true, nil
	end
	local ok, reason = PetSpecies.allowed(data, id)
	if not ok then
		return false, reason
	end
	data.petSpecies = id
	return true, nil
end

-- Drops a pick that is not allowed (run after `found` is loaded).
function PetSpecies.clean(data: Data)
	data.petSpecies = PetSpecies.current(data)
end

return table.freeze(PetSpecies)
