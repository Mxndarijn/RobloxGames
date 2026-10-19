--!strict
-- DexJarView (src/ui/DexJarView.luau): the SlimeDex nav tile as a slime jar, built for real under UiHarness.
local Config = require("../../src/shared/Config")
local ItemIcons = require("../../src/ui/ItemIcons")
local Layout = require("../../src/ui/Layout")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local DexJarView = UiHarness.ui("DexJarView")
local ItemIconView = UiHarness.ui("ItemIconView")
local Widgets = UiHarness.ui("Widgets")

local registry = ItemIcons.build(Config)

-- UDim scales are 32-bit floats.
local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

-- The Dex nav tile as init.client builds it: rounded, with the item icon at Layout.NAV_TILE_Z.icon.
local function tile(): (any, any)
	local N = Layout.NAV
	local t = Widgets.create("Frame", {
		Name = "Tile",
		Size = roblox.UDim2.fromOffset(N.tile, N.tile),
		Parent = UiHarness.root(),
	}, { Widgets.corner(16) })
	local icon = ItemIconView.new({
		Name = "Icon",
		Id = "Dex_50",
		Size = N.tile - N.iconInset * 2,
		ZIndex = Layout.NAV_TILE_Z.icon,
		Parent = t,
	}, registry)
	return t, icon.instance
end

describe("DexJarView.level", function()
	it("is the puddle at 0%, the full tile at 100%, and in between", function()
		local puddle = DexJarView.JAR.puddle
		expect(DexJarView.level(0)).toBe(puddle)
		expect(DexJarView.level(1)).toBe(1)
		expect(DexJarView.level(0.5)).toBe(puddle + (1 - puddle) * 0.5)
		expect(DexJarView.level(-1)).toBe(puddle)
		expect(DexJarView.level(2)).toBe(1)
		expect(DexJarView.level(0 / 0)).toBe(puddle)
	end)
	it("hides the rim once it would cross the tile's rounded top corners", function()
		expect(DexJarView.rimShown(0.5, 66, 16)).toBe(true)
		expect(DexJarView.rimShown(1 - 16 / 66, 66, 16)).toBe(true)
		expect(DexJarView.rimShown(0.9, 66, 16)).toBe(false)
		expect(DexJarView.rimShown(1, 66, 16)).toBe(false)
	end)
end)

describe("DexJarView.progress", function()
	it("is the dex completion and the panel's percent", function()
		local p = DexJarView.progress({ dex = { found = 2, total = 50 } })
		expect(p and p.fraction).toBe(0.04)
		expect(p and p.text).toBe("4%")
		local full = DexJarView.progress({ dex = { found = 50, total = 50 } })
		expect(full and full.text).toBe("100%")
	end)
	it("is nil without a dex, and clamps odd counts", function()
		expect(DexJarView.progress({})).toBeNil()
		expect(DexJarView.progress({ dex = { found = 0, total = 0 } })).toBeNil()
		expect(DexJarView.progress(nil)).toBeNil()
		local over = DexJarView.progress({ dex = { found = 60, total = 50 } })
		expect(over and over.fraction).toBe(1)
	end)
end)

describe("DexJarView slosh maths", function()
	it("bounces only when the overshoot peak keeps the rim under the corners", function()
		local top = DexJarView.rimTop(66, 16) -- about 0.76
		expect(DexJarView.bounces(0.12, 0.5, 66, 16)).toBe(true)
		expect(DexJarView.bounces(0.12, top - 0.01, 66, 16)).toBe(false) -- overshoot would cross
		expect(DexJarView.bounces(0.12, 1, 66, 16)).toBe(false)
	end)
	it("times a Quad Out tween's progress", function()
		expect(DexJarView.quadTime(0)).toBe(0)
		expect(DexJarView.quadTime(1)).toBe(1)
		expect(near(DexJarView.quadTime(0.75), 0.5)).toBe(true) -- 1 - (1 - 0.5)^2 = 0.75
	end)
end)

describe("DexJarView.new", function()
	it("fills the tile up to the completion and writes the percent on the goo", function()
		local t = tile()
		local jar = DexJarView.new(t)
		jar.update({ fraction = 0, text = "0%" })
		local clip = UiHarness.find(t, "DexJar")
		local percent = UiHarness.find(t, "Percent")
		expect(clip.Visible).toBe(true)
		expect(near(clip.Size.Y.Scale, DexJarView.level(0))).toBe(true) -- first fill: no slosh
		expect(percent.Visible).toBe(true)
		expect(percent.Text).toBe("0%")
	end)
	it("draws the goo under the real nav icon and the percent over it", function()
		local t, icon = tile()
		DexJarView.new(t)
		expect(UiHarness.find(t, "DexJar").ZIndex < icon.ZIndex).toBe(true)
		expect(UiHarness.find(t, "Percent").ZIndex > icon.ZIndex).toBe(true)
	end)
	it("clips a tile-tall goo with the tile's corners, so the puddle follows the tile's bottom", function()
		local t = tile()
		local jar = DexJarView.new(t)
		local clip = UiHarness.find(t, "DexJar")
		local goo = UiHarness.find(t, "Goo")
		expect(clip.ClipsDescendants).toBe(true)
		expect(UiHarness.find(goo, "UICorner").CornerRadius.Offset).toBe(16)
		for _, fraction in { 0, 0.42, 1 } do
			jar.update({ fraction = fraction, text = "" })
			local level = DexJarView.level(fraction)
			expect(near(level * goo.Size.Y.Scale, 1)).toBe(true) -- goo height = clip / level = the tile
		end
	end)
	it("sloshes up when the percent rises, and a fall cancels a slosh still running", function()
		local t = tile()
		local jar = DexJarView.new(t)
		jar.update({ fraction = 0.1, text = "10%" })
		local played = UiHarness.stats.tweensPlayed
		local cancelled = UiHarness.stats.tweensCancelled
		jar.update({ fraction = 0.42, text = "42%" })
		expect(UiHarness.stats.tweensPlayed).toBe(played + 1)
		expect(jar.level()).toBe(DexJarView.level(0.42))
		jar.update({ fraction = 0.42, text = "42%" }) -- same level: no new tween
		expect(UiHarness.stats.tweensPlayed).toBe(played + 1)
		jar.update({ fraction = 0, text = "0%" })
		expect(UiHarness.stats.tweensCancelled).toBe(cancelled + 1)
		expect(UiHarness.stats.tweensPlayed).toBe(played + 1)
		expect(near(UiHarness.find(t, "DexJar").Size.Y.Scale, DexJarView.level(0))).toBe(true)
	end)
	it("keeps the rim on a rise into the top until the surface reaches the corners", function()
		UiHarness.virtualTime(true)
		local t = tile()
		local jar = DexJarView.new(t)
		local rim = UiHarness.find(t, "Rim")
		jar.update({ fraction = 0.42, text = "42%" })
		expect(rim.Visible).toBe(true)
		jar.update({ fraction = 1, text = "100%" })
		expect(rim.Visible).toBe(true) -- still climbing
		local from, top = DexJarView.level(0.42), DexJarView.rimTop(Layout.NAV.tile, 16)
		local hideAt = DexJarView.JAR.slosh * DexJarView.quadTime((top - from) / (1 - from))
		UiHarness.advance(hideAt - 0.01)
		expect(rim.Visible).toBe(true)
		UiHarness.advance(0.02)
		expect(rim.Visible).toBe(false)
		jar.update({ fraction = 0.42, text = "42%" }) -- a fall shows it at once
		expect(rim.Visible).toBe(true)
		UiHarness.virtualTime(false)
	end)
	it("a newer level cancels a pending rim timer", function()
		UiHarness.virtualTime(true)
		local t = tile()
		local jar = DexJarView.new(t)
		local rim = UiHarness.find(t, "Rim")
		jar.update({ fraction = 0.42, text = "42%" })
		jar.update({ fraction = 1, text = "100%" })
		jar.update({ fraction = 0.5, text = "50%" })
		UiHarness.advance(DexJarView.JAR.slosh)
		expect(rim.Visible).toBe(true)
		UiHarness.virtualTime(false)
	end)
	it("re-checks the rim when the layout shrinks the tile", function()
		local t = tile()
		local jar = DexJarView.new(t)
		local rim = UiHarness.find(t, "Rim")
		jar.update({ fraction = 0, text = "0%" })
		local level = (DexJarView.rimTop(Layout.NAV.tile, 16) + DexJarView.rimTop(Layout.NAV.ctile, 16)) / 2
		local fraction = (level - DexJarView.JAR.puddle) / (1 - DexJarView.JAR.puddle)
		jar.update({ fraction = fraction, text = "" }) -- ends under the big tile's corners: the rim stays
		expect(rim.Visible).toBe(true)
		t.Size = roblox.UDim2.fromOffset(Layout.NAV.ctile, Layout.NAV.ctile)
		jar.relayout()
		expect(rim.Visible).toBe(false)
	end)
	it("turns the goo darker on the selected tile, so it shows on the Accent green", function()
		local t = tile()
		local jar = DexJarView.new(t)
		local goo = UiHarness.find(t, "Goo")
		jar.setSelected(true)
		expect(goo.BackgroundColor3).toBe(Widgets.Theme.Ink)
		jar.setSelected(false)
		expect(goo.BackgroundColor3).toBe(Widgets.Theme.Good)
	end)
	it("hides the jar and the percent until State has a dex", function()
		local t = tile()
		local jar = DexJarView.new(t)
		jar.update(nil)
		expect(UiHarness.find(t, "DexJar").Visible).toBe(false)
		expect(UiHarness.find(t, "Percent").Visible).toBe(false)
	end)
end)
