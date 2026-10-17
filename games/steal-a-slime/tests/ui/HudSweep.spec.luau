--!strict
-- Small-screen sweep of the HUD overlays: banner stack (countdown chip), toast stack and the
-- layout boxes around them at the five gate viewports (390x844, 844x390, 1024x768, 1366x768, 1920x1080).
local fs = require("@lune/fs")

local Config = require("../../src/shared/Config")
local Goals = require("../../src/shared/Goals")

local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local NextSpawn = require("../../src/ui/NextSpawn")
local TestRunner = require("../TestRunner")
local ToastQueue = require("../../src/ui/ToastQueue")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local CHIP_H = 34 -- one banner at TextSize 15-16: Hud `banner` 34 px minimum
local BANNER_PAD = 20 -- Hud banner UIPadding left + right
local TOAST_PAD = 16 -- Toasts frame padding 8 + 8
local TOAST_ICON = 36 + 8
local TOAST_GAP = 6

-- Longest realistic strings.
local LONGEST_CHIP = (NextSpawn.chip(false, 1000 + 35999, nil, 1000) :: NextSpawn.Info).text -- "🌧 Slime Rain in 9:59:59"
local LONGEST_BOSS = (NextSpawn.chip(false, nil, 1000 + 35999, 1000) :: NextSpawn.Info).text
local LONG_TOASTS = {
	{ "Legendary Rainbow Blorp hatched!", "rare", 20 },
	{ "Someone is stealing from you!", "away", 16 },
	{ "Not enough cash (x12)", "bad", 16 },
	{ "Badge unlocked!\nSlime Collector", "badge", 16 },
}

local function toastStackHeight(width: number): number
	local total = 0
	for i = 1, ToastQueue.MAX do
		local t = LONG_TOASTS[(i - 1) % #LONG_TOASTS + 1]
		local textH = Layout.wrappedHeight(t[1], t[3], width - TOAST_PAD - TOAST_ICON, true)
		total += math.max(textH, 36) + TOAST_PAD
		if i > 1 then
			total += TOAST_GAP
		end
	end
	return total
end

describe("HUD banners and toasts at the gate viewports", function()
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		local s = Layout.screen(vp.w, vp.h)
		local label = vp.name

		it(`{label}: the banner column is inside the viewport`, function()
			local check = LayoutAssert.new(label, s)
			local b = s.banners
			check.onScreen("Banners", Layout.rect(b.x, b.y, b.w, CHIP_H), 0)
			check.noOverlap("Banners", Layout.rect(b.x, b.y, b.w, CHIP_H), "Hud", s.hud.rect)
			expect(check.report()).toBe("")
		end)

		it(`{label}: the countdown chip text fits a banner`, function()
			local check = LayoutAssert.new(label, s)
			for _, text in { LONGEST_CHIP, LONGEST_BOSS } do
				check.text({
					name = "NextSpawnChip",
					text = text,
					size = 15,
					bold = true,
					w = s.banners.w - BANNER_PAD,
					h = CHIP_H,
				})
			end
			expect(check.report()).toBe("")
		end)

		it(`{label}: toasts clear the banner stack (1 chip, 3 banners) and stay on screen`, function()
			local check = LayoutAssert.new(label, s)
			for _, count in { 0, 1, 3 } do
				local bannerH = count * CHIP_H + math.max(count - 1, 0) * 6
				local stack = Layout.rect(s.banners.x, s.banners.y, s.banners.w, bannerH)
				local box = Layout.toastBox(s, bannerH)
				check.onScreen(`Toasts({count} banners)`, box, Layout.MARGIN)
				if bannerH > 0 then
					check.noOverlap(`Toasts({count} banners)`, box, "Banners", stack)
				end
				check.noOverlap(`Toasts({count} banners)`, box, "Hud", s.hud.rect)
				check.noOverlap(`Toasts({count} banners)`, box, "Nav", s.nav)
			end
			expect(check.report()).toBe("")
		end)

		it(`{label}: a full stack of {ToastQueue.MAX} long toasts stays on screen under one banner`, function()
			local box = Layout.toastBox(s, CHIP_H)
			local stack = Layout.rect(box.x, box.y, box.w, toastStackHeight(box.w))
			local check = LayoutAssert.new(label, s)
			check.onScreen(`{ToastQueue.MAX} toasts`, stack, Layout.MARGIN)
			check.noOverlap(
				`{ToastQueue.MAX} toasts`,
				stack,
				"Banners",
				Layout.rect(s.banners.x, s.banners.y, s.banners.w, CHIP_H)
			)
			expect(check.report()).toBe("")
		end)
	end

	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		local s = Layout.screen(vp.w, vp.h)
		it(`{vp.name}: the visible toast stack fits its box with 0..4 banners`, function()
			local check = LayoutAssert.new(vp.name, s)
			for count = 0, 4 do
				local bannerH = count * CHIP_H + math.max(count - 1, 0) * 6
				local box = Layout.toastBox(s, bannerH)
				local q = ToastQueue.new()
				for i, t in LONG_TOASTS do
					q.push(t[1], t[2], 0)
					q.push(`{t[1]} {i}`, "info", 0)
				end
				local visible = q.step(0.1, false, {
					room = box.h,
					gap = TOAST_GAP,
					height = function(e: any): number
						local size = if e.kind == "rare" then 20 else 16
						return math.max(Layout.wrappedHeight(e.text, size, box.w - TOAST_PAD - TOAST_ICON, true), 36)
							+ TOAST_PAD
					end,
				})
				local total = 0
				for i, e in visible do
					local size = if e.kind == "rare" then 20 else 16
					local h = math.max(Layout.wrappedHeight(e.text, size, box.w - TOAST_PAD - TOAST_ICON, true), 36)
						+ TOAST_PAD
					total += h + if i > 1 then TOAST_GAP else 0
				end
				if #visible > 0 then
					local stack = Layout.rect(box.x, box.y, box.w, total)
					check.onScreen(`Toasts({count} banners)`, stack, Layout.MARGIN)
					if bannerH > 0 then
						check.noOverlap(
							`Toasts({count} banners)`,
							stack,
							"Banners",
							Layout.rect(s.banners.x, s.banners.y, s.banners.w, bannerH)
						)
					end
					check.noOverlap(`Toasts({count} banners)`, stack, "Nav", s.nav)
				end
				if count == 0 then
					expect(#visible > 0).toBe(true)
				end
				expect(#visible <= ToastQueue.MAX).toBe(true)
				expect(visible[1].priority).toBe(3) -- steal alerts / rare first
			end
			expect(check.report()).toBe("")
		end)
	end

	it("toastBox keeps the stock box when no banner is up or the columns are apart", function()
		local s = Layout.screen(1920, 1080)
		expect(Layout.toastBox(s, 0)).toBe(s.toasts)
		expect(Layout.toastBox(s, 120)).toBe(s.toasts)
	end)
end)

describe("Hud banner source", function()
	it("sizes every banner to the Banners frame, not a fixed 560 px", function()
		local hud = fs.readFile("src/ui/Hud.luau")
		expect(string.find(hud, "Size = UDim2.fromOffset(560, 34)", 1, true) == nil).toBe(true)
		expect(string.find(hud, "Size = UDim2.new(1, 0, 0, 34)", 1, true) ~= nil).toBe(true)
	end)
end)

describe("Goals 'Next:' preview", function()
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		it(`{vp.name}: every goal step's Next line fits one row line`, function()
			local s = Layout.screen(vp.w, vp.h)
			-- Row text width: menu card minus its padding / scrollbar, the row inset and the 40 px icon column.
			local textW = s.menuW - 24 - 10 - (8 + 40 + 8) - 10
			local check = LayoutAssert.new(vp.name, s)
			for _, goal in Config.GOALS do
				for stage = 3, #goal.targets do
					check.text({
						name = `Next {goal.id}#{stage}`,
						text = `Next: {Goals.title(goal, goal.targets[stage])}`,
						size = 12,
						w = textW,
						h = 14,
					})
				end
			end
			expect(check.report()).toBe("")
		end)
	end
end)
