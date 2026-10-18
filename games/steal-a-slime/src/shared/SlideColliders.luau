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
	kind: "Floor" | "Fill" | "Skirt" | "Joint" | "Post" | "Brace",
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
SlideColliders.END_EXTRA = 0.175 -- the slide head end reaches this far past the path
SlideColliders.MOUTH_EXTRA = 0.5 -- the mouth end: the kit's end cap is square to the TRUE tangent, the last chord is a few degrees off it, so its far corner is up to 0.4 past a square-ended slab
SlideColliders.FOLDER = "SlideColliders" -- under Map.Volcano
SlideColliders.POST_SIDE = 2.3 -- kit supports(): a low post stands this far to each side of the centreline
SlideColliders.POST_WIDTH = 1.3 -- the kit's 6-sided post is 1.2 across its corners
SlideColliders.POST_MAX_Y = 9 -- kit supports(): a trough bottom up to here rests on ground posts, above it hangs off the staves
SlideColliders.BRACE_WIDTH = 1.1 -- the kit's beam is 0.9 wide, its strut 0.8
SlideColliders.BRACE_DROP = 4.5 -- the strut's foot is this far under the beam
SlideColliders.BRACE_REACH = 3.4 -- a bracket collider stops this far from the centreline: the fill (4.3 half-width plus the walls) takes over

local function normalize(x: number, y: number, z: number): Vec
	local len = math.sqrt(x * x + y * y + z * z)
	return { x / len, y / len, z / len }
end

-- Mouth flare 0..1 at path fraction f (kit slide(): smoothstep over the last 10 %).
local function flare(f: number): number
	local m = math.clamp((f - (1 - SlideColliders.MOUTH_SHARE)) / SlideColliders.MOUTH_SHARE, 0, 1)
	return m * m * (3 - 2 * m)
end

-- FEATURES.SlidePCD: the slide mesh (fountain_split_slide, PreciseConvexDecomposition) is the real trough floor, rims, posts and
-- braces (probe pipeline/probes/slidepcd/pcd-final.json: every wall and support cast blocked), so these boxes go. What stays: the
-- Fill (+ ridge roof, +JointFill), because the PCD trough is a walkable ramp (14.5 deg max against MaxSlopeAngle 89, rims only
-- 0.9..2.2 studs, the mouth ~1 stud above ground), and the Skirt, because the thin trough shell leaves a 5.7+ stud gap to walk under.
SlideColliders.PCD_RETIRED = table.freeze({ Floor = true, Joint = true, Post = true, Brace = true })

function SlideColliders.withoutPcd(specs: { Spec }): { Spec }
	local out: { Spec } = {}
	for _, spec in specs do
		if not SlideColliders.PCD_RETIRED[spec.kind] then
			table.insert(out, spec)
		end
	end
	return out
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
		-- slime emerges from below, and the mouth) only END_EXTRA / MOUTH_EXTRA.
		local before = if i > 1 then SlideColliders.OVERLAP / 2 else SlideColliders.END_EXTRA
		local after = if i < n - 1 then SlideColliders.OVERLAP / 2 else SlideColliders.MOUTH_EXTRA
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

-- The roof of a Fill spec. The Fill itself stays a plain box from the ride line up FILL studs (nobody can jump into the channel);
-- the roof sits ON TOP of it (server/FountainColliders builds it as two WedgeParts): both faces fall from the ridge on the
-- centreline (`height` above the ride line = FILL + rise) to the box top at the side edges (`half` out, `base` = FILL above the ride
-- line), at `angle` degrees from flat. rise = half * tan(RIDGE_ANGLE), so every face is exactly RIDGE_ANGLE steep (wider mouth
-- fills just get a taller ridge).
function SlideColliders.ridge(spec: Spec): { half: number, base: number, rise: number, height: number, angle: number }
	local half = spec.size[1] / 2
	local rise = half * math.tan(math.rad(SlideColliders.RIDGE_ANGLE))
	return {
		half = half,
		base = SlideColliders.FILL,
		rise = rise,
		height = SlideColliders.FILL + rise,
		angle = math.deg(math.atan2(rise, half)),
	}
end

-- Placement of the roof wedge of a Fill spec on `side` (-1 left / +1 right of the centreline). ASSUMPTION about Roblox WedgePart
-- (verified in Studio by the bug9-slide-top-drop shot): in its local frame the triangle lies in the Y/Z plane, the vertical face is the
-- +Z side and the slope falls from the top of that face (+Y, +Z) to the bottom front edge (-Y, -Z), so the slope's outward normal is
-- (0, Z, -Y) normalised. The wedge Z axis is therefore put toward the centreline (the tall face on the ridge), Y = the spec's up
-- and X = Y x Z (right-handed, along the slide). Returns the centre, the basis (x, y, z) and the Size ({ x, y, z }).
function SlideColliders.wedge(spec: Spec, side: number): { pos: Vec, x: Vec, y: Vec, z: Vec, size: Vec }
	local r = SlideColliders.ridge(spec)
	local right, up = frameOf(spec)
	local z = { -side * right[1], -side * right[2], -side * right[3] }
	local x = {
		up[2] * z[3] - up[3] * z[2],
		up[3] * z[1] - up[1] * z[3],
		up[1] * z[2] - up[2] * z[1],
	}
	local out = r.half / 2 * side
	local lift = SlideColliders.FILL / 2 + r.rise / 2 -- from the box centre (FILL / 2 over the ride line) to the wedge centre
	return {
		pos = {
			spec.centre[1] + right[1] * out + up[1] * lift,
			spec.centre[2] + right[2] * out + up[2] * lift,
			spec.centre[3] + right[3] * out + up[3] * lift,
		},
		x = x,
		y = up,
		z = z,
		size = { spec.size[3], r.rise, r.half },
	}
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

-- The kit wall_r(z): the stave radius (barrel bulge) the brackets start from.
local function wallRadius(y: number): number
	return 11.2 + 0.5 * math.sin(math.pi * math.clamp((y - 2.4) / (30 - 2.4), 0, 1))
end

-- Colliders for what holds the slide up, which the floor / fill / skirt blocks leave out (the kit's supports()): the ground posts
-- under a trough bottom between WALK_UNDER and POST_MAX_Y (a lower one is inside its skirt) and, with `full`, every bracket
-- (beam + strut, from the staves to the slab's edge). `kit` is the ride line sampled like the kit mesh (WorldLayout.slidePath
-- (KIT_SLIDE_SAMPLES)); the supports sit at the same samples, spaced like the kit does. `base` is build() (a post already held by a
-- floor or skirt is dropped).
function SlideColliders.supports(kit: { Vec }, base: { Spec }, full: boolean?): { Spec }
	local out: { Spec } = {}
	local n = #kit
	local last = -99
	for k = 1, n do
		local i = k - 1 -- the kit's 0-based sample index
		if i - last < 6 or i < 5 then
			continue
		end
		last = i
		local p, a, b = kit[k], kit[math.max(k - 1, 1)], kit[math.min(k + 1, n)]
		local t = normalize(b[1] - a[1], b[2] - a[2], b[3] - a[3])
		local lat = normalize(-t[3], 0, t[1])
		local up = {
			lat[2] * t[3] - lat[3] * t[2],
			lat[3] * t[1] - lat[1] * t[3],
			lat[1] * t[2] - lat[2] * t[1],
		}
		local under = {
			p[1] - up[1] * SlideColliders.FLOOR,
			p[2] - up[2] * SlideColliders.FLOOR,
			p[3] - up[3] * SlideColliders.FLOOR,
		}
		if under[2] <= SlideColliders.POST_MAX_Y then
			for _, side in { -1, 1 } do
				local x = under[1] + lat[1] * side * SlideColliders.POST_SIDE
				local y = under[2] + lat[2] * side * SlideColliders.POST_SIDE
				local z = under[3] + lat[3] * side * SlideColliders.POST_SIDE
				local height = y + 0.2
				local post: Spec = {
					name = `SlidePost{i}{if side < 0 then "L" else "R"}`,
					kind = "Post",
					segment = k,
					centre = { x, height / 2, z },
					forward = { 0, 0, 1 },
					size = { SlideColliders.POST_WIDTH, height, SlideColliders.POST_WIDTH },
				}
				local held = false
				for _, other in base do
					if (other.kind == "Floor" or other.kind == "Skirt") and SlideColliders.contains(other, post) then
						held = true
						break
					end
				end
				if not held then
					table.insert(out, post)
				end
			end
		elseif full then
			local beamY = under[2] - 0.45
			local radius = math.sqrt(under[1] ^ 2 + under[3] ^ 2)
			local from, to = wallRadius(beamY) - 0.3, radius - SlideColliders.BRACE_REACH
			if to > from then
				local dx, dz = under[1] / radius, under[3] / radius
				local mid = (from + to) / 2
				local height = SlideColliders.BRACE_DROP + 0.45
				table.insert(out, {
					name = `SlideBrace{i}`,
					kind = "Brace",
					segment = k,
					centre = { dx * mid, beamY + 0.45 - height / 2, dz * mid },
					forward = { dx, 0, dz },
					size = { SlideColliders.BRACE_WIDTH, height, to - from },
				})
			end
		end
	end
	return out
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

-- Everything the live server places: the solid block (build) plus the supports.
function SlideColliders.all(path: { Vec }, kit: { Vec }, full: boolean?, pcd: boolean?): { Spec }
	local out = SlideColliders.build(path, full)
	for _, spec in SlideColliders.supports(kit, out, full) do
		table.insert(out, spec)
	end
	if pcd then
		return SlideColliders.withoutPcd(out)
	end
	return out
end

return SlideColliders
