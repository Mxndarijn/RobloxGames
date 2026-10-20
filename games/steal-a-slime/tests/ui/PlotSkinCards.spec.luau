--!strict
-- The plot skin picker (gaps #15, FEATURES.PlotSkins): a small card list at the top of the SlimeDex
-- panel with locked / unlocked state and the Dex-set progress; nothing at all without State.plotSkins.
local fs = require("@lune/fs")

local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Fixtures = require("../Fixtures")
local Genome = require("../../src/shared/Genome")
local PlayerData = require("../../src/shared/PlayerData")
local PlotSkins = require("../../src/shared/PlotSkins")
local Remotes = require("../../src/shared/Remotes")
local SlimeDex = require("../../src/ui/SlimeDex")
local SpeciesDex = require("../../src/shared/SpeciesDex")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local UDim2 = (require("@lune/roblox") :: any).UDim2

-- Common species in the set and how many found to unlock it.
local COMMON = SpeciesDex.tierSize(1)
local NEED = math.ceil(COMMON * 0.75)

local function view(commonOwned: number, equipped: string?): { any }
	local data = PlayerData.new()
	local n = 0
	for _, entry in SpeciesDex.ENTRIES do
		if entry.tier == 1 and n < commonOwned then
			data.found[entry.id] = true
			n += 1
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
	panel.update({ dex = Fixtures.dex({ "gummy" }), plotSkins = skins })
	return panel
end

describe("plot skin cards (SlimeDex.skinRows)", function()
	it("is empty without State.plotSkins (flag off)", function()
		expect(#SlimeDex.skinRows(nil, Config)).toBe(0)
		expect(#SlimeDex.skinRows("junk", Config)).toBe(0)
		expect(#SlimeDex.skinRows({}, Config)).toBe(0)
	end)
	it("one card per skin: classic first, locked ones show their set progress", function()
		local rows = SlimeDex.skinRows(view(NEED - 1), Config)
		expect(#rows).toBe(#Config.PLOT_SKINS)
		expect(rows[1].key).toBe("skin:classic")
		expect(rows[1].skin.equipped).toBe(true)
		expect(rows[1].detail).toBe("Default look")
		expect(rows[2].locked).toBe(true)
		expect(rows[2].detail).toBe(`Find {NEED} Common species ({NEED - 1}/{NEED})`)
		expect(rows[2].fraction).toBeCloseTo((NEED - 1) / NEED)
		expect(rows[2].title).toBe("Mushroom Meadow")
		expect(rows[2].skin.unlocked).toBe(false)
	end)
	it("an unlocked skin says so and an equipped one says Equipped", function()
		local unlocked = SlimeDex.skinRows(view(NEED), Config)[2]
		expect(unlocked.detail).toBe("Common set")
		expect(unlocked.fraction).toBe(1)
		expect(unlocked.skin.unlocked and not unlocked.skin.equipped).toBe(true)
		local equipped = SlimeDex.skinRows(view(NEED, "mushroom"), Config)[2]
		expect(equipped.detail).toBe("Common set")
		expect(equipped.skin.equipped).toBe(true)
	end)
end)

describe("plot skin cards in the Dex panel", function()
	it("lists the cards above the slime rows: Equipped stamp, Equip button, unlock progress", function()
		local panel = openDex(view(NEED))
		local list = UiHarness.find(panel.frame, "List")
		local classic = list:FindFirstChild("skin:classic")
		local mushroom = list:FindFirstChild("skin:mushroom")
		local candy = list:FindFirstChild("skin:candy")
		expect(classic ~= nil and mushroom ~= nil and candy ~= nil).toBe(true)
		expect(classic:FindFirstChild("Equipped").Visible).toBe(true)
		expect(classic:FindFirstChild("Equip").Visible).toBe(false)
		expect(mushroom:FindFirstChild("Equip").Text).toBe("Equip")
		expect(mushroom:FindFirstChild("Equip").Visible).toBe(true)
		expect(mushroom:FindFirstChild("Equipped").Visible).toBe(false)
		expect(candy:FindFirstChild("Equip").Visible).toBe(false) -- locked: no button, the unlock text and a bar
		expect(candy:FindFirstChild("Progress").Visible).toBe(true)
		expect(mushroom:FindFirstChild("Progress").Visible).toBe(false)
		local heading = list:FindFirstChild("skins:header")
		expect(UiHarness.find(heading, "Title").Text).toBe("Plot skins")
		expect(heading.LayoutOrder < classic.LayoutOrder).toBe(true)
		expect(classic.LayoutOrder < list:FindFirstChild("header:1").LayoutOrder).toBe(true)
		expect(candy:GetAttribute("Locked")).toBe(true)
		expect(mushroom:GetAttribute("SkinId")).toBe("mushroom")
	end)
	it("species cards carry no Equip button, and without plotSkins there are no cards at all", function()
		local panel = openDex(nil)
		local list = UiHarness.find(panel.frame, "List")
		expect(list:FindFirstChild("skin:classic")).toBeNil()
		expect(list:FindFirstChild("skins:header")).toBeNil()
		expect(UiHarness.find(UiHarness.find(list, "gummy"), "Equip")).toBeNil()
	end)
	it("Equip asks the server with EquipPlotSkin(skinId) and decides nothing itself", function()
		local src = fs.readFile("src/ui/Panels/Dex.luau")
		expect(string.find(src, 'ctx.request("EquipPlotSkin", function() end, id)', 1, true) ~= nil).toBe(true)
		expect(string.find(src, "data.plotSkin", 1, true)).toBeNil()
	end)
end)
