--!strict
--[[
	Persistence (Roblox adapter)

	The save wiring of the server entry. At boot it picks the backend: the in-memory store when workspace
	attribute DataStoreMode = "Memory" (or when no DataStore can be opened), else the real DataStore plus one
	OrderedDataStore per global board (Leaderboards.BOARDS; the weekly board opens a new store each week). It keeps workspace.DataStoreStatus current: "Ok" | "Memory" | "Unavailable"
	(nothing saves) | "Error" (the last load / save failed), warning on each change.
	Loads and saves go through DataService (session-locked, retried); a Studio player whose load fails gets an
	unsaved fresh profile. SaveGate counts loads and saves in flight so BindToClose can wait for them, and
	releases the lock of a load that finishes after the player left or the server began closing.
	No gameplay rules here.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local DataService = require(script.Parent.DataService)
local Leaderboard = require(script.Parent.Leaderboard)
local Leaderboards = require(ReplicatedStorage.Shared.Leaderboards)
local PlayerData = require(ReplicatedStorage.Shared.PlayerData)
local SaveGate = require(script.Parent.SaveGate)
local WeeklyEvents = require(ReplicatedStorage.Shared.WeeklyEvents)
local World = require(script.Parent.World)

-- The last board write of a player: its value and key prefix (nil after a failed remove of the other prefix).
type BoardWrite = { value: number, prefix: string? }

export type Persistence = {
	data: DataService.DataService,
	memoryMode: boolean,
	boardStore: ((name: string) -> OrderedDataStore?)?, -- global boards by store name; nil in memory mode
	unsaved: { [number]: boolean }, -- Studio fallback profiles: never written
	ranked: { [number]: { [string]: BoardWrite } }, -- the last write per player, per board store name
	gate: SaveGate.Gate, -- loads and saves in flight, closing
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
	local boardStore: ((name: string) -> OrderedDataStore?)? = nil
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
		local opened: { [string]: OrderedDataStore } = {}
		boardStore = function(name: string): OrderedDataStore?
			if not opened[name] then
				local ok, store = pcall(function()
					return DataStoreService:GetOrderedDataStore(name)
				end)
				if ok then
					opened[name] = store
				end
			end
			return opened[name]
		end
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
		boardStore = boardStore,
		unsaved = {},
		ranked = {},
		gate = SaveGate.new({
			clock = os.clock,
			wait = function(seconds: number)
				task.wait(seconds)
			end,
		}),
	}
end

--[[
	Loads `userId`'s save. Returns the data, or nil plus the kick message. `present()` says whether the player
	is still in the server: one who left while loading gets the session lock released and (nil, nil). Once the
	server is closing, the lock is released as well and the player is kicked.
]]
function Persistence.load(p: Persistence, userId: number, present: () -> boolean): (PlayerData.Data?, string?)
	local ok, result = SaveGate.load(p.gate, p.data, userId, present)
	if result == "left" then
		return nil, nil
	elseif result == "closing" then
		return nil, "This server is shutting down. Please rejoin."
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

-- Writes each global board value of `userId` that changed since its last write, under the player's current key
-- prefix (Leaderboard.prefixFor); the first write of a session and a prefix change also remove the key under the
-- other prefix, so a hidden player never stays on a board under their real id (yields).
local function rank(p: Persistence, userId: number, playerData: PlayerData.Data, saved: boolean, readOnly: boolean)
	local open = p.boardStore
	if not open then
		return
	end
	local week = WeeklyEvents.weekIndex(os.time())
	local prefix = Leaderboard.prefixFor(playerData)
	local written = p.ranked[userId] or {}
	p.ranked[userId] = written
	for _, def in Leaderboards.BOARDS do
		local name = Leaderboards.storeName(def, week)
		local value = Leaderboard.storeValue(def.stat, playerData, week)
		local last = written[name]
		local moved = last ~= nil and last.prefix ~= prefix
		local store = open(name)
		if
			store and Leaderboard.shouldWrite(saved, readOnly, if last and not moved then last.value else nil, value)
		then
			local keys = Leaderboard.boardWrites(if last then last.prefix else nil, prefix, userId)
			local ok = pcall(function()
				store:SetAsync(keys.set, value)
			end)
			if ok then
				local removed = keys.remove == nil or pcall(function()
					store:RemoveAsync(keys.remove)
				end)
				-- A failed remove leaves no prefix, so the next save writes and removes again.
				written[name] = { value = value, prefix = if removed then prefix else nil }
			end
		end
	end
end

-- Saves (yields); `release` drops the session lock. Also ranks the player on every global board. Returns whether
-- the save was written (a Studio fallback profile never is).
function Persistence.save(p: Persistence, userId: number, playerData: PlayerData.Data, release: boolean): boolean
	if p.unsaved[userId] then
		if release then
			p.unsaved[userId] = nil
		end
		return false
	end
	p.gate.pending += 1
	Leaderboards.rollWeek(playerData, WeeklyEvents.weekIndex(os.time()))
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
	rank(p, userId, playerData, ok, readOnly)
	if release then
		p.ranked[userId] = nil
	end
	p.gate.pending -= 1
	return ok
end

-- Starts a save of every session, each in its own thread.
function Persistence.saveAll(p: Persistence, world: World.World, release: boolean)
	for userId, session in world.sessions do
		task.spawn(Persistence.save, p, userId, session.data, release)
	end
end

-- From now on, loads that finish release their lock and kick instead of joining.
function Persistence.close(p: Persistence)
	SaveGate.close(p.gate)
end

-- Waits until no load or save is in flight or `timeout` seconds pass.
function Persistence.waitForSaves(p: Persistence, timeout: number)
	SaveGate.wait(p.gate, timeout)
end

return Persistence
