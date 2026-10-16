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
	                  up INTO the ceiling slab (no slot), 2 studs thick (the trough edge
	                  to WALL_OUT past it), outside the slime's lane;
	  SlideCeiling<i> an invisible guard CEILING above the floor, over the
	                  walls too: nothing leaves the slide upward;
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
	kind: "Floor" | "Wall" | "Skirt" | "Joint" | "Ceiling",
	segment: number, -- path index i of the segment i -> i + 1 (a Joint: of the join at path[i + 1])
	centre: Vec,
	forward: Vec, -- unit; CFrame.lookAt(centre, centre + forward)
	size: Vec, -- { width, height, length }
}

local SlideColliders = {}

SlideColliders.HALF_WIDTH = 3.5 -- kit HW
SlideColliders.LIP = 1.9 -- kit LIP: wall top above the floor
SlideColliders.FLOOR = 0.7 -- kit -BOT: trough bottom below the floor top
SlideColliders.WALL = 0.6 -- kit HW - IW: the wall's inner part (inside the trough width)
SlideColliders.WALL_OUT = 1.4 -- the wall goes this far past the trough edge too: 2 studs thick in all, a fast ball cannot tunnel it
SlideColliders.MOUTH_SHARE = 0.1 -- last share of the path that flares into the mouth
SlideColliders.WALK_UNDER = 6 -- trough bottoms lower than this get a skirt (no walking under)
SlideColliders.MIN_THICK = 4 -- floor slab never thinner than this (a falling player moves ~2 studs a frame)
SlideColliders.WALL_EXTRA = 4 -- (unused by the walls now: they run up to the ceiling) old wall extra above the kit lip
SlideColliders.CEILING = 9 -- invisible ceiling guard: its underside this far above the floor top (a standing player + jump fits, nothing leaves upward)
SlideColliders.CEILING_THICK = 2
SlideColliders.WALL_TO_CEILING = 0.5 -- walls reach this far INTO the ceiling slab: the tube has no slot between wall top and ceiling (B6 round 4)
SlideColliders.JOINT_MARGIN = 1.5 -- joint walls reach this much further along both segments than the joint floor
SlideColliders.JOINT_LENGTH = 4 -- joint filler floor: at least this long along the bisector of the two segments it joins
SlideColliders.OVERLAP = 0.8 -- extra length so neighbouring segments close their joints (0.4 past each join: a pitch change leaves a ledge of at most 0.4 * tan(5 deg))
SlideColliders.END_EXTRA = 0.175 -- the slide head / mouth end reaches this far past the path
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
		local mid = { (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2 }
		-- Each slab reaches OVERLAP / 2 past a join; the free ends (the slide head, where the
		-- slime emerges from below, and the mouth) only END_EXTRA.
		local before = if i > 1 then SlideColliders.OVERLAP / 2 else SlideColliders.END_EXTRA
		local after = if i < n - 1 then SlideColliders.OVERLAP / 2 else SlideColliders.END_EXTRA
		local long = length + before + after
		local shift = (after - before) / 2
		local function at(side: number, lift: number): Vec
			return {
				mid[1] + right[1] * side + up[1] * lift + f[1] * shift,
				mid[2] + right[2] * side + up[2] * lift + f[2] * shift,
				mid[3] + right[3] * side + up[3] * lift + f[3] * shift,
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
		local wallTop = SlideColliders.CEILING + SlideColliders.WALL_TO_CEILING -- above the floor top: into the ceiling
		local wallHeight = wallTop + SlideColliders.FLOOR
		local wallLift = (wallTop - SlideColliders.FLOOR) / 2
		local wallThick = SlideColliders.WALL + SlideColliders.WALL_OUT
		local wallOffset = half + (SlideColliders.WALL_OUT - SlideColliders.WALL) / 2
		for _, side in { { name = "L", sign = -1 }, { name = "R", sign = 1 } } do
			table.insert(out, {
				name = `SlideWall{side.name}{i}`,
				kind = "Wall",
				segment = i,
				centre = at(side.sign * wallOffset, wallLift),
				forward = f,
				size = { wallThick, wallHeight, long },
			})
		end
		-- Ceiling guard: nothing leaves the slide upward either.
		table.insert(out, {
			name = `SlideCeiling{i}`,
			kind = "Ceiling",
			segment = i,
			centre = at(0, SlideColliders.CEILING + SlideColliders.CEILING_THICK / 2),
			forward = f,
			size = { (half + SlideColliders.WALL_OUT) * 2, SlideColliders.CEILING_THICK, long },
		})
		-- Skirt: ground up to the trough bottom where it is too low to walk under.
		local bottom = math.min(a[2], b[2]) - SlideColliders.FLOOR
		if bottom > 0.05 and bottom <= SlideColliders.WALK_UNDER then
			table.insert(out, {
				name = `SlideSkirt{i}`,
				kind = "Skirt",
				segment = i,
				centre = { mid[1], bottom / 2, mid[3] },
				forward = normalize(dx, 0, dz),
				size = { half * 2, bottom, math.sqrt(dx * dx + dz * dz) + 0.35 },
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
			size = { half * 2, thick, math.max(SlideColliders.JOINT_LENGTH, 2 * reach + 2) },
		})
		-- Walls on BOTH sides (the outer one closes the wedge, the inner one the overlap
		-- of two thick walls), and the ceiling guard across the join.
		local wallTop = SlideColliders.CEILING + SlideColliders.WALL_TO_CEILING -- above the floor top: into the ceiling
		local wallHeight = wallTop + SlideColliders.FLOOR
		local wallLift = (wallTop - SlideColliders.FLOOR) / 2
		local wallThick = SlideColliders.WALL + SlideColliders.WALL_OUT
		local wallOffset = half + (SlideColliders.WALL_OUT - SlideColliders.WALL) / 2
		local jointLength = math.max(SlideColliders.JOINT_LENGTH, 2 * reach + 2)
		local jointWallLength = jointLength + 2 * SlideColliders.JOINT_MARGIN
		for _, side in { { name = "L", sign = -1 }, { name = "R", sign = 1 } } do
			table.insert(out, {
				name = `SlideJointWall{side.name}{i - 1}`,
				kind = "Wall",
				segment = i - 1,
				centre = at(side.sign * wallOffset, wallLift),
				forward = f,
				size = { wallThick, wallHeight, jointWallLength },
			})
		end
		table.insert(out, {
			name = `SlideJointCeiling{i - 1}`,
			kind = "Ceiling",
			segment = i - 1,
			centre = at(0, SlideColliders.CEILING + SlideColliders.CEILING_THICK / 2),
			forward = f,
			size = { (half + SlideColliders.WALL_OUT) * 2, SlideColliders.CEILING_THICK, jointWallLength },
		})
	end
	return out
end

return SlideColliders
