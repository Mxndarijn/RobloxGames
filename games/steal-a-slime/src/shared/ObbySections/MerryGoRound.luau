--!strict
--[[
	Merry-go-round (obby idea 9, docs/obby-variants/9.json; contract/obby-sections.md)

	Spinning jelly disks and planks that carry you round: land on a moving floor, ride it, jump off its moving edge
	when it lines up with the next one. Red see-through arms sweep low over some disks (hop them or time them), red
	spokes lie welded on others (land in a slice), some disks turn back and forth (sweep), some tip (rock), seats
	circle a post (path orbit).

	Every spinning floor wears an `arrows` marker that turns with it, so the way it spins shows. Hand-made variants
	(the design has no generator): the seed is ignored. Variants are appended, never reordered.

	Tuned per §10 (one notch harder than the drafts): faster spins, 5-5.5-stud gaps where the draft had 4, and every
	walking line broken by a gap of at least 4, a raised ledge (more than the walker's 1-stud step) or a hazard.
	Second pass (tough review): hazard windows pulled toward the tier floor (easy about 1.5 s, medium 1.05-1.3 s,
	hard 0.8-0.85 s), a hazard added to most variants that only had a moving floor, and exits raised where the last
	jump was flat.
	Third pass (walk-forward and masher checks, §9): jumping on every landing must not be a way across. Single big
	disks get a red canopy beam over the hub line, just over head height (walk under it, never jump under it), the
	Blender's second arm rides high for the same reason, the Propeller's plank sits 2.5 up on a pole too tall to
	jump, and the Clockwork exit sits 2.5 over the plank so nothing walks onto it.
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

local PAD = 8 -- entry and exit pad length
local ARM_LOW = 0.5 -- a low arm's bottom over its floor ...
local ARM_THICK = 1.2 -- ... and its height: the top sits 1.7 over the floor, an easy hop
local ARM_WIDE = 1.2
local HUB = 1.6 -- the pivot post on a disk with arms
local CANOPY = Kit.HEAD + 0.5 -- a canopy beam's bottom over its floor: clear of a head, not of a jump
local CANOPY_WIDE = 3
local TAU = 2 * math.pi

local function spin(period: number, phase: number?): Kit.Motion
	return { kind = "spin", period = period, phase = phase }
end

-- A floor pad from x0 to x1 (full lane width), top at `top`.
local function pad(x0: number, x1: number, top: number, tone: number?): Kit.Part
	return Kit.slab((x0 + x1) / 2, top, 0, x1 - x0, Kit.WIDTH, "jelly", { tone = tone or 1 })
end

-- A disk `d` across centred on (cx, cz), top at `top`, with `motion`. Its arrows turn with it.
local function disc(cx: number, top: number, d: number, motion: Kit.Motion?, extra: { [string]: any }?): Kit.Part
	local part = Kit.slab(cx, top, 0, d, d, "jelly", { shape = "disc", motion = motion, marker = "arrows", tone = 2 })
	if extra then
		for k, v in extra do
			(part :: any)[k] = v
		end
	end
	return part
end

-- The stand under a disk (decor, out of the way of every jump).
local function stand(cx: number, top: number, cz: number?): Kit.Part
	local h = 6
	return Kit.prop({ 3, h, 3 }, { cx, top - Kit.THICK - h / 2, cz or 0 }, "post", { shape = "disc" })
end

-- The pivot post on top of a disk that has arms.
local function hub(cx: number, top: number, cz: number?, lift: number?): Kit.Part
	local h = ARM_LOW + (lift or 0) + ARM_THICK + 0.5
	return Kit.prop({ HUB, h, HUB }, { cx, top + h / 2, cz or 0 }, "post", { shape = "disc" })
end

-- A low red arm `length` long spinning round (cx, cz) over a floor whose top is `top`.
local function arm(
	cx: number,
	top: number,
	length: number,
	period: number,
	phase: number?,
	lift: number?,
	wide: number?
): Kit.Part
	local bottom = top + ARM_LOW + (lift or 0)
	return Kit.hazard({ length, ARM_THICK, wide or ARM_WIDE }, { cx, bottom + ARM_THICK / 2, 0 }, {
		motion = spin(period, phase),
	})
end

-- A red canopy beam across the lane over (cx, *), its bottom CANOPY over a floor whose top is `top`: just over
-- a standing head, so you walk under it, but a jump under it hits it (mashing jump is no way across).
local function canopy(cx: number, top: number): Kit.Part
	return Kit.hazard({ CANOPY_WIDE, ARM_THICK, Kit.WIDTH }, { cx, top + CANOPY + ARM_THICK / 2, 0 })
end

-- A red spoke lying on a disk at (cx, 0), `length` long, turning with the disk (same period and phase): a slice
-- line welded to the floor. Two at a quarter turn apart cut the disk into four slices.
local function spoke(cx: number, top: number, length: number, period: number, phase: number): Kit.Part
	return Kit.hazard({ length, ARM_THICK, ARM_WIDE }, { cx, top + ARM_THICK / 2, 0 }, {
		motion = spin(period, phase),
	})
end

-- A seat disk `d` across circling (cx, 0) at radius `r` every `period` s, starting at `angle0` degrees.
local function seat(cx: number, top: number, d: number, r: number, angle0: number, period: number): Kit.Part
	local a0 = math.rad(angle0)
	local dir = if period > 0 then 1 else -1
	local n = 16
	local points = {}
	for k = 0, n - 1 do
		local a = a0 + dir * TAU * k / n
		table.insert(points, { r * math.cos(a) - r * math.cos(a0), 0, -r * math.sin(a) + r * math.sin(a0) })
	end
	return Kit.slab(cx + r * math.cos(a0), top, -r * math.sin(a0), d, d, "jelly", {
		shape = "disc",
		tone = 3,
		motion = { kind = "path", points = points, period = math.abs(period), loop = true },
	})
end

-- A turning plank `long` x `wide` centred on (cx, 0), top at `top`.
local function plank(cx: number, top: number, long: number, wide: number, motion: Kit.Motion): Kit.Part
	return Kit.slab(cx, top, 0, long, wide, "plank", { motion = motion, marker = "arrows" })
end

--[[
	A row of disks along the lane: entry pad, then each disk after `gap` studs, then the exit pad. `disks` lists
	{ d, top, motion, arms? } where arms = { { length, period, phase? } }. Returns parts, the exit pad's start.
]]
type Disk = {
	d: number,
	top: number,
	motion: Kit.Motion?,
	arms: { { number } }?,
	spoke: boolean?,
	extra: { [string]: any }?,
}

local function row(parts: { Kit.Part }, disks: { Disk }, gap: number | { number }, from: number): (number, { number })
	local x = from
	local centres = {}
	for i, k in disks do
		local g = if type(gap) == "table" then gap[i] else gap
		local cx = x + g + k.d / 2
		table.insert(parts, disc(cx, k.top, k.d, k.motion, k.extra))
		table.insert(parts, stand(cx, k.top))
		if k.spoke and k.motion then
			table.insert(parts, spoke(cx, k.top, k.d, k.motion.period :: number, k.motion.phase or 0))
		end
		if k.arms then
			local lift = 0
			for _, a in k.arms do
				lift = math.max(lift, a[4] or 0)
			end
			table.insert(parts, hub(cx, k.top, 0, lift))
			for _, a in k.arms do
				table.insert(parts, arm(cx, k.top, a[1], a[2], a[3], a[4], a[5]))
			end
		end
		table.insert(centres, cx)
		x = cx + k.d / 2
	end
	return x, centres
end

local M = {}
M.id = "MerryGoRound"
M.name = "Merry-go-round"
M.idea = 9

M.variants = {
	{
		-- Two big disks turning the same way: learn that the floor carries you and that you jump off a moving edge.
		-- Draft: spin 10 s, 4-stud gaps, 20-stud disks; now 16-stud disks at 6 s, 5.5-stud gaps, exit 1.5 up.
		name = "Slow Ride",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = { pad(0, PAD, 0) }
			local x = row(parts, {
				{ d = 16, top = 0, motion = spin(6) },
				{ d = 16, top = 0, motion = spin(6, 0.25) },
			}, 5.5, PAD)
			local length = x + 5.5 + PAD
			table.insert(parts, pad(x + 5.5, length, 1.5, 3))
			return Kit.section(length, 1.5, parts)
		end,
	},
	{
		-- Three disks turning opposite ways in turn: every landing pulls you a new way. The middle one carries a red
		-- spoke welded across it: land in one half, leave from it. Draft 8 s; 5 / 4.5 s here.
		name = "Turn Turn",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = { pad(0, PAD, 0) }
			local x = row(parts, {
				{ d = 14, top = 0, motion = spin(5) },
				{ d = 14, top = 0, motion = spin(-4.5), spoke = true },
				{ d = 14, top = 0, motion = spin(5) },
			}, 5.5, PAD)
			local length = x + 5.5 + PAD
			table.insert(parts, pad(x + 5.5, length, 0, 3))
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- One big disk with one low red arm going round the other way: hop it (or time it) once, then jump off.
		-- A red canopy beam hangs over the hub line: cross under it on foot, so hop the arm anywhere but there.
		name = "One Sweep",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = { pad(0, PAD + 2, 0) }
			local x = row(parts, {
				{ d = 22, top = 0, motion = spin(6), arms = { { 22, -3.5 } } },
			}, 4.5, PAD + 2)
			table.insert(parts, canopy(PAD + 2 + 4.5 + 11, 0))
			local length = x + 5 + PAD + 2
			table.insert(parts, pad(x + 5, length, 1.5, 3))
			return Kit.section(length, 1.5, parts)
		end,
	},
	{
		-- Big, small, big: the small middle disk gives little room to land, and a short red arm goes round on it
		-- the other way: land, hop it, jump on.
		name = "Big, Small, Big",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = { pad(0, PAD, 0) }
			local x = row(parts, {
				{ d = 20, top = 0, motion = spin(5) },
				{ d = 9, top = 0, motion = spin(5, 0.5), arms = { { 9, -5 } } },
				{ d = 16, top = 0, motion = spin(5) },
			}, 5.5, PAD)
			local length = x + 5.5 + PAD
			table.insert(parts, pad(x + 5.5, length, 1.5, 3))
			return Kit.section(length, 1.5, parts)
		end,
	},
	{
		-- Each disk 3 studs higher than the last, turning opposite ways in turn: jump up onto a moving floor.
		name = "Spiral Steps",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = { pad(0, PAD, 0) }
			local x = row(parts, {
				{ d = 14, top = 3, motion = spin(6) },
				{ d = 14, top = 6, motion = spin(-6, 0.3) },
				{ d = 14, top = 9, motion = spin(6, 0.6) },
			}, 5, PAD)
			local length = x + 5 + PAD
			table.insert(parts, pad(x + 5, length, 12, 3))
			return Kit.section(length, 12, parts)
		end,
	},
	{
		-- The disk sits still until you step on it, then it turns (kit: at one speed, not faster each lap), carrying
		-- you round to the small exit pad in the right corner, 2.5 up: ride until the rim passes it, then jump.
		-- A low red arm goes round it the other way, and a red canopy beam over the hub line: no jumping under it.
		name = "Wind Up",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = { pad(0, PAD + 2, 0) }
			local x = row(parts, {
				{
					d = 20,
					top = 0,
					motion = spin(5),
					arms = { { 20, -3.5 } },
					extra = { trigger = "windup", start = "windup" },
				},
			}, 5, PAD + 2)
			table.insert(parts, canopy(PAD + 2 + 5 + 10, 0))
			local length = x + 5 + PAD
			table.insert(parts, Kit.slab(x + 5 + PAD / 2, 2.5, 8, PAD, 8, "jelly", { tone = 3 }))
			return Kit.section(length, 2.5, parts)
		end,
	},
	{
		-- No disk, just a wide plank turning on a pole, 2.5 studs over the pad (too high to walk on): hop on when an
		-- end comes by, ride it round, hop up off the end when it points at the exit. The pole sticks up through the
		-- middle, too tall to jump, so you ride an end round instead of running across.
		name = "Propeller",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = { pad(0, PAD, 0) }
			local cx = PAD + 1.5 + 11
			table.insert(parts, plank(cx, 2.5, 22, 8, spin(4)))
			table.insert(parts, stand(cx, 2.5))
			-- the pole it turns on sticks up through the middle, too tall to jump: ride an end round, not across
			table.insert(parts, Kit.prop({ 4, 10, 4 }, { cx, 2.5 + 5, 0 }, "post", { shape = "disc" }))
			local x = cx + 11 + 1.5
			local length = x + PAD
			table.insert(parts, pad(x, length, 3.5, 3))
			return Kit.section(length, 3.5, parts)
		end,
	},
	{
		-- Two red arms going round one disk at different speeds and ways (one full, one half length): the safe gap
		-- between them keeps moving. A red canopy beam over the hub line: no hopping under it.
		name = "Two Arms",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = { pad(0, PAD + 2, 0) }
			local x = row(parts, {
				{ d = 22, top = 0, motion = spin(6), arms = { { 22, 2.8 }, { 11, -4, 0.25, 0 } } },
			}, 4, PAD + 2)
			table.insert(parts, canopy(PAD + 2 + 4 + 11, 0))
			local length = x + 5 + PAD + 2
			table.insert(parts, pad(x + 5, length, 1.5, 3))
			return Kit.section(length, 1.5, parts)
		end,
	},
	{
		-- The disks turn one way, stop and turn back (a sweep), each with a red arm going round over it: plan your
		-- hop around the turn.
		name = "Turnabout",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = { pad(0, PAD, 0) }
			local swing = function(phase: number): Kit.Motion
				return { kind = "sweep", amp = 120, period = 8, hold = 0.6, phase = phase }
			end
			local x = row(parts, {
				{ d = 18, top = 0, motion = swing(0), arms = { { 18, 2.7 } } },
				{ d = 18, top = 1.5, motion = swing(0.5), arms = { { 18, -2.7, 0.25 } } },
			}, 5, PAD)
			local length = x + 5 + PAD
			table.insert(parts, pad(x + 5, length, 1.5, 3))
			return Kit.section(length, 1.5, parts)
		end,
	},
	{
		-- Each fast disk carries a red spoke welded across it (a pizza cut in two): land in a slice, ride, leave
		-- before the spoke swings round to your side. (Kit: welded off-centre pucks need a path, and the checks
		-- measure a path hazard's reach too wide, so the slice line is a full spoke.)
		name = "Pizza Line",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = { pad(0, PAD, 0) }
			local d, gap = 14, 5
			local x = PAD
			for i = 1, 4 do
				local period = if i % 2 == 1 then 3.2 else -3.2
				local phase = (i - 1) * 0.25
				local cx = x + gap + d / 2
				table.insert(parts, disc(cx, 0, d, spin(period, phase)))
				table.insert(parts, stand(cx, 0))
				table.insert(parts, spoke(cx, 0, d, period, phase))
				x = cx + d / 2
			end
			local length = x + gap + PAD
			table.insert(parts, pad(x + gap, length, 1.5, 3))
			return Kit.section(length, 1.5, parts)
		end,
	},
	{
		-- Ride the disk to the orange spring pad; it only throws while its rim glows (every 2.5 s), forward onto a
		-- ledge 12 studs on and 4 higher. A red arm goes round the disk the other way while you wait. (Kit: the pad
		-- can't ride the disk's rim, so its aim doesn't turn.)
		name = "Spring Ride",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = { pad(0, PAD, 0) }
			local x = row(parts, { { d = 20, top = 0, motion = spin(6), arms = { { 20, -2.8 } } } }, 5, PAD)
			local px = x + 4.5
			table.insert(
				parts,
				Kit.slab(px + 4, 0, 0, 8, 8, "spring", {
					motion = { kind = "bounce", power = 60, throw = { 14, 0, 0 }, duty = 0.35, period = 2.5 },
					marker = "rings2",
				})
			)
			local lx = px + 8 + 12
			local length = lx + PAD + 2
			table.insert(parts, pad(lx, length, 4, 3))
			return Kit.section(length, 4, parts)
		end,
	},
	{
		-- Disks that tip forward and back (rock) round a turning one, each 1.5 studs higher: the jump is short when
		-- the edge dips toward you and long when it lifts; a red arm sweeps the turning one. (Kit: one motion a
		-- part, so tip and turn are on different disks.)
		name = "Tip and Turn",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = { pad(0, PAD, 0) }
			local x = row(parts, {
				{ d = 16, top = 1.5, motion = { kind = "rock", amp = 8, period = 3.2 } },
				{ d = 16, top = 3, motion = spin(6), arms = { { 16, -2.7 } } },
				{ d = 16, top = 4.5, motion = { kind = "rock", amp = 8, period = 3.2, phase = 0.5 } },
			}, 5, PAD)
			local length = x + 5 + PAD
			table.insert(parts, pad(x + 5, length, 4.5, 3))
			return Kit.section(length, 4.5, parts)
		end,
	},
	{
		-- Two planks turning opposite ways: their ends only meet (2 studs apart) twice a turn, the moment to step
		-- across; otherwise they are 14 apart.
		name = "Line Them Up",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = { pad(0, PAD, 0) }
			local c1 = PAD + 1.5 + 10
			local c2 = c1 + 10 + 2 + 10
			table.insert(parts, plank(c1, 1.5, 20, 8, spin(4)))
			table.insert(parts, stand(c1, 1.5))
			table.insert(parts, plank(c2, 1.5, 20, 8, spin(-4)))
			table.insert(parts, stand(c2, 1.5))
			local x = c2 + 10 + 1.5
			local length = x + PAD
			table.insert(parts, pad(x, length, 3, 3))
			return Kit.section(length, 3, parts)
		end,
	},
	{
		-- Three seat disks circle a big post like carousel seats: hop on one as it passes, ride it round to the far
		-- side, hop off. A low red arm goes round the post the other way: hop it while you ride. (Kit: the seats
		-- circle but don't also spin.)
		name = "Carousel Seats",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = { pad(0, PAD, 0) }
			local r, d, period = 7, 9, 7
			local cx = PAD + 1.5 + r + d / 2
			table.insert(parts, Kit.prop({ 4, 8, 4 }, { cx, 4, 0 }, "post", { shape = "disc" }))
			for i = 0, 2 do
				table.insert(parts, seat(cx, 1.5, d, r, 180 + 120 * i, period))
			end
			-- a low red arm round the post the other way: hop it while you ride
			table.insert(parts, arm(cx, 1.5, 2 * r + d, -3.1))
			local x = cx + r + d / 2 + 1.5
			local length = x + PAD
			table.insert(parts, pad(x, length, 3, 3))
			return Kit.section(length, 3, parts)
		end,
	},
	{
		-- A fast disk with two red arms going round opposite ways, then a long jump to a small disk turning back.
		-- The second arm rides high, just over a head: hop the low one, but never while the high one is overhead.
		name = "Blender",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = { pad(0, PAD + 2, 0) }
			local x = row(parts, {
				{ d = 20, top = 0, motion = spin(4), arms = { { 20, 2.5 }, { 18, -3.1, 0.3, 5 } } },
				{ d = 10, top = 1, motion = spin(-5) },
			}, { 4, 6 }, PAD + 2)
			local length = x + 5 + PAD
			table.insert(parts, pad(x + 5, length, 2, 3))
			return Kit.section(length, 2, parts)
		end,
	},
	{
		-- Three shrinking disks, each with its own red arm, turning opposite ways in turn; the middle one tips.
		-- (Kit: one motion a part, so the wobble is the middle disk's rock.)
		name = "Wobble Gauntlet",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = { pad(0, PAD, 0) }
			local x = row(parts, {
				{ d = 18, top = 0, motion = spin(6), arms = { { 18, 2.3 } } },
				{
					d = 12,
					top = 1.5,
					motion = { kind = "rock", amp = 10, period = 3 },
					arms = { { 10, -2.1, 0, 0.4 } },
				},
				{ d = 9, top = 3, motion = spin(5), arms = { { 9, 2.2, 0.5 } } },
			}, 5, PAD)
			local length = x + 5 + PAD
			table.insert(parts, pad(x + 5, length, 3, 3))
			return Kit.section(length, 3, parts)
		end,
	},
	{
		-- A plank that turns one way, stops and turns back (sweep), with a red arm going round over it: hop the arm
		-- while you wait for the plank to line up with the exit. The exit sits 2.5 over the plank: jump up to it.
		name = "Clockwork",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = { pad(0, PAD, 0) }
			local cx = PAD + 2 + 11
			table.insert(parts, plank(cx, 1.5, 22, 8, { kind = "sweep", amp = 180, period = 10, hold = 0.4 }))
			table.insert(parts, stand(cx, 1.5))
			table.insert(parts, hub(cx, 1.5))
			table.insert(parts, arm(cx, 1.5, 22, -2.6))
			local x = cx + 11 + 3
			local length = x + PAD
			table.insert(parts, pad(x, length, 4, 3))
			return Kit.section(length, 4, parts)
		end,
	},
	{
		-- Four small disks that turn back and forth out of step with each other, rising 1.5 each, two with a red arm:
		-- read each disk's arrows before every jump.
		name = "Gear Train",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = { pad(0, PAD, 0) }
			local swing = function(k: number): Kit.Motion
				return { kind = "sweep", amp = 150, period = 6, hold = 0.3, phase = k * 0.125 }
			end
			local x = row(parts, {
				{ d = 11, top = 1.5, motion = swing(0) },
				{ d = 11, top = 3, motion = swing(1), arms = { { 11, 2.2 } } },
				{ d = 11, top = 4.5, motion = swing(2) },
				{ d = 11, top = 6, motion = swing(3), arms = { { 11, -2.2, 0.25 } } },
			}, 5, PAD)
			local length = x + 5 + PAD
			table.insert(parts, pad(x + 5, length, 6, 3))
			return Kit.section(length, 6, parts)
		end,
	},
}

return M
