--!strict
-- SlimeDex cards (src/ui/SlimeDex.luau) and the real SlimeDex panel built under tests/ui/UiHarness.luau:
-- one card per species grouped by rarity, silhouettes with hints and ingredient slots for what is not found,
-- a grid that fits the panel width, and the close X on every menu.
local roblox = require("@lune/roblox") :: any

local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Fixtures = require("../Fixtures")
local Genome = require("../../src/shared/Genome")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
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
local DEX = Fixtures.dex({ "gummy", "mochi", "bumble" }, SOURCES)

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
	it("a found species shows its name and rarity colour", function()
		local gummy = cardOf(SlimeDex.cards(DEX, Config, lookup), "gummy")
		expect(gummy.found).toBe(true)
		expect(gummy.title).toBe("Gummy")
		expect(gummy.color).toBe(Config.RARITIES[1].color)
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
		local dex = Fixtures.dex({ "bubbles", "gummy", "mochi" }, SOURCES)
		local soda = cardOf(SlimeDex.cards(dex, Config, lookup), "soda")
		expect(soda.found).toBe(false)
		expect(soda.title).toBe("Soda Pop")
	end)
	it("bosses say how to get them; event Secrets are a bonus section", function()
		local cards = SlimeDex.cards(DEX, Config, lookup)
		local boss = cardOf(cards, "goozilla")
		expect(boss.hint).toBe(SpeciesDex.BOSS_HINT)
		expect(boss.badge).toBe("Boss")
		local glitch = cardOf(cards, "glitch")
		expect(glitch.badge).toBe("Event")
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
		expect(lines[1].detail).toBe(`2/{SpeciesDex.tierSize(1)} found`)
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
	it("gives the species and bonus Secrets chips", function()
		local s = SlimeDex.summary(DEX)
		expect(s.count).toBe(`Species 3/{SpeciesDex.TOTAL}`)
		expect(s.percent).toBe(`{math.floor(3 / SpeciesDex.TOTAL * 100)}%`)
		expect(s.secrets).toBe(`Secrets 0/{#SpeciesDex.BONUS}`)
		expect(SlimeDex.summary({ found = 0, total = 50 }).secrets).toBeNil()
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
	it("is titled SlimeDex and shows the species and Secrets counts", function()
		local panel = openDex(390, 844, DEX)
		expect(UiHarness.find(panel.frame, "Title").Text).toBe("SlimeDex")
		expect(UiHarness.find(panel.frame, "Count").Text).toBe(`Species 3/{SpeciesDex.TOTAL}`)
		expect(UiHarness.find(panel.frame, "Secrets").Text).toBe(`Secrets 0/{#SpeciesDex.BONUS}`)
	end)
	it("a found card has its name; an unfound one is ??? with a ? glyph", function()
		local panel = openDex(1920, 1080, DEX)
		local gummy = card(panel, "gummy")
		expect(gummy:GetAttribute("Found")).toBe(true)
		expect(UiHarness.find(gummy, "Title").Text).toBe("Gummy")
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

-- Widths (px) of percent texts in Theme.Font (FredokaOne), from Studio TextService:GetTextSize.
local STUDIO_PERCENT_WIDTHS = {
	{ "0%", 26, 33 },
	{ "8%", 26, 32 },
	{ "42%", 26, 46 },
	{ "100%", 26, 56 },
	{ "0%", 56, 68 },
	{ "8%", 56, 66 },
	{ "42%", 56, 96 },
	{ "100%", 56, 116 },
}

-- The percent label is at least as wide and as tall as its text, and the first chip starts after it.
local function expectPercentFits(panel: any)
	local percent = UiHarness.find(panel.frame, "Percent")
	expect(percent.Size.X.Offset >= SlimeDex.percentWidth(percent.Text, percent.TextSize)).toBe(true)
	expect(percent.Size.Y.Offset >= percent.TextSize).toBe(true)
	local count = UiHarness.find(panel.frame, "Count")
	expect(count.Position.X.Offset >= percent.Size.X.Offset).toBe(true)
end

-- Every gate and phone size, once each.
local DEX_VIEWPORTS: { { name: string, w: number, h: number } } = {}
do
	local seen = {}
	for _, list in { LayoutAssert.GATE_VIEWPORTS, LayoutAssert.PHONE_VIEWPORTS } do
		for _, vp in list do
			if not seen[vp.name] then
				seen[vp.name] = true
				table.insert(DEX_VIEWPORTS, vp)
			end
		end
	end
end

-- Body height below every real screen's (the smallest, 844x332, is about 300): the list would drop under
-- MIN_LIST with the full header.
local SHORT_BODY = 131

describe("SlimeDex.header (short panel bodies)", function()
	it("keeps the big percent and every chip row on a tall body", function()
		local H = SlimeDex.HEADER
		local one = SlimeDex.header(700, 1)
		expect(one.compact).toBe(false)
		expect(one.listTop).toBe(H.percent + H.gap)
		local two = SlimeDex.header(700, true)
		expect(two.listTop).toBe(math.max(H.percent, H.chip * 2 + H.chipGap) + H.gap)
		expect(SlimeDex.header(700, false).listTop).toBe(H.percent + H.gap)
	end)
	it("turns compact (one chip row) when the list would drop under MIN_LIST", function()
		local minimal = SlimeDex.header(SHORT_BODY, true)
		expect(minimal.compact).toBe(true)
		expect(SHORT_BODY - minimal.listTop >= SlimeDex.MIN_LIST).toBe(true)
		expect(SlimeDex.header(SHORT_BODY, false).compact).toBe(true)
	end)
	it("chipRows wraps chips that do not fit and hides the ones past maxRows", function()
		local spots, rows = SlimeDex.chipRows({ 100, 100, 100 }, 50, 250, 5)
		expect(rows).toBe(3)
		expect(spots[1].x).toBe(50)
		expect(spots[2].x).toBe(50) -- 50 + 100 + 6 + 100 > 250: next row
		expect(spots[2].y).toBe(SlimeDex.HEADER.chip + SlimeDex.HEADER.chipGap)
		local capped = SlimeDex.chipRows({ 100, 100, 100 }, 50, 250, 1)
		expect(capped[1].visible).toBe(true)
		expect(capped[2].visible).toBe(false)
	end)
	for _, vp in DEX_VIEWPORTS do
		it(
			`{vp.name}: the real panel keeps the big percent ("100%" fits) and a MIN_LIST tall list under the chips`,
			function()
				local panel, r = openDex(vp.w, vp.h, DEX, {
					dexRewards = { { ladder = "species", count = 8, reward = 1000, bonus = 0.02, claimed = false } },
				})
				local list = UiHarness.find(panel.frame, "List")
				local body = Layout.panelBody(r)
				local bodyH = body.h
				local listH = list.Size.Y.Scale * bodyH + list.Size.Y.Offset
				expect(listH >= SlimeDex.MIN_LIST).toBe(true)
				expect(list.Position.Y.Offset + listH <= bodyH + 1e-6).toBe(true)
				for _, name in { "Percent", "Count", "Secrets" } do
					local item = UiHarness.find(panel.frame, name)
					if item.Visible then
						expect(item.Position.Y.Offset + item.Size.Y.Offset <= list.Position.Y.Offset).toBe(true)
						expect(item.Position.X.Offset + item.Size.X.Offset <= body.w).toBe(true)
					end
				end
				expect(UiHarness.find(panel.frame, "Percent").Size.Y.Offset).toBe(SlimeDex.HEADER.percent)
				expectPercentFits(panel)
			end
		)
	end
	it("percentWidth covers Studio's measured widths, at most 6 px wider", function()
		for _, m in STUDIO_PERCENT_WIDTHS do
			local w = SlimeDex.percentWidth(m[1], m[2])
			expect(w >= m[3]).toBe(true)
			expect(w <= m[3] + 6).toBe(true)
		end
	end)
	it("the chips sit right after the percent text: closer at 0% than at 100%", function()
		local low = openDex(1920, 1080, { found = 0, total = 50 })
		local full = openDex(1920, 1080, { found = 50, total = 50 })
		expect(UiHarness.find(low.frame, "Percent").Text).toBe("0%")
		expect(UiHarness.find(full.frame, "Percent").Text).toBe("100%")
		expectPercentFits(low)
		expectPercentFits(full)
		local lowX = UiHarness.find(low.frame, "Count").Position.X.Offset
		local fullX = UiHarness.find(full.frame, "Count").Position.X.Offset
		expect(lowX < fullX).toBe(true)
		expect(lowX <= SlimeDex.percentWidth("0%", UiHarness.find(low.frame, "Percent").TextSize) + 16).toBe(true)
	end)
	it('a body shorter than any real screen gets the compact percent, and "100%" fits it', function()
		local panel, r = openDex(844, 332, { found = 50, total = 50 })
		local short = Layout.rect(r.x, r.y, r.w, r.h - Layout.panelBody(r).h + SHORT_BODY)
		panel.frame.Size = UDim2.fromOffset(short.w, short.h)
		panel.layout(short)
		expect(UiHarness.find(panel.frame, "Percent").Size.Y.Offset).toBe(SlimeDex.HEADER.chip)
		expectPercentFits(panel)
	end)
end)

describe("SlimeDex.rewardCard", function()
	local REWARDS = {
		{ ladder = "species", count = 8, reward = 1000, bonus = 0.02, claimed = true },
		{ ladder = "species", count = 15, reward = 5000, bonus = 0.03, claimed = false },
		{ ladder = "species", count = 50, reward = 1e7, bonus = 0.15, claimed = false },
	}
	it("names the next species milestone, its pay and every tick to scale", function()
		local rc = SlimeDex.rewardCard({ dex = { found = 10 }, dexRewards = REWARDS }) :: SlimeDex.RewardCard
		expect(rc.title).toBe("Next reward at 15 species")
		expect(rc.reward).toBe("+$5K and +3% income")
		expect(rc.fraction).toBeCloseTo(10 / 50)
		expect(#rc.ticks).toBe(3)
		expect(rc.ticks[1].at).toBeCloseTo(8 / 50)
		expect(rc.ticks[1].claimed).toBe(true)
		expect(rc.ticks[2].isNext).toBe(true)
		expect(rc.ticks[3].at).toBe(1)
	end)
	it("fills the bar once every species milestone is claimed; nil without species milestones", function()
		local done = SlimeDex.rewardCard({
			dex = { found = 50 },
			dexRewards = { { ladder = "species", count = 50, reward = 1, bonus = 0.1, claimed = true } },
		}) :: SlimeDex.RewardCard
		expect(done.reward).toBeNil()
		expect(done.fraction).toBe(1)
		expect(SlimeDex.rewardCard({ dex = {} })).toBeNil()
		expect(SlimeDex.rewardCard({ dexRewards = {} })).toBeNil()
	end)
end)

describe("menu close button (Widgets.panel)", function()
	for _, name in { "Merge", "Shop", "Rebirth", "Goals", "Dex", "Leaderboard" } do
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
