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

	Exclusive Shop (FEATURES.ExclusiveShop, contract/exclusive-shop.md §3): `grantProduct(userId, productKey)`,
	`setPass(userId, passKey, owned)` and `setPaidRandomAllowed(userId, allowed)` run the real PurchaseService paths
	(Purchases.grant, a "studio-<guid>" receipt id, the save) without a productId or a Robux prompt. They only write
	player attributes ("PcwGrantProduct", "PcwPass" = "<passKey>=true|false", "PcwPaidRandom") that the running
	server's watcher applies, so they work from any Lua context in a Studio playtest, e.g. Studio MCP execute_luau:

	    local Hooks = require(game.ServerScriptService.Server.StudioHooks)
	    local userId = game.Players:GetPlayers()[1].UserId
	    Hooks.grantProduct(userId, "Seat_ufo")
	    Hooks.setPass(userId, "Income2x", true)
	    Hooks.setPaidRandomAllowed(userId, true)
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
local PurchaseService = require(script.Parent.PurchaseService)
local SpeciesDex = require(ReplicatedStorage.Shared.SpeciesDex)
local World = require(script.Parent.World)

local StudioHooks = {}

local GRANT_ATTRIBUTE = "PcwGrantProduct"
local PASS_ATTRIBUTE = "PcwPass"
local PAID_RANDOM_ATTRIBUTE = "PcwPaidRandom"

local function playerOf(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

-- Grants one Exclusive Shop product (a Config.EXCLUSIVE_SHOP.products key) to a player in this Studio server.
function StudioHooks.grantProduct(userId: number, productKey: string): boolean
	local player = playerOf(userId)
	if not player then
		return false
	end
	player:SetAttribute(GRANT_ATTRIBUTE, productKey)
	return true
end

-- Gives or takes a Game Pass (a Config.EXCLUSIVE_SHOP.passes key) for this Studio session.
function StudioHooks.setPass(userId: number, passKey: string, owned: boolean): boolean
	local player = playerOf(userId)
	if not player then
		return false
	end
	player:SetAttribute(PASS_ATTRIBUTE, `{passKey}={if owned then "true" else "false"}`)
	return true
end

-- Overrides the PolicyService answer: whether paid random items (the server Luck Potion) may be sold.
function StudioHooks.setPaidRandomAllowed(userId: number, allowed: boolean): boolean
	local player = playerOf(userId)
	if not player then
		return false
	end
	player:SetAttribute(PAID_RANDOM_ATTRIBUTE, allowed)
	return true
end

-- Applies the Exclusive Shop attributes above through the purchase service, then clears them.
local function applyPurchase(player: Player, purchases: PurchaseService.Service, name: string)
	local value = player:GetAttribute(name)
	if value == nil then
		return
	end
	player:SetAttribute(name, nil)
	local userId = player.UserId
	if name == GRANT_ATTRIBUTE and type(value) == "string" then
		local decision = purchases.grantProduct(userId, value, `studio-{HttpService:GenerateGUID(false)}`)
		print(`[StudioHooks] grantProduct {value}: {decision}`)
	elseif name == PASS_ATTRIBUTE and type(value) == "string" then
		local key, flag = string.match(value, "^(%w+)=(%a+)$")
		if key then
			print(`[StudioHooks] setPass {key} {flag}: {purchases.setPass(userId, key, flag == "true")}`)
		end
	elseif name == PAID_RANDOM_ATTRIBUTE and type(value) == "boolean" then
		print(`[StudioHooks] setPaidRandomAllowed {value}: {purchases.setPaidRandomAllowed(userId, value)}`)
	end
end

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

-- `refresh` pushes the view and State right away after a hook changed a session. `purchases` (the server's
-- PurchaseService) takes the Exclusive Shop hooks.
function StudioHooks.start(
	world: World.World,
	memoryMode: boolean,
	refresh: () -> (),
	purchases: PurchaseService.Service?
)
	if not StudioHooks.active(memoryMode) then
		return
	end
	local function watch(player: Player)
		for _, name in { "PcwGrowth", "PcwPlotSkin", "PcwPetSeat", "PcwPads", "PcwSlimes", "PcwPlotBase" } do
			player:GetAttributeChangedSignal(name):Connect(function()
				pcall(apply, world, player, refresh)
			end)
		end
		if purchases then
			for _, name in { GRANT_ATTRIBUTE, PASS_ATTRIBUTE, PAID_RANDOM_ATTRIBUTE } do
				player:GetAttributeChangedSignal(name):Connect(function()
					task.spawn(function() -- the grant saves, which yields
						local ok, err = pcall(applyPurchase, player, purchases, name)
						if not ok then
							warn(`[StudioHooks] {name}: {err}`)
						end
						refresh()
					end)
				end)
			end
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return StudioHooks
