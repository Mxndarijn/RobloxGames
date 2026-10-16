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
-- "string?" means the argument may be nil.
export type ActionDef = { args: { string } }

local Remotes = {}

Remotes.FOLDER = Constants.REMOTES_FOLDER

Remotes.DEFINITIONS = table.freeze({
	table.freeze({ name = Constants.REQUEST, class = "RemoteFunction", direction = "ClientToServer" } :: RemoteDef),
	table.freeze({ name = Constants.STATE, class = "RemoteEvent", direction = "ServerToClient" } :: RemoteDef),
	table.freeze({ name = Constants.NOTIFY, class = "RemoteEvent", direction = "ServerToClient" } :: RemoteDef),
	table.freeze({ name = Constants.LEADERBOARD, class = "RemoteEvent", direction = "ServerToClient" } :: RemoteDef),
} :: { RemoteDef })

Remotes.ACTIONS = table.freeze({
	Merge = table.freeze({ args = { "string", "string" } }), -- slimeIdA, slimeIdB
	Lock = table.freeze({ args = {} }),
	Rebirth = table.freeze({ args = {} }),
	Sell = table.freeze({ args = { "string" } }), -- slimeId
	Favorite = table.freeze({ args = { "string?" } }), -- slimeId, nil clears
	BuyPad = table.freeze({ args = {} }),
	Daily = table.freeze({ args = {} }),
	BuyLockUpgrade = table.freeze({ args = {} }),
	BuySpeedCoil = table.freeze({ args = {} }),
	BuyUpgrade = table.freeze({ args = { "string" } }), -- Config.UPGRADES id (CONTRACT.md §8.1)
	Slap = table.freeze({ args = { "number" } }), -- target UserId
	BuyEgg = table.freeze({ args = {} }), -- Mystery Egg: cash only, hatches into a slime on your plot
	Drop = table.freeze({ args = {} }),
	Appraise = table.freeze({ args = { "string", "string" } }), -- slimeId, "mutation" | "size" (FEATURES.Appraise)
	Redeem = table.freeze({ args = { "code" } }), -- typed code text (Codes.normalize on the server)
	EquipPlotSkin = table.freeze({ args = { "string" } }), -- Config.PLOT_SKINS id (FEATURES.PlotSkins, CONTRACT.md §13)
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
