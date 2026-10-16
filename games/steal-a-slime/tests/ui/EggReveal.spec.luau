--!strict
local EggReveal = require("../../src/ui/EggReveal")
local Remotes = require("../../src/shared/Remotes")
local ShopCatalog = require("../../src/ui/ShopCatalog")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function nameOf(slime: any): string
	return `Epic {slime.name}`
end

describe("EggReveal.banner", function()
	local view = { enabled = true, hatched = { slime = { name = "Blorp" }, at = 100 } }
	it("names the hatched slime while fresh", function()
		expect(EggReveal.banner(view, 103, 6, nameOf)).toBe("🥚 Hatched! Epic Blorp")
	end)
	it("hides when old, empty, nil or the feature is off", function()
		expect(EggReveal.banner(view, 107, 6, nameOf)).toBeNil()
		expect(EggReveal.banner({ enabled = true }, 100, 6, nameOf)).toBeNil()
		expect(EggReveal.banner(nil, 100, 6, nameOf)).toBeNil()
		expect(EggReveal.banner({ enabled = false, hatched = view.hatched }, 100, 6, nameOf)).toBeNil()
	end)
end)

describe("ShopCatalog egg row", function()
	local state = { cash = 5000, shop = { MysteryEgg = { price = 2000 } } }
	local function has(views: { ShopCatalog.ItemView }): boolean
		for _, v in views do
			if v.item.id == "MysteryEgg" then
				return true
			end
		end
		return false
	end
	it("is a buy row priced from State.shop", function()
		expect(has(ShopCatalog.views(state, Remotes.ACTIONS))).toBe(true)
		local view = ShopCatalog.view(ShopCatalog.find("MysteryEgg") :: ShopCatalog.Item, state, Remotes.ACTIONS)
		expect(view.buttonText).toBe("$2K")
		expect(view.enabled).toBe(true)
		expect(
			ShopCatalog.view(
				ShopCatalog.find("MysteryEgg") :: ShopCatalog.Item,
				{ cash = 5, shop = state.shop },
				Remotes.ACTIONS
			).enabled
		).toBe(false)
	end)
	it("is hidden when the feature is off", function()
		expect(has(ShopCatalog.views({ cash = 5000, shop = {} }, Remotes.ACTIONS))).toBe(false)
	end)
end)
