--!strict
--[[
	GuideRoute (pure)

	The route bookkeeping behind the ground guide: where the route ends,
	how far along it the player is, and when it needs a new path.

	Approach spot. A target's own pivot usually sits inside a solid part (a
	vat, a counter, a board), and no path ends there. `approachCandidates`
	puts candidate spots on a ring just outside the target's ground
	footprint (an oriented rectangle), one per direction, `margin` studs
	beyond the rectangle's edge. The adapter grounds each one with a raycast
	and drops the blocked ones; `pickApproach` then takes the one closest to
	the player on the ground plane, skipping spots whose height is more than
	`maxStep` studs away from the target's base (roofs, pits). Ties keep the
	earlier candidate, so the pick is stable.

	Progress. Distances along a route are measured on the ground plane, and
	the player is projected onto the route segments horizontally (the
	player's root floats above the waypoints). `advance` only moves progress
	forward and only looks `lookahead` studs ahead, so a route that bends
	back near the player never makes the trail jump. `offRoute` is the
	distance from the player to the part of the route still ahead.
	`ahead` is the polyline to draw: the player, then the waypoints past
	the progress point.

	Recompute. `shouldRecompute` asks for a new path when there is none
	yet, when the player left the route by more than `offRoute` studs, when
	the goal moved more than `goalMoved` studs since the route was made, or
	every `safetyRefresh` seconds. After failed attempts it waits a back-off
	(`retryBase`, doubling, at most `retryMax` seconds) before trying again.

	  GuideRoute.approachCandidates(footprint, y, options?) -> { Point }
	  GuideRoute.pickApproach(spots, from, baseY?, options?) -> (Point?, index?)
	  GuideRoute.project(route, p, fromAlong?, toAlong?) -> (along, distance)
	  GuideRoute.advance(route, p, along, options?) -> along
	  GuideRoute.offRoute(route, p, along) -> number
	  GuideRoute.ahead(route, along, from) -> { Point }
	  GuideRoute.length(route) -> number            -- on the ground plane
	  GuideRoute.reaches(route, goal, tolerance?) -> boolean
	  GuideRoute.backoff(failures, options?) -> seconds
	  GuideRoute.shouldRecompute(state, options?) -> (boolean, reason?)
	      reason: "NoRoute" | "OffRoute" | "GoalMoved" | "Refresh"
	  GuideRoute.arrival(distance, arriveDistance, band?) -> alpha 0..1
]]

export type Point = { x: number, y: number, z: number }

-- A target's footprint on the ground: an oriented rectangle around (x, z). `axisX, axisZ` is the unit direction of
-- its first axis (A); the second axis (B) is (-axisZ, axisX). `halfA` and `halfB` are its half extents along them.
export type Footprint = { x: number, z: number, axisX: number, axisZ: number, halfA: number, halfB: number }

export type Options = {
	directions: number?, -- approach candidates around the target
	margin: number?, -- studs between the target's footprint and a candidate
	maxStep: number?, -- a spot's height may differ this much from the target's base
	lookahead: number?, -- studs ahead of the progress point the player can be matched to
	offRoute: number?,
	goalMoved: number?,
	safetyRefresh: number?,
	retryBase: number?,
	retryMax: number?,
	reachTolerance: number?, -- a path ending this close to the goal counts as reaching it
}

export type RecomputeState = {
	hasRoute: boolean,
	computing: boolean?,
	failures: number, -- failed attempts in a row
	sinceAttempt: number, -- seconds since the last attempt started
	offRoute: number, -- studs from the remaining route
	goalMoved: number, -- studs the goal moved since the route was made
	paused: boolean?, -- the game asked for no pathing right now (GuideView `shouldPath`)
}

local GuideRoute = {}

GuideRoute.DEFAULTS = table.freeze({
	directions = 12,
	margin = 4,
	maxStep = 6,
	lookahead = 16,
	offRoute = 6,
	goalMoved = 6,
	safetyRefresh = 5,
	retryBase = 1,
	retryMax = 4,
	reachTolerance = 6,
})

local ARRIVE_BAND = 4

local function option(options: Options?, name: string): number
	local value = if options then (options :: any)[name] else nil
	return if type(value) == "number" then value else (GuideRoute.DEFAULTS :: any)[name]
end

local function flat(ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	return math.sqrt(dx * dx + dz * dz)
end

function GuideRoute.approachCandidates(footprint: Footprint, y: number, options: Options?): { Point }
	local count = math.max(math.floor(option(options, "directions")), 1)
	local margin = option(options, "margin")
	local ax, az = footprint.axisX, footprint.axisZ
	local bx, bz = -az, ax
	local out: { Point } = {}
	for i = 0, count - 1 do
		local angle = 2 * math.pi * i / count
		local c, s = math.cos(angle), math.sin(angle)
		-- c and s are this direction's components along axes A and B
		local exitA = if math.abs(c) > 1e-6 then footprint.halfA / math.abs(c) else math.huge
		local exitB = if math.abs(s) > 1e-6 then footprint.halfB / math.abs(s) else math.huge
		local r = math.min(exitA, exitB) + margin
		local dx, dz = ax * c + bx * s, az * c + bz * s
		table.insert(out, { x = footprint.x + dx * r, y = y, z = footprint.z + dz * r })
	end
	return out
end

function GuideRoute.pickApproach(spots: { Point }, from: Point, baseY: number?, options: Options?): (Point?, number?)
	local maxStep = option(options, "maxStep")
	local best: Point? = nil
	local bestIndex: number? = nil
	local bestDistance = math.huge
	for i, spot in spots do
		if baseY == nil or math.abs(spot.y - baseY) <= maxStep then
			local d = flat(from.x, from.z, spot.x, spot.z)
			if d < bestDistance then
				best, bestIndex, bestDistance = spot, i, d
			end
		end
	end
	return best, bestIndex
end

function GuideRoute.length(route: { Point }): number
	local total = 0
	for i = 2, #route do
		total += flat(route[i - 1].x, route[i - 1].z, route[i].x, route[i].z)
	end
	return total
end

-- The point of the route within [fromAlong, toAlong] closest to `p` on the ground plane: its distance along the
-- route and its distance from `p`. Ties go to the earlier point.
function GuideRoute.project(route: { Point }, p: Point, fromAlong: number?, toAlong: number?): (number, number)
	local lo = fromAlong or 0
	local hi = toAlong or math.huge
	if #route == 0 then
		return lo, math.huge
	elseif #route == 1 then
		return 0, flat(p.x, p.z, route[1].x, route[1].z)
	end
	local bestAlong, bestDistance = lo, math.huge
	local start = 0
	for i = 2, #route do
		local a, b = route[i - 1], route[i]
		local len = flat(a.x, a.z, b.x, b.z)
		if start > hi then
			break
		end
		if start + len >= lo then
			local t = 0
			if len > 1e-9 then
				t = ((p.x - a.x) * (b.x - a.x) + (p.z - a.z) * (b.z - a.z)) / (len * len)
			end
			local along = math.clamp(start + t * len, math.max(lo, start), math.min(hi, start + len))
			local k = if len > 1e-9 then (along - start) / len else 0
			local d = flat(p.x, p.z, a.x + (b.x - a.x) * k, a.z + (b.z - a.z) * k)
			if d < bestDistance - 1e-9 then
				bestAlong, bestDistance = along, d
			end
		end
		start += len
	end
	return bestAlong, bestDistance
end

function GuideRoute.advance(route: { Point }, p: Point, along: number, options: Options?): number
	local found = GuideRoute.project(route, p, along, along + option(options, "lookahead"))
	return math.max(along, found)
end

function GuideRoute.offRoute(route: { Point }, p: Point, along: number): number
	local _, distance = GuideRoute.project(route, p, along, math.huge)
	return distance
end

function GuideRoute.ahead(route: { Point }, along: number, from: Point): { Point }
	local out: { Point } = { from }
	local s = 0
	for i, point in route do
		if i > 1 then
			s += flat(route[i - 1].x, route[i - 1].z, point.x, point.z)
		end
		if s > along + 1e-6 or (i == #route and #out == 1) then
			table.insert(out, point)
		end
	end
	return out
end

function GuideRoute.reaches(route: { Point }, goal: Point, tolerance: number?): boolean
	local last = route[#route]
	if not last then
		return false
	end
	return flat(last.x, last.z, goal.x, goal.z) <= (tolerance or GuideRoute.DEFAULTS.reachTolerance)
end

function GuideRoute.backoff(failures: number, options: Options?): number
	if failures <= 0 then
		return 0
	end
	return math.min(option(options, "retryBase") * 2 ^ (failures - 1), option(options, "retryMax"))
end

function GuideRoute.shouldRecompute(state: RecomputeState, options: Options?): (boolean, string?)
	if state.paused then
		return false, "Paused"
	end
	if state.computing then
		return false, nil
	end
	if state.failures > 0 and state.sinceAttempt < GuideRoute.backoff(state.failures, options) then
		return false, nil
	end
	if not state.hasRoute then
		return true, "NoRoute"
	elseif state.offRoute > option(options, "offRoute") then
		return true, "OffRoute"
	elseif state.goalMoved > option(options, "goalMoved") then
		return true, "GoalMoved"
	elseif state.sinceAttempt >= option(options, "safetyRefresh") then
		return true, "Refresh"
	end
	return false, nil
end

-- Ground-arrow alpha near the goal: 0 within `arriveDistance`, 1 from `band` studs further out.
function GuideRoute.arrival(distance: number, arriveDistance: number, band: number?): number
	local width = band or ARRIVE_BAND
	if width <= 0 then
		return if distance > arriveDistance then 1 else 0
	end
	return math.clamp((distance - arriveDistance) / width, 0, 1)
end

return table.freeze(GuideRoute)
