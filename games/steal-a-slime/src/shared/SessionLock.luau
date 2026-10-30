--!strict
--[[
	SessionLock: the shared session-locking rules (shared/luau/src/data/SessionLock) with this game's stale time,
	Config.SESSION_STALE_SECONDS, filled in. Used inside DataStore:UpdateAsync so two servers never both own a
	player's data.

	Stored record: { data = <SaveData.serialize output>, session = { jobId, time }? }. Records without the wrapper
	are read as unlocked data.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local Core = if Lib then require(Lib.data.SessionLock) else require("../../../../shared/luau/src/data/SessionLock")

export type Session = Core.Session
export type Record = Core.Record
export type Status = Core.Status

local SessionLock = {}

SessionLock.unwrap = Core.unwrap
SessionLock.backoff = Core.backoff

-- `staleAfter` defaults to Config.SESSION_STALE_SECONDS.
function SessionLock.status(session: Session?, jobId: string, now: number, staleAfter: number?): Status
	return Core.status(session, jobId, now, staleAfter or Config.SESSION_STALE_SECONDS)
end

-- UpdateAsync transform for loading: (newRecord?, status, data); newRecord is nil while another live server holds
-- the lock.
function SessionLock.acquire(record: any, jobId: string, now: number): (Record?, Status, any)
	return Core.acquire(record, jobId, now, Config.SESSION_STALE_SECONDS)
end

-- UpdateAsync transform for saving: (newRecord?, ok); ok is false once another server owns the session.
function SessionLock.write(record: any, jobId: string, now: number, data: any, release: boolean): (Record?, boolean)
	return Core.write(record, jobId, now, data, release, Config.SESSION_STALE_SECONDS)
end

return table.freeze(SessionLock)
