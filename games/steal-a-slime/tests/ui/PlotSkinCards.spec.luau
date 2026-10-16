--!strict
-- The plot skin picker (gaps #15, FEATURES.PlotSkins): a small card list at the top of the SlimeDex
-- panel with locked / unlocked state and the Dex-set progress; nothing at all without State.plotSkins.
local fs = require("@lune/fs")

local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Genome = require("../../src/shared/Genome")
local PlayerData = require("../../src/shared/PlayerData")
local PlotSkins = require("../../src/shared/PlotSkins")
local Remotes = require("../../src/shared/Remotes")
local SlimeDex = require("../../src/ui/SlimeDex")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local UDim2 = (require("@lune/roblox") :: any).UDim2
local TOTAL = Config.MAX_TIER * (#Config.MUTATIONS + 1 + #Config.COMBOS) * #Config.PATTERNS * #Config.EYES

local function view(commonOwned: number, equipped: string?): { any }
	local data = PlayerData.new()
	local n = 0
	for _, m in
		{
			"None",
			"Glow",
			"Lava",
			"Galaxy",
			"Rainbow",
			"Gold",
			"Crystal",
			"Eclipse",
			"Solar",
			"Nebula",
			"Aurora",
			"Royal",
		}
	do
		for _, p in Config.PATTERNS do
			for _, e in Config.EYES do
				if n < commonOwned then
					data.dex[`1:{m}:{p}:{e}`] = true
					n += 1
				end
			end
		end
	end
	data.plotSkin = equipped or "classic"
	return PlotSkins.view(data)
end

local function ctx(requests: { any }?): any
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
		request = function(action: string, _cb: any, ...: any)
			table.insert(requests or {}, { action, ... })
		end,
	}
end

local function openDex(skins: any, requests: { any }?): any
	local Dex = UiHarness.ui("Panels/Dex")
	local panel = Dex.new(UiHarness.root(), ctx(requests))
	panel.frame.Size = UDim2.fromOffset(560, 600)
	panel.setOpen(true)
	panel.update({ dex = { "1:None:Plain:Round" }, dexTotal = TOTAL, plotSkins = skins })
	return panel
end

describe("plot skin cards (SlimeDex.skinRows)", function()
	it("is empty without State.plotSkins (flag off)", function()
		expect(#SlimeDex.skinRows(nil, Config)).toBe(0)
		expect(#SlimeDex.skinRows("junk", Config)).toBe(0)
		expect(#SlimeDex.skinRows({}, Config)).toBe(0)
	end)
	it("one card per skin: classic first, locked ones show their set progress", function()
		local rows = SlimeDex.skinRows(view(100), Config)
		expect(#rows).toBe(#Config.PLOT_SKINS)
		expect(rows[1].key).toBe("skin:classic")
		expect(rows[1].skin.equipped).toBe(true)
		expect(rows[1].detail).toBe("Equipped · Default look")
		expect(rows[2].locked).toBe(true)
		expect(rows[2].detail).toBe("Common set: 100/216 to unlock")
		expect(rows[2].title).toBe("Plot skin · Mushroom Meadow")
		expect(rows[2].skin.unlocked).toBe(false)
	end)
	it("an unlocked skin says so and an equipped one says Equipped", function()
		local unlocked = SlimeDex.skinRows(view(216), Config)[2]
		expect(unlocked.detail).toBe("Unlocked · Common set")
		expect(unlocked.skin.unlocked and not unlocked.skin.equipped).toBe(true)
		local equipped = SlimeDex.skinRows(view(216, "mushroom"), Config)[2]
		expect(equipped.detail).toBe("Equipped · Common set")
		expect(equipped.skin.equipped).toBe(true)
	end)
end)

describe("plot skin cards in the Dex panel", function()
	it("lists the cards above the slime rows, with Equip / Equipped / Locked buttons", function()
		local panel = openDex(view(216))
		local list = UiHarness.find(panel.frame, "List")
		local classic = list:FindFirstChild("skin:classic")
		local mushroom = list:FindFirstChild("skin:mushroom")
		local candy = list:FindFirstChild("skin:candy")
		expect(classic ~= nil and mushroom ~= nil and candy ~= nil).toBe(true)
		expect(classic:FindFirstChild("Equip").Text).toBe("Equipped")
		expect(mushroom:FindFirstChild("Equip").Text).toBe("Equip")
		expect(candy:FindFirstChild("Equip").Text).toBe("Locked")
		expect(mushroom:FindFirstChild("Equip").Visible).toBe(true)
		expect(classic.LayoutOrder < list:FindFirstChild("1:None:Plain:Round").LayoutOrder).toBe(true)
		expect(candy:GetAttribute("Locked")).toBe(true)
		expect(mushroom:GetAttribute("SkinId")).toBe("mushroom")
	end)
	it("slime rows carry no Equip button, and without plotSkins there are no cards at all", function()
		local panel = openDex(nil)
		local list = UiHarness.find(panel.frame, "List")
		expect(list:FindFirstChild("skin:classic")).toBeNil()
		local row = list:FindFirstChild("1:None:Plain:Round")
		expect(row:FindFirstChild("Equip").Visible).toBe(false)
	end)
	it("Equip asks the server with EquipPlotSkin(skinId) and decides nothing itself", function()
		local src = fs.readFile("src/ui/Panels/Dex.luau")
		expect(string.find(src, 'ctx.request("EquipPlotSkin", function() end, id)', 1, true) ~= nil).toBe(true)
		expect(string.find(src, "data.plotSkin", 1, true)).toBeNil()
	end)
	it("the Studio-only PcwPlotSkin hook fakes the picker for shots and is refreshed live", function()
		local src = fs.readFile("src/ui/init.client.luau")
		expect(string.find(src, 'gui:GetAttribute("PcwPlotSkin")', 1, true) ~= nil).toBe(true)
		expect(string.find(src, "if isStudio then", 1, true) ~= nil).toBe(true)
		expect(string.find(src, '"PcwPlotSkin",', 1, true) ~= nil).toBe(true)
	end)
end)
