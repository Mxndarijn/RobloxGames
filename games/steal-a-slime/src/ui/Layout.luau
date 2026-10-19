--!strict
--[[
	Layout

	Pure layout rules shared by the UI and its tests (tests/ui/Layout.spec,
	tests/ui/LayoutAssert): the ZIndex layers of the top-level overlays,
	scroll list settings, the root UIScale, touch-target sizes and the
	rectangles of the bottom clusters, left nav, full-window menu panels and bottom cards. No
	Instances here; Widgets / Hud / init.client apply them.

	Coordinates are design px: the ScreenGui's AbsoluteSize divided by
	`uiScale` (the root UIScale multiplies everything back). A Rect is
	{ x, y, w, h } from the top-left of the ScreenGui.

	Target viewports (v18): 390x844 phone (scale MIN_SCALE, "compact", room kept
	for Roblox's touch controls) and 1920x1080 desktop (scale 1).
	v27: landscape phone (844x390, 844x332 under the top bar) is "short": the
	nav tiles take more columns above the money cluster and the bottom cards sit
	between the two bottom clusters, so every nav tile stays on screen
	(Layout.screen).
	H1 (2026-10-17): the money (bottom-left) and status (bottom-right)
	clusters sit on the bottom inset line; on phones they are lifted
	TOUCH_RISE px off the touch controls and portrait cards sit above them.
	Oct 18: no top bar and no toasts any more (B6 / B7); the left nav is a grid of
	rounded tiles, icon over label, 2 columns (B5); the bottom clusters are bigger
	(B4) and a status icon can show a tooltip (B8, Layout.statusTooltip).
]]

local InventoryLayout = if script then require(script.Parent.InventoryLayout) else require("./InventoryLayout")
local Nav = if script then require(script.Parent.Nav) else require("./Nav")
local Tutorial = if script then require(script.Parent.Tutorial) else require("./Tutorial")

export type Rect = { x: number, y: number, w: number, h: number }
-- Bottom-left cluster (H1): the money plate, the income / rebirths chips under it.
export type MoneyHud = { rect: Rect, cash: Rect, income: Rect, rebirths: Rect }
-- Bottom-right cluster (H1): STATUS.count icon slots, [1] leftmost; shown ones pack to the right.
export type StatusHud = { rect: Rect, slots: { Rect } }
export type Screen = {
	viewportW: number,
	viewportH: number,
	scale: number,
	width: number, -- design px
	height: number,
	compact: boolean,
	phone: boolean, -- a phone (portrait, or landscape under 500 px high): money | hotbar | events share the bottom row
	tight: boolean, -- portrait phone too narrow for the full-size row: smaller money block, event slots and hotbar slots
	short: boolean, -- landscape phone: more nav columns, cards between the clusters (Layout.screen)
	navColumns: number,
	bottomInset: number,
	money: MoneyHud, -- bottom-left: Money, Income/s, Rebirths (above the touch inset)
	status: StatusHud, -- bottom-right: event timers + friend boost (above the touch inset)
	hotbar: Rect, -- S3 inventory hotbar zone: bottom-centre between the clusters (above them on a narrow phone)
	banners: Rect,
	sound: Rect, -- FEATURES.Audio button: the top-right slot a menu's X would use (hidden while a menu is open)
	nav: Rect,
	navButtons: { Rect }, -- Nav.ENTRIES order (a tile and its label)
	column: Rect, -- right of the nav, above the bottom cards
	panel: Rect, -- full-window menu backdrop: column width, top margin to bottom inset
	menuX: number, -- left edge of every menu card (Layout.panelFor)
	menuW: number, -- width of every menu card
	carry: Rect,
	tutorial: Rect,
	tutorialCarrying: Rect, -- the tutorial card while the carry panel shows
	daily: Rect,
}

local Layout = {}

-- Esc closes an open menu when true (v27 gate A4). Only while a menu is open
-- (init.client passes the key on otherwise); the panel X and gamepad B
-- always close.
Layout.CLOSE_WITH_ESCAPE = true

-- Top-level ZIndex per overlay (ScreenGui uses ZIndexBehavior.Sibling, so
-- children render with their parent). Higher draws on top: banners over
-- menu panels, the tutorial over the daily popup, and the carry panel
-- (Drop) over both.
Layout.ZINDEX = table.freeze({
	Base = 1, -- bottom clusters, nav, the menu backdrop
	Menu = 2, -- menu cards (over the backdrop, whatever their sibling order)
	Banners = 3, -- HUD banners and the tutorial hint
	Daily = 5,
	Tutorial = 15,
	Carry = 30,
})

-- Scroll lists: rows start at the top (VerticalAlignment Center clipped the
-- first / last rows, v15 playtest) with padding so neither edge is cut off.
-- Rows are placed by Layout.stackRows (Widgets.restack), not a UIListLayout:
-- list sync often runs while the panel is Visible=false (init setOpen) and the
-- engine then never reflows, stacking every row at Y=0 (v26 live shop).
Layout.SCROLL_LIST = table.freeze({
	paddingTop = 4,
	paddingBottom = 8,
})

-- Y offsets for scroll-list rows of the given heights (design px; starts at
-- SCROLL_LIST.paddingTop, `gap` between rows) and the canvas height.
function Layout.stackRows(heights: { number }, gap: number): ({ number }, number)
	local rules = Layout.SCROLL_LIST
	local ys = {}
	local y = rules.paddingTop
	for i, h in heights do
		if i > 1 then
			y += gap
		end
		ys[i] = y
		y += math.max(h, 0)
	end
	return ys, y + rules.paddingBottom
end

-- UIScale for the root ScreenGui: 1 on desktop, smaller on phones. Never
-- below MIN_SCALE so a MIN_TOUCH_DESIGN button is still a thumb target.
Layout.DESIGN_WIDTH = 1280
Layout.DESIGN_HEIGHT = 720
Layout.MIN_SCALE = 0.8

-- Smallest on-screen hit size (px, after UIScale) for anything tappable.
Layout.MIN_TOUCH = 44

-- Below this ScreenGui width (or any scale < 1) the UI is "compact".
Layout.COMPACT_WIDTH = 600

-- Roblox's thumbstick / jump button cover the bottom ~90 screen px on
-- phones; compact bottom cards sit above them.
Layout.TOUCH_CONTROLS_HEIGHT = 90

-- The H1 bottom clusters (money, status) sit this many screen px above that strip on compact (phone)
-- layouts, so they also clear the top of Roblox's jump button (bottom-right, ~125 px up) and the
-- thumbstick (bottom-left).
Layout.TOUCH_RISE = 40

-- Landscape phones (wider than tall, phone-sized): the bottom row sits this many screen px above the bottom
-- edge instead of clearing the thumbstick / jump button (no rise). The ScreenGui already starts inside the
-- system safe area (IgnoreGuiInset = false), so a small inset is enough. Gated at <= LANDSCAPE_INSET_MAX.
Layout.LANDSCAPE_BOTTOM_INSET = 10
Layout.LANDSCAPE_INSET_MAX = 16

Layout.MARGIN = 12
Layout.TOP = 12 -- top margin: nav on short screens, the banner stack and the menu card area
Layout.GAP = 12

local function finite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

function Layout.uiScale(width: number, height: number): number
	if not finite(width) or not finite(height) or width <= 0 or height <= 0 then
		return 1
	end
	local scale = math.min(width / Layout.DESIGN_WIDTH, height / Layout.DESIGN_HEIGHT)
	return math.clamp(scale, Layout.MIN_SCALE, 1)
end

-- Design px a control needs so it is MIN_TOUCH screen px at `scale`.
function Layout.minTouchDesignSize(scale: number): number
	if not finite(scale) or scale <= 0 then
		return Layout.MIN_TOUCH
	end
	return math.ceil(Layout.MIN_TOUCH / scale)
end

-- Every button is at least this big (design px), so it passes MIN_TOUCH at
-- any scale the UI can reach.
Layout.MIN_TOUCH_DESIGN = Layout.minTouchDesignSize(Layout.MIN_SCALE)
Layout.BUTTON = 56

function Layout.isCompact(width: number, height: number): boolean
	return width < Layout.COMPACT_WIDTH or Layout.uiScale(width, height) < 1
end

-- ScreenGui size -> design size.
function Layout.designSize(width: number, height: number): (number, number)
	local scale = Layout.uiScale(width, height)
	return width / scale, height / scale
end

-- Rect helpers ---------------------------------------------------------------

function Layout.rect(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = w, h = h }
end

function Layout.overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- True when `r` lies inside a width x height viewport, `margin` from each edge.
function Layout.fitsInViewport(r: Rect, width: number, height: number, margin: number?): boolean
	local m = margin or 0
	return r.w >= 0 and r.h >= 0 and r.x >= m and r.y >= m and r.x + r.w <= width - m and r.y + r.h <= height - m
end

-- Which of two overlay layers draws on top ("Daily" < "Tutorial" < "Carry").
function Layout.drawsAbove(top: string, below: string): boolean
	local z = Layout.ZINDEX :: any
	local a, b = z[top], z[below]
	assert(type(a) == "number" and type(b) == "number", `unknown layer {top} / {below}`)
	return a > b
end

-- Text estimate ----------------------------------------------------------------
-- A char-width heuristic for Gotham (em fractions), good enough to catch
-- labels that would truncate. Bold is ~6% wider.

local NARROW = "ilIjtfr!.,:;'|/ ()[]"
local WIDE = "mwMW%@"

local function charWidth(codepoint: number): number
	if codepoint >= 0x2000 then
		return 1.15 -- emoji / symbols
	end
	local ch = string.char(codepoint)
	if string.find(NARROW, ch, 1, true) then
		return 0.3
	elseif string.find(WIDE, ch, 1, true) then
		return 0.85
	elseif string.match(ch, "%u") then
		return 0.68
	elseif string.match(ch, "%d") or ch == "$" then
		return 0.6
	end
	return 0.56
end

Layout.LINE_HEIGHT = 1.15

-- Width (px) of one line of text.
function Layout.lineWidth(line: string, size: number, bold: boolean?): number
	local em = 0
	for _, codepoint in utf8.codes(line) do
		if codepoint ~= 0xFE0F then -- emoji variation selector
			em += charWidth(codepoint)
		end
	end
	return em * size * (if bold then 1.06 else 1)
end

-- Widest line of `text` and its line count ("\n" separated, no wrapping).
function Layout.textSize(text: string, size: number, bold: boolean?): (number, number)
	local widest, lines = 0, 0
	for _, line in string.split(text, "\n") do
		widest = math.max(widest, Layout.lineWidth(line, size, bold))
		lines += 1
	end
	return widest, lines * size * Layout.LINE_HEIGHT
end

-- Height of `text` word-wrapped into `boxWidth` (15% slack for word breaks).
function Layout.wrappedHeight(text: string, size: number, boxWidth: number, bold: boolean?): number
	local lines = 0
	for _, line in string.split(text, "\n") do
		lines += math.max(1, math.ceil(Layout.lineWidth(line, size, bold) * 1.15 / math.max(boxWidth, 1)))
	end
	return lines * size * Layout.LINE_HEIGHT
end

-- Bottom clusters (H1) -----------------------------------------------------------
-- Money (bottom-left, as in the reference): a plate with the coin and the big amount, the income/s
-- and rebirths chips under it. Status (bottom-right): up to STATUS.count icon slots with a timer or
-- a label under each. Both sit on the bottom inset line (above Roblox's thumbstick / jump button).

-- B4 (Merijn, ui_reference.png): both clusters are about twice the H1 size; the PC money block is a further
-- ~1.4x (2026-10-18) to match the concept's proportions. `c`-prefixed values are the phone
-- (compact) sizes; they are still bigger than the H1 desktop ones.
Layout.MONEY = table.freeze({
	w = 360,
	cw = 212,
	plate = 96, -- coin diameter = height of the coin + pill zone (the pill is a little shorter, `padV` each side)
	cplate = 52,
	chip = 42,
	cchip = 26,
	overlap = 8, -- the chips tuck this far up under the pill's bottom edge
	coverlap = 5,
	tab = 12, -- the small rounded tab under the income chip (counts in the block's height)
	ctab = 7,
	icon = 96, -- the coin (square)
	cicon = 52,
	amountSize = 48,
	camountSize = 28,
	chipSize = 21,
	cchipSize = 13,
	-- The rebirths chip: its share of the chip row (it holds the emblem, count and badge), the emblem's
	-- size as a multiple of the chip height (it stays inside the chip), the count and badge text.
	rebirthShare = 0.58,
	crebirthShare = 0.55,
	emblem = 0.9,
	cemblem = 0.9,
	rebirthSize = 26,
	crebirthSize = 15,
	badgeSize = 19,
	cbadgeSize = 11,
})

-- Each status slot is an icon with its timer in a dark pill tucked `overlap` px up over the icon's bottom edge,
-- centred under it. The row's bottom (the pills) sits on the money block's line, level with the hotbar
-- (`raise` = 0, Merijn 2026-10-19: the old 18 px lift made the icons float above the rest of the bottom row).
Layout.STATUS = table.freeze({
	count = 4,
	slot = 92,
	cslot = 64,
	icon = 76,
	cicon = 54,
	label = 26, -- timer pill height
	clabel = 20,
	labelSize = 18,
	clabelSize = 14,
	overlap = 10,
	coverlap = 7,
	pillPad = 8, -- pill padding left and right of the text
	cpillPad = 6,
	gap = 4,
	raise = 0,
	phoneColumns = 2,
})

-- Tight phone row (portrait, 390 px wide: money | hotbar | events share one bottom row): smaller money block
-- (the two chips stack under the plate) and event slots. Used when Layout.screen sets `tight`.
Layout.MONEY_TIGHT = table.freeze({
	w = 124,
	plate = 40,
	chip = 20,
	overlap = 4,
	tab = 4,
	icon = 40,
	amountSize = 18,
	chipSize = 11,
	rebirthShare = 0.5,
	emblem = 0.8,
	rebirthSize = 11,
	badgeSize = 8,
})
Layout.STATUS_TIGHT = table.freeze({ slot = 44, icon = 34, label = 15, labelSize = 10, overlap = 5, pillPad = 3 })

-- Slot ids, left to right (HudClusters.STATUS_IDS lists the same).
Layout.STATUS_SLOTS = table.freeze({ "Rain", "Event", "Friend", "Secret" })

-- One size class of the money block: coin diameter, chip height, chip overlap under the pill, the tab under
-- the income chip, and how far the coin protrudes above / below the pill (`pad`).
export type MoneyMetrics = { coin: number, chip: number, overlap: number, tab: number, pad: number }
function Layout.moneyMetrics(compact: boolean, tight: boolean?): MoneyMetrics
	local m = Layout.MONEY
	if tight then
		local t = Layout.MONEY_TIGHT
		return { coin = t.plate, chip = t.chip, overlap = t.overlap, tab = t.tab, pad = math.round(t.plate * 0.08) }
	end
	local d = if compact then m.cplate else m.plate
	return {
		coin = d,
		chip = if compact then m.cchip else m.chip,
		overlap = if compact then m.coverlap else m.overlap,
		tab = if compact then m.ctab else m.tab,
		pad = math.round(d * 0.08),
	}
end

-- Where the chips start under the pill: right of the coin; a tight phone has no room, so they start at the
-- left edge and the coin (drawn above them) overlaps their top-left corner.
function Layout.moneyChipX(compact: boolean, tight: boolean?): number
	if tight then
		return 0
	end
	return Layout.moneyMetrics(compact, false).coin + 3
end

-- Top of the chips, from the top of the block: the pill's bottom edge minus the overlap.
function Layout.moneyChipTop(compact: boolean, tight: boolean?): number
	local k = Layout.moneyMetrics(compact, tight)
	return k.coin - k.pad - k.overlap
end

function Layout.moneyHeight(compact: boolean, tight: boolean?): number
	local k = Layout.moneyMetrics(compact, tight)
	return Layout.moneyChipTop(compact, tight) + k.chip + k.tab
end

function Layout.moneyWidth(compact: boolean, tight: boolean?): number
	if tight then
		return Layout.MONEY_TIGHT.w
	end
	return if compact then Layout.MONEY.cw else Layout.MONEY.w
end

-- The money cluster with its bottom-left corner at (x, bottom). `cash` is the coin + pill zone; `income`
-- and `rebirths` are the two chips, which overlap the pill's bottom edge (never each other).
function Layout.moneyCluster(compact: boolean, x: number, bottom: number, tight: boolean?): MoneyHud
	local k = Layout.moneyMetrics(compact, tight)
	local d, chip = k.coin, k.chip
	local w = Layout.moneyWidth(compact, tight)
	local h = Layout.moneyHeight(compact, tight)
	local y = bottom - h
	local chipX = Layout.moneyChipX(compact, tight)
	local chipY = y + Layout.moneyChipTop(compact, tight)
	local gap = if tight then 3 else 5
	local rowW = w - chipX
	local incomeW = math.floor((rowW - gap) * (1 - Layout.moneyRebirth(compact, tight).share))
	local rebirthW = rowW - gap - incomeW
	return {
		rect = Layout.rect(x, y, w, h),
		cash = Layout.rect(x, y, w, d),
		income = Layout.rect(x + chipX, chipY, incomeW, chip),
		rebirths = Layout.rect(x + chipX + incomeW + gap, chipY, rebirthW, chip),
	}
end

-- Width of the "x5" badge on the rebirths chip.
function Layout.moneyBadgeWidth(chipH: number): number
	return chipH
end

-- One size class of the rebirths chip: row share, emblem px (a bare picture filling the chip's height),
-- count and badge text sizes.
export type MoneyRebirth = { share: number, emblem: number, countSize: number, badgeSize: number }
function Layout.moneyRebirth(compact: boolean, tight: boolean?): MoneyRebirth
	local chip = Layout.moneyMetrics(compact, tight).chip
	if tight then
		local t = Layout.MONEY_TIGHT
		return {
			share = t.rebirthShare,
			emblem = math.round(chip * t.emblem),
			countSize = t.rebirthSize,
			badgeSize = t.badgeSize,
		}
	end
	local m = Layout.MONEY
	return {
		share = if compact then m.crebirthShare else m.rebirthShare,
		emblem = math.round(chip * (if compact then m.cemblem else m.emblem)),
		countSize = if compact then m.crebirthSize else m.rebirthSize,
		badgeSize = if compact then m.cbadgeSize else m.badgeSize,
	}
end

-- Text column of a money box, as (x offset, width) inside the box (Hud builds the same numbers). "cash": the
-- amount right of the coin; "income": the chip text between its padding; "rebirths": the count between the
-- chip's emblem and the multiplier badge.
function Layout.moneyTextBox(
	box: Rect,
	kind: "cash" | "income" | "rebirths",
	compact: boolean,
	tight: boolean?
): (number, number)
	local d = Layout.moneyMetrics(compact, tight).coin
	if kind == "cash" then
		local left = d + (if tight then 4 else 8)
		return left, box.w - left - (if tight then 6 else 10)
	elseif kind == "income" then
		return 4, box.w - 8
	end
	local left = Layout.moneyRebirth(compact, tight).emblem + 5
	local right = Layout.moneyBadgeWidth(box.h) + 6
	return left, box.w - left - right
end

-- One size class of a status slot: slot width, icon, timer pill height / text size / side padding, and how far
-- the pill tucks up over the icon.
export type StatusMetrics = { slot: number, icon: number, pill: number, textSize: number, pad: number, overlap: number }
function Layout.statusMetrics(compact: boolean, tight: boolean?): StatusMetrics
	local s, t = Layout.STATUS, Layout.STATUS_TIGHT
	if tight then
		return {
			slot = t.slot,
			icon = t.icon,
			pill = t.label,
			textSize = t.labelSize,
			pad = t.pillPad,
			overlap = t.overlap,
		}
	elseif compact then
		return {
			slot = s.cslot,
			icon = s.cicon,
			pill = s.clabel,
			textSize = s.clabelSize,
			pad = s.cpillPad,
			overlap = s.coverlap,
		}
	end
	return { slot = s.slot, icon = s.icon, pill = s.label, textSize = s.labelSize, pad = s.pillPad, overlap = s.overlap }
end

function Layout.statusSlotWidth(compact: boolean, tight: boolean?): number
	return Layout.statusMetrics(compact, tight).slot
end

-- One slot's height: the icon plus the part of the pill below it.
function Layout.statusHeight(compact: boolean, tight: boolean?): number
	local sm = Layout.statusMetrics(compact, tight)
	return sm.icon + sm.pill - sm.overlap
end

-- The timer pill's width for `text`: the text plus its padding, at least a square-ish pill, at most the slot.
function Layout.statusPillWidth(text: string, compact: boolean, tight: boolean?): number
	local sm = Layout.statusMetrics(compact, tight)
	local w = math.ceil(Layout.lineWidth(text, sm.textSize, true)) + sm.pad * 2
	return math.min(math.max(w, sm.pill * 2), sm.slot)
end

-- Slots per row: one row off phones; a phone shares its bottom row with the money block and the hotbar, so
-- its events stack STATUS.phoneColumns wide.
function Layout.statusColumns(phone: boolean?): number
	return if phone then Layout.STATUS.phoneColumns else Layout.STATUS.count
end

function Layout.statusWidth(compact: boolean, tight: boolean?, phone: boolean?): number
	local columns = Layout.statusColumns(phone)
	return columns * Layout.statusSlotWidth(compact, tight) + (columns - 1) * Layout.STATUS.gap
end

-- The status cluster with its bottom-right corner at (right, bottom). Slots fill rows left to right, top row
-- first, so the last slot is the bottom-right corner.
function Layout.statusCluster(
	compact: boolean,
	right: number,
	bottom: number,
	tight: boolean?,
	phone: boolean?
): StatusHud
	local s = Layout.STATUS
	local columns = Layout.statusColumns(phone)
	local rows = math.ceil(s.count / columns)
	local slotW, slotH = Layout.statusSlotWidth(compact, tight), Layout.statusHeight(compact, tight)
	local w, h = Layout.statusWidth(compact, tight, phone), rows * slotH + (rows - 1) * s.gap
	local x, y = right - w, bottom - h
	local slots = {}
	for i = 1, s.count do
		local col, row = (i - 1) % columns, (i - 1) // columns
		table.insert(slots, Layout.rect(x + col * (slotW + s.gap), y + row * (slotH + s.gap), slotW, slotH))
	end
	return { rect = Layout.rect(x, y, w, h), slots = slots }
end

-- Slot rect for the `index`-th (1 = first) of `shown` visible slots: they pack towards the bottom-right corner.
function Layout.statusSlot(status: StatusHud, index: number, shown: number): Rect
	return status.slots[Layout.STATUS.count - shown + index]
end

-- Status tooltip (B8): a small card above the tapped / hovered status icon with the event's name, what it
-- does and the time left. `tooltipBox` fits the texts; `tooltipRect` keeps the card on screen.
Layout.TOOLTIP = table.freeze({
	w = 236,
	cw = 212,
	pad = 10,
	gap = 8, -- between the card and the icon
	titleSize = 17,
	bodySize = 14,
	timeSize = 14,
	cbodySize = 13,
	line = 4, -- between the text lines
})

function Layout.tooltipBox(
	compact: boolean,
	title: string,
	body: string,
	time: string
): (number, number, { titleH: number, bodyH: number, timeH: number })
	local t = Layout.TOOLTIP
	local w = if compact then t.cw else t.w
	local inner = w - t.pad * 2
	local bodySize = if compact then t.cbodySize else t.bodySize
	local lines = {
		titleH = math.ceil(Layout.wrappedHeight(title, t.titleSize, inner, true)),
		bodyH = math.ceil(Layout.wrappedHeight(body, bodySize, inner, false)),
		timeH = math.ceil(Layout.wrappedHeight(time, t.timeSize, inner, true)),
	}
	return w, t.pad * 2 + lines.titleH + lines.bodyH + lines.timeH + t.line * 2, lines
end

-- The card over `anchor` (a status slot), centred on it, clamped MARGIN inside the screen; below the icon
-- if there is no room above.
function Layout.tooltipRect(screen: Screen, anchor: Rect, w: number, h: number): Rect
	local m, gap = Layout.MARGIN, Layout.TOOLTIP.gap
	local x = math.clamp(anchor.x + anchor.w / 2 - w / 2, m, math.max(screen.width - m - w, m))
	local y = anchor.y - gap - h
	if y < m then
		y = math.min(anchor.y + anchor.h + gap, math.max(screen.height - m - h, m))
	end
	return Layout.rect(x, y, w, h)
end

-- Nav ----------------------------------------------------------------------------
-- B5 (ui_reference.png): a grid of rounded square tiles, the icon on the tile, the label under it, `columns`
-- (default 2) wide, filled left to right then down. No panel behind it. A nav "button" (navButtons) is a tile
-- plus its label, so a tap on either opens the menu.

Layout.NAV = table.freeze({
	left = Layout.MARGIN,
	top = 56, -- highest the nav may go, under Roblox's own profile / voice chips (Layout.screen puts it lower)
	columns = 2,
	gap = 8,
	cgap = 6,
	cell = 78, -- tile + label width: fits the longest label ("SlimeDex") at labelSize
	ccell = 70,
	tile = 66, -- the rounded square
	ctile = 58, -- 58 x 0.8 = 46 screen px >= MIN_TOUCH
	label = 20, -- label row under the tile
	clabel = 17,
	labelSize = 16,
	clabelSize = 13,
	labelGap = 2,
	iconInset = 8, -- item icon inside the tile
	count = #Nav.ENTRIES,
})

-- Nav badge chip: top-right corner of its button, inset so it never leaves the
-- button (init.client builds the same numbers).
Layout.NAV_BADGE = table.freeze({ inset = 2, height = 16, minWidth = 16, textSize = 11, padding = 4 })

function Layout.navBadge(button: Rect, text: string): Rect
	local b = Layout.NAV_BADGE
	local w = math.max(b.minWidth, math.ceil(Layout.lineWidth(text, b.textSize, true)) + b.padding * 2)
	w = math.min(w, button.w - b.inset * 2)
	return Layout.rect(button.x + button.w - b.inset - w, button.y + b.inset, w, b.height)
end

function Layout.navCellSize(compact: boolean): (number, number)
	local n = Layout.NAV
	return if compact then n.ccell else n.cell,
		(if compact then n.ctile + n.labelGap + n.clabel else n.tile + n.labelGap + n.label)
end

function Layout.navGap(compact: boolean): number
	return if compact then Layout.NAV.cgap else Layout.NAV.gap
end

-- The rounded square inside a nav button box.
function Layout.navTile(compact: boolean, button: Rect): Rect
	local tile = if compact then Layout.NAV.ctile else Layout.NAV.tile
	return Layout.rect(button.x + (button.w - tile) / 2, button.y, tile, tile)
end

-- Nav width for `columns` tile columns (default NAV.columns).
function Layout.navWidth(compact: boolean, columns: number?): number
	local cols = columns or Layout.NAV.columns
	local w = Layout.navCellSize(compact)
	return cols * w + (cols - 1) * Layout.navGap(compact)
end

-- Nav height for `count` buttons (default all) in `columns` columns.
function Layout.navHeight(compact: boolean, count: number?, columns: number?): number
	local rows = math.ceil((count or Layout.NAV.count) / (columns or Layout.NAV.columns))
	local _, h = Layout.navCellSize(compact)
	return rows * h + math.max(rows - 1, 0) * Layout.navGap(compact)
end

-- Fewest columns (NAV.columns..count) whose nav fits in `height`; all columns (one row) when nothing fits.
function Layout.navColumns(compact: boolean, height: number, count: number?): number
	local n = count or Layout.NAV.count
	for cols = Layout.NAV.columns, n do
		if Layout.navHeight(compact, n, cols) <= height then
			return cols
		end
	end
	return n
end

-- The nav: left edge, top at `top`.
function Layout.navRect(compact: boolean, top: number, count: number?, columns: number?): Rect
	return Layout.rect(
		Layout.NAV.left,
		top,
		Layout.navWidth(compact, columns),
		Layout.navHeight(compact, count, columns)
	)
end

-- Button boxes inside a nav rect (Nav.ENTRIES order), filled left to right, then down.
function Layout.navButtons(compact: boolean, nav: Rect, count: number?, columns: number?): { Rect }
	local out = {}
	local gap = Layout.navGap(compact)
	local w, h = Layout.navCellSize(compact)
	local cols = columns or Layout.NAV.columns
	for i = 1, count or Layout.NAV.count do
		local col, row = (i - 1) % cols, (i - 1) // cols
		table.insert(out, Layout.rect(nav.x + col * (w + gap), nav.y + row * (h + gap), w, h))
	end
	return out
end

-- Panels and bottom cards ------------------------------------------------------

Layout.CARRY = table.freeze({ w = 420, h = 96 })
-- Carry card text column = card width minus this (swatch left, Drop right).
Layout.CARRY_TEXT_RESERVE = 190
Layout.CARRY_MIN_W = 320 -- narrowest carry card (short screens, beside the tutorial card)
Layout.TUTORIAL_BESIDE_MIN = 260 -- narrowest tutorial card beside the carry card
Layout.DAILY = table.freeze({ w = 420, h = 300 })
Layout.TUTORIAL = table.freeze({ w = 520, bodyTop = 68, bodyTextSize = 14, padX = 14, padBottom = 12 })
-- Short (landscape phone) screens: the tutorial card sits this many screen px
-- above the bottom edge, below the banner stack.
Layout.TUTORIAL_SHORT_MARGIN = 8
Layout.TUTORIAL_SHORT_HEIGHT = 500 -- viewport px: shorter than this is a landscape phone

-- Menu panel chrome (Widgets.panel): the coloured title band holds the
-- menu icon, the title and the close "X" (top-right, MIN_TOUCH_DESIGN
-- square, same spot on every panel); the body fills the rest, `pad` in from
-- the sides and bottom.
Layout.PANEL_CHROME = table.freeze({
	pad = 12,
	close = Layout.MIN_TOUCH_DESIGN,
	closeInset = 6,
	titleSize = 26,
	icon = 60, -- the corner icon tile left of the title (a copy of the nav tile)
	iconRise = 12, -- how far the tile pokes up above the card's top edge
	iconSize = 32, -- the emoji on that tile
	bodyGap = 8, -- space between the band's ink rule and the body
	header = Layout.MIN_TOUCH_DESIGN + 12 + 8, -- the band (closeInset above and below the X) plus bodyGap
})

-- v28 (Merijn: "like Steal a Brainrot"): every menu is a card sized to its
-- content, centred in the full-window backdrop (screen.panel, dimmed; a tap
-- on it closes the menu). One width for every card so the X sits in the
-- same column; heights per Nav key (design px), clamped to the backdrop.
Layout.MENU_WIDTH = 560
Layout.MENU_HEIGHTS = table.freeze({
	Plot = 520,
	Merge = 520,
	Shop = 520,
	WorldShop = 520,
	Inventory = 460,
	Rebirth = 470,
	Goals = 500,
	Dex = 600,
	Leaders = 460,
	Codes = 300,
	Sound = 283,
	Guide = 380,
	Welcome = 380,
})
Layout.BANNER_WIDTH = 560

-- How far the bottom row is lifted off the thumbstick / jump button: phones in portrait and tablets, but not a
-- landscape phone (it hugs the bottom edge). `s` is a Layout.screen.
function Layout.rowRise(s: Screen): number
	if not s.compact or (s.phone and s.width > s.height) then
		return 0
	end
	return math.ceil(Layout.TOUCH_RISE / s.scale)
end

-- Space kept free at the bottom of the screen (touch controls on phones).
function Layout.bottomInset(compact: boolean): number
	return if compact then math.ceil(Layout.TOUCH_CONTROLS_HEIGHT / Layout.MIN_SCALE) else Layout.MARGIN * 2
end

-- Tutorial card height for a width: fits the longest step body.
function Layout.tutorialHeight(width: number): number
	local t = Layout.TUTORIAL
	local body = 0
	for _, step in Tutorial.STEPS do
		body = math.max(body, Layout.wrappedHeight(step.body, t.bodyTextSize, width - t.padX * 2))
	end
	return math.ceil(t.bodyTop + body + t.padBottom)
end

-- The full-window menu box: right of the nav (so the player can switch
-- menus), from the top margin down to the bottom inset (touch controls on
-- phones). The bottom cards (carry, tutorial) draw above it (ZINDEX), so
-- Drop / Hide stay tappable while a menu is open.
function Layout.fullWindowRect(columnX: number, top: number, width: number, height: number, inset: number): Rect
	local w = width - Layout.MARGIN - columnX
	return Layout.rect(columnX, top, math.max(w, 0), math.max(height - inset - top, 0))
end

-- Height of the menu card for `key` (MENU_HEIGHTS, default the tallest).
function Layout.menuHeight(key: string): number
	local h = (Layout.MENU_HEIGHTS :: any)[key]
	if type(h) == "number" then
		return h
	end
	local tallest = 0
	for _, v in Layout.MENU_HEIGHTS :: any do
		tallest = math.max(tallest, v)
	end
	return tallest
end

-- Smallest content-sized card (design px): the title band, the X and a row.
Layout.CARD_MIN = 220

-- Card height for a measured body content height (Widgets.contentHeight):
-- the chrome header and bottom pad around it, at least CARD_MIN.
function Layout.cardHeight(contentH: number): number
	local c = Layout.PANEL_CHROME
	return math.max(Layout.CARD_MIN, math.ceil(c.header + contentH + c.pad))
end

-- The menu card for a Nav key (or "Guide" / "Welcome") on `screen`: screen.menuX /
-- menuW, as tall as its measured body content (`contentH`, Widgets.contentHeight;
-- MENU_HEIGHTS when nil), at most the backdrop, centred in it.
function Layout.panelFor(screen: Screen, key: string, contentH: number?): Rect
	local back = screen.panel
	local want = if contentH then Layout.cardHeight(contentH) else Layout.menuHeight(key)
	local h = math.min(want, back.h)
	local y = back.y + math.floor((back.h - h) / 2)
	return Layout.rect(screen.menuX, y, screen.menuW, h)
end

-- The menu backdrop: the whole window in design px (UIScale'd), reaching under
-- the Roblox top bar and any side insets (`guiInsetX/Y` px, GuiService:GetGuiInset
-- with IgnoreGuiInset off) so the dim leaves no strip. Not screen.panel, which is
-- only the card column.
function Layout.backdrop(screen: Screen, guiInsetX: number, guiInsetY: number): Rect
	local s = screen.scale
	return Layout.rect(
		-guiInsetX / s,
		-guiInsetY / s,
		(screen.viewportW + guiInsetX) / s,
		(screen.viewportH + guiInsetY) / s
	)
end

-- Close button, title and body boxes inside a panel box (PANEL_CHROME).
function Layout.panelClose(panel: Rect): Rect
	local c = Layout.PANEL_CHROME
	return Layout.rect(panel.x + panel.w - c.closeInset - c.close, panel.y + c.closeInset, c.close, c.close)
end

function Layout.panelTitle(panel: Rect): Rect
	local c = Layout.PANEL_CHROME
	local left = c.pad + c.icon + 6
	return Layout.rect(panel.x + left, panel.y + c.closeInset, panel.w - left - c.close - c.closeInset * 2, c.close)
end

function Layout.panelBody(panel: Rect): Rect
	local c = Layout.PANEL_CHROME
	return Layout.rect(panel.x + c.pad, panel.y + c.header, panel.w - c.pad * 2, panel.h - c.header - c.pad)
end

-- `width` centred on the screen, pushed inside [column.x, column right].
local function centredIn(column: Rect, screenW: number, width: number): (number, number)
	local w = math.min(width, column.w)
	local x = math.clamp((screenW - w) / 2, column.x, column.x + column.w - w)
	return x, w
end

export type ScreenOptions = {}

-- Bottom cards centred on the screen inside `row` (x / w only): carry on the
-- bottom line, tutorial above the inset, and above the carry card while
-- carrying, or (`beside`) the carry card at the row's left and the
-- tutorial next to it. `cardMargin` (short screens): the tutorial card hugs the
-- bottom edge that far up and, while carrying, sits next to the carry card.
local function bottomCards(
	row: Rect,
	W: number,
	H: number,
	inset: number,
	beside: boolean?,
	cardMargin: number?,
	tutorialLift: number?
)
	local gap = Layout.GAP
	local carryX, carryW = centredIn(row, W, Layout.CARRY.w)
	local carry = Layout.rect(carryX, H - inset - Layout.CARRY.h, carryW, Layout.CARRY.h)
	local tutX, tutW = centredIn(row, W, Layout.TUTORIAL.w)
	local tutH = Layout.tutorialHeight(tutW)
	local cardBottom = H - (cardMargin or inset)
	local tutorial = Layout.rect(tutX, cardBottom - (tutorialLift or 0) - tutH, tutW, tutH)
	local tutorialCarrying = Layout.rect(tutX, carry.y - gap - tutH, tutW, tutH)
	if beside or cardMargin then
		-- The carry card gives up width (down to CARRY_MIN_W) so the tutorial card beside it keeps
		-- TUTORIAL_BESIDE_MIN: its title and Hide button need ~250 px.
		carryW = math.clamp(row.w - gap - Layout.TUTORIAL_BESIDE_MIN, math.min(Layout.CARRY_MIN_W, carryW), carryW)
		carry = Layout.rect(row.x, carry.y, carryW, carry.h)
		local besideW = math.max(math.min(Layout.TUTORIAL.w, row.w - carryW - gap), 0)
		local besideH = Layout.tutorialHeight(besideW)
		tutorialCarrying = Layout.rect(carry.x + carryW + gap, cardBottom - besideH, besideW, besideH)
	end
	return carry, tutorial, tutorialCarrying
end

-- Every top-level box for a ScreenGui of viewportW x viewportH (see header).
-- One pass in priority order: the bottom clusters, nav, bottom cards, then the menu column
-- and overlays in what is left, so nothing has to be moved afterwards.
function Layout.screen(viewportW: number, viewportH: number, _options: ScreenOptions?): Screen
	local scale = Layout.uiScale(viewportW, viewportH)
	local W, H = viewportW / scale, viewportH / scale
	local compact = Layout.isCompact(viewportW, viewportH)
	local m, gap = Layout.MARGIN, Layout.GAP
	-- Phones (portrait, or landscape under TUTORIAL_SHORT_HEIGHT): the nav grid sits at the very top and the
	-- money block, the hotbar and the events row share one bottom row (`rowBottom`). Portrait too narrow for
	-- the full-size row (money + events + a 3-item hotbar) goes `tight`. A tablet-sized compact screen
	-- (1024x768) is not a phone and keeps the desktop arrangement.
	local phone = compact and (viewportW < Layout.COMPACT_WIDTH or viewportH < Layout.TUTORIAL_SHORT_HEIGHT)
	-- Landscape phone: the row hugs the bottom edge (small inset, no rise); portrait phones lift it off the
	-- thumbstick / jump button.
	local landscapePhone = phone and viewportW > viewportH
	local inset = if landscapePhone
		then math.ceil(Layout.LANDSCAPE_BOTTOM_INSET / scale)
		else Layout.bottomInset(compact)

	-- Bottom clusters (H1): on the inset line (compact: lifted off the touch controls), bottom-left /
	-- bottom-right.
	local rise = if compact and not landscapePhone then math.ceil(Layout.TOUCH_RISE / scale) else 0
	local rowBottom = H - inset - rise
	local fullRowW = Layout.moneyWidth(compact)
		+ Layout.statusWidth(compact, nil, phone)
		+ InventoryLayout.barWidth(4, InventoryLayout.slotSize(compact, Layout.MIN_TOUCH_DESIGN))
		+ 2 * (m + gap)
	local tight = phone and W < fullRowW
	local money = Layout.moneyCluster(compact, m, rowBottom, tight)
	-- The events row stands STATUS.raise above the money line off phones (0: it shares that line); on phones it
	-- always shares the bottom row.
	local statusRaise = if phone then 0 else Layout.STATUS.raise
	local status = Layout.statusCluster(compact, W - m, rowBottom - statusRaise, tight, phone)
	local hotbarH = InventoryLayout.height(compact, Layout.MIN_TOUCH_DESIGN, tight)

	-- 1. "Short" (landscape phone): the default two nav columns won't fit above the money cluster, so
	-- the nav starts at the top margin, takes more columns, and the bottom cards go between the clusters.
	local short = compact and Layout.TOP + Layout.navHeight(compact) + gap > money.rect.y - gap
	local top = if short or phone then Layout.TOP else Layout.NAV.top
	-- Narrower than the carry card plus both clusters (portrait phones): the bottom cards sit above
	-- the clusters instead of beside them.
	local clusterH = math.max(money.rect.h, status.rect.h + statusRaise, if phone then hotbarH else 0)
	local lift = if not short and W < Layout.CARRY.w + money.rect.w + status.rect.w + 2 * (m + gap)
		then rise + clusterH + gap
		else 0
	local cardInset = inset + lift
	-- S3 hotbar (InventoryLayout): bottom-centre between the clusters, above them on a narrow phone; short
	-- phones hug the bottom edge. The server unequips tools while carrying, so the bar is hidden then and the
	-- carry cards may use its place; only the plain tutorial card rises above it (`tutorialLift`).
	local cardMargin = if short and viewportH < Layout.TUTORIAL_SHORT_HEIGHT
		then Layout.TUTORIAL_SHORT_MARGIN / scale
		else nil
	-- Short and too low to stack the tutorial over the carry card: they go side by side.
	local beside = short and H - inset - top < Layout.CARRY.h + gap + Layout.tutorialHeight(Layout.TUTORIAL.w)

	-- 2. Nav: left, 2 columns, low (short: as many as it takes to fit from the top down to the money
	-- cluster; the bottom cards then sit right of the money cluster, step 3).
	local fullRow = Layout.rect(m, 0, W - m * 2, 0)
	local hotbarBottom = if phone then rowBottom else H - cardInset
	-- Phones: the tutorial card already clears the row (portrait: the cards sit above it; landscape: the card hugs
	-- the bottom edge, below the row), so only the desktop arrangement lifts it above the hotbar.
	local tutorialLift = if phone and not landscapePhone
		then 0
		else (H - (cardMargin or cardInset)) - (hotbarBottom - hotbarH) + gap
	local _, tutorial0, tutorialCarrying0 = bottomCards(fullRow, W, H, cardInset, nil, nil, tutorialLift)
	local navBottom = if short then money.rect.y - gap else math.min(tutorial0.y, tutorialCarrying0.y) - gap
	navBottom = math.min(navBottom, money.rect.y - gap)
	local columns = if short then Layout.navColumns(compact, navBottom - top) else Layout.NAV.columns
	-- The nav sits low on the left, its bottom on `navBottom`, so it stays clear of Roblox's chat window
	-- (top-left). Landscape phones have no height to spare and keep it at the top margin.
	local navTop = if short or landscapePhone
		then top
		else math.max(top, navBottom - Layout.navHeight(compact, nil, columns))
	local nav = Layout.navRect(compact, navTop, nil, columns)
	local navRight = nav.x + nav.w + gap
	-- Phones: an open menu card gets the nav's width too (init.client hides the nav tiles while a menu is open);
	-- desktop: the card area is right of the nav so the player can switch menus.
	local columnX = if compact then m else navRight
	local columnW = W - m - columnX

	-- 3. Bottom cards. Full screen width (the nav ends above them); short: between the money cluster
	-- and the status cluster (the nav sits above the money cluster, clear of the cards).
	local cardsX = money.rect.x + money.rect.w + gap
	local row = if short then Layout.rect(cardsX, 0, math.max(status.rect.x - gap - cardsX, 0), 0) else fullRow
	local carry, tutorial, tutorialCarrying = bottomCards(row, W, H, cardInset, beside, cardMargin, tutorialLift)
	local between = Layout.rect(cardsX, 0, math.max(status.rect.x - gap - cardsX, 0), 0)
	-- Truly bottom-centre: the zone is symmetric about the screen centre, as wide as the nearer cluster allows.
	local half = math.max(math.min(W / 2 - between.x, between.x + between.w - W / 2), 0)
	local stacked = lift > 0 and not phone
	local hotbarX = if stacked then m else W / 2 - half
	local hotbarW = if stacked then W - m * 2 else half * 2
	local hotbar = Layout.rect(hotbarX, hotbarBottom - hotbarH, hotbarW, hotbarH)

	-- 4. The column (right of the nav) above the bottom cards; menus use the
	-- full-window box, which runs on down to the bottom inset.
	local column =
		Layout.rect(columnX, Layout.TOP, columnW, math.max(math.min(tutorial.y, carry.y) - gap - Layout.TOP, 0))
	local panel = Layout.fullWindowRect(columnX, Layout.TOP, W, H, inset)

	-- Menu cards: MENU_WIDTH (at most the backdrop), centred in it.
	local menuW = math.min(Layout.MENU_WIDTH, panel.w)
	local menuX = panel.x + math.floor((panel.w - menuW) / 2)

	-- 5. Overlays. Banners draw above menus, so they keep clear of the menu close X (top-right of the
	-- card / the full-window box) and right of the nav: centred in the strip between them.
	local wideClose = Layout.panelClose(Layout.fullWindowRect(0, Layout.TOP, W, H, inset))
	local cardClose = Layout.panelClose(Layout.rect(menuX, Layout.TOP, menuW, 0))
	local close = if cardClose.x < wideClose.x then cardClose else wideClose
	local span = Layout.rect(navRight, 0, math.max(close.x - gap - navRight, 0), 0)
	local bannerX, bannerW = centredIn(span, W, Layout.BANNER_WIDTH)
	local banners = Layout.rect(bannerX, Layout.TOP, bannerW, 0)

	local dailyW = math.min(Layout.DAILY.w, W - m * 2)
	local dailyH = math.min(Layout.DAILY.h, H - m * 2)
	local daily = Layout.rect((W - dailyW) / 2, (H - dailyH) / 2, dailyW, dailyH)

	return {
		viewportW = viewportW,
		viewportH = viewportH,
		scale = scale,
		width = W,
		height = H,
		compact = compact,
		phone = phone,
		tight = tight,
		short = short,
		navColumns = columns,
		bottomInset = inset,
		money = money,
		status = status,
		hotbar = hotbar,
		banners = banners,
		sound = wideClose,
		nav = nav,
		navButtons = Layout.navButtons(compact, nav, nil, columns),
		column = column,
		panel = panel,
		menuX = menuX,
		menuW = menuW,
		carry = carry,
		tutorial = tutorial,
		tutorialCarrying = tutorialCarrying,
		daily = daily,
	}
end

return table.freeze(Layout)
