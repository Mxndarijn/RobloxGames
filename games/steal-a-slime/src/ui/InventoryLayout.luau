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
InventoryLayout.SLOT = 48 -- desktop slot edge
InventoryLayout.GAP = 6
InventoryLayout.PAD = 6

-- Tight bar (portrait phone, 390 px wide: the money block and the events row share the hotbar's row): smaller
-- slots (below MIN_TOUCH, the width leaves no choice), pad and gap.
InventoryLayout.TIGHT = table.freeze({ slot = 40, gap = 4, pad = 4 })

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

-- The bar for `items` item slots (clamped to what fits) centred in `zone`, bottom-aligned.
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

-- Inventory panel: a top line (hint and item count) over a grid of square cells, `columns` per row (4 on a wide
-- body, 3 below `wideMin`), each at most `max` px. The grid shows at least `minRows` rows and always whole
-- rows: the cells after the items are empty slots, so the card never shows a blank area.
InventoryLayout.CELL = table.freeze({
	gap = 10,
	max = 116,
	wideMin = 480,
	wideColumns = 4,
	narrowColumns = 3,
	minRows = 2,
	inset = 8, -- picture inset from the cell's top and sides
	name = 18, -- name line under the picture
	top = 28, -- the top line
	topGap = 10, -- between the top line and the grid
})

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

-- Body content height for `count` items: the top line, its gap and the grid with its empty slots.
function InventoryLayout.contentHeight(count: number, bodyWidth: number): number
	local c = InventoryLayout.CELL
	return c.top + c.topGap + InventoryLayout.gridHeight(InventoryLayout.slotCount(count, bodyWidth), bodyWidth)
end

return table.freeze(InventoryLayout)
