--!nocheck
-- Plot Signs: pure text from PlotSigns.lines and the ranch plank PlotSigns.ensure builds with @lune/roblox.
local roblox = require("@lune/roblox")

local Fixtures = require("./Fixtures")
local NumberFormat = require("../src/shared/NumberFormat")
local PlayerData = require("../src/shared/PlayerData")
local PlotSigns = require("../src/server/PlotSigns")
local RanchSign = require("../src/shared/RanchSign")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local DEPS = {
	Instance = roblox.Instance,
	Enum = roblox.Enum,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
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
	it("adds a SurfaceGui with the plank's Title / Stats on the front (the board face) of a bare Sign", function()
		expect(PlotSigns.FACES).toEqual({ "Front" })
		local sign = roblox.Instance.new("Part")
		sign.Name = "Sign"
		PlotSigns.apply(sign, PlotSigns.lines(2, nil), DEPS)
		for _, face in PlotSigns.FACES do
			local gui = sign:FindFirstChild(PlotSigns.GUI_PREFIX .. face)
			expect(gui ~= nil).toBe(true)
			expect(gui.Face).toBe(roblox.Enum.NormalId[face])
			local plank = gui:FindFirstChild(RanchSign.PLANK)
			expect(plank.Title.Text).toBe("Plot 2")
			expect(plank.Stats.Text).toBe("Empty plot")
			expect(plank.Title.Font).toBe(roblox.Enum.Font.LuckiestGuy)
		end
	end)
	it("carves an owned plot's name in bright cream and a free plot's quieter", function()
		local sign = roblox.Instance.new("Part")
		PlotSigns.apply(sign, PlotSigns.lines(4, nil), DEPS)
		local plank = sign[PlotSigns.GUI_PREFIX .. "Front"]:FindFirstChild(RanchSign.PLANK)
		expect(plank.Title.TextColor3).toBe(rgb(RanchSign.COLORS.freeName))
		PlotSigns.apply(sign, PlotSigns.lines(4, owner("Ann", nil, 0, 0)), DEPS)
		expect(plank.Title.TextColor3).toBe(rgb(RanchSign.COLORS.name))
		-- the name sits above the stats line, both inside the plank
		local t, st = plank.Title, plank.Stats
		expect(t.Position.Y.Scale + t.Size.Y.Scale <= st.Position.Y.Scale).toBe(true)
		expect(st.Position.Y.Scale + st.Size.Y.Scale <= 1).toBe(true)
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
		expect(sign[PlotSigns.GUI_PREFIX .. "Front"]:FindFirstChild(RanchSign.PLANK).Title.Text).toBe("Ann's plot")
	end)
end)

describe("RanchSign.plate", function()
	it("is red with the padlock shut while locked, green with it lifted while open", function()
		local gui = roblox.Instance.new("SurfaceGui")
		local plate = RanchSign.plate(gui, DEPS, 6 / 2.6)
		RanchSign.paintPlate(plate, DEPS, true, "1:37", "Locked")
		expect(plate.plate.BackgroundColor3).toBe(rgb(RanchSign.COLORS.locked))
		expect(plate.big.Text).toBe("1:37")
		expect(plate.small.Text).toBe("Locked")
		local shut = plate.shackle.Position
		RanchSign.paintPlate(plate, DEPS, false, "Open", "stealable!")
		expect(plate.plate.BackgroundColor3).toBe(rgb(RanchSign.COLORS.open))
		expect(plate.big.Text).toBe("Open")
		expect(plate.shackle.Position.Y.Scale < shut.Y.Scale).toBe(true)
		-- built once: a second call finds the same plate
		expect(RanchSign.plate(gui, DEPS, 6 / 2.6).plate).toBe(plate.plate)
		expect(#gui:GetChildren()).toBe(1)
	end)
	it("hangs the plate under its chains, inside the face", function()
		local B = RanchSign.PLATE_BOX
		expect(B.plate[2] > 0 and B.plate[2] + B.plate[4] <= 1).toBe(true)
		for _, x in B.chains do
			expect(x > B.plate[1] and x < B.plate[1] + B.plate[3]).toBe(true)
		end
	end)
end)
