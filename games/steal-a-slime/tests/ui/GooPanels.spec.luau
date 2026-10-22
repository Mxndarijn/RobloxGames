--!strict
-- The Goo menu panels: every menu on a real server State keeps its text at Layout.MIN_TEXT or more, and the
-- per-screen layouts (Goals' right slot, Codes' error line, the Bag's empty state).
local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Fixtures = require("../Fixtures")
local Genome = require("../../src/shared/Genome")
local Layout = require("../../src/ui/Layout")
local PlotSkins = require("../../src/shared/PlotSkins")
local Remotes = require("../../src/shared/Remotes")
local ServerFixtures = require("../ServerFixtures")
local Snapshot = require("../../src/server/Snapshot")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local T0 = ServerFixtures.T0

local function ctx(requests: { any }?): any
	local function record(action: string, done: any, ...: any)
		table.insert(requests or {}, { action = action, done = done, args = { ... } })
	end
	return {
		Config = Config,
		Constants = Constants,
		Genome = Genome,
		TripleMerge = require("../../src/shared/TripleMerge"),
		vat3Forced = function()
			return false
		end,
		actions = Remotes.ACTIONS,
		itemIcons = UiHarness.ui("ItemIcons").build(Config),
		send = function(action: string, ...: any)
			record(action, nil, ...)
		end,
		request = record,
		ask = record,
		serverNow = function()
			return T0 + 1
		end,
		playerName = function()
			return "Tester"
		end,
		togglePanel = function() end,
		toast = function() end,
	}
end

-- A real State from the server snapshot: three slimes, some cash, a welcome-back report and plot skins.
local function realState(): any
	local world = ServerFixtures.world()
	local session = ServerFixtures.join(world, 1, {
		Fixtures.slime("a", 1),
		Fixtures.slime("b", 2),
		Fixtures.slime("c", 3),
	}, 1240)
	local state = Snapshot.build(world, session, T0 + 1) :: any
	state.welcomeBack = { away = 19800, cash = 12400, grown = 3 }
	state.plotSkins = state.plotSkins or PlotSkins.view(session.data)
	return state
end

-- Every text under `root` smaller than Layout.MIN_TEXT, as "Path (size)", rich-text sizes included.
local function tooSmall(root: any): { string }
	local out = {}
	for _, node in UiHarness.descendants(root) do
		local class = node.ClassName
		if class == "TextLabel" or class == "TextButton" or class == "TextBox" then
			local visible = true
			local p = node
			while p and p ~= root do
				if p.Visible == false then
					visible = false
				end
				p = p.Parent
			end
			if visible and type(node.Text) == "string" and node.Text ~= "" then
				if node.TextSize < Layout.MIN_TEXT then
					table.insert(out, `{node.Name} "{node.Text}" ({node.TextSize})`)
				end
				for size in string.gmatch(node.Text, 'size="(%d+)"') do
					if (tonumber(size) or 0) < Layout.MIN_TEXT then
						table.insert(out, `{node.Name} rich text ({size})`)
					end
				end
			end
		end
	end
	return out
end

describe("Goo menus: no text under Layout.MIN_TEXT", function()
	local MENUS = { "Codes", "Dex", "Goals", "Guide", "Merge", "Rebirth", "Welcome" }
	for _, key in MENUS do
		it(`{key} on a real State`, function()
			local panel = UiHarness.ui(`Panels/{key}`).new(UiHarness.root(), ctx())
			local state = realState()
			if panel.update then
				panel.update(state)
			end
			if panel.setOpen then
				panel.setOpen(true)
			end
			panel.frame.Visible = true
			expect(table.concat(tooSmall(panel.frame), ", ")).toBe("")
		end)
	end
	it("Daily reward on a real State", function()
		local popup = UiHarness.ui("Panels/DailyPopup").new(UiHarness.root(), ctx())
		popup.update(realState())
		popup.open()
		expect(table.concat(tooSmall(popup.frame), ", ")).toBe("")
	end)
	for _, shopId in { "ItemShop", "UpgradeShop" } do
		it(`{shopId} on a real State`, function()
			local panel = UiHarness.ui("Panels/WorldShop").new(UiHarness.root(), ctx())
			panel.setShop(shopId)
			panel.update(realState())
			panel.setOpen(true)
			panel.frame.Visible = true
			expect(table.concat(tooSmall(panel.frame), ", ")).toBe("")
		end)
	end
end)

describe("Goals: one fixed right slot per row", function()
	local function quests(done: boolean, claimed: boolean): any
		return {
			resetsIn = 600,
			quests = {
				{
					id = "Lock",
					title = "Lock your base once",
					progress = if done then 1 else 0,
					target = 1,
					done = done,
					claimed = claimed,
					reward = "+$100",
					rewardKind = "cash",
				},
				{
					id = "Merge",
					title = "Merge 3 times",
					progress = 1,
					target = 3,
					reward = "2x income for 5m",
					rewardKind = "boost",
				},
			},
		}
	end
	local function build(): (any, { any })
		local requests = {}
		local panel = UiHarness.ui("Panels/Goals").new(UiHarness.root(), ctx(requests))
		return panel, requests
	end
	it("an open quest shows its reward in a sunken well the size of Layout.ROW_SLOT", function()
		local Theme = UiHarness.ui("Widgets").Theme
		local panel = build()
		local state = realState()
		state.dailyQuests = quests(false, false)
		panel.update(state)
		local row = UiHarness.find(panel.frame, "Quest_Lock")
		local reward = UiHarness.find(row, "Reward")
		expect(reward.Visible).toBe(true)
		expect(reward.Text).toBe("+$100")
		expect(reward.TextColor3).toBe(Theme.Gold)
		expect(reward.BackgroundColor3).toBe(Theme.Ink)
		expect(reward.Size.X.Offset).toBe(Layout.ROW_SLOT.w)
		expect(reward.Size.Y.Offset).toBe(Layout.ROW_SLOT.h)
		expect(UiHarness.find(row, "Claim").Visible).toBe(false)
		expect(UiHarness.find(UiHarness.find(panel.frame, "Quest_Merge"), "Reward").Text).toBe("2x income for 5m")
	end)
	it("a finished quest swaps the well for a gold 'Claim $100' button of the same size", function()
		local Theme = UiHarness.ui("Widgets").Theme
		local panel, requests = build()
		local state = realState()
		state.dailyQuests = quests(true, false)
		panel.update(state)
		local row = UiHarness.find(panel.frame, "Quest_Lock")
		local claim = UiHarness.find(row, "Claim")
		expect(claim.Visible).toBe(true)
		expect(claim.Text).toBe("Claim $100")
		expect(claim.BackgroundColor3).toBe(Theme.Gold)
		expect(claim.Size.X.Offset).toBe(Layout.ROW_SLOT.w)
		expect(UiHarness.find(row, "Reward").Visible).toBe(false)
		UiHarness.fire(claim, "Activated")
		expect(requests[1].action).toBe("ClaimQuest")
		expect(requests[1].args[1]).toBe(1)
		state.dailyQuests = quests(true, true)
		panel.update(state)
		expect(claim.Visible).toBe(false)
		local well = UiHarness.find(row, "Reward")
		expect(well.Visible).toBe(true)
		expect(well.Text).toBe("✅ Claimed")
		expect(well.TextColor3).toBe(Theme.Good)
	end)
	it("Claim names the cash, or says boost", function()
		local Goals = UiHarness.ui("Panels/Goals")
		expect(Goals.claimText("+$100", false)).toBe("Claim $100")
		expect(Goals.claimText("2x income for 5m", true)).toBe("Claim boost")
		expect(Goals.claimText("", false)).toBe("Claim")
	end)
end)
