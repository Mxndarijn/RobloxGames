--!strict
-- DexJarView (src/ui/DexJarView.luau): the SlimeDex nav tile as a slime jar, built for real under UiHarness.
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local DexJarView = UiHarness.ui("DexJarView")
local Widgets = UiHarness.ui("Widgets")

-- UDim scales are 32-bit floats.
local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

-- A nav tile like init.client's: rounded, with the item icon at the default ZIndex.
local function tile(): any
	local root = UiHarness.root()
	local t = Widgets.create("Frame", { Name = "Tile", Parent = root }, { Widgets.corner(16) })
	Widgets.create("ImageLabel", { Name = "Icon", Parent = t })
	return t
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
end)

describe("DexJarView.new", function()
	it("fills the tile up to the completion and writes the percent on the goo", function()
		local t = tile()
		local jar = DexJarView.new(t)
		jar.update({ fraction = 0, text = "0%" })
		local goo = UiHarness.find(t, "Goo")
		local percent = UiHarness.find(t, "Percent")
		expect(UiHarness.find(t, "DexJar").Visible).toBe(true)
		expect(near(goo.Size.Y.Scale, DexJarView.level(0))).toBe(true) -- first fill: no slosh
		expect(percent.Visible).toBe(true)
		expect(percent.Text).toBe("0%")
	end)
	it("draws the goo under the icon and the percent over it", function()
		local t = tile()
		DexJarView.new(t)
		local icon = UiHarness.find(t, "Icon")
		expect(UiHarness.find(t, "DexJar").ZIndex < icon.ZIndex).toBe(true)
		expect(UiHarness.find(t, "Percent").ZIndex > icon.ZIndex).toBe(true)
	end)
	it("keeps the goo inside the tile's rounded corners", function()
		local t = tile()
		DexJarView.new(t)
		local corner = UiHarness.find(UiHarness.find(t, "DexJar"), "UICorner")
		expect(corner.CornerRadius.Offset).toBe(16)
	end)
	it("sloshes up when the percent rises, and drops at once when it falls", function()
		local t = tile()
		local jar = DexJarView.new(t)
		jar.update({ fraction = 0.1, text = "10%" })
		local played = UiHarness.stats.tweensPlayed
		jar.update({ fraction = 0.42, text = "42%" })
		expect(UiHarness.stats.tweensPlayed).toBe(played + 1)
		expect(jar.level()).toBe(DexJarView.level(0.42))
		jar.update({ fraction = 0.42, text = "42%" }) -- same level: no new tween
		expect(UiHarness.stats.tweensPlayed).toBe(played + 1)
		jar.update({ fraction = 0, text = "0%" })
		expect(UiHarness.stats.tweensPlayed).toBe(played + 1)
		expect(near(UiHarness.find(t, "Goo").Size.Y.Scale, DexJarView.level(0))).toBe(true)
	end)
	it("hides the jar and the percent until State has a dex", function()
		local t = tile()
		local jar = DexJarView.new(t)
		jar.update(nil)
		expect(UiHarness.find(t, "DexJar").Visible).toBe(false)
		expect(UiHarness.find(t, "Percent").Visible).toBe(false)
	end)
end)
