--!nocheck
-- Plot Signs: pure text from PlotSigns.lines and the Goo board PlotSigns.ensure builds with @lune/roblox.
local roblox = require("@lune/roblox")

local Fixtures = require("./Fixtures")
local GooBoard = require("../src/shared/GooBoard")
local GooPalette = require("../src/shared/GooPalette")
local NumberFormat = require("../src/shared/NumberFormat")
local PlayerData = require("../src/shared/PlayerData")
local PlotSigns = require("../src/server/PlotSigns")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local DEPS = {
	Instance = roblox.Instance,
	Enum = roblox.Enum,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Color3 = roblox.Color3,
}

local function owner(name, slimes, rebirths, stolen)
	local data = Fixtures.data(slimes or {})
	data.rebirths = rebirths
	data.totalStolen = stolen
	return { name = name, data = data }
end

local function rgb(c)
	return roblox.Color3.fromRGB(c[1], c[2], c[3])
end

local function texts(sign)
	local out = {}
	for _, d in sign:GetDescendants() do
		if d:IsA("TextLabel") then
			table.insert(out, d.Text)
		end
	end
	return out
end

describe("PlotSigns.lines", function()
	it("shows a placeholder on free plots, never blank", function()
		local lines = PlotSigns.lines(3, nil)
		expect(lines.title).toBe("Plot 3")
		expect(lines.stats).toBe("Empty plot")
	end)
	it("shows the owner's name, plot income, rebirths and steals in sentence case", function()
		local o = owner("Merijn", { Fixtures.slime("a", 3), Fixtures.slime("b", 5) }, 2, 1)
		local lines = PlotSigns.lines(1, o)
		expect(lines.title).toBe("Merijn's plot")
		expect(lines.owned).toBe(true)
		local income = "+" .. NumberFormat.rate(PlayerData.incomePerSecond(o.data))
		expect(PlayerData.incomePerSecond(o.data) > 0).toBe(true)
		expect(lines.stats).toBe(`{income}, 2 rebirths, 1 steal`)
		expect(PlotSigns.lines(1, owner("Ann", nil, 1, 0)).stats).toBe("+$0/s, 1 rebirth, 0 steals")
	end)
	it("shows the income the HUD shows when the server passes it (carried slimes left out)", function()
		local o = owner("Merijn", { Fixtures.slime("a", 3) }, 0, 0)
		expect(PlotSigns.lines(1, o, 0).stats).toBe("+$0/s, 0 rebirths, 0 steals")
		expect(PlotSigns.lines(1, o, 1250).stats).toBe("+$1.25K/s, 0 rebirths, 0 steals")
	end)
end)

describe("PlotSigns.apply", function()
	it("adds a SurfaceGui with Title / Stats on the front (the board face) of a bare Sign", function()
		expect(PlotSigns.FACES).toEqual({ "Front" })
		local sign = roblox.Instance.new("Part")
		sign.Name = "Sign"
		PlotSigns.apply(sign, PlotSigns.lines(2, nil), DEPS)
		for _, face in PlotSigns.FACES do
			local gui = sign:FindFirstChild(PlotSigns.GUI_PREFIX .. face)
			expect(gui ~= nil).toBe(true)
			expect(gui.Face).toBe(roblox.Enum.NormalId[face])
			expect(gui.GooCard.Title.Text).toBe("Plot 2")
			expect(gui.GooCard.Stats.Text).toBe("Empty plot")
		end
	end)
	it("draws a mint band with the name in Ink on an owned plot, plain glass on a free one", function()
		local sign = roblox.Instance.new("Part")
		PlotSigns.apply(sign, PlotSigns.lines(4, nil), DEPS)
		local gui = sign[PlotSigns.GUI_PREFIX .. "Front"]
		local card = gui:FindFirstChild(GooBoard.CARD)
		expect(card.Band.Visible).toBe(false)
		expect(card.Title.TextColor3).toBe(rgb(GooPalette.Text))
		expect(card.Stats.TextColor3).toBe(rgb(GooPalette.MutedWell))
		PlotSigns.apply(sign, PlotSigns.lines(4, owner("Ann", nil, 0, 0)), DEPS)
		expect(card.Band.Visible).toBe(true)
		expect(card.Band.BackgroundColor3).toBe(rgb(GooPalette.Mint))
		for _, piece in card.Band:GetDescendants() do
			if piece:IsA("Frame") and piece.Name ~= "Goo" then
				expect(piece.BackgroundColor3).toBe(rgb(GooPalette.Mint))
			end
		end
		expect(card.Title.TextColor3).toBe(rgb(GooPalette.Ink))
		expect(card.Stats.TextColor3).toBe(rgb(GooPalette.Text))
		-- the name sits inside the band
		local t = card.Title
		expect(t.Position.Y.Scale + t.Size.Y.Scale <= PlotSigns.BOARD.band).toBe(true)
	end)
	it("keeps every drip clear of the stats line", function()
		local stats = PlotSigns.TEXT.stats
		for _, d in PlotSigns.BOARD.drips do
			local x, y, w, h = GooBoard.dripBox(PlotSigns.BOARD, d, PlotSigns.ASPECT)
			local besideText = x + w <= stats[1] or x >= stats[1] + stats[3]
			expect(besideText or y + h <= stats[2]).toBe(true)
		end
		expect(GooBoard.gooBottom(PlotSigns.BOARD, PlotSigns.ASPECT) < 1).toBe(true)
	end)
	it("updates in place when the owner changes (no duplicate guis)", function()
		local sign = roblox.Instance.new("Part")
		PlotSigns.apply(sign, PlotSigns.lines(1, nil), DEPS)
		PlotSigns.apply(sign, PlotSigns.lines(1, owner("Ann", nil, 0, 0)), DEPS)
		expect(#sign:GetChildren()).toBe(#PlotSigns.FACES)
		local all = texts(sign)
		expect(#all).toBe(2 * #PlotSigns.FACES)
		for _, text in all do
			expect(text ~= "" and text ~= "Plot 1" and text ~= "Empty plot").toBe(true)
		end
		expect(sign[PlotSigns.GUI_PREFIX .. "Front"].GooCard.Title.Text).toBe("Ann's plot")
	end)
end)
