--!strict
--[[
	LayoutAssert: reusable layout checks on Layout.screen() rects (no
	Instances). Each check appends a readable problem string; a spec asserts
	the list is empty, so a failure names the box, the viewport and the
	numbers.

		local check = LayoutAssert.new("390x844 collapsed", screen)
		check.onScreen("Hud", screen.hud.rect)
		check.touch("Lock", screen.hud.items.Lock)
		check.text({ name = "Lock", text = "🔒 Lock $25\n+60s", size = 16, bold = true, w = 130, h = 56 })
		expect(check.report()).toBe("")

	`LayoutAssert.standard(label, screen)` runs every rule the v18 UI has to
	meet (see the spec): on-screen boxes, touch sizes, no overlaps between the
	HUD / nav / bottom cards, full-window menus with a tappable close X, and
	text that fits (Layout text estimate, unless the descriptor is
	TextWrapped into a tall-enough box or TextScaled).
]]

local Config = require("../../src/shared/Config")
local Format = require("../../src/ui/Format")
local Hint = require("../../src/ui/Hint")
local Layout = require("../../src/ui/Layout")
local LockHud = require("../../src/ui/LockHud")
local Nav = require("../../src/ui/Nav")
local ShopCatalog = require("../../src/ui/ShopCatalog")
local Tutorial = require("../../src/ui/Tutorial")

type Rect = Layout.Rect

-- A text box as the UI builds it: `w` x `h` is the label's box (design px).
export type TextDesc = {
	name: string,
	text: string,
	size: number,
	bold: boolean?,
	w: number,
	h: number,
	wrapped: boolean?, -- TextWrapped: may use more lines, must fit `h`
	scaled: boolean?, -- TextScaled: always fits
}

export type Checker = {
	label: string,
	screen: Layout.Screen,
	problems: { string },
	fail: (msg: string) -> (),
	onScreen: (name: string, r: Rect, margin: number?) -> (),
	inside: (name: string, r: Rect, outerName: string, outer: Rect) -> (),
	touch: (name: string, r: Rect) -> (),
	noOverlap: (aName: string, a: Rect, bName: string, b: Rect) -> (),
	text: (desc: TextDesc) -> (),
	report: () -> string,
}

local LayoutAssert = {}

LayoutAssert.VIEWPORTS = table.freeze({
	table.freeze({ name = "390x844", w = 390, h = 844 }),
	table.freeze({ name = "1920x1080", w = 1920, h = 1080 }),
})

-- The gate viewports (ScrollLists.spec too): full-window menus are checked
-- at all five, the whole `standard` rule set at VIEWPORTS.
LayoutAssert.GATE_VIEWPORTS = table.freeze({
	table.freeze({ name = "390x844", w = 390, h = 844 }),
	table.freeze({ name = "844x390", w = 844, h = 390 }),
	table.freeze({ name = "1024x768", w = 1024, h = 768 }),
	table.freeze({ name = "1366x768", w = 1366, h = 768 }),
	table.freeze({ name = "1920x1080", w = 1920, h = 1080 }),
})

local EPS = 1e-6

local function fmt(r: Rect): string
	return string.format("{x=%.1f y=%.1f w=%.1f h=%.1f}", r.x, r.y, r.w, r.h)
end
LayoutAssert.fmt = fmt

-- Every target viewport (default VIEWPORTS) with the nav collapsed and expanded.
function LayoutAssert.screens(
	viewports: { { name: string, w: number, h: number } }?
): { { label: string, screen: Layout.Screen } }
	local out = {}
	for _, vp in viewports or LayoutAssert.VIEWPORTS do
		for _, collapsed in { true, false } do
			table.insert(out, {
				label = `{vp.name} nav {if collapsed then "collapsed" else "expanded"}`,
				screen = Layout.screen(vp.w, vp.h, { navCollapsed = collapsed }),
			})
		end
	end
	return out
end

-- nil when `desc` fits, else why not.
function LayoutAssert.textFits(desc: TextDesc): string?
	if desc.scaled then
		return nil
	end
	if desc.wrapped then
		local h = Layout.wrappedHeight(desc.text, desc.size, desc.w, desc.bold)
		if h > desc.h + EPS then
			return string.format("wraps to %.1f px tall in %.1f x %.1f", h, desc.w, desc.h)
		end
		return nil
	end
	local w, h = Layout.textSize(desc.text, desc.size, desc.bold)
	if w > desc.w + EPS or h > desc.h + EPS then
		return string.format("needs %.1f x %.1f, box %.1f x %.1f", w, h, desc.w, desc.h)
	end
	return nil
end

-- nil when the layers draw in this order (bottom first), else why not.
function LayoutAssert.zOrder(layers: { string }): string?
	for i = 2, #layers do
		if not Layout.drawsAbove(layers[i], layers[i - 1]) then
			return `{layers[i]} does not draw above {layers[i - 1]}`
		end
	end
	return nil
end

function LayoutAssert.new(label: string, screen: Layout.Screen): Checker
	local self = { label = label, screen = screen, problems = {} } :: Checker

	function self.fail(msg: string)
		table.insert(self.problems, `[{label}] {msg}`)
	end

	function self.onScreen(name: string, r: Rect, margin: number?)
		if not Layout.fitsInViewport(r, screen.width + EPS, screen.height + EPS, margin) then
			self.fail(`{name} {fmt(r)} is off the {screen.width}x{screen.height} screen`)
		end
	end

	function self.inside(name: string, r: Rect, outerName: string, outer: Rect)
		if
			r.x < outer.x - EPS
			or r.y < outer.y - EPS
			or r.x + r.w > outer.x + outer.w + EPS
			or r.y + r.h > outer.y + outer.h + EPS
		then
			self.fail(`{name} {fmt(r)} is outside {outerName} {fmt(outer)}`)
		end
	end

	function self.touch(name: string, r: Rect)
		local px = math.min(r.w, r.h) * screen.scale
		if px + EPS < Layout.MIN_TOUCH then
			self.fail(string.format("%s is %.1f screen px (< MIN_TOUCH %d)", name, px, Layout.MIN_TOUCH))
		end
	end

	function self.noOverlap(aName: string, a: Rect, bName: string, b: Rect)
		if Layout.overlaps(a, b) then
			self.fail(`{aName} {fmt(a)} overlaps {bName} {fmt(b)}`)
		end
	end

	function self.text(desc: TextDesc)
		local why = LayoutAssert.textFits(desc)
		if why then
			self.fail(`text {desc.name} {string.format("%q", desc.text)} {why}`)
		end
	end

	function self.report(): string
		return table.concat(self.problems, "\n")
	end

	return self
end

-- Worst-case State for HUD text: big numbers, max rebirths, a lock running.
LayoutAssert.BIG_STATE = table.freeze({
	cash = 987.6e12,
	incomePerSec = 98.7e12,
	rebirths = Config.MAX_REBIRTHS,
	rebirthMultiplier = 1 + Config.MAX_REBIRTHS * Config.REBIRTH_MULTIPLIER_STEP,
	padsUnlocked = Config.PADS_MAX - 1,
	padsMax = Config.PADS_MAX,
	nextPadCost = 987.6e12,
	lockCost = 987.6e12,
	lockDuration = Config.LOCK_SECONDS + Config.MAX_REBIRTHS * Config.LOCK_SECONDS_PER_REBIRTH,
	lockUntil = 100 + Config.LOCK_MAX_REMAINING / 2,
	slimes = {},
	daily = { available = true, streak = Config.DAILY_STREAK_CAP or 7, amount = 987.6e12 },
})

-- HUD texts at their worst, against the boxes `hud` gives each item.
function LayoutAssert.hudTexts(screen: Layout.Screen): { TextDesc }
	local hud = screen.hud
	local compact = screen.compact
	local s = LayoutAssert.BIG_STATE
	local out: { TextDesc } = {}
	local function add(name: string, text: string, size: number, bold: boolean?, w: number, h: number)
		table.insert(out, { name = name, text = text, size = size, bold = bold, w = w, h = h })
	end
	local items = hud.items
	-- Chips: value label inset 6 px each side, 24 tall, TextSize 18 bold (16 compact).
	local chip = if compact then 16 else 18
	add("Cash", Format.formatCash(s.cash), chip, true, items.Cash.w - 12, 24)
	add("Income", Format.formatRate(s.incomePerSec), chip, true, items.Income.w - 12, 24)
	add(
		"Rebirths",
		`{s.rebirths} {Format.formatMultiplier(s.rebirthMultiplier)}`,
		chip,
		true,
		items.Rebirths.w - 12,
		24
	)
	add("Pads", `{s.padsMax}/{s.padsMax}`, chip, true, items.Pads.w - 12, 24)
	for _, caption in { "CASH", "INCOME", "REBIRTHS", "PADS" } do
		local key = string.upper(string.sub(caption, 1, 1)) .. string.lower(string.sub(caption, 2))
		add(`{key} caption`, caption, 11, true, items[key].w - 12, 14)
	end
	-- Lock block: title 20 / 18 (compact), sub 12 / 11, inset 4 px.
	local lockW = items.LockStatus.w - 8
	for _, status in
		{
			LockHud.status(nil, 100, Config.LOCK_MAX_REMAINING),
			LockHud.status(100 + Config.LOCK_MAX_REMAINING - 1, 100, Config.LOCK_MAX_REMAINING),
			LockHud.status(105, 100, Config.LOCK_MAX_REMAINING),
		}
	do
		add("LockStatus title", status.title, if compact then 18 else 20, true, lockW, 24)
		add("LockStatus sub", status.sub, if compact then 11 else 12, true, lockW, 14)
	end
	-- Buttons (no padding in Widgets.button): Lock 16 / 13, BuyPad 15, Daily 15, Shop 16.
	local maxed = table.clone(s) :: any
	maxed.lockUntil = 100 + Config.LOCK_MAX_REMAINING
	for _, state in { s, maxed } do
		local view = LockHud.lockButton(state, 100, Config.LOCK_MAX_REMAINING)
		add("Lock", view.text, if compact then 13 else 16, true, items.Lock.w, items.Lock.h)
	end
	add("BuyPad", LockHud.padButton(s, compact).text, 15, true, items.BuyPad.w, items.BuyPad.h)
	add("Daily", LockHud.dailyButton(s.daily, false, compact).text, 15, true, items.Daily.w, items.Daily.h)
	if items.Shop then
		add("Shop", "🛒 Shop\nUpgrade!", 16, true, items.Shop.w, items.Shop.h)
	end
	return out
end

-- Nav button texts: labels (expanded) or icons (collapsed), and the toggle.
function LayoutAssert.navTexts(screen: Layout.Screen): { TextDesc }
	local out: { TextDesc } = {}
	local toggle = screen.navButtons[1]
	table.insert(out, {
		name = "NavToggle",
		text = if screen.navCollapsed then "☰" else "◀ Menu",
		size = if screen.navCollapsed then 22 else 16,
		bold = true,
		w = toggle.w,
		h = toggle.h,
	})
	for i, entry in Nav.ENTRIES do
		local b = screen.navButtons[i + 1]
		if screen.navCollapsed then
			table.insert(out, { name = `Nav {entry.key} icon`, text = entry.icon, size = 26, w = b.w, h = b.h })
		else
			table.insert(out, { name = `Nav {entry.key} icon`, text = entry.icon, size = 26, w = 36, h = b.h })
			table.insert(
				out,
				{ name = `Nav {entry.key}`, text = entry.label, size = 18, bold = true, w = b.w - 46, h = b.h }
			)
		end
	end
	return out
end

-- Tutorial card: counter / title beside the Hide button, wrapped body.
function LayoutAssert.tutorialTexts(screen: Layout.Screen): { TextDesc }
	local out: { TextDesc } = {}
	local t = Layout.TUTORIAL
	for _, card in { { "tutorial", screen.tutorial }, { "tutorialCarrying", screen.tutorialCarrying } } do
		local r = card[2]
		for index, step in Tutorial.STEPS do
			local view = Tutorial.view(index) :: Tutorial.StepView
			table.insert(out, {
				name = `{card[1]} {step.id} counter`,
				text = view.counter,
				size = 12,
				bold = true,
				w = r.w - 100,
				h = 16,
			})
			table.insert(
				out,
				{ name = `{card[1]} {step.id} title`, text = step.title, size = 20, bold = true, w = r.w - 100, h = 24 }
			)
			table.insert(out, {
				name = `{card[1]} {step.id} body`,
				text = step.body,
				size = t.bodyTextSize,
				w = r.w - t.padX * 2,
				h = r.h - t.bodyTop - t.padBottom,
				wrapped = true,
			})
		end
		table.insert(
			out,
			{ name = `{card[1]} Hide`, text = "Hide", size = 13, bold = true, w = 72, h = Layout.MIN_TOUCH_DESIGN }
		)
	end
	return out
end

-- Daily popup card texts at their longest.
function LayoutAssert.dailyTexts(screen: Layout.Screen): { TextDesc }
	local w = screen.daily.w
	return {
		{
			name = "Daily title",
			text = "Daily Reward",
			size = 24,
			bold = true,
			w = w - 2 * (Layout.MIN_TOUCH_DESIGN + 10),
			h = 34,
		},
		{ name = "Daily streak", text = "Streak: 77 days", size = 16, w = w, h = 20 },
		{ name = "Daily amount", text = `+{Format.formatCash(987.6e12)}`, size = 36, bold = true, w = w, h = 44 },
		{ name = "Daily hint", text = "Come back every day to grow your streak.", size = 13, w = w, h = 18 },
		{ name = "Daily hint claimed", text = "Come back tomorrow for the next reward.", size = 13, w = w, h = 18 },
		{ name = "Daily claim", text = "Claimed", size = 20, bold = true, w = 200, h = Layout.BUTTON },
	}
end

-- Carry card: name / status beside Drop (TextWrapped status, 2 lines).
function LayoutAssert.carryTexts(screen: Layout.Screen): { TextDesc }
	local c = screen.carry
	local textW = c.w - Layout.CARRY_TEXT_RESERVE
	return {
		{
			name = "Carry stolen",
			text = "STOLEN - escapes in 0:30! Run home!",
			size = 14,
			w = textW,
			h = 36,
			wrapped = true,
		},
		{
			name = "Carry wild",
			text = "Wild slime - bring it to your plot",
			size = 14,
			w = textW,
			h = 36,
			wrapped = true,
		},
		{ name = "Carry Drop", text = "Drop", size = 15, bold = true, w = 100, h = Layout.BUTTON },
		{
			name = "Slap",
			text = "SLAP SomeVeryLongDisplayName!\nSave your slime",
			size = 22,
			w = 0,
			h = 0,
			scaled = true,
		},
	}
end

-- Shop rows (menu body = panel - 24, row = body - 10, text = row - 140;
-- 84 px rows: 50 px description, Layout.BUTTON Buy).
function LayoutAssert.shopTexts(panel: Rect): { TextDesc }
	local textW = panel.w - 24 - 10 - 140
	local out: { TextDesc } = {}
	local state = { cash = 0, lockCost = 987.6e12, lockDuration = 310, shop = {} }
	local actions = { Lock = true, BuyLockUpgrade = true, BuySpeedCoil = true, BuyUpgrade = true }
	local views = ShopCatalog.views(state, actions, Config)
	for _, u in Config.UPGRADES do
		table.insert(
			views,
			ShopCatalog.upgradeViews({
				cash = 0,
				upgrades = {
					{
						id = u.id,
						name = u.name,
						text = u.text,
						level = 0,
						maxLevel = 5,
						price = 987.6e12,
						unlocked = false,
						requires = 50,
					},
				},
			}, actions)[1]
		)
	end
	for _, view in views do
		table.insert(
			out,
			{ name = `Shop {view.item.id} name`, text = view.item.name, size = 16, bold = true, w = textW, h = 20 }
		)
		table.insert(
			out,
			{ name = `Shop {view.item.id} desc`, text = view.description, size = 13, w = textW, h = 50, wrapped = true }
		)
		table.insert(out, {
			name = `Shop {view.item.id} buy`,
			text = view.buttonText,
			size = 15,
			bold = true,
			w = 110,
			h = Layout.BUTTON,
		})
	end
	return out
end

-- Panel titles as Widgets.panel shows them (Panels/*.luau), per Nav key.
LayoutAssert.PANEL_TITLES = table.freeze({
	Plot = "My Plot",
	Merge = "Merge Vat",
	Shop = "Shop",
	Rebirth = "Rebirth",
	Goals = "Goals",
	Dex = "SlimeDex",
	Leaders = "Top Earners",
})

-- The full-window menu box: right of the nav (+ GAP), under the HUD (+ GAP),
-- to MARGIN from the right edge and down to the bottom inset.
function LayoutAssert.expectedPanel(screen: Layout.Screen): Rect
	local x = screen.nav.x + screen.nav.w + Layout.GAP
	local y = screen.hud.rect.y + screen.hud.rect.h + Layout.GAP
	return Layout.rect(x, y, screen.width - Layout.MARGIN - x, screen.height - screen.bottomInset - y)
end

-- Smallest usable menu body (design px): a couple of list rows.
LayoutAssert.MIN_BODY = table.freeze({ w = 240, h = 120 })

-- Full-window panel rules for every Nav menu: the expected rect, on screen,
-- clear of the HUD and nav, a usable body, and a close X that is
-- MIN_TOUCH, inside the panel, top-right, and never under the HUD or a
-- bottom card (those draw above menus).
function LayoutAssert.panelChecks(check: Checker)
	local screen = check.screen
	local expected = LayoutAssert.expectedPanel(screen)
	local c = Layout.PANEL_CHROME
	for _, entry in Nav.ENTRIES do
		local key = entry.key
		local r = Layout.panelFor(screen, key)
		local name = `Panel.{key}`
		if
			math.abs(r.x - expected.x) > EPS
			or math.abs(r.y - expected.y) > EPS
			or math.abs(r.w - expected.w) > EPS
			or math.abs(r.h - expected.h) > EPS
		then
			check.fail(`{name} {fmt(r)} is not the full-window rect {fmt(expected)}`)
		end
		check.onScreen(name, r, Layout.MARGIN)
		check.noOverlap(name, r, "Hud", screen.hud.rect)
		check.noOverlap(name, r, "Nav", screen.nav)
		local body = Layout.panelBody(r)
		check.inside(`{name}.Body`, body, name, r)
		if body.w < LayoutAssert.MIN_BODY.w or body.h < LayoutAssert.MIN_BODY.h then
			check.fail(`{name}.Body {fmt(body)} is smaller than {LayoutAssert.MIN_BODY.w}x{LayoutAssert.MIN_BODY.h}`)
		end

		local close = Layout.panelClose(r)
		local closeName = `{name}.Close`
		check.touch(closeName, close)
		check.inside(closeName, close, name, r)
		if
			math.abs(close.x + close.w + c.closeInset - (r.x + r.w)) > EPS
			or math.abs(close.y - c.closeInset - r.y) > EPS
		then
			check.fail(`{closeName} {fmt(close)} is not in the top-right corner of {fmt(r)}`)
		end
		for _, other in
			{
				{ "Hud", screen.hud.rect },
				{ "Carry", screen.carry },
				{ "Slap", screen.slap },
				{ "Tutorial", screen.tutorial },
				{ "TutorialCarrying", screen.tutorialCarrying },
			}
		do
			check.noOverlap(closeName, close, other[1] :: string, other[2] :: Rect)
		end
		-- Toasts and banners draw above menus too. Banners grow down from
		-- their top as alerts stack, so their whole column must miss the X.
		check.noOverlap(closeName, close, "Toasts", screen.toasts)
		local b = screen.banners
		check.noOverlap(closeName, close, "Banners", Layout.rect(b.x, b.y, b.w, screen.height - b.y))
		local title = Layout.panelTitle(r)
		check.noOverlap(`{name}.Title`, title, closeName, close)
		check.text({
			name = `{name}.Title`,
			text = LayoutAssert.PANEL_TITLES[key] or key,
			size = c.titleSize,
			bold = true,
			w = title.w,
			h = title.h,
		})
		check.text({ name = closeName, text = "X", size = 24, bold = true, w = close.w, h = close.h })
	end
	-- Top-bar hints stay up while a menu is open and draw above it.
	local close = Layout.panelClose(screen.panel)
	for id, hint in Hint.STEPS do
		local place = Hint.place(screen, screen.hud, { id = id, text = hint.text, target = hint.target })
		if place then
			check.noOverlap(`Hint.{id} bubble`, place.bubble, "Panel.Close", close)
		end
	end
end

-- Just the full-window panel rules (any viewport; `standard` also runs them).
function LayoutAssert.fullWindow(label: string, screen: Layout.Screen): Checker
	local check = LayoutAssert.new(label, screen)
	LayoutAssert.panelChecks(check)
	return check
end

-- Every v18 rule for one screen; returns the checker (use `report()`).
function LayoutAssert.standard(label: string, screen: Layout.Screen): Checker
	local check = LayoutAssert.new(label, screen)
	local m = Layout.MARGIN
	local hud = screen.hud

	-- HUD: on screen, items inside the bar, no two items overlapping, buttons tappable.
	check.onScreen("Hud", hud.rect, Layout.TOP)
	local names = {}
	for name in hud.items do
		table.insert(names, name)
	end
	table.sort(names)
	for i, name in names do
		local r = hud.items[name]
		check.inside(`Hud.{name}`, r, "Hud", hud.rect)
		if (Layout.HUD_ITEMS :: any)[name].button then
			check.touch(`Hud.{name}`, r)
		end
		for j = i + 1, #names do
			check.noOverlap(`Hud.{name}`, r, `Hud.{names[j]}`, hud.items[names[j]])
		end
	end
	if screen.compact and #hud.rows ~= 2 then
		check.fail(`compact HUD has {#hud.rows} rows (want 2)`)
	elseif not screen.compact and #hud.rows ~= 1 then
		check.fail(`desktop HUD has {#hud.rows} rows (want 1)`)
	end

	-- Nav: on screen, under the HUD, every button tappable and inside it.
	check.onScreen("Nav", screen.nav, m)
	check.noOverlap("Nav", screen.nav, "Hud", hud.rect)
	if #screen.navButtons ~= #Nav.ENTRIES + 1 then
		check.fail(`nav has {#screen.navButtons} buttons (want {#Nav.ENTRIES + 1})`)
	end
	for i, b in screen.navButtons do
		check.touch(`NavButton{i}`, b)
		check.inside(`NavButton{i}`, b, "Nav", screen.nav)
	end
	if screen.nav.w ~= Layout.navWidth(screen.navCollapsed) then
		check.fail(`nav width {screen.nav.w} ~= Layout.navWidth({screen.navCollapsed})`)
	end

	-- Menu panels: full window, close X tappable (LayoutAssert.fullWindow).
	check.onScreen("column", screen.column, m)
	LayoutAssert.panelChecks(check)

	-- Bottom cards: on screen, above the touch-control inset, clear of the nav.
	local floor = screen.height - screen.bottomInset
	for _, card in
		{
			{ "Carry", screen.carry },
			{ "Slap", screen.slap },
			{ "Tutorial", screen.tutorial },
			{ "TutorialCarrying", screen.tutorialCarrying },
		}
	do
		local name, r = card[1] :: string, card[2] :: Rect
		check.onScreen(name, r, m)
		if r.y + r.h > floor + EPS then
			check.fail(`{name} {fmt(r)} reaches into the bottom inset (floor {floor})`)
		end
		check.noOverlap(name, r, "Nav", screen.nav)
		check.noOverlap(name, r, "Hud", hud.rect)
	end
	check.noOverlap("TutorialCarrying", screen.tutorialCarrying, "Carry", screen.carry)
	check.touch("Slap", screen.slap)

	-- Overlays.
	check.onScreen("Daily", screen.daily, m)
	check.onScreen("Toasts", screen.toasts, m)
	check.noOverlap("Toasts", screen.toasts, "Hud", hud.rect)
	check.onScreen("Banners", screen.banners, m)

	-- Hints for every step that points at a button.
	for id, hint in Hint.STEPS do
		local view = { id = id, text = hint.text, target = hint.target }
		local place = Hint.place(screen, hud, view)
		if place == nil then
			check.fail(`hint {id} has no target`)
		else
			check.onScreen(`Hint.{id} bubble`, place.bubble, m)
			check.onScreen(`Hint.{id} ring`, place.ring)
			check.noOverlap(`Hint.{id} bubble`, place.bubble, "Hud", hud.rect)
			check.noOverlap(`Hint.{id} bubble`, place.bubble, "Nav", screen.nav)
			check.text({
				name = `Hint.{id}`,
				text = hint.text,
				size = Hint.TEXT_SIZE,
				bold = true,
				w = place.bubble.w - Hint.PAD_X * 2,
				h = place.bubble.h,
				wrapped = true,
			})
		end
	end

	-- Text. Phones collapse an expanded nav when a panel opens
	-- (init.client setOpen), so panel text is measured on that screen.
	local panelScreen = if screen.compact and not screen.navCollapsed
		then Layout.screen(screen.viewportW, screen.viewportH, { navCollapsed = true })
		else screen
	for _, list in
		{
			LayoutAssert.hudTexts(screen),
			LayoutAssert.navTexts(screen),
			LayoutAssert.tutorialTexts(screen),
			LayoutAssert.dailyTexts(screen),
			LayoutAssert.carryTexts(screen),
			LayoutAssert.shopTexts(Layout.panelFor(panelScreen, "Shop")),
		}
	do
		for _, desc in list do
			check.text(desc)
		end
	end
	return check
end

return table.freeze(LayoutAssert)
