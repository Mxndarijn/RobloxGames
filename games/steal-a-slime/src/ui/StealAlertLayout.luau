--!strict
--[[
	StealAlertLayout (FEATURES.StealAlerts, CONTRACT.md §17): where the thief arrow and the edge flash may
	draw so they never cover the banner stack or the nav. Pure (tests/ui/StealAlertLayout.spec);
	all values are Layout design px (the ScreenGui carries the UIScale).
]]

local Layout = if script then require(script.Parent.Layout) else require("./Layout")

local StealAlertLayout = {}

StealAlertLayout.ARROW = 44 -- the arrow glyph box
StealAlertLayout.LABEL_W = 120 -- the "N studs" label under it (centred on the arrow)
StealAlertLayout.LABEL_DROP = 26 -- label top below the arrow centre
StealAlertLayout.LABEL_H = 18
StealAlertLayout.FLASH = 40 -- edge flash thickness where nothing hugs the edge

-- The box the arrow (with its distance label) stays in: right of the nav, under the shown
-- banner stack (`bannerH`), `Layout.MARGIN` from the other edges.
function StealAlertLayout.safeRect(screen: Layout.Screen, bannerH: number): Layout.Rect
	local m, gap = Layout.MARGIN, Layout.GAP
	local x = screen.nav.x + screen.nav.w + gap
	local bottomOfBanners = if bannerH > 0 then screen.banners.y + bannerH else 0
	local y = math.max(Layout.TOP, bottomOfBanners) + gap
	return Layout.rect(x, y, math.max(screen.width - m - x, 0), math.max(screen.height - m - y, 0))
end

-- Box (arrow + label, top-left origin) for `angle`: the arrow centre sits on the ellipse inside the safe
-- rect, so the whole box stays in it. `edgePoint` is StealAlert.edgePoint (margin 0).
function StealAlertLayout.arrowBox(
	screen: Layout.Screen,
	bannerH: number,
	edgePoint: (number, number, number, number) -> (number, number),
	angle: number
): Layout.Rect
	local safe = StealAlertLayout.safeRect(screen, bannerH)
	local boxW = StealAlertLayout.LABEL_W
	local boxH = StealAlertLayout.ARROW / 2 + StealAlertLayout.LABEL_DROP + StealAlertLayout.LABEL_H
	local cx, cy = edgePoint(angle, math.max(safe.w - boxW, 0), math.max(safe.h - boxH, 0), 0)
	return Layout.rect(safe.x + cx, safe.y + cy, boxW, boxH)
end

-- Where the box puts the arrow centre (the label hangs LABEL_DROP below it).
function StealAlertLayout.arrowCentre(box: Layout.Rect): (number, number)
	return box.x + box.w / 2, box.y + StealAlertLayout.ARROW / 2
end

-- Edge flash thickness: phones keep it in the gap between the viewport edge and the nav tiles,
-- so it never tints them.
function StealAlertLayout.flashThickness(screen: Layout.Screen): number
	if not screen.compact then
		return StealAlertLayout.FLASH
	end
	return math.max(math.min(StealAlertLayout.FLASH, screen.nav.x, screen.nav.y), 0)
end

return table.freeze(StealAlertLayout)
