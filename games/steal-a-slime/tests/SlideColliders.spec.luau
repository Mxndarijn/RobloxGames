--!nocheck
-- Fountain colliders (TODO 13, v27 playtest: players walked through the
-- fountain). The silo keeps its Basin / Trim / Silo colliders
-- (FountainCollider.spec); the low slide, which the visual-only mesh left
-- open, gets SlideColliders: floor, walls and skirts along SLIDE_PATH, on
-- in every mesh state. Checked here: the specs block a walking player at
-- the slide, every fountain collider leaves the slime ride path clear
-- (pure, 400 rolled rides), and in the real server (fake runtime, mesh
-- loaded and failed) the Parts exist, are solid, invisible and anchored,
-- survive the MeshSwap switch, and the riding slimes never collide.
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Fountain = require("../src/shared/Fountain")
local FountainRide = require("../src/shared/FountainRide")
local Rng = require("../src/shared/Rng")
local Runtime = require("../tools/livetest/Runtime")
local SlideColliders = require("../src/shared/SlideColliders")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")
local TOP_DIP = 1.0 -- deepest the slide's ride line sinks into the dome colliders (a steppable bump)

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local PATH = WorldLayout.SLIDE_PATH
local FP = WorldLayout.FOUNTAIN_PROFILE
local Config = require("../src/shared/Config")
local SPECS = SlideColliders.build(PATH, true)
local EPS = 1e-3
local RIDE_EPS = 0.1 -- see LIVE_EPS
local LIVE_EPS = 0.1 -- Part CFrames are float32, and a slab reaching 0.4 past a join leaves a ledge of at most ~0.1 above the next one's plane on the sharpest (55 degree) bends
local PLAYER_HEIGHT = 5 -- R15 character, feet to head
local BODY_LIFT = 1.5 -- body centre above the pivot for a size-1 slime

local function sub(a, b)
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end
local function dot(a, b): number
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end
local function normalize(v)
	local len = math.sqrt(dot(v, v))
	return { v[1] / len, v[2] / len, v[3] / len }
end

-- lookAt frame of a spec (same maths as CFrame.lookAt, no roll).
local function frame(spec)
	local f = spec.forward
	local right = normalize({ -f[3], 0, f[1] })
	local up =
		{ right[2] * f[3] - right[3] * f[2], right[3] * f[1] - right[1] * f[3], right[1] * f[2] - right[2] * f[1] }
	return right, up, f
end

-- How deep p is inside the spec box (> 0 inside, <= 0 outside or on it).
local function depth(spec, p): number
	local right, up, f = frame(spec)
	local d = sub(p, spec.centre)
	local s = spec.size
	return math.min(s[1] / 2 - math.abs(dot(d, right)), s[2] / 2 - math.abs(dot(d, up)), s[3] / 2 - math.abs(dot(d, f)))
end

-- True when p lies in ANOTHER segment's lane (over its floor slab, within its width, near its top): on this
-- tight spiral the inner side of a bend is the next segment's lane, so a wall cannot (and must not) be there.
local function inOtherLane(p, i): boolean
	for _, spec in SPECS do
		if spec.kind == "Floor" and spec.segment ~= i then
			local right, up, f = frame(spec)
			local d = sub(p, spec.centre)
			if
				math.abs(dot(d, right)) < spec.size[1] / 2
				and math.abs(dot(d, f)) < spec.size[3] / 2
				and math.abs(dot(d, up) - spec.size[2] / 2) < 6
			then
				return true
			end
		end
	end
	return false
end

local function insideAny(p): (boolean, string?)
	for _, spec in SPECS do
		if depth(spec, p) > RIDE_EPS then
			return true, spec.name
		end
	end
	return false, nil
end

-- The silo colliders (FountainCollider.spec checks them against the kit).
local SILO = {
	{ r = FP.plinthRadius, lo = 0, hi = FP.plinthTop },
	{ r = FP.trimRadius, lo = FP.plinthTop, hi = FP.trimTop },
	{ r = FP.wallRadius, lo = FP.plinthTop, hi = FP.eaveTop },
}
local function insideSilo(p): boolean
	local r = math.sqrt(p[1] ^ 2 + p[3] ^ 2)
	for _, c in SILO do
		if r < c.r - EPS and p[2] > c.lo + EPS and p[2] < c.hi - EPS then
			return true
		end
	end
	return false
end

local LOW = {}
for i = 1, #PATH - 1 do
	if SlideColliders.isLow(PATH[i], PATH[i + 1]) then
		table.insert(LOW, i)
	end
end

-- The emerge rise (inside the goo crown, under the slide head) is the one stretch
-- of the ride that sits in the first floor slab; riders are anchored and non-colliding.
local HEAD = PATH[1]
local function emerging(p): boolean
	return math.abs(p[1] - HEAD[1]) < 1e-3 and math.abs(p[3] - HEAD[3]) < 1e-3 and p[2] < HEAD[2] - 1e-3
end

local function byName(): { [string]: any }
	local out = {}
	for _, spec in SPECS do
		out[spec.name] = spec
	end
	return out
end

describe("SlideColliders specs", function()
	it("cover every slide segment (floor + both walls), top to mouth", function()
		local names = byName()
		expect(#LOW >= 10).toBe(true)
		for i = 1, #PATH - 1 do
			expect(names[`SlideFloor{i}`] ~= nil).toBe(true)
			expect(names[`SlideWallL{i}`] ~= nil).toBe(true)
			expect(names[`SlideWallR{i}`] ~= nil).toBe(true)
		end
		for _, spec in SPECS do
			expect(spec.segment >= 1 and spec.segment <= #PATH - 1).toBe(true)
		end
	end)
	it("flag off keeps the old low-only stretch", function()
		for _, spec in SlideColliders.build(PATH) do
			expect(SlideColliders.isLow(PATH[spec.segment], PATH[spec.segment + 1])).toBe(true)
		end
		expect(#SlideColliders.build(PATH) < #SPECS).toBe(true)
		expect(Config.FEATURES.SlideCollision).toBe(true)
	end)
	it("put the floor top exactly on the ride line, the walls either side of it", function()
		local names = byName()
		for i = 1, #PATH - 1 do
			local a, b = PATH[i], PATH[i + 1]
			for _, k in { 0.1, 0.5, 0.9 } do
				local p = { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }
				expect(depth(names[`SlideFloor{i}`], p)).toBeCloseTo(0, EPS)
				expect(depth(names[`SlideFloor{i}`], { p[1], p[2] - 0.2, p[3] }) > 0).toBe(true)
				local right = frame(names[`SlideFloor{i}`])
				local half = names[`SlideFloor{i}`].size[1] / 2
				for _, side in { -1, 1 } do
					local wall = names[if side < 0 then `SlideWallL{i}` else `SlideWallR{i}`]
					local q = { p[1] + right[1] * side * (half + 0.6), p[2] + 1, p[3] + right[3] * side * (half + 0.6) }
					-- (a bend's inner wall stops short of the join where the two inner faces meet, B6 round 5:
					-- near its ends only the middle sample must be in it; the corner behind is sealed by both faces)
					local cut = wall.size[3] < names[`SlideFloor{i}`].size[3] - 1e-6
					if not inOtherLane(q, i) and (k == 0.5 or not cut) then
						expect(depth(wall, q) > 0).toBe(true)
					end
				end
			end
		end
	end)
	it("block a walking player: nothing on the low slide is walk-through from the ground up", function()
		for _, i in LOW do
			local a, b = PATH[i], PATH[i + 1]
			local top = math.min(a[2], b[2])
			if top > PLAYER_HEIGHT then
				continue
			end
			for _, k in { 0.25, 0.5, 0.75 } do
				local x, z = a[1] + (b[1] - a[1]) * k, a[3] + (b[3] - a[3]) * k
				local floorY = a[2] + (b[2] - a[2]) * k
				-- every height a player's body crosses below the floor, plus the walls above it
				local y = 0.1
				while y < floorY - 0.1 do
					expect((insideAny({ x, y, z }))).toBe(true)
					y += 0.25
				end
			end
		end
	end)
	it("give every low segment too low to walk under a skirt from the ground to its trough bottom", function()
		local names = byName()
		for _, i in LOW do
			local a, b = PATH[i], PATH[i + 1]
			local bottom = math.min(a[2], b[2]) - SlideColliders.FLOOR
			local skirt = names[`SlideSkirt{i}`]
			if bottom > 0.05 and bottom <= SlideColliders.WALK_UNDER then
				expect(skirt ~= nil).toBe(true)
				expect(skirt.forward[2]).toBe(0)
				expect(skirt.centre[2] - skirt.size[2] / 2).toBeCloseTo(0, EPS)
				expect(skirt.centre[2] + skirt.size[2] / 2).toBeCloseTo(bottom, EPS)
			else
				expect(skirt).toBe(nil)
			end
		end
	end)
end)

-- Playtest B6: players fell through the slide above LOW_SLIDE_Y (no colliders there).
describe("slide collision covers the whole slide, top to bottom", function()
	local function floorsAt(p, below)
		-- floor specs whose slab holds p (p lowered by `below` studs along -Y)
		local hit = {}
		for _, spec in SPECS do
			if spec.kind == "Floor" and depth(spec, { p[1], p[2] - below, p[3] }) > 0 then
				table.insert(hit, spec)
			end
		end
		return hit
	end
	it("has a floor, both walls for every segment of the path, first to last, none skipped", function()
		local names = byName()
		local topSegment = #PATH - 1
		expect(PATH[1][2] > SlideColliders.WALK_UNDER * 4).toBe(true) -- the top really is high
		for i = 1, topSegment do
			expect(names[`SlideFloor{i}`] ~= nil and names[`SlideWallL{i}`] ~= nil and names[`SlideWallR{i}`] ~= nil).toBe(
				true
			)
		end
	end)
	it("every point of the centreline, very top to mouth, is held up by a floor slab (no gaps)", function()
		local steps = 0
		for i = 1, #PATH - 1 do
			local a, b = PATH[i], PATH[i + 1]
			local n =
				math.max(8, math.ceil(math.sqrt((b[1] - a[1]) ^ 2 + (b[3] - a[3]) ^ 2 + (b[2] - a[2]) ^ 2) / 0.25))
			for s = 0, n do
				local k = s / n
				local p = { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }
				-- just below the surface: inside a slab; just above: clear
				if #floorsAt(p, 0.05) == 0 then
					error(`gap in the slide floor near segment {i} k={k} at ({p[1]}, {p[2]}, {p[3]})`)
				end
				expect(#floorsAt(p, -0.05)).toBe(0)
				steps += 1
			end
		end
		expect(steps > 100).toBe(true)
	end)
	it("a point right across the trough width (floor edge to edge) is held up along the whole slide", function()
		for i = 1, #PATH - 1 do
			local a, b = PATH[i], PATH[i + 1]
			local spec = nil
			for _, c in SPECS do
				if c.name == `SlideFloor{i}` then
					spec = c
				end
			end
			local right = frame(spec)
			local half = spec.size[1] / 2 - 0.1
			for _, k in { 0.02, 0.5, 0.98 } do
				for _, side in { -1, 1 } do
					local p = {
						a[1] + (b[1] - a[1]) * k + right[1] * side * half,
						a[2] + (b[2] - a[2]) * k,
						a[3] + (b[3] - a[3]) * k + right[3] * side * half,
					}
					-- the edge sits at the ride-line height only on a flat cross-section (right is horizontal)
					if #floorsAt(p, 0.05) == 0 then
						error(`gap at the trough edge, segment {i} k={k} side={side}`)
					end
				end
			end
		end
	end)
	it("neighbouring floor slabs overlap at every joint, the steep ones too", function()
		for i = 1, #PATH - 2 do
			local joint = PATH[i + 1]
			local held = {}
			for _, spec in floorsAt(joint, 0.05) do
				held[spec.segment] = true
			end
			expect(held[i]).toBe(true)
			expect(held[i + 1]).toBe(true)
		end
	end)
	it("slabs are thick enough for a falling player, nothing is a thin sheet", function()
		for _, spec in SPECS do
			if spec.kind == "Floor" then
				expect(spec.size[2] >= SlideColliders.MIN_THICK).toBe(true)
				expect(spec.size[2] >= 2).toBe(true)
			elseif spec.kind == "Wall" then
				expect(spec.size[1] >= SlideColliders.WALL).toBe(true)
			end
		end
	end)
	it("a player dropped from above lands on the slide at every height, top to bottom", function()
		-- fall straight down onto the centreline in 1 stud/frame steps from 40 studs up; must stop on the surface
		for i = 1, #PATH - 1 do
			local a, b = PATH[i], PATH[i + 1]
			local p = { (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2 }
			local y = p[2] + 40
			local landed = false
			while y > p[2] - 10 do
				if #floorsAt({ p[1], y, p[3] }, 0) > 0 then
					landed = true
					break
				end
				y -= 1.5 -- ~90 studs/s at 60 Hz, well under terminal speed
			end
			expect(landed).toBe(true)
			expect(y >= p[2] - SlideColliders.MIN_THICK - 1.6).toBe(true)
		end
	end)
end)

describe("slide collision has no gap at any join and follows the visual path (B6 root cause)", function()
	-- B6 (still open after FEATURES.SlideCollision): the slide is a polyline of straight boxes; on a bend the
	-- outer edge of two neighbouring boxes opens a wedge, walls were barely above the ball, slabs were 2 studs.
	-- Joint fillers on the bisector, taller walls and 4-stud slabs close that; these pin it at every join.
	local function solidAt(p, kinds)
		local hit = false
		for _, spec in SPECS do
			if kinds[spec.kind] and depth(spec, p) > 0 then
				hit = true
			end
		end
		return hit
	end
	local FLOORISH = { Floor = true, Joint = true }
	local function pathPoint(i, k)
		local a, b = PATH[i], PATH[i + 1]
		return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }
	end
	local function specOf(name)
		for _, spec in SPECS do
			if spec.name == name then
				return spec
			end
		end
		error(`no spec {name}`)
	end
	local KS = { 0, 0.01, 0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.98, 0.99, 1 }

	it("has a joint floor and joint walls at every interior join of the full path", function()
		local names = byName()
		for i = 1, #PATH - 2 do
			expect(names[`SlideJoint{i}`] ~= nil).toBe(true)
			-- a wall piece on the outer AND the inner side of the bend, and the ceiling across it
			expect(names[`SlideJointWallL{i}`] ~= nil and names[`SlideJointWallR{i}`] ~= nil).toBe(true)
			expect(names[`SlideJointCeiling{i}`] ~= nil).toBe(true)
		end
	end)
	it("consecutive slabs: orientation is consistent and the top surfaces meet at the join", function()
		for i = 1, #PATH - 2 do
			local s1, s2 = specOf(`SlideFloor{i}`), specOf(`SlideFloor{i + 1}`)
			expect(dot(s1.forward, s2.forward) > math.cos(math.rad(60))).toBe(true)
			-- both top planes pass through the shared path point
			local joint = PATH[i + 2 - 1]
			for _, s in { s1, s2 } do
				local _, up = frame(s)
				local topY = dot(sub(joint, s.centre), up) - s.size[2] / 2
				expect(math.abs(topY) < 1e-3).toBe(true)
			end
			-- the far end of one slab's top face lies on the next slab's top plane (within a stud-fraction)
			local r1, u1, f1 = frame(s1)
			local end1 = {}
			for c = 1, 3 do
				end1[c] = s1.centre[c] + u1[c] * s1.size[2] / 2 + f1[c] * s1.size[3] / 2
			end
			local _, u2 = frame(s2)
			local gap = dot(sub(end1, s2.centre), u2) - s2.size[2] / 2
			expect(math.abs(gap) < 0.25).toBe(true)
			expect(r1[2]).toBe(0)
		end
	end)
	it("slabs and joint fillers are at least MIN_THICK thick, walls stand above the kit lip", function()
		expect(SlideColliders.MIN_THICK >= 4).toBe(true)
		for _, spec in SPECS do
			if FLOORISH[spec.kind] then
				expect(spec.size[2] >= SlideColliders.MIN_THICK).toBe(true)
			elseif spec.kind == "Wall" then
				expect(
					spec.size[2] >= SlideColliders.LIP * 0.55 + SlideColliders.FLOOR + SlideColliders.WALL_EXTRA - 1e-6
				).toBe(true)
			end
		end
	end)
	it("the slab edge to edge is held up at every k, 0 and 1 included, joints and bends too", function()
		for i = 1, #PATH - 1 do
			local spec = specOf(`SlideFloor{i}`)
			local right = frame(spec)
			local half = spec.size[1] / 2 - 0.1
			for _, k in KS do
				local c = pathPoint(i, k)
				for _, side in { -1, -0.5, 0, 0.5, 1 } do
					local p = { c[1] + right[1] * side * half, c[2] - 0.05, c[3] + right[3] * side * half }
					if not solidAt(p, FLOORISH) then
						error(`gap in the slide: segment {i} k={k} side={side}`)
					end
					-- and nothing solid hides above the surface: the ride is free
					-- (a joint filler's plane tilts off the segment's on a sharp bend, so only the middle half is checked, for ledges over a stud)
					if math.abs(side) <= 0.5 and solidAt({ p[1], p[2] + 0.9, p[3] }, FLOORISH) then
						error(`solid 0.9 above the surface: segment {i} k={k} side={side}`)
					end
				end
			end
		end
	end)
	it(
		"no ball-sized hole in the floor at any join (every 0.25 stud across the width and along the bisector)",
		function()
			for i = 1, #PATH - 2 do
				local joint = PATH[i + 1]
				local d1 = normalize(sub(joint, PATH[i]))
				local d2 = normalize(sub(PATH[i + 2], joint))
				local f = normalize({ d1[1] + d2[1], d1[2] + d2[2], d1[3] + d2[3] })
				local right = normalize({ -f[3], 0, f[1] })
				local half = specOf(`SlideFloor{i}`).size[1] / 2 - 0.1
				for along = -1.2, 1.2, 0.25 do
					for lat = -half, half, 0.25 do
						local p = {}
						for c = 1, 3 do
							p[c] = joint[c] + f[c] * along + right[c] * lat
						end
						-- 0.7 below the bisector's surface line (the segments' planes differ by a few tenths on a bend)
						p[2] -= 0.7 + math.abs(along) * 0.3
						if not solidAt(p, FLOORISH) then
							error(`hole at join {i}: along={along} lat={lat}`)
						end
					end
				end
			end
		end
	)
	it("no way out sideways at any join: every outward line at ball height meets a wall, both sides", function()
		for i = 1, #PATH - 2 do
			local joint = PATH[i + 1]
			local a, c = PATH[i], PATH[i + 2]
			local d1 = normalize(sub(joint, a))
			local d2 = normalize(sub(c, joint))
			local f = normalize({ d1[1] + d2[1], d1[2] + d2[2], d1[3] + d2[3] })
			local right = normalize({ -f[3], 0, f[1] })
			local up = { 0, 1, 0 }
			for _, side in { -1, 1 } do
				for along = -1.5, 1.5, 0.1 do
					local met = false
					for lat = 0, 8, 0.05 do
						local p = {}
						for k = 1, 3 do
							p[k] = joint[k] + f[k] * along + right[k] * side * lat + up[k] * 1.5
						end
						if solidAt(p, { Wall = true }) then
							met = true
							break
						end
					end
					if not met then
						error(`open side at join {i}: side={side} along={along}`)
					end
				end
			end
		end
	end)
	it("the collider path matches the visual slide path at every sample (WorldLayout.slidePosition)", function()
		local n = 3000
		for s = 0, n do
			local p = WorldLayout.slidePosition(s / n)
			if not solidAt({ p[1], p[2] - 0.05, p[3] }, FLOORISH) then
				error(`visual slide point t={s / n} is not held up by a collider`)
			end
			expect(solidAt({ p[1], p[2] + 0.4, p[3] }, FLOORISH)).toBe(false)
		end
		-- every floor slab is centred on its own path segment, nothing generated from another path
		for i = 1, #PATH - 1 do
			local spec = specOf(`SlideFloor{i}`)
			local _, up = frame(spec)
			local mid = pathPoint(i, 0.5)
			local top = {}
			for c = 1, 3 do
				top[c] = spec.centre[c] + up[c] * spec.size[2] / 2
			end
			-- (the slide head / mouth slabs are shifted along their length: they reach further past the join)
			local off = sub(top, mid)
			local right, _, fwd = frame(spec)
			expect(math.abs(dot(off, right)) + math.abs(dot(off, up)) < 1e-3).toBe(true)
			expect(math.abs(dot(off, fwd)) < SlideColliders.OVERLAP / 2).toBe(true)
		end
	end)
	it("a falling ball over any k (joins included) and any lateral offset lands on the slide, top to bottom", function()
		local landed = 0
		for i = 1, #PATH - 1 do
			local spec = specOf(`SlideFloor{i}`)
			local right = frame(spec)
			for _, k in KS do
				local c = pathPoint(i, k)
				for _, side in { -0.8, 0, 0.8 } do
					local x = c[1] + right[1] * side * spec.size[1] / 2
					local z = c[3] + right[3] * side * spec.size[1] / 2
					local y = c[2] + 40
					local stopped = false
					while y > c[2] - 10 do
						if solidAt({ x, y, z }, FLOORISH) then
							stopped = true
							break
						end
						y -= 1.5
					end
					expect(stopped).toBe(true)
					expect(y >= c[2] - SlideColliders.MIN_THICK - 1.6).toBe(true)
					landed += 1
				end
			end
		end
		expect(landed > 1000).toBe(true)
	end)
end)

-- B6 (third round): Studio's hard probe still lost balls launched at 40 studs/s along a segment at the
-- trough's side (side -2.4, the OUTER side of every bend): they hit the next segment's wall at 20-55 degrees,
-- hopped it and left; the walls were 0.6 thick and 3.4 studs high with no cover. These pin the geometry
-- (wall height both sides, joint walls both sides, overlap, no hole at 19/20/21, a continuous ceiling) and then
-- replay the probe's launch in a small ballistic sphere-vs-box simulation.
describe("slide walls, joints and ceiling hold a fast ball (B6 round 3)", function()
	local DENSE = 0.25
	local function specOf(name)
		for _, spec in SPECS do
			if spec.name == name then
				return spec
			end
		end
		error(`no spec {name}`)
	end
	local function specsOf(kind)
		local out = {}
		for _, spec in SPECS do
			if spec.kind == kind then
				table.insert(out, spec)
			end
		end
		return out
	end
	local function pathPoint(i, k)
		local a, b = PATH[i], PATH[i + 1]
		return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }
	end
	local function solidIn(p, kinds)
		for _, spec in SPECS do
			if kinds[spec.kind] and depth(spec, p) > 0 then
				return true
			end
		end
		return false
	end
	local function jointFrame(i) -- the bisector frame of the join at PATH[i + 1]
		local joint = PATH[i + 1]
		local d1 = normalize(sub(joint, PATH[i]))
		local d2 = normalize(sub(PATH[i + 2], joint))
		local f = normalize({ d1[1] + d2[1], d1[2] + d2[2], d1[3] + d2[3] })
		return joint, f, normalize({ -f[3], 0, f[1] })
	end

	it(
		"walls are thick and tall on both sides: >= 2 studs thick, >= 5 above the floor, every segment and joint",
		function()
			for _, spec in specsOf("Wall") do
				expect(spec.size[1] >= 2 - 1e-6).toBe(true)
				expect(spec.size[2] >= SlideColliders.LIP * 0.55 + SlideColliders.FLOOR + 4 - 1e-6).toBe(true)
			end
			-- measured from the floor's top: every dense point up the wall column is solid, both sides
			for i = 1, #PATH - 1 do
				local floorSpec = nil
				for _, c in SPECS do
					if c.name == `SlideFloor{i}` then
						floorSpec = c
					end
				end
				local right, up = frame(floorSpec)
				local half = floorSpec.size[1] / 2
				for _, k in { 0, 0.1, 0.5, 0.9, 1 } do
					local c = pathPoint(i, k)
					for _, side in { -1, 1 } do
						for _, lat in { half + 0.2, half + 1, half + 1.8 } do
							local h = 0.1
							while h < 5 do
								local p = {}
								for a = 1, 3 do
									p[a] = c[a] + right[a] * side * lat + up[a] * h
								end
								if not solidIn(p, { Wall = true }) and not inOtherLane(p, i) then
									error(`wall gap: segment {i} k={k} side={side} lat={lat} height={h}`)
								end
								h += 0.5
							end
						end
					end
				end
			end
		end
	)
	it("every bend has a joint wall on the inner AND the outer side, as tall as the segment walls", function()
		local names = byName()
		for i = 1, #PATH - 2 do
			local l, r = names[`SlideJointWallL{i}`], names[`SlideJointWallR{i}`]
			expect(l ~= nil and r ~= nil).toBe(true)
			local w = names[`SlideWallL{i}`]
			expect(
				l.size[2] >= w.size[2] - 1e-6
					or l.size[2] >= SlideColliders.LIP * 0.55 + SlideColliders.FLOOR + 4 - 1e-6
			).toBe(true)
			expect(r.size[2] >= SlideColliders.LIP * 0.55 + SlideColliders.FLOOR + 4 - 1e-6).toBe(true)
			expect(l.size[1] >= 2 - 1e-6 and r.size[1] >= 2 - 1e-6).toBe(true)
		end
	end)
	it("neighbouring floor slabs overlap at every join (0.3 either side), across the full width", function()
		for i = 1, #PATH - 2 do
			local joint = PATH[i + 1]
			local s1, s2 = specOf(`SlideFloor{i}`), specOf(`SlideFloor{i + 1}`)
			local r1, _, f1 = frame(s1)
			local r2, _, f2 = frame(s2)
			local half = s1.size[1] / 2
			for lat = -half + 0.3, half - 0.3, DENSE do
				-- a point just past the join on slab i's line is in slab i, one just before it on slab i + 1's in slab i + 1
				local p1, p2 = {}, {}
				for a = 1, 3 do
					p1[a] = joint[a] + f1[a] * 0.3 + r1[a] * lat
					p2[a] = joint[a] - f2[a] * 0.3 + r2[a] * lat
				end
				p1[2] -= 0.05
				p2[2] -= 0.05
				expect(depth(s1, p1) > 0).toBe(true)
				expect(depth(s2, p2) > 0).toBe(true)
			end
			-- the slabs themselves overlap along their length
			local a, b = PATH[i], PATH[i + 1]
			local len = math.sqrt(dot(sub(b, a), sub(b, a)))
			expect(s1.size[3] >= len + SlideColliders.OVERLAP / 2 - 1e-6).toBe(true)
			expect(s1.size[3] >= len + SlideColliders.END_EXTRA - 1e-6).toBe(true)
		end
	end)
	it(
		"no hole at joins 19 / 20 / 21 (or any): every 0.25 stud across width + walls, along 3 studs, below the surface",
		function()
			for i = 18, 21 do
				if i > #PATH - 2 then
					continue
				end
				local joint, f, right = jointFrame(i)
				local half = specOf(`SlideFloor{i}`).size[1] / 2
				for along = -1.5, 1.5, DENSE do
					for lat = -half + 0.1, half - 0.1, DENSE do
						local p = {}
						for a = 1, 3 do
							p[a] = joint[a] + f[a] * along + right[a] * lat
						end
						p[2] -= 0.7 + math.abs(along) * 0.3
						if not solidIn(p, { Floor = true, Joint = true }) then
							error(`hole at join {i}: along={along} lat={lat}`)
						end
					end
				end
			end
		end
	)
	it("the ceiling is continuous along the whole slide and clear of a standing player", function()
		for i = 1, #PATH - 1 do
			local spec = specOf(`SlideFloor{i}`)
			local right, up = frame(spec)
			for _, k in { 0, 0.01, 0.1, 0.5, 0.9, 0.99, 1 } do
				local c = pathPoint(i, k)
				for _, side in { -0.6, 0, 0.6 } do
					local base, above = {}, {}
					for a = 1, 3 do
						base[a] = c[a] + right[a] * side * spec.size[1] / 2
						above[a] = base[a] + up[a] * (SlideColliders.CEILING + 0.75)
					end
					expect(solidIn(above, { Ceiling = true })).toBe(true)
					-- a player's head (5 studs) plus a hop's worth below it is free
					local head = {}
					for a = 1, 3 do
						head[a] = base[a] + up[a] * 6
					end
					for _, spec2 in SPECS do
						-- (a bend's inner walls overlap the next segment's lane near the join: walls only on the centreline)
						if
							(spec2.kind == "Ceiling" or (spec2.kind == "Wall" and side == 0))
							and depth(spec2, head) > 0
						then
							error(`head room blocked by {spec2.name} at segment {i} k={k} side={side}`)
						end
					end
				end
			end
		end
		-- across each join too
		for i = 1, #PATH - 2 do
			local joint, f, right = jointFrame(i)
			for along = -1, 1, DENSE do
				for lat = -3, 3, 0.5 do
					local p = {
						joint[1] + f[1] * along + right[1] * lat,
						joint[2] + SlideColliders.CEILING + SlideColliders.CEILING_THICK / 2,
						joint[3] + f[3] * along + right[3] * lat,
					}
					if not solidIn(p, { Ceiling = true }) then
						error(`ceiling gap at join {i}: along={along} lat={lat}`)
					end
				end
			end
		end
	end)

	it(
		"no gap between wall top and ceiling underside: every wall reaches into a ceiling slab, segments and joints, both sides",
		function()
			local names = byName()
			local function check(wallName, ceilingName)
				local w, c = names[wallName], names[ceilingName]
				expect(w ~= nil and c ~= nil).toBe(true)
				local right, up, f = frame(w)
				-- dense sample up the wall's top edge, across its 2-stud thickness and along its length
				for along = -w.size[3] / 2 + 0.1, w.size[3] / 2 - 0.1, 0.5 do
					for across = -w.size[1] / 2 + 0.1, w.size[1] / 2 - 0.1, 0.45 do
						local p = {}
						for a = 1, 3 do
							p[a] = w.centre[a] + right[a] * across + f[a] * along + up[a] * (w.size[2] / 2 - 0.05)
						end
						expect(solidIn(p, { Ceiling = true })).toBe(true)
					end
				end
			end
			for i = 1, #PATH - 1 do
				for _, side in { "L", "R" } do
					check(`SlideWall{side}{i}`, `SlideCeiling{i}`)
					-- no air column between wall and ceiling at the wall's mid-height either
					local w = names[`SlideWall{side}{i}`]
					expect(w.size[2] >= SlideColliders.CEILING + SlideColliders.FLOOR + 0.1).toBe(true)
				end
			end
			for i = 1, #PATH - 2 do
				for _, side in { "L", "R" } do
					check(`SlideJointWall{side}{i}`, `SlideJointCeiling{i}`)
				end
				-- the OUTER joint wall (the long one; the inner one is a corner piece, B6 round 5)
				local c = names[`SlideJointCeiling{i}`]
				local w = names[`SlideJointWallL{i}`]
				if names[`SlideJointWallR{i}`].size[3] > w.size[3] then
					w = names[`SlideJointWallR{i}`]
				end
				expect(
					c.size[1] >= w.size[1] + w.size[1] + 2 * 3.5 - 1e-6
						or c.size[1] >= 2 * (3.5 + SlideColliders.WALL_OUT) - 1e-6
				).toBe(true)
				-- (the last join, at the mouth on the ground, keeps to the joint floor's length)
				local margin = if i == #PATH - 2 then 0 else 2 * SlideColliders.JOINT_MARGIN
				expect(w.size[3] >= SlideColliders.JOINT_LENGTH + margin - 1e-6).toBe(true)
			end
		end
	)

	-- A 2-stud ball (Roblox plastic: elasticity 0.5, friction 0.3) against the solid specs.
	local GRAVITY = 196.2
	local function closestPush(spec, c)
		local right, up, f = frame(spec)
		local d = sub(c, spec.centre)
		local local3 = { dot(d, right), dot(d, up), dot(d, f) }
		local axes = { right, up, f }
		local clamped, inside = {}, true
		for a = 1, 3 do
			local h = spec.size[a] / 2
			clamped[a] = math.clamp(local3[a], -h, h)
			if math.abs(local3[a]) > h then
				inside = false
			end
		end
		local normal, dist
		if inside then
			-- centre inside the box: leave through the nearest face
			local best, ba, bs = math.huge, 1, 1
			for a = 1, 3 do
				local gap = spec.size[a] / 2 - math.abs(local3[a])
				if gap < best then
					best, ba, bs = gap, a, if local3[a] >= 0 then 1 else -1
				end
			end
			normal = { axes[ba][1] * bs, axes[ba][2] * bs, axes[ba][3] * bs }
			dist = -best
		else
			local diff = { 0, 0, 0 }
			for a = 1, 3 do
				for c3 = 1, 3 do
					diff[c3] += axes[a][c3] * (local3[a] - clamped[a])
				end
			end
			dist = math.sqrt(dot(diff, diff))
			normal = { diff[1] / dist, diff[2] / dist, diff[3] / dist }
		end
		return normal, dist
	end
	local function simulate(x: { number }, v: { number }, duration: number): (boolean, string)
		local solids, slabs = {}, {}
		for _, spec in SPECS do
			if spec.kind ~= "Skirt" then
				local reach = math.sqrt(dot(spec.size, spec.size)) / 2 + 1
				table.insert(solids, { spec = spec, reach = reach })
				if spec.kind == "Floor" or spec.kind == "Joint" then
					table.insert(slabs, spec)
				end
			end
		end
		local dt = 1 / 240
		for _ = 1, math.floor(duration / dt) do
			v[2] -= GRAVITY * dt
			for a = 1, 3 do
				x[a] += v[a] * dt
			end
			for _ = 1, 3 do
				for _, solid in solids do
					local spec = solid.spec
					local d = sub(x, spec.centre)
					if dot(d, d) > solid.reach * solid.reach then
						continue
					end
					local normal, dist = closestPush(spec, x)
					if dist < 1 then
						local push = 1 - dist
						for a = 1, 3 do
							x[a] += normal[a] * push
						end
						local vn = dot(v, normal)
						if vn < 0 then
							local tangent = { v[1] - normal[1] * vn, v[2] - normal[2] * vn, v[3] - normal[3] * vn }
							for a = 1, 3 do
								v[a] = tangent[a] * 0.97 - normal[a] * vn * 0.5
							end
						end
					end
				end
			end
			-- left the slide: outside every floor/joint slab's footprint (lateral past the wall's outer face)
			-- or below the ground
			if x[2] < -1 then
				return false, `fell to y={x[2]}`
			end
			-- the Studio probe's own test (pc-watcher/luau/slide_walk.luau escaped()): within a slab's length and
			-- 8 studs of its top face but outside every such slab's width + 0.2 = left the trough sideways
			local near, inside = false, false
			for _, spec in slabs do
				local right, up, f = frame(spec)
				local d = sub(x, spec.centre)
				if math.abs(dot(d, f)) < spec.size[3] / 2 and math.abs(dot(d, up) - spec.size[2] / 2) < 8 then
					if math.abs(dot(d, right)) < spec.size[1] / 2 + 0.2 then
						inside = true
						break
					end
					near = true
				end
			end
			if near and not inside then
				return false, "left the trough sideways (probe test)"
			end
			if not inside then
				return false, "left the slide"
			end
		end
		return true, ""
	end

	it(
		"simulated probe: a 2-stud ball launched at 40 and 60 studs/s along every segment at side -2.4 / 0 / 2.4 stays in",
		function()
			local trials, failed = 0, {}
			-- (not the open ends, where a ball rightly leaves: the last two segments run out of the mouth, and
			-- k = 0 of the first is the slide's open back edge)
			for i = 1, #PATH - 3 do
				local spec = specOf(`SlideFloor{i}`)
				local right, _, f = frame(spec)
				for _, k in { 0, 0.25, 0.5, 0.9, 0.98, 1 } do
					if i == 1 and k == 0 then
						continue
					end
					local c = pathPoint(i, k)
					for _, side in { -2.4, 0, 2.4 } do
						for _, speed in { 40, 60 } do
							-- at 60 studs/s a ball launched in the last segments before the mouth simply runs out of it
							-- within the probe's 1.5 s window (an open end, not a side escape)
							if speed == 60 and i > #PATH - 4 then
								continue
							end
							-- the probe's drop: world +5 above the surface point
							local x = {
								c[1] + right[1] * side,
								c[2] + 5,
								c[3] + right[3] * side,
							}
							local v = { f[1] * speed, f[2] * speed, f[3] * speed }
							local ok, why = simulate(x, v, 1.5)
							trials += 1
							if not ok then
								table.insert(failed, `segment {i} k={k} side={side} v={speed}: {why}`)
							end
						end
					end
				end
			end
			if #failed > 0 then
				error(`{#failed}/{trials} simulated balls left the slide:\n{table.concat(failed, "\n")}`)
			end
			expect(trials > 500).toBe(true)
		end
	)
	it(
		"no probe ball spawns inside a wall: every slide_walk drop point (k, side 0 / +-2.4, +5) clears every solid by its radius",
		function()
			local bad = {}
			for i = 1, #PATH - 1 do
				local spec = specOf(`SlideFloor{i}`)
				local right = frame(spec)
				for _, k in { 0, 0.02, 0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.98, 1 } do
					local c = pathPoint(i, k)
					for _, side in { -2.4, 0, 2.4 } do
						local x = { c[1] + right[1] * side, c[2] + 5, c[3] + right[3] * side }
						for _, other in SPECS do
							if other.kind ~= "Skirt" then
								local _, dist = closestPush(other, x)
								if dist < 1 then
									table.insert(bad, `segment {i} k={k} side={side} overlaps {other.name} ({dist})`)
								end
							end
						end
					end
				end
			end
			if #bad > 0 then
				error(`{#bad} probe spawn overlaps:\n{table.concat(bad, "\n", 1, math.min(#bad, 20))}`)
			end
		end
	)
	it("segment 3 outer side: dense k at v 40 / 60, sides +-2.4, zero escapes", function()
		local failed = {}
		local spec = specOf("SlideFloor3")
		local right, _, f = frame(spec)
		for k = 0, 1.0001, 0.05 do
			local c = pathPoint(3, math.min(k, 1))
			for _, side in { -2.4, 2.4 } do
				for _, speed in { 40, 60 } do
					local x = { c[1] + right[1] * side, c[2] + 5, c[3] + right[3] * side }
					local v = { f[1] * speed, f[2] * speed, f[3] * speed }
					local ok, why = simulate(x, v, 1.5)
					if not ok then
						table.insert(failed, `k={k} side={side} v={speed}: {why}`)
					end
				end
			end
		end
		if #failed > 0 then
			error(`{#failed} segment 3 escapes:\n{table.concat(failed, "\n")}`)
		end
	end)
end)

describe("fountain colliders leave the ride path clear", function()
	local rng = Rng.new(13)
	local rides = {}
	for k = 1, 400 do
		local drop = Fountain.roll(rng, `c{k}`, false)
		local x, z =
			FountainRide.clearLanding(PATH, math.cos(drop.angle) * drop.radius, math.sin(drop.angle) * drop.radius)
		table.insert(rides, FountainRide.new(PATH, { x, 0.15, z }))
	end
	it("no ride point (pivot) is inside a slide or silo collider", function()
		for _, ride in rides do
			for _, p in ride.points do
				local inside, name = insideAny(p)
				if inside and not emerging(p) then
					error(`ride point ({p[1]}, {p[2]}, {p[3]}) inside {name}`)
				end
				expect(insideSilo(p)).toBe(false)
			end
		end
	end)
	it("the slime body above the pivot stays clear too", function()
		for k = 1, 60 do
			for _, p in rides[k].points do
				local body = { p[1], p[2] + BODY_LIFT, p[3] }
				if emerging(p) then
					continue
				end
				expect((insideAny(body))).toBe(false)
				expect(insideSilo(body)).toBe(false)
			end
		end
	end)
end)

-- The real server, mesh loaded and failed.
local placePath = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-slidecol-{os.time()}-{math.random(1, 1e9)}.rbxlx`
local built = process.exec("rojo", { "build", "-o", placePath })
assert(built.ok, `rojo build failed: {built.stderr}`)

local function boot(loaded: boolean)
	local rt = Runtime.new(placePath, {
		createMeshPart = function(meshId)
			if loaded then
				return roblox.Instance.new("MeshPart")
			end
			error(`livetest: CreateMeshPartAsync({meshId}) failed`)
		end,
	})
	rt:boot()
	local rides = {}
	for _ = 1, 25 * 30 do
		rt:step(1 / 30)
		local folder = rt.workspace:FindFirstChild("WildSlimes")
		for _, model in (if folder then folder:GetChildren() else {}) do
			local solid = false
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d.CanCollide then
					solid = true
				end
			end
			local p = model:GetPivot().Position
			table.insert(rides, { p = p, solid = solid, anchored = model.PrimaryPart.Anchored })
		end
	end
	return rt, rides
end
local loadedRt, loadedRides = boot(true)
local failedRt, failedRides = boot(false)
require("@lune/fs").removeFile(placePath)

local function folderOf(rt)
	return rt.workspace.Map.Volcano:FindFirstChild(SlideColliders.FOLDER)
end

describe("SlideColliders in the live server", function()
	for _, case in { { "mesh loaded", loadedRt }, { "mesh failed", failedRt } } do
		local state, rt = case[1], case[2]
		it(`{state}: Map.Volcano.SlideColliders holds every spec as an invisible, solid, anchored Part`, function()
			expect(#rt.errors).toBe(0)
			local folder = folderOf(rt)
			expect(folder ~= nil).toBe(true)
			local parts = folder:GetChildren()
			expect(#parts).toBe(#SPECS)
			local names = byName()
			for _, part in parts do
				local spec = names[part.Name]
				expect(spec ~= nil).toBe(true)
				expect(part.Anchored).toBe(true)
				expect(part.CanCollide).toBe(true)
				expect(part.CanQuery).toBe(false)
				expect(part.CanTouch).toBe(false)
				expect(part.Transparency).toBe(1)
				expect(part:GetAttribute("FountainCollider")).toBe(spec.kind)
				local c = part.CFrame.Position
				expect((c - roblox.Vector3.new(spec.centre[1], spec.centre[2], spec.centre[3])).Magnitude < EPS).toBe(
					true
				)
				local look = part.CFrame.LookVector
				expect(look:Dot(roblox.Vector3.new(spec.forward[1], spec.forward[2], spec.forward[3])) > 1 - EPS).toBe(
					true
				)
				expect(math.abs(part.Size.X - spec.size[1]) < EPS).toBe(true)
				expect(math.abs(part.Size.Y - spec.size[2]) < EPS).toBe(true)
				expect(math.abs(part.Size.Z - spec.size[3]) < EPS).toBe(true)
			end
		end)
		it(`{state}: riding slimes are anchored and never collide (colliders can't stop them)`, function()
			local rides = if state == "mesh loaded" then loadedRides else failedRides
			expect(#rides > 100).toBe(true)
			for _, r in rides do
				expect(r.solid).toBe(false)
				expect(r.anchored).toBe(true)
			end
		end)
		it(`{state}: no slime pivot ever sits inside a fountain collider Part`, function()
			local rides = if state == "mesh loaded" then loadedRides else failedRides
			local colliders = {}
			for _, d in rt.workspace.Map.Volcano:GetDescendants() do
				if d:IsA("BasePart") and (d:GetAttribute("FountainCollider") or d:GetAttribute("MeshCollider")) then
					table.insert(colliders, d)
				end
			end
			expect(#colliders).toBe(#SPECS + 3 + #WorldLayout.fountainTopTiers())
			for _, r in rides do
				if emerging({ r.p.X, r.p.Y, r.p.Z }) then
					continue
				end
				for _, part in colliders do
					local l = part.CFrame:PointToObjectSpace(r.p)
					local s = part.Size
					local inside
					if part.Shape == roblox.Enum.PartType.Cylinder then
						-- The ride line is straight chords across the dome shoulder, so it dips up to
						-- TOP_DIP into the fountain's top colliders: a bump a player steps over in the
						-- trough, while the anchored slimes never collide.
						local dip = if string.sub(part.Name, 1, 11) == "TopCollider" then TOP_DIP else LIVE_EPS
						inside = math.abs(l.X) < s.X / 2 - dip and math.sqrt(l.Y ^ 2 + l.Z ^ 2) < s.Y / 2 - LIVE_EPS
					else
						inside = math.abs(l.X) < s.X / 2 - LIVE_EPS
							and math.abs(l.Y) < s.Y / 2 - LIVE_EPS
							and math.abs(l.Z) < s.Z / 2 - LIVE_EPS
					end
					if inside then
						error(`slime pivot {r.p} inside {part.Name}`)
					end
				end
			end
		end)
	end
	it("the MeshSwap switch leaves the slide colliders on (both directions)", function()
		local rt = loadedRt
		local MeshSwap = rt:require(rt.game:GetService("ServerScriptService").Server.MeshSwap)
		for _, loaded in { false, true } do
			MeshSwap.setMeshCollision(rt.workspace.Map, "slime_fountain", loaded)
			for _, part in folderOf(rt):GetChildren() do
				expect(part.CanCollide).toBe(true)
			end
		end
		expect(rt.workspace.Map.Volcano.SiloCollider.CanCollide).toBe(true)
	end)
	it("the silo blocks players once the mesh is in (Basin / Trim / Silo on), stand-ins when it failed", function()
		for _, name in { "BasinCollider", "TrimCollider", "SiloCollider" } do
			expect(loadedRt.workspace.Map.Volcano[name].CanCollide).toBe(true)
			expect(failedRt.workspace.Map.Volcano[name].CanCollide).toBe(false)
		end
		for _, name in { "Rock1", "BasinRim", "Column" } do
			expect(failedRt.workspace.Map.Volcano[name].CanCollide).toBe(true)
		end
	end)
end)
