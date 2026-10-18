--!strict
local Inventory = require("../../src/inventory/Inventory")
local ItemRegistry = require("../../src/inventory/ItemRegistry")
local T = require("../../testing/TestRunner")

local describe, it, expect = T.describe, T.it, T.expect

local registry = ItemRegistry.new({
	{ id = "Sword", name = "Sword" },
	{ id = "Potion", name = "Potion", maxStack = 5, kind = "consumable" },
	{ id = "Coin", name = "Coin", maxStack = 99 },
})

local function new(capacity: number?, hotbarSize: number?)
	return Inventory.new(registry, { capacity = capacity or 4, hotbarSize = hotbarSize })
end

describe("ItemRegistry", function()
	it("defaults maxStack to 1 and keeps definition order", function()
		local sword = registry.get("Sword")
		expect(sword and sword.maxStack).toBe(1)
		expect(registry.order).toEqual({ "Sword", "Potion", "Coin" })
		expect(registry.has("Nope")).toBe(false)
	end)

	it("rejects duplicate ids and bad stacks", function()
		expect(function()
			ItemRegistry.new({ { id = "A", name = "A" }, { id = "A", name = "B" } })
		end).toThrow()
		expect(function()
			ItemRegistry.new({ { id = "A", name = "A", maxStack = 0 } })
		end).toThrow()
		expect(function()
			ItemRegistry.new({ { id = "A", name = "A", maxStack = 1.5 } })
		end).toThrow()
	end)
end)

describe("Inventory.add", function()
	it("fills existing stacks before empty slots", function()
		local inv = new()
		expect(inv:add("Potion", 3)).toBe(true)
		expect(inv:add("Potion", 4)).toBe(true)
		expect(inv:get(1)).toEqual({ id = "Potion", count = 5 })
		expect(inv:get(2)).toEqual({ id = "Potion", count = 2 })
		expect(inv:count("Potion")).toBe(7)
	end)

	it("is atomic: adds nothing when the whole amount does not fit", function()
		local inv = new(2)
		inv:add("Sword")
		local ok, reason = inv:add("Potion", 6)
		expect(ok).toBe(false)
		expect(reason).toBe("Full")
		expect(inv:count("Potion")).toBe(0)
		expect(inv.revision).toBe(1)
	end)

	it("refuses unknown items and bad counts", function()
		local inv = new()
		expect(select(2, inv:add("Nope"))).toBe("Unknown")
		expect(select(2, inv:add("Potion", 0))).toBe("BadCount")
		expect(select(2, inv:add("Potion", 1.5))).toBe("BadCount")
		expect(select(2, inv:add("Potion", 0 / 0))).toBe("BadCount")
		expect(select(2, inv:add("Potion", math.huge))).toBe("BadCount")
	end)

	it("canAdd matches add", function()
		local inv = new(1)
		expect(inv:canAdd("Potion", 5)).toBe(true)
		expect(inv:canAdd("Potion", 6)).toBe(false)
		expect(inv:canAdd("Nope")).toBe(false)
	end)
end)

describe("Inventory.remove", function()
	it("takes from the highest slots first and frees empty slots", function()
		local inv = new()
		inv:add("Potion", 7) -- slot 1: 5, slot 2: 2
		expect(inv:remove("Potion", 3)).toBe(true)
		expect(inv:get(1)).toEqual({ id = "Potion", count = 4 })
		expect(inv:get(2)).toBeNil()
	end)

	it("is atomic when there are not enough", function()
		local inv = new()
		inv:add("Potion", 2)
		local ok, reason = inv:remove("Potion", 3)
		expect(ok).toBe(false)
		expect(reason).toBe("NotEnough")
		expect(inv:count("Potion")).toBe(2)
	end)

	it("removeAt checks the slot", function()
		local inv = new()
		inv:add("Sword")
		expect(select(2, inv:removeAt(9))).toBe("BadSlot")
		expect(select(2, inv:removeAt(2))).toBe("Empty")
		expect(select(2, inv:removeAt(1, 2))).toBe("NotEnough")
		expect(inv:removeAt(1)).toBe(true)
		expect(inv:get(1)).toBeNil()
	end)
end)

describe("Inventory.move and split", function()
	it("moves onto an empty slot and the equipped mark follows", function()
		local inv = new()
		inv:add("Sword")
		inv:equip(1)
		expect(inv:move(1, 3)).toBe(true)
		expect(inv:get(3)).toEqual({ id = "Sword", count = 1 })
		expect((inv:equipped())).toBe(3)
	end)

	it("swaps different items", function()
		local inv = new()
		inv:add("Sword")
		inv:add("Potion", 2)
		inv:equip(2)
		inv:move(1, 2)
		expect(inv:get(1)).toEqual({ id = "Potion", count = 2 })
		expect(inv:get(2)).toEqual({ id = "Sword", count = 1 })
		expect((inv:equipped())).toBe(1)
	end)

	it("merges the same item up to maxStack and leaves the rest", function()
		local inv = new()
		inv:add("Potion", 5)
		inv:split(1, 2, 2) -- 3 | 2
		inv:add("Potion", 2) -- 5 | 2? fills slot 1 first
		expect(inv:get(1)).toEqual({ id = "Potion", count = 5 })
		expect(inv:get(2)).toEqual({ id = "Potion", count = 2 })
		expect(inv:move(2, 1)).toBe(false)
		inv:remove("Potion", 4) -- takes slot 2 (2) then slot 1 (2): 3 | -
		expect(inv:get(1)).toEqual({ id = "Potion", count = 3 })
	end)

	it("split refuses a different item or an overfull target", function()
		local inv = new()
		inv:add("Potion", 4)
		inv:add("Sword")
		expect(select(2, inv:split(1, 2, 1))).toBe("Mismatch")
		inv:add("Potion", 5) -- slot 1 to 5, slot 3 gets 4
		expect(select(2, inv:split(3, 1, 1))).toBe("Full")
		expect(select(2, inv:split(1, 1, 1))).toBe("BadSlot")
	end)
end)

describe("Inventory.equip", function()
	it("equips, unequips and refuses empty slots", function()
		local inv = new()
		inv:add("Sword")
		expect(select(2, inv:equip(2))).toBe("Empty")
		expect(inv:equip(1)).toBe(true)
		local slot, stack = inv:equipped()
		expect(slot).toBe(1)
		expect(stack and stack.id).toBe("Sword")
		inv:equip(nil)
		expect((inv:equipped())).toBeNil()
	end)

	it("using the last of a stack in hand puts it away", function()
		local inv = new()
		inv:add("Potion", 2)
		inv:equip(1)
		expect(inv:consumeEquipped()).toBe(true)
		expect((inv:equipped())).toBe(1)
		expect(inv:consumeEquipped()).toBe(true)
		expect((inv:equipped())).toBeNil()
		expect(select(2, inv:consumeEquipped())).toBe("Empty")
	end)

	it("calls onChanged once per change and never on a no-op", function()
		local calls = 0
		local inv = Inventory.new(registry, {
			capacity = 3,
			onChanged = function()
				calls += 1
			end,
		})
		inv:add("Sword")
		inv:equip(1)
		inv:equip(1)
		inv:add("Nope")
		inv:clear()
		inv:clear()
		expect(calls).toBe(3)
	end)
end)

describe("Inventory snapshot and save", function()
	it("snapshot is a frozen copy", function()
		local inv = new(4, 2)
		inv:add("Potion", 3)
		local snap = inv:snapshot()
		expect(snap.capacity).toBe(4)
		expect(snap.hotbarSize).toBe(2)
		expect(snap.slots[1].count).toBe(3)
		expect(table.isfrozen(snap.slots)).toBe(true)
		inv:add("Potion")
		expect(snap.slots[1].count).toBe(3)
	end)

	it("round-trips through serialize / deserialize", function()
		local inv = new()
		inv:add("Sword")
		inv:add("Coin", 40)
		inv:move(2, 4)
		inv:equip(4)
		local loaded, dropped = Inventory.deserialize(registry, inv:serialize(), { capacity = 4 })
		expect(#dropped).toBe(0)
		expect(loaded:get(4)).toEqual({ id = "Coin", count = 40 })
		expect((loaded:equipped())).toBe(4)
	end)

	it("drops unknown items and over-stack, rehomes bad slots, never errors on garbage", function()
		local saved = {
			format = 1,
			slots = {
				{ slot = 1, id = "Gone", count = 2 },
				{ slot = 1, id = "Potion", count = 9 },
				{ slot = 1, id = "Sword", count = 1 },
				{ slot = 99, id = "Coin", count = 5 },
				"junk",
			},
			equipped = 7,
		}
		local inv, dropped = Inventory.deserialize(registry, saved, { capacity = 2 })
		expect(inv:get(1)).toEqual({ id = "Potion", count = 5 })
		expect(inv:get(2)).toEqual({ id = "Sword", count = 1 })
		expect((inv:equipped())).toBeNil()
		local why = {}
		for _, d in dropped do
			why[d.id] = d.why
		end
		expect(why).toEqual({ Gone = "Unknown", Potion = "OverStack", Coin = "Full" })
		local empty = Inventory.deserialize(registry, "garbage", { capacity = 2 })
		expect(empty:get(1)).toBeNil()
	end)
end)
