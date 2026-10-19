--!strict
--[[
	PvpFunRules (pure, FEATURES.PvP, CONTRACT.md §26.4)

	Geometry and small rules of the Fun items that the server (server/PvpFun) and the client (ui/PvpFunFx) must agree
	on: where an aim lands, how long a lob flies, where each bubble of a Bubble Wand stream is, which player a hat
	shot hits, the Squeaky Hammer combo count and the Goo Fireworks colour. Positions are any table with X / Y / Z
	(a Vector3 works). No Roblox APIs, so Lune tests it.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Progression = if script then require(script.Parent.Progression) else require("./Progression")

export type Vec = { X: number, Y: number, Z: number }
-- A Bubble Wand stream: `direction` is a horizontal unit vector.
export type Stream = { origin: Vec, direction: Vec, startedAt: number }
export type Candidate = { id: number, position: Vec }
-- The Squeaky Hammer combo of one attacker: hits on `key` since `firstAt`.
export type Combo = { key: string, count: number, firstAt: number }

local FUN = Config.PVP_FUN

local PvpFunRules = {}

local GOO: { number } = { 0.35, 0.9, 0.3 }

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- A usable position (a finite X / Y / Z), copied into a plain table; nil for junk.
function PvpFunRules.vec(v: any): Vec?
	local t = typeof(v)
	if t ~= "Vector3" and t ~= "vector" and t ~= "table" then
		return nil
	end
	local ok, x, y, z = pcall(function()
		return v.X, v.Y, v.Z
	end)
	if not ok or not finite(x) or not finite(y) or not finite(z) then
		return nil
	end
	return { X = x, Y = y, Z = z }
end

local function sub(a: Vec, b: Vec): Vec
	return { X = a.X - b.X, Y = a.Y - b.Y, Z = a.Z - b.Z }
end

local function length(v: Vec): number
	return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
end

function PvpFunRules.distance(a: Vec, b: Vec): number
	return length(sub(a, b))
end

function PvpFunRules.flatDistance(a: Vec, b: Vec): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- `to`, pulled in along the same direction so it is at most `range` studs from `from` (3D).
function PvpFunRules.within(from: Vec, to: Vec, range: number): Vec
	local d = sub(to, from)
	local n = length(d)
	if n <= range or n < 1e-6 then
		return { X = to.X, Y = to.Y, Z = to.Z }
	end
	local k = range / n
	return { X = from.X + d.X * k, Y = from.Y + d.Y * k, Z = from.Z + d.Z * k }
end

-- `to`, pulled in horizontally so it is at most `range` studs from `from` (its height is kept).
function PvpFunRules.withinFlat(from: Vec, to: Vec, range: number): Vec
	local n = PvpFunRules.flatDistance(from, to)
	if n <= range or n < 1e-6 then
		return { X = to.X, Y = to.Y, Z = to.Z }
	end
	local k = range / n
	return { X = from.X + (to.X - from.X) * k, Y = to.Y, Z = from.Z + (to.Z - from.Z) * k }
end

PvpFunRules.FEET = 3 -- studs from a character's root down to its feet
PvpFunRules.GROUND_ABOVE = 4 -- an aim higher than this above the user's root (the sky) lands at their feet height
PvpFunRules.GROUND_BELOW = 40 -- ...and one this far below them too

--[[
	Where a thrown / placed item lands for the user at root `from` aiming at `aim`: pulled in horizontally to
	`range`; an aim in the sky (or far below) lands at the user's feet height instead.
]]
function PvpFunRules.landing(from: Vec, aim: Vec, range: number): Vec
	local point = PvpFunRules.withinFlat(from, aim, range)
	if point.Y > from.Y + PvpFunRules.GROUND_ABOVE or point.Y < from.Y - PvpFunRules.GROUND_BELOW then
		point.Y = from.Y - PvpFunRules.FEET
	end
	return point
end

-- Unit vector from `from` toward `to`; `flat` drops the height. Nil when they are (nearly) the same point.
function PvpFunRules.direction(from: Vec, to: Vec, flat: boolean?): Vec?
	local d = sub(to, from)
	if flat then
		d.Y = 0
	end
	local n = length(d)
	if n < 1e-6 or n ~= n then
		return nil
	end
	return { X = d.X / n, Y = d.Y / n, Z = d.Z / n }
end

-- The hold charge sent with UsePvpItem: 0..1, junk = 0.
function PvpFunRules.power(raw: any): number
	return if finite(raw) then math.clamp(raw, 0, 1) else 0
end

-- Seconds a lobbed balloon / dance bomb flies from `from` to `to`.
function PvpFunRules.flightTime(from: Vec, to: Vec): number
	return math.clamp(
		PvpFunRules.flatDistance(from, to) / FUN.THROW_SPEED,
		FUN.THROW_MIN_SECONDS,
		FUN.THROW_MAX_SECONDS
	)
end

-- `position` is inside a round area of `radius` around `center` (horizontal), at most `height` studs above or below.
function PvpFunRules.inArea(center: Vec, radius: number, height: number, position: Vec): boolean
	return PvpFunRules.flatDistance(center, position) <= radius and math.abs(position.Y - center.Y) <= height
end

-- When bubble `index` (1..COUNT) of a stream is blown.
function PvpFunRules.bubbleBorn(stream: Stream, index: number): number
	return stream.startedAt + (index - 1) * FUN.BUBBLES.SPACING
end

-- When the whole stream is gone.
function PvpFunRules.streamEnds(stream: Stream): number
	return PvpFunRules.bubbleBorn(stream, FUN.BUBBLES.COUNT) + FUN.BUBBLES.LIFETIME
end

-- Where bubble `index` floats at time `t`, or nil when it is not blown yet or already gone.
function PvpFunRules.bubbleAt(stream: Stream, index: number, t: number): Vec?
	local age = t - PvpFunRules.bubbleBorn(stream, index)
	if age < 0 or age > FUN.BUBBLES.LIFETIME then
		return nil
	end
	local o, d = stream.origin, stream.direction
	local run = FUN.BUBBLES.SPEED * age
	return { X = o.X + d.X * run, Y = o.Y + FUN.BUBBLES.RISE * age, Z = o.Z + d.Z * run }
end

-- Distance from `p` to the segment a..b.
local function segmentDistance(a: Vec, b: Vec, p: Vec): (number, number)
	local ab, ap = sub(b, a), sub(p, a)
	local len2 = ab.X * ab.X + ab.Y * ab.Y + ab.Z * ab.Z
	local u = if len2 > 0 then math.clamp((ap.X * ab.X + ap.Y * ab.Y + ap.Z * ab.Z) / len2, 0, 1) else 0
	local closest = { X = a.X + ab.X * u, Y = a.Y + ab.Y * u, Z = a.Z + ab.Z * u }
	return PvpFunRules.distance(closest, p), u
end

--[[
	A hat shot from `origin` along the unit `direction`, `range` studs long and `radius` wide: the candidate nearest
	the muzzle whose position is within `radius` of the shot, and where the shot ends (the hit, or the far end).
]]
function PvpFunRules.firstHit(
	origin: Vec,
	direction: Vec,
	range: number,
	radius: number,
	candidates: { Candidate }
): (Candidate?, Vec)
	local finish =
		{ X = origin.X + direction.X * range, Y = origin.Y + direction.Y * range, Z = origin.Z + direction.Z * range }
	local best: Candidate? = nil
	local bestU = math.huge
	for _, c in candidates do
		local d, u = segmentDistance(origin, finish, c.position)
		if d <= radius and u < bestU then
			best, bestU = c, u
		end
	end
	if best then
		return best, best.position
	end
	return nil, finish
end

--[[
	One Squeaky Hammer hit on `key` ("p<userId>" / "s<slimeId>") at `now`. Returns the attacker's new combo record
	and whether this hit completes a combo (COMBO_HITS on the same key within COMBO_WINDOW). A combo starts over.
]]
function PvpFunRules.combo(previous: Combo?, key: string, now: number): (Combo, boolean)
	local hammer = FUN.HAMMER
	if previous and previous.key == key and now - previous.firstAt <= hammer.COMBO_WINDOW then
		local count = previous.count + 1
		if count >= hammer.COMBO_HITS then
			return { key = key, count = 0, firstAt = now }, true
		end
		return { key = key, count = count, firstAt = previous.firstAt }, false
	end
	return { key = key, count = 1, firstAt = now }, false
end

-- The Goo Fireworks colour, { r, g, b } 0..1: the favourite slime's colour, else the best slime's, else goo green.
function PvpFunRules.fireworkColor(data: any): { number }
	local ok, slime = pcall(Progression.keeper, data)
	local color = if ok and slime then slime.color else nil
	if type(color) ~= "table" or #color < 3 then
		return table.clone(GOO)
	end
	local out = {}
	for i = 1, 3 do
		local c = tonumber(color[i])
		out[i] = if c and c == c then math.clamp(c / 255, 0, 1) else GOO[i]
	end
	return out
end

-- How many hats a player wears after one more lands: the stack grows to MAX_STACK while the last hat is still on.
function PvpFunRules.hatStack(previous: number, stillOn: boolean): number
	return if stillOn then math.min(previous + 1, FUN.HATS.MAX_STACK) else 1
end

return PvpFunRules
