--!strict
-- SlimeDex rows (src/ui/SlimeDex.luau) and the real SlimeDex panel and menu
-- chrome built under tests/ui/UiHarness.luau: a picture per discovered
-- slime, a silhouette per tier for the rest, rows stacked by
-- Layout.stackRows, and the close X on every menu.
local roblox = require("@lune/roblox") :: any

local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Genome = require("../../src/shared/Genome")
local Layout = require("../../src/ui/Layout")
local Remotes = require("../../src/shared/Remotes")
local SlimeDex = require("../../src/ui/SlimeDex")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local UDim2 = roblox.UDim2

local TOTAL = Config.MAX_TIER * (#Config.MUTATIONS + 1) * #Config.PATTERNS * #Config.EYES
local PER_TIER = TOTAL // Config.MAX_TIER
local DEX = { "2:None:Plain:Round", "1:Glow:Spots:Happy", "1:None:Plain:Round" }

local function ctx(): any
	return {
		Config = Config,
		Constants = Constants,
		Genome = Genome,
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

describe("SlimeDex.rows", function()
	it("lists discovered slimes by tier, each followed by that tier's silhouette row", function()
		local rows = SlimeDex.rows(DEX, TOTAL, Config)
		local keys = {}
		for _, row in rows do
			table.insert(keys, row.key)
		end
		expect(table.concat(keys, ",", 1, 5)).toBe(
			"1:Glow:Spots:Happy,1:None:Plain:Round,locked:1,2:None:Plain:Round,locked:2"
		)
		expect(#rows).toBe(#DEX + Config.MAX_TIER) -- every tier still has undiscovered slimes
	end)
	it("gives discovered rows a name and a colour, locked rows a silhouette with no names", function()
		local rows = SlimeDex.rows(DEX, TOTAL, Config)
		local glow, plain, locked = rows[1], rows[2], rows[3]
		expect(glow.locked).toBe(false)
		expect(glow.title).toBe(`{Config.RARITIES[1].name} · Glow · Spots · Happy`)
		expect(glow.color).toBe(SlimeDex.MUTATION_COLORS.Glow)
		expect(plain.color).toBe(Config.RARITIES[1].color)
		expect(locked.locked).toBe(true)
		expect(locked.color).toBe(SlimeDex.SILHOUETTE)
		expect(locked.image).toBeNil()
		expect(locked.detail).toBe(`{PER_TIER - 2} more to discover`)
		for _, part in { "Glow", "Spots", "Plain", "Round", "Happy" } do
			expect(string.find(locked.title, part, 1, true)).toBeNil()
		end
	end)
	it("uses an uploaded picture by dexKey, then by tier + mutation, else none", function()
		local images = { ["1:Glow:Spots:Happy"] = "rbxassetid://1", ["2:None"] = "rbxassetid://2" }
		local rows = SlimeDex.rows(DEX, TOTAL, Config, images)
		expect(rows[1].image).toBe("rbxassetid://1")
		expect(rows[2].image).toBeNil()
		expect(rows[4].image).toBe("rbxassetid://2")
	end)
	it("drops a tier's silhouette once it is complete, and survives bad State", function()
		local all = {}
		for _, mutation in { "None", "Glow", "Lava", "Galaxy", "Rainbow", "Gold", "Crystal", "Eclipse" } do
			for _, pattern in Config.PATTERNS do
				for _, eyes in Config.EYES do
					table.insert(all, `1:{mutation}:{pattern}:{eyes}`)
				end
			end
		end
		expect(#all).toBe(PER_TIER)
		for _, row in SlimeDex.rows(all, TOTAL, Config) do
			expect(row.key ~= "locked:1").toBe(true)
		end
		expect(#SlimeDex.rows(nil, nil, Config)).toBe(0)
		expect(#SlimeDex.rows({ "garbage" }, TOTAL, Config)).toBe(Config.MAX_TIER)
	end)
end)

-- The SlimeDex panel built for real, sized like a full-window menu
-- (init.client applyLayout: frame size, then panel.layout).
local function openDex(w: number, h: number, dex: { string }, extra: { [string]: any }?): (any, Layout.Rect)
	local panel = UiHarness.ui("Panels/Dex").new(UiHarness.root(), ctx())
	panel.frame.Visible = false
	local raw = Layout.panelFor(Layout.screen(w, h), "Dex")
	local r = Layout.rect(math.floor(raw.x), math.floor(raw.y), math.floor(raw.w), math.floor(raw.h))
	panel.frame.Size = UDim2.fromOffset(r.w, r.h)
	panel.layout(r)
	local state: { [string]: any } = { dex = dex, dexTotal = TOTAL }
	for k, v in extra or {} do
		state[k] = v
	end
	panel.update(state)
	panel.setOpen(true) -- rows are only built while open
	panel.frame.Visible = true
	return panel, r
end

describe("SlimeDex panel", function()
	it("is titled SlimeDex", function()
		local panel = openDex(390, 844, DEX)
		expect(UiHarness.find(panel.frame, "Title").Text).toBe("SlimeDex")
	end)
	it("shows a coloured picture for discovered rows and a ? silhouette for locked ones", function()
		local panel = openDex(1920, 1080, DEX)
		local list = UiHarness.find(panel.frame, "List")
		local found = list:FindFirstChild("1:Glow:Spots:Happy")
		local locked = list:FindFirstChild("locked:1")
		expect(found ~= nil and locked ~= nil).toBe(true)
		expect(found:GetAttribute("Locked")).toBe(false)
		expect(locked:GetAttribute("Locked")).toBe(true)
		local image = found:FindFirstChild("Image")
		expect(image.Size.X.Offset).toBe(image.Size.Y.Offset) -- square
		expect(image.Size.Y.Offset <= found.Size.Y.Offset).toBe(true)
		local glow = SlimeDex.MUTATION_COLORS.Glow
		expect(image.BackgroundColor3).toBe(roblox.Color3.fromRGB(glow[1], glow[2], glow[3]))
		expect(image:FindFirstChild("Glyph").Visible).toBe(false)
		local silhouette = locked:FindFirstChild("Image")
		local s = SlimeDex.SILHOUETTE
		expect(silhouette.BackgroundColor3).toBe(roblox.Color3.fromRGB(s[1], s[2], s[3]))
		expect(silhouette:FindFirstChild("Glyph").Visible).toBe(true)
		expect(silhouette:FindFirstChild("Picture").Visible).toBe(false)
	end)
	it("stacks rows by Layout.stackRows and grows the canvas so the list scrolls", function()
		local many = {}
		for _, pattern in Config.PATTERNS do
			for _, eyes in Config.EYES do
				table.insert(many, `2:None:{pattern}:{eyes}`)
			end
		end
		local panel = openDex(390, 844, many)
		local list = UiHarness.find(panel.frame, "List")
		local rows = {}
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				table.insert(rows, child)
			end
		end
		table.sort(rows, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		local heights = {}
		for i, row in rows do
			heights[i] = row.Size.Y.Offset
		end
		local ys, canvas = Layout.stackRows(heights, list:GetAttribute("ListGap"))
		for i, row in rows do
			expect(row.Position.Y.Offset).toBe(ys[i])
			if i > 1 then
				expect(row.Position.Y.Offset >= rows[i - 1].Position.Y.Offset + rows[i - 1].Size.Y.Offset).toBe(true)
			end
		end
		expect(list.CanvasSize.Y.Offset).toBe(canvas)
		expect(#rows).toBe(#many + Config.MAX_TIER)
		local body = Layout.panelBody(Layout.panelFor(Layout.screen(390, 844), "Dex"))
		expect(canvas > body.h).toBe(true) -- taller than the panel: it scrolls
	end)
end)

describe("SlimeDex.header (short panel bodies)", function()
	it("keeps the full header (tiers at 108, list at 112 / 148 with rewards) on a tall body", function()
		local h = SlimeDex.header(700, true)
		expect(h.tiers and h.bar and h.rewards).toBe(true)
		expect(h.rewardsY).toBe(108)
		expect(h.listTop).toBe(148)
		expect(SlimeDex.header(700, false).listTop).toBe(112)
	end)
	it("drops the tier grid, then rewards, then the bar until a list row fits", function()
		expect(SlimeDex.MIN_LIST).toBe(84) -- one 72 px row (v28) + scroll padding
		local noTiers = SlimeDex.header(200, true) -- 200 - 148 < MIN_LIST <= 200 - 104
		expect(noTiers.tiers).toBe(false)
		expect(noTiers.rewards).toBe(true)
		expect(noTiers.listTop).toBe(64 + 4 + 36)
		local noRewards = SlimeDex.header(160, true) -- 160 - 104 < MIN_LIST <= 160 - 68
		expect(noRewards.rewards).toBe(false)
		expect(noRewards.bar).toBe(true)
		local minimal = SlimeDex.header(131, true) -- the 844x332 body
		expect(minimal.bar).toBe(false)
		expect(131 - minimal.listTop >= SlimeDex.MIN_LIST).toBe(true)
	end)
	for _, vp in { { 390, 844 }, { 844, 390 }, { 844, 332 }, { 1024, 768 }, { 1366, 768 }, { 1920, 1080 } } do
		it(`{vp[1]}x{vp[2]}: the real panel's list is at least one row tall`, function()
			local panel, r = openDex(vp[1], vp[2], DEX, {
				dexRewards = { { count = 10, reward = 1000, bonus = 0.02, claimed = false } },
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
