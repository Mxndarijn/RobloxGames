--!strict
-- Every item of both world shops (CONTRACT.md §27, Shops.SHOPS, flags ignored) has an uploaded picture
-- under ItemIcons.shopIconId(item).
local ItemIcons = require("../../src/ui/ItemIcons")
local Shops = require("../../src/shared/Shops")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local EXPECTED = {
	"Lock",
	"SpeedCoil",
	"Consumable_LuckPotion",
	"Consumable_WeatherTotem",
	"Pvp_KnockGlove1",
	"Pvp_KnockGlove2",
	"Pvp_KnockGlove3",
	"Pvp_KnockGlove4",
	"Pvp_KnockGlove5",
	"Pvp_GooTrap1",
	"Pvp_GooTrap2",
	"Pvp_GooTrap3",
	"Pvp_GooBlaster1",
	"Pvp_GooBlaster2",
	"Pvp_GooBlaster3",
	"Pvp_FunConfetti",
	"Pvp_FunBalloon",
	"Pvp_FunBubbles",
	"Pvp_FunBouncePad",
	"Pvp_FunSqueaky",
	"Pvp_FunHatLauncher",
	"Pvp_FunDanceBomb",
	"Pvp_FunFireworks",
	"LockUpgrade",
	"Upgrade_Income",
	"Upgrade_CarrySpeed",
	"Upgrade_OfflineCap",
	"Upgrade_Luck",
}

local function allItems(): { Shops.Item }
	local out: { Shops.Item } = {}
	for _, shopId in Shops.ORDER do
		for _, item in Shops.SHOPS[shopId].items do
			table.insert(out, item)
		end
	end
	return out
end

describe("shop item icons", function()
	it("every shop item has a positive integer image id under shopIconId", function()
		for _, item in allItems() do
			local id = ItemIcons.shopIconId(item)
			local image = ItemIcons.IMAGES[id]
			expect(`{id}: {type(image)}`).toBe(`{id}: number`)
			expect(`{id}: {image > 0 and image == math.floor(image)}`).toBe(`{id}: true`)
		end
	end)

	it("shopIconId yields exactly the 31 expected ids, in shop order", function()
		local got: { string } = {}
		for _, item in allItems() do
			table.insert(got, ItemIcons.shopIconId(item))
		end
		expect(table.concat(got, ",")).toBe(table.concat(EXPECTED, ","))
	end)

	it("maps actions to prefixes and leaves other items bare", function()
		expect(ItemIcons.shopIconId({ id = "Luck", action = "BuyUpgrade" })).toBe("Upgrade_Luck")
		expect(ItemIcons.shopIconId({ id = "LuckPotion", action = "BuyConsumable" })).toBe("Consumable_LuckPotion")
		expect(ItemIcons.shopIconId({ id = "GooTrap1", action = "BuyPvpItem" })).toBe("Pvp_GooTrap1")
		expect(ItemIcons.shopIconId({ id = "Lock", action = "Lock" })).toBe("Lock")
		expect(ItemIcons.shopIconId({ id = "SpeedCoil" })).toBe("SpeedCoil")
	end)
end)
