--!strict
-- v28 menu pass (Merijn's playtest of v27, items 1-5): content-sized menu
-- cards with an icon band and close X, real slime renders in the SlimeDex,
-- a Rebirth card that shows only the next rebirth, and a Guide NPC that opens a next-goal / tips card.
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
local LayoutAssert = require("./LayoutAssert")
local Progress = require("../../src/ui/Progress")
local Remotes = require("../../src/shared/Remotes")
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

-- A Rebirth row's check is built the first time the row is met, so a row that never was has none.
local function tickShown(row: any): boolean
	local tick = row:FindFirstChild("Tick")
	return tick ~= nil and tick.Visible
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
		nextRebirthMultiplier = Economy.rebirthMultiplier(math.min(rebirths + 1, Config.MAX_REBIRTHS)),
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
	it("an unfound species never shows the generated model (it does not look like the species): a grey blob", function()
		local SlimePreview = UiHarness.ui("SlimePreview")
		local panel = openDex(DEX, { buildSlime = fakeBuild })
		local locked = UiHarness.find(UiHarness.find(panel.frame, "List"), "gummy")
		local preview = locked:FindFirstChild("Image"):FindFirstChild("Preview")
		expect(UiHarness.find(preview, "Slime_Dex_gummy")).toBeNil()
		expect(UiHarness.find(preview, "Body").Color).toBe(SlimePreview.GREYED)
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
	it("the Resets well never lists the cash on the cash pads: rebirth keeps it", function()
		local Rebirth = UiHarness.ui("Panels/Rebirth")
		local panel = Rebirth.new(UiHarness.root(), ctx())
		local state = rebirthState(0, 10)
		state.padCash = 1500
		panel.update(state)
		local reset = UiHarness.find(UiHarness.find(panel.frame, "Reset"), "Body")
		expect(has(reset.Text, "pads")).toBe(false)
		expect(has(reset.Text, Format.formatCash(1500))).toBe(false)
	end)
	it("the panel shows the next rebirth only: hero, cash row and the reason well, then the button", function()
		local Rebirth = UiHarness.ui("Panels/Rebirth")
		local Theme = UiHarness.ui("Widgets").Theme
		local panel = Rebirth.new(UiHarness.root(), ctx())
		local cost = Economy.rebirthCost(0)
		panel.update(rebirthState(0, cost / 2))
		expect(panel.frame:FindFirstChild("Title").Text).toBe("Next rebirth: 1")
		local hero = UiHarness.find(panel.frame, "Hero")
		expect(UiHarness.find(UiHarness.find(hero, "Now"), "Label").Text).toBe("Now · Rebirth 0")
		expect(UiHarness.find(UiHarness.find(hero, "Next"), "Label").Text).toBe("After Rebirth 1")
		expect(UiHarness.find(UiHarness.find(hero, "Now"), "Value").Text).toBe(Format.formatMultiplier(1))
		expect(UiHarness.find(UiHarness.find(hero, "Next"), "Value").Text).toBe(
			Format.formatMultiplier(Economy.rebirthMultiplier(1))
		)
		local costLabel = UiHarness.find(panel.frame, "Cost")
		expect(costLabel.Text).toBe(Format.formatCash(cost))
		expect(costLabel.TextColor3).toBe(Theme.Muted) -- can't pay it yet
		local cashRow = UiHarness.find(panel.frame, "Need")
		expect(UiHarness.find(cashRow, "Have").Visible).toBe(true)
		expect(tickShown(cashRow)).toBe(false)
		expect(UiHarness.find(panel.frame, "Count").Text).toBe("0 of 1 ready")
		-- Not ready: no button, a sunken well with what is missing.
		local button = UiHarness.find(panel.frame, "RebirthButton")
		local reason = UiHarness.find(panel.frame, "Reason")
		expect(button.Visible).toBe(false)
		expect(button.AutoButtonColor).toBe(false)
		expect(reason.Visible).toBe(true)
		expect(reason.Text).toBe(`Need {Format.formatCash(cost - cost / 2)} more`)
		panel.update(rebirthState(0, cost))
		expect(costLabel.TextColor3).toBe(Theme.Gold)
		expect(UiHarness.find(cashRow, "Have").Visible).toBe(false)
		expect(tickShown(cashRow)).toBe(true)
		expect(UiHarness.find(panel.frame, "Count").Text).toBe("1 of 1 ready")
		expect(reason.Visible).toBe(false)
		expect(button.Visible).toBe(true)
		expect(button.AutoButtonColor).toBe(true)
		expect(button.Text).toBe("Hold to rebirth")
		expect(button.BackgroundColor3).toBe(Theme.Accent)
		-- The only later rebirth it names is the next rank's.
		for _, node in UiHarness.descendants(panel.frame) do
			if (node.ClassName == "TextLabel" or node.ClassName == "TextButton") and node.Name ~= "RankTitle" then
				expect(has(string.upper(node.Text), "REBIRTH 2")).toBe(false)
			end
		end
	end)
	it("the title and hero name the next rebirth, never just the number", function()
		local Rebirth = UiHarness.ui("Panels/Rebirth")
		expect(Rebirth.titleText(3, false)).toBe("Next rebirth: 4")
		expect(Rebirth.titleText(Config.MAX_REBIRTHS, true)).toBe(`Max rebirth: {Config.MAX_REBIRTHS}`)
		local now, after = Rebirth.heroLabels(3)
		expect(now).toBe("Now · Rebirth 3")
		expect(after).toBe("After Rebirth 4")
		local panel = Rebirth.new(UiHarness.root(), ctx())
		panel.update(rebirthState(3, 0))
		expect(panel.frame:FindFirstChild("Title").Text).toBe("Next rebirth: 4")
	end)
	it("the rank row: Gold 'New rank' when this rebirth reaches one, else the next rank ahead", function()
		local Rebirth = UiHarness.ui("Panels/Rebirth")
		local Theme = UiHarness.ui("Widgets").Theme
		local up = Rebirth.rank(5, Config.REBIRTH_TIERS) :: any -- rebirth 6: Goo Tycoon
		expect(up.up).toBe(true)
		expect(up.title).toBe("New rank: Goo Tycoon")
		expect(up.desc).toBe("Grows the Frost & Sea Fountain")
		expect(up.income).toBe("+5% income")
		local unlock = Rebirth.rank(0, Config.REBIRTH_TIERS) :: any -- rebirth 1: Goo Getter
		expect(has(unlock.desc, "Unlocks the Strong Arms upgrade")).toBe(true)
		expect(has(unlock.desc, "merges")).toBe(true)
		expect(unlock.income).toBeNil()
		local ahead = Rebirth.rank(23, Config.REBIRTH_TIERS) :: any -- rebirth 24, Goo Titan at 25
		expect(ahead.up).toBe(false)
		expect(ahead.title).toBe("Next rank at Rebirth 25")
		expect(ahead.desc).toBe("Goo Titan: +150% income, opens Celestial merges")
		local last = Config.REBIRTH_TIERS[#Config.REBIRTH_TIERS].rebirths
		expect(Rebirth.rank(last, Config.REBIRTH_TIERS)).toBeNil()
		-- No rank line is longer than the worst case LayoutAssert measures at every viewport.
		local worst = LayoutAssert.rebirthTexts(Layout.panelFor(Layout.screen(390, 844), "Rebirth"))
		local widest = { title = 0, desc = 0 }
		for _, desc in worst do
			if desc.name == "Rebirth rank title" then
				widest.title = Layout.lineWidth(desc.text, desc.size, true)
			elseif desc.name == "Rebirth rank desc" then
				widest.desc = Layout.lineWidth(desc.text, desc.size)
			end
		end
		for r = 0, Config.MAX_REBIRTHS - 1 do
			local view = Rebirth.rank(r, Config.REBIRTH_TIERS)
			if view then
				expect(Layout.lineWidth(view.title, 17, true) <= widest.title).toBe(true)
				expect(Layout.lineWidth(view.desc, 14) <= widest.desc).toBe(true)
			end
		end

		local panel = Rebirth.new(UiHarness.root(), ctx())
		panel.update(rebirthState(5, 0))
		local row = UiHarness.find(panel.frame, "Rank")
		expect(row.Visible).toBe(true)
		expect(UiHarness.find(row, "RankTitle").TextColor3).toBe(Theme.Gold)
		local chip = UiHarness.find(panel.frame, "RankIncome")
		expect(chip.Visible).toBe(true)
		expect(chip.Text).toBe("Rank bonus +5% income")
		panel.update(rebirthState(23, 0))
		expect(UiHarness.find(row, "RankTitle").Text).toBe("Next rank at Rebirth 25")
		expect(chip.Visible).toBe(false)
		panel.update(rebirthState(last, 0))
		expect(row.Visible).toBe(false)
	end)
	it("at max rebirths only the crown card and the done well show", function()
		local Rebirth = UiHarness.ui("Panels/Rebirth")
		local panel = Rebirth.new(UiHarness.root(), ctx())
		panel.update(rebirthState(Config.MAX_REBIRTHS, 0))
		expect(panel.frame:FindFirstChild("Title").Text).toBe(`Max rebirth: {Config.MAX_REBIRTHS}`)
		local crown = UiHarness.find(panel.frame, "Crown")
		expect(crown.Visible).toBe(true)
		expect(UiHarness.find(crown, "CrownTitle").Text).toBe(Config.REBIRTH_TIERS[#Config.REBIRTH_TIERS].title)
		expect(UiHarness.find(UiHarness.find(crown, "Rebirths"), "Value").Text).toBe(tostring(Config.MAX_REBIRTHS))
		for _, name in { "Hero", "Perks", "Rank", "Need", "Keep", "Head" } do
			expect(UiHarness.find(panel.frame, name).Visible).toBe(false)
		end
		expect(UiHarness.find(panel.frame, "Reason").Text).toBe("All rebirths done")
		expect(UiHarness.find(panel.frame, "RebirthButton").Visible).toBe(false)
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
	it("the panel shows the missing slime greyed out with the reason, then a tick and the button", function()
		local Rebirth = UiHarness.ui("Panels/Rebirth")
		local panel = Rebirth.new(UiHarness.root(), ctx())
		panel.update(stateWith(false, 1e9))
		local row = UiHarness.find(panel.frame, "SlimeNeed")
		expect(UiHarness.find(row, "SlimeName").Text).toBe("Sprout Slime")
		local stamp = UiHarness.find(row, "SlimeState")
		expect(stamp.Visible).toBe(true)
		expect(stamp.Text).toBe("Missing")
		expect(tickShown(row)).toBe(false)
		expect(UiHarness.find(row, "SlimeDesc").Text).toBe("Catch or merge one")
		expect(UiHarness.find(panel.frame, "Count").Text).toBe("1 of 2 ready")
		-- greyed out, not the black silhouette: the preview body is the grey tint
		local preview = UiHarness.find(row, "Preview")
		expect(preview.ImageTransparency > 0).toBe(true)
		local body = UiHarness.find(preview, "Body")
		expect(body.Color).toBe(UiHarness.ui("SlimePreview").GREYED)
		local button = UiHarness.find(panel.frame, "RebirthButton")
		local reason = UiHarness.find(panel.frame, "Reason")
		expect(button.Visible).toBe(false)
		expect(reason.Text).toBe("Need a Sprout Slime")
		panel.update(stateWith(true, 1e9))
		expect(stamp.Visible).toBe(false)
		expect(tickShown(row)).toBe(true)
		expect(UiHarness.find(row, "SlimeDesc").Text).toBe("Used up on rebirth")
		expect(UiHarness.find(panel.frame, "Count").Text).toBe("2 of 2 ready")
		expect(preview.ImageTransparency).toBe(0)
		expect(reason.Visible).toBe(false)
		expect(button.Visible).toBe(true)
		panel.update(rebirthState(0, 0))
		expect(row.Visible).toBe(false)
	end)
	it("a missing merge-only slime says it comes from a merge", function()
		local Rebirth = UiHarness.ui("Panels/Rebirth")
		local panel = Rebirth.new(UiHarness.root(), ctx())
		local state = stateWith(false, 1e9)
		state.rebirthSlimes = {
			need({ id = "moo_shroom", name = "Moo-shroom", tier = 4, color = { 200, 120, 90 } }, false),
		}
		panel.update(state)
		local row = UiHarness.find(panel.frame, "SlimeNeed")
		expect(UiHarness.find(row, "SlimeDesc").Text).toBe("Obtained by merge (see SlimeDex)")
		state.rebirthSlimes[1].owned = true
		panel.update(state)
		expect(UiHarness.find(row, "SlimeDesc").Text).toBe("Used up on rebirth")
	end)
	it("a missing slime is its own species mesh in grey, never a generated look-alike", function()
		local Rebirth = UiHarness.ui("Panels/Rebirth")
		local generated = 0
		local function mesh(name: string): any
			local model = UiHarness.Instance.new("Model")
			model.Name = name
			local part = UiHarness.Instance.new("Part")
			part.Name = "Mesh"
			part.Parent = model
			return model
		end
		local panel = Rebirth.new(
			UiHarness.root(),
			ctx({
				buildSpecies = function(id: string)
					return mesh(`Dex_{id}`)
				end,
				buildGreySpecies = function(id: string)
					return mesh(`Grey_{id}`)
				end,
				buildSlime = function()
					generated += 1
					return mesh("Generated")
				end,
			})
		)
		panel.update(stateWith(false, 1e9))
		local preview = UiHarness.find(UiHarness.find(panel.frame, "SlimeNeed"), "Preview")
		expect(UiHarness.find(preview, "Grey_sprout") ~= nil).toBe(true)
		panel.update(stateWith(true, 1e9))
		expect(UiHarness.find(preview, "Dex_sprout") ~= nil).toBe(true)
		expect(generated).toBe(0)
	end)
	it("several slimes: one row each under the cash row, the reason names cash and slimes", function()
		local Rebirth = UiHarness.ui("Panels/Rebirth")
		local panel = Rebirth.new(UiHarness.root(), ctx())
		local state = rebirthState(0, 0)
		state.rebirthSlimes = { need(SPROUT, true), need(ZAP, false) }
		state.canRebirth = false
		panel.update(state)
		local cash = UiHarness.find(panel.frame, "Need")
		local first = UiHarness.find(panel.frame, "SlimeNeed")
		local second = UiHarness.find(panel.frame, "SlimeNeed2")
		expect(first.Visible and second.Visible).toBe(true)
		expect(first.Position.Y.Offset > cash.Position.Y.Offset).toBe(true)
		expect(second.Position.Y.Offset > first.Position.Y.Offset).toBe(true)
		expect(UiHarness.find(second, "SlimeName").Text).toBe("Zap")
		expect(UiHarness.find(second, "SlimeState").Text).toBe("Missing")
		expect(UiHarness.find(panel.frame, "Count").Text).toBe("1 of 3 ready")
		local cost = Format.formatCash(Economy.rebirthCost(0))
		expect(UiHarness.find(panel.frame, "Reason").Text).toBe(`Need {cost} and a Zap`)
		local keep = UiHarness.find(panel.frame, "Keep")
		expect(UiHarness.find(UiHarness.find(keep, "Kept"), "Body").Text).toBe(Rebirth.COPY.keep)
		expect(UiHarness.find(UiHarness.find(keep, "Reset"), "Body").Text).toBe(Rebirth.COPY.reset)
		panel.update(stateWith(false, 1e9))
		expect(second.Visible).toBe(false)
		panel.update(rebirthState(0, 0))
		expect(UiHarness.find(UiHarness.find(keep, "Reset"), "Body").Text).toBe(Rebirth.COPY.resetCash)
	end)
	it("Rebirth.plan stacks one row per need and grows with slimes and the rank row", function()
		local Rebirth = UiHarness.ui("Panels/Rebirth")
		local one, three = Rebirth.plan(1, true), Rebirth.plan(3, true)
		expect(#one.rows).toBe(2)
		expect(#three.rows).toBe(4)
		expect(three.rows[4] > three.rows[3]).toBe(true)
		expect(three.height > one.height).toBe(true)
		expect(three.buttonY + Layout.BUTTON).toBe(three.height)
		local noRank = Rebirth.plan(3, false)
		expect(noRank.rankY).toBeNil()
		expect(noRank.height < three.height).toBe(true)
		expect(#Rebirth.plan(4, true).rows).toBe(5) -- a longer list than any level asks for today still gets a row each
		expect(Rebirth.countText(1, 3)).toBe("1 of 3 ready")
	end)
	it("the lock chip says it is maxed once locks can't grow", function()
		local Rebirth = UiHarness.ui("Panels/Rebirth")
		local panel = Rebirth.new(UiHarness.root(), ctx())
		local state = rebirthState(20, 0)
		state.lockDuration = Config.LOCK_MAX_SECONDS
		panel.update(state)
		expect(UiHarness.find(panel.frame, "LockTime").Text).toBe(Rebirth.COPY.lockMax)
		state.lockDuration = Config.LOCK_SECONDS
		panel.update(state)
		expect(UiHarness.find(panel.frame, "LockTime").Text).toBe(`+{Config.LOCK_SECONDS_PER_REBIRTH}s lock time`)
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
		expect(UiHarness.find(panel.frame, "Tip2").Visible).toBe(true) -- Skip has the first slot
		expect(panel.close ~= nil).toBe(true)
		expect(UiHarness.find(panel.frame, "ShowTutorial").Visible).toBe(false)
	end)
	it("after the tutorial card is hidden the Guide offers it again, opens it and closes", function()
		local Guide = UiHarness.ui("Panels/Guide")
		local root = UiHarness.root()
		local card = UiHarness.ui("TutorialCard").new(root, {}, 2)
		local toggled: { string } = {}
		local panel = Guide.new(
			root,
			ctx({
				tutorial = card,
				togglePanel = function(key: string)
					table.insert(toggled, key)
				end,
			})
		)
		local state = { tutorialStepId = "Grab", slimes = {} }
		card.update(state)
		UiHarness.fire(UiHarness.find(card.frame, "Hide"), "Activated")
		expect(card.hidden()).toBe(true)
		panel.update(state)
		local show = UiHarness.find(panel.frame, "ShowTutorial")
		local skip = UiHarness.find(panel.frame, "SkipTutorial")
		expect(show.Visible).toBe(true)
		expect(skip.Visible).toBe(true)
		-- the two tutorial buttons take the first two slots, the tips follow
		expect(show.Position.Y.Offset < skip.Position.Y.Offset).toBe(true)
		expect(UiHarness.find(panel.frame, "Tip1").Visible).toBe(false)
		expect(UiHarness.find(panel.frame, "Tip2").Visible).toBe(false)
		expect(UiHarness.find(panel.frame, "Tip3").Visible).toBe(true)
		UiHarness.fire(show, "Activated")
		expect(card.hidden()).toBe(false)
		expect(card.shown()).toBe(true)
		expect(toggled[1]).toBe("Guide")
		panel.update(state)
		expect(show.Visible).toBe(false)
		expect(UiHarness.find(panel.frame, "Tip1").Visible).toBe(false) -- Skip keeps the first slot
		expect(UiHarness.find(panel.frame, "Tip2").Visible).toBe(true)
	end)
	it("Skip shows only while the tutorial runs, beside the tips", function()
		local Guide = UiHarness.ui("Panels/Guide")
		local panel = Guide.new(UiHarness.root(), ctx())
		panel.update({ tutorialStepId = "Merge", slimes = {} })
		expect(UiHarness.find(panel.frame, "SkipTutorial").Visible).toBe(true)
		expect(UiHarness.find(panel.frame, "SkipTutorial").Text).toBe(Guide.SKIP_TEXT)
		expect(UiHarness.find(panel.frame, "Tip1").Visible).toBe(false)
		expect(UiHarness.find(panel.frame, "Tip2").Visible).toBe(true)
		panel.update({ slimes = {} })
		expect(UiHarness.find(panel.frame, "SkipTutorial").Visible).toBe(false)
		expect(UiHarness.find(panel.frame, "Tip1").Visible).toBe(true)
	end)
	it("holding Skip asks the server to end the tutorial, with no Tutorial done card after", function()
		local Guide = UiHarness.ui("Panels/Guide")
		local root = UiHarness.root()
		local card = UiHarness.ui("TutorialCard").new(root, {}, 2)
		local sent: { string } = {}
		local panel = Guide.new(
			root,
			ctx({
				tutorial = card,
				send = function(action: string)
					table.insert(sent, action)
				end,
			})
		)
		local state = { tutorialStepId = "Lock", slimes = {} }
		card.update(state)
		panel.update(state)
		panel.frame.Visible = true
		local skip = UiHarness.find(panel.frame, "SkipTutorial")
		UiHarness.virtualTime(true)
		UiHarness.fire(skip, "InputBegan", { UserInputType = roblox.Enum.UserInputType.MouseButton1 })
		UiHarness.renderStep()
		expect(#sent).toBe(0) -- a tap is not enough
		UiHarness.advance(Config.HOLD_CONFIRM_SECONDS + 0.1)
		UiHarness.renderStep()
		UiHarness.virtualTime(false)
		expect(table.concat(sent, ",")).toBe("SkipTutorial")
		card.update({ slimes = {} }) -- the server ended the tutorial
		expect(card.finishedShowing()).toBe(false)
		expect(card.frame.Visible).toBe(false)
	end)
end)
