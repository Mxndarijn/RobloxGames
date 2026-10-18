--!strict
-- SlimeDex cards (src/ui/SlimeDex.luau) and the real SlimeDex panel built under tests/ui/UiHarness.luau:
-- one card per species grouped by rarity, silhouettes with hints and ingredient slots for what is not found,
-- stamp dots, a grid that fits the panel width, and the close X on every menu.
local roblox = require("@lune/roblox") :: any

local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Fixtures = require("../Fixtures")
local Genome = require("../../src/shared/Genome")
local Layout = require("../../src/ui/Layout")
local Remotes = require("../../src/shared/Remotes")
local SlimeDex = require("../../src/ui/SlimeDex")
local SlimeLooks = require("../../src/shared/SlimeLooks")
local SlimeRoster = require("../../src/shared/SlimeRoster")
local SpeciesDex = require("../../src/shared/SpeciesDex")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local UDim2 = roblox.UDim2

local RECIPES = {
	soda = { inputs = { "bubbles", "gummy", "mochi" }, hint = "Fizzy, chewy and soft." },
}
local SOURCES = Fixtures.dexSources(RECIPES, { glitch = 1760918400 })
local DEX = Fixtures.dex({ "gummy", "mochi", "bumble" }, { "gummy:None", "gummy:Glow", "gummy:Solar" }, SOURCES)

local function ctx(): any
	return {
		Config = Config,
		Constants = Constants,
		Genome = Genome,
		SlimeRoster = SlimeRoster,
		SlimeLooks = SlimeLooks,
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

local function lookup(id: string): (string?, { number }?)
	local entry, look = SlimeRoster.get(id), SlimeLooks.get(id)
	return if entry then entry.name else nil, if look then look.color else nil
end

local function cardOf(cards: { SlimeDex.Card }, id: string): SlimeDex.Card
	for _, card in cards do
		if card.key == id then
			return card
		end
	end
	error(`no card {id}`)
end

describe("SlimeDex.cards", function()
	it("has one card per Dex entry and bonus entry, in State order", function()
		local cards = SlimeDex.cards(DEX, Config, lookup)
		expect(#cards).toBe(SpeciesDex.TOTAL + #SpeciesDex.BONUS)
		expect(cards[1].key).toBe(SpeciesDex.ENTRIES[1].id)
		expect(cards[#cards].kind).toBe("event")
	end)
	it("a found species shows its name, rarity colour and lit stamps; gold stamps come separately", function()
		local gummy = cardOf(SlimeDex.cards(DEX, Config, lookup), "gummy")
		expect(gummy.found).toBe(true)
		expect(gummy.title).toBe("Gummy")
		expect(gummy.color).toBe(Config.RARITIES[1].color)
		expect(#gummy.stamps).toBe(#SpeciesDex.CORE_STAMPS)
		local lit = {}
		for _, stamp in gummy.stamps do
			if stamp.on then
				table.insert(lit, stamp.mutation)
			end
		end
		expect(table.concat(lit, ",")).toBe("None,Glow")
		expect(#gummy.gold).toBe(1)
		expect(gummy.gold[1].mutation).toBe("Solar")
		-- Lava is shown as Syrup on the dot's label.
		local lava = gummy.stamps[table.find(SpeciesDex.CORE_STAMPS, "Lava") :: number]
		expect(lava.label).toBe("Syrup")
		expect(lava.on).toBe(false)
	end)
	it("an unfound species is a silhouette named ???", function()
		local moo = cardOf(SlimeDex.cards(DEX, Config, lookup), "moo")
		expect(moo.found).toBe(false)
		expect(moo.title).toBe("???")
		expect(moo.badge).toBeNil()
	end)
	it("a hybrid shows its hint, a Merge-only badge and fills the ingredient slots it has found", function()
		local soda = cardOf(SlimeDex.cards(DEX, Config, lookup), "soda")
		expect(soda.found).toBe(false)
		expect(soda.title).toBe("???")
		expect(soda.badge).toBe("Merge-only")
		expect(soda.hint).toBe("Fizzy, chewy and soft.")
		local slots = soda.slots :: { SlimeDex.Slot }
		expect(#slots).toBe(3)
		expect(slots[1].species).toBeNil() -- bubbles: not found
		expect(slots[1].label).toBe("?")
		expect(slots[2].species).toBe("gummy")
		expect(slots[2].label).toBe("Gummy")
		expect(slots[3].species).toBe("mochi")
	end)
	it("a known recipe names the hybrid before it is crafted", function()
		local dex = Fixtures.dex({ "bubbles", "gummy", "mochi" }, nil, SOURCES)
		local soda = cardOf(SlimeDex.cards(dex, Config, lookup), "soda")
		expect(soda.found).toBe(false)
		expect(soda.title).toBe("Soda Pop")
	end)
	it("bosses say how to get them and carry no stamps; event Secrets are a bonus section", function()
		local cards = SlimeDex.cards(DEX, Config, lookup)
		local boss = cardOf(cards, "goozilla")
		expect(boss.hint).toBe(SpeciesDex.BOSS_HINT)
		expect(boss.badge).toBe("Boss")
		expect(#boss.stamps).toBe(0)
		local glitch = cardOf(cards, "glitch")
		expect(glitch.badge).toBe("Event")
		expect(#glitch.stamps).toBe(0)
	end)
	it("survives a missing or junk State.dex", function()
		expect(#SlimeDex.cards(nil, Config)).toBe(0)
		expect(#SlimeDex.cards({ entries = { "junk", { id = 3 }, { id = "moo", tier = 99 } } }, Config)).toBe(0)
	end)
end)

describe("SlimeDex.grid / lines", function()
	it("fits as many cards as the width allows, one column on a narrow phone", function()
		expect(SlimeDex.grid(140).columns).toBe(1)
		expect(SlimeDex.grid(SlimeDex.CARD.minW * 2 + SlimeDex.CARD.gap).columns).toBe(2)
		expect(SlimeDex.grid(5000).columns).toBe(SlimeDex.CARD.maxColumns)
		for _, w in { 140, 330, 480, 900, 1500 } do
			local g = SlimeDex.grid(w)
			expect(g.columns * g.cardW + (g.columns - 1) * g.gap <= math.max(w, g.cardW)).toBe(true)
		end
	end)
	it("groups cards under one header per rarity with its found count, event Secrets last", function()
		local cards = SlimeDex.cards(DEX, Config, lookup)
		local lines = SlimeDex.lines(cards, 3, Config)
		expect(lines[1].kind).toBe("header")
		expect(lines[1].title).toBe(Config.RARITIES[1].name)
		expect(lines[1].detail).toBe(`2 / {SpeciesDex.tierSize(1)}`)
		local headers, placed = {}, 0
		for _, line in lines do
			if line.kind == "header" then
				table.insert(headers, line.tier)
			else
				local n = #(line.cards :: { SlimeDex.Card })
				expect(n >= 1 and n <= 3).toBe(true)
				placed += n
			end
		end
		expect(placed).toBe(#cards)
		expect(#headers).toBe(Config.MAX_TIER + 1)
		expect(headers[#headers]).toBe(SlimeDex.BONUS_TIER)
	end)
end)

describe("SlimeDex.summary", function()
	it("shows species, stamps, gold and bonus Secrets", function()
		local s = SlimeDex.summary(DEX)
		expect(s.count).toBe(`Species 3 / {SpeciesDex.TOTAL}`)
		expect(s.percent).toBe(`{math.floor(3 / SpeciesDex.TOTAL * 100)}%`)
		expect(s.stamps).toBe(`Stamps 2 / {SpeciesDex.STAMP_TOTAL} · 1 gold · Secrets 0 / {#SpeciesDex.BONUS}`)
		expect(SlimeDex.summary(nil).percent).toBe("0%")
	end)
end)

-- The SlimeDex panel built for real, sized like a full-window menu (init.client applyLayout: frame size,
-- then panel.layout).
local function openDex(w: number, h: number, dex: any, extra: { [string]: any }?): (any, Layout.Rect)
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
	panel.setOpen(true) -- rows are only built while open
	panel.frame.Visible = true
	return panel, r
end

local function card(panel: any, id: string): any
	return UiHarness.find(UiHarness.find(panel.frame, "List"), id)
end

describe("SlimeDex panel", function()
	it("is titled SlimeDex and shows the species and stamp counts", function()
		local panel = openDex(390, 844, DEX)
		expect(UiHarness.find(panel.frame, "Title").Text).toBe("SlimeDex")
		expect(UiHarness.find(panel.frame, "Count").Text).toBe(`Species 3 / {SpeciesDex.TOTAL}`)
		expect(string.find(UiHarness.find(panel.frame, "Caption").Text, "Stamps 2", 1, true) ~= nil).toBe(true)
	end)
	it("a found card has its name and lit stamp dots; an unfound one is ??? with a ? glyph", function()
		local panel = openDex(1920, 1080, DEX)
		local gummy = card(panel, "gummy")
		expect(gummy:GetAttribute("Found")).toBe(true)
		expect(UiHarness.find(gummy, "Title").Text).toBe("Gummy")
		local stamps = UiHarness.find(gummy, "Stamps")
		expect(UiHarness.find(stamps, "Stamp1"):GetAttribute("On")).toBe(true)
		expect(UiHarness.find(stamps, "Stamp3"):GetAttribute("On")).toBe(false)
		expect(UiHarness.find(stamps, "Gold").Visible).toBe(true)
		local moo = card(panel, "moo")
		expect(moo:GetAttribute("Found")).toBe(false)
		expect(UiHarness.find(moo, "Title").Text).toBe("???")
		local image = UiHarness.find(moo, "Image")
		expect(image.Size.X.Offset).toBe(image.Size.Y.Offset) -- square preview box
	end)
	it("a hybrid card shows the badge, the hint and three slots, filled for found ingredients", function()
		local panel = openDex(1920, 1080, DEX)
		local soda = card(panel, "soda")
		expect(UiHarness.find(soda, "Badge").Visible).toBe(true)
		expect(UiHarness.find(soda, "Badge").Text).toBe("Merge-only")
		expect(UiHarness.find(soda, "Hint").Text).toBe("Fizzy, chewy and soft.")
		local slots = UiHarness.find(soda, "Slots")
		expect(slots.Visible).toBe(true)
		expect(UiHarness.find(slots, "Slot1").Text).toBe("?")
		expect(UiHarness.find(slots, "Slot2"):GetAttribute("Species")).toBe("gummy")
		expect(UiHarness.find(card(panel, "gummy"), "Slots").Visible).toBe(false)
	end)
	it("stacks lines by Layout.stackRows, keeps every card inside its line and grows the canvas", function()
		local panel = openDex(390, 844, DEX)
		local list = UiHarness.find(panel.frame, "List")
		local lines = {}
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") and child.Visible then
				table.insert(lines, child)
			end
		end
		table.sort(lines, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		local heights = {}
		for i, line in lines do
			heights[i] = line.Size.Y.Offset
		end
		local ys, canvas = Layout.stackRows(heights, list:GetAttribute("ListGap"))
		local cards = 0
		for i, line in lines do
			expect(line.Position.Y.Offset).toBe(ys[i])
			for _, c in line:GetChildren() do
				if c:IsA("Frame") and c:GetAttribute("Found") ~= nil then
					cards += 1
					expect(c.Position.Y.Offset).toBe(0)
					expect(c.Size.Y.Offset <= line.Size.Y.Offset).toBe(true)
				end
			end
		end
		expect(cards).toBe(SpeciesDex.TOTAL + #SpeciesDex.BONUS)
		expect(list.CanvasSize.Y.Offset).toBe(canvas)
		local body = Layout.panelBody(Layout.panelFor(Layout.screen(390, 844), "Dex"))
		expect(canvas > body.h).toBe(true) -- taller than the panel: it scrolls
	end)
	for _, vp in { { 390, 844 }, { 844, 390 }, { 1024, 768 }, { 1920, 1080 } } do
		it(`{vp[1]}x{vp[2]}: cards of a line sit side by side inside the list width`, function()
			local panel, r = openDex(vp[1], vp[2], DEX)
			local g = panel.grid()
			local body = Layout.panelBody(r)
			expect(g.columns >= 1).toBe(true)
			local line = UiHarness.find(UiHarness.find(panel.frame, "List"), "cards:1:1")
			local right = 0
			for _, c in line:GetChildren() do
				if c:IsA("Frame") and c:GetAttribute("Found") ~= nil then
					right = math.max(right, c.Position.X.Offset + c.Size.X.Offset)
				end
			end
			expect(right <= body.w).toBe(true)
			if vp[1] < 500 then
				expect(g.columns <= 2).toBe(true) -- a phone shows one or two cards per line
			end
		end)
	end
end)

describe("SpeciesModel (the card's species mesh)", function()
	it("clones the server-replicated kit as a white, anchored Model; nil while the kit is missing", function()
		local SpeciesModel = UiHarness.ui("SpeciesModel")
		local folder = UiHarness.Instance.new("Folder")
		local kit = UiHarness.Instance.new("Part")
		kit.Name = "slime_moo"
		kit.Color = roblox.Color3.new(1, 0, 0)
		kit.Parent = folder
		local present = true
		local build = SpeciesModel.builder(function()
			return if present then folder else nil
		end, 180)
		local model = build("moo")
		expect(model ~= nil).toBe(true)
		local part = model:FindFirstChild("Mesh")
		expect(part.Anchored).toBe(true)
		expect(part.Color).toBe(roblox.Color3.new(1, 1, 1))
		expect(model.PrimaryPart).toBe(part)
		expect(kit.Parent).toBe(folder) -- the template stays
		expect(build("gummy")).toBeNil()
		present = false
		expect(build("moo")).toBeNil()
	end)
end)

describe("SlimeDex.header (short panel bodies)", function()
	it("keeps the bar and rewards on a tall body", function()
		local h = SlimeDex.header(700, true)
		expect(h.bar and h.rewards).toBe(true)
		expect(h.rewardsY).toBe(SlimeDex.HEADER.bar)
		expect(h.listTop).toBe(SlimeDex.HEADER.bar + SlimeDex.HEADER.gap + SlimeDex.HEADER.rewards)
		expect(SlimeDex.header(700, false).listTop).toBe(SlimeDex.HEADER.bar + SlimeDex.HEADER.gap)
	end)
	it("drops the rewards, then the bar, until the list keeps MIN_LIST", function()
		local noRewards = SlimeDex.header(160, true)
		expect(noRewards.rewards).toBe(false)
		expect(noRewards.bar).toBe(true)
		local minimal = SlimeDex.header(131, true) -- the 844x332 body
		expect(minimal.bar).toBe(false)
		expect(131 - minimal.listTop >= SlimeDex.MIN_LIST).toBe(true)
	end)
	for _, vp in { { 390, 844 }, { 844, 390 }, { 844, 332 }, { 1024, 768 }, { 1366, 768 }, { 1920, 1080 } } do
		it(`{vp[1]}x{vp[2]}: the real panel's list is at least MIN_LIST tall`, function()
			local panel, r = openDex(vp[1], vp[2], DEX, {
				dexRewards = { { ladder = "species", count = 8, reward = 1000, bonus = 0.02, claimed = false } },
			})
			local list = UiHarness.find(panel.frame, "List")
			local bodyH = Layout.panelBody(r).h
			local listH = list.Size.Y.Scale * bodyH + list.Size.Y.Offset
			expect(listH >= SlimeDex.MIN_LIST).toBe(true)
			expect(list.Position.Y.Offset + listH <= bodyH + 1e-6).toBe(true)
			local rewards = UiHarness.find(panel.frame, "Rewards")
			if rewards.Visible then
				expect(rewards.Position.Y.Offset + rewards.Size.Y.Offset <= list.Position.Y.Offset).toBe(true)
			end
		end)
	end
end)

describe("menu close button (Widgets.panel)", function()
	for _, name in { "Plot", "Merge", "Shop", "Rebirth", "Goals", "Dex", "Leaderboard" } do
		it(`{name}: an X top-right, MIN_TOUCH_DESIGN square, exposed as panel.close`, function()
			local panel = UiHarness.ui(`Panels/{name}`).new(UiHarness.root(), ctx())
			local close = panel.close
			expect(close ~= nil).toBe(true)
			expect(close.ClassName).toBe("TextButton")
			expect(close.Parent).toBe(panel.frame)
			expect(close.Text).toBe("X")
			expect(close.Size.X.Offset).toBe(Layout.MIN_TOUCH_DESIGN)
			expect(close.Size.Y.Offset).toBe(Layout.MIN_TOUCH_DESIGN)
			expect(close.AnchorPoint.X).toBe(1)
			expect(close.Position.X.Scale).toBe(1)
			expect(close.Position.X.Offset).toBe(-Layout.PANEL_CHROME.closeInset)
			expect(close.Position.Y.Offset).toBe(Layout.PANEL_CHROME.closeInset)
			local title = panel.frame:FindFirstChild("Title")
			local reserve = Layout.PANEL_CHROME.close + Layout.PANEL_CHROME.closeInset * 2
			expect(title.Size.X.Offset <= -reserve).toBe(true) -- title stops before the X
		end)
	end
end)
