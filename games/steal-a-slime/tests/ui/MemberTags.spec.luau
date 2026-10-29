--!strict
-- MemberTags (src/ui/MemberTags.luau): the VIP and Slime Club tags over heads and in chat.
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local MemberTags = UiHarness.ui("MemberTags")

describe("MemberTags", function()
	it("has a tag for VIP and the Slime Club only", function()
		expect(MemberTags.look("vip").text).toBe("VIP")
		expect(MemberTags.look("club").text).toBe("CLUB")
		expect(MemberTags.look(nil)).toBeNil()
		expect(MemberTags.look("admin")).toBeNil()
		expect(MemberTags.look(5)).toBeNil()
	end)
	it("prefixes a member's chat name with a coloured tag, nobody else's", function()
		local vip = MemberTags.chatPrefix("vip")
		expect(string.find(vip, "[VIP]", 1, true) ~= nil).toBe(true)
		expect(string.match(vip, '^<font color="#%x%x%x%x%x%x">') ~= nil).toBe(true)
		expect(string.find(MemberTags.chatPrefix("club"), "[CLUB]", 1, true) ~= nil).toBe(true)
		expect(MemberTags.chatPrefix(nil)).toBe("")
	end)
end)
