--!strict
--[[
	JarRoute (pure)

	The walk out of a goo jar tower for a slime dropped on an upper floor
	(contract/slime-walk.md). Roblox pathfinding can't use the jar stair (a
	tight spiral round the centre post, finer than its navmesh), so this
	builds that leg from the layout: round the deck to the top of the stair,
	down the spiral (one unbroken helix from the ground floor to the top jar,
	climbing FLOOR_HEIGHT per turn) and off it on the ground floor. The
	server's pathfinding takes it from there (out of the door to the lane).

	Points are plot-local (x, z) pairs, the same frame WorldLayout builds a
	plot in: jar centre at the origin, angle a at (cos a, sin a).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Layout = if Shared then require(Shared.Parent.Visuals.WorldLayout) else require("../visuals/shared/WorldLayout")
local WorldLayout = Layout

local JarRoute = {}

JarRoute.DECK_RADIUS = 8.5 -- the ring a slime walks round the deck on: clear of the stair hole and the pad stands
JarRoute.ENTER = 15 -- degrees before the stair's top where it steps on (inside the rail's open end)
JarRoute.STEP_OFF = 15 -- degrees past the stair's foot where it steps off on the ground floor (inside the open start)
JarRoute.ARC_STEP = 15 -- degrees between route points on the deck ring and the spiral

local function polar(r: number, deg: number): (number, number)
	local a = math.rad(deg)
	return r * math.cos(a), r * math.sin(a)
end

-- Angle (degrees) where every floor's stair starts and the one below arrives: the spiral's foot on the ground floor.
function JarRoute.footAngle(): number
	return WorldLayout.treadAngle(1, 1) - WorldLayout.STAIR.angle
end

local function push(out: { number }, x: number, z: number)
	table.insert(out, x)
	table.insert(out, z)
end

-- Points from angle `from` to `to` (degrees, unwrapped, either way round) at radius r, `from` left out.
local function arc(out: { number }, r: number, from: number, to: number)
	local steps = math.ceil(math.abs(to - from) / JarRoute.ARC_STEP)
	for i = 1, steps do
		push(out, polar(r, from + (to - from) * i / steps))
	end
end

--[[
	The route (flat plot-local x, z) from a slime at plot-local (x, y, z)
	down to the ground floor, ending just off the spiral's foot. nil on the
	ground floor or outside the glass of the jar at that height.
]]
function JarRoute.down(x: number, y: number, z: number): { number }?
	local floor = WorldLayout.floorAt(y)
	local r = math.sqrt(x * x + z * z)
	if floor <= 1 or r > WorldLayout.jarRadius(floor) then
		return nil
	end
	local foot = JarRoute.footAngle()
	local out = {}
	local deck = JarRoute.DECK_RADIUS
	local at = math.deg(math.atan2(z, x))
	if r > deck then
		push(out, polar(deck, at))
	end
	-- Round the deck the short way to just before the top of the stair (it arrives at the foot angle, mod 360).
	local enter = foot - JarRoute.ENTER
	local delta = (enter - at + 180) % 360 - 180
	arc(out, deck, at, at + delta)
	-- Down the helix (it climbs as the angle grows), floor - 1 turns, at the radius feet go.
	local walk = WorldLayout.RAMP.walk
	local top = enter + (floor - 1) * 360
	local bottom = foot + JarRoute.STEP_OFF
	push(out, polar(walk, top))
	arc(out, walk, top, bottom)
	push(out, polar(deck, bottom))
	return out
end

return JarRoute
