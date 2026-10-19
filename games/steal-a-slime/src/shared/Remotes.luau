--!strict
--[[
	Remotes

	Single source of truth for every remote under ReplicatedStorage.Remotes
	(see CONTRACT.md §3). The definition tables are pure data and load under
	Lune; `setup` (server) and `get` (client) touch Roblox APIs only when called.
]]

local Constants = if script then require(script.Parent.Constants) else require("./Constants")

export type RemoteClass = "RemoteEvent" | "RemoteFunction"
export type Direction = "ClientToServer" | "ServerToClient"
export type RemoteDef = { name: string, class: RemoteClass, direction: Direction }

-- Argument type names for each `Request` action, in call order.
-- "string?" means the argument may be nil; "number?" / "vector3?" likewise. "vector3" = a finite Roblox Vector3.
-- "string" is an id (Validate.slimeId); "code" is free text up to 64 chars; "hotbar" is a string up to
-- HotbarOrder.MAX_LENGTH whose keys HotbarOrder.parse checks.
export type ActionDef = { args: { string } }

local Remotes = {}

Remotes.FOLDER = Constants.REMOTES_FOLDER

Remotes.DEFINITIONS = table.freeze({
	table.freeze({ name = Constants.REQUEST, class = "RemoteFunction", direction = "ClientToServer" } :: RemoteDef),
	table.freeze({ name = Constants.STATE, class = "RemoteEvent", direction = "ServerToClient" } :: RemoteDef),
	table.freeze({ name = Constants.NOTIFY, class = "RemoteEvent", direction = "ServerToClient" } :: RemoteDef),
	table.freeze({ name = Constants.LEADERBOARD, class = "RemoteEvent", direction = "ServerToClient" } :: RemoteDef),
	table.freeze({ name = Constants.PVP_EVENT, class = "RemoteEvent", direction = "ServerToClient" } :: RemoteDef), -- FEATURES.PvP only fires (CONTRACT.md §26.1)
	table.freeze({ name = Constants.SHOP_EVENT, class = "RemoteEvent", direction = "ServerToClient" } :: RemoteDef), -- FEATURES.WorldShops only fires (CONTRACT.md §27.4)
} :: { RemoteDef })

Remotes.ACTIONS = table.freeze({
	Merge = table.freeze({ args = { "string", "string" } }), -- slimeIdA, slimeIdB
	Merge3 = table.freeze({ args = { "string", "string", "string" } }), -- three slime ids (FEATURES.MergeVat3, CONTRACT.md §21)
	AutoMerge = table.freeze({ args = { "number" } }), -- rarity bit mask, bit t - 1 = rarity t (CONTRACT.md §21.1)
	KeepSlime = table.freeze({ args = { "string", "boolean" } }), -- slime id, keep (CONTRACT.md §21.1)
	Lock = table.freeze({ args = {} }),
	Rebirth = table.freeze({ args = {} }),
	Sell = table.freeze({ args = { "string" } }), -- slimeId
	Favorite = table.freeze({ args = { "string?" } }), -- slimeId, nil clears
	BuyPad = table.freeze({ args = {} }),
	Daily = table.freeze({ args = {} }),
	ClaimQuest = table.freeze({ args = { "number" } }), -- daily quest slot 1..Config.DAILY_QUESTS.count (Quests.claim)
	BuyLockUpgrade = table.freeze({ args = {} }),
	BuySpeedCoil = table.freeze({ args = {} }),
	BuyUpgrade = table.freeze({ args = { "string" } }), -- Config.UPGRADES id (CONTRACT.md §8.1)
	Drop = table.freeze({ args = {} }),
	Appraise = table.freeze({ args = { "string", "string" } }), -- slimeId, "size"
	Redeem = table.freeze({ args = { "code" } }), -- typed code text (Codes.normalize on the server)
	EquipPlotSkin = table.freeze({ args = { "string" } }), -- Config.PLOT_SKINS id (FEATURES.PlotSkins, CONTRACT.md §15)
	BuyConsumable = table.freeze({ args = { "string", "string?" } }), -- Config.CONSUMABLES id, slimeId (ignored: buying only adds to the held stack) (FEATURES.Consumables)
	UseConsumable = table.freeze({ args = { "string", "string?" } }), -- held Config.CONSUMABLES id, unused slot (string?): applies the effect, stack -1 (FEATURES.Consumables)
	SetAudioSettings = table.freeze({ args = { "number", "number", "boolean" } }), -- musicVolume, sfxVolume (clamped 0..1), muted (FEATURES.Audio, CONTRACT.md §8.9c)
	BuyPvpItem = table.freeze({ args = { "string" } }), -- Config.PVP_TOOLS id (FEATURES.PvP, CONTRACT.md §26)
	EquipPvpItem = table.freeze({ args = { "string?" } }), -- owned Config.PVP_TOOLS id, nil unequips (FEATURES.PvP)
	UsePvpItem = table.freeze({ args = { "string", "number?", "vector3?" } }), -- itemId, targetUserId, aim point (FEATURES.PvP)
	OpenShop = table.freeze({ args = { "string" } }), -- shopId "ItemShop" | "UpgradeShop" (FEATURES.WorldShops, CONTRACT.md §27)
	CloseShop = table.freeze({ args = {} }), -- clears the open shop
	ShopBuy = table.freeze({ args = { "string", "string", "string?" } }), -- shopId, itemId, unused slot (string?); delegates to the item's existing buy action
	SetHotbar = table.freeze({ args = { "hotbar" } }), -- order: up to 9 slot keys joined by "," ("" = empty slot) (HotbarOrder, CONTRACT.md §3)
	Sync = table.freeze({ args = {} }), -- server re-sends State
} :: { [string]: ActionDef })

function Remotes.definition(name: string): RemoteDef?
	for _, def in Remotes.DEFINITIONS do
		if def.name == name then
			return def
		end
	end
	return nil
end

-- Server only: creates ReplicatedStorage.Remotes and every remote. Idempotent.
function Remotes.setup(): Folder
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local folder = ReplicatedStorage:FindFirstChild(Remotes.FOLDER) :: Folder?
	if not folder then
		local created = Instance.new("Folder")
		created.Name = Remotes.FOLDER
		created.Parent = ReplicatedStorage
		folder = created
	end
	assert(folder, "Remotes folder missing")
	for _, def in Remotes.DEFINITIONS do
		if not folder:FindFirstChild(def.name) then
			local remote = Instance.new(def.class)
			remote.Name = def.name
			remote.Parent = folder
		end
	end
	return folder
end

-- Client or server: waits for a remote created by `setup`.
function Remotes.get(name: string): Instance
	assert(Remotes.definition(name), `unknown remote {name}`)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	return ReplicatedStorage:WaitForChild(Remotes.FOLDER):WaitForChild(name)
end

return table.freeze(Remotes)
