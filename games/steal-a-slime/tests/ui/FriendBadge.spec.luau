--!strict
local FriendBadge = require("../../src/ui/FriendBadge")
local Progress = require("../../src/ui/Progress")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("FriendBadge", function()
	it("shows the bonus in percent", function()
		expect(FriendBadge.line({ count = 1, bonus = 0.1 }, true)).toBe("Friends +10% income")
	end)
	it("hides with no friends, no view or the feature off", function()
		expect(FriendBadge.line(nil, true)).toBeNil()
		expect(FriendBadge.line({ count = 2, bonus = 0.2 }, false)).toBeNil()
	end)
end)

describe("Progress.incomeLine", function()
	it("joins the SlimeDex bonus and the friend line", function()
		expect(Progress.incomeLine("+5%", "Friends +20% income")).toBe("SlimeDex +5% · Friends +20% income")
		expect(Progress.incomeLine("+5%", nil)).toBe("SlimeDex bonus: +5% income")
		expect(Progress.incomeLine(nil, "Friends +20% income")).toBe("Friends +20% income")
		expect(Progress.incomeLine(nil, nil)).toBeNil()
	end)
end)

describe("friend badge placement", function()
	it("labels the slot with the bonus only (no timer), nil without friends or with the feature off", function()
		expect(FriendBadge.label({ count = 2, bonus = 0.1 }, true)).toBe("+10%")
		expect(FriendBadge.label({ count = 0, bonus = 0 }, true)).toBeNil()
		expect(FriendBadge.label({ count = 2, bonus = 0.1 }, false)).toBeNil()
		expect(FriendBadge.label(nil, true)).toBeNil()
	end)
end)
