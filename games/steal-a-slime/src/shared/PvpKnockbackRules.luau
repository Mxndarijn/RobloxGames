--!strict
--[[
	PvpKnockbackRules (pure, FEATURES.PvP, CONTRACT.md §26 "Knockback line")

	Geometry of the Knockback gloves: reach and the landing of the push. No Roblox APIs, so Lune tests it.
	The push is horizontal, away from the attacker, `tool.push` studs, then PvpRules.clampKnockback caps it and
	keeps the landing inside the map. Nothing here touches Humanoid health.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local PvpRules = if script then require(script.Parent.PvpRules) else require("./PvpRules")

type Vec = PvpRules.Vec

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
	Where `target` lands when pushed away from `attacker`. Returns (landing, push) as PvpRules.clampKnockback
	does (push.Y = the small arc). Standing on the same spot pushes along +Z.
]]
function PvpKnockbackRules.plan(tool: Config.PvpTool, attacker: Vec, target: Vec, bounds: PvpRules.Bounds?): (Vec, Vec)
	local dx, dz = target.X - attacker.X, target.Z - attacker.Z
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 1e-6 or length ~= length then
		dx, dz, length = 0, 1, 1
	end
	local push = tool.push or 0
	return PvpRules.clampKnockback(
		target,
		{ X = dx / length * push, Y = Config.PVP.KNOCKBACK_ARC_HEIGHT, Z = dz / length * push },
		bounds
	)
end

-- Horizontal studs of an applied push.
function PvpKnockbackRules.horizontal(push: Vec): number
	return math.sqrt(push.X * push.X + push.Z * push.Z)
end

-- Launch velocity that covers `push` horizontally in Config.PVP.KNOCKBACK_SECONDS and rises its arc (gravity in studs/s^2).
function PvpKnockbackRules.velocity(push: Vec, gravity: number): Vec
	local t = Config.PVP.KNOCKBACK_SECONDS
	return { X = push.X / t, Y = math.sqrt(2 * math.max(0, gravity) * math.max(0, push.Y)), Z = push.Z / t }
end

return PvpKnockbackRules
