--!strict
-- The friend icon on locked bases that let friends in (src/ui/FriendsLockIcon.luau): when the sticker shows, which
-- part it goes on and its face. The guis in the real world are checked in a Studio playtest.
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local FriendsLockIcon = UiHarness.ui("FriendsLockIcon")

describe("FriendsLockIcon", function()
	it("shows the sticker only while friends are allowed and the base is locked", function()
		expect(FriendsLockIcon.shown(true, true)).toBe(true)
		expect(FriendsLockIcon.shown(true, false)).toBe(false)
		expect(FriendsLockIcon.shown(nil, true)).toBe(false)
		expect(FriendsLockIcon.shown(nil, nil)).toBe(false)
	end)

	it("puts the sticker on the shut door's mesh, or on the doorway collider before the mesh lands", function()
		local plot = UiHarness.Instance.new("Model")
		local barrier = UiHarness.Instance.new("Model")
		barrier.Name = "LockBarrier"
		barrier.Parent = plot
		local stopper = UiHarness.Instance.new("Part")
		stopper.Name = "Stopper"
		stopper.Parent = barrier
		local slot = UiHarness.Instance.new("Part")
		slot.Name = "StopperShut"
		slot.Parent = plot
		expect(FriendsLockIcon.doorOf(plot)).toBe(stopper)
		local mesh = UiHarness.Instance.new("Part")
		mesh.Name = "Mesh"
		mesh.Parent = slot
		expect(FriendsLockIcon.doorOf(plot)).toBe(mesh)
	end)

	it("puts the sticker on the face that looks out of the plot", function()
		local part = UiHarness.Instance.new("Part")
		part.CFrame = roblox.CFrame.Angles(0, math.rad(90), 0)
		-- Turned 90 degrees, the part's Right face (+X) points along world -Z.
		expect(FriendsLockIcon.faceToward(part, roblox.Vector3.new(0, 0, -1))).toBe(roblox.Enum.NormalId.Right)
		part.CFrame = roblox.CFrame.new()
		expect(FriendsLockIcon.faceToward(part, roblox.Vector3.new(0, 0, -1))).toBe(roblox.Enum.NormalId.Front)
	end)
end)
