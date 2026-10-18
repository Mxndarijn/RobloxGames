--!strict
--[[
	SessionLock: pure session-locking rules used inside an UpdateAsync-shaped transform, so two servers never both
	own one record (a player rejoining on another server before the old one saved).

	Stored record: { data = <serialized data>, session = { jobId, time }? }. A table without that wrapper is read
	as unlocked data.

	The server:
	  * loads with `acquire` (retrying while "locked"),
	  * saves with `write(..., release = false)`, which refreshes `time`,
	  * releases on leave / shutdown with `write(..., release = true)`.
	A lock whose `time` is more than `staleAfter` seconds old (a crashed server) can be taken over.
]]

export type Session = { jobId: string, time: number }
export type Record = { data: any, session: Session? }
export type Status = "free" | "own" | "stale" | "locked"

local SessionLock = {}

-- Splits a stored value into (data, session?).
function SessionLock.unwrap(record: any): (any, Session?)
	if type(record) ~= "table" then
		return nil, nil
	end
	if record.data == nil and record.session == nil then
		return record, nil
	end
	local s = record.session
	if type(s) == "table" and type(s.jobId) == "string" and type(s.time) == "number" then
		return record.data, { jobId = s.jobId, time = s.time }
	end
	return record.data, nil
end

function SessionLock.status(session: Session?, jobId: string, now: number, staleAfter: number): Status
	if not session then
		return "free"
	end
	if session.jobId == jobId then
		return "own"
	end
	if now - session.time > staleAfter then
		return "stale"
	end
	return "locked"
end

--[[
	Transform for loading. Returns (newRecord?, status, data). newRecord is nil when another live server holds the
	lock: return nil from the transform to cancel the write, then retry later.
]]
function SessionLock.acquire(record: any, jobId: string, now: number, staleAfter: number): (Record?, Status, any)
	local data, session = SessionLock.unwrap(record)
	local status: Status = SessionLock.status(session, jobId, now, staleAfter)
	if status == "locked" then
		return nil, status, data
	end
	return { data = data, session = { jobId = jobId, time = now } }, status, data
end

--[[
	Transform for saving. Returns (newRecord?, ok). ok is false (and newRecord nil: cancel the write) when this
	server no longer owns the session: another server took it over, or it was already released.
]]
function SessionLock.write(
	record: any,
	jobId: string,
	now: number,
	data: any,
	release: boolean,
	staleAfter: number
): (Record?, boolean)
	local _, session = SessionLock.unwrap(record)
	if SessionLock.status(session, jobId, now, staleAfter) ~= "own" then
		return nil, false
	end
	if release then
		return { data = data, session = nil }, true
	end
	return { data = data, session = { jobId = jobId, time = now } }, true
end

-- Seconds to wait before retrying after attempt `attempt` (1-based): 2, 4, 8, ... capped at `cap` (default 10).
function SessionLock.backoff(attempt: number, cap: number?): number
	return math.min(2 ^ attempt, cap or 10)
end

return table.freeze(SessionLock)
