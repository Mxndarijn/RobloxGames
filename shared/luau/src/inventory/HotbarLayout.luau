--!strict
--[[
	HotbarLayout: pure geometry for the default hotbar and inventory grid, in pixels.

	The bar is a centred row of square slots followed by the bag button that opens the grid. It is laid out
	inside a `zone` rectangle the game reserves for it (bottom-centre by default), bottom-aligned, and shows
	only as many slots as fit. Sizes come from a `Metrics` table so a game can restyle without code changes.
]]

export type Rect = { x: number, y: number, w: number, h: number }
export type Bar = { rect: Rect, slots: { Rect }, bag: Rect?, shown: number }
export type Metrics = {
	slot: number, -- slot edge
	gap: number,
	pad: number, -- padding around the row
	minTouch: number, -- smallest slot edge on touch screens
	maxSlots: number,
	bag: boolean, -- show the bag button
	cell: { w: number, h: number, gap: number }, -- grid cells
}

local HotbarLayout = {}

HotbarLayout.DEFAULT = table.freeze({
	slot = 52,
	gap = 6,
	pad = 6,
	minTouch = 48,
	maxSlots = 9,
	bag = true,
	cell = table.freeze({ w = 88, h = 96, gap = 8 }),
} :: Metrics)

-- `overrides` merged over DEFAULT (one level deep, `cell` merged too).
function HotbarLayout.metrics(overrides: { [string]: any }?): Metrics
	local m = table.clone(HotbarLayout.DEFAULT) :: any
	if overrides then
		for k, v in overrides do
			if k == "cell" and type(v) == "table" then
				local cell = table.clone(HotbarLayout.DEFAULT.cell) :: any
				for ck, cv in v do
					cell[ck] = cv
				end
				m.cell = table.freeze(cell)
			else
				m[k] = v
			end
		end
	end
	return table.freeze(m) :: Metrics
end

function HotbarLayout.slotSize(m: Metrics, touch: boolean): number
	return if touch then math.max(m.slot, m.minTouch) else m.slot
end

function HotbarLayout.barWidth(m: Metrics, cells: number, slot: number): number
	if cells <= 0 then
		return 0
	end
	return cells * slot + (cells - 1) * m.gap + m.pad * 2
end

-- Most item slots that fit `width` (the bag takes one cell when shown), at most maxSlots.
function HotbarLayout.maxItems(m: Metrics, width: number, slot: number): number
	local cells = math.floor((width - m.pad * 2 + m.gap) / (slot + m.gap))
	local items = if m.bag then cells - 1 else cells
	return math.clamp(items, 0, m.maxSlots)
end

-- The bar for `items` item slots, clamped to what fits, centred in `zone` and on its bottom edge.
function HotbarLayout.bar(m: Metrics, zone: Rect, items: number, touch: boolean): Bar
	local slot = HotbarLayout.slotSize(m, touch)
	local shown = math.min(items, HotbarLayout.maxItems(m, zone.w, slot))
	local cells = shown + (if m.bag then 1 else 0)
	local w = HotbarLayout.barWidth(m, cells, slot)
	local h = slot + m.pad * 2
	local x = zone.x + math.floor((zone.w - w) / 2)
	local y = zone.y + zone.h - h
	local slots: { Rect } = {}
	for i = 1, shown do
		table.insert(slots, { x = x + m.pad + (i - 1) * (slot + m.gap), y = y + m.pad, w = slot, h = slot })
	end
	local bag = if m.bag then { x = x + m.pad + shown * (slot + m.gap), y = y + m.pad, w = slot, h = slot } else nil
	return { rect = { x = x, y = y, w = w, h = h }, slots = slots, bag = bag, shown = shown }
end

-- Default zone: a strip along the bottom of the screen, `margin` px up from the edge.
function HotbarLayout.defaultZone(m: Metrics, screenW: number, screenH: number, touch: boolean, margin: number?): Rect
	local h = HotbarLayout.slotSize(m, touch) + m.pad * 2
	local inset = margin or 12
	return { x = inset, y = screenH - h - inset, w = math.max(0, screenW - inset * 2), h = h }
end

function HotbarLayout.columns(m: Metrics, bodyWidth: number): number
	return math.max(1, math.floor((bodyWidth + m.cell.gap) / (m.cell.w + m.cell.gap)))
end

function HotbarLayout.gridHeight(m: Metrics, count: number, bodyWidth: number): number
	local rows = math.ceil(count / HotbarLayout.columns(m, bodyWidth))
	return if rows <= 0 then 0 else rows * m.cell.h + (rows - 1) * m.cell.gap
end

-- Cell rectangle `index` (1-based) of the grid, relative to the grid's top-left.
function HotbarLayout.cell(m: Metrics, index: number, bodyWidth: number): Rect
	local cols = HotbarLayout.columns(m, bodyWidth)
	local col = (index - 1) % cols
	local row = (index - 1) // cols
	return { x = col * (m.cell.w + m.cell.gap), y = row * (m.cell.h + m.cell.gap), w = m.cell.w, h = m.cell.h }
end

return table.freeze(HotbarLayout)
