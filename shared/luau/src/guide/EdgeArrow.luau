--!strict
--[[
	EdgeArrow (pure)

	Off-screen pointers: where an arrow on the screen edge goes and which way it
	points so it leads to a world target (a home marker, a thief to chase).
	No Roblox APIs. GuideEdge does the same from a viewport projection; EdgeArrow
	works in camera space and also handles targets beside the camera.

	The direction comes from the target in camera space (camera.CFrame:PointToObjectSpace),
	not from a screen projection: a projection flips and blows up for targets beside or
	behind the camera. In front, the direction matches where the target would be drawn;
	behind, the arrow goes to the bottom edge, leaning to the target's side.

	EdgeArrow.direction(rel) -> (dx, dy)              -- screen direction, y down, unit length
	EdgeArrow.place(origin, dx, dy, rect) -> Arrow     -- on `rect`'s edge along the ray from `origin`
	EdgeArrow.inside(point, rect) -> boolean
]]

export type Vec3 = { x: number, y: number, z: number }
export type Point = { x: number, y: number }
-- Screen box, any pixel space: left / top / right / bottom edges.
export type Rect = { left: number, top: number, right: number, bottom: number }
-- Arrow centre and angle in degrees (0 = right, 90 = down: Roblox GuiObject.Rotation for a right-pointing glyph).
export type Arrow = { x: number, y: number, angle: number }

local EdgeArrow = {}

local EPS = 1e-6

local function finite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

-- Screen direction (x right, y down, unit) towards `rel`, the target in camera space
-- (Roblox: +X right, +Y up, -Z forward). Behind the camera it points down the screen,
-- leaning to the target's side. Straight ahead or degenerate input points down.
function EdgeArrow.direction(rel: Vec3): (number, number)
	local x, y, z = rel.x, rel.y, rel.z
	if not (finite(x) and finite(y) and finite(z)) then
		return 0, 1
	end
	local dx, dy = x, -y
	if z > 0 then
		-- Behind: never point up the screen (that reads as "ahead"), push down by how far behind.
		dy = math.max(dy, 0) + z
	end
	local len = math.sqrt(dx * dx + dy * dy)
	if len < EPS then
		return 0, 1
	end
	return dx / len, dy / len
end

-- True when `point` lies inside `rect` (edges included).
function EdgeArrow.inside(point: Point, rect: Rect): boolean
	return point.x >= rect.left and point.x <= rect.right and point.y >= rect.top and point.y <= rect.bottom
end

-- The arrow spot: where the ray from `origin` along (dx, dy) leaves `rect`. `origin` is
-- where the camera looks (the screen spot straight ahead), so an arrow there points the
-- same way the target lies on screen. An origin outside `rect` is clamped into it first.
function EdgeArrow.place(origin: Point, dx: number, dy: number, rect: Rect): Arrow
	local left, top = rect.left, rect.top
	local right, bottom = math.max(rect.right, left), math.max(rect.bottom, top)
	local ox = math.clamp(if finite(origin.x) then origin.x else (left + right) / 2, left, right)
	local oy = math.clamp(if finite(origin.y) then origin.y else (top + bottom) / 2, top, bottom)
	if not (finite(dx) and finite(dy)) or (math.abs(dx) < EPS and math.abs(dy) < EPS) then
		dx, dy = 0, 1
	end
	local t = math.huge
	if dx > EPS then
		t = math.min(t, (right - ox) / dx)
	elseif dx < -EPS then
		t = math.min(t, (left - ox) / dx)
	end
	if dy > EPS then
		t = math.min(t, (bottom - oy) / dy)
	elseif dy < -EPS then
		t = math.min(t, (top - oy) / dy)
	end
	if not finite(t) then
		t = 0
	end
	return {
		x = math.clamp(ox + dx * t, left, right),
		y = math.clamp(oy + dy * t, top, bottom),
		angle = math.deg(math.atan2(dy, dx)),
	}
end

return table.freeze(EdgeArrow)
