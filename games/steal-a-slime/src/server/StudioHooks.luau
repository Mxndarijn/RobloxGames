--!strict
--[[
	StudioHooks (Roblox adapter, Studio + in-memory store only)

	Review hooks for the PC watcher shots. Player attributes change that player's real session data, so WorldView draws
	the result with its own code: "PcwGrowth" (percent) the growth of the pad 1 slime, "PcwPlotSkin" (a skin id) finds
	that skin's slimes and equips it (the tower turns to its theme), "PcwPetSeat" (a seat id) meets a free seat's goal and
	equips it (the follow pet rides it), "PcwPads" (a count) the unlocked pads (the upper
	jars build), "PcwSlimes" (a tier) puts three slimes of that rarity on free pads (a merge vat load), "PcwPlotBase"
	(a base id) raises the rebirths to that base's gate and equips it (CONTRACT.md §44). ServerLoop's
	`pinClock` covers the
	Lighting "PcwClock" hook. `start` does nothing outside Studio or with a real DataStore: never active in live
	servers, never writes a real save.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Genome = require(ReplicatedStorage.Shared.Genome)
local PetSeats = require(ReplicatedStorage.Shared.PetSeats)
local PlayerData = require(ReplicatedStorage.Shared.PlayerData)
local PlotBases = require(ReplicatedStorage.Shared.PlotBases)
local PlotSkins = require(ReplicatedStorage.Shared.PlotSkins)
local SpeciesDex = require(ReplicatedStorage.Shared.SpeciesDex)
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
	local base = PlotBases.get(player:GetAttribute("PcwPlotBase"))
	if base then
		profile.rebirths = math.max(profile.rebirths, base.rebirths or 0)
		PlotBases.equip(profile, base.id)
	end
	local seat = PetSeats.get(player:GetAttribute("PcwPetSeat"))
	if seat then
		-- Meet a free unlock's goal (merges, or 80 % of the SlimeDex), then wear it; Exclusives stay locked.
		if seat.unlock.kind == "merges" then
			profile.stats.merges = math.max(profile.stats.merges, seat.unlock.count or 0)
		elseif seat.unlock.kind == "dex" then
			local need = math.ceil(SpeciesDex.TOTAL * (seat.unlock.percent or 0) / 100)
			for i, entry in SpeciesDex.ENTRIES do
				if i <= need then
					profile.found[entry.id] = true
				end
			end
		end
		PetSeats.equip(profile, seat.id)
	end
	local pads = player:GetAttribute("PcwPads")
	if type(pads) == "number" then
		profile.padsUnlocked = math.clamp(math.floor(pads), 1, Config.PADS_MAX)
	end
	local tier = player:GetAttribute("PcwSlimes")
	if type(tier) == "number" then
		for _ = 1, 3 do
			local fresh: any = Genome.generate(world.rng, { id = HttpService:GenerateGUID(false), tier = tier })
			PlayerData.addSlime(profile, fresh)
		end
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
		for _, name in { "PcwGrowth", "PcwPlotSkin", "PcwPetSeat", "PcwPads", "PcwSlimes", "PcwPlotBase" } do
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
