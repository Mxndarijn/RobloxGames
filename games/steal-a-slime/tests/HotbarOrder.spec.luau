--!strict
local Config = require("../src/shared/Config")
local Constants = require("../src/shared/Constants")
local HotbarOrder = require("../src/shared/HotbarOrder")
local PlayerData = require("../src/shared/PlayerData")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local EMPTY = { "", "", "", "", "", "", "", "", "" }

describe("HotbarOrder.parse", function()
	it("pads to 9 slots, slot 1 first, empty parts are empty slots", function()
		expect(HotbarOrder.parse("")).toEqual(EMPTY)
		expect(HotbarOrder.parse("tool:Bat,pvp:KnockGlove1,,consumable:LuckPotion")).toEqual({
			"tool:Bat",
			"pvp:KnockGlove1",
			"",
			"consumable:LuckPotion",
			"",
			"",
			"",
			"",
			"",
		})
		expect(HotbarOrder.parse(",,,,,,,,tool:Speed Coil")).toEqual({
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"",
			"tool:Speed Coil",
		})
		expect(HotbarOrder.parse("tool:Bat,,")).toEqual({ "tool:Bat", "", "", "", "", "", "", "", "" })
	end)
	it("allows repeated empty slots but refuses a repeated key", function()
		expect((HotbarOrder.parse(",,tool:Bat,,")) ~= nil).toBe(true)
		local list, reason = HotbarOrder.parse("tool:Bat,,tool:Bat")
		expect(list).toBeNil()
		expect(reason).toBe("bad argument")
	end)
	it("refuses too many parts, too long strings and malformed keys", function()
		expect((HotbarOrder.parse(",,,,,,,,,"))).toBeNil() -- 10 parts
		expect((HotbarOrder.parse(string.rep("x", HotbarOrder.MAX_LENGTH + 1)))).toBeNil()
		for _, bad in { "Bat", "tool:", ":Bat", "weapon:Bat", "tool:Bat!", "tool: Bat", "tool:Bat ", "TOOL:Bat" } do
			expect((HotbarOrder.parse(bad))).toBeNil()
		end
		expect((HotbarOrder.parse("tool:" .. string.rep("a", HotbarOrder.MAX_ID_LENGTH + 1)))).toBeNil()
		expect((HotbarOrder.parse(42 :: any))).toBeNil()
	end)
	it("accepts 9 of the longest Tool keys, and the cap fits 9 ids of the longest prefix", function()
		local keys = {}
		for i = 1, HotbarOrder.SLOTS do
			table.insert(keys, `tool:{string.rep("a", HotbarOrder.MAX_ID_LENGTH - 1)}{i}`)
		end
		expect(HotbarOrder.parse(table.concat(keys, ","))).toEqual(keys)
		local longest = #"consumable:" + HotbarOrder.MAX_ID_LENGTH
		expect(HotbarOrder.SLOTS * longest + HotbarOrder.SLOTS - 1 <= HotbarOrder.MAX_LENGTH).toBe(true)
	end)
	it("refuses pvp / consumable ids that are not in the catalog; Tool names are free-form", function()
		for _, bad in { "pvp:nonexistent", "consumable:Nope", "pvp:LuckPotion", "consumable:KnockGlove1" } do
			local list, reason = HotbarOrder.parse(bad)
			expect(list).toBeNil()
			expect(reason).toBe("bad argument")
		end
		expect((HotbarOrder.parse("tool:Anything Goes")) ~= nil).toBe(true)
	end)
end)

describe("HotbarOrder.isKey", function()
	it("accepts every key the game's own items make", function()
		for _, tool in Config.PVP_TOOLS do
			expect(HotbarOrder.isKey(`pvp:{tool.id}`)).toBe(true)
		end
		for _, def in Config.CONSUMABLES do
			expect(HotbarOrder.isKey(`consumable:{def.id}`)).toBe(true)
		end
		expect(HotbarOrder.isKey(`tool:{Config.BAT.TOOL_NAME}`)).toBe(true)
		expect(HotbarOrder.isKey(`tool:{Constants.SPEED_COIL_TOOL}`)).toBe(true)
	end)
end)

describe("HotbarOrder.clean", function()
	it("returns nil for anything that is not a list", function()
		expect(HotbarOrder.clean(nil)).toBeNil()
		expect(HotbarOrder.clean("tool:Bat")).toBeNil()
		expect(HotbarOrder.clean(7)).toBeNil()
	end)
	it("turns junk entries and repeats into empty slots and drops entries past slot 9", function()
		local raw = { "tool:Bat", 5, "nope", "tool:Bat", "pvp:KnockGlove1", "", "", "", "", "consumable:LuckPotion" }
		expect(HotbarOrder.clean(raw)).toEqual({ "tool:Bat", "", "", "", "pvp:KnockGlove1", "", "", "", "" })
		expect(HotbarOrder.clean({})).toEqual(EMPTY)
		expect(HotbarOrder.clean({ [3] = "tool:Bat" })).toEqual({ "", "", "tool:Bat", "", "", "", "", "", "" })
		-- an item id that left the catalog loads as an empty slot
		expect(HotbarOrder.clean({ "pvp:Retired", "consumable:Retired", "tool:Bat" })).toEqual({
			"",
			"",
			"tool:Bat",
			"",
			"",
			"",
			"",
			"",
			"",
		})
	end)
end)

describe("HotbarOrder.set", function()
	it("stores a parsed order and leaves the old one on a refusal", function()
		local data = PlayerData.new()
		expect(data.hotbar).toBeNil()
		expect(HotbarOrder.set(data, "pvp:KnockGlove1")).toBe(true)
		expect(data.hotbar).toEqual({ "pvp:KnockGlove1", "", "", "", "", "", "", "", "" })
		local ok, reason = HotbarOrder.set(data, "pvp:KnockGlove1,pvp:KnockGlove1")
		expect(ok).toBe(false)
		expect(reason).toBe("bad argument")
		expect((data.hotbar :: { string })[1]).toBe("pvp:KnockGlove1")
	end)
end)
