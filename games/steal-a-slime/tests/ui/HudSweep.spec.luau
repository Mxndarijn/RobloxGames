--!strict
-- Small-screen sweep of the HUD overlay: the banner stack (countdown chip) and the layout boxes around it at
-- the five gate viewports (390x844, 844x390, 1024x768, 1366x768, 1920x1080). Toasts are gone (B6).
local fs = require("@lune/fs")

local Config = require("../../src/shared/Config")
local Goals = require("../../src/shared/Goals")

local EventSecretBanner = require("../../src/ui/EventSecretBanner")
local EventSecrets = require("../../src/shared/EventSecrets")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local NextSpawn = require("../../src/ui/NextSpawn")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local CHIP_H = 34 -- one banner at TextSize 15-16: Hud `banner` 34 px minimum
local BANNER_PAD = 20 -- Hud banner UIPadding left + right

-- Longest realistic strings.
local LONGEST_CHIP = (NextSpawn.chip(false, 1000 + 35999, nil, 1000) :: NextSpawn.Info).text -- "🌧 Slime Rain in 9:59:59"
local LONGEST_BOSS = (NextSpawn.chip(false, nil, 1000 + 35999, 1000) :: NextSpawn.Info).text

describe("HUD banners at the gate viewports", function()
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		local s = Layout.screen(vp.w, vp.h)
		local label = vp.name

		it(`{label}: the banner column is inside the viewport and clear of the nav`, function()
			local check = LayoutAssert.new(label, s)
			local b = s.banners
			check.onScreen("Banners", Layout.rect(b.x, b.y, b.w, CHIP_H), 0)
			for count = 1, 3 do
				local bannerH = count * CHIP_H + (count - 1) * 6
				check.noOverlap(`Banners({count})`, Layout.rect(b.x, b.y, b.w, bannerH), "Nav", s.nav)
			end
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
	end
end)

-- The featured event Secret banner (TextSize 16, wraps): the longest name and countdown fits in two lines.
local LONGEST_FEATURED = (function()
	local longest = ""
	for _, entry in EventSecrets.ROTATION do
		local text =
			EventSecretBanner.banner({ id = entry.id, name = entry.name, endsAt = 1000 + 6 * 86400 + 23 * 3600 }, 1000)
		if text and #text > #longest then
			longest = text
		end
	end
	return longest
end)()

describe("featured Secret banner at the gate viewports", function()
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		local s = Layout.screen(vp.w, vp.h)
		it(`{vp.name}: the longest featured Secret line fits two banner lines`, function()
			local check = LayoutAssert.new(vp.name, s)
			check.text({
				name = "FeaturedSecret",
				text = LONGEST_FEATURED,
				size = 16,
				w = s.banners.w - BANNER_PAD,
				h = 2 * CHIP_H - 8,
				wrapped = true,
			})
			expect(check.report()).toBe("")
		end)
	end
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
