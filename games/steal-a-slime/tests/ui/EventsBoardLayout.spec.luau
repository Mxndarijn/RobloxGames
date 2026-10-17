--!strict
-- FEATURES.EventsBoard / FEATURES.StealAlerts layout at the five gate viewports: the icon + text board
-- fits the banner column and leaves the toasts room; the thief arrow and the edge flash never cover the
-- HUD, the banner stack or the nav (Layout.screen rects; the Hud / StealAlertFx build Instances only in .new).
local fs = require("@lune/fs")

local Config = require("../../src/shared/Config")
local EventsBoard = require("../../src/ui/EventsBoard")
local ItemIcons = require("../../src/ui/ItemIcons")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local StealAlert = require("../../src/shared/StealAlert")
local StealAlertLayout = require("../../src/ui/StealAlertLayout")
local TestRunner = require("../TestRunner")
local WeeklyEvents = require("../../src/shared/WeeklyEvents")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local ICON = 22 -- Hud BOARD_ICON
local ICON_GAP = 6
local ROW_GAP = 3
local PAD_X, PAD_Y = 16, 8 -- Hud board UIPadding
local TEXT_SIZE = 14
local CHIP_H = 34

local function utc(y: number, m: number, d: number, h: number, min: number, s: number): number
	return os.time({ year = y, month = m, day = d, hour = h, min = min, sec = s })
end
local SAT = utc(2026, 10, 17, 19, 0, 0) -- Saturday trait window: mutation + trait + modifier + next
local SURGE = { name = "LuckSurge", label = "Luck Surge", luck = 2, mutation = 2, endsAt = SAT + 120, icon = "🍀" }

-- Pixel height of the board with `rows` laid out in a banner `width` wide (mirrors Hud: wrapped label rows).
local function boardHeight(rows: { EventsBoard.Row }, width: number): number
	local textW = width - PAD_X - ICON - ICON_GAP
	local total = PAD_Y
	for i, row in rows do
		total += math.max(ICON, Layout.wrappedHeight(row.text, TEXT_SIZE, textW, false))
		if i > 1 then
			total += ROW_GAP
		end
	end
	return total
end

describe("EventsBoard rows (icons)", function()
	local rows = EventsBoard.rows(WeeklyEvents.encode(SAT), SURGE, SAT, SAT, true) :: { EventsBoard.Row }
	local registry = ItemIcons.build(Config)

	it("is off with the flag off and every row has a registered, drawn icon", function()
		expect(EventsBoard.rows(WeeklyEvents.encode(SAT), SURGE, SAT, SAT, false)).toBeNil()
		-- title, mutation, trait, modifier (only while FEATURES.CycleModifier is on), next
		expect(#rows).toBe(if Config.FEATURES.CycleModifier then 5 else 4)
		for _, row in rows do
			expect(registry.byId[row.icon] ~= nil).toBe(true)
			expect(registry.byId[row.icon].source).toBe("drawn")
		end
	end)
	it("keeps the emoji out of the icon rows (the image replaces them) and the lines in step", function()
		local lines = EventsBoard.lines(WeeklyEvents.encode(SAT), SURGE, SAT, SAT, true) :: { string }
		expect(#lines).toBe(#rows)
		for i, row in rows do
			expect(string.find(row.text, "[\226\240]") == nil).toBe(true)
			if string.sub(row.text, 1, 5) ~= "Next:" then
				expect(string.find(lines[i], row.text, 1, true) ~= nil).toBe(true)
			end
		end
	end)
	it("picks the luck icon for luck rows and the mutation icon for mutation rows", function()
		expect(rows[2].icon).toBe("Event_mutation") -- weekly mutation
		expect(rows[3].icon).toBe("Event_mutation") -- Mutant Saturday x1.5 mutations
		if Config.FEATURES.CycleModifier then
			expect(rows[4].icon).toBe("Event_luck") -- the modifier
		else
			expect(rows[4].icon).toBe("Event_mutation") -- no modifier row: the next event follows the trait
		end
	end)
end)

describe("EventsBoard banner layout", function()
	local rows = EventsBoard.rows(WeeklyEvents.encode(SAT), SURGE, SAT, SAT, true) :: { EventsBoard.Row }
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		local s = Layout.screen(vp.w, vp.h)
		it(`{vp.name}: the board (+ one chip) fits the banner column and the toasts keep clear of it`, function()
			local boardH = boardHeight(rows, s.banners.w)
			local stackH = boardH + 6 + CHIP_H
			local stack = Layout.rect(s.banners.x, s.banners.y, s.banners.w, stackH)
			local check = LayoutAssert.new(vp.name, s)
			check.onScreen("Banners(board)", stack, 0)
			check.noOverlap("Banners(board)", stack, "Hud", s.hud.rect)
			check.noOverlap("Banners(board)", stack, "Nav", s.nav)
			local box = Layout.toastBox(s, stackH)
			check.onScreen("Toasts", box, 0)
			if box.h > 0 then
				check.noOverlap("Toasts", box, "Banners(board)", stack)
			end
			expect(check.report()).toBe("")
		end)
		it(`{vp.name}: every row's text fits its label (wrapped, never clipped)`, function()
			local textW = s.banners.w - PAD_X - ICON - ICON_GAP
			expect(textW > 120).toBe(true)
			for _, row in rows do
				expect(Layout.wrappedHeight(row.text, TEXT_SIZE, textW, false) <= TEXT_SIZE * 3 * 1.3).toBe(true)
			end
		end)
	end
	it("Hud builds the board from EventsBoard.rows with ItemIconView rows, content-sized", function()
		local hud = fs.readFile("src/ui/Hud.luau")
		expect(string.find(hud, "EventsBoard.rows(", 1, true) ~= nil).toBe(true)
		expect(string.find(hud, 'Name = "EventsBoard"', 1, true) ~= nil).toBe(true)
		expect(string.find(hud, "AutomaticSize = Enum.AutomaticSize.Y", 1, true) ~= nil).toBe(true)
	end)
end)

describe("StealAlerts arrow and flash vs the HUD", function()
	local ANGLES = {}
	for i = 0, 23 do
		table.insert(ANGLES, (i / 24) * 2 * math.pi - math.pi)
	end
	for _, entry in LayoutAssert.screens(LayoutAssert.GATE_VIEWPORTS) do
		local s = entry.screen
		it(
			`{entry.label}: the arrow + distance label stay clear of the HUD, banner stack and nav (all angles)`,
			function()
				local check = LayoutAssert.new(entry.label, s)
				for _, bannerH in { 0, 34, 150, 260 } do
					local stack = Layout.rect(s.banners.x, s.banners.y, s.banners.w, math.max(bannerH, 1))
					for _, angle in ANGLES do
						local box = StealAlertLayout.arrowBox(s, bannerH, StealAlert.edgePoint, angle)
						local name = string.format("Arrow(banners %d, angle %.2f)", bannerH, angle)
						check.onScreen(name, box, Layout.MARGIN - 0.001)
						check.noOverlap(name, box, "Hud", s.hud.rect)
						check.noOverlap(name, box, "Nav", s.nav)
						if bannerH > 0 then
							check.noOverlap(name, box, "Banners", stack)
						end
					end
				end
				expect(check.report()).toBe("")
			end
		)
	end
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		local s = Layout.screen(vp.w, vp.h)
		it(
			`{vp.name}: the flash border stays in the viewport margin on phones, the stock thickness elsewhere`,
			function()
				local t = StealAlertLayout.flashThickness(s)
				if s.compact then
					expect(t > 0).toBe(true)
					expect(s.hud.rect.x >= t).toBe(true)
					expect(s.hud.rect.y >= t).toBe(true)
					expect(s.nav.x >= t).toBe(true)
					expect(s.nav.y >= t).toBe(true)
				else
					expect(t).toBe(StealAlertLayout.FLASH)
				end
			end
		)
	end
	it("StealAlertFx lays out through StealAlertLayout", function()
		local fx = fs.readFile("src/ui/StealAlertFx.luau")
		expect(string.find(fx, "StealAlertLayout.arrowBox(", 1, true) ~= nil).toBe(true)
		expect(string.find(fx, "StealAlertLayout.flashThickness(", 1, true) ~= nil).toBe(true)
	end)
	it("the StealAlerts and EventsBoard flags stay default off", function()
		expect(Config.FEATURES.StealAlerts).toBe(false)
		expect(Config.FEATURES.EventsBoard).toBe(false)
	end)
end)
