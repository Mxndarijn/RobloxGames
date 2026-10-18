--!strict
--[[
	InventoryCore (S3, pure)

	What the hotbar and the inventory panel list, from data the client already has; it keeps NO state of its
	own and the server stays the only owner of what is owned (CONTRACT.md "Inventory hotbar"):
	  * the Bat first (the Tool every player is given, BatTool), then any other Tool in the Backpack / character
	    (the Speed Coil today), in name order. A Tool is the server's own holdable, so the list follows whatever
	    the server puts there;
	  * every owned PvP item (State.pvp.owned) in Config.PVP_TOOLS catalog order, equipped = State.pvp.equipped;
	  * every consumable with a stack (State.consumables.held), in Config.CONSUMABLES order, with the stack as
	    its count. "In hand" is the one thing kept client-side (`heldConsumable`, the id the player picked): the
	    server has no hand slot for a consumable, it only validates the use;
	  * `counts` (item id -> stack size) for the other kinds, if the server ever supplies one.
	Permanent upgrades and shop-only effects (Lock, Longer locks, ...) are never listed.
	Equip / use go through the existing actions only: a Tool through the Humanoid, a PvP item through
	Request("EquipPvpItem", id?) (the server enforces rank, one equipped item and everything else), a consumable
	in hand through Request("UseConsumable", id, slimeId?) (the server checks ownership and stock), the equipped
	PvP item through Request("UsePvpItem", id, targetUserId?, aim?) built by `pvpUseRequest` from the click.
]]

local ItemIcons = if script then require(script.Parent.ItemIcons) else require("./ItemIcons")
local ShopCatalog = if script then require(script.Parent.ShopCatalog) else require("./ShopCatalog")

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
-- used yet (not a consumable, not in hand, or a Mutation Spray with no slime to put it on). The server
-- re-checks everything; the slime is the spray's usual target (the favourite, else the highest tier).
function InventoryCore.useRequest(entry: Entry, state: any): { string }?
	if entry.kind ~= "consumable" or not entry.equipped then
		return nil
	end
	if entry.itemId == "MutationSpray" then
		local target = ShopCatalog.sprayTarget(if type(state) == "table" then state else {})
		if target == nil then
			return nil
		end
		return { InventoryCore.USE_ACTION, entry.itemId, target }
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
export type PvpUse = { action: string, itemId: string, target: number?, aim: Vec? }

InventoryCore.PVP_USE_ACTION = "UsePvpItem"

--[[
	How a PvP item picks the UsePvpItem arguments (server/PvpKnockback, PvpTrap, PvpBlaster, PvpFun):
	  target         a player in reach (the one clicked, else the nearest, thieves first); none = not sent
	  targetOptional the clicked or nearest thief in reach, else no target (Squeaky Hammer: a squeak on its own)
	  hovered        only the clicked player in reach, else yourself (Hat Launcher: friends, checked by the server)
	  shot           the clicked player, else the clicked point, else far along the ray (Goo Blaster hitscan)
	  point          the clicked world point (Goo Trap, Goo Balloon); none = not sent
	  pointOptional  the clicked point when within FUN_AIM_RANGE, else your own spot (Bounce Pad, Fireworks)
	  self           no arguments (Confetti Popper, Bubble Wand)
]]
InventoryCore.PVP_AIM = table.freeze({
	Knockback = "target",
	Trap = "point",
	Blaster = "shot",
	FunConfetti = "self",
	FunBubbles = "self",
	FunBalloon = "point",
	FunBouncePad = "pointOptional",
	FunFireworks = "pointOptional",
	FunSqueaky = "targetOptional",
	FunHatLauncher = "hovered",
	FunDanceBomb = "target",
})

function InventoryCore.pvpAimMode(tool: any): string
	return InventoryCore.PVP_AIM[tool.id] or InventoryCore.PVP_AIM[tool.line] or "self"
end

local function distance(a: Vec, b: Vec): number
	local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- The player to target: the hovered one when in reach, else (unless onlyHovered) the nearest in reach, thieves
-- (carrying) before anyone else; `thievesOnly` skips non-carrying players in the nearest pick.
local function pickTarget(aim: Aim, reach: number, onlyHovered: boolean, thievesOnly: boolean): Other?
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
			if not onlyHovered and (other.carrying or not thievesOnly) then
				local score = d - (if other.carrying then reach * 2 else 0) -- any thief beats any non-thief
				if score < bestScore then
					best, bestScore = other, score
				end
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

--[[
	The UsePvpItem request for the equipped PvP `entry` (tool = its Config.PVP_TOOLS row) from what the click
	pointed at, or (nil, player-facing reason) when there is nothing to send: not equipped, still cooling down,
	nobody in reach, no point to aim at. Intent only: the server re-checks reach, zones, shields and cooldowns.
]]
function InventoryCore.pvpUseRequest(entry: Entry, tool: any, aim: Aim, config: any, now: number): (PvpUse?, string?)
	if entry.kind ~= "pvp" or not entry.equipped or tool == nil or tool.id ~= entry.itemId then
		return nil, nil
	end
	if entry.readyAt and entry.readyAt > now then
		return nil, `Ready in {math.ceil(entry.readyAt - now)}s`
	end
	local use: PvpUse = { action = InventoryCore.PVP_USE_ACTION, itemId = entry.itemId, target = nil, aim = nil }
	local mode = InventoryCore.pvpAimMode(tool)
	local reach = tool.reach or config.SLAP_REACH
	if mode == "target" or mode == "targetOptional" or mode == "hovered" then
		local other = pickTarget(aim, reach, mode == "hovered", mode == "targetOptional")
		if other then
			use.target = other.userId
		elseif mode == "target" then
			return nil, if aim.self then "No one in reach" else "Can't find you"
		end
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
	elseif mode == "pointOptional" then
		local point = aim.point
		if point and aim.self and distance(aim.self, point) <= config.PVP.FUN_AIM_RANGE then
			use.aim = point
		end
	end
	return use, nil
end

-- A server refusal ("too far away") as hotbar tip text ("Too far away").
function InventoryCore.reasonText(message: any): string
	local text = if type(message) == "string" and message ~= "" then message else "Can't use that here"
	return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
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
