--!strict
--[[
	InventoryCore (S3, pure)

	What the hotbar and the inventory panel list, from data the client already has; it keeps NO state of its
	own and the server stays the only owner of what is owned (CONTRACT.md "Inventory hotbar"):
	  * the Bat first (the Tool every player is given, BatTool), then any other Tool in the Backpack / character
	    (the Speed Coil today), in name order. A Tool is the server's own holdable, so the list follows whatever
	    the server puts there;
	  * every owned PvP item (State.pvp.owned) in Config.PVP_TOOLS catalog order, equipped = State.pvp.equipped;
	  * `counts` (item id -> stack size) is shown when the server ever supplies one; nothing does today
	    (consumables apply on purchase, no held stock), so stacks stay nil.
	Permanent upgrades and shop-only effects (Lock, Longer locks, ...) are never listed.
	Equip / use go through the existing actions only: a Tool through the Humanoid, a PvP item through
	Request("EquipPvpItem", id?) (the server enforces rank, one equipped item and everything else).
]]

local ItemIcons = if script then require(script.Parent.ItemIcons) else require("./ItemIcons")

export type ToolInfo = { name: string, equipped: boolean }
export type Entry = {
	key: string, -- unique: "tool:<Tool name>" | "pvp:<item id>"
	kind: string, -- "tool" | "pvp"
	itemId: string, -- Tool name or PVP_TOOLS id
	iconId: string, -- ItemIcons id
	name: string,
	equipped: boolean,
	count: number?,
	readyAt: number?, -- pvp cooldown end (server time), nil when ready or unknown
}
export type Action =
	{ kind: "Tool", toolName: string, equip: boolean }
	| {
		kind: "Request",
		action: string,
		arg: string?,
	}
export type Input = {
	tools: { ToolInfo }, -- Tools in the Backpack and the character, any order
	pvp: any?, -- State.pvp (Types.PvpView)
	config: any, -- shared Config (PVP_TOOLS)
	registry: any, -- ItemIcons registry (get)
	counts: { [string]: number }?,
	now: number?, -- server time, for cooldowns
}

local InventoryCore = {}

-- The ItemIcons registry plus a row for each held Tool picture (ItemIcons.HELD_TOOLS: the Bat) the registry
-- itself does not list. Drawn like any other item by ItemIconView (an uploaded image over a coloured tile).
function InventoryCore.withTools(base: any): any
	local extra: { [string]: any } = {}
	for toolName: string, iconId: string in ItemIcons.HELD_TOOLS :: { [string]: string } do
		if base.get(iconId) == nil then
			local image = ItemIcons.IMAGES[iconId]
			extra[iconId] = table.freeze({
				id = iconId,
				name = toolName,
				group = "gear",
				color = { 170, 120, 70 },
				glyph = "🏏",
				image = image,
				source = if image then "image" else "placeholder",
				brief = `{toolName}: the default melee Tool every player holds.`,
			})
		end
	end
	local function get(id: string): any
		return base.get(id) or extra[id]
	end
	return {
		byId = base.byId,
		order = base.order,
		get = get,
		resolve = function(id: any): any
			local spec = if type(id) == "string" then get(id) else nil
			return spec or ItemIcons.UNKNOWN
		end,
	}
end

InventoryCore.BAT = "Bat"
InventoryCore.PVP_ACTION = "EquipPvpItem"

local function toolIcon(name: string, input: Input): string
	local held = ItemIcons.HELD_TOOLS[name]
	if held then
		return held
	end
	return if input.registry.get(name) then name else "Unknown"
end

local function count(input: Input, id: string): number?
	local n = if input.counts then input.counts[id] else nil
	return if type(n) == "number" and n >= 1 then math.floor(n) else nil
end

function InventoryCore.entries(input: Input): { Entry }
	local out: { Entry } = {}
	local byName: { [string]: ToolInfo } = {}
	for _, tool in input.tools do
		-- a Tool in both places (never expected) counts as equipped if either copy is
		local seen = byName[tool.name]
		if seen then
			seen.equipped = seen.equipped or tool.equipped
		else
			byName[tool.name] = { name = tool.name, equipped = tool.equipped }
		end
	end
	local names: { string } = {}
	for name in byName do
		if name ~= InventoryCore.BAT then
			table.insert(names, name)
		end
	end
	table.sort(names)
	table.insert(names, 1, InventoryCore.BAT)
	for _, name in names do
		local info = byName[name]
		local icon = toolIcon(name, input)
		local spec = input.registry.get(icon)
		table.insert(out, {
			key = `tool:{name}`,
			kind = "tool",
			itemId = name,
			iconId = icon,
			name = if spec then spec.name else name,
			equipped = info ~= nil and info.equipped,
			count = count(input, name),
		})
	end

	local pvp = input.pvp
	if type(pvp) == "table" and type(pvp.owned) == "table" then
		for _, def in input.config.PVP_TOOLS do
			if pvp.owned[def.id] == true then
				local readyAt = if type(pvp.cooldowns) == "table" then pvp.cooldowns[def.id] else nil
				table.insert(out, {
					key = `pvp:{def.id}`,
					kind = "pvp",
					itemId = def.id,
					iconId = ItemIcons.shopIconId({ id = def.id, action = "BuyPvpItem" }),
					name = def.name,
					equipped = pvp.equipped == def.id,
					count = count(input, def.id),
					readyAt = if type(readyAt) == "number" and input.now and readyAt > input.now then readyAt else nil,
				})
			end
		end
	end
	return out
end

-- What selecting `entry` does: toggles it (equip, or put away when it is already in hand).
function InventoryCore.select(entry: Entry): Action
	if entry.kind == "pvp" then
		return {
			kind = "Request",
			action = InventoryCore.PVP_ACTION,
			arg = if entry.equipped then nil else entry.itemId,
		}
	end
	return { kind = "Tool", toolName = entry.itemId, equip = not entry.equipped }
end

-- The entry on number key `n` (1-9) given the entries the hotbar shows, or nil.
function InventoryCore.byKey(entries: { Entry }, shown: number, n: number): Entry?
	if n < 1 or n > shown then
		return nil
	end
	return entries[n]
end

-- "x3" under 100, "99+" above; nil for no stack.
function InventoryCore.countText(n: number?): string?
	if n == nil or n < 1 then
		return nil
	end
	return if n > 99 then "99+" else tostring(math.floor(n))
end

-- Seconds of cooldown left, whole and rounded up; nil when ready.
function InventoryCore.cooldownText(entry: Entry, now: number): string?
	if entry.readyAt == nil or entry.readyAt <= now then
		return nil
	end
	return tostring(math.ceil(entry.readyAt - now))
end

-- Entries and the Tool/pvp state in one comparable string, so the UI rebuilds only on a change.
function InventoryCore.signature(entries: { Entry }): string
	local parts = {}
	for _, e in entries do
		table.insert(parts, `{e.key}:{if e.equipped then 1 else 0}:{e.count or 0}:{e.readyAt or 0}`)
	end
	return table.concat(parts, "|")
end

return table.freeze(InventoryCore)
