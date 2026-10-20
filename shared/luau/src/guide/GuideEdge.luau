--!strict
--[[
	GuideEdge (pure)

	Where a screen-edge pointer goes when the guide's target is off screen.
	Input is the target's viewport point (from Camera:WorldToViewportPoint)
	and whether it is in front of the camera. A target behind the camera
	projects mirrored, so its direction is flipped.

	  GuideEdge.place(x, y, inFront, width, height, margin)
	      -> { visible: boolean, x: number, y: number, angle: number }
	  angle is in degrees, 0 = pointing right, 90 = pointing down (GUI Rotation).
	  visible is false while the target is on screen (inside the margin).
]]

export type Placement = { visible: boolean, x: number, y: number, angle: number }

local GuideEdge = {}

function GuideEdge.place(
	x: number,
	y: number,
	inFront: boolean,
	width: number,
	height: number,
	margin: number
): Placement
	if inFront and x >= margin and x <= width - margin and y >= margin and y <= height - margin then
		return { visible = false, x = x, y = y, angle = 0 }
	end
	local cx, cy = width / 2, height / 2
	local dx, dy = x - cx, y - cy
	if not inFront then
		dx, dy = -dx, -dy
	end
	if math.abs(dx) < 1e-6 and math.abs(dy) < 1e-6 then
		dy = 1 -- straight behind: point down, toward "turn around"
	end
	local halfW, halfH = math.max(cx - margin, 0), math.max(cy - margin, 0)
	local scale = math.min(
		if math.abs(dx) > 1e-6 then halfW / math.abs(dx) else math.huge,
		if math.abs(dy) > 1e-6 then halfH / math.abs(dy) else math.huge
	)
	return {
		visible = true,
		x = cx + dx * scale,
		y = cy + dy * scale,
		angle = math.deg(math.atan2(dy, dx)),
	}
end

return table.freeze(GuideEdge)
