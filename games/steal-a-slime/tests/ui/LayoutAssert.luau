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
	HUD / nav / bottom cards, a full-window menu backdrop with content-sized
	menu cards (v28) each with a tappable close X, and
	text that fits (Layout text estimate, unless the descriptor is
	TextWrapped into a tall-enough box or TextScaled).
	`navReachable` (v27 gate N1) checks every nav button is on screen with
	nothing drawn over it, `noNegativeSizes` that no box has w or h < 0,
	`notSquashed` (PR gate) that one uniform scale maps design px to the
	viewport and every button keeps its design aspect ratio.
]]

local Config = require("../../src/shared/Config")
local Format = require("../../src/ui/Format")
local GuideTips = require("../../src/ui/GuideTips")
local Hint = require("../../src/ui/Hint")
local Icons = require("../../src/ui/Icons")
local Layout = require("../../src/ui/Layout")
local LockHud = require("../../src/ui/LockHud")
local Nav = require("../../src/ui/Nav")
local ShopCatalog = require("../../src/ui/ShopCatalog")
local SlimeDex = require("../../src/ui/SlimeDex")
local Tutorial = require("../../src/ui/Tutorial")

-- Row geometry constants only (Panels/* build Instances in .new, never at load).
local GuidePanel = { TIP_H = 44 }
local RebirthPanel = {
	ROWS = {
		need = { y = 0, h = 112 },
		slime = { y = 120, h = 72 },
		gives = { y = 200, h = 40 },
		keeper = { y = 246, h = 22 },
		button = { y = 276, h = Layout.BUTTON },
		note = { y = 338, h = 18 },
	},
}
local ShopPanel = { BADGE = 48, BUY_W = 110, DESC_H = 32 }

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
	aspect: (name: string, r: Rect, designW: number, designH: number, tolerance: number?) -> (),
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

-- Landscape phone (v27 gate N1): Studio's 844x390, and 844x332 = its
-- ScreenGui under the Roblox top bar (58 px). Both get `standard` and
-- `navReachable`.
LayoutAssert.LANDSCAPE_VIEWPORTS = table.freeze({
	table.freeze({ name = "844x390", w = 844, h = 390 }),
	table.freeze({ name = "844x332", w = 844, h = 332 }),
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

	-- w / h within `tolerance` (default ASPECT_TOLERANCE) of designW / designH.
	function self.aspect(name: string, r: Rect, designW: number, designH: number, tolerance: number?)
		local tol = tolerance or LayoutAssert.ASPECT_TOLERANCE
		if r.h <= EPS or designH <= EPS then
			self.fail(`{name} {fmt(r)} has no height (squashed)`)
			return
		end
		local ratio = (r.w / r.h) / (designW / designH)
		if math.abs(ratio - 1) > tol + EPS then
			self.fail(
				string.format(
					"%s %s is squashed: aspect %.3f vs design %.3f (%dx%d)",
					name,
					fmt(r),
					r.w / r.h,
					designW / designH,
					designW,
					designH
				)
			)
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
		text = if screen.navCollapsed then Icons.NAV_COLLAPSED else Icons.NAV_EXPANDED,
		size = if screen.navCollapsed then 13 else 16,
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
	local tileW = (w - 24) / 7.6 - 4 -- calendar tile (weights 1 x6 + 1.6, see DailyPopup)
	return {
		{ name = "Daily tile day", text = "Day 6", size = 10, w = tileW, h = 14 },
		{ name = "Daily tile amount", text = Format.formatCash(987.6e12), size = 8, w = tileW - 4, h = 14 },
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

-- Shop rows (Panels/Shop, v28): body = card - 24 (PANEL_CHROME.pad), row =
-- body - 10, text = row - badge column - Buy column; ROW-high rows, one
-- line of name, up to two of description, the level chip under the badge.
function LayoutAssert.shopTexts(panel: Rect): { TextDesc }
	local textW = panel.w - Layout.PANEL_CHROME.pad * 2 - 10 - (8 + ShopPanel.BADGE + 10) - (ShopPanel.BUY_W + 16)
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
						level = 9,
						maxLevel = 10,
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
			{ name = `Shop {view.item.id} name`, text = view.item.name, size = 17, bold = true, w = textW, h = 22 }
		)
		if view.levelText then
			local chip = { name = `Shop {view.item.id} level`, text = view.levelText, size = 11, bold = true }
			chip.w, chip.h = ShopPanel.BADGE + 8, 14
			table.insert(out, chip :: any)
		end
		table.insert(out, {
			name = `Shop {view.item.id} desc`,
			text = view.description,
			size = 13,
			w = textW,
			h = ShopPanel.DESC_H,
			wrapped = true,
		})
		table.insert(out, {
			name = `Shop {view.item.id} buy`,
			text = view.buttonText,
			size = 16,
			bold = true,
			w = ShopPanel.BUY_W,
			h = Layout.BUTTON,
		})
	end
	return out
end

-- Rebirth card texts (Panels/Rebirth.ROWS), worst-case numbers: body = card - 24.
function LayoutAssert.rebirthTexts(panel: Rect): { TextDesc }
	local w = panel.w - Layout.PANEL_CHROME.pad * 2
	local rows = RebirthPanel.ROWS
	local chipW = w / 2 - 4
	return {
		{ name = "Rebirth heading", text = "TO REBIRTH 100 YOU NEED", size = 14, bold = true, w = w - 24, h = 18 },
		{ name = "Rebirth cost", text = "💰 $987.6Qa", size = 30, bold = true, w = w - 24, h = 36 },
		{ name = "Rebirth missing", text = "$987.6Qa / $987.6Qa · $987.6Qa more", size = 14, w = w - 24, h = 18 },
		{ name = "Rebirth income", text = "📈 x99.5 income", size = 16, bold = true, w = chipW, h = rows.gives.h },
		{ name = "Rebirth lock", text = "🔒 +60s lock", size = 16, bold = true, w = chipW, h = rows.gives.h },
		{
			name = "Rebirth button",
			text = "♻️ Need $987.6Qa more",
			size = 20,
			bold = true,
			w = w,
			h = rows.button.h,
		},
		{
			name = "Rebirth note",
			text = "Resets cash and slimes. Keeps ★, pads, upgrades.",
			size = 12,
			w = w,
			h = rows.note.h,
		},
	}
end

-- Guide tips (Panels/Guide): one line each, body = card - 24, row - 8 - padding 12.
function LayoutAssert.guideTexts(panel: Rect): { TextDesc }
	local w = panel.w - Layout.PANEL_CHROME.pad * 2 - 8 - 12
	local out: { TextDesc } = {}
	local tips = { "A thief has your slime: chase and SLAP!", "Free pad: bring home another slime" }
	for _, tip in GuideTips.GENERAL do
		table.insert(tips, tip.text)
	end
	for i, text in tips do
		table.insert(out, { name = `Guide tip {i}`, text = `🚨  {text}`, size = 15, w = w, h = GuidePanel.TIP_H })
	end
	return out
end

-- Welcome-back rows (Panels/Welcome): longest copy the card can show, row text = card - 24 - (ICON + 32).
function LayoutAssert.welcomeTexts(panel: Rect): { TextDesc }
	local w = panel.w - Layout.PANEL_CHROME.pad * 2 - 72
	local out: { TextDesc } = {}
	local texts = {
		"+999.99Qa earned while away",
		"12 slimes grew on your pads",
		"Daily reward ready: 999.99Qa",
		"Collect 1000 slimes in total (999/1000)",
	}
	for i, text in texts do
		table.insert(out, { name = `Welcome row {i}`, text = text, size = 18, w = w, h = 56, wrapped = true })
	end
	return out
end

-- Sound card texts (Panels/Sound): the mute button in both states, the two slider names and their percent.
function LayoutAssert.soundTexts(panel: Rect): { TextDesc }
	local w = Layout.panelBody(panel).w
	local out: { TextDesc } = {}
	for _, muted in { true, false } do
		local text = if muted then `{Icons.SOUND_OFF} Muted` else `{Icons.SOUND_ON} Sound on`
		table.insert(
			out,
			{ name = `Sound mute ({text})`, text = text, size = 22, bold = true, w = w, h = Layout.BUTTON }
		)
	end
	for _, name in { "🎵 Music", "🔔 SFX" } do
		table.insert(out, { name = `Sound {name}`, text = name, size = 18, bold = true, w = w * 0.7, h = 24 })
	end
	table.insert(out, { name = "Sound percent", text = "100%", size = 18, bold = true, w = w * 0.3, h = 24 })
	return out
end

-- Panel titles as Widgets.panel shows them (Panels/*.luau), per menu key
-- (the Nav keys plus the Guide card, which has no nav button).
LayoutAssert.PANEL_TITLES = table.freeze({
	Plot = "My Plot",
	Merge = "Merge Vat",
	Shop = "Shop",
	Rebirth = "Rebirth",
	Goals = "Goals",
	Dex = "SlimeDex",
	Leaders = "Top Earners",
	Codes = "Codes",
	Sound = "Sound",
	Guide = "Guide",
	Welcome = "Welcome back!",
})

-- Every menu key the UI opens: Nav.ENTRIES order, then "Guide", "Welcome".
function LayoutAssert.menuKeys(): { string }
	local keys = {}
	for _, entry in Nav.ENTRIES do
		table.insert(keys, entry.key)
	end
	table.insert(keys, "Sound")
	table.insert(keys, "Guide")
	table.insert(keys, "Welcome")
	return keys
end

-- The full-window menu backdrop (screen.panel): right of the nav (+ GAP),
-- under the HUD (+ GAP), to MARGIN from the right edge and down to the
-- bottom inset.
function LayoutAssert.expectedPanel(screen: Layout.Screen): Rect
	local x = screen.nav.x + screen.nav.w + Layout.GAP
	local y = screen.hud.rect.y + screen.hud.rect.h + Layout.GAP
	return Layout.rect(x, y, screen.width - Layout.MARGIN - x, screen.height - screen.bottomInset - y)
end

-- Smallest usable menu body (design px): a couple of list rows.
LayoutAssert.MIN_BODY = table.freeze({ w = 240, h = 120 })

-- v28 menu rules: the dimmed backdrop is the full-window rect; every menu
-- card (Nav keys + Guide) is MENU_WIDTH (or the backdrop width), centred
-- in it horizontally, MENU_HEIGHTS tall (or the backdrop height), inside
-- it, clear of the HUD and nav, with a usable body and a close X that is
-- MIN_TOUCH, inside the card, top-right, and never under the HUD, a
-- bottom card, the toasts or the banners (those draw above menus).
function LayoutAssert.panelChecks(check: Checker)
	local screen = check.screen
	local expected = LayoutAssert.expectedPanel(screen)
	local back = screen.panel
	local c = Layout.PANEL_CHROME
	if
		math.abs(back.x - expected.x) > EPS
		or math.abs(back.y - expected.y) > EPS
		or math.abs(back.w - expected.w) > EPS
		or math.abs(back.h - expected.h) > EPS
	then
		check.fail(`Panel backdrop {fmt(back)} is not the full-window rect {fmt(expected)}`)
	end
	local wantW = math.min(Layout.MENU_WIDTH, back.w)
	for _, key in LayoutAssert.menuKeys() do
		local r = Layout.panelFor(screen, key)
		local name = `Panel.{key}`
		local wantH = math.min(Layout.menuHeight(key), back.h)
		if math.abs(r.w - wantW) > EPS or math.abs(r.h - wantH) > EPS then
			check.fail(`{name} {fmt(r)} is not {wantW}x{wantH} (content-sized card)`)
		end
		if math.abs((r.x + r.w / 2) - (back.x + back.w / 2)) > 1 then
			check.fail(`{name} {fmt(r)} is not centred in the backdrop {fmt(back)}`)
		end
		check.inside(name, r, "Panel backdrop", back)
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
		-- Top-bar hints stay up while a menu is open and draw above it.
		for id, hint in Hint.STEPS do
			local place = Hint.place(screen, screen.hud, { id = id, text = hint.text, target = hint.target })
			if place then
				check.noOverlap(`Hint.{id} bubble`, place.bubble, closeName, close)
			end
		end
	end
end

-- Just the full-window panel rules (any viewport; `standard` also runs them).
function LayoutAssert.fullWindow(label: string, screen: Layout.Screen): Checker
	local check = LayoutAssert.new(label, screen)
	LayoutAssert.panelChecks(check)
	return check
end

-- Boxes that draw over (or beside) the nav while no menu is open, plus the
-- menu box itself. Banners grow down from their top, so their whole column
-- counts.
function LayoutAssert.overlays(screen: Layout.Screen): { { name: string, rect: Rect } }
	local b = screen.banners
	local out = {
		{ name = "Hud", rect = screen.hud.rect },
		{ name = "Toasts", rect = screen.toasts },
		{ name = "Banners", rect = Layout.rect(b.x, b.y, b.w, screen.height - b.y) },
		{ name = "Panel", rect = screen.panel },
		{ name = "Carry", rect = screen.carry },
		{ name = "Slap", rect = screen.slap },
		{ name = "Tutorial", rect = screen.tutorial },
		{ name = "TutorialCarrying", rect = screen.tutorialCarrying },
	}
	for name, r in screen.hud.items do
		table.insert(out, { name = `Hud.{name}`, rect = r })
	end
	for id, hint in Hint.STEPS do
		local place = Hint.place(screen, screen.hud, { id = id, text = hint.text, target = hint.target })
		if place then
			table.insert(out, { name = `Hint.{id} bubble`, rect = place.bubble })
		end
	end
	return out
end

-- v27 gate N1: every nav button (toggle + Nav.ENTRIES) is fully on screen
-- and nothing above overlaps it, so a tap on it reaches it.
function LayoutAssert.navReachable(check: Checker)
	local screen = check.screen
	if #screen.navButtons ~= #Nav.ENTRIES + 1 then
		check.fail(`nav has {#screen.navButtons} buttons (want {#Nav.ENTRIES + 1})`)
	end
	local overlays = LayoutAssert.overlays(screen)
	for i, b in screen.navButtons do
		local name = if i == 1 then "Nav.Toggle" else `Nav.{Nav.ENTRIES[i - 1].key}`
		check.onScreen(name, b)
		check.inside(name, b, "Nav", screen.nav)
		check.touch(name, b)
		for _, o in overlays do
			check.noOverlap(name, b, o.name, o.rect)
		end
	end
end

-- Worst-case badge texts sit fully inside their nav button, clear of the icon.
function LayoutAssert.navBadges(check: Checker)
	for i, entry in Nav.ENTRIES do
		local b = check.screen.navButtons[i + 1]
		local icon = Layout.rect(b.x + 4, b.y + 20, 36, b.h - 20)
		for _, text in { "!", "$", "100%" } do
			local name = `Nav.{entry.key} badge "{text}"`
			local r = Layout.navBadge(b, text)
			check.inside(name, r, `Nav.{entry.key}`, b)
			if not check.screen.navCollapsed then
				check.noOverlap(name, r, `Nav.{entry.key} icon`, icon)
			end
		end
	end
end

-- Every box on `screen` (and the menu chrome and Dex list inside the menu
-- box) has w >= 0 and h >= 0.
function LayoutAssert.noNegativeSizes(check: Checker)
	local screen = check.screen
	local function visit(name: string, value: any)
		if type(value) ~= "table" then
			return
		end
		if type(value.w) == "number" and type(value.h) == "number" then
			if value.w < -EPS or value.h < -EPS then
				check.fail(`{name} {fmt(value)} has a negative size`)
			end
			return
		end
		for k, v in value do
			visit(`{name}.{k}`, v)
		end
	end
	visit("screen", screen)
	for _, key in LayoutAssert.menuKeys() do
		local card = Layout.panelFor(screen, key)
		visit(`Panel.{key}`, card)
		visit(`Panel.{key}.Body`, Layout.panelBody(card))
		visit(`Panel.{key}.Close`, Layout.panelClose(card))
		visit(`Panel.{key}.Title`, Layout.panelTitle(card))
	end
	local body = Layout.panelBody(Layout.panelFor(screen, "Dex"))
	for _, rewards in { false, true } do
		local header = SlimeDex.header(body.h, rewards)
		local listH = body.h - header.listTop
		if listH < SlimeDex.MIN_LIST then
			check.fail(`Dex list is {listH} px in a {body.h} px body (rewards {rewards}; want >= {SlimeDex.MIN_LIST})`)
		end
	end
end

-- Largest allowed w/h drift from the design aspect for `aspect`.
LayoutAssert.ASPECT_TOLERANCE = 0.02

-- PR gate: no aspect-ratio distortion. One UIScale maps design px to the
-- viewport on both axes; HUD items, nav buttons (square when collapsed), the
-- menu close X and Slap keep their design proportions. Slap may narrow with a
-- narrow carry card, but never below 3/4 of its design aspect.
function LayoutAssert.notSquashed(check: Checker)
	local screen = check.screen
	local sx, sy = screen.width * screen.scale, screen.height * screen.scale
	if math.abs(sx - screen.viewportW) > 0.01 or math.abs(sy - screen.viewportH) > 0.01 then
		check.fail(
			string.format(
				"scale is not uniform: %.2f x %.2f design px at %.3f is not %dx%d",
				screen.width,
				screen.height,
				screen.scale,
				screen.viewportW,
				screen.viewportH
			)
		)
	end
	for name, r in screen.hud.items do
		local item = (Layout.HUD_ITEMS :: any)[name]
		check.aspect(`Hud.{name}`, r, if screen.compact then item.cw else item.w, item.h)
	end
	local nav = Layout.NAV
	local cell = (if screen.navCollapsed then nav.collapsedWidth else nav.expandedWidth) - nav.padding * 2
	for i, b in screen.navButtons do
		local name = if i == 1 then "Nav.Toggle" else `Nav.{Nav.ENTRIES[i - 1].key}`
		check.aspect(name, b, cell, nav.button)
	end
	local close = Layout.panelClose(Layout.panelFor(screen, "Shop"))
	check.aspect("Panel.Close", close, Layout.PANEL_CHROME.close, Layout.PANEL_CHROME.close)
	local slap = screen.slap
	local design = Layout.SLAP.w / Layout.SLAP.h
	if slap.h <= EPS or slap.w / slap.h > design + EPS or slap.w / slap.h < design * 0.75 - EPS then
		check.fail(string.format("Slap %s is squashed: aspect outside [%.2f, %.2f]", fmt(slap), design * 0.75, design))
	end
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
	if screen.short and #hud.rows ~= 1 then
		check.fail(`short HUD has {#hud.rows} rows (want 1)`)
	elseif screen.compact and not screen.short and #hud.rows ~= 2 then
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
	if screen.nav.w ~= Layout.navWidth(screen.navCollapsed, screen.navColumns) then
		check.fail(`nav width {screen.nav.w} ~= Layout.navWidth({screen.navCollapsed}, {screen.navColumns})`)
	end
	for i = 1, #screen.navButtons do
		for j = i + 1, #screen.navButtons do
			check.noOverlap(`NavButton{i}`, screen.navButtons[i], `NavButton{j}`, screen.navButtons[j])
		end
	end

	-- Menus: full-window backdrop, content-sized cards, close X tappable.
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

	-- The Sound button (FEATURES.Audio) sits where a menu's X would: tappable, clear of everything idle,
	-- and out of the bottom-right thumb zone (Roblox's jump button: the bottom TOUCH_CONTROLS_HEIGHT strip
	-- plus a 120 px square above it).
	check.onScreen("Sound", screen.sound, m)
	check.touch("Sound", screen.sound)
	local thumbSide = 120
	local thumbTop = screen.height - Layout.TOUCH_CONTROLS_HEIGHT - thumbSide
	check.noOverlap(
		"Sound",
		screen.sound,
		"JumpZone",
		Layout.rect(screen.width - thumbSide, thumbTop, thumbSide, screen.height - thumbTop)
	)
	for _, other in
		{
			{ "Hud", hud.rect },
			{ "Nav", screen.nav },
			{ "Carry", screen.carry },
			{ "Slap", screen.slap },
			{ "Tutorial", screen.tutorial },
			{ "TutorialCarrying", screen.tutorialCarrying },
			{ "Toasts", screen.toasts },
			{ "Banners", screen.banners },
		}
	do
		check.noOverlap("Sound", screen.sound, other[1] :: string, other[2] :: Rect)
	end

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
			LayoutAssert.rebirthTexts(Layout.panelFor(panelScreen, "Rebirth")),
			LayoutAssert.guideTexts(Layout.panelFor(panelScreen, "Guide")),
			LayoutAssert.soundTexts(Layout.panelFor(panelScreen, "Sound")),
			LayoutAssert.welcomeTexts(Layout.panelFor(panelScreen, "Welcome")),
		}
	do
		for _, desc in list do
			check.text(desc)
		end
	end
	return check
end

return table.freeze(LayoutAssert)
