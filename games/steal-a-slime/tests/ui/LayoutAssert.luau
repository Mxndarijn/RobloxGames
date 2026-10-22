--!strict
--[[
	LayoutAssert: reusable layout checks on Layout.screen() rects (no
	Instances). Each check appends a readable problem string; a spec asserts
	the list is empty, so a failure names the box, the viewport and the
	numbers.

		local check = LayoutAssert.new("390x844 collapsed", screen)
		check.onScreen("Nav", screen.nav)
		check.touch("Nav.Rebirth", screen.navButtons[1])
		check.text({ name = "Label", text = "SlimeDex", size = 14, bold = true, w = 78, h = 18 })
		expect(check.report()).toBe("")

	`LayoutAssert.standard(label, screen)` runs every rule the v18 UI has to
	meet (see the spec): on-screen boxes, touch sizes, no overlaps between the
	nav / bottom clusters / bottom cards, a status tooltip that stays on screen (B8), a full-window menu backdrop with content-sized
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
local HudClusters = require("../../src/ui/HudClusters")
local Icons = require("../../src/ui/Icons")
local InventoryLayout = require("../../src/ui/InventoryLayout")
local Layout = require("../../src/ui/Layout")
local Nav = require("../../src/ui/Nav")
local Remotes = require("../../src/shared/Remotes")
local ShopCatalog = require("../../src/ui/ShopCatalog")
local Shops = require("../../src/shared/Shops")
local SlimeDex = require("../../src/ui/SlimeDex")
local Tutorial = require("../../src/ui/Tutorial")
local WorldShopLogic = require("../../src/ui/WorldShopLogic")

-- Row geometry constants only (Panels/* build Instances in .new, never at load).
local GuidePanel = { TIP_H = 44 }
-- Panels/Rebirth's sizes and copy (LayoutAssert.spec checks this copy against the module).
local RebirthPanel = {
	ROWS = { sub = { y = 0, h = 18 }, gap = 8, gets = 20 },
	CARD = {
		pad = 12,
		labelSize = 14,
		labelH = 18,
		amountSize = 28,
		amountH = 34,
		haveH = 18,
		textGap = 10,
		nameSize = 19,
		nameH = 24,
		stateSize = 15,
		stateH = 20,
		descSize = 14,
	},
	TEXT = {
		subSize = 14,
		gainSize = 22,
		gainH = 26,
		gainLabelSize = 14,
		gainLabelH = 18,
		keeperSize = 15,
		statusSize = 18,
		buttonSize = 22,
	},
	COPY = { keeper = "✅ Keeps your other slimes", button = "Hold to rebirth" },
	SLIME_IMAGE = 52,
}
local ShopPanel = { BADGE = 48, BUY_W = 110, DESC_H = 34 }
-- Panels/WorldShop: the buy column (WorldShop.BUY_W); tags and text at the minimum.
local WorldShopPanel = { BUY_W = 170, TAG_H = 18 }

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

-- The copied panel numbers, for the spec that checks them against the real panels.
LayoutAssert.REBIRTH = RebirthPanel

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

-- Every phone-classified gate size: landscape 844x390 / 844x332 and portrait 390x844 (and under the top bar,
-- 390x786). Layout.screen sets `phone` for these; 1024x768 and wider are not phones.
LayoutAssert.PHONE_VIEWPORTS = table.freeze({
	table.freeze({ name = "844x390", w = 844, h = 390 }),
	table.freeze({ name = "844x332", w = 844, h = 332 }),
	table.freeze({ name = "390x844", w = 390, h = 844 }),
	table.freeze({ name = "390x786", w = 390, h = 786 }),
})

local EPS = 1e-6

local function fmt(r: Rect): string
	return string.format("{x=%.1f y=%.1f w=%.1f h=%.1f}", r.x, r.y, r.w, r.h)
end
LayoutAssert.fmt = fmt

-- Every target viewport (default VIEWPORTS).
function LayoutAssert.screens(
	viewports: { { name: string, w: number, h: number } }?
): { { label: string, screen: Layout.Screen } }
	local out = {}
	for _, vp in viewports or LayoutAssert.VIEWPORTS do
		table.insert(out, { label = vp.name, screen = Layout.screen(vp.w, vp.h) })
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
	lockDuration = Config.LOCK_MAX_REMAINING,
	lockUntil = 100 + Config.LOCK_MAX_REMAINING / 2,
	slimes = {},
	daily = { available = true, streak = Config.DAILY_STREAK_CAP or 7, amount = 987.6e12 },
})

-- Bottom-left cluster texts at their worst (Hud builds the same label boxes via Layout.moneyTextBox): the
-- coin plate's amount and the income / rebirths chips.
function LayoutAssert.moneyTexts(screen: Layout.Screen): { TextDesc }
	local m = screen.money
	local s = LayoutAssert.BIG_STATE
	local compact, tight = screen.compact, screen.tight
	local out: { TextDesc } = {}
	local _, cashW = Layout.moneyTextBox(m.cash, "cash", compact, tight)
	table.insert(out, {
		name = "Money amount",
		text = Format.formatCash(s.cash),
		size = if tight
			then Layout.MONEY_TIGHT.amountSize
			elseif compact then Layout.MONEY.camountSize
			else Layout.MONEY.amountSize,
		bold = true,
		w = cashW,
		h = m.cash.h,
	})
	local chip = if tight
		then Layout.MONEY_TIGHT.chipSize
		elseif compact then Layout.MONEY.cchipSize
		else Layout.MONEY.chipSize
	local _, incomeW = Layout.moneyTextBox(m.income, "income", compact, tight)
	table.insert(out, {
		name = "Income chip",
		text = Format.formatRate(s.incomePerSec),
		size = chip,
		bold = true,
		w = incomeW,
		h = m.income.h,
	})
	local _, rebirthW = Layout.moneyTextBox(m.rebirths, "rebirths", compact, tight)
	table.insert(out, {
		name = "Rebirths chip",
		text = tostring(s.rebirths),
		size = Layout.moneyRebirth(compact, tight).countSize,
		bold = true,
		w = rebirthW,
		h = m.rebirths.h,
	})
	-- the "xN" badge on the chip
	table.insert(out, {
		name = "Rebirths badge",
		text = Format.formatMultiplier(s.rebirthMultiplier),
		size = Layout.moneyRebirth(compact, tight).badgeSize,
		bold = true,
		w = Layout.moneyBadgeWidth(m.rebirths.h) - 4,
		h = math.round(m.rebirths.h * 0.72),
	})
	return out
end

-- Bottom-right timer pills at their worst: the longest timer ("1:02:05"), the featured Secret's week countdown
-- ("6d 23h"), a 3-digit friend bonus. Each text fits its pill (Layout.statusPillWidth, the label itself).
function LayoutAssert.statusTexts(screen: Layout.Screen): { TextDesc }
	local out: { TextDesc } = {}
	local sm = Layout.statusMetrics(screen.compact, screen.tight)
	for _, text in { "1:02:05", "6d 23h", "23h 59m", "+100%", "Now" } do
		table.insert(out, {
			name = `Status pill {text}`,
			text = text,
			size = sm.textSize,
			bold = true,
			w = Layout.statusPillWidth(text, screen.compact, screen.tight),
			h = sm.pill,
		})
	end
	return out
end

-- The status tooltip cards (B8) for every kind of slot at its longest: name, effect, time left. Each is
-- [title, body, time] as HudClusters.tooltip words them, with the live timer at its widest.
function LayoutAssert.tooltipCards(): { { title: string, body: string, time: string } }
	local now = 1000
	local cards = {}
	local slots: { HudClusters.Slot? } = {
		HudClusters.rain({ active = true, endsAt = now + 3725, nextAt = nil }, now),
		HudClusters.rain({ active = false, endsAt = nil, nextAt = now + 59 }, now),
		HudClusters.event(
			{ name = "Admin_luck", label = "Luck Event", luck = 3, endsAt = now + 1800, icon = "🍀" },
			now,
			true
		),
		HudClusters.event({ name = "Dusk", label = "Golden Dusk", luck = 2, endsAt = nil }, now, true),
		HudClusters.friend({ count = 20, bonus = 1 }, true),
		HudClusters.secret({ id = "kitsune", name = "Kitsune", endsAt = now + 6 * 86400 + 23 * 3600 }, now),
	}
	for _, slot in slots do
		if slot then
			table.insert(cards, HudClusters.tooltip(slot))
		end
	end
	return cards
end

-- Nav tile labels (the icon is a picture): the label under the tile in the button's width.
function LayoutAssert.navTexts(screen: Layout.Screen): { TextDesc }
	local out: { TextDesc } = {}
	local N = Layout.NAV
	for i, entry in Nav.ENTRIES do
		local b = screen.navButtons[i]
		table.insert(out, {
			name = `Nav {entry.key}`,
			text = entry.label,
			size = if screen.compact then N.clabelSize else N.labelSize,
			bold = true,
			w = b.w,
			h = if screen.compact then N.clabel else N.label,
		})
	end
	return out
end

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
	-- Mirrors DailyPopup.ROWS / TILE / CHIP_SHARE inside the shared panel frame.
	local card = Layout.rect(0, 0, screen.daily.w, screen.daily.h)
	local bodyW = Layout.panelBody(card).w
	local gap, lastWeight, chipShare = 6, 1.6, 0.58
	local unit = bodyW / (6 + lastWeight)
	local tileW, lastW = unit - gap, unit * lastWeight - gap
	local big = Format.formatCash(987.6e12)
	return {
		{ name = "Daily tile today", text = "Day 6", size = 12, bold = true, w = tileW, h = 17 },
		{ name = "Daily tile last", text = "Day 7", size = 14, bold = true, w = lastW, h = 17 },
		{ name = "Daily tile amount", text = big, size = 8, bold = true, w = tileW - 4, h = 16 },
		{ name = "Daily tile amount (full size)", text = "$3.5K", size = 13, bold = true, w = tileW - 4, h = 16 },
		{
			name = "Daily title",
			text = "Daily reward",
			size = Layout.PANEL_CHROME.titleSize,
			bold = true,
			w = Layout.panelTitle(card).w,
			h = Layout.PANEL_CHROME.close,
		},
		{ name = "Daily streak", text = "Streak: 77 days", size = 15, w = bodyW * (1 - chipShare) - gap, h = 26 },
		{
			name = "Daily streak day",
			text = "Day 7 of your streak",
			size = 15,
			w = bodyW * (1 - chipShare) - gap,
			h = 26,
		},
		{
			name = "Daily tomorrow chip",
			text = `Come back tomorrow for {big}`,
			size = 8,
			bold = true,
			w = bodyW * chipShare - 20,
			h = 26,
		},
		{ name = "Daily amount", text = `+{big}`, size = 40, bold = true, w = bodyW, h = 46 },
		{ name = "Daily claim", text = "Claimed", size = 22, bold = true, w = bodyW, h = Layout.BUTTON },
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
	}
end

type RowText = {
	id: string,
	name: string,
	levelText: string?,
	description: string,
	buttonText: string,
	nameSize: number?,
}

local function rowTexts(prefix: string, rows: { RowText }, textW: number, buyW: number, out: { TextDesc })
	for _, view in rows do
		table.insert(out, {
			name = `{prefix} {view.id} name`,
			text = view.name,
			size = view.nameSize or 17,
			bold = true,
			w = textW,
			h = 22,
		})
		if view.levelText then
			local chip =
				{ name = `{prefix} {view.id} level`, text = view.levelText, size = Layout.MIN_TEXT, bold = true }
			chip.w, chip.h = ShopPanel.BADGE + 8, WorldShopPanel.TAG_H
			table.insert(out, chip :: any)
		end
		table.insert(out, {
			name = `{prefix} {view.id} desc`,
			text = view.description,
			size = Layout.MIN_TEXT,
			w = textW,
			h = ShopPanel.DESC_H,
			wrapped = true,
		})
		table.insert(out, {
			name = `{prefix} {view.id} buy`,
			text = view.buttonText,
			size = 16,
			bold = true,
			w = buyW,
			h = Layout.BUTTON,
		})
	end
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
	local rows: { RowText } = {}
	for _, view in views do
		table.insert(rows, {
			id = view.item.id,
			name = view.item.name,
			levelText = view.levelText,
			description = view.description,
			buttonText = view.buttonText,
		})
	end
	rowTexts("Shop", rows, textW, ShopPanel.BUY_W, out)
	return out
end

-- World shop rows (Panels/WorldShop): the same row geometry, worst-case numbers, every row of both shops.
function LayoutAssert.worldShopTexts(panel: Rect): { TextDesc }
	local textW = panel.w - Layout.PANEL_CHROME.pad * 2 - 10 - (8 + ShopPanel.BADGE + 10) - (WorldShopPanel.BUY_W + 16)
	local out: { TextDesc } = {}
	local upgrades = {}
	for _, u in Config.UPGRADES do
		table.insert(upgrades, {
			id = u.id,
			name = u.name,
			text = u.text,
			level = 9,
			maxLevel = 10,
			price = 987.6e12,
			unlocked = false,
			requires = 50,
		})
	end
	local items = {}
	for _, c in Config.CONSUMABLES do
		table.insert(
			items,
			{ id = c.id, name = c.name, icon = c.icon, text = c.text, price = 987.6e12, left = 3, max = 3 }
		)
	end
	local pvpOwned = {}
	local state = {
		cash = 0,
		lockCost = 987.6e12,
		lockDuration = 310,
		shop = { LockUpgrade = { price = 987.6e12, level = 4, maxLevel = 5 }, SpeedCoil = { price = 987.6e12 } },
		upgrades = upgrades,
		consumables = { slot = 1, restockAt = 0, items = items },
		pvp = { rank = 0, owned = pvpOwned, best = {}, cooldowns = {} },
		slimes = {},
	}
	local actions = Remotes.ACTIONS
	local features = table.clone(Config.FEATURES)
	for _, flag in { "Consumables", "PvP" } do
		(features :: any)[flag] = true
	end
	for _, shopId in Shops.ORDER do
		local rows: { RowText } = {}
		for _, row in WorldShopLogic.rows(shopId, state, actions, features, Config) do
			local text: any = table.clone(row)
			text.nameSize = WorldShopLogic.nameSize(row.name)
			table.insert(rows, text)
		end
		rowTexts(`World {shopId}`, rows, textW, WorldShopPanel.BUY_W, out)
	end
	return out
end

-- Rebirth card texts (Panels/Rebirth), worst-case numbers: body = card - 24. Two cards side by side, or
-- with several slimes a full-width cash card over half-width slime cards.
function LayoutAssert.rebirthTexts(panel: Rect): { TextDesc }
	local w = panel.w - Layout.PANEL_CHROME.pad * 2
	local c = RebirthPanel.CARD
	local t = RebirthPanel.TEXT
	local cardW = w / 2 - RebirthPanel.ROWS.gap / 2
	local inner = cardW - c.pad * 2
	local textW = cardW - (c.pad + RebirthPanel.SLIME_IMAGE + c.textGap) - c.pad
	local title = Layout.panelTitle(panel)
	return {
		{
			name = "Rebirth title",
			text = "Rebirth 50", -- the next rebirth's number, Config.MAX_REBIRTHS at most
			size = Layout.PANEL_CHROME.titleSize,
			bold = true,
			w = title.w,
			h = title.h,
		},
		{ name = "Rebirth sub", text = "You need all four:", size = t.subSize, w = w, h = RebirthPanel.ROWS.sub.h },
		{ name = "Rebirth slime label", text = "This slime", size = c.labelSize, w = textW, h = c.labelH },
		{ name = "Rebirth cost", text = "$987.6Qa", size = c.amountSize, bold = true, w = inner, h = c.amountH },
		{ name = "Rebirth have", text = "You have $987.6Qa", size = c.descSize, w = inner, h = c.haveH },
		{ name = "Rebirth slime name", text = "Dragon King", size = c.nameSize, bold = true, w = textW, h = c.nameH },
		{ name = "Rebirth slime state", text = "✅ Owned", size = c.stateSize, bold = true, w = textW, h = c.stateH },
		{ name = "Rebirth income", text = "x99.5", size = t.gainSize, bold = true, w = cardW, h = t.gainH },
		{ name = "Rebirth lock", text = "lock time", size = t.gainLabelSize, w = cardW, h = t.gainLabelH },
		{
			name = "Rebirth keeper",
			text = RebirthPanel.COPY.keeper,
			size = t.keeperSize,
			bold = true,
			w = w * 0.6,
			h = RebirthPanel.ROWS.gets,
		},
		{
			name = "Rebirth reason",
			text = "Need $987.6Qa and a Dragon King",
			size = t.statusSize,
			bold = true,
			w = w,
			h = Layout.BUTTON,
		},
		{
			name = "Rebirth button",
			text = RebirthPanel.COPY.button,
			size = t.buttonSize,
			bold = true,
			w = w,
			h = Layout.BUTTON,
		},
	}
end

-- Guide tips (Panels/Guide): one line each, body = card - 24, row - 8 - padding 12.
function LayoutAssert.guideTexts(panel: Rect): { TextDesc }
	local w = panel.w - Layout.PANEL_CHROME.pad * 2 - 8 - 12
	local out: { TextDesc } = {}
	local tips = { "Thief has your slime: use your bat!", "Free pad: bring home another slime" }
	for _, tip in GuideTips.GENERAL do
		table.insert(tips, tip.text)
	end
	for i, text in tips do
		table.insert(out, { name = `Guide tip {i}`, text = `🚨  {text}`, size = 15, w = w, h = GuidePanel.TIP_H })
	end
	return out
end

-- Welcome-back card (Panels/Welcome): the away line, the gold headline and each card's name /
-- description / amount / count at their longest. Mirrors Welcome.ROWS / CARD.
function LayoutAssert.welcomeTexts(panel: Rect): { TextDesc }
	local bodyW = Layout.panelBody(panel).w
	local textX, right, sideGap, amountW, countW = 62, 12, 8, 110, 84
	local plainW = bodyW - textX - right
	local big = Format.formatCash(999.99e15)
	return {
		{ name = "Welcome away", text = "You were away for 99d 23h and earned", size = 16, w = bodyW, h = 22 },
		{ name = "Welcome headline", text = `+{big}`, size = 44, bold = true, w = bodyW, h = 52 },
		{ name = "Welcome growth", text = "12 slimes grew", size = 18, bold = true, w = plainW, h = 22 },
		{ name = "Welcome growth desc", text = "on your pads while you were gone", size = 14, w = plainW, h = 18 },
		{ name = "Welcome streak", text = "Daily streak: 77 days", size = 18, bold = true, w = plainW, h = 22 },
		{
			name = "Welcome daily",
			text = "Daily reward ready",
			size = 18,
			bold = true,
			w = plainW - amountW - sideGap,
			h = 22,
		},
		{ name = "Welcome daily amount", text = big, size = 20, bold = true, w = amountW, h = 24 },
		{
			name = "Welcome goal",
			text = "Lock your base 1000 times",
			size = 18,
			bold = true,
			w = plainW - countW - sideGap,
			h = 22,
		},
		{ name = "Welcome goal count", text = "999/1000", size = 15, bold = true, w = countW, h = 22 },
	}
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
	Merge = "Merge vat",
	Shop = "Shop",
	Rebirth = "Rebirth", -- built with this; the open card shows "Rebirth 50" at most (rebirthTexts)
	Goals = "Goals",
	Dex = "SlimeDex",
	Leaders = "Top earners",
	Codes = "Codes",
	Sound = "Sound",
	Guide = "Guide",
	Welcome = "Welcome back",
})

-- Every menu key the UI opens: Nav.ENTRIES order, then "Guide", "Welcome".
function LayoutAssert.menuKeys(): { string }
	local keys = {}
	for _, entry in Nav.ENTRIES do
		table.insert(keys, entry.key)
	end
	table.insert(keys, "WorldShop")
	table.insert(keys, "Inventory")
	table.insert(keys, "Sound")
	table.insert(keys, "Guide")
	table.insert(keys, "Welcome")
	return keys
end

-- The full-window menu backdrop (screen.panel): right of the nav (+ GAP; phones: from the
-- left margin, the nav is hidden while a menu is open), from the top margin, to MARGIN from
-- the right edge and down to the bottom inset.
function LayoutAssert.expectedPanel(screen: Layout.Screen): Rect
	local x = if screen.compact then Layout.MARGIN else screen.nav.x + screen.nav.w + Layout.GAP
	local y = Layout.TOP
	return Layout.rect(x, y, screen.width - Layout.MARGIN - x, screen.height - screen.bottomInset - y)
end

-- Smallest usable menu body (design px): a couple of list rows.
LayoutAssert.MIN_BODY = table.freeze({ w = 240, h = 120 })

-- v28 menu rules: the dimmed backdrop is the full-window rect; every menu
-- card (Nav keys + Guide) is MENU_WIDTH (or the backdrop width), centred
-- in it horizontally, MENU_HEIGHTS tall (or the backdrop height), inside
-- it, clear of the nav, with a usable body and a close X that is
-- MIN_TOUCH, inside the card, top-right, and never under a
-- bottom card or the banners (those draw above menus).
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
		if not screen.compact then
			check.noOverlap(name, r, "Nav", screen.nav)
		end
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
				{ "Carry", screen.carry },
				{ "Tutorial", screen.tutorial },
				{ "TutorialCarrying", screen.tutorialCarrying },
			}
		do
			check.noOverlap(closeName, close, other[1] :: string, other[2] :: Rect)
		end
		-- Banners draw above menus too. They grow down from their top as alerts
		-- stack, so their whole column must miss the X.
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
		-- Nav hints stay up while a menu is open and draw above it (phones hide the nav, and its hint, then).
		for id, hint in Hint.STEPS do
			local place = Hint.place(screen, { id = id, text = hint.text, target = hint.target })
			if place and not screen.compact then
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
		{ name = "Banners", rect = Layout.rect(b.x, b.y, b.w, screen.height - b.y) },
		{ name = "Money", rect = screen.money.rect },
		{ name = "Status", rect = screen.status.rect },
		{ name = "Carry", rect = screen.carry },
		{ name = "Tutorial", rect = screen.tutorial },
		{ name = "TutorialCarrying", rect = screen.tutorialCarrying },
	}
	if not screen.compact then -- phones hide the nav while a menu is open
		table.insert(out, { name = "Panel", rect = screen.panel })
	end
	for id, hint in Hint.STEPS do
		local place = Hint.place(screen, { id = id, text = hint.text, target = hint.target })
		if place then
			table.insert(out, { name = `Hint.{id} bubble`, rect = place.bubble })
		end
	end
	return out
end

-- v27 gate N1: every nav button (Nav.ENTRIES: a tile and its label) is fully on screen
-- and nothing above overlaps it, so a tap on it reaches it.
function LayoutAssert.navReachable(check: Checker)
	local screen = check.screen
	if #screen.navButtons ~= #Nav.ENTRIES then
		check.fail(`nav has {#screen.navButtons} buttons (want {#Nav.ENTRIES})`)
	end
	local overlays = LayoutAssert.overlays(screen)
	for i, b in screen.navButtons do
		local name = `Nav.{Nav.ENTRIES[i].key}`
		check.onScreen(name, b)
		check.inside(name, b, "Nav", screen.nav)
		check.touch(name, b)
		for _, o in overlays do
			check.noOverlap(name, b, o.name, o.rect)
		end
	end
end

-- Worst-case badge texts sit fully inside their nav button, on its tile corner (not on the label).
function LayoutAssert.navBadges(check: Checker)
	for i, entry in Nav.ENTRIES do
		local b = check.screen.navButtons[i]
		local tile = Layout.navTile(check.screen.compact, b)
		local label = Layout.rect(b.x, tile.y + tile.h, b.w, b.h - tile.h)
		for _, text in { "!" } do
			local name = `Nav.{entry.key} badge "{text}"`
			local r = Layout.navBadge(b, text)
			check.inside(name, r, `Nav.{entry.key}`, b)
			check.noOverlap(name, r, `Nav.{entry.key} label`, label)
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
-- viewport on both axes; nav tiles (square), nav buttons, the status slots and the
-- menu close X keep their design proportions.
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
	local cellW, cellH = Layout.navCellSize(screen.compact)
	for i, b in screen.navButtons do
		local name = `Nav.{Nav.ENTRIES[i].key}`
		check.aspect(name, b, cellW, cellH)
		local tile = Layout.navTile(screen.compact, b)
		check.aspect(`{name}.Tile`, tile, 1, 1)
	end
	for i, slot in screen.status.slots do
		check.aspect(
			`Status.slot{i}`,
			slot,
			Layout.statusSlotWidth(screen.compact, screen.tight),
			Layout.statusHeight(screen.compact, screen.tight)
		)
	end
	local close = Layout.panelClose(Layout.panelFor(screen, "Shop"))
	check.aspect("Panel.Close", close, Layout.PANEL_CHROME.close, Layout.PANEL_CHROME.close)
end

-- Every v18 rule for one screen; returns the checker (use `report()`).
function LayoutAssert.clusterChecks(check: Checker)
	local screen = check.screen
	local m = Layout.MARGIN
	local boxes: { { string | Rect } } = {
		{ "Money", screen.money.rect },
		{ "Money.cash", screen.money.cash },
		{ "Money.income", screen.money.income },
		{ "Money.rebirths", screen.money.rebirths },
		{ "Status", screen.status.rect },
	}
	for i, slot in screen.status.slots do
		table.insert(boxes, { `Status.slot{i}`, slot })
		check.inside(`Status.slot{i}`, slot, "Status", screen.status.rect)
	end
	local rise = Layout.rowRise(screen)
	local floor = screen.height - screen.bottomInset - rise
	for _, box in boxes do
		local name, r = box[1] :: string, box[2] :: Rect
		check.onScreen(name, r, m)
		if r.y + r.h > floor + EPS then
			check.fail(`{name} {fmt(r)} reaches into the touch-controls strip (floor {floor})`)
		end
	end
	check.inside("Money.cash", screen.money.cash, "Money", screen.money.rect)
	check.inside("Money.income", screen.money.income, "Money", screen.money.rect)
	check.inside("Money.rebirths", screen.money.rebirths, "Money", screen.money.rect)
	-- The chips are tucked up under the pill's bottom edge: they may enter the coin + pill zone, but by no more
	-- than the overlap plus the coin's protrusion, and never past its middle.
	for _, chipBox in { { "Money.income", screen.money.income }, { "Money.rebirths", screen.money.rebirths } } do
		local name, r = chipBox[1] :: string, chipBox[2] :: Rect
		local cash = screen.money.cash
		local intrusion = cash.y + cash.h - r.y
		local k = Layout.moneyMetrics(screen.compact, screen.tight)
		if intrusion > k.overlap + k.pad + EPS or intrusion < 0 or r.y < cash.y + cash.h / 2 then
			check.fail(
				`{name} {fmt(r)} tucks {intrusion} px into the pill zone {fmt(cash)} (want 0 to {k.overlap + k.pad})`
			)
		end
	end
	check.noOverlap("Money.income", screen.money.income, "Money.rebirths", screen.money.rebirths)
	check.noOverlap("Money", screen.money.rect, "Status", screen.status.rect)
	-- The events row: its slots side by side (2 x 2 on phones), clear of the hotbar; off phones it stands
	-- STATUS.raise above the bottom line (0: on it, level with the money block and hotbar).
	for i, a in screen.status.slots do
		for j = i + 1, #screen.status.slots do
			check.noOverlap(`Status.slot{i}`, a, `Status.slot{j}`, screen.status.slots[j])
		end
	end
	check.noOverlap("Status", screen.status.rect, "Hotbar.bar", screen.hotbar)
	if not screen.phone and screen.status.rect.y + screen.status.rect.h > floor - Layout.STATUS.raise + EPS then
		check.fail(
			`Status {fmt(screen.status.rect)} is not raised {Layout.STATUS.raise} px above the bottom line {floor}`
		)
	end
	for _, cluster in { { "Money", screen.money.rect }, { "Status", screen.status.rect } } do
		local name, r = cluster[1] :: string, cluster[2] :: Rect
		for _, other in
			{
				{ "Nav", screen.nav },
				{ "Carry", screen.carry },
				{ "Tutorial", screen.tutorial },
				{ "TutorialCarrying", screen.tutorialCarrying },
				{ "Sound", screen.sound },
				{ "Banners", screen.banners },
			}
		do
			check.noOverlap(name, r, other[1] :: string, other[2] :: Rect)
		end
	end
	-- B8: a tooltip over any status slot stays on screen (MARGIN in), clear of the slot it explains.
	for i, slot in screen.status.slots do
		for k, card in LayoutAssert.tooltipCards() do
			local w, h = Layout.tooltipBox(screen.compact, card.title, card.body, card.time)
			local r = Layout.tooltipRect(screen, slot, w, h)
			local name = `Tooltip{k}@slot{i}`
			check.onScreen(name, r, m)
			check.noOverlap(name, r, `Status.slot{i}`, slot)
		end
	end
end

-- S3 hotbar: its zone and the fullest bar (every slot + bag) are on screen, touch-sized on phones, inside
-- the zone, clear of every other box and of the thumbstick / jump zones. The carry cards are the exception:
-- the server unequips tools while carrying, so the bar is hidden then (Inventory) and they may use its place.
function LayoutAssert.hotbarChecks(check: Checker)
	local screen = check.screen
	local zone = screen.hotbar
	check.onScreen("Hotbar.zone", zone, Layout.MARGIN)
	local bar =
		InventoryLayout.bar(zone, InventoryLayout.MAX_SLOTS, screen.compact, Layout.MIN_TOUCH_DESIGN, screen.tight)
	if bar.shown < 3 then
		check.fail(`Hotbar holds only {bar.shown} item slots in {fmt(zone)} (want at least 3)`)
	end
	check.inside("Hotbar.bar", bar.rect, "Hotbar.zone", zone)
	-- Bottom-centre: off a narrow phone the zone is centred on the screen, between the money and status clusters.
	if zone.w < screen.width - Layout.MARGIN * 2 and math.abs(zone.x + zone.w / 2 - screen.width / 2) > 1 then
		check.fail(`Hotbar.zone {fmt(zone)} is not centred on the {screen.width} px screen`)
	end
	local cells = { { "Hotbar.bag", bar.bag } }
	for i, slot in bar.slots do
		table.insert(cells, { `Hotbar.slot{i}`, slot })
	end
	local thumbSide = 120
	local thumbTop = screen.height - Layout.TOUCH_CONTROLS_HEIGHT - thumbSide
	local zones = {
		{ "JumpZone", Layout.rect(screen.width - thumbSide, thumbTop, thumbSide, screen.height - thumbTop) },
		{ "ThumbstickZone", Layout.rect(0, thumbTop, thumbSide, screen.height - thumbTop) },
	}
	for _, cell in cells do
		local name, r = cell[1] :: string, cell[2] :: Rect
		check.inside(name, r, "Hotbar.bar", bar.rect)
		-- Tight (390 px portrait): the shared bottom row leaves only TIGHT.slot design px per slot, below MIN_TOUCH.
		if screen.compact and not screen.tight then
			check.touch(name, r)
		end
	end
	for _, other in
		{
			{ "Nav", screen.nav },
			{ "Money", screen.money.rect },
			{ "Status", screen.status.rect },
			{ "Tutorial", screen.tutorial },
			{ "Sound", screen.sound },
			{ "Banners", screen.banners },
			zones[1],
			zones[2],
		}
	do
		check.noOverlap("Hotbar.bar", bar.rect, other[1] :: string, other[2] :: Rect)
	end
	if screen.phone then
		LayoutAssert.phoneRowChecks(check, bar.rect)
	end
end

-- Phones (Layout.phone: landscape and portrait): the nav grid sits at the very top (the top margin) on landscape
-- phones and low on the left, above the money block, on portrait ones (clear of Roblox's chat window); the money
-- block, the hotbar and the events row share one bottom row: bottom edges within BOTTOM_ALIGN px, money left of
-- the hotbar left of the events, none overlapping.
LayoutAssert.BOTTOM_ALIGN = 2

function LayoutAssert.phoneRowChecks(check: Checker, bar: Rect)
	local screen = check.screen
	local money, status = screen.money.rect, screen.status.rect
	if screen.viewportW > screen.viewportH then
		if math.abs(screen.nav.y - Layout.TOP) > EPS then
			check.fail(`Nav {fmt(screen.nav)} is not at the top (y should be {Layout.TOP})`)
		end
	elseif screen.nav.y < Layout.TOP - EPS or screen.nav.y + screen.nav.h > money.y then
		check.fail(`Nav {fmt(screen.nav)} is not between the top margin and the money block`)
	end
	local bottoms = { Money = money.y + money.h, Hotbar = bar.y + bar.h, Status = status.y + status.h }
	for name, bottom in bottoms do
		if math.abs(bottom - bottoms.Hotbar) > LayoutAssert.BOTTOM_ALIGN then
			check.fail(
				`{name} bottom {bottom} is not aligned with the hotbar bottom {bottoms.Hotbar} (within {LayoutAssert.BOTTOM_ALIGN} px)`
			)
		end
	end
	-- Landscape phone: the row hugs the bottom edge. The gap between its bottom and the screen bottom, in
	-- screen px, is at most Layout.LANDSCAPE_INSET_MAX (16) and the row is not lifted off it (no rise).
	if screen.width > screen.height then
		local gapPx = (screen.height - bottoms.Hotbar) * screen.scale
		if gapPx > Layout.LANDSCAPE_INSET_MAX + EPS or gapPx < 0 then
			check.fail(`landscape bottom inset {gapPx} px is not within 0 to {Layout.LANDSCAPE_INSET_MAX} px`)
		end
		if screen.bottomInset * screen.scale > Layout.LANDSCAPE_INSET_MAX + EPS then
			check.fail(
				`landscape bottomInset {screen.bottomInset * screen.scale} px is over {Layout.LANDSCAPE_INSET_MAX} px`
			)
		end
	end
	if not (money.x + money.w <= bar.x + EPS and bar.x + bar.w <= status.x + EPS) then
		check.fail(`bottom row is not money {fmt(money)} | hotbar {fmt(bar)} | events {fmt(status)} left to right`)
	end
	check.noOverlap("Money", money, "Hotbar.bar", bar)
	check.noOverlap("Hotbar.bar", bar, "Status", status)
	check.noOverlap("Money", money, "Status", status)
	check.noOverlap("Nav", screen.nav, "Money", money)
end

function LayoutAssert.standard(label: string, screen: Layout.Screen): Checker
	local check = LayoutAssert.new(label, screen)
	local m = Layout.MARGIN

	-- Nav: on screen, every button (tile + label) tappable and inside it, 2 columns unless the screen is short.
	check.onScreen("Nav", screen.nav, m)
	if #screen.navButtons ~= #Nav.ENTRIES then
		check.fail(`nav has {#screen.navButtons} buttons (want {#Nav.ENTRIES})`)
	end
	if not screen.short and screen.navColumns ~= Layout.NAV.columns then
		check.fail(`nav has {screen.navColumns} columns (want {Layout.NAV.columns})`)
	end
	for i, b in screen.navButtons do
		check.touch(`NavButton{i}`, b)
		check.touch(`NavButton{i}.Tile`, Layout.navTile(screen.compact, b))
		check.inside(`NavButton{i}`, b, "Nav", screen.nav)
	end
	if screen.nav.w ~= Layout.navWidth(screen.compact, screen.navColumns) then
		check.fail(`nav width {screen.nav.w} ~= Layout.navWidth({screen.compact}, {screen.navColumns})`)
	end
	for i = 1, #screen.navButtons do
		for j = i + 1, #screen.navButtons do
			check.noOverlap(`NavButton{i}`, screen.navButtons[i], `NavButton{j}`, screen.navButtons[j])
		end
	end

	-- H1 bottom clusters: on screen, on the bottom inset line (compact: also above the touch-controls rise),
	-- clear of the nav, bottom cards and each other; every status slot inside its cluster; a status
	-- tooltip stays on screen.
	LayoutAssert.clusterChecks(check)
	LayoutAssert.hotbarChecks(check)

	-- Menus: full-window backdrop, content-sized cards, close X tappable.
	check.onScreen("column", screen.column, m)
	LayoutAssert.panelChecks(check)

	-- Bottom cards: on screen, above the touch-control inset, clear of the nav.
	local floor = screen.height - screen.bottomInset
	for _, card in
		{
			{ "Carry", screen.carry },
			{ "Tutorial", screen.tutorial },
			{ "TutorialCarrying", screen.tutorialCarrying },
		}
	do
		local name, r = card[1] :: string, card[2] :: Rect
		-- Short phones: the tutorial card hugs the bottom edge (Layout.TUTORIAL_SHORT_MARGIN).
		local edge = if string.sub(name, 1, 8) == "Tutorial"
				and screen.short
				and screen.viewportH < Layout.TUTORIAL_SHORT_HEIGHT
			then Layout.TUTORIAL_SHORT_MARGIN / screen.scale
			else nil
		check.onScreen(name, r, edge or m)
		if r.y + r.h > (if edge then screen.height - edge else floor) + EPS then
			check.fail(`{name} {fmt(r)} reaches into the bottom inset (floor {floor})`)
		end
		check.noOverlap(name, r, "Nav", screen.nav)
	end
	check.noOverlap("TutorialCarrying", screen.tutorialCarrying, "Carry", screen.carry)

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
			{ "Nav", screen.nav },
			{ "Carry", screen.carry },
			{ "Tutorial", screen.tutorial },
			{ "TutorialCarrying", screen.tutorialCarrying },
			{ "Banners", screen.banners },
		}
	do
		check.noOverlap("Sound", screen.sound, other[1] :: string, other[2] :: Rect)
	end

	-- Overlays.
	check.onScreen("Daily", screen.daily, m)
	check.onScreen("Banners", screen.banners, m)

	-- Hints for every step that points at a button.
	for id, hint in Hint.STEPS do
		local view = { id = id, text = hint.text, target = hint.target }
		local place = Hint.place(screen, view)
		if place == nil then
			check.fail(`hint {id} has no target`)
		else
			check.onScreen(`Hint.{id} bubble`, place.bubble, m)
			check.onScreen(`Hint.{id} ring`, place.ring)
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

	-- Text.
	local panelScreen = screen
	for _, list in
		{
			LayoutAssert.moneyTexts(screen),
			LayoutAssert.statusTexts(screen),
			LayoutAssert.navTexts(screen),
			LayoutAssert.tutorialTexts(screen),
			LayoutAssert.dailyTexts(screen),
			LayoutAssert.carryTexts(screen),
			LayoutAssert.shopTexts(Layout.panelFor(panelScreen, "Shop")),
			LayoutAssert.worldShopTexts(Layout.panelFor(panelScreen, "WorldShop")),
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
