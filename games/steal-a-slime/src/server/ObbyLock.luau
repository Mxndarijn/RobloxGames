--!strict
--[[
	ObbyLock (pure, contract/obby.md §3)

	While a player runs the Obby their base lock counts down at Config.OBBY.LOCK_RATE (0.5: half speed). The lock stays
	one end time (`session.lockUntil`, the plot's LockUntil attribute), so every client countdown, the lock pad ring, the
	door and the steal checks read the slower lock with no change of their own: each obby tick pushes lockUntil out by
	the part of the tick the lock did not use.
	  * Only while `session.obbyRun` is set; from the run's last tick (`run.lockAt`, else `enteredAt`) to now.
	  * A lock that started mid-tick counts from its start (`session.lockStartedAt`); an expired lock or no lock is
	    left alone; a lock that runs out mid-tick ends at the moment it would have at the slow rate (in the past).
	  * The breather lock (SlimeGuard.breather) keeps its mark: `breatherUntil` moves with lockUntil.
	  * The rate is held within MIN_RATE..1: a run slows a lock, it never stops it.
	No Roblox APIs.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local World = if script then require(script.Parent.World) else require("./World")

type Session = World.Session

local ObbyLock = {}

ObbyLock.MIN_RATE = 0.1

-- Config.OBBY.LOCK_RATE held within MIN_RATE..1.
function ObbyLock.rate(): number
	local rate = Config.OBBY.LOCK_RATE
	if type(rate) ~= "number" or rate ~= rate then
		return 1
	end
	return math.clamp(rate, ObbyLock.MIN_RATE, 1)
end

--[[
	The lock's end time after it ran at `rate` from `from` to `to` (real seconds). `lockStartedAt` = when the current lock
	began. Unchanged when there is no running lock in that window.
]]
function ObbyLock.slowed(lockUntil: number, lockStartedAt: number, from: number, to: number, rate: number): number
	rate = math.clamp(rate, ObbyLock.MIN_RATE, 1)
	local start = math.max(from, lockStartedAt)
	if to <= start or lockUntil <= start then
		return lockUntil
	end
	local left = lockUntil - start -- lock seconds left at `start`
	local after = left - rate * (to - start)
	if after > 0 then
		return to + after
	end
	return start + left / rate -- ran out inside the window, at the slow rate
end

-- One obby tick for `session`: slows its lock over the time since the last tick of its run. Returns true when
-- lockUntil moved. Marks the session dirty when the whole second shown on the countdown changes (State.lockUntil).
function ObbyLock.step(session: Session, now: number): boolean
	local run = session.obbyRun
	if not run then
		return false
	end
	local from = run.lockAt or run.enteredAt
	run.lockAt = now
	local before = session.lockUntil
	local after = ObbyLock.slowed(before, session.lockStartedAt, from, now, ObbyLock.rate())
	if after == before then
		return false
	end
	if session.breatherUntil == before then
		session.breatherUntil = after
	end
	session.lockUntil = after
	if math.ceil(before - from) ~= math.ceil(math.max(0, after - now)) then
		World.markDirty(session)
	end
	return true
end

return ObbyLock
