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
	navCollapsed: boolean,
	bottomInset: number,
	hud: HudLayout,
	banners: Rect,
	toasts: Rect,
	nav: Rect,
	navButtons: { Rect }, -- [1] = collapse toggle, then Nav.ENTRIES order
	column: Rect, -- right of the nav, under the HUD, above the bottom cards
	panel: Rect, -- full-window menu box: column width, HUD to bottom inset
	carry: Rect,
	slap: Rect,
	tutorial: Rect,
	tutorialCarrying: Rect, -- the tutorial card while the carry panel shows
	daily: Rect,
}

local Layout = {}

-- Esc closes an open menu only when true. Default false so Esc cannot clash
-- with Roblox's own menu; the panel X and gamepad B always close.
Layout.CLOSE_WITH_ESCAPE = false

-- Top-level ZIndex per overlay (ScreenGui uses ZIndexBehavior.Sibling, so
-- children render with their parent). Higher draws on top: banners over
-- menu panels, the tutorial over the daily popup, and the carry panel
-- (Drop, Slap) over both.
Layout.ZINDEX = table.freeze({
	Base = 1, -- HUD, nav, menu panels
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
})

-- HUD bar (top centre) and its items in screen design px. `visible[name] ==
-- false` hides an item.
function Layout.hud(width: number, compact: boolean, visible: { [string]: boolean }?): HudLayout
	local pad, gap = Layout.HUD_PADDING, Layout.HUD_GAP
	local rows: { { string } } = {}
	local rowWidths: { number } = {}
	for _, row in (if compact then Layout.HUD_ROWS.compact else Layout.HUD_ROWS.wide) :: { { string } } do
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
	gap = 6,
	button = Layout.BUTTON,
	expandedWidth = 148, -- fits the longest label ("SlimeDex")
	collapsedWidth = 68, -- 56 px icon buttons + padding (~54 screen px on a phone)
	count = #Nav.ENTRIES + 1, -- + the collapse toggle
})

function Layout.navWidth(collapsed: boolean): number
	return if collapsed then Layout.NAV.collapsedWidth else Layout.NAV.expandedWidth
end

function Layout.navHeight(count: number?): number
	local n = count or Layout.NAV.count
	return Layout.NAV.padding * 2 + n * Layout.NAV.button + math.max(n - 1, 0) * Layout.NAV.gap
end

-- Collapsed on phones / small windows, labelled on desktop.
function Layout.navDefaultCollapsed(viewportW: number, viewportH: number): boolean
	return Layout.isCompact(viewportW, viewportH)
end

-- The nav: left edge, centred in the band between `top` and `bottom`, never
-- above `top`.
function Layout.navRect(collapsed: boolean, top: number, bottom: number, count: number?): Rect
	local h = Layout.navHeight(count)
	local y = math.max(top, top + (bottom - top - h) / 2)
	return Layout.rect(Layout.NAV.left, y, Layout.navWidth(collapsed), h)
end

-- Button boxes inside a nav rect ([1] = toggle).
function Layout.navButtons(nav: Rect, count: number?): { Rect }
	local out = {}
	local p = Layout.NAV.padding
	for i = 1, count or Layout.NAV.count do
		local y = nav.y + p + (i - 1) * (Layout.NAV.button + Layout.NAV.gap)
		table.insert(out, Layout.rect(nav.x + p, y, nav.w - p * 2, Layout.NAV.button))
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

-- Menu panel chrome (Widgets.panel): the title band holds the title and the
-- close "X" (top-right, MIN_TOUCH_DESIGN square, same spot on every panel);
-- the body fills the rest, `pad` in from the sides and bottom.
Layout.PANEL_CHROME = table.freeze({
	pad = 12,
	close = Layout.MIN_TOUCH_DESIGN,
	closeInset = 6,
	titleSize = 20,
	header = Layout.MIN_TOUCH_DESIGN + 12, -- closeInset above and below the X
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

-- The box of the menu panel for a Nav key on `screen`. Every menu is full
-- window, so the key only documents the call site.
function Layout.panelFor(screen: Screen, _key: string): Rect
	return screen.panel
end

-- Close button, title and body boxes inside a panel box (PANEL_CHROME).
function Layout.panelClose(panel: Rect): Rect
	local c = Layout.PANEL_CHROME
	return Layout.rect(panel.x + panel.w - c.closeInset - c.close, panel.y + c.closeInset, c.close, c.close)
end

function Layout.panelTitle(panel: Rect): Rect
	local c = Layout.PANEL_CHROME
	return Layout.rect(panel.x + c.pad, panel.y + c.closeInset, panel.w - c.pad - c.close - c.closeInset * 2, c.close)
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

-- Every top-level box for a ScreenGui of viewportW x viewportH (see header).
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

	local hud = Layout.hud(W, compact, opts.hudVisible)
	local hudBottom = hud.rect.y + hud.rect.h
	local top = hudBottom + gap

	-- Banners and toasts draw above menus, so both keep clear of the menu
	-- close X (top-right of the panel; its x / y don't depend on the nav).
	-- Banners may cover a menu title, but stay centred left of the X column;
	-- toasts stack under the X row.
	local close = Layout.panelClose(Layout.fullWindowRect(0, top, W, H, inset))
	local bannerW = math.min(Layout.BANNER_WIDTH, W - m * 2, 2 * (close.x - gap) - W)
	local banners = Layout.rect((W - bannerW) / 2, hudBottom + 8, bannerW, 0)
	local toastW = math.min(Layout.TOAST_WIDTH, W - m * 2)
	local toastY = close.y + close.h + gap
	local toasts = Layout.rect(W - m - toastW, toastY, toastW, math.max(math.min(300, H - m - toastY), 0))

	-- Bottom cards: carry on the bottom line, tutorial above it while
	-- carrying. Full screen width (the nav ends above them), so a phone
	-- card doesn't shrink when the nav is expanded.
	local row = Layout.rect(m, 0, W - m * 2, 0)
	local carryX, carryW = centredIn(row, W, Layout.CARRY.w)
	local carry = Layout.rect(carryX, H - inset - Layout.CARRY.h, carryW, Layout.CARRY.h)
	local slapX, slapW = centredIn(row, W, Layout.SLAP.w)
	local slap = Layout.rect(slapX, carry.y + carry.h - Layout.SLAP.h, slapW, Layout.SLAP.h)
	local tutX, tutW = centredIn(row, W, Layout.TUTORIAL.w)
	local tutH = Layout.tutorialHeight(tutW)
	local tutorial = Layout.rect(tutX, H - inset - tutH, tutW, tutH)
	local tutorialCarrying = Layout.rect(tutX, carry.y - gap - tutH, tutW, tutH)

	-- Nav: centred between the HUD and the highest bottom card.
	local nav = Layout.navRect(collapsed, top, math.min(tutorial.y, tutorialCarrying.y) - gap)
	local columnX = nav.x + nav.w + gap
	local columnW = W - m - columnX

	-- The column (right of the nav) above the bottom cards; menus use the
	-- full-window box, which runs on down to the bottom inset.
	local column = Layout.rect(columnX, top, columnW, math.min(tutorial.y, carry.y) - gap - top)
	local panel = Layout.fullWindowRect(columnX, top, W, H, inset)

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
		navCollapsed = collapsed,
		bottomInset = inset,
		hud = hud,
		banners = banners,
		toasts = toasts,
		nav = nav,
		navButtons = Layout.navButtons(nav),
		column = column,
		panel = panel,
		carry = carry,
		slap = slap,
		tutorial = tutorial,
		tutorialCarrying = tutorialCarrying,
		daily = daily,
	}
end

return table.freeze(Layout)
