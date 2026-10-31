--!strict
-- v18 mobile-first layout at 390x844 and 1920x1080, on Layout.screen() rects via
-- tests/ui/LayoutAssert.luau. Oct 18: no top bar / toasts, a 2-column nav tile grid, bigger bottom clusters.
local fs = require("@lune/fs")

local Config = require("../../src/shared/Config")
local GuideTips = require("../../src/ui/GuideTips")
local Hint = require("../../src/ui/Hint")
local InventoryLayout = require("../../src/ui/InventoryLayout")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local Nav = require("../../src/ui/Nav")
local ShopCatalog = require("../../src/ui/ShopCatalog")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function read(path: string): string
	return fs.readFile(path)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

describe("LayoutAssert helper", function()
	it("reports off-screen boxes, small buttons, overlaps and overflowing text", function()
		local screen = Layout.screen(390, 844)
		local check = LayoutAssert.new("probe", screen)
		check.onScreen("wide", Layout.rect(0, 0, screen.width + 1, 10))
		check.touch("tiny", Layout.rect(20, 20, 40, 40)) -- 32 screen px at 0.8
		check.noOverlap("a", Layout.rect(0, 0, 10, 10), "b", Layout.rect(5, 5, 10, 10))
		check.text({ name = "long", text = "Slime Rain: 12:34 left", size = 15, bold = true, w = 60, h = 56 })
		check.inside("out", Layout.rect(0, 0, 20, 20), "box", Layout.rect(5, 5, 10, 10))
		expect(#check.problems).toBe(5)
		expect(has(check.report(), "[probe] tiny is 32.0 screen px")).toBe(true)
	end)
	it("accepts wrapped text in a tall box and TextScaled text", function()
		local long = string.rep("word ", 30)
		expect(LayoutAssert.textFits({ name = "w", text = long, size = 14, w = 300, h = 200, wrapped = true })).toBeNil()
		expect(LayoutAssert.textFits({ name = "w", text = long, size = 14, w = 300, h = 20, wrapped = true })).toBeTruthy()
		expect(LayoutAssert.textFits({ name = "s", text = long, size = 40, w = 10, h = 10, scaled = true })).toBeNil()
	end)
	it("covers both viewports", function()
		local labels = {}
		for _, entry in LayoutAssert.screens() do
			table.insert(labels, entry.label)
		end
		expect(table.concat(labels, ", ")).toBe("390x844, 1920x1080")
	end)
end)

describe("v18 layout rules", function()
	for _, entry in LayoutAssert.screens() do
		it(`{entry.label}: on screen, tappable, no overlaps, text fits`, function()
			expect(LayoutAssert.standard(entry.label, entry.screen).report()).toBe("")
		end)
	end
end)

describe("menus at the five gate viewports (v28: full-window backdrop, content-sized cards)", function()
	for _, entry in LayoutAssert.screens(LayoutAssert.GATE_VIEWPORTS) do
		it(
			`{entry.label}: full-window backdrop, centred cards, close X tappable and inside, clear of the nav`,
			function()
				expect(LayoutAssert.fullWindow(entry.label, entry.screen).report()).toBe("")
			end
		)
	end
	it("the checker rejects a side panel and a small / misplaced close button", function()
		local s = Layout.screen(390, 844)
		local side = table.clone(s) :: any
		side.panel = Layout.rect(s.panel.x, s.panel.y + 40, 300, 300)
		local report = LayoutAssert.fullWindow("side", side).report()
		expect(has(report, "is not the full-window rect")).toBe(true)
		local wide = table.clone(s) :: any
		wide.menuW = s.menuW - 40
		expect(has(LayoutAssert.fullWindow("narrow card", wide).report(), "content-sized card")).toBe(true)
		local check = LayoutAssert.new("probe", s)
		check.touch("Close", Layout.rect(0, 0, 40, 40))
		expect(#check.problems).toBe(1)
	end)
	it("measures the titles the panels really show", function()
		for key, title in LayoutAssert.PANEL_TITLES do
			expect(has(read(`src/ui/Panels/{key}.luau`), `Widgets.panel(parent, "{key}Panel", "{title}", `)).toBe(true)
		end
	end)
	it("mirrors the panels' row geometry (WorldShop, Guide)", function()
		local worldShop = UiHarness.ui("Panels/WorldShop")
		local copy = LayoutAssert.WORLD_SHOP
		for _, k in
			{
				"BADGE",
				"BADGE_THIN",
				"BUY_W",
				"DESC_H",
				"DESC_THIN_H",
				"LABEL_H",
				"TAB_H",
				"TAB_GAP",
				"STEP",
				"STEP_GAP",
				"EDGE",
				"GRID_COLS",
				"GRID_GAP",
				"TILE_NAME_H",
			}
		do
			expect(copy[k]).toBe(worldShop[k])
		end
		for k, v in copy.SIZE do
			expect(v).toBe(worldShop.SIZE[k])
		end
		local guide = read("src/ui/Panels/Guide.luau")
		expect(has(guide, "Guide.TIP_H = 44")).toBe(true)
		expect(UiHarness.ui("Panels/Guide").SHOW_TEXT).toBe("📖  Show the tutorial again")
	end)
	it("the Rebirth sizes and copy it measures are the panel's own", function()
		local real = UiHarness.ui("Panels/Rebirth")
		local function same(copy: { [string]: any }, source: { [string]: any }, path: string)
			for k, v in copy do
				if type(v) == "table" then
					same(v, source[k], `{path}.{k}`)
				elseif source[k] ~= v then
					error(`LayoutAssert's {path}.{k} is {v}, Panels/Rebirth has {source[k]}`)
				end
			end
		end
		same(LayoutAssert.REBIRTH, real, "Rebirth")
	end)
	it("the Settings sizes and copy it measures are the panel's own", function()
		local real = UiHarness.ui("Panels/Settings")
		for _, part in { "STYLE", "COPY" } do
			for k, v in LayoutAssert.SETTINGS[part] do
				if real[part][k] ~= v then
					error(`LayoutAssert's Settings.{part}.{k} is {v}, Panels/Settings has {real[part][k]}`)
				end
			end
		end
	end)
	it("every card fits its content at the tallest gate viewport (no scroll on desktop)", function()
		local s = Layout.screen(1920, 1080)
		local chrome = Layout.PANEL_CHROME.header + Layout.PANEL_CHROME.pad
		-- cards are sized by their measured content (init.client: Widgets.contentHeight), capped at the backdrop
		local rebirth = UiHarness.ui("Panels/Rebirth").plan(3, true).height -- the tallest: three slimes and a rank row
		expect(Layout.panelFor(s, "Rebirth", rebirth).h >= chrome + rebirth).toBe(true)
		local guide = UiHarness.ui("Panels/Guide").contentHeight(GuideTips.MAX_TIPS) -- the goal and every slot filled
		expect(Layout.panelFor(s, "Guide", guide).h >= chrome + guide).toBe(true)
		for _, key in LayoutAssert.menuKeys() do
			local r = Layout.panelFor(s, key)
			expect(r.w < s.panel.w and r.h < s.panel.h).toBe(true) -- smaller than the window
		end
	end)
	it("Layout.panelClose is a MIN_TOUCH_DESIGN square in the top-right corner", function()
		local r = Layout.rect(100, 50, 600, 400)
		local close = Layout.panelClose(r)
		expect(close.w).toBe(Layout.MIN_TOUCH_DESIGN)
		expect(close.h).toBe(Layout.MIN_TOUCH_DESIGN)
		expect(close.w * Layout.MIN_SCALE >= Layout.MIN_TOUCH).toBe(true)
		expect(close.x + close.w).toBe(r.x + r.w - Layout.PANEL_CHROME.closeInset)
		expect(close.y).toBe(r.y + Layout.PANEL_CHROME.closeInset)
		local body = Layout.panelBody(r)
		expect(body.y >= close.y + close.h).toBe(true) -- body starts under the X
		expect(Layout.overlaps(Layout.panelTitle(r), close)).toBe(false)
	end)
end)

describe("v18 viewports", function()
	it("phone: compact, a 2-column tile nav, MIN_SCALE, no top bar", function()
		local s = Layout.screen(390, 844)
		expect(s.compact).toBe(true)
		expect(s.short).toBe(false)
		expect(s.navColumns).toBe(2)
		expect(s.scale).toBe(Layout.MIN_SCALE)
		expect(s.bottomInset * s.scale >= Layout.TOUCH_CONTROLS_HEIGHT).toBe(true)
	end)
	it("desktop: a 2-column tile nav, scale 1", function()
		local s = Layout.screen(1920, 1080)
		expect(s.compact).toBe(false)
		expect(s.navColumns).toBe(2)
		expect(s.scale).toBe(1)
		expect(#s.navButtons).toBe(#Nav.ENTRIES)
	end)
	it("desktop: the backdrop fills the window beside the nav, cards are centred in it", function()
		local s = Layout.screen(1920, 1080)
		local back = s.panel
		expect(back.x).toBe(s.nav.x + s.nav.w + Layout.GAP) -- right next to the nav
		expect(back.y).toBe(Layout.TOP)
		expect(back.x + back.w).toBe(s.width - Layout.MARGIN)
		expect(back.y + back.h).toBe(s.height - s.bottomInset)
		for _, entry in Nav.ENTRIES do
			local r = Layout.panelFor(s, entry.key)
			expect(r.w).toBe(Layout.MENU_WIDTH)
			expect(r.h).toBe(Layout.menuHeight(entry.key))
			expect(r.w * r.h < 0.3 * s.width * s.height).toBe(true) -- a card, not the whole screen
		end
	end)
	it("phone menus use the full width (the nav steps aside while a menu is open)", function()
		local s = Layout.screen(390, 844)
		local a = Layout.panelFor(s, "WorldShop")
		expect(a.w).toBe(s.column.w)
		expect(a.x).toBe(Layout.MARGIN)
		expect(s.panel.h > s.column.h).toBe(true) -- the backdrop runs on under the carry card
		expect(Layout.drawsAbove("Carry", "Base") and Layout.drawsAbove("Banners", "Base")).toBe(true)
	end)
	it("hint bubbles sit right of the nav (menu targets)", function()
		for _, entry in LayoutAssert.screens() do
			local s = entry.screen
			for id, hint in Hint.STEPS do
				local place = Hint.place(s, { id = id, text = hint.text, target = hint.target }) :: Hint.Placement
				expect(place.side).toBe("right")
				expect(place.bubble.x >= s.nav.x + s.nav.w).toBe(true)
			end
		end
	end)
	it("the nav is a grid of rounded square tiles, label under them, left to right then down (B5)", function()
		for _, vp in { { 390, 844 }, { 1920, 1080 } } do
			local s = Layout.screen(vp[1], vp[2])
			for i, b in s.navButtons do
				local tile = Layout.navTile(s.compact, b)
				expect(tile.w).toBe(tile.h) -- square
				expect(tile.y).toBe(b.y) -- the tile on top ...
				expect(b.h > tile.h).toBe(true) -- ... the label row under it
				local col = (i - 1) % 2
				expect(b.x).toBe(s.nav.x + col * (b.w + Layout.navGap(s.compact)))
			end
			expect(s.navButtons[2].y).toBe(s.navButtons[1].y) -- row 1: Rebirth, Goals
			expect(s.navButtons[3].y > s.navButtons[2].y).toBe(true) -- row 2: SlimeDex, Codes
			expect(s.navButtons[3].x).toBe(s.navButtons[1].x)
		end
	end)
	it("the bottom clusters are bigger than the H1 sizes (B4) and clear the touch controls", function()
		local desktop, phone = Layout.screen(1920, 1080), Layout.screen(844, 390)
		expect(desktop.money.rect.w >= 240 and desktop.money.cash.h >= 56).toBe(true) -- H1: 200 x 44
		expect(desktop.status.slots[1].w >= 88).toBe(true) -- H1: 54
		expect(phone.money.cash.h > 40 and phone.status.slots[1].w > 54).toBe(true) -- H1 phone: 40, 54
		-- the phone clusters sit TOUCH_RISE above the touch strip, so Roblox's thumbstick and jump button stay clear
		-- (portrait only: a landscape phone hugs the bottom edge, no rise)
		local portrait = Layout.screen(390, 844)
		local rise = math.ceil(Layout.TOUCH_RISE / portrait.scale)
		expect(Layout.rowRise(phone)).toBe(0)
		expect(Layout.rowRise(portrait)).toBe(rise)
		expect(portrait.money.rect.y + portrait.money.rect.h <= portrait.height - portrait.bottomInset - rise).toBe(
			true
		)
		expect(portrait.status.rect.y + portrait.status.rect.h <= portrait.height - portrait.bottomInset - rise).toBe(
			true
		)
	end)
end)

-- Position of a Nav key in Nav.ENTRIES (screen.navButtons follows it).
local function navIndex(key: string): number
	for i, entry in Nav.ENTRIES do
		if entry.key == key then
			return i
		end
	end
	error(`no nav entry {key}`)
end

describe("landscape phone (v27 gate N1)", function()
	for _, vp in LayoutAssert.LANDSCAPE_VIEWPORTS do
		local label = vp.name
		local s = Layout.screen(vp.w, vp.h)
		it(`{label}: every v18 rule`, function()
			expect(LayoutAssert.standard(label, s).report()).toBe("")
		end)
		it(`{label}: every nav button on screen and clear of banners, clusters, cards`, function()
			local check = LayoutAssert.new(label, s)
			LayoutAssert.navReachable(check)
			expect(check.report()).toBe("")
		end)
		it(`{label}: no negative sizes, Dex list keeps a row`, function()
			local check = LayoutAssert.new(label, s)
			LayoutAssert.noNegativeSizes(check)
			expect(check.report()).toBe("")
		end)
	end
	it(
		"844x332 (gate N1 numbers): short, the nav tiles above the money cluster, Dex button on screen, panel most of the window",
		function()
			local s = Layout.screen(844, 332)
			expect(s.phone).toBe(true)
			expect(s.navColumns >= 2).toBe(true)
			expect(s.nav.y + s.nav.h < s.money.rect.y).toBe(true)
			local dex = s.navButtons[navIndex("Dex")]
			expect(dex.y + dex.h <= s.height).toBe(true)
			expect(s.nav.y + s.nav.h <= s.height - s.bottomInset).toBe(true)
			expect(s.panel.w >= Layout.MENU_WIDTH).toBe(true)
			expect(s.panel.h >= 0.5 * s.height).toBe(true)
		end
	)
	for _, vp in LayoutAssert.PHONE_VIEWPORTS do
		it(
			`{vp.name}: nav at the top (landscape) or low on the left (portrait), money | hotbar | events share one bottom row`,
			function()
				local s = Layout.screen(vp.w, vp.h)
				expect(s.phone).toBe(true)
				local bar = InventoryLayout.bar(
					s.hotbar,
					InventoryLayout.MAX_SLOTS,
					s.compact,
					Layout.MIN_TOUCH_DESIGN,
					s.tight
				)
				if vp.w > vp.h then
					expect(s.nav.y).toBe(Layout.TOP)
				else
					expect(s.nav.y > Layout.NAV.top).toBe(true)
					expect(s.nav.y + s.nav.h < s.money.rect.y).toBe(true)
				end
				local bottom = bar.rect.y + bar.rect.h
				expect(math.abs(s.money.rect.y + s.money.rect.h - bottom) <= LayoutAssert.BOTTOM_ALIGN).toBe(true)
				expect(math.abs(s.status.rect.y + s.status.rect.h - bottom) <= LayoutAssert.BOTTOM_ALIGN).toBe(true)
				expect(s.money.rect.x + s.money.rect.w <= bar.rect.x).toBe(true)
				expect(bar.rect.x + bar.rect.w <= s.status.rect.x).toBe(true)
				expect(bar.shown >= (if s.tight then 3 else 8)).toBe(true)
				local check = LayoutAssert.new(vp.name, s)
				LayoutAssert.hotbarChecks(check)
				expect(check.report()).toBe("")
			end
		)
	end
	it(
		"landscape phone: the bottom row sits at most 16 screen px above the bottom edge, portrait and PC keep their insets",
		function()
			for _, vp in { { 844, 390 }, { 844, 332 }, { 932, 430 }, { 667, 375 } } do
				local s = Layout.screen(vp[1], vp[2])
				expect(s.phone).toBe(true)
				local bar = InventoryLayout.bar(
					s.hotbar,
					InventoryLayout.MAX_SLOTS,
					s.compact,
					Layout.MIN_TOUCH_DESIGN,
					s.tight
				)
				for name, bottom in
					{
						money = s.money.rect.y + s.money.rect.h,
						status = s.status.rect.y + s.status.rect.h,
						hotbar = bar.rect.y + bar.rect.h,
					}
				do
					local gap = (s.height - bottom) * s.scale
					expect(`{vp[1]}x{vp[2]} {name}: {gap <= 16 and gap > 0}`).toBe(`{vp[1]}x{vp[2]} {name}: true`)
				end
				expect(s.bottomInset * s.scale <= 16).toBe(true)
				expect(Layout.rowRise(s)).toBe(0)
				local check = LayoutAssert.new(`{vp[1]}x{vp[2]}`, s)
				LayoutAssert.hotbarChecks(check)
				expect(check.report()).toBe("")
			end
			-- portrait phone and PC are unchanged: the 90 px touch strip + rise, and the 2 x MARGIN desktop inset
			local portrait, pc = Layout.screen(390, 844), Layout.screen(1920, 1080)
			expect(portrait.bottomInset).toBe(math.ceil(Layout.TOUCH_CONTROLS_HEIGHT / Layout.MIN_SCALE))
			expect(Layout.rowRise(portrait) > 0).toBe(true)
			expect(pc.bottomInset).toBe(Layout.MARGIN * 2)
			expect(Layout.rowRise(pc)).toBe(0)
		end
	)
	it("the landscape row check catches a bottom row lifted more than 16 px off the bottom edge", function()
		local s = table.clone(Layout.screen(844, 390)) :: any
		local lift = 30
		s.bottomInset = s.bottomInset + lift
		s.hotbar = Layout.rect(s.hotbar.x, s.hotbar.y - lift, s.hotbar.w, s.hotbar.h)
		s.money = table.clone(s.money)
		s.money.rect = Layout.rect(s.money.rect.x, s.money.rect.y - lift, s.money.rect.w, s.money.rect.h)
		s.status = table.clone(s.status)
		s.status.rect = Layout.rect(s.status.rect.x, s.status.rect.y - lift, s.status.rect.w, s.status.rect.h)
		local check = LayoutAssert.new("probe", s)
		LayoutAssert.hotbarChecks(check)
		expect(has(check.report(), "landscape bottom inset")).toBe(true)
	end)
	it("only portrait 390 wide is tight; PC and 1024x768 are not phones and put the nav low, under NAV.top", function()
		for _, vp in LayoutAssert.PHONE_VIEWPORTS do
			expect(Layout.screen(vp.w, vp.h).tight).toBe(vp.w == 390)
		end
		for _, vp in { { 1024, 768 }, { 1024, 710 }, { 1366, 768 }, { 1920, 1080 } } do
			local s = Layout.screen(vp[1], vp[2])
			expect(s.phone).toBe(false)
			expect(s.tight).toBe(false)
			expect(s.nav.y > Layout.NAV.top).toBe(true)
			expect(s.nav.y + s.nav.h < s.money.rect.y).toBe(true)
		end
	end)
	it("the landscape row check catches a hotbar off the bottom row, a nav off the top and an overlap", function()
		local s = table.clone(Layout.screen(844, 390)) :: any
		s.hotbar = Layout.rect(s.hotbar.x, s.hotbar.y + 20, s.hotbar.w, s.hotbar.h)
		local check = LayoutAssert.new("probe", s)
		LayoutAssert.hotbarChecks(check)
		expect(has(check.report(), "is not aligned with the hotbar bottom")).toBe(true)
		local low = table.clone(Layout.screen(844, 390)) :: any
		low.nav = Layout.rect(low.nav.x, 60, low.nav.w, low.nav.h)
		local lowCheck = LayoutAssert.new("probe", low)
		LayoutAssert.hotbarChecks(lowCheck)
		expect(has(lowCheck.report(), "is not at the top")).toBe(true)
		local over = table.clone(Layout.screen(844, 390)) :: any
		over.status = table.clone(over.status)
		over.status.rect = Layout.rect(over.hotbar.x + 40, over.status.rect.y, over.status.rect.w, over.status.rect.h)
		local overCheck = LayoutAssert.new("probe", over)
		LayoutAssert.hotbarChecks(overCheck)
		expect(has(overCheck.report(), "Status")).toBe(true)
	end)
	it("portrait, tablet and desktop keep the 2-column nav", function()
		for _, vp in { { 390, 844 }, { 1024, 768 }, { 1366, 768 }, { 1920, 1080 } } do
			local s = Layout.screen(vp[1], vp[2])
			expect(s.short).toBe(false)
			expect(s.navColumns).toBe(2)
		end
	end)
	it("the checks catch a nav button pushed off screen or covered", function()
		local s = table.clone(Layout.screen(844, 332)) :: any
		s.navButtons = table.clone(s.navButtons)
		s.navButtons[navIndex("Dex")] = Layout.rect(18, s.height - 20, 56, 56)
		local check = LayoutAssert.new("probe", s)
		LayoutAssert.navReachable(check)
		expect(has(check.report(), "Nav.Dex")).toBe(true)
		expect(has(check.report(), "is off the")).toBe(true)
		local covered = table.clone(Layout.screen(844, 332)) :: any
		covered.money = table.clone(covered.money)
		covered.money.rect = covered.navButtons[navIndex("Dex")]
		local check2 = LayoutAssert.new("probe", covered)
		LayoutAssert.navReachable(check2)
		expect(has(check2.report(), "overlaps Money")).toBe(true)
	end)
	it("noNegativeSizes flags a negative box and a Dex list with no room", function()
		local s = table.clone(Layout.screen(844, 332)) :: any
		s.column = Layout.rect(0, 0, 10, -5)
		s.panel = Layout.rect(s.panel.x, s.panel.y, s.panel.w, 100)
		local check = LayoutAssert.new("probe", s)
		LayoutAssert.noNegativeSizes(check)
		expect(has(check.report(), "screen.column")).toBe(true)
		expect(has(check.report(), "Dex list is")).toBe(true)
	end)
end)

describe("ZIndex order", function()
	it("Banners < Daily < Carry, over the side panels", function()
		expect(LayoutAssert.zOrder({ "Base", "Menu", "Banners", "Daily", "Carry" })).toBeNil()
		expect(LayoutAssert.zOrder({ "Daily", "Banners" })).toBeTruthy()
		expect(LayoutAssert.zOrder({ "Carry", "Daily" })).toBeTruthy()
	end)
end)

-- Numbers players read must come from Config, not literals in the UI.
describe("Config-backed numbers", function()
	it("Speed Coil copy uses Config walk speeds", function()
		local text = ShopCatalog.speedCoilText(Config) :: string
		expect(has(text, tostring(Config.BASE_WALK_SPEED))).toBe(true)
		expect(has(text, tostring(Config.SPEED_COIL_WALK_SPEED))).toBe(true)
		local fake = table.clone(Config) :: any
		fake.SPEED_COIL_WALK_SPEED = 31
		expect(has(ShopCatalog.speedCoilText(fake) :: string, "→ 31")).toBe(true)
	end)
end)

describe("phone nav + panels", function()
	it("a phone card gets the nav tiles' width; on desktop it sits beside the nav", function()
		local s = Layout.screen(390, 844)
		expect(s.panel.x).toBe(Layout.MARGIN)
		local desktop = Layout.screen(1920, 1080)
		expect(desktop.panel.x).toBe(desktop.nav.x + desktop.nav.w + Layout.GAP)
	end)
end)
