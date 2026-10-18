--!strict
--[[
	Hotbar: the client's view model for the hotbar and the inventory grid. Pure: it turns the server's
	Inventory snapshot (plus any extra entries the game adds) into a list of entries to draw, and turns a
	player's press into an intent. It keeps no state and decides nothing; the server validates every intent.

	Extra entries are for things a game shows in the bar that are not Inventory items, such as Roblox Tools
	the server put in the Backpack. They come after the inventory's hotbar slots and are selected through
	their own `onSelect` intent kind ("Extra").
]]

local ItemRegistry = if script then require(script.Parent.ItemRegistry) else require("./ItemRegistry")
local Inventory = if script then require(script.Parent.Inventory) else require("./Inventory")

type Registry = ItemRegistry.Registry
type Snapshot = Inventory.Snapshot

export type Entry = {
	key: string, -- unique and stable: "slot:<n>" or "extra:<key>"
	slot: number?, -- inventory slot, nil for an extra entry
	itemId: string,
	name: string,
	icon: string?,
	color: { number }?,
	count: number?, -- shown only for stacks above 1
	equipped: boolean,
	cooldownUntil: number?,
}

export type Extra = {
	key: string,
	itemId: string,
	name: string,
	icon: string?,
	color: { number }?,
	count: number?,
	equipped: boolean,
	cooldownUntil: number?,
}

export type Intent =
	{ kind: "Equip", slot: number }
	| { kind: "Unequip" }
	| { kind: "Extra", key: string, equip: boolean }

local Hotbar = {}

Hotbar.MAX_KEYS = 9

local function entryFor(slot: number, stack: Inventory.Stack, registry: Registry, equipped: boolean): Entry
	local def = registry.get(stack.id)
	return {
		key = `slot:{slot}`,
		slot = slot,
		itemId = stack.id,
		name = if def then def.name else stack.id,
		icon = if def then def.icon else nil,
		color = if def then def.color else nil,
		count = if stack.count > 1 then stack.count else nil,
		equipped = equipped,
	}
end

-- Hotbar entries: filled hotbar slots in slot order, then the extras in the order given.
function Hotbar.entries(snapshot: Snapshot?, registry: Registry, extras: { Extra }?): { Entry }
	local out: { Entry } = {}
	if snapshot then
		for slot = 1, snapshot.hotbarSize do
			local stack = snapshot.slots[slot]
			if stack then
				table.insert(out, entryFor(slot, stack, registry, snapshot.equipped == slot))
			end
		end
	end
	local extraList: { Extra } = extras or {}
	for _, extra in extraList do
		table.insert(out, {
			key = `extra:{extra.key}`,
			itemId = extra.itemId,
			name = extra.name,
			icon = extra.icon,
			color = extra.color,
			count = if extra.count and extra.count > 1 then extra.count else nil,
			equipped = extra.equipped,
			cooldownUntil = extra.cooldownUntil,
		})
	end
	return out
end

-- Grid entries: every filled slot of the whole inventory, in slot order (the bag panel).
function Hotbar.gridEntries(snapshot: Snapshot?, registry: Registry): { Entry }
	local out: { Entry } = {}
	if snapshot then
		for slot = 1, snapshot.capacity do
			local stack = snapshot.slots[slot]
			if stack then
				table.insert(out, entryFor(slot, stack, registry, snapshot.equipped == slot))
			end
		end
	end
	return out
end

-- Pressing an entry toggles it: equip it, or put it away when it is already in hand.
function Hotbar.select(entry: Entry): Intent
	if entry.slot == nil then
		return { kind = "Extra", key = string.sub(entry.key, 7), equip = not entry.equipped }
	end
	if entry.equipped then
		return { kind = "Unequip" }
	end
	return { kind = "Equip", slot = entry.slot }
end

-- The entry on number key `n` (1-9), counting only the entries the bar shows.
function Hotbar.byKey(entries: { Entry }, shown: number, n: number): Entry?
	if n < 1 or n > math.min(shown, Hotbar.MAX_KEYS) then
		return nil
	end
	return entries[n]
end

-- "3", "99+", or nil for no stack.
function Hotbar.countText(n: number?): string?
	if n == nil or n < 2 then
		return nil
	end
	return if n > 99 then "99+" else tostring(math.floor(n))
end

-- Whole seconds of cooldown left, rounded up; nil when ready.
function Hotbar.cooldownText(entry: Entry, now: number): string?
	local untilTime = entry.cooldownUntil
	if untilTime == nil or untilTime <= now then
		return nil
	end
	return tostring(math.ceil(untilTime - now))
end

-- One comparable string per entry list, so a view rebuilds only when something it draws changed.
function Hotbar.signature(entries: { Entry }): string
	local parts = table.create(#entries)
	for _, e in entries do
		table.insert(parts, `{e.key}={e.itemId}:{if e.equipped then 1 else 0}:{e.count or 1}:{e.cooldownUntil or 0}`)
	end
	return table.concat(parts, "|")
end

return table.freeze(Hotbar)
