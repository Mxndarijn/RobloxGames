--!strict
-- The join loading screen wears the Goo palette (its own copy, since it runs before Shared arrives) and draws the
-- canvas's goo screen: drips from the top that stop above the title, a goo tube bar, a Skip that waits its turn.
local roblox = require("@lune/roblox") :: any

local GooPalette = require("../../src/shared/GooPalette")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local Look = UiHarness.ui("../first/LoadingLook")
local LoadingScreen = UiHarness.ui("../first/LoadingScreen")

local function rgb(c: { number }): any
	return roblox.Color3.fromRGB(c[1], c[2], c[3])
end

describe("loading screen look", function()
	it("matches the Goo palette (Shared.GooPalette) and the HUD fonts (Widgets.Theme)", function()
		local pairs = {
			bg = "Bg",
			bgBottom = "BgDeep",
			ink = "Ink",
			band = "Mint",
			bandHi = "MintHi",
			bandLo = "MintLo",
			text = "Text",
			muted = "Muted",
			glass = "Glass",
			slime = "Gold",
			slimeHi = "GoldHi",
			slimeLo = "GoldDeep",
			white = "White",
		}
		for key, paletteKey in pairs do
			expect(Look[key]).toBe(rgb((GooPalette :: any)[paletteKey]))
		end
		local Theme = UiHarness.ui("Widgets").Theme
		expect(Look.font == Theme.Font).toBe(true)
		expect(Look.fontBody == Theme.FontBody).toBe(true)
	end)
end)

describe("loading screen", function()
	it("keeps every drip above the title, from a short phone screen to a tall monitor", function()
		for _, height in { 300, 360, 414, 600, 720, 1080, 1440 } do
			local goo = LoadingScreen.gooHeight(height)
			expect(goo > 0).toBe(true)
			expect(goo * LoadingScreen.dripBottom() < LoadingScreen.titleTop(height)).toBe(true)
		end
		expect(LoadingScreen.dripBottom() <= 1).toBe(true) -- the drips stay inside the goo layer
	end)

	it("keeps the hopping slime clear of the title and the tip line clear of the bar", function()
		expect(LoadingScreen.riderTop() > LoadingScreen.titleBottom()).toBe(true)
		expect(Look.statusY - (Look.labelSize + 8) / 2 > Look.barY + Look.barSize.Y.Offset / 2).toBe(true)
		for _, t in { 0, 0.1, 0.275, 0.4 } do
			local lift = LoadingScreen.hopAt(t)
			expect(lift >= 0 and lift <= Look.riderHop).toBe(true)
		end
	end)

	it("moves the goo, drops, shine and slime, and rests them all under Reduced Motion", function()
		local screen = LoadingScreen.build()
		screen.layout(720)
		local bg = screen.gui:FindFirstChild("Background")
		local drip = bg:FindFirstChild("Goo"):FindFirstChild("Drip2")
		local shine = bg:FindFirstChild("Bar"):FindFirstChild("Fill"):FindFirstChild("Shine")
		local slime = bg:FindFirstChild("Bar"):FindFirstChild("Rider"):FindFirstChild("Slime")
		local drop = bg:FindFirstChild("Drop1")
		local d = Look.drops[1]
		local falling = d.every * (1 - Look.dropFall / 2) - d.delay -- halfway through its fall

		screen.animate(falling, true)
		expect(drop.Visible).toBe(true)
		expect(shine.Visible).toBe(true)
		screen.animate(Look.swayPeriods[2] / 4, true)
		expect(drip.Size.Y.Scale > Look.drips[2].hang + Look.drips[2].w).toBe(true)
		screen.animate(Look.riderPeriod / 2, true)
		expect(slime.Position.Y.Offset < 0).toBe(true)

		screen.animate(falling, false)
		expect(drop.Visible).toBe(false)
		expect(shine.Visible).toBe(false)
		expect(math.abs(drip.Size.Y.Scale - (Look.drips[2].hang + Look.drips[2].w)) < 1e-6).toBe(true)
		expect(slime.Position.Y.Offset).toBe(0)
	end)

	it("draws the goo, the outlined title, the tube bar and a hidden Skip", function()
		local screen = LoadingScreen.build()
		local bg = screen.gui:FindFirstChild("Background")
		local goo = bg:FindFirstChild("Goo")
		expect(goo:FindFirstChild("Band").BackgroundColor3).toBe(Look.band)
		expect(goo:FindFirstChild(`Drip{#Look.drips}`) ~= nil).toBe(true)
		local title = bg:FindFirstChild("Title")
		expect(title.Text).toBe("Steal a Slime")
		expect(title.TextColor3).toBe(Look.band)
		expect(title:FindFirstChildOfClass("UIStroke").Color).toBe(Look.ink)
		expect(bg:FindFirstChild("Bar").BackgroundColor3).toBe(Look.ink)
		expect(screen.skip.Visible).toBe(false)
		screen.setSkip(true)
		expect(screen.skip.Visible).toBe(true)
		screen.layout(720)
		expect(goo.Size.Y.Offset).toBe(LoadingScreen.gooHeight(720))
	end)

	it("fills the bar from 0 to 1 and hides an empty fill", function()
		local screen = LoadingScreen.build()
		local fill = screen.gui:FindFirstChild("Background"):FindFirstChild("Bar"):FindFirstChild("Fill")
		screen.setProgress(0)
		expect(fill.Visible).toBe(false)
		screen.setProgress(0.35)
		expect(fill.Visible).toBe(true)
		expect(math.abs(fill.Size.X.Scale - 0.35) < 1e-6).toBe(true)
		local rider = screen.gui:FindFirstChild("Background"):FindFirstChild("Bar"):FindFirstChild("Rider")
		expect(math.abs(rider.Position.X.Scale - 0.35) < 1e-6).toBe(true) -- the slime rides the fill's tip
		screen.setProgress(4)
		expect(fill.Size.X.Scale).toBe(1)
		screen.setStatus("Building the world...")
		expect(screen.gui:FindFirstChild("Background"):FindFirstChild("Status").Text).toBe("Building the world...")
	end)

	it("fades outlines out with the rest, so no ring is left behind", function()
		local screen = LoadingScreen.build()
		local faded: { [any]: { [string]: number } } = {}
		local tweens = {
			Create = function(_self: any, target: any, _info: any, goal: { [string]: number })
				faded[target] = goal
				return { Play = function() end }
			end,
		}
		local ok = pcall(screen.fade, tweens :: any)
		expect(ok).toBe(true)
		for _, d in screen.gui:GetDescendants() do
			if d:IsA("UIStroke") then
				expect(faded[d] and faded[d].Transparency).toBe(1)
			elseif d:IsA("Frame") or d:IsA("TextLabel") or d:IsA("TextButton") then
				expect(faded[d] and faded[d].BackgroundTransparency).toBe(1)
			end
		end
	end)
end)
