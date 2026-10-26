--!strict
-- v29 menu gaps: Esc / gamepad B close the Daily popup, menu cards are as tall
-- as their measured content (clamped to the viewport), the SlimeDex body's
-- blocks do not overlap, and Dex previews are virtualised to the scroll window.
local roblox = require("@lune/roblox") :: any

local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Fixtures = require("../Fixtures")
local Genome = require("../../src/shared/Genome")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local Remotes = require("../../src/shared/Remotes")
local SpeciesDex = require("../../src/shared/SpeciesDex")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local Enum, UDim2, Vector2 = roblox.Enum, roblox.UDim2, roblox.Vector2
local SlimePreview = UiHarness.ui("SlimePreview")
local MenuClose = UiHarness.ui("MenuClose")
local Widgets = UiHarness.ui("Widgets")

local DEX = Fixtures.dex({ "gummy" })

local function ctx(): any
	return {
		Config = Config,
		Constants = Constants,
		Genome = Genome,
		actions = Remotes.ACTIONS,
		send = function() end,
		serverNow = function()
			return 0
		end,
		playerName = function()
			return "Tester"
		end,
		toast = function() end,
	}
end

describe("Esc / B closes the Daily popup", function()
	-- Mirrors init.client: the popup wins over the open card.
	local function client(dailyOpen: boolean, menu: string?)
		local c: any = { daily = dailyOpen, menu = menu, handler = nil }
		MenuClose.bind(
			{
				BindAction = function(_: any, _name: string, handler: any)
					c.handler = handler
				end,
			},
			true,
			function()
				return MenuClose.topKey(c.menu, c.daily)
			end,
			function()
				if c.daily then
					c.daily = false
				else
					c.menu = nil
				end
			end
		)
		return c
	end

	it("closes the Daily popup alone and sinks the key", function()
		local c = client(true, nil)
		expect(c.handler("CloseMenu", Enum.UserInputState.Begin)).toBe(Enum.ContextActionResult.Sink)
		expect(c.daily).toBe(false)
	end)
	it("closes the popup first when a card is open under it, then the card", function()
		local c = client(true, "WorldShop")
		c.handler("CloseMenu", Enum.UserInputState.Begin)
		expect(c.daily).toBe(false)
		expect(c.menu).toBe("WorldShop")
		c.handler("CloseMenu", Enum.UserInputState.Begin)
		expect(c.menu).toBe(nil)
	end)
	it("closes the bag panel when no card or popup is open", function()
		expect(MenuClose.topKey(nil, false, true)).toBe(MenuClose.BAG)
		expect(MenuClose.topKey("WorldShop", false, true)).toBe("WorldShop")
		expect(MenuClose.topKey(nil, true, true)).toBe("Daily")
		expect(MenuClose.topKey(nil, false, false)).toBe(nil)
	end)
	it("still passes the key on with nothing open", function()
		local c = client(false, nil)
		expect(c.handler("CloseMenu", Enum.UserInputState.Begin)).toBe(Enum.ContextActionResult.Pass)
	end)
end)

-- A fake body: `rows` fixed rows of 40 px.
local function bodyWith(rows: number): any
	local body = UiHarness.Instance.new("Frame")
	for i = 1, rows do
		local row = UiHarness.Instance.new("Frame")
		row.Position = UDim2.fromOffset(0, (i - 1) * 40)
		row.Size = UDim2.fromOffset(100, 40)
		row.Parent = body
	end
	return body
end

describe("content-sized menu cards", function()
	it("Widgets.contentHeight measures fixed rows, lists and bottom-pinned buttons", function()
		expect(Widgets.contentHeight(bodyWith(3))).toBe(120)
		local body = bodyWith(2)
		local list = Widgets.scrollList({ Name = "List", Position = UDim2.fromOffset(0, 80), Parent = body }, 4)
		list.CanvasSize = UDim2.fromOffset(0, 300)
		expect(Widgets.contentHeight(body)).toBe(380)
		local button = UiHarness.Instance.new("Frame")
		button.Position = UDim2.new(0, 0, 1, -48)
		button.Size = UDim2.fromOffset(100, 40)
		button.Parent = body
		expect(Widgets.contentHeight(body)).toBe(428)
	end)
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		it(`{vp.name}: card height follows content and stays on screen`, function()
			local screen = Layout.screen(vp.w, vp.h)
			local back = screen.panel
			local last = 0
			for _, rows in { 1, 3, 6, 40 } do
				local content = Widgets.contentHeight(bodyWith(rows))
				local card = Layout.panelFor(screen, "WorldShop", content)
				local want = math.min(Layout.cardHeight(content), back.h)
				expect(card.h).toBe(want)
				expect(card.h >= last).toBe(true)
				last = card.h
				if Layout.cardHeight(content) <= back.h then
					expect(card.h >= content + Layout.PANEL_CHROME.header).toBe(true)
				end
				local check = LayoutAssert.new(vp.name, screen)
				check.inside("card", card, "backdrop", back)
				check.onScreen("card", card)
				expect(#check.problems).toBe(0)
			end
			expect(Layout.panelFor(screen, "WorldShop", 100).h < Layout.panelFor(screen, "WorldShop", 400).h).toBe(
				Layout.cardHeight(100) < back.h and Layout.cardHeight(400) > Layout.cardHeight(100)
			)
		end)
		it(`{vp.name}: real Codes, Guide and Dex bodies size their card to what they hold`, function()
			local screen = Layout.screen(vp.w, vp.h)
			for _, name in { "Codes", "Guide", "Dex" } do
				local panel = UiHarness.ui(`Panels/{name}`).new(UiHarness.root(), ctx())
				if name == "Dex" then
					panel.update({ dex = DEX })
					panel.setOpen(true)
				end
				local content = Widgets.contentHeight(UiHarness.find(panel.frame, "Body"))
				expect(content > 0).toBe(true)
				local card = Layout.panelFor(screen, name, content)
				local check = LayoutAssert.new(vp.name, screen)
				check.inside(name, card, "backdrop", screen.panel)
				expect(#check.problems).toBe(0)
				if Layout.cardHeight(content) <= screen.panel.h then
					expect(Layout.panelBody(card).h >= content).toBe(true)
				end
			end
		end)
	end
end)

local function openDex(w: number, h: number, dex: any, extra: { [string]: any }?): any
	local panel = UiHarness.ui("Panels/Dex").new(UiHarness.root(), ctx())
	panel.frame.Visible = false
	local raw = Layout.panelFor(Layout.screen(w, h), "Dex")
	local r = Layout.rect(math.floor(raw.x), math.floor(raw.y), math.floor(raw.w), math.floor(raw.h))
	panel.frame.Size = UDim2.fromOffset(r.w, r.h)
	panel.layout(r)
	local state: { [string]: any } = { dex = dex }
	for k, v in extra or {} do
		state[k] = v
	end
	panel.update(state)
	panel.setOpen(true)
	panel.frame.Visible = true
	return panel
end

local function rect(inst: any): Layout.Rect
	return Layout.rect(inst.Position.X.Offset, inst.Position.Y.Offset, inst.Size.X.Offset, inst.Size.Y.Offset)
end

-- The last spawn species: the bottom of the Fountain tab's grid.
local LAST_SPAWN: string = SpeciesDex.ENTRIES[1].id
do
	for _, entry in SpeciesDex.ENTRIES do
		if entry.kind == "spawn" then
			LAST_SPAWN = entry.id
		end
	end
end

describe("SlimeDex body", function()
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		it(`{vp.name}: chips, tabs, reward line, grid and pane do not overlap and stay in the card`, function()
			local panel = openDex(vp.w, vp.h, DEX, {
				dexRewards = { { ladder = "species", count = 8, reward = 1000, bonus = 0.02, claimed = false } },
			})
			local check = LayoutAssert.new(vp.name, Layout.screen(vp.w, vp.h))
			local body = UiHarness.find(panel.frame, "Body")
			local inner = Layout.panelBody(Layout.rect(0, 0, panel.frame.Size.X.Offset, panel.frame.Size.Y.Offset))
			local shown = {}
			for _, name in { "Tab_spawn", "Tab_hybrid", "Tab_boss", "Reward", "List", "Pane" } do
				local item = UiHarness.find(body, name)
				if item.Visible then
					local r = rect(item)
					expect(r.x >= 0 and r.y >= 0).toBe(true)
					expect(r.x + r.w <= inner.w + 1e-6).toBe(true)
					expect(r.y + r.h <= inner.h + 1e-6).toBe(true)
					table.insert(shown, { name, r })
				end
			end
			for i = 1, #shown do
				for j = i + 1, #shown do
					check.noOverlap(shown[i][1], shown[i][2], shown[j][1], shown[j][2])
				end
			end
			-- The band chips sit between the title text and the close X.
			local close = UiHarness.find(panel.frame, "Close")
			local closeLeft = panel.frame.Size.X.Offset - Layout.PANEL_CHROME.closeInset - close.Size.X.Offset
			local titleRight = Layout.PANEL_CHROME.pad
				+ Layout.PANEL_CHROME.icon
				+ 10
				+ Layout.lineWidth("SlimeDex", Layout.PANEL_CHROME.titleSize, true)
			for _, name in { "Count", "Percent" } do
				local chip = UiHarness.find(panel.frame, name)
				local right = panel.frame.Size.X.Offset + chip.Position.X.Offset
				expect(right <= closeLeft + 1e-6).toBe(true)
				expect(right - chip.Size.X.Offset >= titleRight).toBe(true)
			end
			expect(#check.problems).toBe(0)
		end)
	end
	it("the reward line names the next milestone and fills toward it", function()
		local panel = openDex(1920, 1080, Fixtures.dex({ "gummy", "mochi" }), {
			dexRewards = {
				{ ladder = "species", count = 1, reward = 1000, bonus = 0.02, claimed = true },
				{ ladder = "species", count = 8, reward = 2500, bonus = 0.03, claimed = false },
			},
		})
		local line = UiHarness.find(panel.frame, "Reward")
		expect(line.Visible).toBe(true)
		expect(UiHarness.find(line, "RewardText").Text).toBe("Next reward at 8: +$2.5K and +3% income")
		expect(UiHarness.find(line, "RewardCount").Text).toBe("2/8")
		expect(UiHarness.find(UiHarness.find(line, "RewardBar"), "Fill").Size.X.Scale).toBeCloseTo(2 / 8)
	end)
	it("hides the reward line on a server without dex rewards and moves the grid up", function()
		local panel = openDex(1920, 1080, DEX)
		expect(UiHarness.find(panel.frame, "Reward").Visible).toBe(false)
		local list = UiHarness.find(panel.frame, "List")
		expect(list.Position.Y.Offset).toBe(UiHarness.ui("SlimeDex").contentTop(false))
	end)
end)

describe("SlimeDex virtualised previews", function()
	local function previewLive(card: any): boolean
		local preview = UiHarness.find(card, "Preview")
		return preview.Visible and UiHarness.find(preview, "World") ~= nil
	end

	it("the last Fountain card scrolled into view gets a live preview; live count stays <= cap", function()
		local panel = openDex(390, 844, DEX)
		local list = UiHarness.find(panel.frame, "List")
		local card = UiHarness.find(list, LAST_SPAWN)
		expect(previewLive(card)).toBe(false) -- off screen at the bottom: no viewport
		expect(panel.liveCount() <= SlimePreview.MAX_LIVE).toBe(true)
		list.CanvasPosition = Vector2.new(0, card.Parent.Position.Y.Offset - 40)
		panel.refreshPreviews()
		expect(previewLive(card)).toBe(true)
		expect(panel.liveCount() <= SlimePreview.MAX_LIVE).toBe(true)
		-- recycled: the top cards gave their previews back
		expect(previewLive(UiHarness.find(list, SpeciesDex.ENTRIES[1].id))).toBe(false)
	end)
	it("never mounts more than MAX_LIVE on any tab, scrolled anywhere", function()
		local panel = openDex(1920, 1080, DEX)
		for _, tab in { "spawn", "hybrid", "boss", "event" } do
			panel.selectTab(tab)
			local list = UiHarness.find(panel.frame, if tab == "hybrid" then "Recipes" else "List")
			for y = 0, list.CanvasSize.Y.Offset, 300 do
				list.CanvasPosition = Vector2.new(0, y)
				panel.refreshPreviews()
				expect(panel.liveCount() <= SlimePreview.MAX_LIVE).toBe(true)
			end
		end
	end)
end)
