--!strict
-- PR gate layout (tools/pr-gate/layout.sh): every rule at the five gate
-- viewports (390x844, 844x390, 1024x768, 1366x768, 1920x1080), each raw and
-- minus the 58 px top bar (the ScreenGui's real size, IgnoreGuiInset off):
-- LayoutAssert.standard, navReachable (on screen, nothing drawn
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

-- Known findings the gate tolerates (each must still occur, so a fix forces this list to shrink). Empty:
-- the nav is a 2-column tile grid (more columns on a short screen) and nothing overlaps it.
local KNOWN: { { label: string, pattern: string } } = {}

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
			local s = Layout.screen(tonumber(w) :: number, tonumber(h) :: number)
			if knownHits(gate(k.label, s), k.pattern) == 0 then
				error(`KNOWN finding no longer occurs, remove it: {k.label} {k.pattern}`)
			end
		end
	end)
end)

describe("PR gate: the checks catch PR #60's bugs", function()
	-- A one-column nav on a landscape phone (the pre-v27 shape). 844x332 is Studio's 844x390 under the 58 px
	-- top bar (what the ScreenGui gets): the column runs into the money cluster.
	local function oneColumn(w: number, h: number): any
		local s = table.clone(Layout.screen(w, h)) :: any
		s.nav = Layout.navRect(s.compact, Layout.TOP, nil, 1)
		s.navButtons = Layout.navButtons(s.compact, s.nav, nil, 1)
		s.navColumns = 1
		return s
	end
	for _, case in
		{
			{ w = 844, h = 332, keys = { "Codes" } },
		}
	do
		it(`{case.w}x{case.h} one nav column: {table.concat(case.keys, " / ")} under the money cluster`, function()
			local check = LayoutAssert.new(`{case.w}x{case.h} one column`, oneColumn(case.w, case.h))
			LayoutAssert.navReachable(check)
			local report = check.report()
			for _, key in case.keys do
				expect(string.match(report, "Nav%." .. key .. " {[^}]*} overlaps Money") ~= nil).toBe(true)
			end
		end)
	end
	it("844x390: Dex covered by an overlay (not clickable)", function()
		local s = table.clone(Layout.screen(844, 390)) :: any
		s.tutorial = s.navButtons[navIndex("Dex")]
		local check = LayoutAssert.new("844x390 covered", s)
		LayoutAssert.navReachable(check)
		expect(has(check.report(), "Nav.Dex")).toBe(true)
		expect(has(check.report(), "overlaps Tutorial")).toBe(true)
	end)
	it("844x390: a squashed nav button and a non-uniform scale", function()
		local s = table.clone(Layout.screen(844, 390)) :: any
		s.navButtons = table.clone(s.navButtons)
		local dex = s.navButtons[navIndex("Dex")]
		s.navButtons[navIndex("Dex")] = Layout.rect(dex.x, dex.y, dex.w, dex.h * 0.6)
		s.width += 40
		local check = LayoutAssert.new("844x390 squashed", s)
		LayoutAssert.notSquashed(check)
		local report = check.report()
		expect(has(report, "Nav.Dex")).toBe(true)
		expect(has(report, "is squashed")).toBe(true)
		expect(has(report, "scale is not uniform")).toBe(true)
	end)
end)
