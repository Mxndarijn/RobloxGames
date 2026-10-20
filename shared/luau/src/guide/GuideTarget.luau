--!strict
--[[
	GuideTarget (pure)

	Picks which candidate a guide should lead to: the closest one on the
	ground plane (height ignored), but it keeps the current pick while that
	is still a candidate unless another one is clearly closer. That stops a
	guide flicking between two targets at nearly the same distance (two
	slimes walking side by side).

	The game builds the candidate list itself (already filtered: affordable,
	unlocked, reachable...), so nothing here knows what a target is.

	  GuideTarget.pick(candidates, from, currentKey?, stickiness?) -> Candidate?
	      stickiness 0.25: a new candidate must be more than 25% closer
	      than the current one to take over.
]]

export type Point = { x: number, z: number }
export type Candidate<T> = { key: string, x: number, z: number, value: T }

local GuideTarget = {}

GuideTarget.STICKINESS = 0.25

local function distance(c: { x: number, z: number }, from: Point): number
	local dx, dz = c.x - from.x, c.z - from.z
	return math.sqrt(dx * dx + dz * dz)
end

function GuideTarget.pick<T>(
	candidates: { Candidate<T> },
	from: Point,
	currentKey: string?,
	stickiness: number?
): Candidate<T>?
	local best: Candidate<T>? = nil
	local bestDistance = math.huge
	local current: Candidate<T>? = nil
	local currentDistance = math.huge
	for _, candidate in candidates do
		local d = distance(candidate, from)
		if d < bestDistance or (d == bestDistance and best ~= nil and candidate.key < best.key) then
			best, bestDistance = candidate, d
		end
		if currentKey ~= nil and candidate.key == currentKey then
			current, currentDistance = candidate, d
		end
	end
	if current == nil or best == nil then
		return best
	end
	local keep = 1 - math.clamp(stickiness or GuideTarget.STICKINESS, 0, 1)
	return if bestDistance < currentDistance * keep then best else current
end

return table.freeze(GuideTarget)
