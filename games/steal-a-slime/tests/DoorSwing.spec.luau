--!strict
-- The door look between shut and open (src/visuals/shared/DoorSwing.luau): it turns round its hinge, or slides when
-- the two poses don't turn (a shutter), and the easing settles past the end.
local StaticWorld = require("../scripts/StaticWorld")
local TestRunner = require("./TestRunner")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local DoorSwing = StaticWorld.visual("DoorSwing")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local EPS = 1e-4 -- CFrames are 32-bit floats

local function near(a: any, b: any)
	expect((a.Position - b.Position).Magnitude).toBeCloseTo(0, EPS)
	expect((a.LookVector - b.LookVector).Magnitude).toBeCloseTo(0, EPS)
end

describe("DoorSwing.pose", function()
	-- A door at (10, 5, 20), turned 30 degrees, hanging on a hinge 4 studs to its side.
	local shut = CFrame.new(10, 5, 20) * CFrame.Angles(0, math.rad(30), 0)
	local hinge = shut:PointToWorldSpace(Vector3.new(-4, 0, 0)) * Vector3.new(1, 0, 1)
	local function turned(degrees: number): any
		return CFrame.new(hinge) * CFrame.Angles(0, math.rad(degrees), 0) * CFrame.new(-hinge) * shut
	end
	local open = turned(130)

	it("starts shut and ends open", function()
		near(DoorSwing.pose(shut, open, 0), shut)
		near(DoorSwing.pose(shut, open, 1), open)
	end)

	it("turns round the hinge on the way, keeping its distance to it", function()
		local function hingeDistance(cf: any): number
			return ((cf.Position - hinge) * Vector3.new(1, 0, 1)).Magnitude
		end
		for _, f in { 0.25, 0.5, 0.75, 1.1 } do
			local pose = DoorSwing.pose(shut, open, f)
			expect(hingeDistance(pose)).toBeCloseTo(hingeDistance(shut), EPS)
			expect(pose.Position.Y).toBeCloseTo(shut.Position.Y, EPS)
		end
		near(DoorSwing.pose(shut, open, 0.5), turned(65))
	end)

	it("slides when the two poses don't turn (a shutter rolling up)", function()
		local up = CFrame.new(0, 6, 0) * shut
		near(DoorSwing.pose(shut, up, 0.5), CFrame.new(0, 3, 0) * shut)
		near(DoorSwing.pose(shut, up, 1), up)
	end)
end)

describe("DoorSwing.ease", function()
	local T = DoorSwing.TIMING
	it("goes 0 to 1, fast at the start", function()
		for _, c in { T.closeOvershoot, T.openOvershoot } do
			expect(DoorSwing.ease(0, c)).toBeCloseTo(0)
			expect(DoorSwing.ease(1, c)).toBeCloseTo(1)
			expect(DoorSwing.ease(-1, c)).toBeCloseTo(0)
			expect(DoorSwing.ease(2, c)).toBeCloseTo(1)
			expect(DoorSwing.ease(0.3, c) > 0.3).toBe(true)
		end
	end)

	it("settles a few degrees past shut, and never swings past open", function()
		local most, mostOpen = 0, 0
		for i = 0, 100 do
			most = math.max(most, DoorSwing.ease(i / 100, T.closeOvershoot))
			mostOpen = math.max(mostOpen, DoorSwing.ease(i / 100, T.openOvershoot))
		end
		expect(most > 1 and most < 1.04).toBe(true)
		expect(mostOpen).toBeCloseTo(1)
	end)
end)
