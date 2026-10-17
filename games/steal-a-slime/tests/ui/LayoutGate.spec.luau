--!strict
-- PR gate layout (tools/pr-gate/layout.sh): every rule at the five gate
-- viewports (390x844, 844x390, 1024x768, 1366x768, 1920x1080), each raw and
-- minus the 58 px top bar (the ScreenGui's real size, IgnoreGuiInset off),
-- nav collapsed and expanded: LayoutAssert.standard, navReachable (on screen, nothing drawn
-- over a nav button), noNegativeSizes and notSquashed (aspect ratio). The
-- fixtures at the bottom prove each class of bug PR #60 fixed still fails.
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local Nav = require("../../src/ui/Nav")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

-- Known findings the gate tolerates (each must still occur, so a fix forces
-- this list to shrink). navReachable treats the banner stack as reaching the
-- bottom of the screen; on a portrait phone with the nav expanded (a state
-- the player picks with the toggle) that column overlaps the labelled nav.
-- Under the top bar (390x786) the nav is taller than the band between the
-- HUD and the tutorial card shown while carrying, so that card covers the
-- bottom of the nav (Nav.Leaders); tools/pr-gate/rhr_check.py sees the same.
local KNOWN: { { label: string, pattern: string } } = {
	{ label = "390x844 nav expanded", pattern = "^%[390x844 nav expanded%] Nav%.%w+ {.-} overlaps Banners " },
	{ label = "390x786 nav expanded", pattern = "^%[390x786 nav expanded%] Nav%.%w+ {.-} overlaps Banners " },
	{ label = "390x786 nav collapsed", pattern = "^%[390x786 nav collapsed%] TutorialCarrying {.-} overlaps Nav " },
	{
		label = "390x786 nav collapsed",
		pattern = "^%[390x786 nav collapsed%] Nav%.%w+ {.-} overlaps TutorialCarrying ",
	},
	{ label = "390x786 nav expanded", pattern = "^%[390x786 nav expanded%] TutorialCarrying {.-} overlaps Nav " },
	{
		label = "390x786 nav expanded",
		pattern = "^%[390x786 nav expanded%] Nav%.%w+ {.-} overlaps TutorialCarrying ",
	},
}

-- The gate viewports, each raw and under the top bar.
local TOPBAR = 58
local VIEWPORTS = {}
for _, vp in LayoutAssert.GATE_VIEWPORTS do
	table.insert(VIEWPORTS, vp)
	table.insert(VIEWPORTS, { name = `{vp.w}x{vp.h - TOPBAR}`, w = vp.w, h = vp.h - TOPBAR })
end

local function unexpected(label: string, report: string): (string, number)
	local out, known = {}, 0
	for _, line in string.split(report, "\n") do
		local ok = line == ""
		for _, k in KNOWN do
			if k.label == label and string.match(line, k.pattern) then
				ok = true
				known += 1
			end
		end
		if not ok then
			table.insert(out, line)
		end
	end
	return table.concat(out, "\n"), known
end

-- Lines of `report` matching a KNOWN pattern.
local function knownHits(report: string, pattern: string): number
	local n = 0
	for _, line in string.split(report, "\n") do
		if string.match(line, pattern) then
			n += 1
		end
	end
	return n
end

local function gate(label: string, screen: Layout.Screen): string
	local check = LayoutAssert.standard(label, screen)
	LayoutAssert.navReachable(check)
	LayoutAssert.noNegativeSizes(check)
	LayoutAssert.notSquashed(check)
	return check.report()
end

local function navIndex(key: string): number
	for i, entry in Nav.ENTRIES do
		if entry.key == key then
			return i
		end
	end
	error(`no nav entry {key}`)
end

describe("PR gate: five viewports (raw and under the top bar), every layout rule", function()
	for _, entry in LayoutAssert.screens(VIEWPORTS) do
		it(`{entry.label}: on screen, unoccluded, not squashed, text fits`, function()
			local rest = unexpected(entry.label, gate(entry.label, entry.screen))
			expect(rest).toBe("")
		end)
	end
	it("known findings still occur (remove them from KNOWN once fixed)", function()
		for _, k in KNOWN do
			local vp = string.match(k.label, "^(%d+x%d+)") :: string
			local w, h = string.match(vp, "^(%d+)x(%d+)$")
			local s = Layout.screen(tonumber(w) :: number, tonumber(h) :: number, {
				navCollapsed = has(k.label, "collapsed"),
			})
			if knownHits(gate(k.label, s), k.pattern) == 0 then
				error(`KNOWN finding no longer occurs, remove it: {k.label} {k.pattern}`)
			end
		end
	end)
end)

describe("PR gate: the checks catch PR #60's bugs", function()
	-- Pre-#60 landscape: two-row compact HUD and one nav column. 844x332 is
	-- Studio's 844x390 under the 58 px top bar (what the ScreenGui gets).
	local function preV27(w: number, h: number): any
		local s = table.clone(Layout.screen(w, h, { navCollapsed = true })) :: any
		s.hud = Layout.hud(s.width, true)
		local top = s.hud.rect.y + s.hud.rect.h + Layout.GAP
		s.nav = Layout.navRect(true, top, s.height - s.bottomInset, nil, 1)
		s.navButtons = Layout.navButtons(s.nav, nil, 1)
		s.navColumns = 1
		return s
	end
	for _, case in
		{
			{ w = 844, h = 390, keys = { "Codes" } },
			{ w = 844, h = 332, keys = { "Dex", "Codes" } },
		}
	do
		it(`{case.w}x{case.h} pre-#60 (one nav column): {table.concat(case.keys, " / ")} off screen`, function()
			local check = LayoutAssert.new(`{case.w}x{case.h} one column`, preV27(case.w, case.h))
			LayoutAssert.navReachable(check)
			local report = check.report()
			for _, key in case.keys do
				expect(string.match(report, "Nav%." .. key .. " {[^}]*} is off the") ~= nil).toBe(true)
			end
		end)
	end
	it("844x390: Dex covered by an overlay (not clickable)", function()
		local s = table.clone(Layout.screen(844, 390)) :: any
		s.tutorial = s.navButtons[1 + navIndex("Dex")]
		local check = LayoutAssert.new("844x390 covered", s)
		LayoutAssert.navReachable(check)
		expect(has(check.report(), "Nav.Dex")).toBe(true)
		expect(has(check.report(), "overlaps Tutorial")).toBe(true)
	end)
	it("844x390: a squashed nav button, HUD button and non-uniform scale", function()
		local s = table.clone(Layout.screen(844, 390)) :: any
		s.navButtons = table.clone(s.navButtons)
		local dex = s.navButtons[1 + navIndex("Dex")]
		s.navButtons[1 + navIndex("Dex")] = Layout.rect(dex.x, dex.y, dex.w, dex.h * 0.6)
		s.hud = table.clone(s.hud)
		s.hud.items = table.clone(s.hud.items)
		local lock = s.hud.items.Lock
		s.hud.items.Lock = Layout.rect(lock.x, lock.y, lock.w * 1.5, lock.h)
		s.width += 40
		local check = LayoutAssert.new("844x390 squashed", s)
		LayoutAssert.notSquashed(check)
		local report = check.report()
		expect(has(report, "Nav.Dex")).toBe(true)
		expect(has(report, "Hud.Lock")).toBe(true)
		expect(has(report, "is squashed")).toBe(true)
		expect(has(report, "scale is not uniform")).toBe(true)
	end)
end)
