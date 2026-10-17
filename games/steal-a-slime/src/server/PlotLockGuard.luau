--!strict
--[[
	PlotLockGuard (pure)

	Server-side enforcement of the plot lock. The LockBarrier panels are
	cosmetic on the client, so the server decides: a character that stands
	inside a locked plot it does not own is put back outside the entrance.
	Only the owner may be inside a locked plot (no friend pass).

	Positions are plot-local (Base CFrame space, entrance at -Z).
	No Roblox APIs: runs unchanged under Lune.
]]

local PlotLockGuard = {}

PlotLockGuard.MARGIN = 2 -- studs inside the fence before the guard reacts
PlotLockGuard.EJECT_DISTANCE = 8 -- studs outside the entrance edge
PlotLockGuard.MIN_Y = -10 -- local height window that counts as "in" the plot
PlotLockGuard.MAX_Y = 60

-- True when the point is inside the plot's footprint (shrunk by MARGIN) and height window.
function PlotLockGuard.inside(x: number, y: number, z: number, half: number): boolean
	local limit = half - PlotLockGuard.MARGIN
	return math.abs(x) <= limit and math.abs(z) <= limit and y >= PlotLockGuard.MIN_Y and y <= PlotLockGuard.MAX_Y
end

-- True when `userId` must be removed from this plot right now.
function PlotLockGuard.shouldEject(
	userId: number,
	ownerId: number?,
	locked: boolean,
	x: number,
	y: number,
	z: number,
	half: number
): boolean
	if not locked or ownerId == nil or ownerId == userId then
		return false
	end
	return PlotLockGuard.inside(x, y, z, half)
end

-- Plot-local point in front of the entrance (-Z) where an ejected character lands.
function PlotLockGuard.ejectPoint(half: number): (number, number, number)
	return 0, 4, -(half + PlotLockGuard.EJECT_DISTANCE)
end

-- Collision group names (barrier panels of plot i / the characters allowed through them).
function PlotLockGuard.lockGroup(index: number): string
	return `PlotLock_{index}`
end

function PlotLockGuard.ownerGroup(index: number): string
	return `PlotOwner_{index}`
end

return table.freeze(PlotLockGuard)
