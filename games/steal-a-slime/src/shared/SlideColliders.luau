--!strict
--[[
	SlideColliders (pure)

	Invisible collision for the fountain slide, which the visual-only fountain
	mesh and the non-colliding Chute stand-in leave open. The slide is NOT for
	players (Merijn #9: they walked up the trough and stood inside it): each
	segment is a SOLID block from under the trough floor up FILL studs above the
	ride line, so a player can neither enter the trough nor climb the slide, and
	the top of the block is out of a jump's reach (a jump clears about 7 studs).
	Slimes ride anchored and never collide (FountainRide), so they pass through
	the block. build(path, true) covers the FULL path, top to mouth
	(FEATURES.SlideCollision); build(path) / false keeps the low-only stretch.
	The fountain mesh itself is one MeshPart whose slide cannot be split off, so
	this stays hand-placed (docs/COLLISION.md).

	Per slide segment a -> b (WorldLayout.SLIDE_PATH, kit trough profile
	models/slime_fountain.py: half-width HW, floor BOT thick, the last 10 %
	flared 20 % wider and 45 % lower):
	  SlideFloor<i>   the trough floor slab, its top exactly on the ride line,
	                  deep enough to meet the skirt under the segment's high end;
	  SlideFill<i>    the solid from the ride line up FILL studs, as wide as the
	                  trough plus the old walls (nothing is hollow);
	  SlideSkirt<i>   ground up to the trough bottom wherever it is too low to
	                  walk under (the posts), so nobody walks into the slide.
	and a SlideJoint<i> floor plus a SlideJointFill<i> on every bend.

	Specs are plain tables (centre, forward, size as X width, Y height, Z
	length along `forward`); server/FountainColliders turns them into Parts.
]]

local FountainRide = if script then require(script.Parent.FountainRide) else require("./FountainRide")

export type Vec = { number }
export type Spec = {
	name: string,
	kind: "Floor" | "Fill" | "Skirt" | "Joint",
	segment: number, -- path index i of the segment i -> i + 1 (a Joint: of the join at path[i + 1])
	centre: Vec,
	forward: Vec, -- unit; CFrame.lookAt(centre, centre + forward)
	size: Vec, -- { width, height, length }
}

local SlideColliders = {}

SlideColliders.HALF_WIDTH = 3.5 -- kit HW
SlideColliders.LIP = 1.9 -- kit LIP: the visible trough lip above the floor
SlideColliders.FLOOR = 0.7 -- kit -BOT: trough bottom below the floor top
SlideColliders.WALL = -0.8 -- the floor slab reaches this far INSIDE the trough edge; negative = outside it (the solid is
-- wider than the visible trough, so the lip is never a step: HALF_WIDTH + 0.8 = 4.3 from the centreline)
SlideColliders.WALL_OUT = 2.8 -- the fill's outer face this far past the trough edge
SlideColliders.MOUTH_SHARE = 0.1 -- last share of the path that flares into the mouth
SlideColliders.WALK_UNDER = 6 -- trough bottoms lower than this get a skirt (no walking under)
SlideColliders.MIN_THICK = 4 -- floor slab never thinner than this (a falling player moves ~2 studs a frame)
SlideColliders.FILL = 11 -- the solid reaches this far above the ride line: a jump clears ~7 studs, so nobody gets on top of it
SlideColliders.RIDGE_ANGLE = 60 -- degrees: the fill's top is a ridge (roof) whose two faces are at least this steep (bug #9: nobody stays on top)
SlideColliders.JOINT_MARGIN = 1.5 -- a joint's fill reaches this much further along both segments than the joint floor
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

function SlideColliders.buildRaw(path: { Vec }, full: boolean?): { Spec }
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
			size = { (half - SlideColliders.WALL) * 2, thick, long },
		})
		-- Fill: solid from the ride line up, as wide as the old walls' outer faces.
		table.insert(out, {
			name = `SlideFill{i}`,
			kind = "Fill",
			segment = i,
			centre = at(0, SlideColliders.FILL / 2),
			forward = f,
			size = { (half + SlideColliders.WALL_OUT) * 2, SlideColliders.FILL, long },
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
	-- the end overlap does not close. A floor slab and a fill block on the bisector
	-- frame of the join plug it, so the solid is unbroken round every bend.
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
			size = { (half - SlideColliders.WALL) * 2, thick, math.max(SlideColliders.JOINT_LENGTH, 2 * reach + 2) },
		})
		local jointLength = math.max(SlideColliders.JOINT_LENGTH, 2 * reach + 2)
		-- (the last join sits at the ground by the mouth, where riding slimes walk off to their landing: its
		-- fill keeps to the joint floor's length there)
		local jointFillLength = jointLength + if i == n - 1 then 0 else 2 * SlideColliders.JOINT_MARGIN
		table.insert(out, {
			name = `SlideJointFill{i - 1}`,
			kind = "Fill",
			segment = i - 1,
			centre = at(0, SlideColliders.FILL / 2),
			forward = f,
			size = { (half + SlideColliders.WALL_OUT) * 2, SlideColliders.FILL, jointFillLength },
		})
	end
	return out
end

-- The roof of a Fill spec (server/FountainColliders builds it as two WedgeParts instead of one box): both faces fall from the
-- ridge on the centreline (`height` above the ride line) to the side edges (`half` out), at `angle` degrees from flat.
-- Height is FILL, or more where the mouth flare makes the fill wider than FILL / tan(RIDGE_ANGLE) allows.
function SlideColliders.ridge(spec: Spec): { half: number, height: number, angle: number }
	local half = spec.size[1] / 2
	local height = math.max(SlideColliders.FILL, half * math.tan(math.rad(SlideColliders.RIDGE_ANGLE)))
	return { half = half, height = height, angle = math.deg(math.atan2(height, half)) }
end

-- lookAt frame of a spec (right is horizontal, up = right x forward).
local function frameOf(spec: Spec): (Vec, Vec, Vec)
	local f = spec.forward
	local right = normalize(-f[3], 0, f[1])
	local up = {
		right[2] * f[3] - right[3] * f[2],
		right[3] * f[1] - right[1] * f[3],
		right[1] * f[2] - right[2] * f[1],
	}
	return right, up, f
end

-- True when every corner of `inner` lies inside `outer` (boxes are convex: then inner is a subset of outer).
function SlideColliders.contains(outer: Spec, inner: Spec): boolean
	local oRight, oUp, oF = frameOf(outer)
	local iRight, iUp, iF = frameOf(inner)
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local x, y, z = sx * inner.size[1] / 2, sy * inner.size[2] / 2, sz * inner.size[3] / 2
				local d = {
					inner.centre[1] + iRight[1] * x + iUp[1] * y + iF[1] * z - outer.centre[1],
					inner.centre[2] + iRight[2] * x + iUp[2] * y + iF[2] * z - outer.centre[2],
					inner.centre[3] + iRight[3] * x + iUp[3] * y + iF[3] * z - outer.centre[3],
				}
				if
					math.abs(d[1] * oRight[1] + d[2] * oRight[2] + d[3] * oRight[3]) > outer.size[1] / 2 + 1e-6
					or math.abs(d[1] * oUp[1] + d[2] * oUp[2] + d[3] * oUp[3]) > outer.size[2] / 2 + 1e-6
					or math.abs(d[1] * oF[1] + d[2] * oF[2] + d[3] * oF[3]) > outer.size[3] / 2 + 1e-6
				then
					return false
				end
			end
		end
	end
	return true
end

-- The colliders of build(), minus every skirt that a floor slab already holds whole (the lowest segments,
-- where the thick floor reaches the ground): the same solid volume in fewer Parts. The segments' boxes
-- point along a spiral, so no two of them are coplanar and none can be merged; dropping a box that
-- another contains is the only change that leaves the collision envelope exactly as it was.
function SlideColliders.build(path: { Vec }, full: boolean?): { Spec }
	local raw = SlideColliders.buildRaw(path, full)
	local out: { Spec } = {}
	for _, spec in raw do
		local held = false
		if spec.kind == "Skirt" then
			for _, other in raw do
				if other.kind == "Floor" and SlideColliders.contains(other, spec) then
					held = true
					break
				end
			end
		end
		if not held then
			table.insert(out, spec)
		end
	end
	return out
end

return SlideColliders
