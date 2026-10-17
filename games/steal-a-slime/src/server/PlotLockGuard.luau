--!strict
--[[
	PlotLockGuard (pure)

	Server-side rule for the plot lock. The LockBarrier is ONE-WAY: it only blocks ENTERING. Nobody is ever
	teleported, ejected or thrown. A character that is not the plot's owner and stands inside a locked plot
	(there at lock time, or it got in some other way) is a "leaver": its parts go into the PlotLeaver collision
	group, which does not collide with the barrier panels, so it can always walk out through the gate. Once its
	root is clear of the plot (past the barrier by EXIT_MARGIN) it flips back to its normal group and the barrier
	blocks it again. Outside non-owners keep colliding, so entering stays blocked. No friend pass.

	Positions are plot-local (Base CFrame space, entrance at -Z).
	No Roblox APIs: runs unchanged under Lune.
]]

local PlotLockGuard = {}

PlotLockGuard.MARGIN = 2 -- studs inside the fence before the guard reacts
PlotLockGuard.EXIT_MARGIN = 1.5 -- studs clear of the plot (past the barrier) before a leaver collides again
PlotLockGuard.MIN_Y = -10 -- local height window that counts as "in" the plot
PlotLockGuard.MAX_Y = 60
PlotLockGuard.LEAVER_GROUP = "PlotLeaver" -- characters that may pass every LockBarrier panel on their way out

-- True when the point is inside the plot's footprint (shrunk by MARGIN) and height window.
function PlotLockGuard.inside(x: number, y: number, z: number, half: number): boolean
	local limit = half - PlotLockGuard.MARGIN
	return math.abs(x) <= limit and math.abs(z) <= limit and y >= PlotLockGuard.MIN_Y and y <= PlotLockGuard.MAX_Y
end

-- True when the point is in the locked zone: inside the footprint, or in the front LockBarrier slab (plot-local z
-- from `frontZ`, the slab's outer face, to the guard limit) that `inside` leaves out. `grow` widens the zone on
-- every open side (the hysteresis a current leaver gets before it counts as out).
function PlotLockGuard.trapped(x: number, y: number, z: number, half: number, frontZ: number?, grow: number?): boolean
	local g = grow or 0
	if PlotLockGuard.inside(x, y, z, half + g) then
		return true
	end
	return frontZ ~= nil
		and math.abs(x) <= half + g
		and z >= frontZ - g
		and z <= -(half - PlotLockGuard.MARGIN)
		and y >= PlotLockGuard.MIN_Y
		and y <= PlotLockGuard.MAX_Y
end

-- True when this character must be a leaver for this plot right now. Never true for the owner, an unlocked or
-- unowned plot. `wasLeaver` (its state last tick) keeps it a leaver until it is EXIT_MARGIN clear of the zone.
function PlotLockGuard.isLeaver(
	userId: number,
	ownerId: number?,
	locked: boolean,
	x: number,
	y: number,
	z: number,
	half: number,
	frontZ: number?,
	wasLeaver: boolean?
): boolean
	if not locked or ownerId == nil or ownerId == userId then
		return false
	end
	return PlotLockGuard.trapped(x, y, z, half, frontZ, if wasLeaver then PlotLockGuard.EXIT_MARGIN else 0)
end

-- Collision group names (barrier panels of plot i / the characters allowed through them).
function PlotLockGuard.lockGroup(index: number): string
	return `PlotLock_{index}`
end

function PlotLockGuard.ownerGroup(index: number): string
	return `PlotOwner_{index}`
end

return table.freeze(PlotLockGuard)
