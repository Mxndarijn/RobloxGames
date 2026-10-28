--!strict
--[[
	GuideMarker (pure)

	Where the guide's marker floats when the target carries its own floating
	labels (a name tag, a price): above the highest of them instead of on top
	of them. A label is described by plain numbers read off a BillboardGui;
	its height is in studs plus pixels, so it depends on how far the camera is.

	  GuideMarker.labelTop(label, pxPerStud) -> number   -- world Y of the label's top edge
	  GuideMarker.top(baseY, labels, pxPerStud) -> number -- max of baseY and every label top
	  GuideMarker.pxPerStud(viewportHeight, fovDegrees, depth) -> number
]]

export type Label = {
	y: number, -- world Y of the label's anchor plus its world-space studs offset
	scaleY: number, -- Size.Y.Scale: studs
	offsetY: number, -- Size.Y.Offset: px
	sizeOffsetY: number, -- SizeOffset.Y: the centre sits this many label heights above the anchor
	pxPerStud: number?, -- screen px per stud at this label's depth (default: the caller's pxPerStud)
}

local GuideMarker = {}

-- Screen px per stud at `depth` studs in front of a camera with vertical field of view `fovDegrees` on a viewport
-- `viewportHeight` px tall.
function GuideMarker.pxPerStud(viewportHeight: number, fovDegrees: number, depth: number): number
	return viewportHeight / (2 * math.max(depth, 0.01) * math.tan(math.rad(fovDegrees) / 2))
end

-- World Y of the top edge of `label` at `pxPerStud` (the label's own when it has one).
function GuideMarker.labelTop(label: Label, pxPerStud: number): number
	local px = math.max(label.pxPerStud or pxPerStud, 1e-6)
	local height = label.scaleY + label.offsetY / px
	return label.y + height * label.sizeOffsetY + height / 2
end

-- The world Y the marker sits on: `baseY` (the top of the target), or higher when a label reaches above it.
function GuideMarker.top(baseY: number, labels: { Label }, pxPerStud: number): number
	local top = baseY
	for _, label in labels do
		top = math.max(top, GuideMarker.labelTop(label, pxPerStud))
	end
	return top
end

return table.freeze(GuideMarker)
