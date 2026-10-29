--!strict
-- Every Exclusive Shop product and Game Pass in Config has its Roblox id (src/shared/ExclusiveIds.luau), and no two
-- share one. A new product needs creating on Roblox (Open Cloud, contract/exclusive-shop.md §1) before it ships.
local Config = require("../src/shared/Config")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

describe("Exclusive Shop Roblox ids", function()
	it("every product and pass has a unique id", function()
		local seen: { [number]: string } = {}
		for key, def in Config.EXCLUSIVE_SHOP.products do
			expect(`{key}: {def.productId > 0}`).toBe(`{key}: true`)
			expect(`{key}: {seen[def.productId] or "unique"}`).toBe(`{key}: unique`)
			seen[def.productId] = key
		end
		for key, def in Config.EXCLUSIVE_SHOP.passes do
			expect(`{key}: {def.passId > 0}`).toBe(`{key}: true`)
		end
	end)
end)
