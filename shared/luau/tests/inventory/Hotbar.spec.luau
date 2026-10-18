--!strict
local Hotbar = require("../../src/inventory/Hotbar")
local HotbarLayout = require("../../src/inventory/HotbarLayout")
local Inventory = require("../../src/inventory/Inventory")
local InventoryActions = require("../../src/inventory/InventoryActions")
local ItemRegistry = require("../../src/inventory/ItemRegistry")
local T = require("../../testing/TestRunner")

local describe, it, expect = T.describe, T.it, T.expect

local registry = ItemRegistry.new({
	{ id = "Sword", name = "Sword", icon = "rbxassetid://1" },
	{ id = "Potion", name = "Potion", maxStack = 5, color = { 200, 40, 40 } },
})

describe("Hotbar.entries", function()
	it("lists filled hotbar slots in order, then extras", function()
		local inv = Inventory.new(registry, { capacity = 6, hotbarSize = 3 })
		inv:add("Sword")
		inv:add("Potion", 3)
		inv:move(2, 3)
		inv:add("Potion", 5) -- fills slot 3 to 5, then slot 2 gets 3
		inv:equip(3)
		local entries = Hotbar.entries(inv:snapshot(), registry, {
			{ key = "Bat", itemId = "Bat", name = "Bat", equipped = false },
		})
		expect(#entries).toBe(4)
		expect(entries[1].key).toBe("slot:1")
		expect(entries[1].icon).toBe("rbxassetid://1")
		expect(entries[1].count).toBeNil()
		expect(entries[3].slot).toBe(3)
		expect(entries[3].equipped).toBe(true)
		expect(entries[3].count).toBe(5)
		expect(entries[4].key).toBe("extra:Bat")
	end)

	it("grid lists the whole inventory, not only the hotbar", function()
		local inv = Inventory.new(registry, { capacity = 4, hotbarSize = 1 })
		inv:add("Sword")
		inv:add("Potion", 2)
		expect(#Hotbar.entries(inv:snapshot(), registry)).toBe(1)
		expect(#Hotbar.gridEntries(inv:snapshot(), registry)).toBe(2)
		expect(#Hotbar.entries(nil, registry)).toBe(0)
	end)
end)

describe("Hotbar.select", function()
	it("toggles equip, and routes extras to the game", function()
		local slotEntry = { key = "slot:2", slot = 2, itemId = "Sword", name = "Sword", equipped = false }
		expect(Hotbar.select(slotEntry :: any)).toEqual({ kind = "Equip", slot = 2 })
		slotEntry.equipped = true
		expect(Hotbar.select(slotEntry :: any)).toEqual({ kind = "Unequip" })
		local extra = { key = "extra:Bat", itemId = "Bat", name = "Bat", equipped = false }
		expect(Hotbar.select(extra :: any)).toEqual({ kind = "Extra", key = "Bat", equip = true })
	end)

	it("byKey only reaches shown entries", function()
		local entries = { { key = "a" }, { key = "b" }, { key = "c" } } :: any
		expect(Hotbar.byKey(entries, 2, 2).key).toBe("b")
		expect(Hotbar.byKey(entries, 2, 3)).toBeNil()
		expect(Hotbar.byKey(entries, 3, 0)).toBeNil()
	end)

	it("formats counts and cooldowns", function()
		expect(Hotbar.countText(1)).toBeNil()
		expect(Hotbar.countText(7)).toBe("7")
		expect(Hotbar.countText(150)).toBe("99+")
		expect(Hotbar.cooldownText({ cooldownUntil = 10.2 } :: any, 8)).toBe("3")
		expect(Hotbar.cooldownText({ cooldownUntil = 10 } :: any, 10)).toBeNil()
	end)

	it("signature changes only when something drawn changes", function()
		local a = { { key = "slot:1", itemId = "Sword", equipped = false } } :: any
		local b = { { key = "slot:1", itemId = "Sword", equipped = false } } :: any
		expect(Hotbar.signature(a)).toBe(Hotbar.signature(b))
		b[1].equipped = true
		expect(Hotbar.signature(a) == Hotbar.signature(b)).toBe(false)
	end)
end)

describe("InventoryActions.handle", function()
	it("validates untrusted args before touching the inventory", function()
		local inv = Inventory.new(registry, { capacity = 3 })
		inv:add("Potion", 4)
		expect(select(2, InventoryActions.handle(inv, "Equip", { "1" }))).toBe("BadArgs")
		expect(select(2, InventoryActions.handle(inv, "Move", { 1, 0 / 0 }))).toBe("BadArgs")
		expect(select(2, InventoryActions.handle(inv, "Split", { 1, 2 }))).toBe("BadArgs")
		expect(select(2, InventoryActions.handle(inv, "Hack", {}))).toBe("UnknownAction")
		expect(InventoryActions.handle(inv, "Equip", { 1 })).toBe(true)
		expect(InventoryActions.handle(inv, "Split", { 1, 3, 2 })).toBe(true)
		expect(inv:get(3)).toEqual({ id = "Potion", count = 2 })
		expect(InventoryActions.handle(inv, "Equip", {})).toBe(true)
		expect((inv:equipped())).toBeNil()
	end)

	it("Drop only works when the game allows it", function()
		local inv = Inventory.new(registry, { capacity = 2 })
		inv:add("Sword")
		expect(select(2, InventoryActions.handle(inv, "Drop", { 1 }))).toBe("UnknownAction")
		expect(InventoryActions.handle(inv, "Drop", { 1 }, { allowDrop = true })).toBe(true)
		expect(inv:get(1)).toBeNil()
	end)
end)

describe("HotbarLayout", function()
	local m = HotbarLayout.DEFAULT

	it("centres the bar in the zone, bottom-aligned, with the bag last", function()
		local zone = { x = 0, y = 0, w = 1000, h = 200 }
		local bar = HotbarLayout.bar(m, zone, 3, false)
		expect(bar.shown).toBe(3)
		local w = HotbarLayout.barWidth(m, 4, m.slot)
		expect(bar.rect.w).toBe(w)
		expect(bar.rect.x).toBe(math.floor((1000 - w) / 2))
		expect(bar.rect.y + bar.rect.h).toBe(200)
		expect(bar.bag and bar.bag.x).toBe(bar.slots[3].x + m.slot + m.gap)
	end)

	it("shows only what fits and never more than maxSlots", function()
		local narrow = HotbarLayout.bar(m, { x = 0, y = 0, w = 200, h = 80 }, 9, false)
		expect(narrow.shown).toBe(2)
		local wide = HotbarLayout.bar(m, { x = 0, y = 0, w = 5000, h = 80 }, 20, false)
		expect(wide.shown).toBe(9)
	end)

	it("uses the touch minimum and accepts overrides", function()
		local big = HotbarLayout.metrics({ slot = 40, minTouch = 56, bag = false, cell = { w = 50 } })
		expect(HotbarLayout.slotSize(big, true)).toBe(56)
		expect(HotbarLayout.slotSize(big, false)).toBe(40)
		expect(big.cell.w).toBe(50)
		expect(big.cell.h).toBe(m.cell.h)
		local bar = HotbarLayout.bar(big, { x = 0, y = 0, w = 1000, h = 80 }, 2, false)
		expect(bar.bag).toBeNil()
	end)

	it("lays the grid out in rows", function()
		local cols = HotbarLayout.columns(m, 400)
		expect(cols).toBe(4)
		local fifth = HotbarLayout.cell(m, 5, 400)
		expect(fifth.x).toBe(0)
		expect(fifth.y).toBe(m.cell.h + m.cell.gap)
		expect(HotbarLayout.gridHeight(m, 5, 400)).toBe(2 * m.cell.h + m.cell.gap)
		expect(HotbarLayout.gridHeight(m, 0, 400)).toBe(0)
	end)
end)
