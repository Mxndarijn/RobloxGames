--!nocheck
-- The Steal prompt never shows to a player outside that base or on another floor of it (src/ui/StealReach.luau),
-- driven through minimal mock instances. Positions are plot-local already: localPoint passes them through.
local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local StealReach = require("../../src/ui/StealReach")
local TestRunner = require("../TestRunner")
local WorldLayout = require("../../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local ME = 111
local OTHER = 222
local REACH = Config.STEAL_REACH - 2
local JAR = {
	radii = WorldLayout.JAR_RADII,
	floorTop = WorldLayout.PLOT_FLOOR_TOP,
	floorHeight = WorldLayout.FLOOR_HEIGHT,
	wall = WorldLayout.JAR_WALL,
}

local function node(name: string, class: string?, attrs: { [string]: any }?): any
	local self = { Name = name, children = {}, attrs = attrs or {} }
	function self.IsA(_, cls)
		return cls == (class or "Folder")
	end
	function self.GetAttribute(_, key)
		return self.attrs[key]
	end
	function self.GetChildren()
		return self.children
	end
	function self.FindFirstChild(_, n)
		for _, c in self.children do
			if c.Name == n then
				return c
			end
		end
		return nil
	end
	return self
end

local function add(parent: any, child: any): any
	table.insert(parent.children, child)
	return child
end

-- A plot owned by `owner` with one pad slime at plot-local `at`; returns the plots folder and that slime's prompt.
local function world(owner: number, at: { number }): (any, any)
	local plots = node("Plots")
	local plot = add(plots, node("Plot_1", "Model", { OwnerUserId = owner, PadsUnlocked = 8 }))
	local slimes = add(plot, node(Constants.PLOT_SLIMES_FOLDER))
	local model = add(slimes, node("gem", "Model"))
	local body = add(model, node("Body", "BasePart"))
	body.Position = at
	model.PrimaryPart = body
	local prompt = add(body, node(Constants.GRAB_PROMPT_NAME, "ProximityPrompt"))
	prompt.MaxActivationDistance = REACH
	prompt.Enabled = true
	return plots, prompt
end

local function start(plots: any, me: { Position: { number } }?)
	return StealReach.start({
		plots = function()
			return plots
		end,
		localUserId = ME,
		root = function()
			return me
		end,
		jarOf = function()
			return JAR
		end,
		localPoint = function(_, at)
			return at
		end,
		slimesFolder = Constants.PLOT_SLIMES_FOLDER,
		promptName = Constants.GRAB_PROMPT_NAME,
		padsAttribute = Constants.PLOT_PADS_UNLOCKED_ATTRIBUTE,
	})
end

local x, z = WorldLayout.padOffset(1)
local PAD = { x, WorldLayout.floorTop(1) + 1.5, z }
local r = WorldLayout.jarRadius(1) + WorldLayout.JAR_WALL + 1
local len = math.sqrt(x * x + z * z)
local OUTSIDE = { x * r / len, WorldLayout.floorTop(1) + 3, z * r / len }
local INSIDE = { x * 0.85, WorldLayout.floorTop(1) + 3, z * 0.85 }

describe("StealReach", function()
	it("hides another player's Steal prompt from a player outside the glass", function()
		local plots, prompt = world(OTHER, PAD)
		local me = { Position = OUTSIDE }
		local handle = start(plots, me)
		handle.tick()
		expect(prompt.MaxActivationDistance).toBe(0)
		expect(prompt.Enabled).toBe(true) -- Enabled stays the server's
	end)
	it("gives it back the server's range once the player walks in", function()
		local plots, prompt = world(OTHER, PAD)
		local me = { Position = OUTSIDE }
		local handle = start(plots, me)
		handle.tick()
		me.Position = INSIDE
		handle.tick()
		expect(prompt.MaxActivationDistance).toBe(REACH)
	end)
	it("hides it from a player inside but on another floor", function()
		local plots, prompt = world(OTHER, PAD)
		local handle = start(plots, { Position = { INSIDE[1], WorldLayout.floorTop(2) + 3, INSIDE[3] } })
		handle.tick()
		expect(prompt.MaxActivationDistance).toBe(0)
	end)
	it("hides it while there is no character", function()
		local plots, prompt = world(OTHER, PAD)
		start(plots, nil).tick()
		expect(prompt.MaxActivationDistance).toBe(0)
	end)
	it("leaves the player's own plot alone", function()
		local plots, prompt = world(ME, PAD)
		start(plots, { Position = OUTSIDE }).tick()
		expect(prompt.MaxActivationDistance).toBe(REACH)
	end)
	it("puts every range back on destroy", function()
		local plots, prompt = world(OTHER, PAD)
		local handle = start(plots, { Position = OUTSIDE })
		handle.tick()
		handle.destroy()
		expect(prompt.MaxActivationDistance).toBe(REACH)
	end)
end)
