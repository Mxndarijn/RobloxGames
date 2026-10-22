--!strict
--[[
	PlotLockGuard (pure)

	Server-side rule for the plot lock. While a plot is locked, the LockBarrier (the cork stopper in jar 1's door)
	blocks every non-owner BOTH ways: nobody gets in, and a non-owner already inside stays inside until the lock ends
	(only the owner's character, in PlotOwner_<i>, passes it). There is no "leaver" pass any more: it let a character
	pushed or jumping into the stopper count as inside and walk through it.

	A non-owner standing in the doorway itself when the lock starts would be wedged in the stopper, so it is set
	down just outside the door, on the bridge (`doorwayExit`). That is the only time the server moves anyone.

	Positions are plot-local (Base CFrame space, door at -Z). No Roblox APIs: runs unchanged under Lune.
]]

local PlotLockGuard = {}

PlotLockGuard.MIN_Y = -10 -- local height window that counts as "in" the plot
PlotLockGuard.MAX_Y = 60
PlotLockGuard.EXIT_GAP = 2.5 -- studs out from the stopper's outer face where a wedged character is set down
PlotLockGuard.DOOR_HEIGHT_PAD = 1 -- the doorway check reaches this far above the door

-- The doorway: |x| <= halfWidth, z from zOuter (the stopper's outer face) to zInner (its inner face), up to height.
export type Door = { halfWidth: number, zOuter: number, zInner: number, height: number }

local function inWindow(y: number): boolean
	return y >= PlotLockGuard.MIN_Y and y <= PlotLockGuard.MAX_Y
end

-- True when the point is inside the doorway (where the stopper stands while locked).
function PlotLockGuard.inDoorway(x: number, y: number, z: number, door: Door): boolean
	return math.abs(x) <= door.halfWidth
		and z >= door.zOuter
		and z <= door.zInner
		and y <= door.height + PlotLockGuard.DOOR_HEIGHT_PAD
		and inWindow(y)
end

-- True when this character must be set down outside: a non-owner in the doorway of a locked, owned plot.
function PlotLockGuard.wedged(
	userId: number,
	ownerId: number?,
	locked: boolean,
	x: number,
	y: number,
	z: number,
	door: Door
): boolean
	if not locked or ownerId == nil or ownerId == userId then
		return false
	end
	return PlotLockGuard.inDoorway(x, y, z, door)
end

-- Where a wedged character is set down: the same x, just outside the stopper (plot-local z).
function PlotLockGuard.doorwayExit(door: Door): number
	return door.zOuter - PlotLockGuard.EXIT_GAP
end

-- A plot's jar tower in plot-local terms: inner glass radius per floor, floor 1's walking height, storey height.
export type Jar = { radii: { number }, floorTop: number, floorHeight: number, wall: number }

PlotLockGuard.INSIDE_MARGIN = 1.5 -- studs in from the glass before a character counts as inside
PlotLockGuard.OUTSIDE_MARGIN = 2.5 -- studs out past the glass before a character inside counts as out again

--[[
	True when a character at plot-local (x, y, z) (y on the floorTop scale) is inside one of the plot's `floors`
	built jars. `wasInside` (last tick) keeps it inside until it is clearly past the glass, so standing against the
	stopper does not flicker in and out.
]]
function PlotLockGuard.insideJar(x: number, y: number, z: number, jar: Jar, floors: number, wasInside: boolean): boolean
	local built = math.min(floors, #jar.radii)
	if built < 1 then
		return false
	end
	local pad = if wasInside then 1 else 0
	local top = jar.floorTop + built * jar.floorHeight
	if y < jar.floorTop - 2 - pad or y > top + pad then
		return false
	end
	local f = math.clamp(math.floor((y - jar.floorTop) / jar.floorHeight) + 1, 1, built)
	local r = math.sqrt(x * x + z * z)
	local limit = if wasInside
		then jar.radii[f] + jar.wall + PlotLockGuard.OUTSIDE_MARGIN
		else jar.radii[f] - PlotLockGuard.INSIDE_MARGIN
	return r <= limit
end

-- True when a character that entered a plot at `enteredAt` got in after its current lock began: an intruder.
-- One already inside when the lock started is trapped instead (the LockBarrier blocks both ways).
function PlotLockGuard.intruder(enteredAt: number, lockStartedAt: number): boolean
	return enteredAt > lockStartedAt
end

-- Collision group names (stopper of plot i / the owner's character, which passes it).
function PlotLockGuard.lockGroup(index: number): string
	return `PlotLock_{index}`
end

function PlotLockGuard.ownerGroup(index: number): string
	return `PlotOwner_{index}`
end

return table.freeze(PlotLockGuard)
