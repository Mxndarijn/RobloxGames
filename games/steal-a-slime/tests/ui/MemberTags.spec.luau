--!strict
-- MemberTags (src/ui/MemberTags.luau): the VIP and Slime Club tags over heads and in chat.
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local MemberTags = UiHarness.ui("MemberTags")
local LabelFit = require("../../../../shared/luau/src/ui/LabelFit")
local roblox = require("@lune/roblox") :: any

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
	it("draws a member's chip as a phone-fit pill, outlined on its edge so the letters stay apart", function()
		local function signal()
			return {
				Connect = function()
					return { Disconnect = function() end }
				end,
			}
		end
		local character = roblox.Instance.new("Model")
		local head = roblox.Instance.new("Part")
		head.Name = "Head"
		head.Parent = character
		local player = {
			UserId = 7,
			Character = character,
			CharacterAdded = signal(),
			GetAttribute = function(_, name: string): any
				return if name == "Member" then "vip" else nil
			end,
			GetAttributeChangedSignal = function()
				return signal()
			end,
		}
		local players = {
			PlayerAdded = signal(),
			PlayerRemoving = signal(),
			GetPlayers = function()
				return { player }
			end,
		}
		local gui = UiHarness.Instance.new("Folder")
		local stop = MemberTags.start({ Players = players, attribute = "Member", playerGui = gui })
		local chip = gui:FindFirstChild(MemberTags.FOLDER):FindFirstChild("Member_7")
		local s = MemberTags.SIZE
		expect(chip.Size.X.Offset).toBe(s.w)
		expect(chip.Size.Y.Offset <= 60).toBe(true) -- a pixel tag stays at most 60 px tall at 720p
		expect(chip:HasTag(LabelFit.TAG)).toBe(true)
		expect(chip.MaxDistance).toBe(s.maxDistance)
		local tag = chip:FindFirstChild("Tag")
		expect(tag.Text).toBe("VIP")
		expect(tag.TextSize >= 14).toBe(true)
		expect(tag:FindFirstChildOfClass("UIStroke").ApplyStrokeMode).toBe(roblox.Enum.ApplyStrokeMode.Border)
		stop()
	end)
end)
