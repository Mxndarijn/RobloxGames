--!strict
--[[
	JarInside (pure)

	Where a point stands in a plot's base: inside its walls or not, and on which floor. Shared by the plot lock
	(SlimeGuardView: who is in which base), the steal rule (a thief must be inside the owner's base, on the slime's
	floor: Steal.canSteal's thiefInside) and the client, which hides the Steal prompt from anyone outside (StealReach).

	A base's walls come from BaseShapes (`guard`): radii per floor, or half-widths of a square when `square` (the Goo
	Factory). Positions are plot-local (Base CFrame space, door at -Z) with y on WorldLayout.floorTop's scale.
	No Roblox APIs: runs unchanged under Lune.
]]

-- A plot's base in plot-local terms: inner wall radius per floor, floor 1's walking height, storey height.
export type Jar = {
	radii: { number },
	floorTop: number,
	floorHeight: number,
	wall: number,
	square: boolean?,
	extra: { { x: number, z: number, r: number } }?, -- more round rooms inside on every floor (a stair turret)
	-- Plot-local height of the roof's outer surface over (x, z) while floor `top` is the top built floor (nil = no
	-- roof there). A dome starts below the next storey's height, so without it a player on the roof counts as inside.
	ceiling: ((top: number, x: number, z: number) -> number?)?,
}

local Economy = if script then require(script.Parent.Economy) else require("./Economy")

local JarInside = {}

JarInside.INSIDE_MARGIN = 1.5 -- studs in from the glass before a character counts as inside
JarInside.OUTSIDE_MARGIN = 2.5 -- studs out past the glass before a character inside counts as out again
-- A root this far above the roof's outer surface is standing on the roof (a standing root is about 3 studs up; one
-- inside stays about 3 studs under the glass, its head in between).
JarInside.ROOF_MARGIN = 0.5

-- Floors standing on a plot whose owner has `padsUnlocked` pads (a free plot counts as one).
function JarInside.builtFloors(padsUnlocked: number): number
	return if padsUnlocked > 0 then Economy.floorsShown(padsUnlocked) else 1
end

-- The floor (1..built floors) a plot-local height `y` is on.
function JarInside.floorAt(y: number, jar: Jar, floors: number): number
	local built = math.max(1, math.min(floors, #jar.radii))
	return math.clamp(math.floor((y - jar.floorTop) / jar.floorHeight) + 1, 1, built)
end

--[[
	True when plot-local (x, y, z) is inside one of the `floors` built floors of `jar`. `wasInside` (last tick) keeps a
	character inside until it is clearly past the glass, so standing against the stopper does not flicker in and out.
	On the top floor a point above the roof (`ceiling`) is outside: standing on the roof is not being in the base.
]]
function JarInside.inside(x: number, y: number, z: number, jar: Jar, floors: number, wasInside: boolean): boolean
	local built = math.min(floors, #jar.radii)
	if built < 1 then
		return false
	end
	local pad = if wasInside then 1 else 0
	local top = jar.floorTop + built * jar.floorHeight
	if y < jar.floorTop - 2 - pad or y > top + pad then
		return false
	end
	local f = JarInside.floorAt(y, jar, built)
	if f == built and jar.ceiling then
		local roof = jar.ceiling(built, x, z)
		if roof and y > roof + JarInside.ROOF_MARGIN + pad then
			return false
		end
	end
	local r = if jar.square then math.max(math.abs(x), math.abs(z)) else math.sqrt(x * x + z * z)
	local function within(radius: number, at: number): boolean
		local limit = if wasInside
			then radius + jar.wall + JarInside.OUTSIDE_MARGIN
			else radius - JarInside.INSIDE_MARGIN
		return at <= limit
	end
	if within(jar.radii[f], r) then
		return true
	end
	local extra = jar.extra
	if extra then
		for _, e in extra do
			local dx, dz = x - e.x, z - e.z
			if within(e.r, math.sqrt(dx * dx + dz * dz)) then
				return true
			end
		end
	end
	return false
end

--[[
	True when a thief at plot-local `thief` may steal the slime at plot-local `slime` as far as the walls go: the thief
	is inside the base (strict, no hysteresis) and on the slime's floor. Distance is checked on its own
	(STEAL_REACH): the glass lets prompts through, and every pad is within reach of a spot just outside it.
]]
function JarInside.canReach(thief: { number }, slime: { number }, jar: Jar, floors: number): boolean
	if not JarInside.inside(thief[1], thief[2], thief[3], jar, floors, false) then
		return false
	end
	return JarInside.floorAt(thief[2], jar, floors) == JarInside.floorAt(slime[2], jar, floors)
end

return table.freeze(JarInside)
