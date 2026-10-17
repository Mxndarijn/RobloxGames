--!strict
--[[
	PvpBlasterRules (pure, FEATURES.PvP, CONTRACT.md §26 "Goo Blaster line")

	Geometry of the Goo Blaster hitscan and the slow factor. No Roblox APIs, so Lune tests it. The shot is a
	segment from the attacker's root toward the aim point, `tool.range` studs long; the first player whose root
	lies within HIT_RADIUS of that segment is hit. Nothing here touches Humanoid health: the only effect is a
	walk-speed multiplier (PvpRules.applySlow bounds its length).
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local PvpRules = if script then require(script.Parent.PvpRules) else require("./PvpRules")

type Vec = PvpRules.Vec

export type Candidate = { id: number, position: Vec }

local PvpBlasterRules = {}

PvpBlasterRules.HIT_RADIUS = 3 -- studs from the ray to a player's root (a forgiving body width)
PvpBlasterRules.MISS_FX_SECONDS = 0.4 -- how long clients draw a missed shot
PvpBlasterRules.MAX_SLOW = 0.9 -- the walk speed never drops below 10 % of normal

function PvpBlasterRules.range(tool: Config.PvpTool): number
	return tool.range or 25
end

local function finite(v: Vec): boolean
	return v.X == v.X
		and v.Y == v.Y
		and v.Z == v.Z
		and math.abs(v.X) < math.huge
		and math.abs(v.Y) < math.huge
		and math.abs(v.Z) < math.huge
end

-- Unit direction from origin toward aim, nil for a junk or zero-length aim.
function PvpBlasterRules.direction(origin: Vec, aim: Vec): Vec?
	if not finite(origin) or not finite(aim) then
		return nil
	end
	local dx, dy, dz = aim.X - origin.X, aim.Y - origin.Y, aim.Z - origin.Z
	local length = math.sqrt(dx * dx + dy * dy + dz * dz)
	if length < 1e-6 then
		return nil
	end
	return { X = dx / length, Y = dy / length, Z = dz / length }
end

-- Distance along the ray (0..range) of the point closest to `point`, and the distance from the ray to it.
function PvpBlasterRules.along(origin: Vec, dir: Vec, range: number, point: Vec): (number, number)
	local px, py, pz = point.X - origin.X, point.Y - origin.Y, point.Z - origin.Z
	local t = math.clamp(px * dir.X + py * dir.Y + pz * dir.Z, 0, range)
	local cx, cy, cz = dir.X * t - px, dir.Y * t - py, dir.Z * t - pz
	return t, math.sqrt(cx * cx + cy * cy + cz * cz)
end

function PvpBlasterRules.endPoint(origin: Vec, dir: Vec, range: number): Vec
	return { X = origin.X + dir.X * range, Y = origin.Y + dir.Y * range, Z = origin.Z + dir.Z * range }
end

-- The first candidate along the ray within HIT_RADIUS (nearest wins). Returns the candidate or nil.
function PvpBlasterRules.firstHit(origin: Vec, dir: Vec, range: number, candidates: { Candidate }): Candidate?
	local best: Candidate? = nil
	local bestT = math.huge
	for _, candidate in candidates do
		if finite(candidate.position) then
			local t, off = PvpBlasterRules.along(origin, dir, range, candidate.position)
			if off <= PvpBlasterRules.HIT_RADIUS and t < bestT then
				best, bestT = candidate, t
			end
		end
	end
	return best
end

-- Walk speed multiplier for the tier: 1 - slow, never below 1 - MAX_SLOW.
function PvpBlasterRules.slowFactor(tool: Config.PvpTool): number
	local slow = tool.slow or 0
	if slow ~= slow then
		slow = 0
	end
	return 1 - math.clamp(slow, 0, PvpBlasterRules.MAX_SLOW)
end

-- The multiplier in force at `now` for a slow of `factor` that lasts until `untilTime` (1 once over).
function PvpBlasterRules.factorAt(factor: number, untilTime: number, now: number): number
	return if now < untilTime then factor else 1
end

return PvpBlasterRules
