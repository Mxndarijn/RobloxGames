--!strict
--[[
	DataService: session-locked load and save through an injected UpdateAsync-shaped backend.

		local service = DataService.new({
			backend = DataStoreBackend.new("PlayerData"), -- or DataService.memoryBackend()
			jobId = game.JobId,
			now = os.time,
			wait = task.wait,
			defaultData = function() return { coins = 0 } end,
			serialize = function(data, now) return { version = 2, coins = data.coins, savedAt = now } end,
			deserialize = function(raw) return { coins = Migrations.num(raw.coins, 0, 0) } end,
			migrations = { steps = { [1] = upgradeV1 }, latest = 2 },
		})
		local ok, data, readOnly = service:load(`u_{userId}`) -- (false, reason) when it gave up: kick
		service:save(`u_{userId}`, data, false)                -- autosave
		service:save(`u_{userId}`, data, true)                 -- leave / shutdown: releases the lock

	load: runs SessionLock.acquire inside backend.update. While another live server holds the lock, or the backend
	errors, it waits SessionLock.backoff(attempt) and retries, up to `loadAttempts`; then returns
	(false, "Locked" | "BackendError"). On success the stored data goes through Migrations.run and `deserialize`;
	nothing stored gives `defaultData()`.

	Read-only sessions: when the stored record is from a newer schema (Migrations "newer") or unreadable (garbage,
	or `deserialize` errors), load still succeeds with a best-effort value (`deserialize` of the raw record for
	"newer", else `defaultData()`) and returns readOnly = true. Saves for that key never write the given data:
	they refresh or release the lock, write the stored record back untouched, and return (false, "ReadOnly").

	save: runs SessionLock.write inside backend.update, retrying backend errors up to `saveAttempts`. When
	another server took the session over (or it was already released), the save is refused with "SessionLost"
	and every later save for that key is refused without a backend call until the key is loaded again.

	Backend: { update: (key, transform: (old: any) -> any?) -> any }. The transform returns nil to cancel the
	write. update may error; DataService catches it.
]]

local Migrations = if script then require(script.Parent.Parent.core.Migrations) else require("../core/Migrations")
local SessionLock = if script then require(script.Parent.SessionLock) else require("./SessionLock")

export type Backend = {
	update: (key: string, transform: (old: any) -> any?) -> any,
}

export type MemoryBackend = Backend & { records: { [string]: any } }

export type MigrationOptions = {
	steps: Migrations.Steps,
	latest: number,
	versionField: string?,
}

export type ReadOnlyReason = "newer" | "unreadable"

export type Options = {
	backend: Backend,
	jobId: string,
	now: () -> number,
	wait: (seconds: number) -> (),
	defaultData: () -> any,
	serialize: (data: any, now: number) -> any,
	deserialize: (raw: any) -> any,
	migrations: MigrationOptions?,
	staleAfter: number?,
	loadAttempts: number?,
	saveAttempts: number?,
	backoffCap: number?,
	log: ((message: string) -> ())?,
}

export type DataService = {
	load: (self: DataService, key: string) -> (boolean, any, boolean?),
	save: (self: DataService, key: string, data: any, release: boolean) -> (boolean, string?),
	readOnly: (self: DataService, key: string) -> ReadOnlyReason?,
	isLost: (self: DataService, key: string) -> boolean,
}

type State = DataService & {
	options: Options,
	staleAfter: number,
	loadAttempts: number,
	saveAttempts: number,
	log: (message: string) -> (),
	lost: { [string]: boolean },
	readOnlyKeys: { [string]: ReadOnlyReason? },
}

local DEFAULT_STALE_AFTER = 1800
local DEFAULT_LOAD_ATTEMPTS = 5
local DEFAULT_SAVE_ATTEMPTS = 3

local DataService = {}
DataService.__index = DataService

local function noop(_: string) end

function DataService.new(options: Options): DataService
	for _, name in { "now", "wait", "defaultData", "serialize", "deserialize" } do
		if type((options :: any)[name]) ~= "function" then
			error(`DataService.new: options.{name} must be a function`, 2)
		end
	end
	if type(options.backend) ~= "table" or type(options.backend.update) ~= "function" then
		error("DataService.new: options.backend must have an update function", 2)
	end
	if type(options.jobId) ~= "string" then
		error("DataService.new: options.jobId must be a string", 2)
	end
	local self = setmetatable({
		options = options,
		staleAfter = options.staleAfter or DEFAULT_STALE_AFTER,
		loadAttempts = math.max(1, options.loadAttempts or DEFAULT_LOAD_ATTEMPTS),
		saveAttempts = math.max(1, options.saveAttempts or DEFAULT_SAVE_ATTEMPTS),
		log = options.log or noop,
		lost = {},
		readOnlyKeys = {},
	}, DataService)
	return (self :: any) :: DataService
end

-- Turns a stored value into (data, readOnlyReason?).
local function decode(state: State, stored: any): (any, ReadOnlyReason?)
	local options = state.options
	if stored == nil then
		return options.defaultData(), nil
	end
	local raw: any = stored
	if options.migrations then
		local m = options.migrations
		local migrated, status = Migrations.run(stored, m.steps, m.latest, m.versionField)
		if status == "newer" then
			local ok, data = pcall(options.deserialize, stored)
			return if ok and data ~= nil then data else options.defaultData(), "newer" :: ReadOnlyReason
		elseif status == "fresh" then
			return options.defaultData(), "unreadable" :: ReadOnlyReason
		end
		raw = migrated
	elseif type(stored) ~= "table" then
		return options.defaultData(), "unreadable" :: ReadOnlyReason
	end
	local ok, data = pcall(options.deserialize, raw)
	if not ok or data == nil then
		return options.defaultData(), "unreadable" :: ReadOnlyReason
	end
	return data, nil
end

-- Returns (true, data, readOnly) or (false, reason). Yields through `wait` between retries.
function DataService.load(self: DataService, key: string): (boolean, any, boolean?)
	local state = self :: State
	local options = state.options
	local reason = "BackendError"
	for attempt = 1, state.loadAttempts do
		local status: SessionLock.Status? = nil
		local stored: any = nil
		local ok = pcall(options.backend.update, key, function(old: any): any?
			local record, st, data = SessionLock.acquire(old, options.jobId, options.now(), state.staleAfter)
			status = st :: SessionLock.Status
			stored = data
			return record
		end)
		if ok and status ~= nil and status ~= "locked" then
			state.lost[key] = nil
			local data: any, readOnly: ReadOnlyReason? = decode(state, stored)
			state.readOnlyKeys[key] = readOnly
			if readOnly then
				state.log(`[DataService] {key}: stored record is {readOnly}; this session is read-only`)
			end
			return true, data, readOnly ~= nil
		end
		reason = if ok and status == "locked" then "Locked" else "BackendError"
		if attempt < state.loadAttempts then
			options.wait(SessionLock.backoff(attempt, options.backoffCap))
		end
	end
	return false, reason
end

-- Why this key's session is read-only, or nil when saves write normally.
function DataService.readOnly(self: DataService, key: string): ReadOnlyReason?
	return (self :: State).readOnlyKeys[key]
end

-- True when another server took this key's session over; cleared by the next successful load.
function DataService.isLost(self: DataService, key: string): boolean
	return (self :: State).lost[key] == true
end

-- Returns (ok, reason?): reason is "SessionLost", "ReadOnly" or "BackendError". Yields through `wait`.
function DataService.save(self: DataService, key: string, data: any, release: boolean): (boolean, string?)
	local state = self :: State
	local options = state.options
	if state.lost[key] then
		return false, "SessionLost"
	end
	local readOnly = state.readOnlyKeys[key] ~= nil
	for attempt = 1, state.saveAttempts do
		local written: boolean? = nil
		local ok = pcall(options.backend.update, key, function(old: any): any?
			local now = options.now()
			local payload = if readOnly then (SessionLock.unwrap(old)) else options.serialize(data, now)
			local record, wrote = SessionLock.write(old, options.jobId, now, payload, release, state.staleAfter)
			written = wrote
			return record
		end)
		if ok and written then
			if readOnly then
				if release then
					state.readOnlyKeys[key] = nil
				end
				return false, "ReadOnly"
			end
			return true, nil
		end
		if ok and written == false then
			state.lost[key] = true
			state.log(`[DataService] {key}: session taken over by another server; saves stopped`)
			return false, "SessionLost"
		end
		if attempt < state.saveAttempts then
			options.wait(SessionLock.backoff(attempt, options.backoffCap))
		end
	end
	return false, "BackendError"
end

-- In-memory backend for tests and for Studio without API access. `records` is the stored state by key.
function DataService.memoryBackend(): MemoryBackend
	local records: { [string]: any } = {}
	return {
		records = records,
		update = function(key: string, transform: (old: any) -> any?): any
			local new = transform(records[key])
			if new ~= nil then
				records[key] = new
			end
			return new
		end,
	}
end

return table.freeze(DataService)
