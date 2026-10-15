--!strict
--[[
	SessionLock

	Pure session-locking rules used inside DataStore:UpdateAsync so that two
	servers never both own a player's data (rejoin on another server before
	the old one saved, duplicated slimes, etc.).

	Stored record: { data = <SaveData.serialize output>, session = { jobId, time }? }
	Records without the wrapper (older saves) are read as unlocked data.

	The server:
	  * loads with `acquire` (retrying while "locked", kicking after N tries),
	  * saves with `write(..., release = false)` and refreshes `time`,
	  * releases on leave / shutdown with `write(..., release = true)`.
	A lock whose `time` is older than SESSION_STALE_SECONDS (crashed server)
	can be taken over.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

export type Session = { jobId: string, time: number }
export type Record = { data: any, session: Session? }
export type Status = "free" | "own" | "stale" | "locked"

local SessionLock = {}

function SessionLock.unwrap(record: any): (any, Session?)
	if type(record) ~= "table" then
		return nil, nil
	end
	if record.data == nil and record.session == nil then
		return record, nil -- legacy, unwrapped save
	end
	local s = record.session
	if type(s) == "table" and type(s.jobId) == "string" and type(s.time) == "number" then
		return record.data, { jobId = s.jobId, time = s.time }
	end
	return record.data, nil
end

function SessionLock.status(session: Session?, jobId: string, now: number, staleAfter: number?): Status
	if not session then
		return "free"
	end
	if session.jobId == jobId then
		return "own"
	end
	if now - session.time > (staleAfter or Config.SESSION_STALE_SECONDS) then
		return "stale"
	end
	return "locked"
end

--[[
	UpdateAsync transform for loading. Returns (newRecord?, status, data).
	newRecord is nil when another live server holds the lock: return nil from
	the UpdateAsync callback to cancel the write, then retry later.
]]
function SessionLock.acquire(record: any, jobId: string, now: number): (Record?, Status, any)
	local data, session = SessionLock.unwrap(record)
	local status: Status = SessionLock.status(session, jobId, now)
	if status == "locked" then
		return nil, status, data
	end
	return { data = data, session = { jobId = jobId, time = now } }, status, data
end

--[[
	UpdateAsync transform for saving. Returns (newRecord?, ok). ok is false
	(and newRecord nil: cancel the write) when another server has taken the
	session over: this server must stop saving that player.
]]
function SessionLock.write(record: any, jobId: string, now: number, data: any, release: boolean): (Record?, boolean)
	local _, session = SessionLock.unwrap(record)
	local status = SessionLock.status(session, jobId, now)
	if status ~= "own" then
		-- Another server took the session over (and maybe already released it).
		return nil, false
	end
	if release then
		return { data = data, session = nil }, true
	end
	return { data = data, session = { jobId = jobId, time = now } }, true
end

-- Seconds to wait before load attempt `attempt` (1-based) is retried.
function SessionLock.backoff(attempt: number): number
	return math.min(2 ^ attempt, 10)
end

return SessionLock
