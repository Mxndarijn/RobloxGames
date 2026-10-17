--!strict
--[[
	Layout

	Pure layout rules shared by the UI and its tests (tests/ui/Layout.spec,
	tests/ui/LayoutAssert): the ZIndex layers of the top-level overlays,
	scroll list settings, the root UIScale, touch-target sizes and the
	rectangles of the HUD, left nav, full-window menu panels and bottom cards. No
	Instances here; Widgets / Hud / init.client apply them.

	Coordinates are design px: the ScreenGui's AbsoluteSize divided by
	`uiScale` (the root UIScale multiplies everything back). A Rect is
	{ x, y, w, h } from the top-left of the ScreenGui.

	Target viewports (v18): 390x844 phone (scale MIN_SCALE, "compact": two
	HUD rows, nav collapsed to an icon strip, room kept for Roblox's touch
	controls) and 1920x1080 desktop (scale 1, one HUD row, labelled nav).
	v27: landscape phone (844x390, 844x332 under the top bar) is "short":
	one compact HUD row, the nav as a grid of columns and the bottom cards
	right of it, so every nav button stays on screen (Layout.screen).
]]

local Nav = if script then require(script.Parent.Nav) else require("./Nav")
local Tutorial = if script then require(script.Parent.Tutorial) else require("./Tutorial")

export type Rect = { x: number, y: number, w: number, h: number }
export type HudLayout = { rect: Rect, items: { [string]: Rect }, rows: { { string } } }
export type Screen = {
	viewportW: number,
	viewportH: number,
	scale: number,
	width: number, -- design px
	height: number,
	compact: boolean,
	short: boolean, -- landscape phone: one HUD row, nav grid (Layout.screen)
	navCollapsed: boolean,
	navColumns: number,
	bottomInset: number,
	hud: HudLayout,
	banners: Rect,
	toasts: Rect,
	sound: Rect, -- FEATURES.Audio button: the top-right slot a menu's X would use (hidden while a menu is open)
	nav: Rect,
	navButtons: { Rect }, -- [1] = collapse toggle, then Nav.ENTRIES order
	column: Rect, -- right of the nav, under the HUD, above the bottom cards
	panel: Rect, -- full-window menu backdrop: column width, HUD to bottom inset
	menuX: number, -- left edge of every menu card (Layout.panelFor)
	menuW: number, -- width of every menu card
	carry: Rect,
	slap: Rect,
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
-- (Drop, Slap) over both.
Layout.ZINDEX = table.freeze({
	Base = 1, -- HUD, nav, the menu backdrop
	Menu = 2, -- menu cards (over the backdrop, whatever their sibling order)
	Banners = 3, -- HUD banners, toasts and the tutorial hint
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

Layout.MARGIN = 12
Layout.TOP = 8
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

-- HUD --------------------------------------------------------------------------
-- Absolute placement from HUD_ROWS (not a UIListLayout) so tests see the
-- same boxes the player does. Hidden items take no space.

Layout.HUD_PADDING = 8
Layout.HUD_GAP = 6
Layout.HUD_ROW_HEIGHT = Layout.BUTTON

-- w = desktop width, cw = compact width; h = height (centred in the row).
Layout.HUD_ITEMS = table.freeze({
	Cash = table.freeze({ w = 110, cw = 96, h = 48 }),
	Income = table.freeze({ w = 100, cw = 86, h = 48 }),
	Rebirths = table.freeze({ w = 90, cw = 78, h = 48 }),
	Pads = table.freeze({ w = 70, cw = 60, h = 48 }),
	LockStatus = table.freeze({ w = 200, cw = 180, h = 56 }),
	Lock = table.freeze({ w = 140, cw = 116, h = Layout.BUTTON, button = true }),
	BuyPad = table.freeze({ w = 160, cw = 134, h = Layout.BUTTON, button = true }),
	Shop = table.freeze({ w = 100, cw = 100, h = Layout.BUTTON, button = true }),
	Daily = table.freeze({ w = 120, cw = 96, h = Layout.BUTTON, button = true }),
})

-- Compact drops the HUD Shop button: the nav's Shop entry (with its "$"
-- badge) is right there.
Layout.HUD_ROWS = table.freeze({
	wide = table.freeze({
		table.freeze({ "Cash", "Income", "Rebirths", "Pads", "LockStatus", "Lock", "BuyPad", "Shop", "Daily" }),
	}),
	compact = table.freeze({
		table.freeze({ "Cash", "Income", "Rebirths", "Pads", "Daily" }),
		table.freeze({ "LockStatus", "Lock", "BuyPad" }),
	}),
	-- Short landscape phone (Layout.screen): the compact items on one row.
	compactOneRow = table.freeze({
		table.freeze({ "Cash", "Income", "Rebirths", "Pads", "Daily", "LockStatus", "Lock", "BuyPad" }),
	}),
})

-- HUD bar (top centre) and its items in screen design px. `visible[name] ==
-- false` hides an item. `oneRow` puts the compact items on a single row.
function Layout.hud(width: number, compact: boolean, visible: { [string]: boolean }?, oneRow: boolean?): HudLayout
	local pad, gap = Layout.HUD_PADDING, Layout.HUD_GAP
	local rows: { { string } } = {}
	local rowWidths: { number } = {}
	local layoutRows = if not compact
		then Layout.HUD_ROWS.wide
		elseif oneRow then Layout.HUD_ROWS.compactOneRow
		else Layout.HUD_ROWS.compact
	for _, row in layoutRows :: { { string } } do
		local names = {}
		local w = 0
		for _, name in row do
			if visible == nil or visible[name] ~= false then
				local item = (Layout.HUD_ITEMS :: any)[name]
				w += (if #names > 0 then gap else 0) + (if compact then item.cw else item.w)
				table.insert(names, name)
			end
		end
		if #names > 0 then
			table.insert(rows, names)
			table.insert(rowWidths, w)
		end
	end
	local inner = 0
	for _, w in rowWidths do
		inner = math.max(inner, w)
	end
	local barW = inner + pad * 2
	local barH = #rows * Layout.HUD_ROW_HEIGHT + math.max(#rows - 1, 0) * gap + pad * 2
	local bar = Layout.rect((width - barW) / 2, Layout.TOP, barW, barH)
	local items: { [string]: Rect } = {}
	for r, names in rows do
		local x = bar.x + pad + (inner - rowWidths[r]) / 2
		local rowY = bar.y + pad + (r - 1) * (Layout.HUD_ROW_HEIGHT + gap)
		for _, name in names do
			local item = (Layout.HUD_ITEMS :: any)[name]
			local w = if compact then item.cw else item.w
			items[name] = Layout.rect(x, rowY + (Layout.HUD_ROW_HEIGHT - item.h) / 2, w, item.h)
			x += w + gap
		end
	end
	return { rect = bar, items = items, rows = rows }
end

-- Nav ----------------------------------------------------------------------------

Layout.NAV = table.freeze({
	left = Layout.MARGIN,
	padding = 6,
	gap = 3, -- 9 buttons still fit a 390x844 phone above the bottom cards
	button = Layout.BUTTON,
	expandedWidth = 148, -- fits the longest label ("SlimeDex")
	collapsedWidth = 68, -- 56 px icon buttons + padding (~54 screen px on a phone)
	count = #Nav.ENTRIES + 1, -- + the collapse toggle
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

-- Nav width for `columns` button columns (default 1).
function Layout.navWidth(collapsed: boolean, columns: number?): number
	local one = if collapsed then Layout.NAV.collapsedWidth else Layout.NAV.expandedWidth
	local cols = columns or 1
	local p = Layout.NAV.padding
	return p * 2 + cols * (one - p * 2) + (cols - 1) * Layout.NAV.gap
end

-- Nav height for `count` buttons (default all) in `columns` columns.
function Layout.navHeight(count: number?, columns: number?): number
	local n = math.ceil((count or Layout.NAV.count) / (columns or 1))
	return Layout.NAV.padding * 2 + n * Layout.NAV.button + math.max(n - 1, 0) * Layout.NAV.gap
end

-- Fewest columns (1..count) whose nav fits in `height`; all columns (one
-- row) when nothing fits.
function Layout.navColumns(height: number, count: number?): number
	local n = count or Layout.NAV.count
	for cols = 1, n do
		if Layout.navHeight(n, cols) <= height then
			return cols
		end
	end
	return n
end

-- Collapsed on phones / small windows, labelled on desktop.
function Layout.navDefaultCollapsed(viewportW: number, viewportH: number): boolean
	return Layout.isCompact(viewportW, viewportH)
end

-- The nav: left edge, centred in the band between `top` and `bottom`, never
-- above `top`.
function Layout.navRect(collapsed: boolean, top: number, bottom: number, count: number?, columns: number?): Rect
	local h = Layout.navHeight(count, columns)
	local y = math.max(top, top + (bottom - top - h) / 2)
	return Layout.rect(Layout.NAV.left, y, Layout.navWidth(collapsed, columns), h)
end

-- Button boxes inside a nav rect ([1] = toggle), filled column by column.
function Layout.navButtons(nav: Rect, count: number?, columns: number?): { Rect }
	local out = {}
	local p, gap, size = Layout.NAV.padding, Layout.NAV.gap, Layout.NAV.button
	local n = count or Layout.NAV.count
	local cols = columns or 1
	local perColumn = math.ceil(n / cols)
	local w = (nav.w - p * 2 - (cols - 1) * gap) / cols
	for i = 1, n do
		local col, row = (i - 1) // perColumn, (i - 1) % perColumn
		table.insert(out, Layout.rect(nav.x + p + col * (w + gap), nav.y + p + row * (size + gap), w, size))
	end
	return out
end

-- Panels and bottom cards ------------------------------------------------------

Layout.CARRY = table.freeze({ w = 420, h = 96 })
-- Carry card text column = card width minus this (swatch left, Drop right).
Layout.CARRY_TEXT_RESERVE = 190
Layout.SLAP = table.freeze({ w = 200, h = Layout.BUTTON })
Layout.DAILY = table.freeze({ w = 420, h = 300 })
Layout.TUTORIAL = table.freeze({ w = 520, bodyTop = 68, bodyTextSize = 14, padX = 14, padBottom = 12 })
-- Short (landscape phone) screens: the tutorial card sits this many screen px
-- above the bottom edge, below the banner stack and the toast column.
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
	titleSize = 22,
	icon = 36, -- emoji icon left of the title
	header = Layout.MIN_TOUCH_DESIGN + 12, -- closeInset above and below the X
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
	Rebirth = 470,
	Goals = 500,
	Dex = 600,
	Leaders = 460,
	Codes = 300,
	Sound = 275,
	Guide = 380,
	Welcome = 380,
})
Layout.BANNER_WIDTH = 560
Layout.TOAST_WIDTH = 320

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
-- menus), from under the HUD down to the bottom inset (touch controls on
-- phones). The bottom cards (carry, tutorial) draw above it (ZINDEX), so
-- Drop / Slap / Hide stay tappable while a menu is open.
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
-- MENU_HEIGHTS when nil), at most the backdrop. Centred in the backdrop
-- unless that would push its X under the toasts (phones: the card spans the
-- width), then at the top of the backdrop, where the X has always been.
function Layout.panelFor(screen: Screen, key: string, contentH: number?): Rect
	local back = screen.panel
	local want = if contentH then Layout.cardHeight(contentH) else Layout.menuHeight(key)
	local h = math.min(want, back.h)
	local y = back.y + math.floor((back.h - h) / 2)
	local close = Layout.panelClose(Layout.rect(screen.menuX, y, screen.menuW, h))
	if Layout.overlaps(close, screen.toasts) or Layout.overlaps(close, screen.hud.rect) then
		y = back.y
	end
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

export type ScreenOptions = {
	navCollapsed: boolean?, -- nil: Layout.navDefaultCollapsed
	hudVisible: { [string]: boolean }?,
}

-- Bottom cards centred on the screen inside `row` (x / w only): carry on the
-- bottom line, tutorial above the inset, and above the carry card while
-- carrying, or (`beside`) the carry card at the row's left and the
-- tutorial next to it. `cardMargin` (short screens): the tutorial card hugs the
-- bottom edge that far up and, while carrying, sits next to the carry card.
local function bottomCards(row: Rect, W: number, H: number, inset: number, beside: boolean?, cardMargin: number?)
	local gap = Layout.GAP
	local carryX, carryW = centredIn(row, W, Layout.CARRY.w)
	local carry = Layout.rect(carryX, H - inset - Layout.CARRY.h, carryW, Layout.CARRY.h)
	local tutX, tutW = centredIn(row, W, Layout.TUTORIAL.w)
	local tutH = Layout.tutorialHeight(tutW)
	local cardBottom = H - (cardMargin or inset)
	local tutorial = Layout.rect(tutX, cardBottom - tutH, tutW, tutH)
	local tutorialCarrying = Layout.rect(tutX, carry.y - gap - tutH, tutW, tutH)
	if beside or cardMargin then
		carry = Layout.rect(row.x, carry.y, carryW, carry.h)
		local besideW = math.max(math.min(Layout.TUTORIAL.w, row.w - carryW - gap), 0)
		local besideH = Layout.tutorialHeight(besideW)
		tutorialCarrying = Layout.rect(carry.x + carryW + gap, cardBottom - besideH, besideW, besideH)
	end
	local slapW = math.min(Layout.SLAP.w, carry.w)
	local slap = Layout.rect(carry.x + (carry.w - slapW) / 2, carry.y + carry.h - Layout.SLAP.h, slapW, Layout.SLAP.h)
	return carry, slap, tutorial, tutorialCarrying
end

-- The toast stack's box with the banner stack `bannerH` px tall: toasts that
-- would sit under the banners (phones: both reach the middle) start below them.
function Layout.toastBox(screen: Screen, bannerH: number): Rect
	local t, b = screen.toasts, screen.banners
	if bannerH <= 0 or t.x >= b.x + b.w or b.x >= t.x + t.w then
		return t
	end
	local y = math.max(t.y, b.y + bannerH + Layout.GAP)
	return Layout.rect(t.x, y, t.w, math.max(math.min(t.h, screen.height - Layout.MARGIN - y), 0))
end

-- Every top-level box for a ScreenGui of viewportW x viewportH (see header).
-- One pass in priority order: HUD, nav, bottom cards, then the menu column
-- and overlays in what is left, so nothing has to be moved afterwards.
function Layout.screen(viewportW: number, viewportH: number, options: ScreenOptions?): Screen
	local opts: ScreenOptions = options or {}
	local scale = Layout.uiScale(viewportW, viewportH)
	local W, H = viewportW / scale, viewportH / scale
	local compact = Layout.isCompact(viewportW, viewportH)
	local collapsed = if opts.navCollapsed == nil
		then Layout.navDefaultCollapsed(viewportW, viewportH)
		else opts.navCollapsed
	local m, gap = Layout.MARGIN, Layout.GAP
	local inset = Layout.bottomInset(compact)

	-- 1. HUD. "Short" (landscape phone): one nav column won't fit between a
	-- two-row compact HUD and the bottom inset, so the HUD takes one row when
	-- that row fits the width.
	local hud = Layout.hud(W, compact, opts.hudVisible)
	local short = false
	if compact and hud.rect.y + hud.rect.h + gap + Layout.navHeight() > H - inset then
		local oneRow = Layout.hud(W, compact, opts.hudVisible, true)
		if oneRow.rect.w <= W - m * 2 then
			short, hud = true, oneRow
		end
	end
	local hudBottom = hud.rect.y + hud.rect.h
	local top = hudBottom + gap
	-- Short and too low to stack the tutorial over the carry card: they go
	-- side by side, which leaves no width for a labelled nav grid.
	local beside = short and H - inset - top < Layout.CARRY.h + gap + Layout.tutorialHeight(Layout.TUTORIAL.w)
	if beside then
		collapsed = true
	end

	-- 2. Nav: centred between the HUD and the highest bottom card. Short: as
	-- many columns as it takes to fit from the HUD down to the bottom inset;
	-- the bottom cards then sit right of it (step 3).
	local fullRow = Layout.rect(m, 0, W - m * 2, 0)
	local _, _, tutorial0, tutorialCarrying0 = bottomCards(fullRow, W, H, inset)
	local columns = if short then Layout.navColumns(H - inset - top) else 1
	local navBottom = if short then H - inset else math.min(tutorial0.y, tutorialCarrying0.y) - gap
	if columns > 2 then
		collapsed = true -- a labelled 3-column grid would squeeze the bottom cards and menus
	end
	local nav = Layout.navRect(collapsed, top, navBottom, nil, columns)
	local columnX = nav.x + nav.w + gap
	local columnW = W - m - columnX

	-- 3. Bottom cards. Full screen width (the nav ends above them), so a
	-- phone card doesn't shrink when the nav is expanded; short: right of the
	-- nav, which runs down beside them.
	local row = if short then Layout.rect(columnX, 0, math.max(columnW, 0), 0) else fullRow
	local cardMargin = if short and viewportH < Layout.TUTORIAL_SHORT_HEIGHT
		then Layout.TUTORIAL_SHORT_MARGIN / scale
		else nil
	local carry, slap, tutorial, tutorialCarrying = bottomCards(row, W, H, inset, beside, cardMargin)

	-- 4. The column (right of the nav) above the bottom cards; menus use the
	-- full-window box, which runs on down to the bottom inset.
	local column = Layout.rect(columnX, top, columnW, math.max(math.min(tutorial.y, carry.y) - gap - top, 0))
	local panel = Layout.fullWindowRect(columnX, top, W, H, inset)

	-- Menu cards: MENU_WIDTH (at most the backdrop), centred in it.
	local menuW = math.min(Layout.MENU_WIDTH, panel.w)
	local menuX = panel.x + math.floor((panel.w - menuW) / 2)

	-- 5. Overlays. Banners and toasts draw above menus, so both keep clear of the menu
	-- close X (top-right of the card / the full-window box). Banners may cover
	-- a menu title, but stay centred left of the X column; toasts stack under
	-- the X row.
	local wideClose = Layout.panelClose(Layout.fullWindowRect(0, top, W, H, inset))
	local cardClose = Layout.panelClose(Layout.rect(menuX, top, menuW, 0))
	local close = if cardClose.x < wideClose.x then cardClose else wideClose
	-- Short: the nav runs up to the HUD, so banners also keep right of it.
	local bannerX, bannerW
	if short then
		local span = Layout.rect(columnX, 0, math.max(close.x - gap - columnX, 0), 0)
		bannerX, bannerW = centredIn(span, W, Layout.BANNER_WIDTH)
	else
		bannerW = math.min(Layout.BANNER_WIDTH, W - m * 2, 2 * (close.x - gap) - W)
		bannerX = (W - bannerW) / 2
	end
	local banners = Layout.rect(bannerX, hudBottom + 8, bannerW, 0)
	local toastW = math.min(Layout.TOAST_WIDTH, W - m * 2)
	local toastY = wideClose.y + wideClose.h + gap
	local toasts = Layout.rect(W - m - toastW, toastY, toastW, math.max(math.min(300, H - m - toastY), 0))

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
		short = short,
		navCollapsed = collapsed,
		navColumns = columns,
		bottomInset = inset,
		hud = hud,
		banners = banners,
		toasts = toasts,
		sound = wideClose,
		nav = nav,
		navButtons = Layout.navButtons(nav, nil, columns),
		column = column,
		panel = panel,
		menuX = menuX,
		menuW = menuW,
		carry = carry,
		slap = slap,
		tutorial = tutorial,
		tutorialCarrying = tutorialCarrying,
		daily = daily,
	}
end

return table.freeze(Layout)
