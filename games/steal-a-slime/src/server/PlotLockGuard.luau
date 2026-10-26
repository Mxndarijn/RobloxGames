--!strict
--[[
	PlotLockGuard (pure)

	Server-side rule for the plot lock. While a plot is locked, the LockBarrier (the cork stopper in jar 1's door)
	blocks every non-owner BOTH ways: nobody gets in, and a non-owner already inside stays inside until the lock ends
	(only the owner's character, in PlotOwner_<i>, passes it). There is no "leaver" pass any more: it let a character
	pushed or jumping into the stopper count as inside and walk through it.

	The lock never moves anyone. Guests the owner lets in (PlotGuests) pass the stopper too, and a guest who stops
	being one keeps passing it until they have left the jar (SlimeGuard.formerGuests).

	Positions are plot-local (Base CFrame space, door at -Z). No Roblox APIs: runs unchanged under Lune.
]]

local PlotLockGuard = {}

-- A plot's jar tower in plot-local terms: inner glass radius per floor, floor 1's walking height, storey height.
-- A base's walls per floor (BaseShapes.guard): radii, or half-widths of a square when `square` (the Goo Factory).
export type Jar = { radii: { number }, floorTop: number, floorHeight: number, wall: number, square: boolean? }

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
	local r = if jar.square then math.max(math.abs(x), math.abs(z)) else math.sqrt(x * x + z * z)
	local limit = if wasInside
		then jar.radii[f] + jar.wall + PlotLockGuard.OUTSIDE_MARGIN
		else jar.radii[f] - PlotLockGuard.INSIDE_MARGIN
	return r <= limit
end

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
