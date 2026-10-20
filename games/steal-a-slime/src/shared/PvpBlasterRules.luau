--!strict
--[[
	PvpBlasterRules (pure, FEATURES.PvP, CONTRACT.md §26.6)

	Geometry of the Goo Blaster blobs. No Roblox APIs, so Lune tests it. A blob leaves the attacker's position and
	flies a ballistic arc (gravity Config.PVP.BLOB_GRAVITY, flight time = distance / tool.speed) to the aim point,
	clamped to `tool.range`. The server tests the arc against the players' positions at fire time; the client draws
	the same arc (one particle with the same start velocity and gravity). Nothing here touches Humanoid health.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local PvpRules = if script then require(script.Parent.PvpRules) else require("./PvpRules")

type Vec = PvpRules.Vec

export type Candidate = { id: number, position: Vec }
export type Arc = {
	from: Vec,
	to: Vec, -- where the arc ends (the aim, clamped to the range)
	velocity: Vec, -- start velocity
	flight: number, -- seconds from `from` to `to`
	gravity: number,
}

local PvpBlasterRules = {}

PvpBlasterRules.HIT_RADIUS = 3 -- studs from the arc to a player's root (a forgiving body width)
PvpBlasterRules.MIN_FLIGHT = 0.15 -- seconds: even a point-blank blob is visible
PvpBlasterRules.SAMPLES = 16 -- points along the arc the hit test checks

function PvpBlasterRules.range(tool: Config.PvpTool): number
	return tool.range or 25
end

-- A table / Vector3 with finite X / Y / Z.
local function isFinite(v: any): boolean
	if type(v) ~= "table" and typeof(v) ~= "Vector3" then
		return false
	end
	for _, n in { v.X, v.Y, v.Z } do
		if type(n) ~= "number" or n ~= n or math.abs(n) == math.huge then
			return false
		end
	end
	return true
end
PvpBlasterRules.isFinite = isFinite

-- Unit direction from origin toward aim, nil for a junk or zero-length aim.
function PvpBlasterRules.direction(origin: Vec, aim: Vec): Vec?
	if not isFinite(origin) or not isFinite(aim) then
		return nil
	end
	local dx, dy, dz = aim.X - origin.X, aim.Y - origin.Y, aim.Z - origin.Z
	local length = math.sqrt(dx * dx + dy * dy + dz * dz)
	if length < 1e-6 then
		return nil
	end
	return { X = dx / length, Y = dy / length, Z = dz / length }
end

-- `aim` pulled back along the line from `origin` so it is at most `range` studs away.
function PvpBlasterRules.clampAim(origin: Vec, aim: Vec, range: number): Vec
	local dx, dy, dz = aim.X - origin.X, aim.Y - origin.Y, aim.Z - origin.Z
	local length = math.sqrt(dx * dx + dy * dy + dz * dz)
	if length <= range or length < 1e-6 then
		return { X = aim.X, Y = aim.Y, Z = aim.Z }
	end
	local k = range / length
	return { X = origin.X + dx * k, Y = origin.Y + dy * k, Z = origin.Z + dz * k }
end

-- The aim turned `degrees` about the vertical axis through `origin` (the Blaster's fan).
function PvpBlasterRules.turn(origin: Vec, aim: Vec, degrees: number): Vec
	local a = math.rad(degrees)
	local dx, dz = aim.X - origin.X, aim.Z - origin.Z
	local c, s = math.cos(a), math.sin(a)
	return { X = origin.X + dx * c - dz * s, Y = aim.Y, Z = origin.Z + dx * s + dz * c }
end

-- The arc from `origin` to `aim` (clamped to the tool's range). nil for a junk aim.
function PvpBlasterRules.arc(tool: Config.PvpTool, origin: Vec, aim: Vec): Arc?
	if not PvpBlasterRules.direction(origin, aim) then
		return nil
	end
	local to = PvpBlasterRules.clampAim(origin, aim, PvpBlasterRules.range(tool))
	local dx, dy, dz = to.X - origin.X, to.Y - origin.Y, to.Z - origin.Z
	local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
	local g = Config.PVP.BLOB_GRAVITY
	local t = math.max(PvpBlasterRules.MIN_FLIGHT, distance / math.max(1, tool.speed or 60))
	return {
		from = { X = origin.X, Y = origin.Y, Z = origin.Z },
		to = to,
		velocity = { X = dx / t, Y = dy / t + 0.5 * g * t, Z = dz / t },
		flight = t,
		gravity = g,
	}
end

-- The blob's position `t` seconds after it left.
function PvpBlasterRules.pointAt(arc: Arc, t: number): Vec
	local v, o = arc.velocity, arc.from
	return { X = o.X + v.X * t, Y = o.Y + v.Y * t - 0.5 * arc.gravity * t * t, Z = o.Z + v.Z * t }
end

local function distance(a: Vec, b: Vec): number
	local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- The first candidate the arc passes within HIT_RADIUS of (earliest along the flight). Returns it and the seconds into
-- the flight, or nil.
function PvpBlasterRules.firstHit(arc: Arc, candidates: { Candidate }): (Candidate?, number?)
	local best: Candidate? = nil
	local bestT = math.huge
	for i = 1, PvpBlasterRules.SAMPLES do
		local t = arc.flight * i / PvpBlasterRules.SAMPLES
		if t >= bestT then
			break
		end
		local point = PvpBlasterRules.pointAt(arc, t)
		for _, candidate in candidates do
			if isFinite(candidate.position) and distance(point, candidate.position) <= PvpBlasterRules.HIT_RADIUS then
				if t < bestT then
					best, bestT = candidate, t
				end
			end
		end
	end
	return best, if best then bestT else nil
end

-- Every candidate within `radius` of `center` (the Cannon splash).
function PvpBlasterRules.within(center: Vec, radius: number, candidates: { Candidate }): { Candidate }
	local out = {}
	for _, candidate in candidates do
		if isFinite(candidate.position) and distance(center, candidate.position) <= radius then
			table.insert(out, candidate)
		end
	end
	return out
end

-- Walk speed multiplier for a slow of `slow` (0..1): never below 1 - 0.9.
function PvpBlasterRules.slowFactor(slow: number?): number
	local s = slow or 0
	if s ~= s then
		s = 0
	end
	return 1 - math.clamp(s, 0, 0.9)
end

-- The fan of aim points of one Blaster shot: `blobs` aims `spreadDeg` apart, centred on `aim`.
function PvpBlasterRules.fan(tool: Config.PvpTool, origin: Vec, aim: Vec): { Vec }
	local n = math.max(1, tool.blobs or 1)
	local spread = tool.spreadDeg or 0
	local out = {}
	for i = 1, n do
		local offset = (i - (n + 1) / 2) * spread
		table.insert(out, if offset == 0 then aim else PvpBlasterRules.turn(origin, aim, offset))
	end
	return out
end

return PvpBlasterRules
