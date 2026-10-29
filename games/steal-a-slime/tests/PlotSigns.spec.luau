--!nocheck
-- Plot Signs: pure text from PlotSigns.lines and the mascot sign PlotSigns.ensure builds with @lune/roblox.
local roblox = require("@lune/roblox")

local Config = require("../src/shared/Config")
local Fixtures = require("./Fixtures")
local MascotSign = require("../src/shared/MascotSign")
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
	it(
		"carries the owner's plot theme for the mascot (classic until another skin is unlocked); none on a free plot",
		function()
			expect(PlotSigns.lines(1, owner("Ann", nil, 0, 0)).skin).toBe(Config.PLOT_SKIN_DEFAULT)
			expect(PlotSigns.lines(1, nil).skin).toBe(nil)
		end
	)
	it("shows the income the HUD shows when the server passes it (carried slimes left out)", function()
		local o = owner("Merijn", { Fixtures.slime("a", 3) }, 0, 0)
		expect(PlotSigns.lines(1, o, 0).stats).toBe("+$0/s, 0 rebirths, 0 steals")
		expect(PlotSigns.lines(1, o, 1250).stats).toBe("+$1.25K/s, 0 rebirths, 0 steals")
	end)
end)

describe("PlotSigns.apply", function()
	local function face(sign)
		return sign:FindFirstChild(PlotSigns.GUI_PREFIX .. "Front"):FindFirstChild(MascotSign.ROOT)
	end

	it("adds a SurfaceGui with the mascot sign on the front (the drawn face) of a bare Sign", function()
		expect(PlotSigns.FACES).toEqual({ "Front" })
		local sign = roblox.Instance.new("Part")
		sign.Name = "Sign"
		PlotSigns.apply(sign, PlotSigns.lines(2, nil), DEPS)
		local gui = sign:FindFirstChild(PlotSigns.GUI_PREFIX .. "Front")
		expect(gui.Face).toBe(roblox.Enum.NormalId.Front)
		expect(gui.MaxDistance).toBe(PlotSigns.MAX_DISTANCE)
		local root = face(sign)
		expect(root.Bar.Title.Text).toBe("Plot 2")
		expect(root.Bar.Stats.Text).toBe("Empty plot")
	end)

	it("puts a free plot's mascot to sleep and wakes it in the owner's theme colour", function()
		local sign = roblox.Instance.new("Part")
		PlotSigns.apply(sign, PlotSigns.lines(4, nil), DEPS)
		local root = face(sign)
		expect(root.Mascot.Eye1.Visible).toBe(false)
		expect(root.Mascot.Lid1.Visible).toBe(true)
		expect(root.Zz.Visible).toBe(true)
		expect(root.Paw1.BackgroundColor3).toBe(rgb(MascotSign.COLORS.asleep))
		local owned = PlotSigns.lines(4, owner("Ann", nil, 0, 0))
		PlotSigns.apply(sign, owned, DEPS)
		expect(root.Mascot.Eye1.Visible).toBe(true)
		expect(root.Mascot.Lid1.Visible).toBe(false)
		expect(root.Zz.Visible).toBe(false)
		expect(root.Paw1.BackgroundColor3).toBe(rgb(MascotSign.bodyColor(owned)))
		expect(MascotSign.bodyColor(owned)).toEqual(
			MascotSign.bodyColor({ title = "", stats = "", owned = true, skin = Config.PLOT_SKINS[1].id })
		)
	end)

	it("colours the mascot and the nameplate's goo for each theme, a different colour per theme", function()
		local sign = roblox.Instance.new("Part")
		local seen = {}
		for _, skin in Config.PLOT_SKINS do
			local lines = PlotSigns.lines(1, owner("Ann", nil, 0, 0))
			lines.skin = skin.id
			PlotSigns.apply(sign, lines, DEPS)
			local root = face(sign)
			local body = rgb(MascotSign.bodyColor(lines))
			expect(root.Paw1.BackgroundColor3).toBe(body)
			expect(root.Goo.BackgroundColor3).toBe(body)
			expect(root.Drip1.BackgroundColor3).toBe(body)
			local key = table.concat(MascotSign.bodyColor(lines), ",")
			expect(seen[key]).toBe(nil) -- no two themes share a colour
			seen[key] = true
		end
	end)

	it("keeps the goo drips at the ends of the nameplate, clear of the text", function()
		for _, d in MascotSign.GOO.drips do
			expect(d[1] < 0.2 or d[1] > 0.8).toBe(true)
		end
	end)

	it("keeps the mascot's eyes above the nameplate and the bar inside the face", function()
		local B = MascotSign.BOX
		local m = B.mascot
		expect(m[2] + m[4] * B.eyeY < B.bar[2]).toBe(true)
		expect(B.bar[2] + B.bar[4] <= 1).toBe(true)
		expect(m[2] >= 0).toBe(true)
	end)

	it("updates in place when the owner changes (no duplicate guis)", function()
		local sign = roblox.Instance.new("Part")
		PlotSigns.apply(sign, PlotSigns.lines(1, nil), DEPS)
		PlotSigns.apply(sign, PlotSigns.lines(1, owner("Ann", nil, 0, 0)), DEPS)
		expect(#sign:GetChildren()).toBe(#PlotSigns.FACES)
		expect(#sign:FindFirstChild(PlotSigns.GUI_PREFIX .. "Front"):GetChildren()).toBe(1)
		expect(face(sign).Bar.Title.Text).toBe("Ann's plot")
	end)
end)
