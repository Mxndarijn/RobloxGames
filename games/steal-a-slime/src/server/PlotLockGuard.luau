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
PlotLockGuard.MIN_Y = -10 -- local height window that counts as "in" the plot
PlotLockGuard.MAX_Y = 60

-- True when the point is inside the plot's footprint (shrunk by MARGIN) and height window.
function PlotLockGuard.inside(x: number, y: number, z: number, half: number): boolean
	local limit = half - PlotLockGuard.MARGIN
	return math.abs(x) <= limit and math.abs(z) <= limit and y >= PlotLockGuard.MIN_Y and y <= PlotLockGuard.MAX_Y
end

-- True when the point is trapped in a locked plot: inside the footprint, or in the front LockBarrier slab
-- (plot-local z from `frontZ`, the slab's outer face, to the guard limit) that `inside` leaves out.
function PlotLockGuard.trapped(x: number, y: number, z: number, half: number, frontZ: number?): boolean
	if PlotLockGuard.inside(x, y, z, half) then
		return true
	end
	return frontZ ~= nil
		and math.abs(x) <= half
		and z >= frontZ
		and z <= -(half - PlotLockGuard.MARGIN)
		and y >= PlotLockGuard.MIN_Y
		and y <= PlotLockGuard.MAX_Y
end

-- True when `userId` must be removed from this plot right now.
function PlotLockGuard.shouldEject(
	userId: number,
	ownerId: number?,
	locked: boolean,
	x: number,
	y: number,
	z: number,
	half: number,
	frontZ: number?
): boolean
	if not locked or ownerId == nil or ownerId == userId then
		return false
	end
	return PlotLockGuard.trapped(x, y, z, half, frontZ)
end

PlotLockGuard.GROUND_Y = 0.5 -- plot-local ground (Base top) when no raycast is available
PlotLockGuard.STAND_HEIGHT = 3 -- R15 hip height + half the root part: root centre above the ground
PlotLockGuard.EJECT_OUT = 4 -- studs beyond the front slab's outer face
PlotLockGuard.EJECT_SPACING = 4 -- sideways gap between ejected characters
PlotLockGuard.EJECT_PER_ROW = 8 -- characters per row; further rows stand EJECT_SPACING further out

-- Plot-local landing spot of intruder `slot` of `count` (1-based) ejected from a plot of half-size `half` whose
-- front slab ends at `frontZ` (WorldLayout.frontBarrier().zOuter): in front of the gate, spread sideways, on the
-- ground. Returns x, y, z and the plot-local look direction (dx, dy, dz): outward, -Z.
function PlotLockGuard.ejectPose(
	half: number,
	frontZ: number?,
	slot: number,
	count: number,
	groundY: number?
): (number, number, number, number, number, number)
	local row = (slot - 1) // PlotLockGuard.EJECT_PER_ROW
	local inRow = math.min(count - row * PlotLockGuard.EJECT_PER_ROW, PlotLockGuard.EJECT_PER_ROW)
	local col = (slot - 1) % PlotLockGuard.EJECT_PER_ROW
	local x = (col - (inRow - 1) / 2) * PlotLockGuard.EJECT_SPACING
	local z = (frontZ or -half) - PlotLockGuard.EJECT_OUT - row * PlotLockGuard.EJECT_SPACING
	return x, (groundY or PlotLockGuard.GROUND_Y) + PlotLockGuard.STAND_HEIGHT, z, 0, 0, -1
end

-- Collision group names (barrier panels of plot i / the characters allowed through them).
function PlotLockGuard.lockGroup(index: number): string
	return `PlotLock_{index}`
end

function PlotLockGuard.ownerGroup(index: number): string
	return `PlotOwner_{index}`
end

return table.freeze(PlotLockGuard)
