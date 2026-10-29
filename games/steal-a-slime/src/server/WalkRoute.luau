--!strict
--[[
	WalkRoute (pure)

	The route a dropped slime walks back to the lane on (contract/slime-walk.md), round everything solid. The
	adapter (WorldView) passes a Probe of the world:

	* ground(x, z, fromY): the first solid surface below (x, fromY, z), nil for none
	* clear(from, to): whether a slime's body can move from foot spot `from` to `to` without touching anything it
	  can't step over (walls, props, rails, a table top: what is taller than a curb)
	* path(from, to, wide): the ground path the engine finds (waypoints after `from`, up to and including `to`), nil
	  for none; `wide` asks again with a wider agent (the engine only roughly keeps a big slime's distance from props)

	plan tries, in order:
	1. "path": the engine's path to the goal (the nearest lane point), when every leg of it is clear, or can be made
	   clear with one waypoint beside it (sidestep: round a solid prop the engine can't see, CanQuery off). A path
	   that can't is searched once more with a wider agent.
	2. "ledge": off a roof or the fountain: walk to an edge, drop off it (WalkHeight does the fall), then the path
	   from where it lands, or off the next ledge from there (up to MAX_DROPS). Low landings (the ground, not the
	   slide) come first; MAX_PATHS engine searches in all.
	3. nil ("none"): there is no clear way back, or only one MAX_DETOUR times longer than the straight line (the
	   fountain's dome: down the whole slide). The caller pops it onto the lane.
]]

local WalkRoute = {}

export type P = { x: number, y: number, z: number }

export type Probe = {
	ground: (x: number, z: number, fromY: number) -> number?,
	clear: (from: P, to: P) -> boolean,
	path: (from: P, to: P, wide: boolean) -> { P }?,
}

export type Options = {
	speed: number, -- studs / s it walks at (it keeps walking while it falls)
	gravity: number, -- studs / s^2 (WalkHeight.GRAVITY)
	stepUp: number, -- WalkHeight.STEP_UP
	stepDown: number, -- WalkHeight.STEP_DOWN
}

WalkRoute.DIRECTIONS = 16 -- directions searched for a ledge to drop off
WalkRoute.REACH = 40 -- studs from the start a ledge may be
WalkRoute.STEP = 1 -- studs between ground samples on the way to a ledge
WalkRoute.LAND_PAST = 1.5 -- studs past where the fall carries it that it lands (clear of the edge it fell off)
WalkRoute.LEDGE_TRIES = 4 -- ledges tried at each height
WalkRoute.MAX_DROPS = 3 -- ledges in a row it may drop off (a tiered roof, the fountain's dome then the slide)
WalkRoute.MAX_PATHS = 12 -- engine path searches per plan (each one can take a while)
WalkRoute.SIDESTEPS = { 2, 4, 6, 8, 10 } -- studs a waypoint is shifted to go round a prop the engine can't see
WalkRoute.SIDESTEP_AT = { 0.5, 0.25, 0.75 } -- where along the blocked leg the shifted waypoint may go
WalkRoute.MAX_DETOUR = 3 -- a route this many times the straight line (at least REACH) is too far round: none
WalkRoute.LIP = 2.5 -- studs past the edge the fall is checked from (a slime's half width plus a little)
WalkRoute.LOW_WEIGHT = 4 -- score per stud of landing height: a ledge onto the ground beats one onto the slide

local function flat(a: P, b: P): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
end

-- Whether every leg of start, points[1], points[2], ... is clear.
function WalkRoute.walkable(start: P, points: { P }, probe: Probe): boolean
	local prev = start
	for _, p in points do
		if not probe.clear(prev, p) then
			return false
		end
		prev = p
	end
	return true
end

-- A point beside the leg a -> b that makes both halves clear (round a prop the engine can't see), or nil: shifted
-- SIDESTEPS studs either way, at each of SIDESTEP_AT along the leg.
function WalkRoute.sidestep(a: P, b: P, probe: Probe): P?
	local dx, dz = b.x - a.x, b.z - a.z
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-3 then
		return nil
	end
	local px, pz = -dz / len, dx / len
	for _, k in WalkRoute.SIDESTEPS do
		for _, at in WalkRoute.SIDESTEP_AT do
			for _, side in { 1, -1 } do
				local m = {
					x = a.x + dx * at + px * k * side,
					y = a.y + (b.y - a.y) * at,
					z = a.z + dz * at + pz * k * side,
				}
				if probe.clear(a, m) and probe.clear(m, b) then
					return m
				end
			end
		end
	end
	return nil
end

-- `points` (after `start`) with a sidestep into every leg that is not clear, or nil when one can't be mended.
function WalkRoute.mend(start: P, points: { P }, probe: Probe): { P }?
	local out: { P } = {}
	local prev = start
	for _, p in points do
		if not probe.clear(prev, p) then
			local m = WalkRoute.sidestep(prev, p, probe)
			if not m then
				return nil
			end
			table.insert(out, m)
		end
		table.insert(out, p)
		prev = p
	end
	return out
end

export type Ledge = {
	edge: P, -- the last spot on the high ground
	lip: P, -- LIP studs out past the edge, at its height: the fall is checked from here (clear of the edge's corner)
	landing: P, -- where it lands, on the ground below
}

-- Ledges round `start`: in each of DIRECTIONS, walking out over the ground it is on (steps it can take) up to
-- REACH, the first spot where the ground drops more than stepDown. The landing is where the fall carries it (it
-- keeps walking at `speed` while it falls) plus LAND_PAST.
function WalkRoute.ledges(start: P, probe: Probe, opts: Options): { Ledge }
	local out: { Ledge } = {}
	for k = 0, WalkRoute.DIRECTIONS - 1 do
		local a = 2 * math.pi * k / WalkRoute.DIRECTIONS
		local dx, dz = math.cos(a), math.sin(a)
		local prev = start
		local d = WalkRoute.STEP
		while d <= WalkRoute.REACH do
			local x, z = start.x + dx * d, start.z + dz * d
			local g = probe.ground(x, z, prev.y + opts.stepUp)
			if g == nil then
				break -- off the map
			end
			if g < prev.y - opts.stepDown then
				local drop = prev.y - g
				local carry = opts.speed * math.sqrt(2 * drop / opts.gravity) + WalkRoute.LAND_PAST
				local lx, lz = prev.x + dx * carry, prev.z + dz * carry
				local lg = probe.ground(lx, lz, prev.y)
				if lg and lg < prev.y - opts.stepDown then
					table.insert(out, {
						edge = prev,
						lip = {
							x = prev.x + dx * math.min(WalkRoute.LIP, carry),
							y = prev.y,
							z = prev.z + dz * math.min(WalkRoute.LIP, carry),
						},
						landing = { x = lx, y = lg, z = lz },
					})
				end
				break
			end
			prev = { x = x, y = g, z = z }
			d += WalkRoute.STEP
		end
	end
	return out
end

-- The route (points after `start`, the last one `goal`) and how it was found, or nil and "none".
function WalkRoute.plan(start: P, goal: P, probe: Probe, opts: Options): ({ P }?, string)
	local paths = 0 -- engine searches so far (each one can take a while): at most MAX_PATHS
	local function pathTo(from: P, to: P): { P }?
		for _, wide in { false, true } do
			if paths >= WalkRoute.MAX_PATHS then
				return nil
			end
			paths += 1
			local path = probe.path(from, to, wide)
			if path == nil then
				return nil -- no way at all: a wider agent won't find one either
			end
			local mended = if #path > 0 then WalkRoute.mend(from, path, probe) else nil
			if mended then
				return mended
			end
		end
		return nil
	end
	-- a way round that is MAX_DETOUR times the straight line or more is no way back (down the whole slide, say)
	local function short(route: { P }): boolean
		local length, prev = 0, start
		for _, q in route do
			length += flat(prev, q)
			prev = q
		end
		return length <= WalkRoute.MAX_DETOUR * math.max(flat(start, goal), WalkRoute.REACH)
	end

	local path = pathTo(start, goal)
	if path and short(path) then
		return path, "path"
	end

	-- Off a ledge, and off the next one from where it lands (a tiered roof, the fountain's dome then the slide), up
	-- to MAX_DROPS: the best LEDGE_TRIES ledges at each height.
	local function descend(from: P, drops: number): { P }?
		if drops > WalkRoute.MAX_DROPS then
			return nil
		end
		local ledges = WalkRoute.ledges(from, probe, opts)
		local function score(l: Ledge): number
			return l.landing.y * WalkRoute.LOW_WEIGHT + flat(l.landing, goal) + flat(from, l.edge)
		end
		table.sort(ledges, function(a, b)
			return score(a) < score(b)
		end)
		local tries = 0
		for _, l in ledges do
			if tries >= WalkRoute.LEDGE_TRIES or paths >= WalkRoute.MAX_PATHS then
				break
			end
			if probe.clear(from, l.edge) and probe.clear(l.edge, l.lip) and probe.clear(l.lip, l.landing) then
				tries += 1
				local rest = pathTo(l.landing, goal) or descend(l.landing, drops + 1)
				if rest then
					local route = { l.edge, l.landing }
					table.move(rest, 1, #rest, 3, route)
					return route
				end
			end
		end
		return nil
	end

	local down = descend(start, 1)
	if down and short(down) then
		return down, "ledge"
	end
	return nil, "none"
end

return WalkRoute
