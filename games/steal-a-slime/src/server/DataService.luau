--!strict
--[[
	DataService (pure, backend injected)

	Loads and saves PlayerData through a DataStore-like backend with retries
	and session locking (Shared.SessionLock around Shared.SaveData).

	* Key "u_<UserId>" in Constants.DATASTORE_NAME.
	* load: UpdateAsync + SessionLock.acquire. Retries with
	  SessionLock.backoff while another live server holds the lock or the
	  call errors; gives up after `loadAttempts` (the caller kicks).
	* save: UpdateAsync + SessionLock.write, retried `saveAttempts` times on
	  errors. If another server took the session over, the save is refused
	  and this server stops saving that player (no duplicated slimes).
	* release = true on leave / BindToClose frees the session lock.

	Backend: { update: (key, transform: (old: any) -> any?) -> any }, which
	may error (the Roblox adapter wraps DataStore:UpdateAsync).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local SaveData = if Shared then require(Shared.SaveData) else require("../shared/SaveData")
local SessionLock = if Shared then require(Shared.SessionLock) else require("../shared/SessionLock")

export type Backend = {
	update: (key: string, transform: (old: any) -> any?) -> any,
}

export type Options = {
	backend: Backend,
	jobId: string,
	now: () -> number,
	wait: (seconds: number) -> (),
	loadAttempts: number?,
	saveAttempts: number?,
}

export type DataService = {
	backend: Backend,
	jobId: string,
	now: () -> number,
	wait: (seconds: number) -> (),
	loadAttempts: number,
	saveAttempts: number,
	lost: { [number]: boolean }, -- userIds whose session another server took over
}

local DataService = {}

function DataService.key(userId: number): string
	return `u_{userId}`
end

function DataService.new(options: Options): DataService
	return {
		backend = options.backend,
		jobId = options.jobId,
		now = options.now,
		wait = options.wait,
		loadAttempts = options.loadAttempts or 5,
		saveAttempts = options.saveAttempts or 3,
		lost = {},
	}
end

-- Returns (true, data) or (false, reason). Yields between retries.
function DataService.load(service: DataService, userId: number): (boolean, PlayerData.Data | string)
	local key = DataService.key(userId)
	local reason = "DataStore error"
	for attempt = 1, service.loadAttempts do
		local status: SessionLock.Status? = nil
		local stored: any = nil
		local ok = pcall(service.backend.update, key, function(old: any): any?
			local record, st, data = SessionLock.acquire(old, service.jobId, service.now())
			status = st :: SessionLock.Status
			stored = data
			return record
		end)
		if ok and status ~= nil and status ~= "locked" then
			service.lost[userId] = nil
			return true, SaveData.deserialize(stored)
		end
		reason = if ok and status == "locked" then "your data is open on another server" else "DataStore error"
		if attempt < service.loadAttempts then
			service.wait(SessionLock.backoff(attempt))
		end
	end
	return false, reason
end

-- Returns (ok, reason?). Yields between retries.
function DataService.save(
	service: DataService,
	userId: number,
	data: PlayerData.Data,
	release: boolean
): (boolean, string?)
	if service.lost[userId] then
		return false, "session lost"
	end
	local key = DataService.key(userId)
	for attempt = 1, service.saveAttempts do
		local written: boolean? = nil
		local ok = pcall(service.backend.update, key, function(old: any): any?
			local now = service.now()
			local record, wrote = SessionLock.write(old, service.jobId, now, SaveData.serialize(data, now), release)
			written = wrote
			return record
		end)
		if ok and written then
			return true, nil
		end
		if ok and written == false then
			service.lost[userId] = true
			return false, "session lost"
		end
		if attempt < service.saveAttempts then
			service.wait(SessionLock.backoff(attempt))
		end
	end
	return false, "DataStore error"
end

-- In-memory backend for Studio without API access and for tests.
function DataService.memoryBackend(): Backend & { records: { [string]: any } }
	local records: { [string]: any } = {}
	local backend = {
		records = records,
		update = function(key: string, transform: (old: any) -> any?): any
			local new = transform(records[key])
			if new ~= nil then
				records[key] = new
			end
			return new
		end,
	}
	return backend
end

return DataService
