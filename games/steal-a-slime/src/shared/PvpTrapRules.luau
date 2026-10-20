--!strict
--[[
	PvpTrapRules (pure, FEATURES.PvP, CONTRACT.md §26.5)

	Rules of the Goo Traps (GooTrap1-3): where one may be thrown, the live cap, who springs one and what it does.
	A trap is plain data (no Instance): a server-side zone checked against player positions. No Roblox APIs, so
	Lune tests it. Nothing here touches Humanoid health; holds go through PvpRules.applyControl, slows through
	PvpRules.applySlow.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local PvpRules = if script then require(script.Parent.PvpRules) else require("./PvpRules")

type Vec = PvpRules.Vec

export type Trap = {
	id: string,
	owner: number, -- userId
	itemId: string,
	position: Vec,
	radius: number,
	placedAt: number,
	expiresAt: number,
}

local PvpTrapRules = {}

-- A trap reaches this far above / below its position (a player jumping over still springs it, one on another floor not).
PvpTrapRules.HEIGHT = 8

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- A usable aim point: a table / Vector3 with finite X / Y / Z.
function PvpTrapRules.validAim(aim: any): boolean
	if type(aim) ~= "table" and typeof(aim) ~= "Vector3" then
		return false
	end
	return finite(aim.X) and finite(aim.Y) and finite(aim.Z)
end

-- Is `aim` within Config.PVP.TRAP_PLACE_RANGE of `origin` (the owner's server-side position)?
function PvpTrapRules.inReach(origin: Vec, aim: Vec): boolean
	local dx, dy, dz = aim.X - origin.X, aim.Y - origin.Y, aim.Z - origin.Z
	local d2 = dx * dx + dy * dy + dz * dz
	local range = Config.PVP.TRAP_PLACE_RANGE
	return d2 == d2 and d2 <= range * range
end

--[[
	May the owner standing at `origin` throw `tool` at `aim`? `charges` = charges of that tier left. Anywhere on the
	map within TRAP_PLACE_RANGE; `origin` comes from the server, never the client. The live cap is not a refusal
	(`overflow` says how many old traps go).
]]
function PvpTrapRules.canPlace(
	tool: Config.PvpTool,
	charges: number,
	origin: Vec,
	aim: any,
	flag: boolean?
): (boolean, string?)
	if not PvpRules.enabled(flag) then
		return false, "PvP is not open yet"
	end
	if tool.line ~= "Trap" then
		return false, "not a trap"
	end
	if charges <= 0 then
		return false, "no traps left"
	end
	if not PvpTrapRules.validAim(aim) then
		return false, "no aim"
	end
	if not PvpTrapRules.validAim(origin) or not PvpTrapRules.inReach(origin, aim) then
		return false, "too far away"
	end
	return true, nil
end

-- How many of the owner's oldest traps go when one more is placed with `live` already out.
function PvpTrapRules.overflow(live: number): number
	return math.max(0, live + 1 - Config.PVP.TRAP_MAX_LIVE)
end

function PvpTrapRules.new(id: string, owner: number, tool: Config.PvpTool, aim: Vec, now: number): Trap
	return {
		id = id,
		owner = owner,
		itemId = tool.id,
		position = { X = aim.X, Y = aim.Y, Z = aim.Z },
		radius = tool.radius or 3,
		placedAt = now,
		expiresAt = now + Config.PVP.TRAP_LIFETIME_SECONDS,
	}
end

function PvpTrapRules.expired(trap: Trap, now: number): boolean
	return now >= trap.expiresAt
end

function PvpTrapRules.within(center: Vec, radius: number, position: Vec): boolean
	local dx, dz, dy = position.X - center.X, position.Z - center.Z, position.Y - center.Y
	local d2 = dx * dx + dz * dz
	return d2 == d2 and d2 <= radius * radius and math.abs(dy) <= PvpTrapRules.HEIGHT
end

function PvpTrapRules.inRadius(trap: Trap, position: Vec): boolean
	return PvpTrapRules.within(trap.position, trap.radius, position)
end

-- Does `victim` spring `trap`? Anyone but the owner, in the radius, before it expires.
function PvpTrapRules.triggers(trap: Trap, victimUserId: number, position: Vec, now: number): boolean
	if victimUserId == trap.owner or PvpTrapRules.expired(trap, now) then
		return false
	end
	return PvpTrapRules.inRadius(trap, position)
end

export type Effect = {
	hold: number, -- seconds held in place (0 = none)
	slow: number, -- speed taken away while slowed after the hold (0 = none)
	slowSeconds: number,
	pull: number, -- studs around the trap pulled in (Mega)
	spit: number, -- studs of push when the hold ends (Mega)
	spitArc: number,
}

-- What a tier does to the player it catches (before PvpRules clamps it).
function PvpTrapRules.effect(tool: Config.PvpTool): Effect
	return {
		hold = tool.control or 0,
		slow = tool.slow or 0,
		slowSeconds = tool.slowSeconds or 0,
		pull = tool.pull or 0,
		spit = if tool.pull then tool.push or 0 else 0,
		spitArc = tool.spitArc or 0,
	}
end

return PvpTrapRules
