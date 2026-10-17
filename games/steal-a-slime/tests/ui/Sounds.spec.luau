--!strict
-- Notify sound name -> asset id mapping (src/ui/Sounds.luau).
local Sounds = require("../../src/ui/Sounds")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

-- Keep in sync with the `Notify` sound names in CONTRACT.md.
local CONTRACT_NAMES = {
	"Alarm",
	"Grab",
	"Stolen",
	"Escape",
	"Slap",
	"Lock",
	"Unlock",
	"Merge",
	"Cash",
	"Deposit",
	"Rain",
	"Rebirth",
	"Rare", -- v13, §8.6
	"Goal",
	"Secret", -- v28 Secret spawn announcement
	"PvpHit", -- v22 PvP feel (docs/PVP.md)
	"PvpCollide",
	"PvpGoo",
	"PvpSquirt",
	"PvpBoing",
	"PvpPop",
	"PvpSqueak",
	"PvpFirework",
	"PvpBubble",
}

describe("Sounds.resolve", function()
	it("resolves every CONTRACT sound name to a numeric rbxassetid", function()
		for _, name in CONTRACT_NAMES do
			local id = Sounds.resolve(name)
			expect(type(id)).toBe("string")
			expect(string.match(id :: string, "^rbxassetid://%d+$") ~= nil).toBe(true)
		end
	end)
	it("maps no names beyond the CONTRACT list", function()
		local count = 0
		for name in Sounds.IDS do
			count += 1
			expect(table.find(CONTRACT_NAMES, name) ~= nil).toBe(true)
		end
		expect(count).toBe(#CONTRACT_NAMES)
	end)
	it("passes raw rbxassetid strings through", function()
		expect(Sounds.resolve("rbxassetid://123456")).toBe("rbxassetid://123456")
	end)
	it("returns nil for nil, unknown names and malformed ids", function()
		expect(Sounds.resolve(nil)).toBe(nil)
		expect(Sounds.resolve("Nope")).toBe(nil)
		expect(Sounds.resolve("rbxassetid://abc")).toBe(nil)
		expect(Sounds.resolve(42)).toBe(nil)
	end)
end)
