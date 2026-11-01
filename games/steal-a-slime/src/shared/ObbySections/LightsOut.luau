--!strict
--[[
	Lights Out (obby idea 17, docs/obby-variants/17.json; contract/obby-sections.md)

	The section turns to night the moment you enter (a `dark` zone: the screen fades to night and only your own soft
	light of `zone.light` studs shows the floor round you). Anything glowing green (a slime, an edge strip, a firefly)
	marks a safe place to land; red goo keeps its hazard look and still sends you back to the start pad.

	How each light of the design maps onto the kit:
	  * glowing slime     a small ghost ball, look `glow` tone 2 (green), sitting on a safe platform
	  * light the next    the slime hides inside its platform and rises out (`path` once on a `start` clock) when you
	                      land on the platform before it (that platform is the `trigger`)
	  * blinking lights   `flip` on a ghost marker (shown / hidden on a duty), or `flip` with `solid = true` on the
	                      platform itself (only its glow pulses: the lighthouse sweep and the lightning flash)
	  * firefly           a small ghost `glow` ball on a `path`: once per landing (Firefly Friend) or one timed trip
	                      that holds over each platform (Firefly Pace)
	  * shrinking light   one dark zone per platform, each with a smaller `light` radius; a campfire pad resets it
	  * lighthouse beam   a ghost bar spinning (`spin`) on a post, or a light bar sweeping up the climb (`path`)
	  * red light         a see-through red goo curtain across the lane that blinks (`flip` hazard): you cross it, or
	                      jump through it in a gap, while it is out

	Tuned per contract §10 (one notch up from the drafts): gaps of 5 and more everywhere (a straight walk always falls
	in), dim red goo on the floors, and every variant has at least one timed hazard: a tall goo bar sliding across a
	platform or a blinking red light (both taller than a jump, so you can't hop over them). Measured windows: easy
	1.5..1.8 s, medium 1.0..1.15 s, hard 0.8..0.85 s (tests/obby/LightsOut.spec bounds them).
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

type Part = Kit.Part

local PAD = 8 -- platform size (studs, both ways) unless a variant says otherwise
local ZONE_LOW, ZONE_HIGH = -14, 30 -- the dark zone's box, in studs from the entry floor top
local SLIME = 1.6 -- glowing slime ball size
local GOO_HIGH = 2 -- dim red goo block height
local GOO_WALL = 9 -- moving / blinking goo: taller than a jump (7.2) plus a bit

-- A laid-out platform: centre x / z, its top and its x range.
type Pad = { x: number, z: number, top: number, x0: number, x1: number, sx: number, sz: number }

-- Pads along x from x = 0: each entry is { gap before it, top, z } (the first gap is ignored). `sx` / `sz` default to
-- PAD.
local function lay(list: { { number } }, sx: number?, sz: number?): { Pad }
	local lx, lz = sx or PAD, sz or PAD
	local out: { Pad } = {}
	local x = 0
	for i, e in list do
		if i > 1 then
			x += e[1]
		end
		table.insert(out, { x = x + lx / 2, z = e[3], top = e[2], x0 = x, x1 = x + lx, sx = lx, sz = lz })
		x += lx
	end
	return out
end

local function slab(p: Pad, extra: { [string]: any }?): Part
	local e: { [string]: any } = { tone = 3 }
	for k, v in (extra or {}) :: { [string]: any } do
		e[k] = v
	end
	return Kit.slab(p.x, p.top, p.z, p.sx, p.sz, "tile", e)
end

-- The night over x0..x1 (the whole lane across): your light is `light` studs inside it.
local function dark(x0: number, x1: number, light: number): Part
	return Kit.prop(
		{ x1 - x0, ZONE_HIGH - ZONE_LOW, Kit.WIDTH },
		{ (x0 + x1) / 2, (ZONE_HIGH + ZONE_LOW) / 2, 0 },
		"dark",
		{ ghost = true, zone = { kind = "dark", light = light } }
	)
end

-- A glowing green slime sitting on a platform top at (x, z).
local function slime(x: number, top: number, z: number, extra: { [string]: any }?): Part
	local e: { [string]: any } = { tone = 2, ghost = true, shape = "ball" }
	for k, v in (extra or {}) :: { [string]: any } do
		e[k] = v
	end
	return Kit.prop({ SLIME, SLIME, SLIME }, { x, top + SLIME / 2, z }, "glow", e)
end

-- A slime hidden inside its platform until `group` starts, then it pops up onto the top (light the next).
local function litBy(x: number, top: number, z: number, group: string): Part
	return Kit.prop({ 1.4, 0.6, 1.4 }, { x, top - 0.5, z }, "glow", {
		tone = 2,
		ghost = true,
		start = group,
		motion = { kind = "path", points = { { 0, 0, 0 }, { 0, 1.6, 0 } }, period = 0.4, once = true },
	})
end

-- Dim red goo, `sx` x `sz`, standing on a top at (x, z).
local function goo(x: number, top: number, z: number, sx: number, sz: number, extra: { [string]: any }?): Part
	return Kit.hazard({ sx, GOO_HIGH, sz }, { x, top + GOO_HIGH / 2, z }, extra)
end

-- A tall red goo bar `wide` across a pad, `dx` past its centre, sliding side to side (`amp`, `period`): it leaves the
-- pad open on one side at a time, so you time the crossing. It is taller than a jump, so you can't hop over it.
local function sweeper(p: Pad, dx: number, wide: number, amp: number, period: number, phase: number?): Part
	return Kit.hazard({ 1.5, GOO_WALL, wide }, { p.x + dx, p.top + GOO_WALL / 2, p.z }, {
		motion = { kind = "slide", axis = "z", amp = amp, period = period, phase = phase or 0 },
	})
end

-- A red light: a see-through goo curtain across the whole lane at `x` (from `low` - 2 up to a jump over `high`) that
-- blinks: on for most of `period`, out for `off` s. You cross while it is out (in a gap, you jump through it).
local function redLight(x: number, low: number, high: number, period: number, off: number, phase: number?): Part
	local bottom, top = low - 2, high + GOO_WALL
	return Kit.hazard({ 1, top - bottom, Kit.WIDTH }, { x, (bottom + top) / 2, 0 }, {
		motion = { kind = "flip", duty = 1 - off / period, period = period, phase = phase or 0 },
	})
end

-- The red light in the gap between two pads.
local function gapLight(a: Pad, b: Pad, period: number, off: number, phase: number?): Part
	return redLight((a.x1 + b.x0) / 2, math.min(a.top, b.top), math.max(a.top, b.top), period, off, phase)
end

-- Seconds into a `period` cycle, as a flip `phase` that centres a `duty` window on it.
local function centredOn(at: number, period: number, duty: number): number
	return (duty / 2 - at / period) % 1
end

-- A campfire on a pad: a warm glow and two logs (decor).
local function campfire(parts: { Part }, p: Pad)
	local x, z = p.x + 2, p.z
	table.insert(parts, Kit.prop({ 1.4, 1.4, 1.4 }, { x, p.top + 1.1, z }, "glow", { tone = 1, ghost = true }))
	table.insert(parts, Kit.prop({ 2.4, 0.4, 0.4 }, { x, p.top + 0.2, z }, "log", { ghost = true, yaw = 35 }))
	table.insert(parts, Kit.prop({ 2.4, 0.4, 0.4 }, { x, p.top + 0.2, z }, "log", { ghost = true, yaw = -35 }))
end

-- One dark zone per pad (from half a gap before it to half a gap after), each with its own light radius.
local function fadingNight(parts: { Part }, pads: { Pad }, lights: { number })
	for i, p in pads do
		local x0 = if i == 1 then 0 else (pads[i - 1].x1 + p.x0) / 2
		local x1 = if i == #pads then p.x1 else (p.x1 + pads[i + 1].x0) / 2
		table.insert(parts, dark(x0, x1, lights[i]))
	end
end

local M = {}
M.id = "LightsOut"
M.name = "Lights Out"
M.idea = 17

M.variants = {
	{
		-- Plain dark run: every platform has a glowing slime, so you hop from glow to glow. Two platforms carry dim red
		-- goo on one side (land on the slime's side), and a tall goo bar slides across the middle one.
		name = "Night Walk",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local pads =
				lay({ { 0, 0, 0 }, { 5.5, 0.5, 2 }, { 5.5, 0, -2 }, { 5.5, 1, 2 }, { 5.5, 0, -2 }, { 5.5, 0.5, 0 } })
			local parts: { Part } = {}
			for i, p in pads do
				table.insert(parts, slab(p))
				if i > 1 then
					table.insert(parts, slime(p.x, p.top, p.z + (if i == 3 or i == 5 then 1.5 else 0)))
				end
			end
			for _, i in { 3, 5 } do
				local p = pads[i]
				table.insert(parts, goo(p.x + 1, p.top, p.z - 2.5, 3, 3))
			end
			table.insert(parts, sweeper(pads[4], 1, 6, 3, 3.2))
			local length = pads[#pads].x1
			table.insert(parts, dark(0, length, 12))
			return Kit.section(length, pads[#pads].top, parts)
		end,
	},
	{
		-- Platforms zigzag left and right; a lit lantern on a post beside each one says which way to turn. Goo sits on
		-- the outer far corner of two of them, and two red lights blink across the gaps: jump through while they are out.
		name = "Lantern Zigzag",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local pads = lay({
				{ 0, 0, 0 },
				{ 5.5, 0, -4 },
				{ 5.5, 0.5, 4 },
				{ 5.5, 0, -4 },
				{ 5.5, 1, 4 },
				{ 5.5, 0, -4 },
				{ 5.5, 0.5, 0 },
			})
			local parts: { Part } = {}
			for i, p in pads do
				table.insert(parts, slab(p))
				if i > 1 and i < #pads then
					local side = if p.z > 0 then 1 else -1
					local pz = p.z + side * 6.2
					table.insert(parts, Kit.prop({ 0.6, 6, 0.6 }, { p.x, p.top + 3, pz }, "post", { ghost = true }))
					table.insert(
						parts,
						Kit.prop({ 1.4, 1.4, 1.4 }, { p.x, p.top + 6.7, pz }, "glow", { tone = 1, ghost = true })
					)
				end
			end
			for _, i in { 3, 5 } do
				local p = pads[i]
				local side = if p.z > 0 then 1 else -1
				table.insert(parts, goo(p.x1 - 1.5, p.top, p.z + side * 2.5, 3, 3))
			end
			table.insert(parts, gapLight(pads[3], pads[4], 3.4, 2.0))
			table.insert(parts, gapLight(pads[5], pads[6], 3.4, 2.0, 0.5))
			local length = pads[#pads].x1
			table.insert(parts, dark(0, length, 12))
			return Kit.section(length, pads[#pads].top, parts)
		end,
	},
	{
		-- Long wide floors with glowing green edge strips on all four sides, so you see where each one ends. A goo
		-- block on the two middle floors makes you pick a side, and a tall goo bar sweeps across each of them.
		name = "Glow Edges",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local pads = lay({ { 0, 0, 0 }, { 6, 0.5, 3 }, { 6, 0, -3 }, { 6, 1, 0 } }, 14, 10)
			local parts: { Part } = {}
			for _, p in pads do
				table.insert(parts, slab(p))
				local y = p.top + 0.1
				local strip: { [string]: any } = { tone = 2, ghost = true }
				for _, sx in { -1, 1 } do
					table.insert(
						parts,
						Kit.prop({ 0.4, 0.2, p.sz }, { p.x + sx * (p.sx / 2 - 0.2), y, p.z }, "glow", strip)
					)
					table.insert(
						parts,
						Kit.prop({ p.sx - 0.8, 0.2, 0.4 }, { p.x, y, p.z + sx * (p.sz / 2 - 0.2) }, "glow", strip)
					)
				end
			end
			table.insert(parts, goo(pads[2].x - 2, pads[2].top, pads[2].z - 2.5, 2, 5))
			table.insert(parts, goo(pads[3].x - 2, pads[3].top, pads[3].z + 2.5, 2, 5))
			table.insert(parts, sweeper(pads[2], 3.5, 8, 2, 3.2))
			table.insert(parts, sweeper(pads[3], 3.5, 8, 2, 3.2, 0.5))
			local length = pads[#pads].x1
			table.insert(parts, dark(0, length, 10))
			return Kit.section(length, pads[#pads].top, parts)
		end,
	},
	{
		-- Only the platform ahead glows; landing on it lights the next one, so the path builds as you go. A climb of 1
		-- to 1.5 a jump, goo on two of them and a tall goo bar sliding across a third.
		name = "Light the Way",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local pads = lay({
				{ 0, 0, 0 },
				{ 5, 1, 3 },
				{ 5.5, 2.5, -2 },
				{ 5, 3.5, 2 },
				{ 5.5, 5, -3 },
				{ 5, 6, 1 },
				{ 5.5, 7.5, 0 },
			})
			local parts: { Part } = {}
			for i, p in pads do
				table.insert(parts, slab(p, if i < #pads then { trigger = `way{i}` } else nil))
				if i == 2 then
					table.insert(parts, slime(p.x, p.top, p.z))
				elseif i > 2 then
					table.insert(parts, litBy(p.x, p.top, p.z, `way{i - 1}`))
				end
			end
			for _, i in { 4, 6 } do
				local p = pads[i]
				table.insert(parts, goo(p.x1 - 1.5, p.top, p.z + 2.5, 3, 3))
			end
			table.insert(parts, sweeper(pads[5], 1, 6, 3, 3.2))
			local length = pads[#pads].x1
			table.insert(parts, dark(0, length, 10))
			return Kit.section(length, pads[#pads].top, parts)
		end,
	},
	{
		-- A dark staircase that climbs 3 a step; every other step carries a glowing slime and your own light shows
		-- the step under you. Goo on two steps and a red light blinking across one gap.
		name = "Glow Stairs",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local list = {}
			local zs = { 0, 2, -2, 2, -2, 2, 0 }
			for i = 1, 7 do
				table.insert(list, { 5, (i - 1) * 3, zs[i] })
			end
			local pads = lay(list)
			local parts: { Part } = {}
			for i, p in pads do
				table.insert(parts, slab(p))
				if i % 2 == 0 then
					table.insert(parts, slime(p.x, p.top, p.z))
				end
			end
			for _, i in { 3, 5 } do
				local p = pads[i]
				table.insert(parts, goo(p.x1 - 1.5, p.top, p.z + (if p.z > 0 then -2.5 else 2.5), 3, 3))
			end
			table.insert(parts, gapLight(pads[4], pads[5], 3.4, 2.0))
			local length = pads[#pads].x1
			table.insert(parts, dark(0, length, 14))
			return Kit.section(length, pads[#pads].top, parts)
		end,
	},
	{
		-- A firefly waits on each platform until you land, then flies on over the next one (each landing sends one
		-- out). A gentle curve, goo on one platform and a tall goo bar sliding across another.
		name = "Firefly Friend",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local pads =
				lay({ { 0, 0, 0 }, { 5.5, 1, 3 }, { 5.5, 2.5, 3 }, { 5.5, 1.5, 3 }, { 5.5, 3, -1 }, { 5.5, 2, -3 } })
			local parts: { Part } = {}
			for i, p in pads do
				local last = i == #pads
				table.insert(parts, slab(p, if last then nil else { trigger = `fly{i}` }))
				if not last then
					local q = pads[i + 1]
					table.insert(
						parts,
						Kit.prop({ 0.8, 0.8, 0.8 }, { p.x, p.top - 0.5, p.z }, "glow", {
							tone = 1,
							ghost = true,
							shape = "ball",
							start = `fly{i}`,
							motion = {
								kind = "path",
								points = { { 0, 0, 0 }, { 0, 3.5, 0 }, { q.x - p.x, q.top - p.top + 3.5, q.z - p.z } },
								period = 1.6,
								once = true,
							},
						})
					)
				end
			end
			local p4 = pads[4]
			table.insert(parts, goo(p4.x1 - 1.5, p4.top, p4.z + 2.5, 3, 3))
			table.insert(parts, sweeper(pads[5], 0, 6, 3, 3.2))
			local length = pads[#pads].x1
			table.insert(parts, dark(0, length, 12))
			return Kit.section(length, pads[#pads].top, parts)
		end,
	},
	{
		-- All the slimes blink together on the beat clock: 1.4 s on, then 2.8 s dark with only your small light, so you
		-- look, then jump. Static goo on two platforms, a tall goo bar sliding across a third, and two red lights in the
		-- gaps that go out only while the slimes glow: the flash is your one chance to jump.
		name = "Blink",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local pads = lay({
				{ 0, 0, 0 },
				{ 5.5, 1.5, -3 },
				{ 5.5, 0, 2 },
				{ 5.5, 2.5, -2 },
				{ 5.5, 1, 3 },
				{ 5.5, 3, -1 },
				{ 5.5, 2, 0 },
			})
			local beats = 7 -- 4.2 s at Kit.BPM
			local duty = 1.4 / Kit.beat(beats)
			local parts: { Part } = {}
			for i, p in pads do
				table.insert(parts, slab(p))
				if i > 1 then
					table.insert(
						parts,
						slime(p.x, p.top, p.z, { beat = beats, motion = { kind = "flip", duty = duty, period = 1 } })
					)
				end
			end
			for _, i in { 3, 6 } do
				local p = pads[i]
				table.insert(parts, goo(p.x1 - 1.5, p.top, p.z - 2.5, 3, 3))
			end
			table.insert(parts, sweeper(pads[4], 1, 6, 3, 2.4))
			for _, i in { 2, 5 } do
				local light = gapLight(pads[i], pads[i + 1], 1, duty, 1 - duty)
				light.beat = beats
				table.insert(parts, light)
			end
			local length = pads[#pads].x1
			table.insert(parts, dark(0, length, 8))
			return Kit.section(length, pads[#pads].top, parts)
		end,
	},
	{
		-- The firefly leads, but waits only 2 s over each platform: step onto the first and it sets off, dawdle and
		-- it flies on without you. Side-steps of 6, goo on two platforms and tall goo bars sliding across two more.
		name = "Firefly Pace",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local pads = lay({
				{ 0, 0, 0 },
				{ 5, 1, -3 },
				{ 5, 0, 3 },
				{ 5, 1.5, -3 },
				{ 5, 0.5, 3 },
				{ 5, 2, -3 },
				{ 5, 1, 3 },
				{ 5, 1.5, 0 },
			})
			local parts: { Part } = {}
			for i, p in pads do
				table.insert(parts, slab(p, if i == 1 then { trigger = "pace" } else nil))
			end
			local p2 = pads[2]
			local points = {}
			for i = 2, #pads do
				local p = pads[i]
				table.insert(points, { p.x - p2.x, p.top - p2.top, p.z - p2.z })
			end
			local hold, fly = 2, 0.6
			table.insert(
				parts,
				Kit.prop({ 0.9, 0.9, 0.9 }, { p2.x, p2.top + 3.5, p2.z }, "glow", {
					tone = 1,
					ghost = true,
					shape = "ball",
					start = "pace",
					motion = {
						kind = "path",
						points = points,
						hold = hold,
						period = (hold + fly) * (#points - 1),
						once = true,
					},
				})
			)
			for _, i in { 4, 6 } do
				local p = pads[i]
				table.insert(parts, goo(p.x1 - 1.5, p.top, p.z - 2.5, 3, 3))
			end
			table.insert(parts, sweeper(pads[3], 0, 6, 3, 2.4))
			table.insert(parts, sweeper(pads[7], 0, 6, 3, 2.4, 0.5))
			local length = pads[#pads].x1
			table.insert(parts, dark(0, length, 8))
			return Kit.section(length, pads[#pads].top, parts)
		end,
	},
	{
		-- A dark field of scattered stones with no rows: the stone you land on lights the stones you can reach from it,
		-- all safe, so you pick one and feel your way across. Goo on two stones, and two red lights blink across the
		-- whole field: whichever way you pick, you cross them while they are out.
		name = "Feel the Way",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local pitch = PAD + 4.5
			-- { column, z } per stone, and which stones each one lights (indices into this list).
			local stones = {
				{ 0, 0 }, -- 1 entry
				{ 1, -7 },
				{ 1, 6 },
				{ 2, -8 },
				{ 2, 2 },
				{ 3, -3 },
				{ 3, 8 },
				{ 4, -8 },
				{ 4, 3 },
				{ 5, -2 },
				{ 5, 8 },
				{ 6, -7 },
				{ 6, 3 },
				{ 7, 0 }, -- 14 exit
			}
			local lights = {
				{ 2, 3 },
				{ 4, 5 },
				{ 5 },
				{ 6 },
				{ 6, 7 },
				{ 8, 9 },
				{ 9 },
				{ 10 },
				{ 10, 11 },
				{ 12, 13 },
				{ 13 },
				{ 14 },
				{ 14 },
			}
			local pads: { Pad } = {}
			for _, s in stones do
				local x0 = s[1] * pitch
				table.insert(pads, { x = x0 + PAD / 2, z = s[2], top = 0, x0 = x0, x1 = x0 + PAD, sx = PAD, sz = PAD })
			end
			local parts: { Part } = {}
			for i, p in pads do
				table.insert(parts, slab(p, if lights[i] then { trigger = `feel{i}` } else nil))
			end
			for from, list in lights do
				local a = pads[from]
				for _, to in list do
					local b = pads[to]
					local dx, dz = a.x - b.x, a.z - b.z
					local d = math.sqrt(dx * dx + dz * dz)
					table.insert(parts, litBy(b.x + dx / d * 2.4, b.top, b.z + dz / d * 2.4, `feel{from}`))
				end
			end
			for _, i in { 8, 10 } do
				local p = pads[i]
				table.insert(parts, goo(p.x1 - 1.5, p.top, p.z + (if p.z > 0 then 2.5 else -2.5), 3, 3))
			end
			for k, col in { 2, 5 } do
				table.insert(parts, redLight(col * pitch + PAD / 2, 0, 0, 2.6, 1.25, (k - 1) * 0.5))
			end
			local length = pads[#pads].x1
			table.insert(parts, dark(0, length, 8))
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Two lamps on posts in the middle sweep a beam round; each platform glows only while the beam is on it, so you
		-- wait for the sweep to see your next jump. Platforms in two staggered rows round the lamps.
		name = "Lighthouse",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local pads: { Pad } = {}
			local function add(x0: number, top: number, z: number)
				table.insert(pads, { x = x0 + PAD / 2, z = z, top = top, x0 = x0, x1 = x0 + PAD, sx = PAD, sz = PAD })
			end
			add(0, 0, 0)
			local tops = { 1, 2, 1, 2.5, 1.5, 2.5 }
			for k = 1, 6 do
				add(13 + (k - 1) * 11, tops[k], if k % 2 == 1 then 6 else -6)
			end
			add(pads[#pads].x1 + 5, 1.5, 0)
			local turn, sweep = 8, 4 -- a two-ended beam turns once per 8 s: each platform is lit every 4 s
			local duty = 0.2
			local lamps = { pads[3].x, pads[6].x }
			local parts: { Part } = {}
			for i, p in pads do
				local extra: { [string]: any }? = nil
				if i > 1 then
					local lx = if math.abs(p.x - lamps[1]) < math.abs(p.x - lamps[2]) then lamps[1] else lamps[2]
					local angle = math.deg(math.atan2(-p.z, p.x - lx)) % 180
					local at = angle / 360 * turn
					extra = {
						tone = 2,
						motion = {
							kind = "flip",
							solid = true,
							duty = duty,
							period = sweep,
							phase = centredOn(at, sweep, duty),
						},
					}
				end
				table.insert(parts, slab(p, extra))
			end
			for _, lx in lamps do
				table.insert(parts, Kit.prop({ 1.5, 14, 1.5 }, { lx, 3, 0 }, "post", {}))
				table.insert(
					parts,
					Kit.prop({ 2, 2, 2 }, { lx, 11, 0 }, "glow", { tone = 1, ghost = true, shape = "ball" })
				)
				table.insert(
					parts,
					Kit.prop({ Kit.WIDTH, 0.4, 1 }, { lx, 9, 0 }, "glow", {
						tone = 1,
						ghost = true,
						motion = { kind = "spin", period = turn },
					})
				)
			end
			local p4 = pads[4]
			table.insert(parts, goo(p4.x1 - 1.5, p4.top, p4.z + 2.5, 3, 3))
			table.insert(parts, sweeper(pads[6], 0, 6, 2.5, 2.4))
			table.insert(parts, sweeper(pads[3], 0, 6, 2.5, 2.4, 0.5))
			local length = pads[#pads].x1
			table.insert(parts, dark(0, length, 8))
			return Kit.section(length, pads[#pads].top, parts)
		end,
	},
	{
		-- Platforms slide side to side in the dark, each carrying its glowing slime, so you track a moving glow before
		-- you jump. Two of them carry red goo too, and red lights blink across two gaps.
		name = "Dark Movers",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local pads = lay({
				{ 0, 0, 0 },
				{ 5, 1, -3.5 },
				{ 5, 0, 3.5 },
				{ 5, 1.5, -3.5 },
				{ 5, 0.5, 3.5 },
				{ 5, 2, -3.5 },
				{ 5, 1, 0 },
			})
			local parts: { Part } = {}
			for i, p in pads do
				if i == 1 or i == #pads then
					table.insert(parts, slab(p))
				else
					local motion = { kind = "slide", axis = "z", amp = 4, period = 2.6, phase = (i - 2) * 0.2 }
					table.insert(parts, slab(p, { motion = motion }))
					table.insert(parts, slime(p.x, p.top, p.z, { motion = table.clone(motion) }))
					if i == 3 or i == 5 then
						table.insert(parts, goo(p.x1 - 1.25, p.top, p.z, 2.5, 3, { motion = table.clone(motion) }))
					end
				end
			end
			table.insert(parts, gapLight(pads[2], pads[3], 2.8, 1.4))
			table.insert(parts, gapLight(pads[5], pads[6], 2.8, 1.4, 0.5))
			local length = pads[#pads].x1
			table.insert(parts, dark(0, length, 8))
			return Kit.section(length, pads[#pads].top, parts)
		end,
	},
	{
		-- Wide dark floors with glowing slimes, but red goo blocks sit on them, glowing dim red, so you weave past and
		-- jump over in the dark. One block slides across.
		name = "Red in the Dark",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local pads = lay({ { 0, 0, 0 }, { 5.5, 0, 0 }, { 5.5, 0, 0 }, { 5.5, 0, 0 } }, 14, 12)
			local parts: { Part } = {}
			for i, p in pads do
				table.insert(parts, slab(p))
				table.insert(parts, slime(p.x1 - 2, p.top, if i % 2 == 0 then -4 else 4))
			end
			local a, b, c, d = pads[1], pads[2], pads[3], pads[4]
			table.insert(parts, goo(a.x0 + 9, 0, -3, 2, 6))
			table.insert(parts, goo(b.x0 + 4, 0, 3, 2, 6))
			table.insert(parts, sweeper(b, 3, 11, 4, 2.6))
			table.insert(parts, goo(c.x0 + 3.5, 0, -3, 2, 6))
			table.insert(parts, goo(c.x0 + 10, 0, 3, 2, 6))
			table.insert(parts, goo(d.x0 + 3, 0, 3, 2, 6))
			table.insert(parts, sweeper(d, 2, 11, 4, 2.6, 0.5))
			local length = d.x1
			table.insert(parts, dark(0, length, 10))
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- The road forks: a long way of seven small stones lined with glowing slimes, guarded by two blinking red
		-- lights, or a short way of four pads, wider gaps, goo and a sliding goo bar, pitch dark apart from your own
		-- small light. Both rejoin on one pad.
		name = "Dark Shortcut",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local entry: Pad = { x = 4, z = 0, top = 0, x0 = 0, x1 = 8, sx = 8, sz = Kit.WIDTH }
			local exitX0 = 65
			local parts: { Part } = {}
			table.insert(parts, slab(entry))
			-- The lit road (main): 7 stones 3.5 long, 8 wide, evenly spread from the entry to the exit.
			local stoneLong = 3.5
			local gap = (exitX0 - entry.x1 - 7 * stoneLong) / 8
			for k = 1, 7 do
				local x0 = entry.x1 + k * gap + (k - 1) * stoneLong
				local p: Pad =
					{ x = x0 + stoneLong / 2, z = -7, top = 0, x0 = x0, x1 = x0 + stoneLong, sx = stoneLong, sz = 8 }
				table.insert(parts, slab(p))
				table.insert(parts, slime(p.x, p.top, p.z))
				if k == 3 or k == 5 then
					-- a red light over this stone, across the lit road only (z -12..-1)
					table.insert(
						parts,
						Kit.hazard({ 1, GOO_WALL + 2, 11 }, { p.x, GOO_WALL / 2 - 1, -6.5 }, {
							motion = { kind = "flip", duty = 0.5, period = 2.8, phase = if k == 5 then 0.5 else 0 },
						})
					)
				end
			end
			-- The dark road ("dark"): 4 pads with 5-stud gaps, climbing a little.
			local tops = { 1, 2.5, 1.5, 2.5 }
			local darkPads: { Pad } = {}
			for k = 1, 4 do
				local x0 = entry.x1 + 5 + (k - 1) * (PAD + 5)
				local p: Pad = { x = x0 + PAD / 2, z = 7, top = tops[k], x0 = x0, x1 = x0 + PAD, sx = PAD, sz = PAD }
				table.insert(darkPads, p)
				table.insert(parts, slab(p, { route = "dark", tone = 1 }))
			end
			for _, k in { 2, 4 } do
				local p = darkPads[k]
				table.insert(parts, goo(p.x, p.top, p.z + 2.5, 3, 3))
			end
			table.insert(parts, sweeper(darkPads[3], 1, 6, 2, 2.4))
			local exit: Pad = { x = exitX0 + 5, z = 0, top = 1, x0 = exitX0, x1 = exitX0 + 10, sx = 10, sz = Kit.WIDTH }
			table.insert(parts, dark(0, exit.x1, 8))
			table.insert(parts, slab(exit))
			return Kit.section(exit.x1, exit.top, parts)
		end,
	},
	{
		-- No slimes: your light shrinks a step on every platform (12, 8, 5 studs) and each campfire pad fills it back
		-- up. The dark platforms between the fires crack and melt soon after you land, so you hurry from fire to fire,
		-- and a goo bar sweeps across each campfire so you can't rest there.
		name = "Campfire Hop",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local pads = lay({
				{ 0, 0, 0 },
				{ 5, 1, -2 },
				{ 5, 2, 2 },
				{ 5, 1, 0 },
				{ 5, 2.5, -2 },
				{ 5, 1.5, 2 },
				{ 5, 3, 0 },
				{ 5, 2, -2 },
				{ 5, 2.5, 1 },
			}, 7)
			local fires = { [1] = true, [4] = true, [7] = true }
			local parts: { Part } = {}
			for i, p in pads do
				if fires[i] or i == #pads then
					table.insert(parts, slab(p, if fires[i] then { tone = 2 } else nil))
				else
					table.insert(parts, slab(p, { motion = { kind = "melt", delay = 1.2, away = 3 } }))
				end
				if fires[i] then
					campfire(parts, p)
				end
			end
			table.insert(parts, sweeper(pads[4], -1.5, 6, 3, 2.4))
			table.insert(parts, sweeper(pads[7], -1.5, 6, 3, 2.4, 0.5))
			fadingNight(parts, pads, { 12, 8, 5, 12, 8, 5, 12, 8, 4 })
			local length = pads[#pads].x1
			return Kit.section(length, pads[#pads].top, parts)
		end,
	},
	{
		-- No slimes at all: a lightning flash lights every platform for 0.6 s every 3 s, and you jump from
		-- memory in between. Gaps of 5 to 6, rises up to 2.5, tall goo bars sliding across two platforms and a red light
		-- blinking across one gap.
		name = "Thunder Flash",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local pads = lay({
				{ 0, 0, 0 },
				{ 5.5, 2, -2 },
				{ 6, 0.5, 2 },
				{ 5, 3, -3 },
				{ 6, 5.5, 1 },
				{ 5.5, 4, 3 },
				{ 6, 6.5, -1 },
				{ 5.5, 5, 0 },
			})
			local flash = { kind = "flip", solid = true, duty = 0.6 / 3, period = 3 }
			local parts: { Part } = {}
			for i, p in pads do
				table.insert(parts, slab(p, if i > 1 then { tone = 2, motion = table.clone(flash) } else nil))
			end
			for _, i in { 4, 6 } do
				local p = pads[i]
				table.insert(parts, sweeper(p, 1, 6, 3, 1.9))
			end
			table.insert(parts, gapLight(pads[2], pads[3], 2.4, 1.1))
			local length = pads[#pads].x1
			table.insert(parts, dark(0, length, 6))
			return Kit.section(length, pads[#pads].top, parts)
		end,
	},
	{
		-- Dark, moving and blinking: sliding platforms carry their slimes, but the glowing track under each one shows
		-- only 1 s out of every 3 s, so you judge where a platform will be when you land. Red lights blink across two
		-- of the gaps, so you also wait for them to go out.
		name = "Night Shift",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local pads = lay({
				{ 0, 0, 0 },
				{ 5.5, 1, -3 },
				{ 5.5, 0, 3 },
				{ 5.5, 1.5, -3 },
				{ 5.5, 0.5, 3 },
				{ 5.5, 2, -3 },
				{ 5.5, 1, 3 },
				{ 5.5, 1.5, 0 },
			})
			local amp, period = 3, 3
			local parts: { Part } = {}
			for i, p in pads do
				if i == 1 or i == #pads then
					table.insert(parts, slab(p))
				else
					local phase = ((i - 2) * 0.3) % 1
					local motion = { kind = "slide", axis = "z", amp = amp, period = period, phase = phase }
					table.insert(parts, slab(p, { motion = motion }))
					table.insert(parts, slime(p.x, p.top, p.z, { motion = table.clone(motion) }))
					table.insert(
						parts,
						Kit.prop({ 2, 0.2, p.sz + 2 * amp }, { p.x, p.top - 1.3, p.z }, "glow", {
							tone = 2,
							ghost = true,
							motion = { kind = "flip", duty = 1 / 3, period = period, phase = phase },
						})
					)
				end
			end
			table.insert(parts, gapLight(pads[3], pads[4], 2.4, 1.1))
			table.insert(parts, gapLight(pads[6], pads[7], 2.4, 1.1, 0.5))
			local length = pads[#pads].x1
			table.insert(parts, dark(0, length, 6))
			return Kit.section(length, pads[#pads].top, parts)
		end,
	},
	{
		-- A climb of 3 a jump over a red goo pool, lit only by a slow beam of light sweeping up it once every 5 s;
		-- each platform glows while the beam is on it, so every jump waits for the light to come round.
		name = "Beam Over Goo",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local list = {}
			local zs = { 0, -2, 2, -2, 2, -2, 0 }
			for i = 1, 7 do
				table.insert(list, { 5.5, (i - 1) * 3, zs[i] })
			end
			local pads = lay(list)
			local length = pads[#pads].x1
			local rise = pads[#pads].top
			local period, duty = 5, 0.2
			local parts: { Part } = {}
			for i, p in pads do
				local extra: { [string]: any }? = nil
				if i > 1 then
					local at = p.x / length * period
					extra = {
						tone = 2,
						motion = {
							kind = "flip",
							solid = true,
							duty = duty,
							period = period,
							phase = centredOn(at, period, duty),
						},
					}
				end
				table.insert(parts, slab(p, extra))
			end
			for _, i in { 3, 5 } do
				local p = pads[i]
				table.insert(parts, goo(p.x1 - 1.5, p.top, p.z + (if p.z > 0 then 2.5 else -2.5), 3, 3))
			end
			table.insert(parts, sweeper(pads[4], 0, 6, 3, 2.3))
			table.insert(parts, sweeper(pads[6], 0, 6, 3, 2.3, 0.2))
			-- The beam: a bar of light high over the climb, sweeping from the start to the end, then back in a blink.
			table.insert(
				parts,
				Kit.prop({ 1, 0.4, Kit.WIDTH }, { 0.5, 9, 0 }, "glow", {
					tone = 1,
					ghost = true,
					motion = {
						kind = "path",
						points = { { 0, 0, 0 }, { length - 1, rise, 0 } },
						period = period,
						loop = true,
						jump = true,
					},
				})
			)
			-- The goo pool under it all.
			table.insert(parts, Kit.hazard({ length, 1, Kit.WIDTH }, { length / 2, -6.5, 0 }))
			table.insert(parts, dark(0, length, 6))
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- Your light starts big and shrinks on every platform (16 down to 3 studs); only one campfire halfway fills it
		-- up again, so read the far jumps early while you can still see them. The dark platforms melt soon after you
		-- land, two carry dim red goo, and tall goo bars sweep across two more.
		name = "Fading Lantern",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local pads = lay({
				{ 0, 0, 0 },
				{ 5.5, 2, -2 },
				{ 6, 4, 2 },
				{ 5, 2.5, -1 },
				{ 6, 4.5, 0 },
				{ 5.5, 7, 2 },
				{ 6, 5.5, -2 },
				{ 5.5, 8, 0 },
			})
			local fire = 5
			local parts: { Part } = {}
			for i, p in pads do
				if i == 1 or i == fire or i == #pads then
					table.insert(parts, slab(p, if i == fire then { tone = 2 } else nil))
				else
					table.insert(parts, slab(p, { motion = { kind = "melt", delay = 0.9, away = 2.5 } }))
				end
			end
			campfire(parts, pads[fire])
			for _, i in { 3, 7 } do
				local p = pads[i]
				table.insert(parts, goo(p.x1 - 1.5, p.top, p.z + (if p.z > 0 then 2.5 else -2.5), 3, 3))
			end
			table.insert(parts, sweeper(pads[4], 0, 6, 3, 1.9))
			table.insert(parts, sweeper(pads[6], 0, 6, 3, 1.9, 0.5))
			fadingNight(parts, pads, { 16, 11, 7, 4, 16, 10, 6, 3 })
			local length = pads[#pads].x1
			return Kit.section(length, pads[#pads].top, parts)
		end,
	},
}

return M
