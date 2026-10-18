--!strict
--[[
	PvpTrapRules (pure, FEATURES.PvP, CONTRACT.md §26 "Goo Trap line")

	Rules of the Goo Trap (GooTrap1-3): where one may be placed, how many, who triggers it and when it re-arms.
	A trap is plain data (no Instance): a server-side zone checked against player positions. No Roblox APIs,
	so Lune tests it. Nothing here touches Humanoid health; the freeze length goes through PvpRules.applyControl.
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
	control: number, -- freeze seconds before PvpRules clamps it
	rearm: number,
	armedAt: number, -- the time it is armed again (<= now = armed)
}

local PvpTrapRules = {}

-- A trap reaches this far above / below its position (a thief jumping over still triggers it, one on another floor not).
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
	May the owner standing at `origin` place `tool` at `aim`? `armed` = traps the owner already has. Placing
	beyond `tool.traps` is REFUSED (it does not replace the oldest). `onOwnPlot` = the aim lies on the owner's
	own plot. `origin` comes from the server, never the client.
]]
function PvpTrapRules.canPlace(
	tool: Config.PvpTool,
	armed: number,
	origin: Vec,
	aim: any,
	onOwnPlot: boolean,
	flag: boolean?
): (boolean, string?)
	if not PvpRules.enabled(flag) then
		return false, "PvP is not open yet"
	end
	if tool.line ~= "Trap" then
		return false, "not a trap"
	end
	if not PvpTrapRules.validAim(aim) then
		return false, "no aim"
	end
	if not PvpTrapRules.validAim(origin) or not PvpTrapRules.inReach(origin, aim) then
		return false, "too far away"
	end
	if not onOwnPlot then
		return false, "only on your own plot"
	end
	if PvpRules.inSafeZone(aim) then
		return false, "safe zone"
	end
	if armed >= (tool.traps or 1) then
		return false, "too many traps"
	end
	return true, nil
end

function PvpTrapRules.new(id: string, owner: number, tool: Config.PvpTool, aim: Vec, now: number): Trap
	return {
		id = id,
		owner = owner,
		itemId = tool.id,
		position = { X = aim.X, Y = aim.Y, Z = aim.Z },
		radius = tool.radius or 3,
		control = tool.control or 0,
		rearm = tool.cooldown, -- the Trap tiers' cooldown is their re-arm time
		armedAt = now,
	}
end

function PvpTrapRules.isArmed(trap: Trap, now: number): boolean
	return now >= trap.armedAt
end

function PvpTrapRules.inRadius(trap: Trap, position: Vec): boolean
	local dx, dz, dy = position.X - trap.position.X, position.Z - trap.position.Z, position.Y - trap.position.Y
	local d2 = dx * dx + dz * dz
	return d2 == d2 and d2 <= trap.radius * trap.radius and math.abs(dy) <= PvpTrapRules.HEIGHT
end

--[[
	Does `victim` spring `trap`? Only a thief carrying the OWNER's slime (never the owner, never a wild-slime
	carrier), in the radius, while the trap is armed and the victim is not new-player shielded.
]]
function PvpTrapRules.triggers(
	trap: Trap,
	victimUserId: number,
	position: Vec,
	carryingOwnersSlime: boolean,
	shielded: boolean,
	now: number
): boolean
	if victimUserId == trap.owner or not carryingOwnersSlime or shielded then
		return false
	end
	return PvpTrapRules.isArmed(trap, now) and PvpTrapRules.inRadius(trap, position)
end

-- Springs the trap: it is disarmed for `rearm` seconds (it stays as a zone).
function PvpTrapRules.spring(trap: Trap, now: number)
	trap.armedAt = now + trap.rearm
end

return PvpTrapRules
