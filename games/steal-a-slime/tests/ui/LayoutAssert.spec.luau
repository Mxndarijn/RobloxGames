--!strict
-- v18 mobile-first layout at 390x844 and 1920x1080 (nav collapsed and
-- expanded), on Layout.screen() rects via tests/ui/LayoutAssert.luau.
local fs = require("@lune/fs")

local Config = require("../../src/shared/Config")
local Hint = require("../../src/ui/Hint")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local Nav = require("../../src/ui/Nav")
local ShopCatalog = require("../../src/ui/ShopCatalog")
local TestRunner = require("../TestRunner")

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
		check.text({ name = "long", text = "Buy next pad 8/8", size = 15, bold = true, w = 60, h = 56 })
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
	it("covers both viewports with the nav collapsed and expanded", function()
		local labels = {}
		for _, entry in LayoutAssert.screens() do
			table.insert(labels, entry.label)
		end
		expect(table.concat(labels, ", ")).toBe(
			"390x844 nav collapsed, 390x844 nav expanded, 1920x1080 nav collapsed, 1920x1080 nav expanded"
		)
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
			`{entry.label}: full-window backdrop, centred cards, close X tappable and inside, clear of HUD / nav`,
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
			local file = if key == "Leaders" then "Leaderboard" else key
			expect(has(read(`src/ui/Panels/{file}.luau`), `Widgets.panel(parent, "{file}Panel", "{title}", `)).toBe(
				true
			)
		end
	end)
	it("mirrors the panels' row geometry (Shop, Rebirth, Guide)", function()
		local shop = read("src/ui/Panels/Shop.luau")
		expect(has(shop, "Shop.BADGE = 48")).toBe(true)
		expect(has(shop, "Shop.BUY_W = 110")).toBe(true)
		expect(has(shop, "Shop.DESC_H = 32")).toBe(true)
		local guide = read("src/ui/Panels/Guide.luau")
		expect(has(guide, "Guide.TIP_H = 44")).toBe(true)
		local rebirth = read("src/ui/Panels/Rebirth.luau")
		expect(has(rebirth, "slime = { y = 120, h = 72 }")).toBe(true)
		expect(has(rebirth, "button = { y = 276, h = Layout.BUTTON }")).toBe(true)
		expect(has(rebirth, "note = { y = 338, h = 18 }")).toBe(true)
	end)
	it("every card fits its content at the tallest gate viewport (no scroll on desktop)", function()
		local s = Layout.screen(1920, 1080)
		local chrome = Layout.PANEL_CHROME.header + Layout.PANEL_CHROME.pad
		expect(Layout.panelFor(s, "Rebirth").h >= chrome + 356).toBe(true) -- Rebirth.CONTENT_H
		expect(Layout.panelFor(s, "Guide").h >= chrome + 96 + 8 + 3 * (44 + 8)).toBe(true) -- Guide.CONTENT_H
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
	it("phone: compact, two HUD rows, nav collapsed by default, MIN_SCALE", function()
		local s = Layout.screen(390, 844)
		expect(s.compact).toBe(true)
		expect(s.navCollapsed).toBe(true)
		expect(s.scale).toBe(Layout.MIN_SCALE)
		expect(#s.hud.rows).toBe(2)
		expect(s.hud.items.Shop).toBeNil() -- the nav's Shop entry covers it
		expect(s.bottomInset * s.scale >= Layout.TOUCH_CONTROLS_HEIGHT).toBe(true)
	end)
	it("desktop: one HUD row with every item, labelled nav, scale 1", function()
		local s = Layout.screen(1920, 1080)
		expect(s.compact).toBe(false)
		expect(s.navCollapsed).toBe(false)
		expect(s.scale).toBe(1)
		expect(#s.hud.rows).toBe(1)
		for name in Layout.HUD_ITEMS do
			expect(s.hud.items[name]).toBeTruthy()
		end
	end)
	it("desktop: the backdrop fills the window beside the nav, cards are centred in it", function()
		for _, collapsed in { true, false } do
			local s = Layout.screen(1920, 1080, { navCollapsed = collapsed })
			local back = s.panel
			expect(back.x).toBe(s.nav.x + s.nav.w + Layout.GAP) -- right next to the nav
			expect(back.y).toBe(s.hud.rect.y + s.hud.rect.h + Layout.GAP)
			expect(back.x + back.w).toBe(s.width - Layout.MARGIN)
			expect(back.y + back.h).toBe(s.height - s.bottomInset)
			for _, entry in Nav.ENTRIES do
				local r = Layout.panelFor(s, entry.key)
				expect(r.w).toBe(Layout.MENU_WIDTH)
				expect(r.h).toBe(Layout.menuHeight(entry.key))
				expect(r.w * r.h < 0.3 * s.width * s.height).toBe(true) -- a card, not the whole screen
			end
		end
	end)
	it("phone menus use the full width and move with the nav width", function()
		local collapsed = Layout.screen(390, 844, { navCollapsed = true })
		local expanded = Layout.screen(390, 844, { navCollapsed = false })
		local a, b = Layout.panelFor(collapsed, "Shop"), Layout.panelFor(expanded, "Shop")
		expect(a.w).toBe(collapsed.column.w)
		expect(b.x - a.x).toBe(Layout.navWidth(false) - Layout.navWidth(true))
		expect(collapsed.panel.h > collapsed.column.h).toBe(true) -- the backdrop runs on under the bottom cards
		expect(Layout.drawsAbove("Carry", "Base") and Layout.drawsAbove("Tutorial", "Base")).toBe(true)
	end)
	it("hint bubbles sit below the HUD (top-bar targets) or right of the nav (menu targets)", function()
		for _, entry in LayoutAssert.screens() do
			local s = entry.screen
			for id, hint in Hint.STEPS do
				local place =
					Hint.place(s, s.hud, { id = id, text = hint.text, target = hint.target }) :: Hint.Placement
				if hint.target.kind == "hud" then
					expect(place.side).toBe("below")
					expect(place.bubble.y >= s.hud.rect.y + s.hud.rect.h).toBe(true)
				else
					expect(place.side).toBe("right")
					expect(place.bubble.x >= s.nav.x + s.nav.w).toBe(true)
				end
			end
		end
	end)
end)

-- Position of a Nav key in Nav.ENTRIES (navButtons[1] is the toggle).
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
		for _, collapsed in { true, false } do
			local label = `{vp.name} nav {if collapsed then "collapsed" else "expanded"}`
			local s = Layout.screen(vp.w, vp.h, { navCollapsed = collapsed })
			it(`{label}: every v18 rule`, function()
				expect(LayoutAssert.standard(label, s).report()).toBe("")
			end)
			it(`{label}: every nav button on screen and clear of HUD, toasts, banners, cards, panel`, function()
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
	end
	it(
		"844x332 (gate N1 numbers): short, one nav row above the money cluster, Dex button on screen, panel most of the window",
		function()
			local s = Layout.screen(844, 332)
			expect(s.short).toBe(true)
			expect(s.navColumns).toBe(Nav.ENTRIES and #Nav.ENTRIES + 1) -- the 5 buttons + the toggle in one row
			expect(s.nav.y + s.nav.h < s.money.rect.y).toBe(true)
			expect(#s.hud.rows).toBe(1)
			local dex = s.navButtons[1 + navIndex("Dex")]
			expect(dex.y + dex.h <= s.height).toBe(true)
			expect(s.nav.y + s.nav.h <= s.height - s.bottomInset).toBe(true)
			expect(s.panel.w >= Layout.MENU_WIDTH).toBe(true)
			expect(s.panel.h >= 0.5 * s.height).toBe(true)
		end
	)
	it("portrait, tablet and desktop keep one nav column and their HUD rows", function()
		for _, vp in { { 390, 844, 2 }, { 1024, 768, 2 }, { 1366, 768, 1 }, { 1920, 1080, 1 } } do
			local s = Layout.screen(vp[1], vp[2])
			expect(s.short).toBe(false)
			expect(s.navColumns).toBe(1)
			expect(#s.hud.rows).toBe(vp[3])
		end
	end)
	it("the checks catch a nav button pushed off screen or covered", function()
		local s = table.clone(Layout.screen(844, 332)) :: any
		s.navButtons = table.clone(s.navButtons)
		s.navButtons[1 + navIndex("Dex")] = Layout.rect(18, s.height - 20, 56, 56)
		local check = LayoutAssert.new("probe", s)
		LayoutAssert.navReachable(check)
		expect(has(check.report(), "Nav.Dex")).toBe(true)
		expect(has(check.report(), "is off the")).toBe(true)
		local covered = table.clone(Layout.screen(844, 332)) :: any
		covered.toasts = covered.navButtons[1 + navIndex("Dex")]
		local check2 = LayoutAssert.new("probe", covered)
		LayoutAssert.navReachable(check2)
		expect(has(check2.report(), "overlaps Toasts")).toBe(true)
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
	it("init.client places panels via panel.layout and the HUD uses the short row", function()
		expect(has(read("src/ui/init.client.luau"), "entry.panel.layout(r)")).toBe(true)
		expect(has(read("src/ui/Hud.luau"), "Layout.hud(screen.width, compact, shown, screen.short)")).toBe(true)
	end)
end)

describe("ZIndex order", function()
	it("Daily < Tutorial < Carry, banners / hint over the side panels", function()
		expect(LayoutAssert.zOrder({ "Base", "Banners", "Daily", "Tutorial", "Carry" })).toBeNil()
		expect(LayoutAssert.zOrder({ "Tutorial", "Daily" })).toBeTruthy()
	end)
	it("is what the hint overlay uses", function()
		local src = read("src/ui/Panels/HintOverlay.luau")
		expect(has(src, "Layout.ZINDEX.Banners")).toBe(true)
	end)
end)

describe("init.client applies Layout for every viewport", function()
	local src = read("src/ui/init.client.luau")
	it("lays everything out from Layout.screen and re-runs it on resize", function()
		expect(has(src, "Layout.screen(size.X, size.Y, { navCollapsed = navChoice })")).toBe(true)
		expect(has(src, 'GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)')).toBe(true)
		for _, call in
			{
				"hud.layout(s)",
				"toasts.layout(s, hud.bannerHeight)",
				"carry.layout(s)",
				"tutorial.layout(s)",
				"dailyPopup.layout(s)",
			}
		do
			expect(has(src, call)).toBe(true)
		end
		expect(has(src, "Layout.panelFor(s, entry.key, Widgets.contentHeight(")).toBe(true)
		expect(has(src, "NAV_WIDTH")).toBe(false) -- no hard-coded nav width left
	end)
	it("closes the open menu from its X, gamepad B and Esc (CLOSE_WITH_ESCAPE on)", function()
		expect(Layout.CLOSE_WITH_ESCAPE).toBe(true)
		expect(has(src, "entry.panel.close.Activated:Connect(function()\n\t\tsetOpen(nil)")).toBe(true)
		-- Binding itself is MenuClose (tests/ui/MenuClose.spec drives it).
		expect(has(src, "MenuClose.bind(ContextActionService, Layout.CLOSE_WITH_ESCAPE")).toBe(true)
		local _, escapes = string.gsub(src, "Enum%.KeyCode%.Escape", "")
		expect(escapes).toBe(0)
	end)
	it("has a collapse toggle and icon-only collapsed buttons", function()
		expect(has(src, 'Name = "NavToggle"')).toBe(true)
		expect(has(src, "btn.label.Visible = not s.navCollapsed")).toBe(true)
	end)
	it("queues the daily popup behind the tutorial (no direct auto-open)", function()
		expect(has(src, 'popups.update(state, openKey == "Welcome")')).toBe(true)
		expect(has(src, 'next == "Daily"')).toBe(true)
		expect(has(src, "shouldAutoOpen")).toBe(false)
	end)
end)

describe("touch-size buttons in the overlays", function()
	it("Drop / Claim / Close / Hide use Layout sizes", function()
		expect(has(read("src/ui/Panels/Carry.luau"), "Size = UDim2.fromOffset(100, Layout.BUTTON)")).toBe(true)
		expect(has(read("src/ui/Panels/Carry.luau"), "Slap")).toBe(false) -- the Bat Tool replaced the button
		local daily = read("src/ui/Panels/DailyPopup.luau")
		expect(has(daily, "Size = UDim2.fromOffset(200, Layout.BUTTON)")).toBe(true)
		expect(has(daily, "Size = UDim2.fromOffset(Layout.MIN_TOUCH_DESIGN, Layout.MIN_TOUCH_DESIGN)")).toBe(true)
		expect(has(read("src/ui/Panels/TutorialOverlay.luau"), "Size = UDim2.fromOffset(72, Layout.MIN_TOUCH_DESIGN)")).toBe(
			true
		)
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
	it("UI sources read these values through Config (checklist)", function()
		local checklist = {
			{ "src/ui/ShopCatalog.luau", "config.BASE_WALK_SPEED" },
			{ "src/ui/ShopCatalog.luau", "config.SPEED_COIL_WALK_SPEED" },
			{ "src/ui/Hud.luau", "ctx.Config.LOCK_MAX_REMAINING" },
			{ "src/ui/Panels/DailyPopup.luau", "ctx.Config.DAILY_STREAK_CAP" },
			{ "src/ui/Panels/DailyPopup.luau", "ctx.Config.DAILY_BASE" },
		}
		for _, item in checklist do
			local src = read(item[1])
			if not has(src, item[2]) then
				error(`{item[1]} no longer reads {item[2]}`)
			end
		end
	end)
	it("no hard-coded walk speeds or lock cap in UI copy", function()
		for _, path in { "src/ui/ShopCatalog.luau", "src/ui/Tutorial.luau", "src/ui/LockHud.luau", "src/ui/Hint.luau" } do
			local src = read(path)
			expect(has(src, "16 → 22")).toBe(false)
			expect(has(src, "→ 22")).toBe(false)
			expect(has(src, "5:00 cap")).toBe(false)
		end
	end)
end)

describe("phone nav + panels", function()
	it("an open panel collapses an expanded nav on phones (init.client setOpen)", function()
		local src = read("src/ui/init.client.luau")
		local body = string.match(src, "local function setOpen(.-)\nend") :: string
		expect(has(body, "screen.compact and not screen.navCollapsed")).toBe(true)
		expect(has(body, "navChoice = true")).toBe(true)
	end)
	it("Shop rows (v28): compact 68 px rows, two description lines, a touch-size Buy", function()
		local src = read("src/ui/Panels/Shop.luau")
		expect(has(src, "Shop.ROW = 68")).toBe(true)
		expect(has(src, "Shop.DESC_H = 32")).toBe(true)
		expect(has(src, "Size = UDim2.fromOffset(Shop.BUY_W, Layout.BUTTON)")).toBe(true)
		expect(has(src, "6 + Shop.NAME_H + 2")).toBe(true) -- name 6..28, description 30..62 in a 68 px row
	end)
end)
