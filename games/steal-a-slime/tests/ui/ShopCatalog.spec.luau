--!strict
-- Shop catalogue resolution (src/ui/ShopCatalog.luau).
local Config = require("../../src/shared/Config")
local Remotes = require("../../src/shared/Remotes")
local ShopCatalog = require("../../src/ui/ShopCatalog")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local ALL = { Lock = {}, BuyLockUpgrade = {}, BuySpeedCoil = {} }

local function item(id: string): ShopCatalog.Item
	return ShopCatalog.find(id) :: ShopCatalog.Item
end

describe("ShopCatalog.ITEMS", function()
	it("has unique ids, a lock upgrade and a speed coil", function()
		local seen = {}
		for _, entry in ShopCatalog.ITEMS do
			expect(seen[entry.id]).toBeNil()
			seen[entry.id] = true
			expect(type(entry.action)).toBe("string")
		end
		expect(ShopCatalog.find("LockUpgrade")).toBeTruthy()
		expect(ShopCatalog.find("SpeedCoil")).toBeTruthy()
		expect(ShopCatalog.find("Nope")).toBeNil()
	end)
	it("buys lock time with the contracted Lock action", function()
		expect(item("Lock").action).toBe("Lock")
		expect(Remotes.ACTIONS.Lock).toBeTruthy()
	end)
end)

describe("ShopCatalog.view", function()
	it("prices Lock from lockCost / lockDuration", function()
		local view = ShopCatalog.view(item("Lock"), { cash = 500, lockCost = 200, lockDuration = 70 }, Remotes.ACTIONS)
		expect(view.available).toBe(true)
		expect(view.enabled).toBe(true)
		expect(view.buttonText).toBe("$200")
		expect(string.find(view.description, "+70s", 1, true) ~= nil).toBe(true)
	end)
	it("disables what the player can't afford", function()
		local view = ShopCatalog.view(item("Lock"), { cash = 50, lockCost = 200, lockDuration = 60 }, Remotes.ACTIONS)
		expect(view.enabled).toBe(false)
		expect(view.buttonText).toBe("$200")
	end)
	it("shows Coming soon while the server has no action", function()
		local view = ShopCatalog.view(item("SpeedCoil"), { cash = 1e9 }, { Lock = {} })
		expect(view.available).toBe(false)
		expect(view.enabled).toBe(false)
		expect(view.buttonText).toBe("Coming soon")
	end)
	it("reads level / price from state.shop", function()
		local state = { cash = 1000, shop = { LockUpgrade = { price = 750, level = 2, maxLevel = 5 } } }
		local view = ShopCatalog.view(item("LockUpgrade"), state, ALL)
		expect(view.enabled).toBe(true)
		expect(view.buttonText).toBe("$750")
		expect(view.levelText).toBe("Lv 2/5")
	end)
	it("marks max level and owned items", function()
		local maxed = ShopCatalog.view(
			item("LockUpgrade"),
			{ cash = 1, shop = { LockUpgrade = { level = 5, maxLevel = 5 } } },
			ALL
		)
		expect(maxed.maxed).toBe(true)
		expect(maxed.enabled).toBe(false)
		expect(maxed.buttonText).toBe("Max")
		local owned = ShopCatalog.view(item("SpeedCoil"), { cash = 1, shop = { SpeedCoil = { owned = true } } }, ALL)
		expect(owned.buttonText).toBe("Owned")
		expect(owned.enabled).toBe(false)
	end)
	it("lets the server decide when an available item has no price yet", function()
		local view = ShopCatalog.view(item("SpeedCoil"), { cash = 0 }, ALL)
		expect(view.enabled).toBe(true)
		expect(view.buttonText).toBe("Buy")
		expect(view.levelText).toBeNil()
	end)
	it("returns one view per item (the egg row only with State.shop.MysteryEgg)", function()
		expect(#ShopCatalog.views({ cash = 0 }, Remotes.ACTIONS)).toBe(#ShopCatalog.ITEMS - 1)
		local withEgg = { cash = 0, shop = { MysteryEgg = { price = 1 } } }
		expect(#ShopCatalog.views(withEgg, Remotes.ACTIONS)).toBe(#ShopCatalog.ITEMS)
	end)
end)

describe("ShopCatalog Speed Coil copy", function()
	local function has(text: string, needle: string): boolean
		return string.find(text, needle, 1, true) ~= nil
	end
	it("shows the Config walk speeds and that it helps while carrying", function()
		local view = ShopCatalog.view(item("SpeedCoil"), { cash = 0 }, ALL, Config)
		expect(has(view.description, `{Config.BASE_WALK_SPEED} → {Config.SPEED_COIL_WALK_SPEED}`)).toBe(true)
		expect(has(view.description, "while carrying")).toBe(true)
		local viaViews = ShopCatalog.views({ cash = 0 }, ALL, Config)
		for _, v in viaViews do
			if v.item.id == "SpeedCoil" then
				expect(v.description).toBe(view.description)
			end
		end
	end)
	it("never claims it only works when not carrying", function()
		for _, config in { Config, {} } do
			local view = ShopCatalog.view(item("SpeedCoil"), { cash = 0 }, ALL, config)
			expect(has(view.description, "not carrying")).toBe(false)
		end
		expect(has(ShopCatalog.view(item("SpeedCoil"), { cash = 0 }, ALL).description, "not carrying")).toBe(false)
		expect(ShopCatalog.speedCoilText({ BASE_WALK_SPEED = "16" })).toBeNil()
	end)
end)

describe("ShopCatalog.upgradeViews (v13 State.upgrades)", function()
	local upgrades = {
		{
			id = "Income",
			name = "Slime Snacks",
			text = "+10% income",
			level = 2,
			maxLevel = 10,
			price = 12500,
			requires = 0,
			unlocked = true,
		},
		{
			id = "CarrySpeed",
			name = "Strong Arms",
			text = "-15% carry slowdown",
			level = 0,
			maxLevel = 4,
			requires = 1,
			unlocked = false,
		},
		{
			id = "Luck",
			name = "Lucky Charm",
			text = "+4% luck",
			level = 5,
			maxLevel = 5,
			requires = 5,
			unlocked = true,
		},
	}
	local actions = { BuyUpgrade = {} }
	it("builds BuyUpgrade(id) rows with level, price and lock state", function()
		local views = ShopCatalog.upgradeViews({ cash = 20000, upgrades = upgrades }, actions)
		expect(#views).toBe(3)
		expect(views[1].item.action).toBe("BuyUpgrade")
		expect(views[1].item.args[1]).toBe("Income")
		expect(views[1].buttonText).toBe("$12.5K")
		expect(views[1].levelText).toBe("Lv 2/10")
		expect(views[1].enabled).toBe(true)
		expect(views[2].buttonText).toBe("Rebirth 1")
		expect(views[2].enabled).toBe(false)
		expect(views[3].buttonText).toBe("Max")
	end)
	it("says Coming soon before the server has BuyUpgrade, and is empty without upgrades", function()
		local views = ShopCatalog.upgradeViews({ cash = 1e9, upgrades = upgrades }, {})
		expect(views[1].buttonText).toBe("Coming soon")
		expect(views[1].enabled).toBe(false)
		expect(#ShopCatalog.upgradeViews({ cash = 1 }, actions)).toBe(0)
		expect(#ShopCatalog.views({ cash = 1, upgrades = upgrades }, actions)).toBe(#ShopCatalog.ITEMS + 2)
	end)
end)

describe("ShopCatalog consumables (FEATURES.Consumables)", function()
	local function state(left: number)
		return {
			cash = 5000,
			serverTime = 1000,
			favoriteId = "b",
			slimes = { { slime = { id = "a", tier = 5 } }, { slime = { id = "b", tier = 1 } } },
			consumables = {
				restockAt = 1200,
				items = {
					{
						id = "MutationSpray",
						name = "Mutation Spray",
						icon = "🧪",
						text = "t",
						price = 3000,
						left = left,
						max = 3,
					},
					{
						id = "LuckPotion",
						name = "Luck Potion",
						icon = "🍀",
						text = "t",
						price = 6000,
						left = 1,
						max = 1,
					},
				},
			},
		}
	end
	it("lists a row per stocked item with quantities, after the other rows", function()
		local views = ShopCatalog.views(state(2), Remotes.ACTIONS, Config)
		local spray = views[#views - 1]
		expect(spray.item.id).toBe("Consumable_MutationSpray")
		expect(spray.levelText).toBe("2/3 left")
		expect(spray.enabled).toBe(true)
		expect(spray.item.action).toBe("BuyConsumable")
		expect(Remotes.ACTIONS.BuyConsumable ~= nil).toBe(true)
	end)
	it("sprays the favourite, disables sold out and unaffordable rows", function()
		local views = ShopCatalog.consumableViews(state(0), Remotes.ACTIONS)
		expect(views[1].item.args[2]).toBe("b")
		expect(views[1].enabled).toBe(false)
		expect(views[1].buttonText).toBe("Sold out")
		expect(views[2].enabled).toBe(false) -- 6000 > 5000 cash
		expect(#ShopCatalog.consumableViews({ cash = 1 }, Remotes.ACTIONS)).toBe(0)
	end)
	it("formats the restock countdown", function()
		expect(ShopCatalog.restockText(1200, 1000)).toBe("Restocks in 3:20")
		expect(ShopCatalog.restockText(1200, 1195.5)).toBe("Restocks in 0:05")
		expect(ShopCatalog.restockText(1200, 1300)).toBe("Restocks in 0:00")
	end)
end)
