--!strict
-- Leaderboard panel (src/ui/Panels/Leaderboard.luau): five board tabs, ten rows, the "You" line.
local Config = require("../../src/shared/Config")
local Layout = require("../../src/ui/Layout")
local Leaderboards = require("../../src/shared/Leaderboards")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local ME = 42

local function build(): any
	local ctx: any = {
		Config = Config,
		userId = ME,
		send = function() end,
		serverNow = function()
			return 0
		end,
	}
	return UiHarness.ui("Panels/Leaderboard").new(UiHarness.root(), ctx)
end

local function board(stat: string, n: number, meAt: number?): any
	local entries = {}
	for k = 1, n do
		table.insert(entries, {
			rank = k,
			userId = if k == meAt then ME else 1000 + k,
			name = if k == meAt then "Me" else `Player{k}`,
			value = (n - k + 1) * 1500,
		})
	end
	return { stat = stat, entries = entries }
end

local function rowFrames(panel: any): { any }
	local list = UiHarness.find(panel.frame, "List")
	local out = {}
	for _, child in list:GetChildren() do
		if string.match(child.Name, "^Row_") then
			table.insert(out, child)
		end
	end
	table.sort(out, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	return out
end

describe("Leaderboard panel", function()
	it("has one tab per board in BOARDS order, Earners shown first in its accent colour", function()
		local Panel = UiHarness.ui("Panels/Leaderboard")
		local Widgets = UiHarness.ui("Widgets")
		local panel = build()
		local labels = {}
		for _, def in Leaderboards.BOARDS do
			local tab = UiHarness.find(panel.frame, `Tab_{def.stat}`)
			expect(tab ~= nil).toBe(true)
			table.insert(labels, tab.Text)
			local on = def.stat == "TotalEarned"
			expect(tab:GetAttribute("Selected")).toBe(on)
			expect(tab.BackgroundColor3).toBe(if on then Widgets.color3(def.accent) else Widgets.Theme.Info)
		end
		expect(table.concat(labels, ",")).toBe("SlimeDex,Weekly,Earners,Steals,Merges")
		expect(Panel.DEFAULT).toBe("TotalEarned")
		expect(UiHarness.find(panel.frame, "BoardTitle").Text).toBe("Top Earners")
	end)

	it("switches boards from a tab and shows that board's rows", function()
		local panel = build()
		panel.setBoard(board("TotalEarned", 3))
		panel.setBoard(board("Steals", 2))
		expect(#rowFrames(panel)).toBe(3)
		UiHarness.fire(UiHarness.find(panel.frame, "Tab_Steals"), "Activated")
		expect(UiHarness.find(panel.frame, "BoardTitle").Text).toBe("Top Steals")
		expect(UiHarness.find(panel.frame, "Tab_Steals"):GetAttribute("Selected")).toBe(true)
		expect(UiHarness.find(panel.frame, "Tab_TotalEarned"):GetAttribute("Selected")).toBe(false)
		local rows = rowFrames(panel)
		expect(#rows).toBe(2)
		expect(UiHarness.find(rows[1], "Value").Text).toBe("3K")
	end)

	it("formats rows as #rank, name and value: $ on cash boards, plain counts otherwise", function()
		local Theme = UiHarness.ui("Widgets").Theme
		local panel = build()
		panel.setBoard(board("TotalEarned", 12))
		local rows = rowFrames(panel)
		expect(#rows).toBe(10)
		expect(UiHarness.find(rows[1], "Rank").Text).toBe("#1")
		expect(UiHarness.find(rows[1], "Name").Text).toBe("Player1")
		expect(UiHarness.find(rows[1], "Value").Text).toBe(Leaderboards.format("TotalEarned", 12 * 1500))
		expect(string.sub(UiHarness.find(rows[1], "Value").Text, 1, 1)).toBe("$")
		expect(UiHarness.find(rows[1], "Rank").TextColor3).toBe(Theme.Gold)
		expect(UiHarness.find(rows[10], "Rank").TextColor3).toBe(Theme.Muted)
		panel.setBoard(board("Merges", 1))
		panel.select("Merges")
		local merges = rowFrames(panel)
		expect(UiHarness.find(merges[1], "Value").Text).toBe("1.5K")
	end)

	it("only redraws for the board that is shown", function()
		local panel = build()
		panel.setBoard(board("TotalEarned", 4))
		panel.setBoard(board("Dex", 1))
		expect(#rowFrames(panel)).toBe(4)
		panel.select("Dex")
		expect(#rowFrames(panel)).toBe(1)
	end)

	it("highlights the local player's own row", function()
		local Theme = UiHarness.ui("Widgets").Theme
		local panel = build()
		panel.setBoard(board("TotalEarned", 5, 3))
		local rows = rowFrames(panel)
		expect(rows[3].BackgroundColor3).toBe(Theme.BgLight)
		expect(UiHarness.find(rows[3], "Name").TextColor3).toBe(Theme.Good)
		expect(rows[2].BackgroundColor3).toBe(Theme.Row)
	end)

	it("the You line gives your rank in the top 10, else your value from State.boards", function()
		local panel = build()
		local you = UiHarness.find(panel.frame, "You")
		panel.update({ boards = { TotalEarned = 9000, Steals = 7 } })
		panel.setBoard(board("TotalEarned", 5, 2))
		expect(you.Text).toBe(`You: #2  {Leaderboards.format("TotalEarned", 4 * 1500)}`)
		panel.setBoard(board("TotalEarned", 5))
		expect(you.Text).toBe("You: $9K (not in the top 10)")
		panel.select("Steals")
		expect(you.Text).toBe("You: 7 (not in the top 10)")
		panel.select("Merges")
		expect(you.Text).toBe("You: no score yet")
	end)

	it("an empty board shows one muted line instead of rows", function()
		local Theme = UiHarness.ui("Widgets").Theme
		local panel = build()
		local empty = UiHarness.find(panel.frame, "Empty")
		expect(empty.Visible).toBe(true)
		panel.setBoard({ stat = "TotalEarned", entries = {} })
		expect(empty.Visible).toBe(true)
		expect(empty.Text).toBe("No entries yet")
		expect(empty.TextColor3).toBe(Theme.Muted)
		expect(#rowFrames(panel)).toBe(0)
		panel.setBoard(board("TotalEarned", 1))
		expect(empty.Visible).toBe(false)
	end)

	it("ignores payloads for unknown boards", function()
		local panel = build()
		panel.setBoard({ stat = "Nope", entries = { { rank = 1, userId = 1, name = "x", value = 1 } } })
		panel.setBoard(nil)
		expect(#rowFrames(panel)).toBe(0)
	end)

	it("tab labels fit five across the narrowest menu card", function()
		local Panel = UiHarness.ui("Panels/Leaderboard")
		local R = Panel.ROWS
		local narrowest = math.huge
		for _, vp in { { 390, 844 }, { 844, 390 }, { 844, 332 } } do
			local s = Layout.screen(vp[1], vp[2])
			narrowest = math.min(narrowest, s.menuW)
		end
		local body = narrowest - Layout.PANEL_CHROME.pad * 2
		local count = #Leaderboards.BOARDS
		local tabW = (body - R.tabs.gap * (count - 1)) / count
		for _, label in Panel.TABS do
			expect(Layout.lineWidth(label, R.tabs.size) + 8 <= tabW).toBe(true)
		end
	end)
end)

describe("Leaderboard panel text", function()
	it("youText falls back to the plain value outside the top 10", function()
		local Panel = UiHarness.ui("Panels/Leaderboard")
		local rows = Panel.rows(board("Steals", 3), ME)
		expect(Panel.youText(rows, "Steals", 12)).toBe("You: 12 (not in the top 10)")
		expect(Panel.youText(rows, "Steals", nil)).toBe("You: no score yet")
		local mineRows = Panel.rows(board("Steals", 3, 1), ME)
		expect(mineRows[1].isMe).toBe(true)
		expect(Panel.youText(mineRows, "Steals", 12)).toBe("You: #1  4.5K")
	end)
end)
