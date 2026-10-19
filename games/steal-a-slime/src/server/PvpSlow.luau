--!strict
--[[
	PvpSlow (pure, FEATURES.PvP, CONTRACT.md §26 "Walk speed")

	The one per-session record of PvP holds and slows (Goo Trap holds, trap / blaster / splat slows, the stacking
	Squirter slow). It owns no rule about who may be slowed: callers decide that through PvpRules (applyControl /
	applySlow / extendSlow, which also start the immunity). `walkFactor` is what Carry.targetWalkSpeed multiplies in,
	so the existing TargetWalkSpeed enforcement applies it and restores the speed by itself when it runs out.
	Weak-keyed by session, never saved. No Humanoid health is ever touched.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local PvpRules = if Shared then require(Shared.PvpRules) else require("../shared/PvpRules")
local World = if script then require(script.Parent.World) else require("./World")

type Session = World.Session

export type Entry = {
	holdUntil: number, -- walk speed 0 before this
	factor: number, -- walk speed multiplier while slowed
	slowUntil: number, -- the slow ends here
	startedAt: number, -- when the slow (or the hold before it) began: a stack never runs past this + SLOW_MAX_SECONDS
	stacks: number, -- Squirter hits in this slow (0 = not a stacking slow)
}

local PvpSlow = {}

PvpSlow.MIN_FACTOR = 0.1 -- a slow never takes more than 90 % of the walk speed

local entries: { [Session]: Entry } = setmetatable({}, { __mode = "k" }) :: any

local function clampFactor(factor: number): number
	if factor ~= factor then
		return 1
	end
	return math.clamp(factor, PvpSlow.MIN_FACTOR, 1)
end

-- The live entry, nil once everything in it ran out.
function PvpSlow.entry(session: Session, now: number): Entry?
	local entry = entries[session]
	if entry and now >= entry.holdUntil and now >= entry.slowUntil then
		entries[session] = nil
		return nil
	end
	return entry
end

-- Holds the player in place until `holdUntil`, then slows them by `factor` until `slowUntil` (both optional).
function PvpSlow.hold(session: Session, now: number, holdUntil: number, factor: number?, slowUntil: number?)
	entries[session] = {
		holdUntil = holdUntil,
		factor = clampFactor(factor or 1),
		slowUntil = math.max(holdUntil, slowUntil or holdUntil),
		startedAt = now,
		stacks = 0,
	}
end

-- Slows the player by `factor` until `untilTime` (replaces a weaker or shorter slow, never shortens a hold).
function PvpSlow.slow(session: Session, now: number, factor: number, untilTime: number)
	local entry = PvpSlow.entry(session, now)
	local holdUntil = if entry then entry.holdUntil else 0
	entries[session] = {
		holdUntil = holdUntil,
		factor = clampFactor(factor),
		slowUntil = untilTime,
		startedAt = now,
		stacks = 0,
	}
end

--[[
	One Goo Squirter hit on `session` (`state` = its PvpRules state). A running stacking slow is deepened by
	`perHit` (up to `maxSlow`) and extended by `seconds` (PvpRules.extendSlow: the whole slow at most SLOW_MAX_SECONDS
	from its first hit); otherwise a new slow starts if PvpRules.applySlow allows it. Returns the seconds the slow now
	lasts from `now` (0 = refused: immune).
]]
function PvpSlow.stack(
	session: Session,
	state: PvpRules.State,
	now: number,
	perHit: number,
	maxSlow: number,
	seconds: number
): number
	local entry = PvpSlow.entry(session, now)
	if entry and entry.stacks > 0 and now < entry.slowUntil then
		entry.slowUntil = PvpRules.extendSlow(state, entry.startedAt, entry.slowUntil, seconds, now)
		entry.stacks += 1
		entry.factor = clampFactor(1 - math.min(entry.stacks * perHit, maxSlow))
		return entry.slowUntil - now
	end
	local applied = PvpRules.applySlow(state, seconds, now)
	if applied <= 0 then
		return 0
	end
	entries[session] = {
		holdUntil = 0,
		factor = clampFactor(1 - math.min(perHit, maxSlow)),
		slowUntil = now + applied,
		startedAt = now,
		stacks = 1,
	}
	return applied
end

-- True while a hold keeps the player in place.
function PvpSlow.held(session: Session, now: number): boolean
	local entry = PvpSlow.entry(session, now)
	return entry ~= nil and now < entry.holdUntil
end

-- Walk speed multiplier right now: 0 while held, the slow factor while slowed, else 1.
function PvpSlow.walkFactor(session: Session, now: number): number
	local entry = PvpSlow.entry(session, now)
	if not entry then
		return 1
	end
	if now < entry.holdUntil then
		return 0
	end
	return if now < entry.slowUntil then entry.factor else 1
end

function PvpSlow.clear(session: Session)
	entries[session] = nil
end

return PvpSlow
