--!strict
-- v26: scroll list rows must not stack. Builds the real Shop, Goals, Merge,
-- Dex, Plot, Rebirth and Leaderboard panels (tests/ui/UiHarness.luau), feeds
-- them a server State while hidden (as setOpen did live) and checks every
-- row's rect: Y = paddingTop + sum(previous heights + gaps), pairwise
-- disjoint, inside the canvas, at the gate viewport sizes.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox") :: any

local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Fixtures = require("../Fixtures")
local Genome = require("../../src/shared/Genome")
local Layout = require("../../src/ui/Layout")
local Remotes = require("../../src/shared/Remotes")
local ServerFixtures = require("../ServerFixtures")
local ShopCatalog = require("../../src/ui/ShopCatalog")
local Snapshot = require("../../src/server/Snapshot")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local Enum, UDim2 = roblox.Enum, roblox.UDim2

local VIEWPORTS = { { 390, 844 }, { 844, 390 }, { 1024, 768 }, { 1366, 768 }, { 1920, 1080 } }

type RowRect = { name: string, x: number, y: number, w: number, h: number }

-- Problems with a list's row rects (empty = fine): Y off the stackRows
-- formula, two rows sharing vertical space, or a row outside the canvas.
local function rowProblems(rows: { RowRect }, gap: number, canvasH: number, listW: number): { string }
	local problems = {}
	local heights = {}
	for i, row in rows do
		heights[i] = row.h
	end
	local ys = Layout.stackRows(heights, gap)
	for i, row in rows do
		if row.y ~= ys[i] then
			table.insert(problems, `{row.name} at y={row.y}, expected {ys[i]}`)
		end
		if row.y < 0 or row.y + row.h > canvasH then
			table.insert(problems, `{row.name} y {row.y}..{row.y + row.h} outside canvas 0..{canvasH}`)
		end
		if row.x < 0 or row.x + row.w > listW then
			table.insert(problems, `{row.name} x {row.x}..{row.x + row.w} outside list width {listW}`)
		end
		for j = i + 1, #rows do
			local other = rows[j]
			if row.y < other.y + other.h and other.y < row.y + row.h then
				table.insert(problems, `{row.name} overlaps {other.name}`)
			end
		end
	end
	return problems
end

local function axis(dim: any, parent: number): number
	return dim.Scale * parent + dim.Offset
end

type ListGeometry = { rows: { RowRect }, gap: number, canvasH: number, listW: number, list: any }

-- Rows of the scroll list `List` in `panel` laid out in box `r`, as drawn:
-- visible GuiObject children in canvas space (Widgets.panel body:
-- Layout.panelBody).
local function geometry(panel: any, r: Layout.Rect): ListGeometry
	local list = UiHarness.find(panel.frame, "List")
	assert(list, "panel has no List")
	local bodyW = Layout.panelBody(r).w
	local listW = axis(list.Size.X, bodyW)
	local rows = {}
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") and child.Visible then
			assert(child.Position.Y.Scale == 0 and child.AnchorPoint.Y == 0, `{child.Name}: offset-only Y`)
			table.insert(rows, {
				name = child.Name,
				x = axis(child.Position.X, listW) - child.AnchorPoint.X * axis(child.Size.X, listW),
				y = child.Position.Y.Offset,
				w = axis(child.Size.X, listW),
				h = axis(child.Size.Y, 0),
			})
		end
	end
	table.sort(rows, function(a, b)
		return a.y < b.y
	end)
	return {
		rows = rows,
		gap = list:GetAttribute("ListGap"),
		canvasH = axis(list.CanvasSize.Y, 0),
		listW = listW,
		list = list,
	}
end

local function ctx(): any
	return {
		Config = Config,
		Constants = Constants,
		Genome = Genome,
		actions = Remotes.ACTIONS,
		send = function() end,
		serverNow = function()
			return ServerFixtures.T0
		end,
		playerName = function()
			return "Tester"
		end,
		toast = function() end,
	}
end

-- A mid-game State: 6 slimes over three tiers, cash for the shop, SlimeDex.
local function state(): any
	local slimes = {}
	for i = 1, 6 do
		table.insert(slimes, Fixtures.slime(`s{i}`, 1 + (i % 3)))
	end
	local world = ServerFixtures.world()
	local session = ServerFixtures.join(world, 1, slimes, 5000)
	local s: any = Snapshot.build(world, session, ServerFixtures.T0)
	if #s.dex < 3 then
		s.dex = { "1:Plain", "2:Plain", "3:Plain", "1:Spots" }
	end
	return s
end

local BOARD = {
	entries = {
		{ rank = 2, userId = 2, name = "B", value = 900 },
		{ rank = 1, userId = 1, name = "A", value = 1000 },
		{ rank = 3, userId = 3, name = "C", value = 10 },
	},
}

-- Builds panel `key`, hides it, places it in Layout.panelFor at w x h, feeds
-- it State, then shows it: the setOpen order live.
local function openPanel(key: string, w: number, h: number): (any, Layout.Rect)
	local module = UiHarness.ui(`Panels/{key}`)
	local panel = module.new(UiHarness.root(), ctx())
	panel.frame.Visible = false
	local layoutKey = if key == "Leaderboard" then "Plot" else key
	local raw = Layout.panelFor(Layout.screen(w, h), layoutKey)
	-- UDim offsets are integers (Roblox truncates; Lune rejects fractions).
	local r = Layout.rect(math.floor(raw.x), math.floor(raw.y), math.floor(raw.w), math.floor(raw.h))
	panel.frame.Size = UDim2.fromOffset(r.w, r.h)
	if panel.layout then
		panel.layout(r)
	end
	if panel.update then
		panel.update(state())
	end
	if panel.setBoard then
		panel.setBoard(BOARD)
	end
	panel.frame.Visible = true
	return panel, r
end

describe("Layout.stackRows", function()
	it("puts row i at paddingTop + sum(previous heights + gap)", function()
		local ys, canvas = Layout.stackRows({ 84, 84, 84 }, 6)
		local top = Layout.SCROLL_LIST.paddingTop
		expect(ys[1]).toBe(top)
		expect(ys[2]).toBe(top + 84 + 6)
		expect(ys[3]).toBe(top + 2 * (84 + 6))
		expect(canvas).toBe(top + 3 * 84 + 2 * 6 + Layout.SCROLL_LIST.paddingBottom)
	end)
	it("gives an empty list just its padding", function()
		local ys, canvas = Layout.stackRows({}, 6)
		expect(#ys).toBe(0)
		expect(canvas).toBe(Layout.SCROLL_LIST.paddingTop + Layout.SCROLL_LIST.paddingBottom)
	end)
	it("is what the row checker accepts, and the checker rejects stacked rows", function()
		local ys, canvas = Layout.stackRows({ 84, 84, 84 }, 6)
		local good, stacked = {}, {}
		for i, y in ys do
			table.insert(good, { name = `r{i}`, x = 0, y = y, w = 100, h = 84 })
			-- the live v25/v26 bug: every row at the same Y
			table.insert(stacked, { name = `r{i}`, x = 0, y = 0, w = 100, h = 84 })
		end
		expect(#rowProblems(good, 6, canvas, 120)).toBe(0)
		local problems = rowProblems(stacked, 6, canvas, 120)
		expect(#problems > 0).toBe(true)
		expect(string.find(table.concat(problems, "\n"), "r1 overlaps r2", 1, true) ~= nil).toBe(true)
	end)
end)

describe("Widgets.scrollList", function()
	local Widgets = UiHarness.ui("Widgets")

	it("has no UIListLayout / UIPadding to move rows, and a fixed canvas", function()
		local list = Widgets.scrollList({ Name = "List", Parent = UiHarness.root() }, 6)
		expect(list.ClassName).toBe("ScrollingFrame")
		for _, child in list:GetChildren() do
			expect(child:IsA("UIGridStyleLayout") or child:IsA("UIPadding")).toBe(false)
		end
		expect(list.AutomaticCanvasSize).toBe(Enum.AutomaticSize.None)
		expect(list:GetAttribute("ListGap")).toBe(6)
	end)
	it("restacks after rows are added, hidden, reordered and removed", function()
		local list = Widgets.scrollList({ Name = "List", Parent = UiHarness.root() }, 6)
		local rows = Widgets.keyedList(list, function(k: string)
			return k
		end, function(k: string)
			return { instance = Widgets.create("Frame", { Name = k, Size = UDim2.new(1, -10, 0, 84) }) }
		end, function() end)
		rows.sync({ "a", "b", "c" })
		local top = Layout.SCROLL_LIST.paddingTop
		expect(list:FindFirstChild("c").Position.Y.Offset).toBe(top + 2 * 90)
		rows.sync({ "c", "a" })
		expect(list:FindFirstChild("c").Position.Y.Offset).toBe(top)
		expect(list:FindFirstChild("a").Position.Y.Offset).toBe(top + 90)
		expect(list:FindFirstChild("b")).toBeNil()
		list:FindFirstChild("c").Visible = false
		Widgets.restack(list)
		expect(list:FindFirstChild("a").Position.Y.Offset).toBe(top)
		expect(list.CanvasSize.Y.Offset).toBe(top + 84 + Layout.SCROLL_LIST.paddingBottom)
	end)
	it("is the only way panels make a scroll list (no ScrollingFrame / UIListLayout of their own)", function()
		local offenders = {}
		for _, name in fs.readDir("src/ui/Panels") do
			local src = fs.readFile(`src/ui/Panels/{name}`)
			if string.find(src, "ScrollingFrame", 1, true) or string.find(src, "UIListLayout", 1, true) then
				table.insert(offenders, name)
			end
		end
		expect(table.concat(offenders, ", ")).toBe("")
	end)
end)

local PANELS = { "Shop", "Goals", "Merge", "Dex", "Plot", "Leaderboard" }

describe("Scroll list panels (opened hidden, as setOpen did)", function()
	for _, key in PANELS do
		for _, vp in VIEWPORTS do
			it(`{key} rows are vertically distinct and inside the canvas at {vp[1]}x{vp[2]}`, function()
				local panel, r = openPanel(key, vp[1], vp[2])
				local g = geometry(panel, r)
				expect(#g.rows >= 3).toBe(true)
				expect(type(g.gap)).toBe("number")
				local problems = rowProblems(g.rows, g.gap, g.canvasH, g.listW)
				expect(table.concat(problems, "\n")).toBe("")
				expect(g.canvasH).toBe(g.rows[#g.rows].y + g.rows[#g.rows].h + Layout.SCROLL_LIST.paddingBottom)
			end)
		end
	end

	it("Shop lists every catalogue item as its own 84px row", function()
		local panel, r = openPanel("Shop", 390, 844)
		local g = geometry(panel, r)
		expect(#g.rows).toBe(#ShopCatalog.views(state(), Remotes.ACTIONS, Config))
		expect(#g.rows >= 5).toBe(true)
		for i, row in g.rows do
			expect(row.h).toBe(84)
			if i > 1 then
				expect(row.y - g.rows[i - 1].y).toBe(84 + g.gap)
			end
		end
	end)

	it("Goals keeps rows apart after a second update (re-sync while open)", function()
		local panel, r = openPanel("Goals", 1366, 768)
		panel.update(state())
		local g = geometry(panel, r)
		expect(table.concat(rowProblems(g.rows, g.gap, g.canvasH, g.listW), "\n")).toBe("")
	end)
end)
