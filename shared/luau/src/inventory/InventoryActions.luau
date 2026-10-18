--!strict
--[[
	InventoryActions: the client requests a game lets players make on their own inventory, validated and applied
	on the server. A game plugs `handle` into its own Request remote; arguments arrive untrusted from the client.

	  Equip    (slot: number?)                  put a slot in hand; nil puts it away
	  Move     (from: number, to: number)       move / merge / swap stacks
	  Split    (from: number, to: number, n)    move part of a stack
	  Drop     (slot: number, n: number?)       only when the game allows it (options.allowDrop)

	Using an item is game logic (what does a potion do?), so it is not here: the game validates its own "Use"
	action, then calls `inv:consumeEquipped()` or `inv:removeAt()`.
	Returns (ok, reason). Reasons are Inventory's plus "UnknownAction" and "BadArgs".
]]

local Inventory = if script then require(script.Parent.Inventory) else require("./Inventory")

type Inventory = Inventory.Inventory

export type Options = { allowDrop: boolean? }

local InventoryActions = {}

InventoryActions.NAMES = table.freeze({ "Equip", "Move", "Split", "Drop" })

local function int(v: any): number?
	if type(v) ~= "number" or v ~= v or v ~= math.floor(v) or math.abs(v) == math.huge then
		return nil
	end
	return v
end

function InventoryActions.handle(inv: Inventory, action: any, args: { any }, options: Options?): (boolean, string?)
	if action == "Equip" then
		local slot = args[1]
		if slot == nil then
			return inv:equip(nil)
		end
		local s = int(slot)
		if s == nil then
			return false, "BadArgs"
		end
		return inv:equip(s)
	elseif action == "Move" then
		local from, to = int(args[1]), int(args[2])
		if from == nil or to == nil then
			return false, "BadArgs"
		end
		return inv:move(from, to)
	elseif action == "Split" then
		local from, to, n = int(args[1]), int(args[2]), int(args[3])
		if from == nil or to == nil or n == nil then
			return false, "BadArgs"
		end
		return inv:split(from, to, n)
	elseif action == "Drop" then
		if not (options and options.allowDrop) then
			return false, "UnknownAction"
		end
		local slot = int(args[1])
		local n = if args[2] == nil then 1 else int(args[2])
		if slot == nil or n == nil then
			return false, "BadArgs"
		end
		return inv:removeAt(slot, n)
	end
	return false, "UnknownAction"
end

return table.freeze(InventoryActions)
