--!strict
--[[
	HotbarOrder (pure)

	The player's saved hotbar order (CONTRACT.md §3 `SetHotbar`, §5.1 `State.hotbar`): exactly SLOTS slot keys,
	slot 1 first, "" = empty slot. A key is the client's inventory entry key, `tool:<ToolName>`,
	`pvp:<Config.PVP_TOOLS id>` or `consumable:<Config.CONSUMABLES id>`. Ownership is not checked: the client
	skips keys it doesn't hold. Reads / writes `data.hotbar` (nil until the player first sets an order).
	`parse` checks a client order string, `clean` a stored list (SaveData.deserialize); both use one key rule.
]]

local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")

local HotbarOrder = {}

HotbarOrder.SLOTS = 9
HotbarOrder.MAX_ID_LENGTH = 32
-- Long enough for SLOTS of the longest legal key ("consumable:" + MAX_ID_LENGTH) and the commas between them.
HotbarOrder.MAX_LENGTH = 400

local KINDS = table.freeze({ tool = true, pvp = true, consumable = true })

-- True for a well-formed non-empty key. Ids: letters, digits, space, `_`, `-`, `.`, `'`; no leading / trailing space.
function HotbarOrder.isKey(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	local kind, id = string.match(value, "^(%a+):(.+)$")
	if not kind or not id or not KINDS[kind] or #id > HotbarOrder.MAX_ID_LENGTH then
		return false
	end
	if string.find(id, "[^%w _%-%.']") or string.find(id, "^%s") or string.find(id, "%s$") then
		return false
	end
	return true
end

local function empty(): { string }
	return table.create(HotbarOrder.SLOTS, "")
end

-- Parses "key,key,,key" (slot 1 first, fewer parts = the rest empty) into a SLOTS-long list.
-- Returns (nil, reason) for anything too long, more than SLOTS parts, a malformed key or a repeated key.
function HotbarOrder.parse(order: string): ({ string }?, string?)
	if type(order) ~= "string" or #order > HotbarOrder.MAX_LENGTH then
		return nil, "bad argument"
	end
	local parts = string.split(order, ",")
	if #parts > HotbarOrder.SLOTS then
		return nil, "bad argument"
	end
	local out = empty()
	local seen: { [string]: boolean } = {}
	for i, part in parts do
		if part ~= "" then
			if not HotbarOrder.isKey(part) or seen[part] then
				return nil, "bad argument"
			end
			seen[part] = true
			out[i] = part
		end
	end
	return out, nil
end

-- A stored order (untrusted): not a list -> nil; otherwise exactly SLOTS strings, where a malformed or repeated key
-- and anything past slot SLOTS become / are dropped as empty slots.
function HotbarOrder.clean(raw: any): { string }?
	if type(raw) ~= "table" then
		return nil
	end
	local out = empty()
	local seen: { [string]: boolean } = {}
	for i = 1, HotbarOrder.SLOTS do
		local key = raw[i]
		if HotbarOrder.isKey(key) and not seen[key] then
			seen[key] = true
			out[i] = key
		end
	end
	return out
end

-- Saves `order` as the player's hotbar. Returns ok + a player-facing reason; never errors.
function HotbarOrder.set(data: PlayerData.Data, order: string): (boolean, string?)
	local list, reason = HotbarOrder.parse(order)
	if not list then
		return false, reason
	end
	data.hotbar = list
	return true
end

return table.freeze(HotbarOrder)
