--!strict
--[[
	InventoryCore (S3, pure)

	What the hotbar and the inventory panel list, from data the client already has; it keeps NO state of its
	own and the server stays the only owner of what is owned (CONTRACT.md "Inventory hotbar"):
	  * the Bat first (the Tool every player is given, BatTool), then any other Tool in the Backpack / character
	    (the Speed Coil today), in name order. A Tool is the server's own holdable, so the list follows whatever
	    the server puts there;
	  * every owned PvP item (State.pvp.owned) in Config.PVP_TOOLS catalog order, equipped = State.pvp.equipped; a Goo
	    Trap shows its charges (State.pvp.charges) as the stack count;
	  * every consumable with a stack (State.consumables.held), in Config.CONSUMABLES order, with the stack as
	    its count. "In hand" is the one thing kept client-side (`heldConsumable`, the id the player picked): the
	    server has no hand slot for a consumable, it only validates the use;
	  * `counts` (item id -> stack size) for the other kinds, if the server ever supplies one.
	Permanent upgrades and shop-only effects (Lock, Longer locks, ...) are never listed.
	Equip / use go through the existing actions only: a Tool through the Humanoid, a PvP item through
	Request("EquipPvpItem", id?) (the server enforces rank, one equipped item and everything else), a consumable
	in hand through Request("UseConsumable", id, slimeId?) (the server checks ownership and stock), the equipped
	PvP item through Request("UsePvpItem", id, targetUserId?, aim?) built by `pvpUseRequest` from the click.
	Which item sits on which hotbar slot is the player's saved order (State.hotbar, set by Request("SetHotbar")):
	`hotbarSlots`, `applyDrop`, `placeNew` and `orderString` below.
]]

local ItemIcons = if script then require(script.Parent.ItemIcons) else require("./ItemIcons")
local Shared = if script then game:GetService("ReplicatedStorage"):WaitForChild("Shared") :: any else nil
local HotbarOrder = if Shared then require(Shared:WaitForChild("HotbarOrder")) else require("../shared/HotbarOrder")

export type ToolInfo = { name: string, equipped: boolean }
export type Entry = {
	key: string, -- unique: "tool:<Tool name>" | "pvp:<item id>" | "consumable:<item id>"
	kind: string, -- "tool" | "pvp" | "consumable"
	itemId: string, -- Tool name, PVP_TOOLS id or CONSUMABLES id
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
	| { kind: "Consumable", itemId: string, equip: boolean }
export type Input = {
	tools: { ToolInfo }, -- Tools in the Backpack and the character, any order
	pvp: any?, -- State.pvp (Types.PvpView)
	config: any, -- shared Config (PVP_TOOLS)
	registry: any, -- ItemIcons registry (get)
	counts: { [string]: number }?,
	held: { [string]: number }?, -- State.consumables.held: consumable id -> stack
	heldConsumable: string?, -- the consumable the player has in hand (client-side pick)
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
InventoryCore.USE_ACTION = "UseConsumable"

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

-- A Goo Trap's charges (State.pvp.charges), else the generic count.
local function pvpCount(input: Input, pvp: any, id: string): number?
	local n = if type(pvp.charges) == "table" then pvp.charges[id] else nil
	if type(n) == "number" and n >= 1 then
		return math.floor(n)
	end
	return count(input, id)
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
					count = pvpCount(input, pvp, def.id),
					readyAt = if type(readyAt) == "number" and input.now and readyAt > input.now then readyAt else nil,
				})
			end
		end
	end

	local held = input.held
	if type(held) == "table" and type(input.config.CONSUMABLES) == "table" then
		for _, def in input.config.CONSUMABLES do
			local n = held[def.id]
			if type(n) == "number" and n >= 1 then
				table.insert(out, {
					key = `consumable:{def.id}`,
					kind = "consumable",
					itemId = def.id,
					iconId = ItemIcons.shopIconId({ id = def.id, action = "BuyConsumable" }),
					name = def.name,
					equipped = input.heldConsumable == def.id,
					count = math.floor(n),
				})
			end
		end
	end
	return out
end

-- What selecting `entry` does: toggles it (equip, or put away when it is already in hand).
function InventoryCore.select(entry: Entry): Action
	if entry.kind == "consumable" then
		return { kind = "Consumable", itemId = entry.itemId, equip = not entry.equipped }
	end
	if entry.kind == "pvp" then
		return {
			kind = "Request",
			action = InventoryCore.PVP_ACTION,
			arg = if entry.equipped then nil else entry.itemId,
		}
	end
	return { kind = "Tool", toolName = entry.itemId, equip = not entry.equipped }
end

-- The Request that uses the consumable `entry` in hand: (action, itemId, slimeId?), or nil when it cannot be
-- used yet (not a consumable or not in hand). The server re-checks everything.
function InventoryCore.useRequest(entry: Entry): { string }?
	if entry.kind ~= "consumable" or not entry.equipped then
		return nil
	end
	return { InventoryCore.USE_ACTION, entry.itemId }
end

export type Vec = { X: number, Y: number, Z: number }
export type Other = { userId: number, position: Vec, carrying: boolean? } -- another player's root
-- What the click / tap on the world pointed at (ui/PvpAim samples it): all optional, the server re-checks it all.
export type Aim = {
	self: Vec?, -- the local player's root
	point: Vec?, -- the world point under the click (nil = sky / nothing hit)
	far: Vec?, -- a point far along the click ray (aimed shots into the sky)
	hovered: number?, -- userId of the player under the click
	players: { Other }, -- every other player with a character
}
export type PvpUse = { action: string, itemId: string, target: number?, aim: Vec?, charged: boolean? }

InventoryCore.PVP_USE_ACTION = "UsePvpItem"

--[[
	How a PvP item picks the UsePvpItem arguments (server/PvpKnockback, PvpTrap, PvpBlaster, PvpFun):
	  target  a player in reach (the one clicked, else the nearest, thieves first); none = not sent
	  shot    the clicked player, else the clicked point, else far along the ray (Goo Blaster hitscan, and every
	          Fun item: the server pulls a far aim in to the item's range, CONTRACT.md §26.8)
	  point   the clicked world point (Goo Trap); none = not sent
]]
InventoryCore.PVP_AIM = table.freeze({
	Knockback = "target",
	Trap = "point",
	Blaster = "shot",
	Fun = "shot",
})
function InventoryCore.pvpAimMode(tool: any): string
	return InventoryCore.PVP_AIM[tool.id] or InventoryCore.PVP_AIM[tool.line] or "self"
end

-- Items used on release so a hold means something: gloves (hold = power punch), the Goo Cannon (hold to aim the
-- lob) and the Fun items that charge (Confetti Popper: mega pop, Goo Fireworks: volley).
InventoryCore.PVP_HOLD = table.freeze({ Knockback = true, GooBlaster3 = true, FunConfetti = true, FunFireworks = true })

function InventoryCore.pvpHolds(tool: any): boolean
	return tool ~= nil and (InventoryCore.PVP_HOLD[tool.id] == true or InventoryCore.PVP_HOLD[tool.line] == true)
end

-- Items whose hold means more (UsePvpItem `charged`): a glove's power punch, the Confetti Popper's mega pop, the
-- Goo Fireworks volley.
InventoryCore.PVP_CHARGE = table.freeze({ Knockback = true, FunConfetti = true, FunFireworks = true })

-- A press held `seconds` (Config.PVP.CHARGE_SECONDS or longer) on a charging item sends `charged = true`.
function InventoryCore.pvpCharged(tool: any, seconds: number?, config: any): boolean
	return tool ~= nil
		and (InventoryCore.PVP_CHARGE[tool.id] == true or InventoryCore.PVP_CHARGE[tool.line] == true)
		and type(seconds) == "number"
		and seconds >= config.PVP.CHARGE_SECONDS
end

local function distance(a: Vec, b: Vec): number
	local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- The player to target: the hovered one when in reach, else the nearest in reach, thieves (carrying) first.
local function pickTarget(aim: Aim, reach: number): Other?
	local me = aim.self
	if not me then
		return nil
	end
	local best: Other? = nil
	local bestScore = math.huge
	for _, other in aim.players do
		local d = distance(me, other.position)
		if d == d and d <= reach then
			if other.userId == aim.hovered then
				return other
			end
			local score = d - (if other.carrying then reach * 2 else 0) -- any thief beats any non-thief
			if score < bestScore then
				best, bestScore = other, score
			end
		end
	end
	return best
end

local function positionOf(aim: Aim, userId: number?): Vec?
	for _, other in aim.players do
		if other.userId == userId then
			return other.position
		end
	end
	return nil
end

-- The equipped PvP `entry` is off cooldown at `now` (server time): a click on it plays its use animation.
function InventoryCore.pvpReady(entry: Entry, now: number): boolean
	return entry.kind == "pvp" and entry.equipped == true and not (entry.readyAt and entry.readyAt > now)
end

--[[
	The UsePvpItem request for the equipped PvP `entry` (tool = its Config.PVP_TOOLS row) from what the click
	pointed at, or (nil, player-facing reason) when there is nothing to send: not equipped, still cooling down,
	nobody in reach, no point to aim at. Intent only: the server re-checks reach, zones, shields and cooldowns.
]]
function InventoryCore.pvpUseRequest(
	entry: Entry,
	tool: any,
	aim: Aim,
	config: any,
	now: number,
	held: number?
): (PvpUse?, string?)
	if entry.kind ~= "pvp" or not entry.equipped or tool == nil or tool.id ~= entry.itemId then
		return nil, nil
	end
	if entry.readyAt and entry.readyAt > now then
		return nil, `Ready in {math.ceil(entry.readyAt - now)}s`
	end
	local use: PvpUse = {
		action = InventoryCore.PVP_USE_ACTION,
		itemId = entry.itemId,
		target = nil,
		aim = nil,
		charged = if InventoryCore.pvpCharged(tool, held, config) then true else nil,
	}
	local mode = InventoryCore.pvpAimMode(tool)
	local reach = tool.reach or config.SLAP_REACH
	if mode == "target" then
		local other = pickTarget(aim, reach)
		if not other then
			return nil, if aim.self then "No one in reach" else "Can't find you"
		end
		use.target = other.userId
	elseif mode == "shot" then
		use.aim = positionOf(aim, aim.hovered) or aim.point or aim.far
		if use.aim == nil then
			return nil, "Aim somewhere"
		end
	elseif mode == "point" then
		use.aim = aim.point
		if use.aim == nil then
			return nil, "Aim at the ground"
		end
	end
	return use, nil
end

-- A server refusal ("too far away") as hotbar tip text ("Too far away").
function InventoryCore.reasonText(message: any): string
	local text = if type(message) == "string" and message ~= "" then message else "Can't use that here"
	return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

-- The entry on number key `n` (1-9) given the hotbar slots (InventoryCore.hotbarSlots, nil = empty slot) and how
-- many of them the bar shows, or nil.
function InventoryCore.byKey(slots: { Entry? }, shown: number, n: number): Entry?
	if n < 1 or n > shown then
		return nil
	end
	return slots[n]
end

--[[
	The player-arranged hotbar (CONTRACT.md `SetHotbar`, `State.hotbar`). The order is a list of exactly `max` slot
	keys (Entry.key, "" = empty slot), slot 1 first; the bar and number key i show slot i. With no saved order the
	slots are the first `max` entries in list order. A saved key the player does not own right now (a used-up
	potion) keeps its slot and shows empty there, so the item comes back to that slot when it is owned again,
	unless a new item needs a slot and none is truly empty: then the first such reserved slot goes to the new
	item (`placeNew`).
]]
InventoryCore.HOTBAR_ACTION = "SetHotbar"

export type DragFrom = { kind: "bar", index: number } | { kind: "bag", key: string }
export type DragTo = { kind: "bar", index: number } | { kind: "bag" }

-- A saved order (State.hotbar, untrusted) as exactly `max` keys, "" for empty; a repeated key keeps its first slot.
-- nil when there is no saved order.
function InventoryCore.savedKeys(saved: any, max: number): { string }?
	if type(saved) ~= "table" then
		return nil
	end
	local out: { string } = table.create(max, "")
	local seen: { [string]: boolean } = {}
	for i = 1, max do
		local key = saved[i]
		if type(key) == "string" and key ~= "" and not seen[key] then
			seen[key] = true
			out[i] = key
		end
	end
	return out
end

-- The `max` slot keys: the saved order, or (none saved) the keys of the first `max` entries.
function InventoryCore.slotKeys(entries: { Entry }, saved: { string }?, max: number): { string }
	local keys = InventoryCore.savedKeys(saved, max)
	if keys then
		return keys
	end
	local out: { string } = table.create(max, "")
	for i = 1, math.min(max, #entries) do
		out[i] = entries[i].key
	end
	return out
end

-- The `max` hotbar slots: each the owned entry whose key the slot holds, or nil (empty, or not owned now).
-- The list has holes: index it 1..max, never with # or ipairs.
function InventoryCore.hotbarSlots(entries: { Entry }, saved: { string }?, max: number): { Entry? }
	local byKey: { [string]: Entry } = {}
	for _, entry in entries do
		byKey[entry.key] = entry
	end
	local slots: { Entry? } = {}
	for i, key in InventoryCore.slotKeys(entries, saved, max) do
		slots[i] = if key ~= "" then byKey[key] else nil
	end
	return slots
end

-- The highest filled slot of `slots` (1..max), 0 when every slot is empty.
function InventoryCore.lastFilled(slots: { Entry? }, max: number): number
	for i = max, 1, -1 do
		if slots[i] ~= nil then
			return i
		end
	end
	return 0
end

-- The slot (1..n) holding `key`, or nil.
function InventoryCore.slotOf(keys: { string }, key: string): number?
	if key == "" then
		return nil
	end
	return table.find(keys, key)
end

--[[
	The order after a drag from `from` to `to` (a new list; `keys` is not changed):
	  bag -> bar slot  the item goes there (the slot's old item goes back to the bag); an item already on the bar
	                   moves like a bar -> bar drag, so it is never on two slots
	  bar -> bar slot  the two slots swap (an empty target just takes the item)
	  bar -> bag       the slot empties
	  same slot, bag -> bag: no change
]]
function InventoryCore.applyDrop(keys: { string }, from: DragFrom, to: DragTo): { string }
	local out = table.clone(keys)
	local fromIndex: number? = nil
	local key = ""
	if from.kind == "bar" then
		fromIndex = from.index
		key = out[from.index] or ""
	else
		key = from.key
		fromIndex = InventoryCore.slotOf(out, key)
	end
	if to.kind == "bag" then
		if fromIndex then
			out[fromIndex] = ""
		end
		return out
	end
	local target = to.index
	if target < 1 or target > #out or key == "" or fromIndex == target then
		return out
	end
	if fromIndex then
		out[fromIndex] = out[target]
	end
	out[target] = key
	return out
end

-- `keys` with every key the server would refuse (HotbarOrder.isKey: an odd Tool name) as an empty slot, so one
-- bad key never sinks the whole order, and whether any key was blanked.
function InventoryCore.cleanOrder(keys: { string }): ({ string }, boolean)
	local out = table.clone(keys)
	local blanked = false
	for i, key in out do
		if key ~= "" and not HotbarOrder.isKey(key) then
			out[i] = ""
			blanked = true
		end
	end
	return out, blanked
end

-- The SetHotbar argument: the keys joined by "," (slot 1 first, "" = empty slot).
function InventoryCore.orderString(keys: { string }): string
	return table.concat(keys, ",")
end

-- `keys` with each of `newKeys` that is on no slot yet (and that the server would take: HotbarOrder.isKey) put
-- on the first empty slot, else on the first slot reserved for a key not in `owned` (an item the player no longer
-- holds), in order while there is room. A key placed here counts as owned. Without `owned` only empty slots are
-- used. Returns the new list and whether anything moved.
function InventoryCore.placeNew(
	keys: { string },
	newKeys: { string },
	owned: { [string]: boolean }?
): ({ string }, boolean)
	local out = table.clone(keys)
	local changed = false
	for _, key in newKeys do
		if key ~= "" and HotbarOrder.isKey(key) and not table.find(out, key) then
			local free = table.find(out, "")
			if free == nil and owned then
				for i, held in out do
					if not owned[held] and not table.find(newKeys, held) then
						free = i
						break
					end
				end
			end
			if free == nil then
				break
			end
			out[free] = key
			changed = true
		end
	end
	return out, changed
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
