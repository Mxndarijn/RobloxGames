--!strict
--[[
	PlotLockGuard (pure)

	Server-side rule for the plot lock. The LockBarrier (the cork stopper in jar 1's door) is ONE-WAY: it only
	blocks ENTERING. Nobody is ever teleported, ejected or thrown. A character that is not the plot's owner and
	stands inside a locked plot's jar (there at lock time, or it got in some other way) is a "leaver": its parts go
	into the PlotLeaver collision group, which does not collide with the stopper, so it can always walk out through
	the door. Once its root is clear of the jar and the doorway by EXIT_MARGIN it flips back to its normal group and
	the stopper blocks it again. Outside non-owners (bridge, moat, plot corners) keep colliding, so entering stays
	blocked. No friend pass.

	"Inside" is the jar interior at the character's height: plot-local radius within `radius` (the inner radius of
	the jar at that height, WorldLayout.jarRadius) less MARGIN, plus the doorway passage `door` (|x| within its half
	width, z from its outer face in to the jar centre).

	Positions are plot-local (Base CFrame space, door at -Z).
	No Roblox APIs: runs unchanged under Lune.
]]

local PlotLockGuard = {}

PlotLockGuard.MARGIN = 2 -- studs inside the glass before the guard reacts
PlotLockGuard.EXIT_MARGIN = 1.5 -- studs clear of the jar and doorway before a leaver collides again
PlotLockGuard.MIN_Y = -10 -- local height window that counts as "in" the plot
PlotLockGuard.MAX_Y = 60
PlotLockGuard.LEAVER_GROUP = "PlotLeaver" -- characters that may pass every LockBarrier part on their way out

-- The doorway passage: |x| <= halfWidth, z from zOuter (the stopper's outer face) in to the jar centre.
export type Door = { halfWidth: number, zOuter: number }

local function inWindow(y: number): boolean
	return y >= PlotLockGuard.MIN_Y and y <= PlotLockGuard.MAX_Y
end

-- True when the point is inside the jar of inner radius `radius` (shrunk by MARGIN) and the height window.
function PlotLockGuard.inside(x: number, y: number, z: number, radius: number): boolean
	local limit = radius - PlotLockGuard.MARGIN
	return x * x + z * z <= limit * limit and inWindow(y)
end

-- True when the point is in the locked zone: inside the jar, or in the doorway passage that `inside` leaves out.
-- `grow` widens the zone on every side (the hysteresis a current leaver gets before it counts as out).
function PlotLockGuard.trapped(x: number, y: number, z: number, radius: number, door: Door?, grow: number?): boolean
	local g = grow or 0
	if PlotLockGuard.inside(x, y, z, radius + g) then
		return true
	end
	return door ~= nil and math.abs(x) <= door.halfWidth + g and z >= door.zOuter - g and z <= 0 and inWindow(y)
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
	radius: number,
	door: Door?,
	wasLeaver: boolean?
): boolean
	if not locked or ownerId == nil or ownerId == userId then
		return false
	end
	return PlotLockGuard.trapped(x, y, z, radius, door, if wasLeaver then PlotLockGuard.EXIT_MARGIN else 0)
end

-- Collision group names (stopper of plot i / the characters allowed through it).
function PlotLockGuard.lockGroup(index: number): string
	return `PlotLock_{index}`
end

function PlotLockGuard.ownerGroup(index: number): string
	return `PlotOwner_{index}`
end

return table.freeze(PlotLockGuard)
