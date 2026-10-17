--!strict
-- Overlays, backdrops, cards and banners start hidden and follow their menu:
-- the full-window dim backdrop and the nav highlight are derived from the
-- menu cards' own Visible (never only from setOpen), so a card hidden or
-- shown by Esc, a script or a debug tool can't strand a dim card over the
-- viewport.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox") :: any

local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Genome = require("../../src/shared/Genome")
local Remotes = require("../../src/shared/Remotes")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function read(path: string): string
	return fs.readFile(path)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function ctx(): any
	return {
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
end

local MENUS = {
	Plot = "Plot",
	Merge = "Merge",
	Shop = "Shop",
	Rebirth = "Rebirth",
	Goals = "Goals",
	Dex = "Dex",
	Leaders = "Leaderboard",
	Codes = "Codes",
	Guide = "Guide",
	Welcome = "Welcome",
}

describe("overlays start hidden and follow their menu", function()
	it("every menu card is created hidden, and stays hidden after a State update", function()
		for key, file in MENUS do
			local panel = UiHarness.ui(`Panels/{file}`).new(UiHarness.root(), ctx())
			expect(panel.frame.Visible).toBe(false)
			if panel.update then
				pcall(panel.update, { cash = 0, slimes = {}, rebirths = 0, dex = {}, dexTotal = 1 })
			end
			expect(panel.frame.Visible).toBe(false)
			expect(key ~= "").toBe(true)
		end
	end)
	it("Widgets.panel frames are hidden by default", function()
		local Widgets = UiHarness.ui("Widgets")
		local panel = Widgets.panel(UiHarness.root(), "P", "T", "x", roblox.Color3.new(1, 1, 1))
		expect(panel.frame.Visible).toBe(false)
	end)
	it("popup overlays (daily, tutorial, hint) and every HUD banner start hidden", function()
		local root = UiHarness.root()
		UiHarness.ui("Panels/DailyPopup").new(root, ctx())
		UiHarness.ui("Panels/TutorialOverlay").new(root, ctx())
		UiHarness.ui("Panels/HintOverlay").new(root)
		for _, name in { "DailyPopup", "HintRing" } do
			expect(UiHarness.find(root, name).Visible).toBe(false)
		end
		-- Hud needs services the harness lacks: every banner goes through banner().
		local hud = read("src/ui/Hud.luau")
		local helper = string.match(hud, "local function banner%(.-Parent = parent") or ""
		expect(has(helper, "Visible = false")).toBe(true)
		for _, name in { "StealAlert", "RareBanner", "RainBanner", "PadHint" } do
			expect(has(hud, `banner(banners, "{name}"`)).toBe(true)
		end
	end)
	it("the menu backdrop starts hidden and is derived from the cards' Visible", function()
		local src = read("src/ui/init.client.luau")
		local made = string.match(src, 'Name = "MenuBackdrop".-Parent = gui') or ""
		expect(has(made, "Visible = false")).toBe(true)
		expect(has(src, 'entry.panel.frame:GetPropertyChangedSignal("Visible"):Connect(syncMenus)')).toBe(true)
		expect(has(src, "backdrop.Visible = visibleKey ~= nil")).toBe(true)
		-- setOpen only flips the cards; nothing else writes backdrop.Visible
		local _, writes = string.gsub(src, "backdrop%.Visible =", "")
		expect(writes).toBe(1)
	end)
end)
