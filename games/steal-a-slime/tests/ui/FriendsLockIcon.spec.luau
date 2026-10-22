--!strict
-- The friend icon on bases that let friends in (src/ui/FriendsLockIcon.luau): when the sticker and the badge show,
-- and the sticker's face. The guis in the real world are checked in a Studio playtest.
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local FriendsLockIcon = UiHarness.ui("FriendsLockIcon")

describe("FriendsLockIcon", function()
	it("shows the badge while friends are allowed and the sticker only while the base is also locked", function()
		local function shown(allowed: any, locked: any): string
			local s = FriendsLockIcon.shown(allowed, locked)
			return `{s.sticker},{s.badge}`
		end
		expect(shown(true, true)).toBe("true,true")
		expect(shown(true, false)).toBe("false,true")
		expect(shown(nil, true)).toBe("false,false")
		expect(shown(nil, nil)).toBe("false,false")
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
