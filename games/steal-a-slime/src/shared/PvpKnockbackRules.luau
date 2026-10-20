--!strict
--[[
	PvpKnockbackRules (pure, FEATURES.PvP, CONTRACT.md §26 "Knockback line")

	Geometry of the Knockback gloves: reach and the landing of the push. No Roblox APIs, so Lune tests it.
	The push is horizontal, away from the attacker, `tool.push` studs, then PvpRules.clampKnockback caps it and
	keeps the landing inside the map. Nothing here touches Humanoid health.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local PvpRules = if script then require(script.Parent.PvpRules) else require("./PvpRules")

export type Vec = PvpRules.Vec

local PvpKnockbackRules = {}

-- Glove reach in studs: the tool's own `reach`, else the base slap's.
function PvpKnockbackRules.reach(tool: Config.PvpTool): number
	return tool.reach or Config.SLAP_REACH
end

function PvpKnockbackRules.distance(a: Vec, b: Vec): number
	local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function PvpKnockbackRules.inReach(tool: Config.PvpTool, attacker: Vec, target: Vec): boolean
	local d = PvpKnockbackRules.distance(attacker, target)
	return d == d and d <= PvpKnockbackRules.reach(tool)
end

--[[
	Where `target` lands when pushed `push` studs straight away from `from` with an `arc` studs high. Returns
	(landing, push) as PvpRules.clampKnockback does (capped, inside the map). Standing on the same spot pushes along +Z.
]]
function PvpKnockbackRules.away(from: Vec, target: Vec, push: number, arc: number, bounds: PvpRules.Bounds?): (Vec, Vec)
	local dx, dz = target.X - from.X, target.Z - from.Z
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 1e-6 or length ~= length then
		dx, dz, length = 0, 1, 1
	end
	return PvpRules.clampKnockback(target, { X = dx / length * push, Y = arc, Z = dz / length * push }, bounds)
end

--[[
	The push of `tool` on `target` away from `attacker`: `tool.push` x `scale` (a power punch: Config.PVP.CHARGE_PUSH)
	studs with the row's `arc` (default KNOCKBACK_DEFAULT_ARC). Returns (landing, push) like `away`.
]]
function PvpKnockbackRules.plan(
	tool: Config.PvpTool,
	attacker: Vec,
	target: Vec,
	bounds: PvpRules.Bounds?,
	scale: number?
): (Vec, Vec)
	local push = (tool.push or 0) * (scale or 1)
	return PvpKnockbackRules.away(attacker, target, push, tool.arc or Config.PVP.KNOCKBACK_DEFAULT_ARC, bounds)
end

-- Horizontal studs of an applied push.
function PvpKnockbackRules.horizontal(push: Vec): number
	return math.sqrt(push.X * push.X + push.Z * push.Z)
end

-- Launch velocity that covers `push` horizontally in Config.PVP.KNOCKBACK_SECONDS (x KNOCKBACK_FRICTION_BOOST: ground
-- friction eats part of a short launch) and rises its arc (gravity in studs/s^2; default 196.2).
function PvpKnockbackRules.velocity(push: Vec, gravity: number?): Vec
	local t = Config.PVP.KNOCKBACK_SECONDS
	local boost = Config.PVP.KNOCKBACK_FRICTION_BOOST
	return {
		X = push.X / t * boost,
		Y = math.sqrt(2 * math.max(0, gravity or 196.2) * math.max(0, push.Y)),
		Z = push.Z / t * boost,
	}
end

-- The most horizontal speed a launch may have (client clamp uses it): MAX_PUSH over KNOCKBACK_SECONDS x boost.
function PvpKnockbackRules.maxHorizontalSpeed(): number
	return Config.PVP.KNOCKBACK_MAX_PUSH / Config.PVP.KNOCKBACK_SECONDS * Config.PVP.KNOCKBACK_FRICTION_BOOST
end

-- Clamps a received launch velocity (payload `velocity`) the same way on the client: junk / NaN -> zero, horizontal
-- speed <= maxHorizontalSpeed, vertical 0..KNOCKBACK_MAX_SPEED_Y.
function PvpKnockbackRules.clampVelocity(v: any): Vec
	if type(v) ~= "table" then
		return { X = 0, Y = 0, Z = 0 }
	end
	local x, y, z = v.X, v.Y, v.Z
	if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" or x ~= x or y ~= y or z ~= z then
		return { X = 0, Y = 0, Z = 0 }
	end
	local limit = PvpKnockbackRules.maxHorizontalSpeed()
	local h = math.sqrt(x * x + z * z)
	if h > limit then
		x, z = x / h * limit, z / h * limit
	end
	return { X = x, Y = math.clamp(y, 0, Config.PVP.KNOCKBACK_MAX_SPEED_Y), Z = z }
end

return PvpKnockbackRules
