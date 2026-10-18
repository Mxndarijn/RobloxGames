--!strict
--[[
	Inventory: one player's items, owned and changed by the server only.

	A fixed number of slots (`capacity`); each slot is empty or holds a stack { id, count } of one item, at most
	the item's `maxStack`. The first `hotbarSize` slots are the hotbar. At most one slot is equipped (in hand).

	Every change is atomic: `add` either fits the whole amount or changes nothing, the same for `remove`.
	Mutating methods return (ok, reason) with reason one of:
	  "Unknown"   the item id is not in the registry
	  "BadCount"  count is not a whole number >= 1
	  "BadSlot"   slot index out of range
	  "Empty"     the slot has nothing in it
	  "Full"      not enough room
	  "NotEnough" fewer items than asked for
	  "Mismatch"  split onto a slot holding a different item
	After any successful change `revision` goes up by one and `onChanged` (if given) is called, so an adapter
	knows when to push a new snapshot to the client or mark the save dirty.

	`serialize` / `Inventory.deserialize` give a plain table for saving. Loading drops unknown items and clamps
	counts, and reports what it dropped so the game can log or refund it.
]]

local ItemRegistry = if script then require(script.Parent.ItemRegistry) else require("./ItemRegistry")

type Registry = ItemRegistry.Registry

export type Stack = { id: string, count: number }

export type Options = {
	capacity: number,
	hotbarSize: number?, -- default min(9, capacity)
	onChanged: ((inv: Inventory) -> ())?,
}

export type Snapshot = {
	capacity: number,
	hotbarSize: number,
	slots: { [number]: Stack }, -- sparse: only filled slots
	equipped: number?,
	revision: number,
}

export type Saved = {
	format: number,
	slots: { { slot: number, id: string, count: number } },
	equipped: number?,
}

export type Inventory = {
	capacity: number,
	hotbarSize: number,
	revision: number,

	get: (self: Inventory, slot: number) -> Stack?,
	count: (self: Inventory, id: string) -> number,
	has: (self: Inventory, id: string, count: number?) -> boolean,
	canAdd: (self: Inventory, id: string, count: number?) -> boolean,
	add: (self: Inventory, id: string, count: number?) -> (boolean, string?),
	remove: (self: Inventory, id: string, count: number?) -> (boolean, string?),
	removeAt: (self: Inventory, slot: number, count: number?) -> (boolean, string?),
	move: (self: Inventory, from: number, to: number) -> (boolean, string?),
	split: (self: Inventory, from: number, to: number, count: number) -> (boolean, string?),
	equip: (self: Inventory, slot: number?) -> (boolean, string?),
	equipped: (self: Inventory) -> (number?, Stack?),
	consumeEquipped: (self: Inventory, count: number?) -> (boolean, string?),
	clear: (self: Inventory) -> (),
	snapshot: (self: Inventory) -> Snapshot,
	serialize: (self: Inventory) -> Saved,
}

local SAVE_FORMAT = 1

local Inventory = {}
Inventory.__index = Inventory
Inventory.SAVE_FORMAT = SAVE_FORMAT

type Internal = Inventory & {
	_registry: Registry,
	_slots: { [number]: Stack },
	_equipped: number?,
	_onChanged: ((inv: Inventory) -> ())?,
}

local function wholeCount(count: number?): number?
	local n = if count == nil then 1 else count
	if type(n) ~= "number" or n < 1 or n ~= math.floor(n) or n ~= n or n == math.huge then
		return nil
	end
	return n
end

local function validSlot(self: Internal, slot: any): boolean
	return type(slot) == "number" and slot >= 1 and slot <= self.capacity and slot == math.floor(slot)
end

local function changed(self: Internal)
	self.revision += 1
	if self._onChanged then
		self._onChanged(self)
	end
end

function Inventory.new(registry: Registry, options: Options): Inventory
	assert(type(registry) == "table" and type(registry.get) == "function", "Inventory.new: expected an ItemRegistry")
	local capacity = options.capacity
	assert(
		type(capacity) == "number" and capacity >= 1 and capacity == math.floor(capacity),
		"Inventory.new: capacity must be a whole number >= 1"
	)
	local hotbarSize = options.hotbarSize or math.min(9, capacity)
	assert(hotbarSize >= 0 and hotbarSize <= capacity, "Inventory.new: hotbarSize must be within capacity")
	local self = setmetatable({
		capacity = capacity,
		hotbarSize = hotbarSize,
		revision = 0,
		_registry = registry,
		_slots = {},
		_equipped = nil,
		_onChanged = options.onChanged,
	}, Inventory)
	return (self :: any) :: Inventory
end

function Inventory.get(self: Internal, slot: number): Stack?
	local stack = self._slots[slot]
	return if stack then { id = stack.id, count = stack.count } else nil
end

function Inventory.count(self: Internal, id: string): number
	local total = 0
	for _, stack in self._slots do
		if stack.id == id then
			total += stack.count
		end
	end
	return total
end

function Inventory.has(self: Internal, id: string, count: number?): boolean
	return self:count(id) >= (count or 1)
end

-- Room for `id`: free space in existing stacks of it plus empty slots times maxStack.
local function room(self: Internal, id: string, maxStack: number): number
	local free = 0
	for slot = 1, self.capacity do
		local stack = self._slots[slot]
		if stack == nil then
			free += maxStack
		elseif stack.id == id then
			free += maxStack - stack.count
		end
	end
	return free
end

function Inventory.canAdd(self: Internal, id: string, count: number?): boolean
	local def = self._registry.get(id)
	local n = wholeCount(count)
	return def ~= nil and n ~= nil and room(self, id, def.maxStack) >= n
end

-- Fills existing stacks first (lowest slot first), then empty slots in order.
function Inventory.add(self: Internal, id: string, count: number?): (boolean, string?)
	local def = self._registry.get(id)
	if def == nil then
		return false, "Unknown"
	end
	local n = wholeCount(count)
	if n == nil then
		return false, "BadCount"
	end
	if room(self, id, def.maxStack) < n then
		return false, "Full"
	end
	local left = n
	for slot = 1, self.capacity do
		local stack = self._slots[slot]
		if stack and stack.id == id and stack.count < def.maxStack then
			local put = math.min(left, def.maxStack - stack.count)
			stack.count += put
			left -= put
			if left == 0 then
				break
			end
		end
	end
	for slot = 1, self.capacity do
		if left == 0 then
			break
		end
		if self._slots[slot] == nil then
			local put = math.min(left, def.maxStack)
			self._slots[slot] = { id = id, count = put }
			left -= put
		end
	end
	changed(self)
	return true, nil
end

local function take(self: Internal, slot: number, n: number)
	local stack = self._slots[slot]
	stack.count -= n
	if stack.count <= 0 then
		self._slots[slot] = nil
		if self._equipped == slot then
			self._equipped = nil
		end
	end
end

-- Takes from the highest slots first, so the hotbar keeps its items longest.
function Inventory.remove(self: Internal, id: string, count: number?): (boolean, string?)
	if self._registry.get(id) == nil then
		return false, "Unknown"
	end
	local n = wholeCount(count)
	if n == nil then
		return false, "BadCount"
	end
	if self:count(id) < n then
		return false, "NotEnough"
	end
	local left = n
	for slot = self.capacity, 1, -1 do
		local stack = self._slots[slot]
		if stack and stack.id == id then
			local put = math.min(left, stack.count)
			take(self, slot, put)
			left -= put
			if left == 0 then
				break
			end
		end
	end
	changed(self)
	return true, nil
end

function Inventory.removeAt(self: Internal, slot: number, count: number?): (boolean, string?)
	if not validSlot(self, slot) then
		return false, "BadSlot"
	end
	local stack = self._slots[slot]
	if stack == nil then
		return false, "Empty"
	end
	local n = wholeCount(count)
	if n == nil then
		return false, "BadCount"
	end
	if stack.count < n then
		return false, "NotEnough"
	end
	take(self, slot, n)
	changed(self)
	return true, nil
end

-- Moves the stack in `from` to `to`: onto an empty slot, merged into a stack of the same item (what does not
-- fit stays in `from`), or swapped with a different item. The equipped mark follows the stack it was on.
function Inventory.move(self: Internal, from: number, to: number): (boolean, string?)
	if not validSlot(self, from) or not validSlot(self, to) then
		return false, "BadSlot"
	end
	local a = self._slots[from]
	if a == nil then
		return false, "Empty"
	end
	if from == to then
		return true, nil
	end
	local b = self._slots[to]
	if b and b.id == a.id then
		local def = self._registry.get(a.id)
		local maxStack = if def then def.maxStack else b.count
		local put = math.min(a.count, maxStack - b.count)
		if put <= 0 then
			return false, "Full"
		end
		b.count += put
		a.count -= put
		if a.count <= 0 then
			self._slots[from] = nil
			if self._equipped == from then
				self._equipped = to
			end
		end
	else
		self._slots[from] = b :: any
		self._slots[to] = a
		if self._equipped == from then
			self._equipped = to
		elseif self._equipped == to then
			self._equipped = from
		end
	end
	changed(self)
	return true, nil
end

-- Moves `count` items from the stack in `from` onto `to` (empty, or the same item with room).
function Inventory.split(self: Internal, from: number, to: number, count: number): (boolean, string?)
	if not validSlot(self, from) or not validSlot(self, to) or from == to then
		return false, "BadSlot"
	end
	local a = self._slots[from]
	if a == nil then
		return false, "Empty"
	end
	local n = wholeCount(count)
	if n == nil then
		return false, "BadCount"
	end
	if a.count < n then
		return false, "NotEnough"
	end
	local b = self._slots[to]
	local def = self._registry.get(a.id)
	local maxStack = if def then def.maxStack else a.count
	if b and b.id ~= a.id then
		return false, "Mismatch"
	end
	if (if b then b.count else 0) + n > maxStack then
		return false, "Full"
	end
	if b then
		b.count += n
	else
		self._slots[to] = { id = a.id, count = n }
	end
	take(self, from, n)
	changed(self)
	return true, nil
end

-- Puts the item in `slot` in hand; nil puts whatever is in hand away. Equipping the slot already in hand is a no-op.
function Inventory.equip(self: Internal, slot: number?): (boolean, string?)
	if slot == nil then
		if self._equipped == nil then
			return true, nil
		end
		self._equipped = nil
		changed(self)
		return true, nil
	end
	if not validSlot(self, slot) then
		return false, "BadSlot"
	end
	if self._slots[slot] == nil then
		return false, "Empty"
	end
	if self._equipped == slot then
		return true, nil
	end
	self._equipped = slot
	changed(self)
	return true, nil
end

function Inventory.equipped(self: Internal): (number?, Stack?)
	local slot = self._equipped
	if slot == nil then
		return nil, nil
	end
	return slot, self:get(slot)
end

-- Uses `count` of the item in hand; an emptied stack is put away.
function Inventory.consumeEquipped(self: Internal, count: number?): (boolean, string?)
	local slot = self._equipped
	if slot == nil then
		return false, "Empty"
	end
	return self:removeAt(slot, count)
end

function Inventory.clear(self: Internal)
	if next(self._slots) == nil and self._equipped == nil then
		return
	end
	table.clear(self._slots)
	self._equipped = nil
	changed(self)
end

-- A frozen copy for the client: it renders this and never changes it.
function Inventory.snapshot(self: Internal): Snapshot
	local slots: { [number]: Stack } = {}
	for slot, stack in self._slots do
		slots[slot] = table.freeze({ id = stack.id, count = stack.count })
	end
	return table.freeze({
		capacity = self.capacity,
		hotbarSize = self.hotbarSize,
		slots = table.freeze(slots),
		equipped = self._equipped,
		revision = self.revision,
	})
end

function Inventory.serialize(self: Internal): Saved
	local slots = {}
	for slot = 1, self.capacity do
		local stack = self._slots[slot]
		if stack then
			table.insert(slots, { slot = slot, id = stack.id, count = stack.count })
		end
	end
	return { format = SAVE_FORMAT, slots = slots, equipped = self._equipped }
end

export type Dropped = { id: string, count: number, why: string }

--[[
	Builds an Inventory from saved data. Never errors on bad data: nil or garbage gives an empty inventory.
	Items not in the registry are dropped, counts are clamped to 1..maxStack (the overflow is dropped), and a
	slot past capacity or used twice moves the stack to the first free slot (dropped when none is left).
	Returns the inventory and the list of what was dropped.
]]
function Inventory.deserialize(registry: Registry, saved: any, options: Options): (Inventory, { Dropped })
	local inv = Inventory.new(registry, { capacity = options.capacity, hotbarSize = options.hotbarSize }) :: Internal
	local dropped: { Dropped } = {}
	if type(saved) ~= "table" or type(saved.slots) ~= "table" then
		inv._onChanged = options.onChanged
		return inv, dropped
	end
	local homeless: { Stack } = {}
	for _, entry in saved.slots do
		if type(entry) ~= "table" or type(entry.id) ~= "string" or type(entry.count) ~= "number" then
			continue
		end
		local def = registry.get(entry.id)
		local count = math.floor(entry.count)
		if def == nil then
			table.insert(dropped, { id = entry.id, count = count, why = "Unknown" })
			continue
		end
		if count < 1 or count ~= count then
			continue
		end
		if count > def.maxStack then
			table.insert(dropped, { id = entry.id, count = count - def.maxStack, why = "OverStack" })
			count = def.maxStack
		end
		local slot = entry.slot
		if validSlot(inv, slot) and inv._slots[slot] == nil then
			inv._slots[slot] = { id = entry.id, count = count }
		else
			table.insert(homeless, { id = entry.id, count = count })
		end
	end
	for _, stack in homeless do
		local placed = false
		for slot = 1, inv.capacity do
			if inv._slots[slot] == nil then
				inv._slots[slot] = stack
				placed = true
				break
			end
		end
		if not placed then
			table.insert(dropped, { id = stack.id, count = stack.count, why = "Full" })
		end
	end
	local equipped = saved.equipped
	if validSlot(inv, equipped) and inv._slots[equipped] ~= nil then
		inv._equipped = equipped
	end
	inv._onChanged = options.onChanged
	return inv, dropped
end

return Inventory
