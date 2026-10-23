--!strict
-- SlimeDex (src/ui/SlimeDex.luau) and the real SlimeDex panel built under tests/ui/UiHarness.luau: one card per
-- species split over the Fountain / Merges / Bosses / Secrets tabs, a grid with a side pane for the selected
-- card, merge recipe rows that say which ingredients are in your base, and the close X on every menu.
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
	truffle = { inputs = { "flan", "flan", "mushie" }, hint = "Double caramel on a mushroom." },
	bloom = { inputs = { "bumble", "mushie", "prickles" }, hint = "A bee, a mushroom and a cactus flower." },
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
		setName = SpeciesDex.setName,
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

local function lookup(id: string): (string?, { number }?, string?)
	local entry, look = SlimeRoster.get(id), SlimeLooks.get(id)
	return if entry then entry.name else nil, if look then look.color else nil, SpeciesDex.setName(id)
end

local function cardOf(cards: { SlimeDex.Card }, id: string): SlimeDex.Card
	for _, card in cards do
		if card.key == id then
			return card
		end
	end
	error(`no card {id}`)
end

-- State.slimes with one pad slime per species id (repeats allowed).
local function slimes(ids: { string }, stolen: { [string]: boolean }?): { any }
	local out = {}
	for i, id in ids do
		table.insert(out, {
			slime = { id = `s{i}`, species = id, tier = 1 },
			stolenBy = if stolen and stolen[id] then 99 else nil,
		})
	end
	return out
end

describe("SlimeDex.cards", function()
	it("has one card per Dex entry and bonus entry, in State order", function()
		local cards = SlimeDex.cards(DEX, Config, lookup)
		expect(#cards).toBe(SpeciesDex.TOTAL + #SpeciesDex.BONUS)
		expect(cards[1].key).toBe(SpeciesDex.ENTRIES[1].id)
		expect(cards[#cards].kind).toBe("event")
	end)
	it("a found species shows its name and rarity colour; a spawn species carries its set", function()
		local gummy = cardOf(SlimeDex.cards(DEX, Config, lookup), "gummy")
		expect(gummy.found).toBe(true)
		expect(gummy.title).toBe("Gummy")
		expect(gummy.color).toBe(Config.RARITIES[1].color)
		expect(gummy.set).toBe("Meadow")
		expect(cardOf(SlimeDex.cards(DEX, Config, lookup), "flan").set).toBe("Garden")
	end)
	it("an unfound species is a silhouette with its name", function()
		local moo = cardOf(SlimeDex.cards(DEX, Config, lookup), "moo")
		expect(moo.found).toBe(false)
		expect(moo.title).toBe("Moo")
	end)
	it("a hybrid fills the ingredient slots it has found and names the set of the others", function()
		local soda = cardOf(SlimeDex.cards(DEX, Config, lookup), "soda")
		expect(soda.found).toBe(false)
		expect(soda.title).toBe("Soda Pop")
		expect(soda.set).toBeNil()
		local slots = soda.slots :: { SlimeDex.Slot }
		expect(#slots).toBe(3)
		expect(slots[1].species).toBeNil() -- bubbles: not found
		expect(slots[1].label).toBe("???")
		expect(slots[1].set).toBe("Meadow")
		expect(slots[2].species).toBe("gummy")
		expect(slots[2].label).toBe("Gummy")
		expect(slots[3].species).toBe("mochi")
	end)
	it("survives a missing or junk State.dex", function()
		expect(#SlimeDex.cards(nil, Config)).toBe(0)
		expect(#SlimeDex.cards({ entries = { "junk", { id = 3 }, { id = "moo", tier = 99 } } }, Config)).toBe(0)
	end)
end)

describe("SlimeDex.tabs", function()
	it("Fountain, Merges, Bosses and Secrets, each with its found count", function()
		local tabs = SlimeDex.tabs(SlimeDex.cards(DEX, Config, lookup))
		local keys, labels = {}, {}
		for _, tab in tabs do
			table.insert(keys, tab.key)
			table.insert(labels, tab.label)
		end
		expect(table.concat(keys, ",")).toBe("spawn,hybrid,boss,event")
		expect(table.concat(labels, ",")).toBe("Fountain,Merges,Bosses,Secrets")
		local spawn = #SlimeRoster.ofKind("spawn")
		expect(tabs[1].count).toBe(`3/{spawn}`)
		expect(tabs[2].found).toBe(0)
	end)
	it("drops a tab with no cards (a server without event Secrets)", function()
		local cards = SlimeDex.ofKind(SlimeDex.cards(DEX, Config, lookup), "spawn")
		local tabs = SlimeDex.tabs(cards)
		expect(#tabs).toBe(1)
		expect(tabs[1].key).toBe("spawn")
	end)
end)

describe("SlimeDex.grid / lines", function()
	it("fits as many cards as the width allows, at most maxColumns", function()
		expect(SlimeDex.grid(80).columns).toBe(1)
		expect(SlimeDex.grid(SlimeDex.CARD.minW * 2 + SlimeDex.CARD.gap).columns).toBe(2)
		expect(SlimeDex.grid(5000).columns).toBe(SlimeDex.CARD.maxColumns)
		for _, w in { 80, 230, 300, 480, 900 } do
			local g = SlimeDex.grid(w)
			expect(g.columns * g.cardW + (g.columns - 1) * g.gap <= math.max(w, g.cardW)).toBe(true)
		end
	end)
	it("groups one tab's cards under one header per rarity with its found count", function()
		local cards = SlimeDex.ofKind(SlimeDex.cards(DEX, Config, lookup), "spawn")
		local lines = SlimeDex.lines(cards, 3, Config)
		expect(lines[1].kind).toBe("header")
		expect(lines[1].title).toBe(Config.RARITIES[1].name)
		local commons = 0
		for _, card in cards do
			if card.tier == 1 then
				commons += 1
			end
		end
		expect(lines[1].detail).toBe(`2/{commons}`)
		local placed = 0
		for _, line in lines do
			if line.kind == "cards" then
				local n = #(line.cards :: { SlimeDex.Card })
				expect(n >= 1 and n <= 3).toBe(true)
				placed += n
			end
		end
		expect(placed).toBe(#cards)
	end)
	it("puts the event Secrets in one section", function()
		local cards = SlimeDex.ofKind(SlimeDex.cards(DEX, Config, lookup), "event")
		local lines = SlimeDex.lines(cards, 3, Config)
		expect(lines[1].title).toBe("Event Secrets")
		expect(lines[1].tier).toBe(SlimeDex.BONUS_TIER)
	end)
end)

describe("SlimeDex.inBase / detail", function()
	it("counts pad slimes per species, not ones being stolen", function()
		local base = SlimeDex.inBase(slimes({ "gummy", "gummy", "mochi", "bumble" }, { bumble = true }))
		expect(base.gummy).toBe(2)
		expect(base.mochi).toBe(1)
		expect(base.bumble).toBeNil()
		expect(next(SlimeDex.inBase(nil))).toBeNil()
	end)
	it("the side pane says how to get it, its set, how many you have and the merges it is in", function()
		local cards = SlimeDex.cards(DEX, Config, lookup)
		local d = SlimeDex.detail(cardOf(cards, "gummy"), cards, { gummy = 2 }, Config)
		expect(d.title).toBe("Gummy")
		expect(d.rarity).toBe(Config.RARITIES[1].name)
		expect(d.how).toBe(SlimeDex.HOW.spawn)
		expect(d.set).toBe("Meadow set")
		expect(d.have).toBe("2 in your base")
		expect(#d.usedIn).toBe(1)
		expect(d.usedIn[1].title).toBe("Soda Pop")
		local moo = SlimeDex.detail(cardOf(cards, "moo"), cards, {}, Config)
		expect(moo.have).toBe("None in your base")
		expect(#moo.usedIn).toBe(0)
		local boss = SlimeDex.detail(cardOf(cards, "goozilla"), cards, {}, Config)
		expect(boss.how).toBe(SpeciesDex.BOSS_HINT)
		expect(boss.set).toBeNil()
	end)
end)

describe("SlimeDex.recipes", function()
	local function recipeOf(list: { SlimeDex.Recipe }, id: string): SlimeDex.Recipe
		for _, r in list do
			if r.result.key == id then
				return r
			end
		end
		error(`no recipe {id}`)
	end

	it("marks each ingredient In base, Found or unknown with its set", function()
		local dex = Fixtures.dex({ "gummy", "mochi", "bubbles", "bumble" }, SOURCES)
		local cards = SlimeDex.cards(dex, Config, lookup)
		local soda = recipeOf(SlimeDex.recipes(cards, SlimeDex.inBase(slimes({ "gummy", "mochi" }))), "soda")
		expect(soda.slots[1].state).toBe("found") -- bubbles: found before, none in base
		expect(soda.slots[1].tag).toBe("Found")
		expect(soda.slots[2].state).toBe("base")
		expect(soda.slots[2].tag).toBe("In base")
		expect(soda.status).toBe("need")
		expect(soda.statusText).toBe("Need 1 more")
		local bloom = recipeOf(SlimeDex.recipes(cards, {}), "bloom")
		expect(bloom.slots[3].state).toBe("unknown") -- prickles
		expect(bloom.slots[3].label).toBe("???")
		expect(bloom.slots[3].tag).toBe("Garden")
	end)
	it("a repeated ingredient needs one slime in base per slot", function()
		local dex = Fixtures.dex({ "flan", "mushie" }, SOURCES)
		local cards = SlimeDex.cards(dex, Config, lookup)
		local one = recipeOf(SlimeDex.recipes(cards, SlimeDex.inBase(slimes({ "flan", "mushie" }))), "truffle")
		expect(one.slots[1].state).toBe("base")
		expect(one.slots[2].state).toBe("found")
		expect(one.missing).toBe(1)
		local two = recipeOf(SlimeDex.recipes(cards, SlimeDex.inBase(slimes({ "flan", "flan", "mushie" }))), "truffle")
		expect(two.status).toBe("ready")
		expect(two.statusText).toBe("Ready to merge")
	end)
	it("sorts ready first, then the fewest missing, made last", function()
		local dex = Fixtures.dex({ "gummy", "mochi", "bubbles", "bumble", "mushie", "flan", "soda" }, SOURCES)
		local cards = SlimeDex.cards(dex, Config, lookup)
		local list = SlimeDex.recipes(cards, SlimeDex.inBase(slimes({ "bumble", "mushie" })))
		expect(list[1].result.key).toBe("bloom") -- 1 missing
		expect(list[1].status).toBe("need")
		expect(list[#list].result.key).toBe("soda")
		expect(list[#list].status).toBe("made")
		expect(list[#list].statusText).toBe("Made")
		local ready = SlimeDex.recipes(cards, SlimeDex.inBase(slimes({ "bumble", "mushie", "flan", "flan" })))
		expect(ready[1].status).toBe("ready") -- truffle: flan, flan, mushie all in base
		expect(ready[1].result.key).toBe("truffle")
	end)
	it("`only` keeps the recipes that take that species", function()
		local cards = SlimeDex.cards(DEX, Config, lookup)
		local list = SlimeDex.recipes(cards, {}, "bumble")
		expect(#list).toBe(1)
		expect(list[1].result.key).toBe("bloom")
	end)
end)

describe("SlimeDex.summary / rewardLine", function()
	it("gives the percent and found chips", function()
		local s = SlimeDex.summary(DEX)
		expect(s.count).toBe(`3/{SpeciesDex.TOTAL} found`)
		expect(s.percent).toBe(`{math.floor(3 / SpeciesDex.TOTAL * 100)}%`)
		expect(SlimeDex.summary(nil).percent).toBe("0%")
	end)
	local REWARDS = {
		{ ladder = "species", count = 8, reward = 1000, bonus = 0.02, claimed = true },
		{ ladder = "species", count = 15, reward = 5000, bonus = 0.03, claimed = false },
		{ ladder = "species", count = 50, reward = 1e7, bonus = 0.15, claimed = false },
	}
	it("names the next species milestone, its pay and the progress toward it", function()
		local line = SlimeDex.rewardLine({ dex = { found = 10 }, dexRewards = REWARDS }) :: SlimeDex.RewardLine
		expect(line.text).toBe("Next reward at 15: +$5K and +3% income")
		expect(line.count).toBe("10/15")
		expect(line.fraction).toBeCloseTo(10 / 15)
	end)
	it("is full once every milestone is claimed; nil without species milestones", function()
		local done = SlimeDex.rewardLine({
			dex = { found = 50 },
			dexRewards = { { ladder = "species", count = 50, reward = 1, bonus = 0.1, claimed = true } },
		}) :: SlimeDex.RewardLine
		expect(done.text).toBe("Every species reward collected")
		expect(done.count).toBeNil()
		expect(done.fraction).toBe(1)
		expect(SlimeDex.rewardLine({ dex = {} })).toBeNil()
		expect(SlimeDex.rewardLine({ dexRewards = {} })).toBeNil()
	end)
end)

-- The SlimeDex panel built for real, sized like a full-window menu (init.client applyLayout: frame size,
-- then panel.layout).
local function openDex(w: number, h: number, dex: any, extra: { [string]: any }?, c: any?): (any, Layout.Rect)
	local panel = UiHarness.ui("Panels/Dex").new(UiHarness.root(), c or ctx())
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

local function recipe(panel: any, id: string): any
	return UiHarness.find(UiHarness.find(panel.frame, "Recipes"), `recipe:{id}`)
end

describe("SlimeDex panel", function()
	it("is titled SlimeDex with the percent and found chips in the band", function()
		local panel = openDex(390, 844, DEX)
		expect(UiHarness.find(panel.frame, "Title").Text).toBe("SlimeDex")
		expect(UiHarness.find(panel.frame, "Count").Text).toBe(`3/{SpeciesDex.TOTAL} found`)
		expect(UiHarness.find(panel.frame, "Percent").Parent).toBe(panel.frame)
	end)
	it("opens on Fountain; the tabs show their counts and the shown one is selected", function()
		local panel = openDex(1920, 1080, DEX)
		expect(panel.tab()).toBe("spawn")
		local tab = UiHarness.find(panel.frame, "Tab_spawn")
		expect(tab:GetAttribute("Selected")).toBe(true)
		expect(tab.Text).toBe(`Fountain\n3/{#SlimeRoster.ofKind("spawn")}`)
		expect(UiHarness.find(panel.frame, "Tab_hybrid"):GetAttribute("Selected")).toBe(false)
		expect(card(panel, "soda")).toBeNil() -- hybrids live on the Merges tab
		expect(UiHarness.find(panel.frame, "Recipes").Visible).toBe(false)
	end)
	it("every card has its name, found or not, and a square preview", function()
		local panel = openDex(1920, 1080, DEX)
		local gummy = card(panel, "gummy")
		expect(gummy:GetAttribute("Found")).toBe(true)
		expect(UiHarness.find(gummy, "Title").Text).toBe("Gummy")
		local moo = card(panel, "moo")
		expect(moo:GetAttribute("Found")).toBe(false)
		expect(UiHarness.find(moo, "Title").Text).toBe("Moo")
		local image = UiHarness.find(moo, "Image")
		expect(image.Size.X.Offset).toBe(image.Size.Y.Offset)
	end)
	it("selects the first found card and fills the side pane; tapping a card moves it", function()
		local panel = openDex(1920, 1080, DEX, { slimes = slimes({ "gummy" }) })
		expect(card(panel, "gummy"):GetAttribute("Selected")).toBe(true)
		local pane = UiHarness.find(panel.frame, "Pane")
		expect(UiHarness.find(pane, "PaneTitle").Text).toBe("Gummy")
		expect(UiHarness.find(pane, "Have").Text).toBe("1 in your base")
		expect(UiHarness.find(pane, "Set").Text).toBe("Meadow set")
		expect(UiHarness.find(pane, "UsedIn").Text).toBe("Soda Pop")
		expect(UiHarness.find(pane, "SeeMerges").Visible).toBe(true)
		panel.select("moo")
		expect(card(panel, "moo"):GetAttribute("Selected")).toBe(true)
		expect(card(panel, "gummy"):GetAttribute("Selected")).toBe(false)
		expect(UiHarness.find(pane, "PaneTitle").Text).toBe("Moo")
		expect(UiHarness.find(pane, "Have").Text).toBe("None in your base")
		expect(UiHarness.find(pane, "SeeMerges").Visible).toBe(false)
	end)
	it("See merges opens the Merges tab with only that species' recipes, Show all clears it", function()
		local panel = openDex(1920, 1080, DEX)
		panel.select("bumble")
		UiHarness.fire(UiHarness.find(UiHarness.find(panel.frame, "Pane"), "SeeMerges"), "Activated")
		expect(panel.tab()).toBe("hybrid")
		expect(recipe(panel, "bloom") ~= nil).toBe(true)
		expect(recipe(panel, "soda")).toBeNil()
		expect(UiHarness.find(panel.frame, "Legend").Text).toBe("Merges with Bumble")
		local showAll = UiHarness.find(panel.frame, "ShowAll")
		expect(showAll.Visible).toBe(true)
		UiHarness.fire(showAll, "Activated")
		expect(recipe(panel, "soda") ~= nil).toBe(true)
		expect(UiHarness.find(panel.frame, "ShowAll").Visible).toBe(false)
	end)
	it("a recipe row marks In base slots with the mint ring and says what is missing", function()
		local panel = openDex(1920, 1080, DEX, { slimes = slimes({ "gummy" }) })
		panel.selectTab("hybrid")
		expect(UiHarness.find(panel.frame, "List").Visible).toBe(false)
		local soda = recipe(panel, "soda")
		expect(soda:GetAttribute("Status")).toBe("need")
		expect(UiHarness.find(soda, "Status").Text).toBe("Need 2 more")
		local slot1, slot2 = UiHarness.find(soda, "Slot1"), UiHarness.find(soda, "Slot2")
		expect(slot1:GetAttribute("State")).toBe("unknown")
		expect(UiHarness.find(slot1, "Name").Text).toBe("???")
		expect(UiHarness.find(slot1, "Tag").Text).toBe("Meadow")
		expect(slot2:GetAttribute("State")).toBe("base")
		expect(slot2:FindFirstChildOfClass("UIStroke").Enabled).toBe(true)
		expect(UiHarness.find(slot2, "Tag").Text).toBe("In base")
		expect(UiHarness.find(UiHarness.find(soda, "Result"), "Name").Text).toBe("Soda Pop")
	end)
	it("a ready recipe sorts first and wears the mint ring", function()
		local dex = Fixtures.dex({ "gummy", "mochi", "bubbles" }, SOURCES)
		local panel = openDex(1920, 1080, dex, { slimes = slimes({ "gummy", "mochi", "bubbles" }) })
		panel.selectTab("hybrid")
		local soda = recipe(panel, "soda")
		expect(soda:GetAttribute("Status")).toBe("ready")
		expect(UiHarness.find(soda, "Status").Text).toBe("Ready to merge")
		for _, row in UiHarness.find(panel.frame, "Recipes"):GetChildren() do
			if row:IsA("GuiObject") and row ~= soda then
				expect(soda.LayoutOrder < row.LayoutOrder).toBe(true)
			end
		end
	end)
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		it(
			`{vp.name}: cards sit side by side inside the grid, the pane beside it, recipe parts in their row`,
			function()
				local panel, r = openDex(vp.w, vp.h, DEX)
				local body = Layout.panelBody(r)
				local list = UiHarness.find(panel.frame, "List")
				local pane = UiHarness.find(panel.frame, "Pane")
				expect(list.Position.X.Offset + list.Size.X.Offset <= pane.Position.X.Offset).toBe(true)
				expect(pane.Position.X.Offset + pane.Size.X.Offset <= body.w + 1e-6).toBe(true)
				local line = UiHarness.find(list, "cards:1:1")
				local right = 0
				for _, c in line:GetChildren() do
					if c:IsA("GuiObject") and c:GetAttribute("Found") ~= nil then
						right = math.max(right, c.Position.X.Offset + c.Size.X.Offset)
						expect(c.Size.X.Offset >= SlimeDex.CARD.minW).toBe(true)
					end
				end
				expect(right <= list.Size.X.Offset).toBe(true)
				expect(panel.grid().columns >= 2).toBe(true)
				panel.selectTab("hybrid")
				local soda = recipe(panel, "soda")
				local rowW = UiHarness.find(panel.frame, "Recipes").Size.X.Offset - 10
				local x = 0
				for _, name in { "Slot1", "Slot2", "Slot3", "Result" } do
					local part = UiHarness.find(soda, name)
					expect(part.Position.X.Offset >= x).toBe(true)
					x = part.Position.X.Offset + part.Size.X.Offset
					expect(part.Size.X.Offset >= 60).toBe(true) -- room for a 14 px name
					expect(part.Position.Y.Offset + part.Size.Y.Offset <= soda.Size.Y.Offset).toBe(true)
				end
				expect(x <= rowW + 1e-6).toBe(true)
			end
		)
	end
	it("measures as a full-height list menu once open, so init.client fills the window with it", function()
		local panel = openDex(1920, 1080, DEX)
		local content = UiHarness.ui("Widgets").contentHeight(UiHarness.find(panel.frame, "Body"))
		local c = Layout.PANEL_CHROME
		expect(content).toBe(Layout.menuHeight("Dex") - c.header - c.pad)
		local screen = Layout.screen(1920, 1080)
		expect(Layout.panelFor(screen, "Dex", content).h).toBe(Layout.panelFor(screen, "Dex").h)
	end)
	it("rebuilds only while open: an update while closed marks the lists dirty", function()
		local panel = UiHarness.ui("Panels/Dex").new(UiHarness.root(), ctx())
		panel.update({ dex = DEX })
		expect(panel.builds()).toBe(0)
		panel.setOpen(true)
		expect(panel.builds()).toBe(1)
		panel.setOpen(false)
		panel.update({ dex = Fixtures.dex({ "gummy", "mochi", "bumble", "moo" }, SOURCES) })
		expect(panel.builds()).toBe(1)
		panel.setOpen(true)
		expect(panel.builds()).toBe(2)
		expect(card(panel, "moo"):GetAttribute("Found")).toBe(true)
		panel.update({ dex = Fixtures.dex({ "gummy", "mochi", "bumble", "moo" }, SOURCES) })
		expect(panel.builds()).toBe(2) -- same State: no rebuild
	end)
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

describe("menu close button (Widgets.panel)", function()
	for _, name in { "Merge", "WorldShop", "Rebirth", "Goals", "Dex", "Skins" } do
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
