--!strict
--[[
	StudioHooks (Roblox adapter, Studio + in-memory store only)

	Review hooks for the PC watcher shots. Player attributes change that player's real session data, so WorldView draws
	the result with its own code: "PcwGrowth" (percent) the growth of the pad 1 slime, "PcwPlotSkin" (a skin id) finds
	that skin's slimes and equips it (the tower turns to its theme), "PcwPads" (a count) the unlocked pads (the upper
	jars build). ServerLoop's `pinClock` covers the
	Lighting "PcwClock" hook. `start` does nothing outside Studio or with a real DataStore: never active in live
	servers, never writes a real save.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Genome = require(ReplicatedStorage.Shared.Genome)
local PlayerData = require(ReplicatedStorage.Shared.PlayerData)
local PlotSkins = require(ReplicatedStorage.Shared.PlotSkins)
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
	local skin = PlotSkins.get(player:GetAttribute("PcwPlotSkin"))
	if skin then
		for _, id in PlotSkins.slimes(skin) do
			profile.found[id] = true
		end
		PlotSkins.equip(profile, skin.id)
	end
	local pads = player:GetAttribute("PcwPads")
	if type(pads) == "number" then
		profile.padsUnlocked = math.clamp(math.floor(pads), 1, Config.PADS_MAX)
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
		for _, name in { "PcwGrowth", "PcwPlotSkin", "PcwPads" } do
			player:GetAttributeChangedSignal(name):Connect(function()
				pcall(apply, world, player, refresh)
			end)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return StudioHooks
