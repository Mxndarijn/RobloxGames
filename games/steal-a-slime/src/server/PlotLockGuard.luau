--!strict
--[[
	PlotLockGuard (pure)

	Server-side rule for the plot lock. While a plot is locked, the LockBarrier (the cork stopper in jar 1's door)
	blocks every non-owner BOTH ways: nobody gets in, and a non-owner already inside stays inside until the lock ends
	(only the owner's character, in PlotOwner_<i>, passes it). There is no "leaver" pass any more: it let a character
	pushed or jumping into the stopper count as inside and walk through it.

	The lock never moves anyone. Guests the owner lets in (PlotGuests) pass the stopper too, and a guest who stops
	being one keeps passing it until they have left the jar (SlimeGuard.formerGuests).

	Who stands inside which base is JarInside's. No Roblox APIs: runs unchanged under Lune.
]]

local PlotLockGuard = {}

PlotLockGuard.SHUT_GRACE = 2 -- seconds after a lock starts in which getting in is not intrusion

--[[
	True when a character that entered a plot at `enteredAt` got in after its current lock began: an intruder. One
	already inside when the lock started is trapped instead (the LockBarrier blocks both ways). Getting in within
	SHUT_GRACE of the lock starting is not intrusion either: the stopper shutting on someone standing in the doorway
	pushes them out of it, sometimes into the jar.
]]
function PlotLockGuard.intruder(enteredAt: number, lockStartedAt: number): boolean
	return enteredAt > lockStartedAt + PlotLockGuard.SHUT_GRACE
end

-- Collision group names (stopper of plot i / the owner's character, which passes it).
function PlotLockGuard.lockGroup(index: number): string
	return `PlotLock_{index}`
end

function PlotLockGuard.ownerGroup(index: number): string
	return `PlotOwner_{index}`
end

return table.freeze(PlotLockGuard)
