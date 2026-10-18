--!strict
--[[
	StudioHooks (Roblox adapter, Studio + in-memory store only)

	Review hooks for the PC watcher shots. The Player attribute "PcwGrowth" (percent)
	changes that player's real session data (growth of the pad 1 slime), so WorldView draws the result with its own code. ServerLoop's `pinClock` covers the
	Lighting "PcwClock" hook. `start` does nothing outside Studio or with a real DataStore: never active in live
	servers, never writes a real save.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Genome = require(ReplicatedStorage.Shared.Genome)
local PlayerData = require(ReplicatedStorage.Shared.PlayerData)
local World = require(script.Parent.World)

local StudioHooks = {}

-- True only in Studio on the in-memory store.
function StudioHooks.active(memoryMode: boolean): boolean
	return RunService:IsStudio() and memoryMode
end

local function apply(world: World.World, player: Player, refresh: () -> ())
	local session = World.session(world, player.UserId)
	if not session then
		return
	end
	local profile = session.data
	local percent = player:GetAttribute("PcwGrowth")
	if type(percent) == "number" then
		local slime: any = PlayerData.slimeOnPad(profile, 1)
		if slime == nil then
			local fresh: any = Genome.generate(world.rng, { id = HttpService:GenerateGUID(false), tier = 1 })
			PlayerData.addSlime(profile, fresh, 1)
			slime = fresh
		end
		slime.growth = math.clamp(percent, 0, 100) / 100
	end
	World.markDirty(session)
	refresh()
end

-- `refresh` pushes the view and State right away after a hook changed a session.
function StudioHooks.start(world: World.World, memoryMode: boolean, refresh: () -> ())
	if not StudioHooks.active(memoryMode) then
		return
	end
	local function watch(player: Player)
		player:GetAttributeChangedSignal("PcwGrowth"):Connect(function()
			pcall(apply, world, player, refresh)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return StudioHooks
