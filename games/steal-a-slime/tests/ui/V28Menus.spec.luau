--!strict
-- v28 menu pass (Merijn's playtest of v27, items 1-5): content-sized menu
-- cards with an icon band and close X, real slime renders in the SlimeDex,
-- ONE shop menu opened by the ShopStand prompt, a Rebirth card that shows
-- only the next rebirth, and a Guide NPC that opens a next-goal / tips card.
-- Real panels under tests/ui/UiHarness.luau; pure modules directly.
local roblox = require("@lune/roblox") :: any

local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Economy = require("../../src/shared/Economy")
local Fixtures = require("../Fixtures")
local Format = require("../../src/ui/Format")
local Genome = require("../../src/shared/Genome")
local GuideTips = require("../../src/ui/GuideTips")
local Layout = require("../../src/ui/Layout")
local Progress = require("../../src/ui/Progress")
local Remotes = require("../../src/shared/Remotes")
local ShopCatalog = require("../../src/ui/ShopCatalog")
local SlimeDex = require("../../src/ui/SlimeDex")
local SlimeLayout = require("../../src/visuals/shared/SlimeLayout")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local UDim2, Vector3 = roblox.UDim2, roblox.Vector3

local RARITY_NAMES = {}
for i, rarity in Config.RARITIES do
	RARITY_NAMES[i] = rarity.name
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function ctx(extra: { [string]: any }?): any
	local c: { [string]: any } = {
		Config = Config,
		Constants = Constants,
		Genome = Genome,
		actions = Remotes.ACTIONS,
		send = function() end,
		serverNow = function()
			return 1000
		end,
		playerName = function()
			return "Tester"
		end,
		toast = function() end,
	}
	for k, v in extra or {} do
		c[k] = v
	end
	return c
end

local function rebirthState(rebirths: number, cash: number): any
	return {
		rebirths = rebirths,
		rebirthMultiplier = Economy.rebirthMultiplier(rebirths),
		rebirthCost = Economy.rebirthCost(rebirths),
		canRebirth = cash >= Economy.rebirthCost(rebirths),
		cash = cash,
		slimes = {},
	}
end

describe("v28 item 1: friendlier, content-sized menus", function()
	it("every menu card has its icon on a corner tile, the shared title band and the close X", function()
		local Widgets = UiHarness.ui("Widgets")
		local panel = Widgets.panel(UiHarness.root(), "TestPanel", "Test", "🛒")
		expect(panel.icon.Text).toBe("🛒")
		expect(panel.icon.Parent.Name).toBe("IconTile")
		expect(panel.close.Text).toBe("X")
		expect(panel.close.BackgroundColor3).toBe(Widgets.Theme.Bad)
		expect(panel.frame:FindFirstChild("Band").BackgroundColor3).toBe(Widgets.Theme.Band)
		expect(panel.frame.ZIndex).toBe(Layout.ZINDEX.Menu)
	end)
	it("cards are smaller than the full-window backdrop on desktop and span it on phones", function()
		local desk = Layout.screen(1920, 1080)
		local phone = Layout.screen(390, 844)
		for key in Layout.MENU_HEIGHTS do
			local d = Layout.panelFor(desk, key)
			expect(d.w < desk.panel.w and d.h < desk.panel.h).toBe(true)
			local p = Layout.panelFor(phone, key)
			expect(p.w).toBe(phone.panel.w)
			expect(p.h <= phone.panel.h).toBe(true)
		end
	end)
end)

-- A stand-in for Visuals.ModelFactory.build: a Model with a Body part.
local built: { any } = {}
local function fakeBuild(genome: any): any
	local model = UiHarness.Instance.new("Model")
	model.Name = `Slime_{genome.id}`
	local body = UiHarness.Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(4, 3, 4)
	body.Parent = model
	model:SetAttribute("Tier", genome.tier)
	table.insert(built, genome)
	return model
end

local function openDex(dex: any, extra: { [string]: any }): any
	local Dex = UiHarness.ui("Panels/Dex")
	local panel = Dex.new(UiHarness.root(), ctx(extra))
	panel.frame.Size = UDim2.fromOffset(560, 600)
	panel.setOpen(true)
	panel.update({ dex = dex })
	return panel
end

local DEX = Fixtures.dex({ "bumble" })

describe("v28 item 2: SlimeDex pictures are real slime renders", function()
	it(
		"SlimeDex.genome turns every card into a buildable slime of its species (SlimeLayout, same as the world)",
		function()
			local cards = SlimeDex.cards(DEX, Config)
			expect(#cards > 0).toBe(true)
			for _, card in cards do
				local genome = SlimeDex.genome(card) :: any
				expect(genome.species).toBe(card.key)
				expect(genome.tier >= 1 and genome.tier <= Config.MAX_TIER).toBe(true)
				local specs = SlimeLayout.build(genome)
				expect(#specs >= 1).toBe(true)
			end
		end
	)
	it(
		"without a species mesh the Dex panel mounts the built model (not the blob) when ctx.buildSlime is there",
		function()
			table.clear(built)
			local panel = openDex(DEX, { buildSlime = fakeBuild })
			local card = UiHarness.find(UiHarness.find(panel.frame, "List"), "bumble")
			local preview = card:FindFirstChild("Image"):FindFirstChild("Preview")
			expect(preview.Visible).toBe(true)
			local model = UiHarness.find(preview, "Slime_Dex_bumble")
			expect(model ~= nil).toBe(true)
			expect(model:FindFirstChild("Body").Anchored).toBe(true)
			expect(preview.CurrentCamera ~= nil).toBe(true)
			expect(#built >= 1).toBe(true)
		end
	)
	it("an unfound species renders its model as a dark silhouette", function()
		local SlimePreview = UiHarness.ui("SlimePreview")
		local panel = openDex(DEX, { buildSlime = fakeBuild })
		local locked = UiHarness.find(UiHarness.find(panel.frame, "List"), "gummy")
		local body = UiHarness.find(locked:FindFirstChild("Image"):FindFirstChild("Preview"), "Body")
		expect(body.Color).toBe(SlimePreview.SILHOUETTE)
	end)
	it("falls back to the SlimePreview blob when the builders error", function()
		local panel = openDex(DEX, {
			buildSpecies = function()
				error("no mesh")
			end,
			buildSlime = function()
				error("no Visuals")
			end,
		})
		local card = UiHarness.find(UiHarness.find(panel.frame, "List"), "bumble")
		local preview = card:FindFirstChild("Image"):FindFirstChild("Preview")
		expect(preview.Visible).toBe(true)
		expect(UiHarness.find(preview, "Body") ~= nil).toBe(true)
	end)
end)

describe("v28 item 3: one shop menu from the ShopStand prompt", function()
	it("the Shop panel lists every item flat in one scroll list, a Buy button per row", function()
		local Shop = UiHarness.ui("Panels/Shop")
		local panel = Shop.new(UiHarness.root(), ctx())
		local state = {
			cash = 5000,
			lockCost = 25,
			lockDuration = 60,
			shop = {},
			upgrades = {
				{ id = "Income", name = "Slime Snacks", text = "+10% income", level = 0, maxLevel = 10, price = 2000 },
				{
					id = "Luck",
					name = "Lucky Charm",
					text = "+4% chance a slime you bring home is one rarity higher",
					level = 0,
					maxLevel = 5,
					unlocked = false,
					requires = 5,
				},
			},
		}
		panel.update(state)
		local list = UiHarness.find(panel.frame, "List")
		local rows = {}
		for _, child in list:GetChildren() do
			if child.ClassName == "Frame" then
				table.insert(rows, child)
				expect(child:FindFirstChild("Buy") ~= nil).toBe(true)
				expect(child:FindFirstChild("Icon").Text ~= "").toBe(true)
				expect(UiHarness.find(child, "List")).toBeNil() -- no nested menu
			end
		end
		expect(#rows).toBe(#ShopCatalog.ITEMS + 2)
		expect(UiHarness.find(panel.frame, "Cash").Text).toBe("💰 $5K")
		local luck = list:FindFirstChild("Upgrade_Luck")
		expect(luck:FindFirstChild("Description").Text).toBe("+4% rarity-up chance")
		expect(luck:FindFirstChild("Level").Text).toBe("Lv 0/5")
	end)
	it("ShopCatalog.upgradeText keeps the number and shortens known upgrades only", function()
		expect(ShopCatalog.upgradeText("Luck", "+4% chance a slime you bring home is one rarity higher")).toBe(
			"+4% rarity-up chance"
		)
		expect(ShopCatalog.upgradeText("Income", "+10% income")).toBe("+10% income")
		expect(ShopCatalog.upgradeText("Luck", "luckier")).toBe("luckier")
	end)
end)

describe("v28 item 4: Rebirth shows only the next rebirth", function()
	it("Progress.nextRebirth: cost, what's missing and what it gives", function()
		local cost = Economy.rebirthCost(2)
		local n = Progress.nextRebirth(rebirthState(2, cost / 4), Config)
		expect(n.rebirth).toBe(3)
		expect(n.cost).toBe(cost)
		expect(n.ready).toBe(false)
		expect(n.fraction).toBeCloseTo(0.25)
		expect(n.multiplier).toBeCloseTo(Economy.rebirthMultiplier(3))
		expect(n.lockGain).toBe(Config.LOCK_SECONDS_PER_REBIRTH)
		expect(has(n.need, "more")).toBe(true)
		local ready = Progress.nextRebirth(rebirthState(2, cost), Config)
		expect(ready.ready).toBe(true)
		expect(ready.need).toBe("Ready!")
		local maxed = Progress.nextRebirth(rebirthState(Config.MAX_REBIRTHS, 0), Config)
		expect(maxed.maxed).toBe(true)
		expect(maxed.ready).toBe(false)
	end)
	it("the panel has one requirement card and no ladder of later tiers", function()
		local Rebirth = UiHarness.ui("Panels/Rebirth")
		local Theme = UiHarness.ui("Widgets").Theme
		local panel = Rebirth.new(UiHarness.root(), ctx())
		local cost = Economy.rebirthCost(0)
		panel.update(rebirthState(0, cost / 2))
		expect(panel.frame:FindFirstChild("Title").Text).toBe("Rebirth 1")
		local costLabel = UiHarness.find(panel.frame, "Cost")
		expect(costLabel.Text).toBe(Format.formatCash(cost))
		expect(costLabel.TextColor3).toBe(Theme.Muted) -- can't pay it yet
		-- Not ready: no button, a sunken well with what is missing.
		local button = UiHarness.find(panel.frame, "RebirthButton")
		local reason = UiHarness.find(panel.frame, "Reason")
		expect(button.Visible).toBe(false)
		expect(button.AutoButtonColor).toBe(false)
		expect(reason.Visible).toBe(true)
		expect(reason.Text).toBe(`Need {Format.formatCash(cost - cost / 2)} more`)
		panel.update(rebirthState(0, cost))
		expect(costLabel.TextColor3).toBe(Theme.Gold)
		expect(reason.Visible).toBe(false)
		expect(button.Visible).toBe(true)
		expect(button.AutoButtonColor).toBe(true)
		expect(button.Text).toBe("Hold to rebirth")
		expect(button.BackgroundColor3).toBe(Theme.Accent)
		-- No text mentions any later rebirth.
		for _, node in UiHarness.descendants(panel.frame) do
			if node.ClassName == "TextLabel" or node.ClassName == "TextButton" then
				expect(has(string.upper(node.Text), "REBIRTH 2")).toBe(false)
			end
		end
	end)
end)

describe("Rebirth needs specific slimes and uses them up", function()
	local SPROUT = { id = "sprout", name = "Sprout Slime", tier = 2, color = { 90, 200, 90 } }
	local ZAP = { id = "zap", name = "Zap", tier = 4, color = { 90, 90, 200 } }
	local function need(base: any, owned: boolean): any
		local row = table.clone(base)
		row.owned = owned
		return row
	end
	local function stateWith(owned: boolean, cash: number): any
		local state = rebirthState(0, cash)
		state.rebirthSlimes = { need(SPROUT, owned) }
		state.canRebirth = owned and cash >= Economy.rebirthCost(0)
		return state
	end
	it("Progress.nextRebirth carries the requirement and lists the missing slimes", function()
		local missing = Progress.nextRebirth(stateWith(false, 1e9), Config)
		expect(#missing.slimes).toBe(1)
		expect(missing.slimes[1].name).toBe("Sprout Slime")
		expect(#missing.missing).toBe(1)
		expect(missing.ready).toBe(false)
		local owned = Progress.nextRebirth(stateWith(true, 1e9), Config)
		expect(#owned.missing).toBe(0)
		expect(owned.ready).toBe(true)
		expect(#Progress.nextRebirth(rebirthState(0, 0), Config).slimes).toBe(0)
		local state = stateWith(false, 0)
		state.rebirths = Config.MAX_REBIRTHS
		expect(#Progress.nextRebirth(state, Config).slimes).toBe(0)
	end)
	it("the panel shows the missing slime greyed out with the reason, then Owned and the button", function()
		local Rebirth = UiHarness.ui("Panels/Rebirth")
		local Theme = UiHarness.ui("Widgets").Theme
		local panel = Rebirth.new(UiHarness.root(), ctx())
		panel.update(stateWith(false, 1e9))
		local card = UiHarness.find(panel.frame, "SlimeNeed")
		expect(UiHarness.find(card, "SlimeName").Text).toBe("Sprout Slime")
		local stamp = UiHarness.find(card, "SlimeState")
		expect(stamp.Text).toBe("Missing")
		expect(stamp.TextColor3).toBe(Theme.Bad)
		-- greyed out, not the black silhouette: the preview body is the grey tint
		local preview = UiHarness.find(card, "Preview")
		expect(preview.ImageTransparency > 0).toBe(true)
		local body = UiHarness.find(preview, "Body")
		expect(body.Color).toBe(UiHarness.ui("SlimePreview").GREYED)
		local button = UiHarness.find(panel.frame, "RebirthButton")
		local reason = UiHarness.find(panel.frame, "Reason")
		expect(button.Visible).toBe(false)
		expect(reason.Text).toBe("Need a Sprout Slime")
		panel.update(stateWith(true, 1e9))
		expect(stamp.Text).toBe("✅ Owned")
		expect(stamp.TextColor3).toBe(Theme.Good)
		expect(UiHarness.find(card, "SlimeDesc").Text).toBe("Used up on rebirth")
		expect(preview.ImageTransparency).toBe(0)
		expect(reason.Visible).toBe(false)
		expect(button.Visible).toBe(true)
		panel.update(rebirthState(0, 0))
		expect(card.Visible).toBe(false)
	end)
	it("several slimes: a full-width cash card over one card per slime, the reason names cash and slimes", function()
		local Rebirth = UiHarness.ui("Panels/Rebirth")
		local panel = Rebirth.new(UiHarness.root(), ctx())
		local state = rebirthState(0, 0)
		state.rebirthSlimes = { need(SPROUT, true), need(ZAP, false) }
		state.canRebirth = false
		panel.update(state)
		expect(UiHarness.find(panel.frame, "Sub").Text).toBe("You need all three:")
		expect(UiHarness.find(panel.frame, "Need").Size.X.Scale).toBe(1)
		local first = UiHarness.find(panel.frame, "SlimeNeed")
		local second = UiHarness.find(panel.frame, "SlimeNeed2")
		expect(first.Visible and second.Visible).toBe(true)
		expect(first.Position.Y.Offset).toBe(second.Position.Y.Offset) -- side by side
		expect(UiHarness.find(first, "Label").Visible).toBe(false)
		expect(UiHarness.find(second, "SlimeName").Text).toBe("Zap")
		expect(UiHarness.find(second, "SlimeState").Text).toBe("Missing")
		local cost = Format.formatCash(Economy.rebirthCost(0))
		expect(UiHarness.find(panel.frame, "Reason").Text).toBe(`Need {cost} and a Zap`)
		expect(UiHarness.find(panel.frame, "Note").Text).toBe(
			"Rebirth uses up the slimes above and resets your cash. "
				.. "You keep your other slimes, your pads and your upgrades."
		)
		-- Back to one slime: the second card hides, the cards sit side by side again.
		panel.update(stateWith(false, 1e9))
		expect(second.Visible).toBe(false)
		expect(UiHarness.find(panel.frame, "Need").Size.X.Scale).toBe(0.5)
		expect(UiHarness.find(first, "Label").Visible).toBe(true)
	end)
	it("Rebirth.plan puts a third slime card on a second row and grows the content", function()
		local Rebirth = UiHarness.ui("Panels/Rebirth")
		local one, two, three = Rebirth.plan(1, 34), Rebirth.plan(2, 34), Rebirth.plan(3, 34)
		expect(one.multi).toBe(false)
		expect(two.multi and three.multi).toBe(true)
		expect(three.cards[3].position.Y.Offset > three.cards[1].position.Y.Offset).toBe(true)
		expect(three.cards[3].position.X.Scale).toBe(0)
		expect(three.height > two.height).toBe(true)
		expect(one.noteY + 34).toBe(one.height)
		local four = Rebirth.plan(4, 34) -- a longer list than any level asks for today still gets a card each
		expect(#four.cards).toBe(4)
		expect(four.cards[4].position.Y.Offset).toBe(four.cards[3].position.Y.Offset)
		expect(Rebirth.subText(4, false)).toBe("You need all five:")
		expect(Rebirth.subText(0, false)).toBe("You need:")
	end)
	it("the lock tile says Max once locks can't grow", function()
		local Rebirth = UiHarness.ui("Panels/Rebirth")
		local panel = Rebirth.new(UiHarness.root(), ctx())
		local state = rebirthState(20, 0)
		state.lockDuration = Config.LOCK_MAX_REMAINING
		panel.update(state)
		expect(UiHarness.find(UiHarness.find(panel.frame, "LockTime"), "Value").Text).toBe("Max")
		state.lockDuration = Config.LOCK_SECONDS
		panel.update(state)
		expect(UiHarness.find(UiHarness.find(panel.frame, "LockTime"), "Value").Text).toBe(
			`+{Config.LOCK_SECONDS_PER_REBIRTH}s`
		)
	end)
end)

describe("v28 item 5: the Guide NPC opens a next-goal + tips card", function()
	it("next goal: the tutorial step first", function()
		local view = GuideTips.view({ tutorialStepId = "Lock", slimes = {} }, RARITY_NAMES, 0)
		expect(view.goal).toBe(GuideTips.STEP_GOALS.Lock)
		expect(view.goalIcon).toBe("🔒")
		expect(#view.tips).toBe(GuideTips.MAX_TIPS)
	end)
	it("tips put urgent things first: a thief, an open plot, a ready rebirth", function()
		local state = {
			slimes = { { slime = { id = "a", tier = 1 }, stolenBy = 7 } },
			lockUntil = 0,
			canRebirth = true,
			padsUnlocked = 4,
			cash = 0,
		}
		local view = GuideTips.view(state, RARITY_NAMES, 100)
		expect(view.tips[1].id).toBe("Stolen")
		expect(view.tips[2].id).toBe("Lock")
		expect(view.tips[3].id).toBe("Rebirth")
	end)
	it("a finished tutorial falls back to goals, and bad state never errors", function()
		local view = GuideTips.view({ slimes = {}, cash = 0 }, RARITY_NAMES, 0)
		expect(type(view.goal)).toBe("string")
		expect(#view.tips >= 1).toBe(true)
		expect(GuideTips.view(nil, RARITY_NAMES, 0).goal).toBe("Grab a slime at the fountain")
	end)
	it("the Guide panel shows the goal and the tips", function()
		local Guide = UiHarness.ui("Panels/Guide")
		local panel = Guide.new(UiHarness.root(), ctx())
		panel.update({ tutorialStepId = "Grab", slimes = {} })
		expect(UiHarness.find(panel.frame, "GoalText").Text).toBe(GuideTips.STEP_GOALS.Grab)
		expect(UiHarness.find(panel.frame, "Tip1").Visible).toBe(true)
		expect(panel.close ~= nil).toBe(true)
	end)
end)
