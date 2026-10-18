--!strict
--[[
	ItemRegistry: the catalog of item definitions a game supplies to Inventory and the hotbar.

	A definition is plain data. Only `id` and `name` are required:
	  id        unique string key (what saves and remotes carry)
	  name      display name
	  maxStack  how many fit in one slot (default 1: not stackable)
	  kind      free-form category the game uses ("tool", "consumable", ...)
	  icon      image asset ("rbxassetid://...") or nil; the default UI falls back to the name's initial
	  color     { r, g, b } 0-255 tile tint for the default UI, optional
	  data      any game-specific payload, untouched by the library
	Definitions are validated and frozen once, at `new`.
]]

export type ItemDef = {
	id: string,
	name: string,
	maxStack: number,
	kind: string?,
	icon: string?,
	color: { number }?,
	data: any?,
}

export type Registry = {
	order: { string },
	get: (id: string) -> ItemDef?,
	has: (id: string) -> boolean,
}

local ItemRegistry = {}

function ItemRegistry.new(defs: { any }): Registry
	assert(type(defs) == "table", "ItemRegistry.new: expected a list of item definitions")
	local byId: { [string]: ItemDef } = {}
	local order: { string } = {}
	for index, raw in defs do
		assert(type(raw) == "table", `ItemRegistry.new: definition {index} is not a table`)
		local id = raw.id
		assert(type(id) == "string" and id ~= "", `ItemRegistry.new: definition {index} has no string id`)
		assert(byId[id] == nil, `ItemRegistry.new: duplicate item id "{id}"`)
		assert(type(raw.name) == "string", `ItemRegistry.new: item "{id}" has no name`)
		local maxStack = if raw.maxStack == nil then 1 else raw.maxStack
		assert(
			type(maxStack) == "number" and maxStack >= 1 and maxStack == math.floor(maxStack),
			`ItemRegistry.new: item "{id}" maxStack must be a whole number >= 1`
		)
		byId[id] = table.freeze({
			id = id,
			name = raw.name,
			maxStack = maxStack,
			kind = raw.kind,
			icon = raw.icon,
			color = if raw.color then table.freeze(table.clone(raw.color)) else nil,
			data = raw.data,
		})
		table.insert(order, id)
	end
	table.freeze(order)

	return table.freeze({
		order = order,
		get = function(id: string): ItemDef?
			return byId[id]
		end,
		has = function(id: string): boolean
			return byId[id] ~= nil
		end,
	})
end

return table.freeze(ItemRegistry)
