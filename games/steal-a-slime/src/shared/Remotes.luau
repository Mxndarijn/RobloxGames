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
-- HotbarOrder.MAX_LENGTH whose keys HotbarOrder.parse checks. "cosmetic" is "" or an id (Validate.slimeId). "target?"
-- is nil, an id (Validate.slimeId) or a finite number.
export type ActionDef = { args: { string } }

local Remotes = {}

Remotes.FOLDER = Constants.REMOTES_FOLDER

Remotes.DEFINITIONS = table.freeze({
	table.freeze({ name = Constants.REQUEST, class = "RemoteFunction", direction = "ClientToServer" } :: RemoteDef),
	table.freeze({ name = Constants.STATE, class = "RemoteEvent", direction = "ServerToClient" } :: RemoteDef),
	table.freeze({ name = Constants.NOTIFY, class = "RemoteEvent", direction = "ServerToClient" } :: RemoteDef),
	table.freeze({ name = Constants.LEADERBOARD, class = "RemoteEvent", direction = "ServerToClient" } :: RemoteDef),
	table.freeze({ name = Constants.PVP_EVENT, class = "RemoteEvent", direction = "ServerToClient" } :: RemoteDef), -- FEATURES.PvP only fires (CONTRACT.md §26.1)
	table.freeze({ name = Constants.SHOP_EVENT, class = "RemoteEvent", direction = "ServerToClient" } :: RemoteDef), -- CONTRACT.md §27.4
	table.freeze({ name = Constants.CLAW_SHOW, class = "RemoteEvent", direction = "ServerToClient" } :: RemoteDef), -- contract/exclusive-shop.md §7.2
} :: { RemoteDef })

Remotes.ACTIONS = table.freeze({
	VatAdd = table.freeze({ args = { "string" } }), -- slimeId: Move mode placed this pad slime in the merge vat (CONTRACT.md §21)
	VatRemove = table.freeze({ args = { "string" } }), -- slimeId: take it out of the vat (it stays on its pad)
	VatStart = table.freeze({ args = {} }), -- start brewing the full vat
	VatCancel = table.freeze({ args = {} }), -- stop the brew; the slimes stay in the vat
	VatCollect = table.freeze({ args = {} }), -- merge a finished brew onto the first input's pad
	Lock = table.freeze({ args = {} }),
	ToggleFriends = table.freeze({ args = {} }), -- flips the owner's friends switch (FEATURES.FriendsInBase)
	Rebirth = table.freeze({ args = {} }),
	Sell = table.freeze({ args = { "string" } }), -- slimeId
	Favorite = table.freeze({ args = { "string?" } }), -- slimeId, nil clears
	MoveSlime = table.freeze({ args = { "string", "number" } }), -- slimeId, target pad
	HatchEgg = table.freeze({ args = { "string" } }), -- slime id of the owner's ready Mystery Egg (contract/mystery-egg.md)
	BuyPad = table.freeze({ args = {} }),
	Daily = table.freeze({ args = {} }),
	SkipTutorial = table.freeze({ args = {} }), -- ends the tutorial (Guide panel)
	ReplayTutorial = table.freeze({ args = {} }), -- starts the tutorial again from its first step (Settings menu)
	ClaimQuest = table.freeze({ args = { "number" } }), -- daily quest slot 1..Config.DAILY_QUESTS.count (Quests.claim)
	BuySpeedCoil = table.freeze({ args = {} }),
	BuyUpgrade = table.freeze({ args = { "string" } }), -- Config.UPGRADES id (CONTRACT.md §8.1)
	Drop = table.freeze({ args = {} }),
	Redeem = table.freeze({ args = { "code" } }), -- typed code text (Codes.normalize on the server)
	EquipPlotSkin = table.freeze({ args = { "string" } }), -- Config.PLOT_SKINS id (FEATURES.PlotSkins, CONTRACT.md §15)
	EquipPlotBase = table.freeze({ args = { "string" } }), -- Config.PLOT_BASES id (FEATURES.BaseShapes, CONTRACT.md §44)
	EquipPetSeat = table.freeze({ args = { "string" } }), -- Config.PET_SEATS id (contract/pet-seats.md)
	BuyConsumable = table.freeze({ args = { "string", "string?" } }), -- Config.CONSUMABLES id, slimeId (ignored: buying only adds to the held stack) (FEATURES.Consumables)
	UseConsumable = table.freeze({ args = { "string", "string?" } }), -- held Config.CONSUMABLES id, unused slot (string?): applies the effect, stack -1 (FEATURES.Consumables)
	SetSettings = table.freeze({ args = { "settings" } }), -- { [settingId] = value }: changed Settings menu values (PlayerSettings, CONTRACT.md §8.9c)
	BuyPvpItem = table.freeze({ args = { "string" } }), -- Config.PVP_TOOLS id (FEATURES.PvP, CONTRACT.md §26)
	EquipPvpItem = table.freeze({ args = { "string?" } }), -- owned Config.PVP_TOOLS id, nil unequips (FEATURES.PvP)
	UsePvpItem = table.freeze({ args = { "string", "number?", "vector3?", "boolean?" } }), -- itemId, targetUserId, aim point, charged (held: power punch, mega confetti, fireworks volley) (FEATURES.PvP)
	OpenShop = table.freeze({ args = { "string" } }), -- shopId "ItemShop" | "UpgradeShop" (CONTRACT.md §27)
	CloseShop = table.freeze({ args = {} }), -- clears the open shop
	ShopBuy = table.freeze({ args = { "string", "string", "string?" } }), -- shopId, itemId, unused slot (string?); delegates to the item's existing buy action
	AimHatch = table.freeze({ args = { "string" } }), -- the pad egg id a "Hatch now" purchase is for, sent just before the Roblox prompt
	UseCredit = table.freeze({ args = { "string", "target?" } }), -- "brew" | "hatch" | "lockBreak", target: the hatch egg id (nil = the one closest to ready) or the locked base's plot index: spends a saved Exclusive Shop credit
	AimSnack = table.freeze({ args = { "string" } }), -- slimeId: the slime the next GrowthSnack purchase feeds
	EquipStyle = table.freeze({ args = { "string", "cosmetic" } }), -- "fanfare" | "lockStyle" | "hat", an owned id ("" = none)
	ClaimPerk = table.freeze({ args = { "string" } }), -- "vipPotion": a VIP's free server Luck Potion of the day
	EquipTrail = table.freeze({ args = { "cosmetic" } }), -- owned Config.EXCLUSIVE_SHOP.trails id, "" = none
	EquipBatSkin = table.freeze({ args = { "cosmetic" } }), -- owned Config.EXCLUSIVE_SHOP.batSkins id, "" = the default Bat
	AimLockBreak = table.freeze({ args = { "number" } }), -- plot index of the locked base the next LockBreak purchase opens, sent just before the Roblox prompt
	AimGift = table.freeze({ args = { "string", "number" } }), -- cosmetic product key (Seat_* / Trail_* / BatSkin_*), target userId: who the next Gift_<key> purchase is for
	SendGift = table.freeze({ args = { "string", "number" } }), -- product key of an unsent gift, target userId: sends it
	SetHotbar = table.freeze({ args = { "hotbar" } }), -- order: up to 9 slot keys joined by "," ("" = empty slot) (HotbarOrder, CONTRACT.md §3)
	RequestKits = table.freeze({ args = { "kits" } }), -- species: up to KitRequest.MAX species ids joined by ","; their kit meshes replicate to this player only (KitRequest, CONTRACT.md §3)
	Admin = table.freeze({ args = { "string", "string?", "number?" } }), -- AdminCommands id, an id argument, a number argument (contract/admin-menu.md)
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
