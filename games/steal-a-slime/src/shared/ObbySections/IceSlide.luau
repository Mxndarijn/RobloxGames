--!strict
--[[
	Ice Slide (obby idea 6, docs/obby-variants/6.json; contract/obby-sections.md)

	Glossy pale-blue ice that always tilts down: on a `slide` part you keep your speed, the slope pulls you downhill and
	walking only steers (ObbyMoves). Red see-through goo and holes in the ice show where not to steer; green brake goo
	(look "sticky", a floor, not a wall) is the one place you can stop. Hand-made (no generator): a track's feel
	depends on its angles, and a random turn could be one you can't steer through.

	Every variant opens on a jelly entry pad (x 0..ENTRY) and most end with a hop up onto a jelly exit ledge EXIT_UP
	studs above the end of the ice: holding forward without a jump walks into that ledge (ObbyCheck.walkStop stops at a
	step over 2 studs), so no variant can be cleared by walking (contract §9, §11). Hopping on every landing doesn't
	do it either: goo strips that overlap across the lane, rows that don't line up, bumpers a hop can't clear and slow
	blink cycles leave no straight line that works more than by luck (ObbyCheck.masher). Gaps and holes are at least 5 studs
	where the far side is lower, too long to stumble over.

	Lane limits: the lane is 24 studs wide and every section runs along +x, so the design's 90° sweep, 180° hairpins and
	1.5-turn corkscrew are built as the closest shape that fits (a 60° banked arc, three side-by-side legs joined by
	brake-goo turn pads, one full banked turn round a tower). Slide speeds per tier are in SLIDE; a slide's cap is
	what lets its end jump reach further than a walking jump (ObbyCheck.makeable, tests/obby/IceSlide.spec).

	Not too easy (contract §10), but steerable: on ice the stick only adds 16 studs/s² sideways, so a goo layout is
	only as tight as tests/obby/IceSlide.spec's steering planner allows (P holds the spacings, each one step short of
	where the planner or a check fails). Every static goo strip is longer than a slide jump clears, so it has to be
	steered round, not hopped. Timed hazards sit where you can wait first (the entry pad, brake goo), because on ice
	you can't stop in front of them.

	Variants are appended, never reordered (a pick stores the index).
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

type Part = Kit.Part
type Slide = { pull: number, cap: number }

local ENTRY = 6 -- the jelly entry pad at x 0..ENTRY
local EXIT_UP = 2.5 -- the exit ledge's top over the end of the ice: a jump, not a walk
local EXIT_LONG = 8
local GOO_UP = 1.2 -- a goo patch's top over the ice
local GOO_THICK = 1.7 -- so it sits half a stud into the ice
local RAIL_H = 1.5 -- soft rails (see-through bubble walls) stand this high over the ice
local BAR_THICK = 1.2 -- spinning sweeper bars

-- Slide controller numbers per tier: downhill pull (studs/s²) and speed cap (studs/s).
local SLIDE: { [string]: Slide } = {
	easy = { pull = 30, cap = 22 },
	medium = { pull = 38, cap = 28 },
	hard = { pull = 44, cap = 30 },
}
local SLALOM: Slide = { pull = 28, cap = 20 } -- slower, so a 16-stud slalom can be steered
local SPIRAL: Slide = { pull = 24, cap = 16 } -- slow enough to hold a 6.5-stud turn

-- Timing and spacing per variant, tuned against the checks and the idea spec's steering planner: each sits one
-- step short of where a check (or the steering) would fail.
local P = {
	firstSweep = 3.8, -- First Slide: the sweeper's turn (s)
	firstRight = 54, -- First Slide: where the right-hand goo strip starts (the left one ends at x 38)
	dodgeGap = 13, -- Dodge: ice between one strip's end and the next one's start
	greenGoo = 17, -- Steer to the Green: the goo strip's length
	hairPeriod = 3.2, -- Hairpins: the blinking patch
	hairDuty = 0.5,
	cheeseRow = 18, -- Swiss Cheese: a row of holes (longer than a slide jump)
	cheesePad = 10, -- the full-width ice between rows (room to steer across)
	cheeseShift = 2, -- rows A and C sit this far off the middle, to opposite sides: no straight line is on A, B and C
	cheesePeriod = 3,
	cheeseDuty = 0.49,
	bridgeAt = 26, -- Ice Bridge: where the bridge starts
	bridgePeriod = 3,
	bridgeDuty = 0.49,
	skiLand = 7, -- Ski Jump: how far right the landing sits
	forkPeriod = 8, -- Fork: the right lane's blinking patch
	forkDuty = 0.8,
	slalomGap = 21, -- Slalom: gate to gate
	brakeSweep = { 3.5, 3.5, 3.5 }, -- Brake and Go: each sweeper's turn
	brakePhase = { 0, 0.3, 0.15 }, -- each paddle's start in its turn: a run that never stops meets one of them
	brakeRadius = 7, -- paddle arm length
	brakeTall = 6, -- paddle height: taller than a hop, so it is timed, not jumped
	brakeWide = 12, -- the track (the brake patch is 8 of it)
	brakeBars = 1, -- one paddle per post (a cross leaves no fair window)
	pipePeriod = 6, -- Half-Pipe: the blinking patch at the bottom
	pipeDuty = 0.8,
	redHole = 7, -- Red Run: holes, the pieces between them and the free line across each landing piece
	redPiece = 13,
	redLine = { -4, 0, 4 },
	redLane = 5,
	screwGap = 5.8, -- Corkscrew: the gap before the exit
	islandGap = 9, -- Ice Islands: gaps and the zigzag
	islandZig = 4,
	crestFlat = 4, -- Blind Crest: the flat top of each crest and how far across its goo strip reaches
	crestGoo = 9,
}

local function tan(deg: number): number
	return math.tan(math.rad(deg))
end

local function merge(part: { [string]: any }, extra: { [string]: any }?): Part
	if extra then
		for k, v in extra do
			part[k] = v
		end
	end
	return part :: any
end

-- A box whose top runs straight from (x0, top0) to (x1, top1) along x, `thick` deep, `wide` across, centred on z.
local function along(
	x0: number,
	top0: number,
	x1: number,
	top1: number,
	z: number,
	wide: number,
	thick: number,
	look: string,
	extra: { [string]: any }?
): Part
	local dx, dy = x1 - x0, top1 - top0
	local a = math.atan2(dy, dx)
	local part: { [string]: any } = {
		size = { math.sqrt(dx * dx + dy * dy), thick, wide },
		pos = { (x0 + x1) / 2 + math.sin(a) * thick / 2, (top0 + top1) / 2 - math.cos(a) * thick / 2, z },
		look = look,
	}
	if math.abs(a) > 1e-9 then
		part.roll = math.deg(a)
	end
	return merge(part, extra)
end

-- Ice from x0 (top top0) to x1, falling `deg` degrees: a slide step. Returns it and its top at x1.
local function ice(
	x0: number,
	top0: number,
	x1: number,
	deg: number,
	z: number,
	wide: number,
	slide: Slide,
	extra: { [string]: any }?
): (Part, number)
	local top1 = top0 - (x1 - x0) * tan(deg)
	local part = along(x0, top0, x1, top1, z, wide, Kit.THICK, "ice", { step = true, slide = slide })
	return merge(part :: any, extra), top1
end

-- The ice surface height at x on a slope that is at `top0` at x0 and falls `deg` degrees.
local function surf(x0: number, top0: number, deg: number, x: number): number
	return top0 - (x - x0) * tan(deg)
end

-- A red goo patch lying on a slope (surface `top0` at x0, falling `deg`) from x0 to x1, `wide` across at z.
local function goo(x0: number, x1: number, top0: number, deg: number, z: number, wide: number): Part
	local top1 = surf(x0, top0, deg, x1)
	return along(x0, top0 + GOO_UP, x1, top1 + GOO_UP, z, wide, GOO_THICK, "hazard", { hazard = true })
end

-- A soft rail (see-through bubble wall) along a slope from x0 to x1 at z.
local function rail(x0: number, top0: number, x1: number, top1: number, z: number): Part
	return along(x0, top0 + RAIL_H, x1, top1 + RAIL_H, z, 1, RAIL_H + 0.5, "bubble", { tone = 1 })
end

-- A spinning red goo sweeper bar `radius` long each way on a dark post, over a slope (surface `top` at x, falling
-- `deg`), turning once every `period` s. Its bottom clears the uphill ice by half a stud.
local function sweeper(
	parts: { Part },
	x: number,
	z: number,
	top: number,
	deg: number,
	radius: number,
	period: number,
	phase: number?,
	tall: number?,
	bars: number?
)
	local h = tall or BAR_THICK
	local centre = top + radius * tan(deg) + 0.5 + h / 2
	local n = bars or 1
	for k = 0, n - 1 do
		-- a cross is two bars a quarter turn apart
		table.insert(
			parts,
			Kit.hazard({ radius * 2, h, BAR_THICK }, { x, centre, z }, {
				motion = { kind = "spin", period = period, phase = ((phase or 0) + k / (2 * n)) % 1 },
			})
		)
	end
	local post = centre - top + 0.5
	table.insert(parts, Kit.prop({ 1.2, post, 1.2 }, { x, top - 0.5 + post / 2, z }, "post"))
end

-- A segment whose top centre line starts at (px, top, pz) and runs `run` flat studs heading `h` degrees (0 = +x,
-- positive towards +z), falling `deg`; `bank` degrees lowers its left (+z of the heading) side, `ext` studs more at
-- both ends cover the corners of a bend. Returns the part and where its centre line ends (x, z, top).
local function seg(
	px: number,
	pz: number,
	top: number,
	h: number,
	run: number,
	deg: number,
	wide: number,
	thick: number,
	look: string,
	bank: number?,
	ext: number?,
	extra: { [string]: any }?
): (Part, number, number, number)
	local hr = math.rad(h)
	local dx, dz = math.cos(hr), math.sin(hr)
	local drop = run * tan(deg)
	local mx, mz, mtop = px + dx * run / 2, pz + dz * run / 2, top - drop / 2
	local yaw, roll, pitch = -h, -deg, bank or 0
	local down = Kit.rotate({ 0, -thick / 2, 0 }, yaw, pitch, roll)
	local part: { [string]: any } = {
		size = { (run + 2 * (ext or 0)) / math.cos(math.rad(deg)), thick, wide },
		pos = { mx + down[1], mtop + down[2], mz + down[3] },
		look = look,
	}
	if yaw ~= 0 then
		part.yaw = yaw
	end
	if roll ~= 0 then
		part.roll = roll
	end
	if pitch ~= 0 then
		part.pitch = pitch
	end
	return merge(part, extra), px + dx * run, pz + dz * run, top - drop
end

local function entry(parts: { Part }, z: number, wide: number, long: number?)
	local l = long or ENTRY
	table.insert(parts, Kit.slab(l / 2, 0, z, l, wide, "jelly", { tone = 1 }))
end

-- The exit ledge from x0 to x0 + EXIT_LONG with top `top`; returns the section's length.
local function exit(parts: { Part }, x0: number, top: number, z: number, wide: number): number
	table.insert(parts, Kit.slab(x0 + EXIT_LONG / 2, top, z, EXIT_LONG, wide, "jelly", { tone = 3 }))
	return x0 + EXIT_LONG
end

-- Brake goo: a green floor that ends the slide (the one place you can stop).
local function brake(x0: number, x1: number, top: number, z: number, wide: number): Part
	return Kit.slab((x0 + x1) / 2, top, z, x1 - x0, wide, "sticky", { tone = 1 })
end

-- A blinking red goo patch lying on a slope like `goo`: there while its cycle is under `duty`.
local function blink(
	x0: number,
	x1: number,
	top0: number,
	deg: number,
	z: number,
	wide: number,
	period: number,
	duty: number,
	phase: number?
): Part
	local part = goo(x0, x1, top0, deg, z, wide)
	part.motion = { kind = "flip", period = period, duty = duty, phase = phase }
	return part
end

local M = {}
M.id = "IceSlide"
M.name = "Ice Slide"
M.idea = 6

M.variants = {
	{
		-- A gentle railed slope onto a flat run-out, then a hop up onto the exit. Easy still has work (§10): a slow
		-- sweeper near the top (timed from the entry pad), then goo strips left and right on the lower slope that overlap
		-- across the middle, so no straight line misses both: pass the first on the right, steer over, pass the second
		-- on the left.
		name = "First Slide",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local sl, deg, W = SLIDE.easy, 8, 16
			local parts = {}
			entry(parts, 0, W)
			local stop = P.firstRight + 12
			local slope, low = ice(ENTRY, 0, stop, deg, 0, W, sl)
			table.insert(parts, slope)
			local runout = ice(stop, low, stop + 6, 0, 0, W, sl)
			table.insert(parts, runout)
			local function at(x: number): number
				return surf(ENTRY, 0, deg, x)
			end
			-- rail pieces per side, broken beside that side's goo strip (no riding a rail past it)
			local breaks = { [-1] = { 24, 40 }, [1] = { P.firstRight - 2, stop + 6 } }
			for _, side in { -1, 1 } do
				local b = breaks[side]
				local zr = side * (W / 2 + 0.5)
				table.insert(parts, rail(ENTRY, 0, b[1], at(b[1]), zr))
				if b[2] < stop then
					table.insert(parts, rail(b[2], at(b[2]), stop, low, zr))
				end
			end
			sweeper(parts, 15, 0, at(15), deg, 7, P.firstSweep)
			-- two goo strips that overlap across the middle: no straight line misses both
			table.insert(parts, goo(26, 38, at(26), deg, -3.5, 9)) -- z -8..1
			table.insert(parts, goo(P.firstRight, stop, at(P.firstRight), deg, 3.5, 9)) -- z -1..8
			local length = exit(parts, stop + 6, low + EXIT_UP, 0, W)
			return Kit.section(length, low + EXIT_UP, parts)
		end,
	},
	{
		-- Three long goo strips, left, right, left: steer one way, then the other, then back. Each strip is longer than
		-- a slide jump carries, so you can't hop it; the spacing is what the steering can just do.
		name = "Dodge Left, Dodge Right",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local sl, deg, W = SLIDE.easy, 8, 20
			local parts = {}
			entry(parts, 0, W)
			local L, G = 11, P.dodgeGap
			local x = 12
			for i = 1, 3 do
				local side = if i % 2 == 1 then -1 else 1
				table.insert(parts, goo(x, x + L, surf(ENTRY, 0, deg, x), deg, side * 5, 10))
				x += L + G
			end
			local stop = x - G + 6
			local slope, low = ice(ENTRY, 0, stop, deg, 0, W, sl)
			table.insert(parts, 2, slope)
			local length = exit(parts, stop, low + EXIT_UP, 0, W)
			return Kit.section(length, low + EXIT_UP, parts)
		end,
	},
	{
		-- An S of two 45° bends with soft rails on the outside of each; the inside of each bend is goo, so a lazy line
		-- that cuts a corner is sent back.
		name = "Bumper Bend",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local sl, deg, W = SLIDE.easy, 7, 16
			local shift = 7.2 -- the S moves the track this far across (the lane leaves 8; the bends' corners need some)
			local za, zb = -shift / 2, shift / 2
			local parts = {}
			entry(parts, za, W)
			local s1, top1 = ice(ENTRY, 0, 18, deg, za, W, sl)
			table.insert(parts, s1)
			local run = shift / math.sin(math.rad(45))
			local ext = W / 2 * tan(22.5)
			local diag, x2, _, top2 =
				seg(18, za, top1, 45, run, deg, W, Kit.THICK, "ice", 0, ext, { step = true, slide = sl })
			table.insert(parts, diag)
			local s2, top3 = ice(x2, top2, 54, deg, zb, W, sl)
			table.insert(parts, s2)
			-- Rails: bend 1's outside is the -z edge of the diagonal's first half, bend 2's the +z edge of its second.
			local half = run / 2
			local off = W / 2 + 0.5
			local c, s = math.cos(math.rad(45)), math.sin(math.rad(45))
			table.insert(
				parts,
				(
					seg(18 + s * off, za - c * off, top1 + RAIL_H, 45, half, deg, 1, RAIL_H + 0.5, "bubble", 0, 0, {
						tone = 1,
					})
				)
			)
			local mx, mz = 18 + c * half, za + s * half
			local mtop = top1 - half * tan(deg)
			table.insert(
				parts,
				(
					seg(mx - s * off, mz + c * off, mtop + RAIL_H, 45, half, deg, 1, RAIL_H + 0.5, "bubble", 0, 0, {
						tone = 1,
					})
				)
			)
			-- bend 1 turns towards +z (inside: the +z edge of the straight before it), bend 2 back (inside: -z)
			table.insert(parts, goo(7, 18, surf(ENTRY, 0, deg, 7), deg, za + 5, 6))
			table.insert(parts, goo(31, 42, surf(x2, top2, deg, 31), deg, zb - 4, 8))
			local length = exit(parts, 54, top3 + EXIT_UP, zb, W)
			return Kit.section(length, top3 + EXIT_UP, parts)
		end,
	},
	{
		-- The slope runs out onto flat ice that ends in a drop; only the left half has green brake goo leading on to
		-- the exit. A long goo strip down the left of the slope makes you start right and steer over late.
		name = "Steer to the Green",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local sl, deg, W = SLIDE.easy, 9, 16
			local parts = {}
			entry(parts, 0, W)
			local slope, low = ice(ENTRY, 0, 30, deg, 0, W, sl)
			table.insert(parts, slope)
			table.insert(parts, goo(9, 9 + P.greenGoo, surf(ENTRY, 0, deg, 9), deg, -3.5, 9))
			local flat = ice(30, low, 34, 0, 0, W, sl)
			table.insert(parts, flat)
			table.insert(parts, brake(34, 44, low, -4, 8))
			local length = exit(parts, 44, low + EXIT_UP, -4, 8)
			return Kit.section(length, low + EXIT_UP, parts)
		end,
	},
	{
		-- Three short slopes, each a drop of 2.5 lower over a 5.5-stud gap (a jump, not a walk); goo strips cover the
		-- left of the second slope and the right of the third, so you line up in the air.
		name = "Ice Stairs",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local sl, deg, W = SLIDE.easy, 10, 16
			local parts = {}
			entry(parts, 0, W, 5)
			local x, top = 5, 0
			for i = 1, 3 do
				local p, low = ice(x, top, x + 12, deg, 0, W, sl)
				table.insert(parts, p)
				if i >= 2 then
					local side = if i == 2 then -1 else 1
					table.insert(parts, goo(x + 1, x + 11, surf(x, top, deg, x + 1), deg, side * 4, 8))
				end
				x, top = x + 12, low
				if i < 3 then
					x, top = x + 5.5, top - 2.5
				end
			end
			local length = exit(parts, x, top + EXIT_UP, 0, W)
			return Kit.section(length, top + EXIT_UP, parts)
		end,
	},
	{
		-- One long banked turn with no rails: a 60° arc (the lane is too narrow for 90°) tilted to the inside, so
		-- holding the turn keeps you on. Goo on the inside of the apex punishes cutting it: the 8-wide entry pad and
		-- the goo bite cover the same lines, so every straight line (the chord) runs into the bite or off the ice.
		name = "Wide Sweep",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local sl, deg, W = SLIDE.easy, 7, 16
			local parts = {}
			entry(parts, -2, 8)
			local x, z, top = ENTRY, -4, 0
			local headings = { 30, 15, 0, -15, -30 }
			local apex: { number }? = nil
			for i, h in headings do
				local p
				local x0, z0, t0 = x, z, top
				p, x, z, top = seg(x, z, top, h, 8, deg, W, Kit.THICK, "ice", -10, 1.2, { step = true, slide = sl })
				table.insert(parts, p)
				if i == 3 then
					apex = { x0, z0, t0 }
				end
			end
			local a = apex :: { number }
			-- The turn bends towards -z: its inside is the -z edge. A goo bite there at the apex, from that edge across
			-- every line the entry pad starts on.
			table.insert(parts, goo(a[1] - 2, a[1] + 8, a[3] + 2 * tan(deg), deg, a[2] - 4.3, 7.4))
			local length = exit(parts, x, top + EXIT_UP, z, W)
			return Kit.section(length, top + EXIT_UP, parts)
		end,
	},
	{
		-- Three legs side by side zigzag down the hill (+x, -x, +x), joined by brake-goo turn pads at the ends: the
		-- lane is too narrow for a sliding 180° turn, so you stop, turn and go. No rail on the pads' outer edges;
		-- see-through walls between the legs stop a drop onto the leg below. The middle leg has a blinking goo patch:
		-- wait on the first pad, go when it is out.
		name = "Hairpins",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local sl, deg = SLIDE.medium, 9
			local parts = {}
			local row = 8
			entry(parts, -row, row)
			local leg1, t1 = ice(ENTRY, 0, 40, deg, -row, row, sl)
			table.insert(parts, leg1)
			table.insert(parts, brake(40, 48, t1, -row / 2, row * 2))
			-- A tall bubble bumper closes the first pad's far end: going straight on (walking or hopping) stops there
			-- instead of dropping onto the exit; you have to turn back onto leg 2 (a 9-stud wall a jump can't clear).
			table.insert(parts, Kit.prop({ 1, 11, row * 2 }, { 48.5, t1 + 4.5, -row / 2 }, "bubble", { tone = 1 }))
			-- Leg 2 runs back from x 40 to x 10, falling towards -x: the same box as one rising along +x.
			local t2 = t1 - 30 * tan(deg)
			table.insert(parts, along(10, t2, 40, t1, 0, row, Kit.THICK, "ice", { step = true, slide = sl }))
			table.insert(parts, brake(2, 10, t2, row / 2, row * 2))
			local leg3, t3 = ice(10, t2, 44, deg, row, row, sl)
			table.insert(parts, leg3)
			-- The blinking patch on leg 2, 6 studs into it.
			table.insert(
				parts,
				along(
					28,
					surf(40, t1, -deg, 28) + GOO_UP,
					34,
					surf(40, t1, -deg, 34) + GOO_UP,
					0,
					row,
					GOO_THICK,
					"hazard",
					{
						hazard = true,
						motion = { kind = "flip", period = P.hairPeriod, duty = P.hairDuty },
					}
				)
			)
			-- Walls between the legs: from under the lower leg to well over the higher one.
			for _, wall in { { ENTRY, 40, -row / 2, t2 }, { 10, 44, row / 2, t3 } } do
				local x0, x1, wz, lowY = wall[1], wall[2], wall[3], wall[4] - 1
				local highY = 5
				table.insert(
					parts,
					Kit.prop(
						{ x1 - x0, highY - lowY, 1 },
						{ (x0 + x1) / 2, (highY + lowY) / 2, wz },
						"bubble",
						{ tone = 1 }
					)
				)
			end
			-- A goo bite on leg 3's outer edge: a sloppy start off the second pad runs into it.
			table.insert(parts, goo(14, 30, surf(10, t2, deg, 14), deg, row + 2.5, 3))
			local length = exit(parts, 44, t3 + EXIT_UP, row, row)
			return Kit.section(length, t3 + EXIT_UP, parts)
		end,
	},
	{
		-- Three rows of long holes (too long to jump at the cap) in a staggered pattern (2, 1, 2): the ice between them
		-- is exactly 8 wide, so you weave centre, side, centre. Rows A and C sit off the middle to opposite sides, so no
		-- straight line runs on all three rows. A blinking patch on the first centre strip sets when you
		-- leave the pad.
		name = "Swiss Cheese",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local sl, deg, W = SLIDE.medium, 8, 22
			local parts = {}
			entry(parts, 0, W)
			local function at(x: number): number
				return surf(ENTRY, 0, deg, x)
			end
			local function piece(x0: number, x1: number, z: number, wide: number)
				table.insert(parts, (ice(x0, at(x0), x1, deg, z, wide, sl)))
			end
			local R, Q, S = P.cheeseRow, P.cheesePad, P.cheeseShift
			local x = ENTRY
			piece(x, x + 6, 0, W)
			x += 6
			piece(x, x + R, -S, 8) -- row A: holes at both sides, the ice a little left of the middle
			table.insert(parts, blink(x + 4, x + 10, at(x + 4), deg, -S, 8, P.cheesePeriod, P.cheeseDuty))
			x += R
			piece(x, x + Q, 0, W)
			x += Q
			piece(x, x + R, -8, 8) -- row B: a hole in the middle
			piece(x, x + R, 8, 8)
			x += R
			piece(x, x + Q, 0, W)
			x += Q
			piece(x, x + R, S, 8) -- row C: holes at both sides, the ice a little right of the middle
			x += R
			piece(x, x + 4, 0, W)
			x += 4
			local length = exit(parts, x, at(x) + EXIT_UP, 0, W)
			return Kit.section(length, at(x) + EXIT_UP, parts)
		end,
	},
	{
		-- The wide slope narrows to a 28-long, 8-wide bridge with no rails: steer round a long goo strip, line up, hold
		-- straight through a blinking patch on the bridge, and steer round another strip where it widens.
		name = "Ice Bridge",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local sl, deg, W = SLIDE.medium, 8, 20
			local parts = {}
			entry(parts, 0, W)
			local b0, b1 = P.bridgeAt, P.bridgeAt + 28
			local w1, t1 = ice(ENTRY, 0, b0, deg, 0, W, sl)
			table.insert(parts, w1)
			table.insert(parts, goo(8, 8 + 14, surf(ENTRY, 0, deg, 8), deg, 5, 10))
			local bridge, t2 = ice(b0, t1, b1, deg, 0, 8, sl)
			table.insert(parts, bridge)
			table.insert(
				parts,
				blink(b0 + 12, b0 + 18, surf(b0, t1, deg, b0 + 12), deg, 0, 8, P.bridgePeriod, P.bridgeDuty)
			)
			local w2, t3 = ice(b1, t2, b1 + 18, deg, 0, W, sl)
			table.insert(parts, w2)
			table.insert(parts, goo(b1 + 2, b1 + 16, surf(b1, t2, deg, b1 + 2), deg, -5, 10))
			local length = exit(parts, b1 + 18, t3 + EXIT_UP, 0, W)
			return Kit.section(length, t3 + EXIT_UP, parts)
		end,
	},
	{
		-- A steep slope ends in an upturned lip that throws you over a 10.4-stud gap onto a landing set to the right;
		-- a long goo strip down the right of the slope makes you start left and steer over late.
		name = "Ski Jump",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local sl, deg, W = SLIDE.medium, 14, 18
			local parts = {}
			entry(parts, 0, W)
			local slope, low = ice(ENTRY, 0, 32, deg, 0, W, sl)
			table.insert(parts, slope)
			table.insert(parts, goo(9, 9 + 16, surf(ENTRY, 0, deg, 9), deg, 3.5, 11))
			local lip, lipTop = ice(32, low, 36, -14, 0, W, sl)
			table.insert(parts, lip)
			local land = lipTop - 2
			local gap = 10.4
			table.insert(parts, Kit.slab(36 + gap + 4, land, P.skiLand, 8, 8, "jelly", { tone = 3 }))
			return Kit.section(36 + gap + 8, land, parts)
		end,
	},
	{
		-- Four slalom gates on alternating sides: a goo fence from the lane edge to just past the middle (longer than
		-- a slide jump, so you can't hop it) ending in a tall goo post. The gates are as close as the steering allows,
		-- so you snake left-right-left-right with no straight bit.
		name = "Slalom Posts",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local sl, deg, W = SLALOM, 8, 20
			local parts = {}
			entry(parts, 0, W)
			local L, D = 10, P.slalomGap
			local last = 12 + 3 * D + L
			local slope, low = ice(ENTRY, 0, last + 4, deg, 0, W, sl)
			table.insert(parts, slope)
			for i = 0, 3 do
				local x = 12 + i * D
				local side = if i % 2 == 0 then -1 else 1
				local top = surf(ENTRY, 0, deg, x + L / 2)
				table.insert(parts, goo(x, x + L, surf(ENTRY, 0, deg, x), deg, side * 5, 10))
				-- the post at its inner end, taller than a jump
				table.insert(parts, Kit.hazard({ 2, 9, 2 }, { x + L / 2, top + 4, side * -0.5 + side * 1 }))
			end
			local length = exit(parts, last + 4, low + EXIT_UP, 0, W)
			return Kit.section(length, low + EXIT_UP, parts)
		end,
	},
	{
		-- A goo island with a pointy nose splits the slope into two 8-wide lanes: the left has an 8-stud hole to jump,
		-- the right a blinking goo patch to time. Pick one early. The patch is out once a slow cycle (one blink in
		-- P.forkPeriod s): going on sight from the pad, not hopping down at random, gets you through.
		name = "Fork in the Ice",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local sl, deg, W = SLIDE.medium, 10, 24
			local parts = {}
			entry(parts, 0, W)
			local wide, t1 = ice(ENTRY, 0, 18, deg, 0, W, sl)
			table.insert(parts, wide)
			local function at(x: number): number
				return surf(ENTRY, 0, deg, x)
			end
			-- left lane (main route): a hole at x 27..35
			table.insert(parts, (ice(18, t1, 27, deg, -8, 8, sl)))
			table.insert(parts, (ice(35, at(35), 46, deg, -8, 8, sl)))
			-- right lane: one piece with a blinking patch on it
			table.insert(parts, (ice(18, t1, 46, deg, 8, 8, sl, { route = "right" })))
			local merge2, t2 = ice(46, at(46), 54, deg, 0, W, sl)
			table.insert(parts, merge2)
			-- the island and its nose
			table.insert(parts, goo(22, 46, at(22), deg, 0, 8))
			local nose = 8 / math.sqrt(2) -- a square turned 45°: an 8-wide point
			table.insert(parts, Kit.hazard({ nose, 2.2, nose }, { 22, at(22) + 0.6, 0 }, { yaw = 45 }))
			table.insert(parts, blink(30, 36, at(30), deg, 8, 8, P.forkPeriod, P.forkDuty))
			local length = exit(parts, 54, t2 + EXIT_UP, 0, W)
			return Kit.section(length, t2 + EXIT_UP, parts)
		end,
	},
	{
		-- Stop on a green brake patch, watch the spinning goo paddle 10 studs on, step off and slide past it while it
		-- is away; three times. The paddles are taller than a hop and turn in step, each a set part of a turn behind
		-- the last, so sliding on without stopping meets one of them: you have to wait on each patch. Miss the 8-wide
		-- patch and you slide on at the paddle's mercy.
		name = "Brake and Go",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local sl, deg, W = SLIDE.medium, 8, P.brakeWide
			local flank = (W - 8) / 2 -- the flat ice beside each brake patch
			local parts = {}
			entry(parts, 0, W)
			local x, top = ENTRY, 0
			for i = 1, 3 do
				local a, t = ice(x, top, x + 5, deg, 0, W, sl)
				table.insert(parts, a)
				x, top = x + 5, t
				-- the brake patch (8 wide) with flat ice either side of it
				table.insert(parts, brake(x, x + 6, top, 0, 8))
				for _, side in { -1, 1 } do
					table.insert(
						parts,
						Kit.prop(
							{ 6, Kit.THICK, flank },
							{ x + 3, top - Kit.THICK / 2, side * (4 + flank / 2) },
							"ice",
							{ slide = sl }
						)
					)
				end
				x = x + 6
				local b, t2 = ice(x, top, x + 16, deg, 0, W, sl)
				table.insert(parts, b)
				sweeper(
					parts,
					x + 9,
					0,
					surf(x, top, deg, x + 9),
					deg,
					P.brakeRadius,
					P.brakeSweep[i],
					P.brakePhase[i],
					P.brakeTall,
					P.brakeBars
				)
				x, top = x + 16, t2
			end
			local length = exit(parts, x, top + EXIT_UP, 0, W)
			return Kit.section(length, top + EXIT_UP, parts)
		end,
	},
	{
		-- Drop into a 12-deep U-shaped bowl and up the far side onto a ledge 2 under the start: only a straight, fast
		-- line carries you (goo lines the bowl's sides), and a blinking goo patch at the bottom sets when you drop in.
		-- It is out once a slow cycle: watch it from the pad and drop in on time (dropping in at random rarely works).
		name = "Half-Pipe Hop",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local sl, W = SLIDE.hard, 16
			local parts = {}
			entry(parts, 0, W)
			local x0, span, depth = ENTRY, 30, 12
			local function y(x: number): number
				local u = (x - (x0 + span / 2)) / (span / 2)
				return -depth * (1 - u * u)
			end
			local cut = x0 + span / 2 + span / 2 * math.sqrt(1 - 4.5 / depth) -- where the far side is 4.5 under
			local xs = { x0, x0 + 5, x0 + 10, x0 + 15, x0 + 20, cut }
			for i = 1, #xs - 1 do
				local a, b = xs[i], xs[i + 1]
				table.insert(parts, along(a, y(a), b, y(b), 0, W, Kit.THICK, "ice", { step = true, slide = sl }))
			end
			-- goo down both sides of the bowl: an 8-wide straight line from the lip to the climb
			local marks = { x0 + 5, x0 + 10, x0 + 15, x0 + 20, x0 + 23 }
			for _, side in { -1, 1 } do
				for i = 1, #marks - 1 do
					local a, b = marks[i], marks[i + 1]
					table.insert(
						parts,
						along(a, y(a) + GOO_UP, b, y(b) + GOO_UP, side * 6, 4, GOO_THICK, "hazard", { hazard = true })
					)
				end
			end
			table.insert(
				parts,
				Kit.hazard({ 4, 2, 8 }, { x0 + 15, y(x0 + 15) + 0.5, 0 }, {
					motion = { kind = "flip", period = P.pipePeriod, duty = P.pipeDuty },
				})
			)
			local length = exit(parts, cut, -2, 0, W)
			return Kit.section(length, -2, parts)
		end,
	},
	{
		-- A steep run of short ice pieces over three holes; each landing piece is goo but for one 5-wide line that moves
		-- across from piece to piece, then a lip throws you 11 studs onto the landing: jump, line up, jump, no rest.
		name = "Red Run",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local sl, deg, W = SLIDE.hard, 14, 18
			local parts = {}
			entry(parts, 0, W, 5)
			local x, top = 5, 0
			local H, N = P.redHole, P.redPiece
			for i = 1, 4 do
				local p, low = ice(x, top, x + N, deg, 0, W, sl)
				table.insert(parts, p)
				if i >= 2 then
					-- goo either side of the one free line across this piece
					local c, half = P.redLine[i - 1], P.redLane / 2
					local lo, hi = c - half, c + half
					table.insert(parts, goo(x, x + N, top, deg, (-W / 2 + lo) / 2, lo + W / 2))
					table.insert(parts, goo(x, x + N, top, deg, (hi + W / 2) / 2, W / 2 - hi))
				end
				x, top = x + N, low
				if i < 4 then
					x = x + H
				end
			end
			local lip, lipTop = ice(x, top, x + 3, -14, 0, W, sl)
			table.insert(parts, lip)
			x += 3
			local land = lipTop - 2.5
			table.insert(parts, Kit.slab(x + 11 + 4, land, 0, 8, W, "jelly", { tone = 3 }))
			return Kit.section(x + 11 + 8, land, parts)
		end,
	},
	{
		-- One full banked turn round a tower (the lane fits one 8-wide turn of radius 6.5, not the draft's 1.5 turns
		-- round a 10-stud tower), no rails, three goo bites on the outer edge; then a hop over a gap onto the exit.
		name = "Corkscrew",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local sl = SPIRAL
			local parts = {}
			local cx, rin, rout = 8, 2.5, 10.5
			local rm, wide = (rin + rout) / 2, rout - rin
			local slope = 11
			local perRad = rm * tan(slope) -- studs of drop per radian of turn
			local n, step = 18, 2 * math.pi / 18
			entry(parts, -rm, wide, cx)
			local long = 2 * rout * math.tan(step / 2)
			local bites = { [4] = true, [9] = true, [14] = true }
			for i = 0, n - 1 do
				local phi = (i + 0.5) * step
				local px, pz = cx + rm * math.sin(phi), -rm * math.cos(phi)
				local h = math.deg(phi)
				local top = -perRad * phi
				local dx, dz = math.cos(phi), math.sin(phi)
				local back = long / 2
				local p = seg(
					px - dx * back,
					pz - dz * back,
					top + back * perRad / rm,
					h,
					long,
					slope,
					wide,
					Kit.THICK,
					"ice",
					12,
					0,
					{ step = true, slide = sl }
				)
				table.insert(parts, p)
				if bites[i] then
					-- a bite out of the outer edge: goo over its outer 4 studs
					local r = rout - 2
					table.insert(
						parts,
						Kit.hazard({ long, 2.5, 4 }, { cx + r * math.sin(phi), top + 0.3, -r * math.cos(phi) }, {
							yaw = -h,
						})
					)
				end
			end
			local low = -perRad * 2 * math.pi
			table.insert(parts, Kit.prop({ 3.4, 14, 3.4 }, { cx, low - 1 + 7, 0 }, "post"))
			local out = ice(cx, low, cx + 16, 0, -rm, wide, sl)
			table.insert(parts, out)
			local length = exit(parts, cx + 16 + P.screwGap, low + EXIT_UP, -rm, wide)
			return Kit.section(length, low + EXIT_UP, parts)
		end,
	},
	{
		-- Five short tilted ice pads, 8 wide, with long gaps: you land sliding, can't stop, and must jump again before
		-- the edge. The pads zigzag so each one only just overlaps the last: line up in the air every time.
		name = "Ice Islands",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local sl, deg = SLIDE.hard, 12
			local parts = {}
			entry(parts, 0, 10)
			local x, top = ENTRY, 0
			for i = 1, 5 do
				x = x + (if i == 1 then 5.5 else P.islandGap) -- the first jump is off the jelly pad, at walking speed
				local p, low = ice(x, top, x + 9, deg, if i % 2 == 1 then -P.islandZig else P.islandZig, 8, sl)
				table.insert(parts, p)
				x, top = x + 9, low
			end
			local length = exit(parts, x + P.islandGap, top + 1.5, 0, 10)
			return Kit.section(length, top + 1.5, parts)
		end,
	},
	{
		-- The slope rolls over two 3-high crests; you only see what is behind each from its top, where a frost arrow
		-- points to the safe side of the long goo strip just past it.
		name = "Blind Crest",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local sl, W = SLIDE.hard, 18
			local parts = {}
			entry(parts, 0, W)
			local d1, t1 = ice(ENTRY, 0, 16, 12, 0, W, sl)
			table.insert(parts, d1)
			local x, top = 16, t1
			local F, G = P.crestFlat, P.crestGoo
			for i = 1, 2 do
				local upDeg = math.deg(math.atan(3 / 8))
				local up, crest = ice(x, top, x + 8, -upDeg, 0, W, sl)
				table.insert(parts, up)
				local flat = ice(x + 8, crest, x + 8 + F, 0, 0, W, sl)
				table.insert(parts, flat)
				local safe = if i == 1 then 1 else -1
				-- the frost arrow: a see-through plate on the crest pointing forward and to the safe side
				table.insert(
					parts,
					Kit.prop({ 3, 0.2, 3 }, { x + 8 + F / 2, crest + 0.15, 0 }, "ice", {
						ghost = true,
						yaw = -safe * 35,
						marker = "arrows",
					})
				)
				local d0, downLen = x + 8 + F, 18
				local down, low = ice(d0, crest, d0 + downLen, 16, 0, W, sl)
				table.insert(parts, down)
				table.insert(parts, goo(d0 + 1, d0 + 18, surf(d0, crest, 16, d0 + 1), 16, -safe * (W - G) / 2, G))
				x, top = d0 + downLen, low
			end
			local length = exit(parts, x, top + EXIT_UP, 0, W)
			return Kit.section(length, top + EXIT_UP, parts)
		end,
	},
}

return M
