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

-- Slot edge: desktop SLOT; on a phone at least `minTouch` design px (Layout.MIN_TOUCH_DESIGN).
function InventoryLayout.slotSize(compact: boolean, minTouch: number): number
	return if compact then math.max(InventoryLayout.SLOT, minTouch) else InventoryLayout.SLOT
end

-- Bar height (slot plus padding) for a phone or desktop.
function InventoryLayout.height(compact: boolean, minTouch: number): number
	return InventoryLayout.slotSize(compact, minTouch) + InventoryLayout.PAD * 2
end

function InventoryLayout.barWidth(cells: number, slot: number): number
	return cells * slot + (cells - 1) * InventoryLayout.GAP + InventoryLayout.PAD * 2
end

-- Most item slots (the bag button takes one more cell) that fit `width`, at most MAX_SLOTS.
function InventoryLayout.maxItems(width: number, slot: number): number
	local cells = math.floor((width - InventoryLayout.PAD * 2 + InventoryLayout.GAP) / (slot + InventoryLayout.GAP))
	return math.clamp(cells - 1, 0, InventoryLayout.MAX_SLOTS)
end

-- The bar for `items` item slots (clamped to what fits) centred in `zone`, bottom-aligned.
function InventoryLayout.bar(zone: Rect, items: number, compact: boolean, minTouch: number): Bar
	local slot = InventoryLayout.slotSize(compact, minTouch)
	local shown = math.min(items, InventoryLayout.maxItems(zone.w, slot))
	local cells = shown + 1
	local w = InventoryLayout.barWidth(cells, slot)
	local h = slot + InventoryLayout.PAD * 2
	local x = zone.x + math.floor((zone.w - w) / 2)
	local y = zone.y + zone.h - h
	local slots: { Rect } = {}
	for i = 1, shown do
		table.insert(slots, {
			x = x + InventoryLayout.PAD + (i - 1) * (slot + InventoryLayout.GAP),
			y = y + InventoryLayout.PAD,
			w = slot,
			h = slot,
		})
	end
	local bag = {
		x = x + InventoryLayout.PAD + shown * (slot + InventoryLayout.GAP),
		y = y + InventoryLayout.PAD,
		w = slot,
		h = slot,
	}
	return { rect = { x = x, y = y, w = w, h = h }, slots = slots, bag = bag, shown = shown }
end

-- Inventory panel grid: cells per row for a body `width` and the canvas height for `count` items.
InventoryLayout.CELL = table.freeze({ w = 96, h = 104, gap = 8, icon = 56 })

function InventoryLayout.columns(bodyWidth: number): number
	local c = InventoryLayout.CELL
	return math.max(1, math.floor((bodyWidth + c.gap) / (c.w + c.gap)))
end

function InventoryLayout.gridHeight(count: number, bodyWidth: number): number
	local c = InventoryLayout.CELL
	local rows = math.ceil(count / InventoryLayout.columns(bodyWidth))
	return if rows <= 0 then 0 else rows * c.h + (rows - 1) * c.gap
end

return table.freeze(InventoryLayout)
