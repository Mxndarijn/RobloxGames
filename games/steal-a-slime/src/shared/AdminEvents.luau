--!strict
--[[
	AdminEvents (pure, FEATURES.AdminEvents, CONTRACT.md §12)

	Who may trigger a live event, how a chat command and a cross-server payload are parsed and
	validated, and the rate limit. No Roblox APIs: the server wires it (server/AdminEvents).
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

export type Def = { id: string, label: string, icon: string, luck: number }
export type Payload = { v: number, id: string, seconds: number, by: number, nonce: string }
export type Limiter = { lastAt: number }

local AdminEvents = {}

AdminEvents.VERSION = 1

function AdminEvents.def(id: any): Def?
	for _, def in Config.ADMIN_EVENTS do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- True for a listed admin or the place owner (`creatorId` is nil/0 for groups and unpublished places).
function AdminEvents.isAdmin(userId: any, creatorId: number?): boolean
	if not Config.FEATURES.AdminEvents or type(userId) ~= "number" or userId ~= userId or userId <= 0 then
		return false
	end
	if creatorId and creatorId > 0 and userId == creatorId then
		return true
	end
	return table.find(Config.ADMIN_USER_IDS, userId) ~= nil
end

local function clampSeconds(seconds: any): number?
	if type(seconds) ~= "number" or seconds ~= seconds then
		return nil
	end
	return math.clamp(math.floor(seconds), Config.ADMIN_EVENT_MIN_SECONDS, Config.ADMIN_EVENT_MAX_SECONDS)
end

-- "/event luck 10" -> ("luck", 600). Minutes, optional. nil when it is not an event command.
function AdminEvents.parse(text: any): (string?, number?)
	if type(text) ~= "string" or #text > 64 then
		return nil, nil
	end
	local id, minutes = string.match(text, "^/event%s+(%a+)%s*(%d*%.?%d*)%s*$")
	if not id or not AdminEvents.def(string.lower(id)) then
		return nil, nil
	end
	local seconds = Config.ADMIN_EVENT_DEFAULT_SECONDS
	if minutes ~= "" then
		local n = tonumber(minutes)
		if not n then
			return nil, nil
		end
		seconds = n * 60
	end
	return string.lower(id), clampSeconds(seconds)
end

function AdminEvents.payload(id: string, seconds: number, by: number, nonce: string): Payload
	return { v = AdminEvents.VERSION, id = id, seconds = seconds, by = by, nonce = nonce }
end

-- Rebuilds a cross-server payload from untrusted data; nil when anything is off. The sender must
-- itself be an admin, so a forged message from a non-admin does nothing.
function AdminEvents.validate(raw: any, creatorId: number?): Payload?
	if type(raw) ~= "table" or raw.v ~= AdminEvents.VERSION then
		return nil
	end
	if type(raw.id) ~= "string" or not AdminEvents.def(raw.id) then
		return nil
	end
	if type(raw.nonce) ~= "string" or #raw.nonce == 0 or #raw.nonce > 40 then
		return nil
	end
	local seconds = clampSeconds(raw.seconds)
	if not seconds or not AdminEvents.isAdmin(raw.by, creatorId) then
		return nil
	end
	return AdminEvents.payload(raw.id, seconds, raw.by, raw.nonce)
end

function AdminEvents.limiter(): Limiter
	return { lastAt = -math.huge }
end

-- True (and records `now`) when the cooldown since the last accepted trigger has passed.
function AdminEvents.allow(limiter: Limiter, now: number): boolean
	if now - limiter.lastAt < Config.ADMIN_EVENT_COOLDOWN then
		return false
	end
	limiter.lastAt = now
	return true
end

-- HUD / toast text: "🍀 Luck Event x3 luck - 10:00 left" style pieces come from ModifierBadge;
-- this is the toast.
function AdminEvents.announce(def: Def, seconds: number): string
	local minutes = math.max(1, math.floor(seconds / 60 + 0.5))
	if def.id == "rain" then
		return `{def.icon} {def.label}! The fountain is overflowing!`
	end
	return `{def.icon} {def.label}! Active for {minutes} min.`
end

return table.freeze(AdminEvents)
