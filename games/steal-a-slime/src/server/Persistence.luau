--!strict
--[[
	Persistence (Roblox adapter)

	The save wiring of the server entry. At boot it picks the backend: the in-memory store when workspace
	attribute DataStoreMode = "Memory" (or when no DataStore can be opened), else the real DataStore plus the
	leaderboard OrderedDataStore. It keeps workspace.DataStoreStatus current: "Ok" | "Memory" | "Unavailable"
	(nothing saves) | "Error" (the last load / save failed), warning on each change.
	Loads and saves go through DataService (session-locked, retried); a Studio player whose load fails gets an
	unsaved fresh profile. `pending` counts saves in flight so BindToClose can wait for them.
	No gameplay rules here.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local DataService = require(script.Parent.DataService)
local Leaderboard = require(script.Parent.Leaderboard)
local PlayerData = require(ReplicatedStorage.Shared.PlayerData)
local World = require(script.Parent.World)

export type Persistence = {
	data: DataService.DataService,
	memoryMode: boolean,
	orderedStore: OrderedDataStore?, -- global leaderboard; nil in memory mode
	unsaved: { [number]: boolean }, -- Studio fallback profiles: never written
	pending: number, -- saves in flight
}

local Persistence = {}

local function setStatus(status: string, reason: string?)
	if workspace:GetAttribute(Constants.DATASTORE_STATUS_ATTRIBUTE) == status then
		return
	end
	workspace:SetAttribute(Constants.DATASTORE_STATUS_ATTRIBUTE, status)
	if status ~= "Ok" and status ~= "Memory" then
		warn(`[Server] DataStoreStatus = {status}: {reason or "?"}`)
	end
end

function Persistence.new(): Persistence
	local memoryMode = workspace:GetAttribute(Constants.DATASTORE_MODE_ATTRIBUTE) == "Memory"
	local storeOk, dataStore = pcall(function()
		return DataStoreService:GetDataStore(Constants.DATASTORE_NAME)
	end)
	if memoryMode then
		setStatus("Memory")
	elseif not storeOk then
		setStatus("Unavailable", `{dataStore}; using the in-memory store, progress will NOT save`)
		memoryMode = true
	else
		setStatus("Ok")
	end
	local backend: DataService.Backend
	local orderedStore: OrderedDataStore? = nil
	if memoryMode then
		backend = DataService.memoryBackend()
	else
		backend = {
			update = function(key: string, transform: (any) -> any?): any
				return dataStore:UpdateAsync(key, function(old: any)
					return transform(old)
				end)
			end,
		}
		orderedStore = DataStoreService:GetOrderedDataStore(Constants.LEADERBOARD_STORE)
	end
	return {
		data = DataService.new({
			backend = backend,
			jobId = if game.JobId ~= "" then game.JobId else `studio-{HttpService:GenerateGUID(false)}`,
			now = os.time,
			wait = function(seconds: number)
				task.wait(seconds)
			end,
		}),
		memoryMode = memoryMode,
		orderedStore = orderedStore,
		unsaved = {},
		pending = 0,
	}
end

--[[
	Loads `userId`'s save. Returns the data, or nil plus the kick message. `present()` says whether the player
	is still in the server: one who left while loading gets the session lock released and (nil, nil).
]]
function Persistence.load(p: Persistence, userId: number, present: () -> boolean): (PlayerData.Data?, string?)
	local ok, result = DataService.load(p.data, userId)
	if not present() then
		if ok then
			DataService.save(p.data, userId, result :: PlayerData.Data, true) -- left while loading: release
		end
		return nil, nil
	end
	if not p.memoryMode then
		if ok then
			setStatus("Ok")
		elseif result == "DataStore error" then
			setStatus("Error", `load failed for {userId}`)
		end
	end
	if ok then
		return result :: PlayerData.Data, nil
	end
	if RunService:IsStudio() then
		warn(`[Server] DataStore unavailable ({result}); using an unsaved profile`)
		p.unsaved[userId] = true
		return PlayerData.new(), nil
	end
	return nil, `Couldn't load your slimes: {result}. Please rejoin.`
end

-- True when this server may not write `userId`'s save (a newer or unreadable record).
function Persistence.readOnly(p: Persistence, userId: number): boolean
	return DataService.readOnly(p.data, userId) ~= nil
end

-- True when this server writes `userId`'s progress: not read-only, not taken over by another server and not a
-- Studio fallback profile. A theft needs both players' saves (World.canSave).
function Persistence.canSave(p: Persistence, userId: number): boolean
	return not p.unsaved[userId] and DataService.canSave(p.data, userId)
end

-- Saves (yields); `release` drops the session lock. Also ranks the player on the global board.
function Persistence.save(p: Persistence, userId: number, playerData: PlayerData.Data, release: boolean)
	if p.unsaved[userId] then
		if release then
			p.unsaved[userId] = nil
		end
		return
	end
	p.pending += 1
	local readOnly = Persistence.readOnly(p, userId)
	local ok, reason = DataService.save(p.data, userId, playerData, release)
	if not ok then
		warn(`[Server] save failed for {userId}: {reason}`)
		if reason == "DataStore error" then
			setStatus("Error", `save failed for {userId}`)
		end
	elseif not p.memoryMode then
		setStatus("Ok")
	end
	local store = p.orderedStore
	if store and not readOnly then -- a read-only session's progress is not saved, so it doesn't rank either
		pcall(function()
			store:SetAsync(DataService.key(userId), Leaderboard.storeValue(playerData))
		end)
	end
	p.pending -= 1
end

-- Starts a save of every session, each in its own thread.
function Persistence.saveAll(p: Persistence, world: World.World, release: boolean)
	for userId, session in world.sessions do
		task.spawn(Persistence.save, p, userId, session.data, release)
	end
end

-- Waits until no save is in flight or `timeout` seconds pass.
function Persistence.waitForSaves(p: Persistence, timeout: number)
	local deadline = os.clock() + timeout
	while p.pending > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end

return Persistence
