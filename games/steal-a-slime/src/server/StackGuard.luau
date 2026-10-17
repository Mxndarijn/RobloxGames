--!strict
--[[
	StackGuard (pure)

	Server-side eject for the fountain-top slime stack (Map.Volcano.EmergeMesh, bug #10). A solid mesh does not push
	out a character whose root already overlaps it (Hull / Box only resolve contacts), so like PlotLockGuard the
	server moves it: a root inside the stack's oriented bounding box goes to just above the top, or radially outside
	when the space above is blocked. Positions are box-local (the mesh's own CFrame), half = half extents.
	No Roblox APIs: runs unchanged under Lune.
]]

local StackGuard = {}

StackGuard.MARGIN = 0.5 -- studs the box is shrunk sideways before the guard reacts
StackGuard.TOP_SLACK = 1.5 -- a root this far over the top or lower counts as "in" (standing on top is ~3 up)
StackGuard.LIFT = 4 -- root height over the top after an eject (feet clear the surface)
StackGuard.OUTSIDE = 4 -- studs past the side when the top is blocked

-- True when the root (box-local x, y, z) is inside the box.
function StackGuard.inside(x: number, y: number, z: number, hx: number, hy: number, hz: number): boolean
	local m = StackGuard.MARGIN
	return math.abs(x) < hx - m and math.abs(z) < hz - m and y > -hy and y < hy + StackGuard.TOP_SLACK
end

-- Box-local point to move an inside root to; `topBlocked` (something overhead) pushes it out sideways instead.
function StackGuard.ejectPoint(
	x: number,
	y: number,
	z: number,
	hx: number,
	hy: number,
	hz: number,
	topBlocked: boolean?
): (number, number, number)
	if not topBlocked then
		return x, hy + StackGuard.LIFT, z
	end
	-- nearest side face, measured in half extents so a long box does not always pick its long side
	local fx, fz = (hx - math.abs(x)) / hx, (hz - math.abs(z)) / hz
	if fx <= fz then
		return (if x < 0 then -1 else 1) * (hx + StackGuard.OUTSIDE), y, z
	end
	return x, y, (if z < 0 then -1 else 1) * (hz + StackGuard.OUTSIDE)
end

return table.freeze(StackGuard)
