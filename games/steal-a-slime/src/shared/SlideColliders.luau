--!strict
--[[
	SlideColliders (pure)

	Invisible collision for the fountain slide, which the visual-only fountain
	mesh and the non-colliding Chute stand-in leave open: players walked
	straight through the trough and its posts, and (playtest B6) fell through
	everything above FountainRide.LOW_SLIDE_Y, which had no colliders at all.
	build(path, true) covers the FULL path, top to mouth (FEATURES.SlideCollision);
	build(path) / false keeps the old low-only stretch.

	Per slide segment a -> b (WorldLayout.SLIDE_PATH, kit trough profile
	models/slime_fountain.py: half-width HW, lip LIP above the floor, floor
	BOT thick, the last 10 % flared 20 % wider and 45 % lower):
	  SlideFloor<i>   the trough floor, its top exactly on the ride line, deep
	                  enough to meet the skirt under the segment's high end;
	  SlideWallL<i> / SlideWallR<i>  the side walls, BOT below the floor up
	                  to the lip, outside the slime's lane;
	  SlideSkirt<i>   ground up to the trough bottom wherever it is too low to
	                  walk under (the posts), so nobody walks into the slide.
	Nothing sits on or above the ride line: the slime rides on the floor
	top between the walls (FountainRide), and slimes are anchored and never
	collide anyway.

	Specs are plain tables (centre, forward, size as X width, Y height, Z
	length along `forward`); server/FountainColliders turns them into Parts.
]]

local FountainRide = if script then require(script.Parent.FountainRide) else require("./FountainRide")

export type Vec = { number }
export type Spec = {
	name: string,
	kind: "Floor" | "Wall" | "Skirt" | "Joint",
	segment: number, -- path index i of the segment i -> i + 1 (a Joint: of the join at path[i + 1])
	centre: Vec,
	forward: Vec, -- unit; CFrame.lookAt(centre, centre + forward)
	size: Vec, -- { width, height, length }
}

local SlideColliders = {}

SlideColliders.HALF_WIDTH = 3.5 -- kit HW
SlideColliders.LIP = 1.9 -- kit LIP: wall top above the floor
SlideColliders.FLOOR = 0.7 -- kit -BOT: trough bottom below the floor top
SlideColliders.WALL = 0.6 -- kit HW - IW: wall thickness
SlideColliders.MOUTH_SHARE = 0.1 -- last share of the path that flares into the mouth
SlideColliders.WALK_UNDER = 6 -- trough bottoms lower than this get a skirt (no walking under)
SlideColliders.MIN_THICK = 4 -- floor slab never thinner than this (a falling player moves ~2 studs a frame)
SlideColliders.WALL_EXTRA = 1.5 -- walls stand this far above the kit lip: a bouncing player / ball cannot hop out on a bend
SlideColliders.JOINT_LENGTH = 3 -- joint filler floor: at least this long along the bisector of the two segments it joins
SlideColliders.OVERLAP = 0.35 -- extra length so neighbouring segments close their joints
SlideColliders.FOLDER = "SlideColliders" -- under Map.Volcano

local function normalize(x: number, y: number, z: number): Vec
	local len = math.sqrt(x * x + y * y + z * z)
	return { x / len, y / len, z / len }
end

-- Mouth flare 0..1 at path fraction f (kit slide(): smoothstep over the last 10 %).
local function flare(f: number): number
	local m = math.clamp((f - (1 - SlideColliders.MOUTH_SHARE)) / SlideColliders.MOUTH_SHARE, 0, 1)
	return m * m * (3 - 2 * m)
end

-- True for the segment a -> b that gets colliders.
function SlideColliders.isLow(a: Vec, b: Vec): boolean
	return math.min(a[2], b[2]) <= FountainRide.LOW_SLIDE_Y
end

function SlideColliders.build(path: { Vec }, full: boolean?): { Spec }
	local out: { Spec } = {}
	local n = #path
	for i = 1, n - 1 do
		local a, b = path[i], path[i + 1]
		if not full and not SlideColliders.isLow(a, b) then
			continue
		end
		local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
		local length = math.sqrt(dx * dx + dy * dy + dz * dz)
		if length < 1e-3 then
			continue
		end
		local f = normalize(dx, dy, dz)
		-- lookAt frame: right is horizontal, up = right x forward.
		local right = normalize(-f[3], 0, f[1])
		local up = {
			right[2] * f[3] - right[3] * f[2],
			right[3] * f[1] - right[1] * f[3],
			right[1] * f[2] - right[2] * f[1],
		}
		local m = flare((i - 0.5) / (n - 1))
		local half = SlideColliders.HALF_WIDTH * (1 + 0.2 * m)
		local lip = SlideColliders.LIP * (1 - 0.45 * m)
		local mid = { (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2 }
		local long = length + SlideColliders.OVERLAP
		local function at(side: number, lift: number): Vec
			return {
				mid[1] + right[1] * side + up[1] * lift,
				mid[2] + right[2] * side + up[2] * lift,
				mid[3] + right[3] * side + up[3] * lift,
			}
		end
		-- Floor: top on the ride line, deep enough under the high end to
		-- overlap the skirt (flat-topped at the low end's trough bottom).
		local thick = math.max(SlideColliders.FLOOR + math.abs(dy) + 0.2, SlideColliders.MIN_THICK)
		table.insert(out, {
			name = `SlideFloor{i}`,
			kind = "Floor",
			segment = i,
			centre = at(0, -thick / 2),
			forward = f,
			size = { half * 2, thick, long },
		})
		local wallHeight = lip + SlideColliders.FLOOR + SlideColliders.WALL_EXTRA
		local wallLift = (lip + SlideColliders.WALL_EXTRA - SlideColliders.FLOOR) / 2
		for _, side in { { name = "L", sign = -1 }, { name = "R", sign = 1 } } do
			table.insert(out, {
				name = `SlideWall{side.name}{i}`,
				kind = "Wall",
				segment = i,
				centre = at(side.sign * (half - SlideColliders.WALL / 2), wallLift),
				forward = f,
				size = { SlideColliders.WALL, wallHeight, long },
			})
		end
		-- Skirt: ground up to the trough bottom where it is too low to walk under.
		local bottom = math.min(a[2], b[2]) - SlideColliders.FLOOR
		if bottom > 0.05 and bottom <= SlideColliders.WALK_UNDER then
			table.insert(out, {
				name = `SlideSkirt{i}`,
				kind = "Skirt",
				segment = i,
				centre = { mid[1], bottom / 2, mid[3] },
				forward = normalize(dx, 0, dz),
				size = { half * 2, bottom, math.sqrt(dx * dx + dz * dz) + SlideColliders.OVERLAP },
			})
		end
	end
	-- Joint fillers: segment boxes are straight, so on a bend the outer edge of two
	-- neighbours opens a wedge (HW * tan(turn / 2) deep each side of the join) that
	-- the end overlap does not close: a ball rolling the bend hit the wedge's
	-- corner and left the trough (B6). A floor slab on the bisector frame of the
	-- join plugs it, and a wall piece on the bend's OUTER side (the inner walls
	-- already overlap) keeps the outer wall unbroken.
	for i = 2, n - 1 do
		local a, b, c = path[i - 1], path[i], path[i + 1]
		if not full and not (SlideColliders.isLow(a, b) and SlideColliders.isLow(b, c)) then
			continue
		end
		local d1 = normalize(b[1] - a[1], b[2] - a[2], b[3] - a[3])
		local d2 = normalize(c[1] - b[1], c[2] - b[2], c[3] - b[3])
		local cosTurn = d1[1] * d2[1] + d1[2] * d2[2] + d1[3] * d2[3]
		if cosTurn < -0.99 then
			continue
		end
		local f = normalize(d1[1] + d2[1], d1[2] + d2[2], d1[3] + d2[3])
		local right = normalize(-f[3], 0, f[1])
		local up = {
			right[2] * f[3] - right[3] * f[2],
			right[3] * f[1] - right[1] * f[3],
			right[1] * f[2] - right[2] * f[1],
		}
		local m = flare((i - 1) / (n - 1))
		local half = SlideColliders.HALF_WIDTH * (1 + 0.2 * m)
		local lip = SlideColliders.LIP * (1 - 0.45 * m)
		local reach = half * math.sqrt((1 - cosTurn) / (1 + cosTurn)) -- tan(turn / 2) * half
		local function at(side: number, lift: number): Vec
			return {
				b[1] + right[1] * side + up[1] * lift,
				b[2] + right[2] * side + up[2] * lift,
				b[3] + right[3] * side + up[3] * lift,
			}
		end
		local thick = SlideColliders.MIN_THICK
		table.insert(out, {
			name = `SlideJoint{i - 1}`,
			kind = "Joint",
			segment = i - 1,
			centre = at(0, -thick / 2),
			forward = f,
			size = { half * 2, thick, math.max(SlideColliders.JOINT_LENGTH, 2 * reach + 1) },
		})
		-- Outer side: the side the path turns away from (d2 leans toward the inner side).
		local outer = if d2[1] * right[1] + d2[3] * right[3] > 0 then -1 else 1
		local wallHeight = lip + SlideColliders.FLOOR + SlideColliders.WALL_EXTRA
		local wallLift = (lip + SlideColliders.WALL_EXTRA - SlideColliders.FLOOR) / 2
		table.insert(out, {
			name = `SlideJointWall{if outer < 0 then "L" else "R"}{i - 1}`,
			kind = "Wall",
			segment = i - 1,
			centre = at(outer * (half - SlideColliders.WALL / 2), wallLift),
			forward = f,
			size = { SlideColliders.WALL, wallHeight, 2 * reach + 1 },
		})
	end
	return out
end

return SlideColliders
