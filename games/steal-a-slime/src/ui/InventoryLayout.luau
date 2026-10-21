--!strict
--[[
	InventoryLayout (S3 hotbar geometry, pure)

	The hotbar is a centred row of square slots: up to MAX_SLOTS item slots then the bag button that opens the
	inventory panel. `zone` is the box Layout.screen reserves for it (screen.hotbar: bottom-centre between the
	money and status clusters, or above them on a narrow portrait phone, always clear of the touch controls);
	the bar itself is centred in the zone and shrinks to the slots it needs. Numbers are design px.
	Takes plain numbers (no Layout require) so Layout.screen can reserve the zone from here.
]]

export type Rect = { x: number, y: number, w: number, h: number }
export type Bar = { rect: Rect, slots: { Rect }, bag: Rect, shown: number }

local InventoryLayout = {}

InventoryLayout.MAX_SLOTS = 9 -- number keys 1-9
InventoryLayout.SLOT = 52 -- desktop slot edge
InventoryLayout.GAP = 6
InventoryLayout.PAD = 6

-- Tight bar (portrait phone, 390 px wide: the money block and the events row share the hotbar's row): smaller
-- slots (below MIN_TOUCH, the width leaves no choice), pad and gap.
InventoryLayout.TIGHT = table.freeze({ slot = 42, gap = 4, pad = 4 })

-- Slot edge: desktop SLOT; on a phone at least `minTouch` design px (Layout.MIN_TOUCH_DESIGN); tight: TIGHT.slot.
function InventoryLayout.slotSize(compact: boolean, minTouch: number, tight: boolean?): number
	if tight then
		return InventoryLayout.TIGHT.slot
	end
	return if compact then math.max(InventoryLayout.SLOT, minTouch) else InventoryLayout.SLOT
end

local function gapOf(tight: boolean?): number
	return if tight then InventoryLayout.TIGHT.gap else InventoryLayout.GAP
end

local function padOf(tight: boolean?): number
	return if tight then InventoryLayout.TIGHT.pad else InventoryLayout.PAD
end

-- Bar height (slot plus padding) for a phone or desktop.
function InventoryLayout.height(compact: boolean, minTouch: number, tight: boolean?): number
	return InventoryLayout.slotSize(compact, minTouch, tight) + padOf(tight) * 2
end

function InventoryLayout.barWidth(cells: number, slot: number, tight: boolean?): number
	return cells * slot + (cells - 1) * gapOf(tight) + padOf(tight) * 2
end

-- Most item slots (the bag button takes one more cell) that fit `width`, at most MAX_SLOTS.
function InventoryLayout.maxItems(width: number, slot: number, tight: boolean?): number
	local cells = math.floor((width - padOf(tight) * 2 + gapOf(tight)) / (slot + gapOf(tight)))
	return math.clamp(cells - 1, 0, InventoryLayout.MAX_SLOTS)
end

-- The bar for `items` item slots (clamped to what fits) centred in `zone`, bottom-aligned. `items` is the last
-- filled hotbar slot: the empty slots before it are drawn too, so slot i stays on number key i.
function InventoryLayout.bar(zone: Rect, items: number, compact: boolean, minTouch: number, tight: boolean?): Bar
	local slot = InventoryLayout.slotSize(compact, minTouch, tight)
	local gap, pad = gapOf(tight), padOf(tight)
	local shown = math.min(items, InventoryLayout.maxItems(zone.w, slot, tight))
	local cells = shown + 1
	local w = InventoryLayout.barWidth(cells, slot, tight)
	local h = slot + pad * 2
	local x = zone.x + math.floor((zone.w - w) / 2)
	local y = zone.y + zone.h - h
	local slots: { Rect } = {}
	for i = 1, shown do
		table.insert(slots, {
			x = x + pad + (i - 1) * (slot + gap),
			y = y + pad,
			w = slot,
			h = slot,
		})
	end
	local bag = {
		x = x + pad + shown * (slot + gap),
		y = y + pad,
		w = slot,
		h = slot,
	}
	return { rect = { x = x, y = y, w = w, h = h }, slots = slots, bag = bag, shown = shown }
end

--[[
	Inventory panel body, top to bottom (design px, relative to the body):
	  "Hotbar" heading line (CELL.top), CELL.topGap,
	  the hotbar plate: the MAX_SLOTS slots on PLATE.rows rows of PLATE.columns (keys 1-9), centred,
	  PLATE.sectionGap, "Bag" heading line with the item count (CELL.top), CELL.topGap,
	  the bag grid (scrolls; its rows start CELL.gridPad down the canvas; the footer line sits in the scroll canvas under the grid, after PLATE.footerGap).
	The plate never scrolls: on a short card its slots shrink (down to PLATE.min) so the grid keeps PLATE.minGrid.
	When even that leaves the grid less than one cell tall (a landscape phone), the body goes side by side
	(InventoryLayout.arrange): the plate as a 3x3 block on the left, both headings on the top line, and the bag
	grid (it scrolls) filling the body's height to its right.
	Bag grid: square cells, `columns` per row (4 on a wide body, 3 below `wideMin`), each at most `max` px; at
	least `minRows` rows and always whole rows: the cells after the items are empty slots.
]]
InventoryLayout.CELL = table.freeze({
	gap = 10,
	max = 116,
	wideMin = 480,
	wideColumns = 4,
	narrowColumns = 3,
	minRows = 2,
	inset = 8, -- picture inset from the cell's top and sides
	name = 18, -- name line under the picture
	top = 28, -- a heading line
	topGap = 10, -- between a heading line and what it heads
	gridPad = 8, -- the bag grid's first row sits this far down its scroll canvas, clear of the "Bag" heading
})

InventoryLayout.PLATE = table.freeze({
	columns = 5,
	rows = 2,
	pad = 10, -- plate edge to the slots
	gap = 8, -- between slots
	max = 96, -- slot edge cap
	min = 48, -- slot edge floor on a short card (the desktop bar's SLOT)
	minGrid = 80, -- grid height a short card keeps under the plate
	sectionGap = 14, -- plate to the "Bag" heading
	footerGap = 8, -- grid to the footer line
	sideColumns = 3, -- side by side: the plate is a 3x3 block
	sideMax = 64, -- side by side: slot edge cap, the grid keeps the rest of the width
})

local function plateFixed(): number
	local c, p = InventoryLayout.CELL, InventoryLayout.PLATE
	return (c.top + c.topGap) * 2 + p.sectionGap
end

-- Plate slot edge for a body `bodyWidth` wide (and, when known, `bodyHeight` tall: then the plate leaves the
-- grid PLATE.minGrid, never below PLATE.min).
function InventoryLayout.plateSlot(bodyWidth: number, bodyHeight: number?): number
	local p = InventoryLayout.PLATE
	local slot = math.min(p.max, math.floor((bodyWidth - p.pad * 2 - (p.columns - 1) * p.gap) / p.columns))
	if bodyHeight then
		local room = bodyHeight - plateFixed() - p.minGrid - p.pad * 2 - (p.rows - 1) * p.gap
		slot = math.min(slot, math.floor(room / p.rows))
	end
	return math.max(p.min, slot)
end

function InventoryLayout.plateHeight(slot: number): number
	local p = InventoryLayout.PLATE
	return p.rows * slot + (p.rows - 1) * p.gap + p.pad * 2
end

-- The plate (relative to the body) and its MAX_SLOTS slots (relative to the plate), slot 1 top-left.
function InventoryLayout.plate(bodyWidth: number, slot: number): (Rect, { Rect })
	local c, p = InventoryLayout.CELL, InventoryLayout.PLATE
	local w = p.columns * slot + (p.columns - 1) * p.gap + p.pad * 2
	local rect =
		{ x = math.floor((bodyWidth - w) / 2), y = c.top + c.topGap, w = w, h = InventoryLayout.plateHeight(slot) }
	local slots: { Rect } = {}
	for i = 1, InventoryLayout.MAX_SLOTS do
		local col, row = (i - 1) % p.columns, (i - 1) // p.columns
		slots[i] = { x = p.pad + col * (slot + p.gap), y = p.pad + row * (slot + p.gap), w = slot, h = slot }
	end
	return rect, slots
end

-- Top of the "Bag" heading line and of the bag grid, for a plate of `slot` slots.
function InventoryLayout.bagTop(slot: number): (number, number)
	local c, p = InventoryLayout.CELL, InventoryLayout.PLATE
	local heading = c.top + c.topGap + InventoryLayout.plateHeight(slot) + p.sectionGap
	return heading, heading + c.top + c.topGap
end

-- The index of the rect in `rects` that holds point (x, y), or nil.
function InventoryLayout.hit(rects: { Rect }, x: number, y: number): number?
	for i, r in rects do
		if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then
			return i
		end
	end
	return nil
end

function InventoryLayout.columns(bodyWidth: number): number
	local c = InventoryLayout.CELL
	return if bodyWidth >= c.wideMin then c.wideColumns else c.narrowColumns
end

-- Cell edge for a body `width`: the columns fill it, capped at CELL.max.
function InventoryLayout.cellSize(bodyWidth: number): number
	local c = InventoryLayout.CELL
	local cols = InventoryLayout.columns(bodyWidth)
	return math.max(1, math.min(c.max, math.floor((bodyWidth - (cols - 1) * c.gap) / cols)))
end

-- Cells drawn for `count` items: whole rows, at least CELL.minRows of them.
function InventoryLayout.slotCount(count: number, bodyWidth: number): number
	local cols = InventoryLayout.columns(bodyWidth)
	return math.max(InventoryLayout.CELL.minRows, math.ceil(count / cols)) * cols
end

-- Height of `cells` cells laid out in rows.
function InventoryLayout.gridHeight(cells: number, bodyWidth: number): number
	local c = InventoryLayout.CELL
	local rows = math.ceil(cells / InventoryLayout.columns(bodyWidth))
	local size = InventoryLayout.cellSize(bodyWidth)
	return if rows <= 0 then 0 else rows * size + (rows - 1) * c.gap
end

-- Body content height for `count` bag items: the hotbar heading and plate, the bag heading, the grid with its
-- empty slots and (`footerHeight`, measured by the caller) the footer line under it.
function InventoryLayout.contentHeight(count: number, bodyWidth: number, footerHeight: number?): number
	local _, gridTop = InventoryLayout.bagTop(InventoryLayout.plateSlot(bodyWidth))
	local grid = InventoryLayout.gridHeight(InventoryLayout.slotCount(count, bodyWidth), bodyWidth)
	local footer = if footerHeight then InventoryLayout.PLATE.footerGap + footerHeight else 0
	return gridTop + InventoryLayout.CELL.gridPad + grid + footer
end

export type Arrangement = {
	side: boolean, -- plate left, grid right (a short body)
	slot: number, -- plate slot edge
	plate: Rect, -- relative to the body
	slots: { Rect }, -- relative to the plate
	barHeadingW: number, -- the "Hotbar" heading line's width (it starts at the body's left)
	bagHeadingX: number, -- the "Bag" heading line's left edge ...
	bagHeadingY: number,
	gridX: number, -- the bag grid (scroll frame) top-left, relative to the body
	gridY: number,
	gridW: number, -- width its cells are laid out in
}

-- Everything the panel places: stacked (the default) or, when `bodyHeight` is known and the stacked plate would
-- leave the grid less than one cell tall, side by side.
function InventoryLayout.arrange(bodyWidth: number, bodyHeight: number?): Arrangement
	local c, p = InventoryLayout.CELL, InventoryLayout.PLATE
	local slot = InventoryLayout.plateSlot(bodyWidth, bodyHeight)
	local headingY, gridY = InventoryLayout.bagTop(slot)
	if bodyHeight == nil or bodyHeight - gridY >= InventoryLayout.cellSize(bodyWidth) then
		local plate, slots = InventoryLayout.plate(bodyWidth, slot)
		return {
			side = false,
			slot = slot,
			plate = plate,
			slots = slots,
			barHeadingW = bodyWidth,
			bagHeadingX = 0,
			bagHeadingY = headingY,
			gridX = 0,
			gridY = gridY,
			gridW = bodyWidth,
		}
	end
	local n = p.sideColumns
	local top = c.top + c.topGap
	local fit = math.floor((bodyHeight - top - p.pad * 2 - (n - 1) * p.gap) / n)
	local sideSlot = math.clamp(fit, p.min, p.sideMax)
	local w = n * sideSlot + (n - 1) * p.gap + p.pad * 2
	local slots: { Rect } = {}
	for i = 1, InventoryLayout.MAX_SLOTS do
		local col, row = (i - 1) % n, (i - 1) // n
		slots[i] = {
			x = p.pad + col * (sideSlot + p.gap),
			y = p.pad + row * (sideSlot + p.gap),
			w = sideSlot,
			h = sideSlot,
		}
	end
	local gridX = w + c.gap
	return {
		side = true,
		slot = sideSlot,
		plate = { x = 0, y = top, w = w, h = n * sideSlot + (n - 1) * p.gap + p.pad * 2 },
		slots = slots,
		barHeadingW = w,
		bagHeadingX = gridX,
		bagHeadingY = 0,
		gridX = gridX,
		gridY = top,
		gridW = bodyWidth - gridX,
	}
end

return table.freeze(InventoryLayout)
