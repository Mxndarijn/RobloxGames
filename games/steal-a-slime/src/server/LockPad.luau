--!strict
--[[
	LockPad (pure)

	The lock pad round each plot's LockButton (CONTRACT.md §8.5): a ring of Config.LOCK_PAD.SEGMENTS segments on the
	floor. The owner standing in it for STAND_SECONDS starts the same Lock action as the LockPrompt. Reads / writes
	session.lockPadSince (when the owner stepped on). `ring` says how many segments are lit and in which colour:
	  charge  the owner is standing on it: segments light up one by one over STAND_SECONDS;
	  locked  the plot is locked: the lit segments are the share of the lock still to run;
	  ready   the lock just ran out: all segments, for READY_FLASH_SECONDS;
	  idle    none lit.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local World = if script then require(script.Parent.World) else require("./World")

export type Mode = "idle" | "charge" | "locked" | "ready"
export type Ring = { mode: Mode, lit: number }

local PAD = Config.LOCK_PAD

local LockPad = {}

-- True when a root part `dx`, `dz` studs (flat) from the LockButton's centre and `dy` studs above the floor stands on the pad.
function LockPad.inside(dx: number, dy: number, dz: number): boolean
	if dx ~= dx or dy ~= dy or dz ~= dz then
		return false
	end
	return dx * dx + dz * dz <= PAD.REACH * PAD.REACH and dy >= -1 and dy <= PAD.HEIGHT
end

--[[
	One tick for the owner: `onPad` = standing on their own pad, `locked` = their plot is locked. Returns true when they
	have stood on it for STAND_SECONDS and the caller should run the Lock action. Stepping off, or a running lock, starts
	the count again from zero.
]]
function LockPad.step(session: World.Session, onPad: boolean, locked: boolean, now: number): boolean
	if not onPad or locked then
		session.lockPadSince = nil
		return false
	end
	local since = session.lockPadSince
	if since == nil then
		session.lockPadSince = now
		return false
	end
	if now - since >= PAD.STAND_SECONDS then
		session.lockPadSince = nil
		return true
	end
	return false
end

--[[
	What the ring shows for a plot: `lockUntil` / `lockStartedAt` of the owner's current lock (0 / 0 on a free plot),
	`since` = session.lockPadSince.
]]
function LockPad.ring(now: number, lockUntil: number, lockStartedAt: number, since: number?): Ring
	local n = PAD.SEGMENTS
	if now < lockUntil then
		local total = lockUntil - lockStartedAt
		local share = if total > 0 then (lockUntil - now) / total else 1
		return { mode = "locked", lit = math.clamp(math.ceil(share * n), 1, n) }
	end
	if since ~= nil then
		local share = math.clamp((now - since) / PAD.STAND_SECONDS, 0, 1)
		return { mode = "charge", lit = math.floor(share * n) }
	end
	if lockUntil > 0 and now - lockUntil < PAD.READY_FLASH_SECONDS then
		return { mode = "ready", lit = n }
	end
	return { mode = "idle", lit = 0 }
end

return LockPad
