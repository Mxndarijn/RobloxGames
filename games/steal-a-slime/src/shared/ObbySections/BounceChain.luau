--!strict
--[[
	Bounce Chain (obby idea 4, docs/obby-variants/4.json; contract/obby-sections.md)

	Everything that throws you is an orange spring pad (look "spring", motion `bounce`): 1 ring = low (45), 2 rings =
	normal (62), 3 rings = high (75); an arrow pad is tilted the way its `throw` goes; a star pad is a timed high pad
	(85) that only throws while its rim glows (`duty`, snapped to the beat). Red goo under the gaps (see SIDEWAYS_PIT).

	Numbers (Kit.GRAVITY 196.2): a pad throws you `power^2 / 392` studs up (45: 5.2, 62: 9.8, 75: 14.3, 85: 18.4).
	Holding forward you fly 16 studs / s, so from where the pad throws you (its near edge when you walk on) you carry
	CARRY(power, rise) studs. Every walked-on pad is laid out so that near-edge throw still lands (pad depth + gap
	<= carry - a few tenths); chained pads keep their pitch under the carry, so you can always shorten to fit.
	tests/obby/BounceChain.spec checks that rule and that every variant needs its pads.

	Blades (sweptPad): a timed pad stays a solid floor while it is dark, so on its own you could stand on it and
	wait. A swept pad has a tall goo blade beside it that rests off the pad while it glows and sweeps across it
	(a `path` with holds at both ends, 8 beats) in the middle of every dark spell: you can't wait on it, you step on
	while it glows. The spec measures each one's open window (glowing and the blade off) against the tier.

	Kit limits (listed in the idea's engineGaps): one motion per part, so a pad can't also slide or melt; no ring
	swap between powers; no super bounce on a jump. Variants keep their twist with what the kit has (a ride to a fixed
	pad, melting islands, timed star / swap pads with blades).

	SIDEWAYS_PIT: ObbyCheck's fairness runner can't follow a throw across the lane, so a goo floor under a sideways
	throw reads as never open; where the path steps sideways over a hole the goo is left out (falling still resets).

	Every variant opens with a 4-stud hole over goo (too long to walk over, ObbyCheck.walkStop), and the pads' gaps,
	sideways landings and back throws stop a walker that holds forward.
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

local LOW, MID, HIGH, STAR = 45, 62, 75, 85
local ENTRY = 8 -- entry pad length
local HOLE = 4 -- the opening jump: too long to walk over
local FROM = ENTRY + HOLE -- x of the first island
local PIT_DROP = 3 -- goo sits this far under the lowest floor near it
local TILT = 8 -- degrees an arrow pad leans the way it throws
local SIDE = 16 -- studs / s sideways throw of an arrow pad
local BACK = 14 -- studs / s backward throw
-- Pads 8 wide this far left or right of the middle: 2.5 studs apart in z, so no straight line across the lane
-- touches both (a walker stands 1 stud past an edge) and the next one is a short steer away.
local OFF = 5.25
local PAD_BEATS = 4 -- a timed pad's cycle (2.4 s at Kit.BPM)
local BLADE_TALL = 6 -- a blade is too tall to hop over while you stand on the pad (a jump is over 6 for 0.16 s)
local CLEAR = 1.5 -- studs past a pad's side edge a resting blade's face stays (a body is 1 each side)
local BLADE_MOVE = 1.2 -- seconds a blade takes to cross, at most

local function ringsOf(power: number): string
	return if power <= 50 then "rings1" elseif power <= 65 then "rings2" else "rings3"
end

local function merge(part: Kit.Part, extra: { [string]: any }?): Kit.Part
	if extra then
		for k, v in extra do
			(part :: any)[k] = v
		end
	end
	return part
end

-- A plain floor slab from x0 to x1 with its top at `top`.
local function floor(
	x0: number,
	x1: number,
	top: number,
	z: number,
	wide: number,
	tone: number?,
	extra: { [string]: any }?
): Kit.Part
	return Kit.slab((x0 + x1) / 2, top, z, x1 - x0, wide, "jelly", merge({ tone = tone or 1 } :: any, extra) :: any)
end

-- A floor that cracks and drops `delay` s after you land on it (back 4 s later).
local function melting(
	x0: number,
	x1: number,
	top: number,
	z: number,
	wide: number,
	tone: number,
	delay: number
): Kit.Part
	return floor(x0, x1, top, z, wide, tone, {
		motion = { kind = "melt", on = "land", delay = delay, away = 4 },
		marker = "cracks",
	})
end

-- A straight spring pad from x0 to x1 throwing up at `power` (rings for its power).
local function pad(
	x0: number,
	x1: number,
	top: number,
	z: number,
	wide: number,
	power: number,
	extra: { [string]: any }?
): Kit.Part
	local part = Kit.slab((x0 + x1) / 2, top, z, x1 - x0, wide, "spring", {
		motion = { kind = "bounce", power = power },
		marker = ringsOf(power),
	})
	return merge(part, extra)
end

-- An arrow pad: tilted the way it throws, `throw` = { x, y, z } on top of `power` up.
local function arrowPad(
	x0: number,
	x1: number,
	top: number,
	z: number,
	wide: number,
	power: number,
	throw: Kit.Vec
): Kit.Part
	local part = Kit.slab((x0 + x1) / 2, top, z, x1 - x0, wide, "spring", {
		motion = { kind = "bounce", power = power, throw = throw },
		marker = "arrows",
	})
	-- lean towards the throw: a +z throw tips the normal to +z (pitch), a -x throw tips it back (roll lifts +x)
	if throw[3] ~= 0 then
		part.pitch = if throw[3] > 0 then TILT else -TILT
	elseif throw[1] ~= 0 then
		part.roll = if throw[1] < 0 then TILT else -TILT
	end
	return part
end

-- A timed pad: throws at `power` only while its cycle is under `duty` (rim glows before), on a PAD_BEATS clock.
local function timedPad(
	x0: number,
	x1: number,
	top: number,
	z: number,
	wide: number,
	power: number,
	duty: number,
	phase: number,
	marker: string
): Kit.Part
	return Kit.slab((x0 + x1) / 2, top, z, x1 - x0, wide, "spring", {
		motion = { kind = "bounce", power = power, duty = duty, phase = phase },
		beat = PAD_BEATS,
		marker = marker,
	})
end

-- A timed pad with its goo blade (see Blades in the header): the blade rests CLEAR past one side edge, crosses to
-- CLEAR past the other in the middle of the pad's dark spell, rests there through the next glow, and comes back in
-- the next dark spell. Returns the pad and the blade.
local function sweptPad(
	x0: number,
	x1: number,
	top: number,
	z: number,
	wide: number,
	power: number,
	duty: number,
	phase: number,
	marker: string
): (Kit.Part, Kit.Part)
	local thePad = timedPad(x0, x1, top, z, wide, power, duty, phase, marker)
	local lo, hi = z - wide / 2 - CLEAR - 0.5, z + wide / 2 + CLEAR + 0.5 -- blade centre at either end
	assert(lo - 0.5 >= -Kit.HALF and hi + 0.5 <= Kit.HALF, "a pad's blade leaves the lane")
	local P = Kit.beat(PAD_BEATS)
	local period = 2 * P
	local move = math.min((1 - duty) * P - 0.2, BLADE_MOVE)
	local hold = (period - 2 * move) / 2
	-- the first crossing's middle, `hold + move / 2` into the blade's period, falls in the middle of a dark spell
	local mid = hold + move / 2
	local psi = ((mid / P + phase - (1 + duty) / 2) % 1) / 2
	local blade = Kit.hazard({ x1 - x0, BLADE_TALL, 1 }, { (x0 + x1) / 2, top + BLADE_TALL / 2, lo }, {
		motion = { kind = "path", points = { { 0, 0, 0 }, { 0, 0, hi - lo } }, hold = hold, phase = psi },
		beat = 2 * PAD_BEATS,
	})
	return thePad, blade
end

-- A pad that is there to be read, not taken (a decoy beside the real one): not on the walking path.
local function decoy(part: Kit.Part): Kit.Part
	part.step = nil
	return part
end

-- Red goo across the lane from x0 to x1, its top `PIT_DROP` under `over`.
local function pit(x0: number, x1: number, over: number): Kit.Part
	local top = over - PIT_DROP
	return Kit.hazard({ x1 - x0, 1, Kit.WIDTH }, { (x0 + x1) / 2, top - 0.5, 0 })
end

-- The entry pad and the opening hole (goo under it).
local function entry(parts: { Kit.Part })
	table.insert(parts, floor(0, ENTRY, 0, 0, Kit.WIDTH, 1))
end

local function add(parts: { Kit.Part }, ...: Kit.Part)
	for _, p in { ... } do
		table.insert(parts, p)
	end
end

local M = {}
M.id = "BounceChain"
M.name = "Bounce Chain"
M.idea = 4

M.variants = {
	{
		-- Four normal pads, each throwing you onto a ledge 6.5 up that holds the next one, on the other side.
		name = "Step Up",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(parts, floor(FROM, 20, 0, 0, 16, 2))
			-- a 3-stud hole past each 4-deep pad: a near-edge throw carries 8.0 up 6.5, it needs 7.5
			for i = 0, 3 do
				local x0, top = 20 + i * 15, i * 6.5
				add(parts, pad(x0, x0 + 4, top, if i % 2 == 0 then OFF else -OFF, 8, MID))
				if i < 3 then
					add(parts, floor(x0 + 7, x0 + 15, top + 6.5, 0, 16, 3 - i % 2))
				end
			end
			add(parts, floor(72, 81, 26, 0, Kit.WIDTH, 3))
			add(parts, pit(ENTRY, 72, 0))
			return Kit.section(81, 26, parts)
		end,
	},
	{
		-- Five pads over the drop, a little left and right of each other: ride each bounce onto the next, steering a
		-- step sideways and shortening if you would overshoot.
		name = "Hop Line",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(parts, floor(FROM, 20, 0, 0, 16, 2))
			-- 5.75 forward and 2.5 across between 3-deep pads (6.3 corner to corner, over a jump's 6): a near-edge
			-- throw carries 10.1, the hop needs 9.7
			for i = 0, 4 do
				local x0 = 20 + i * 8.75
				table.insert(parts, pad(x0, x0 + 3, 0, if i % 2 == 0 then OFF else -OFF, 8, MID))
			end
			add(parts, floor(64.25, 74.25, 0, 0, Kit.WIDTH, 3))
			add(parts, pit(ENTRY, FROM, 0)) -- goo only in the opening hole (see SIDEWAYS_PIT)
			return Kit.section(74.25, 0, parts)
		end,
	},
	{
		-- Two walls block the lane right past their pads: walk onto each pad (a jump onto its far half runs into the
		-- wall). The second wall is taller and its pad has three rings.
		name = "Over the Wall",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			-- wall 1: 7.5 over the 3-deep two-ring pad (higher than any jump), 1 thick, 1.5 past it
			add(parts, floor(FROM, 21, 0, 0, Kit.WIDTH, 2), pad(21, 24, 0, 0, 12, MID))
			add(parts, Kit.prop({ 1, 13.5, Kit.WIDTH }, { 26, 0.75, 0 }, "jelly", { tone = 3 }))
			-- wall 2: 11.5 over the 4-deep three-ring pad
			add(parts, floor(30.2, 38, 0, 0, Kit.WIDTH, 1), pad(38, 42, 0, 0, 12, HIGH))
			add(parts, Kit.prop({ 1, 17.5, Kit.WIDTH }, { 44, 2.75, 0 }, "jelly", { tone = 3 }))
			add(parts, floor(48.2, 60, 0, 0, Kit.WIDTH, 2))
			add(parts, pit(ENTRY, FROM, 0)) -- goo in the opening hole only: the fairness runner can't jump a wall
			return Kit.section(60, 0, parts)
		end,
	},
	{
		-- Two three-ring pads, each throwing you over a hole twice a jump wide onto a landing off to the other side.
		name = "Long Spring",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			-- 1: off a raised island, an 8.5 hole (near edge: 12.4 needed, 12.8 carried down 3)
			add(parts, floor(FROM, 20, 3, 0, 16, 2), pad(20, 23, 3, 5.5, 8, HIGH))
			add(parts, floor(31.5, 40, 0, -6.5, 11, 3))
			-- 2: level, an 8.25 hole (near edge: 12.1 needed, 12.2 carried)
			add(parts, pad(40, 43, 0, -5.5, 8, HIGH))
			add(parts, floor(51.25, 60, 0, 6.5, 11, 2), floor(60, 66, 0, 0, Kit.WIDTH, 1))
			add(parts, pit(ENTRY, FROM, 0)) -- goo only in the opening hole (see SIDEWAYS_PIT)
			return Kit.section(66, 0, parts)
		end,
	},
	{
		-- Two pads side by side, twice: count the rings. First two against three (only three reaches the ledge 11 up),
		-- then one against two (the ledge is 8 up).
		name = "Ring Count",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(parts, floor(FROM, 20, 0, 0, Kit.WIDTH, 2))
			-- the ledge is on the decoy's side: the high pad throws you up, you steer across onto it
			add(parts, decoy(pad(20, 24, 0, -6.5, 9, MID)), pad(20, 24, 0, 6.75, 9, HIGH))
			add(parts, floor(27, 36, 11, -6.125, 11.75, 3), floor(36, 42, 11, 0, Kit.WIDTH, 1))
			-- 8 up is over the two-ring pad's reach less 0.3; a near-edge throw carries 7.2, it needs 7
			add(parts, decoy(pad(42, 46, 11, -6.5, 9, LOW)), pad(42, 46, 11, 6.75, 9, MID))
			add(parts, floor(48.5, 56.5, 19, 0, 12, 2), floor(56.5, 62, 19, 0, Kit.WIDTH, 3))
			add(parts, pit(ENTRY, FROM, 0)) -- goo only in the opening hole (see SIDEWAYS_PIT)
			return Kit.section(62, 19, parts)
		end,
	},
	{
		-- Arrow pads throw you straight across the lane onto the side ledge beside them (let go of forward or you fly
		-- past it); each ledge cracks as you land, so hop on to the next pad: right, left, right.
		name = "Side Throw",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			-- each side ledge sits level with its pad, 6.5 across the lane (too far to jump), the next pad a 4.5 hop on
			-- (the left ledge sits a few studs further on than its pad, so no pad is a plain jump from another)
			add(parts, floor(FROM, 20, 0, -8, 8, 2), arrowPad(20, 28, 0, -7.5, 8, MID, { 0, 0, SIDE }))
			add(parts, melting(20, 28, 0, 7.5, 9, 3, 1.5), arrowPad(32.5, 40.5, 0, 7.5, 8, MID, { 0, 0, -SIDE }))
			add(parts, melting(36, 44, 0, -7.5, 9, 2, 1.5), arrowPad(48.5, 56.5, 0, -7.5, 8, MID, { 0, 0, SIDE }))
			add(parts, floor(58.5, 70.5, 0, 0, Kit.WIDTH, 1))
			add(parts, pit(ENTRY, FROM, 0)) -- goo only in the opening hole (see SIDEWAYS_PIT)
			return Kit.section(70.5, 0, parts)
		end,
	},
	{
		-- Six arrow pads over the drop with no ledges between: each throw lands on the next, so you never stop, and
		-- the last one throws you onto a floor sliding back and forth on its rail.
		name = "Zig-zag Tilt",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(parts, floor(FROM, 20, 0, 0, 16, 2))
			-- 15 across and only 7 forward a throw: hold forward through it and you outrun the pads
			for i = 0, 5 do
				local side = if i % 2 == 0 then -1 else 1
				local x0 = 20 + i * 7
				table.insert(parts, arrowPad(x0, x0 + 8, 0, 7.5 * side, 8, MID, { 0, 0, -SIDE * side }))
			end
			-- the slider rides 4 either way along the lane: land on it as it comes, hop off as it nears the exit
			local slide = { kind = "slide", axis = "x", amp = 4, period = 2.4 }
			add(parts, floor(66, 74, 0, -4, 8, 3, { motion = slide, marker = "rail" }))
			add(parts, floor(79, 89, 0, 0, Kit.WIDTH, 1))
			add(parts, pit(ENTRY, FROM, 0)) -- goo only in the opening hole (see SIDEWAYS_PIT)
			return Kit.section(89, 0, parts)
		end,
	},
	{
		-- Pairs of pads (one ring, three rings): under a goo ceiling take the low one, under open sky the high one.
		-- The floors between crack as you land, so read the next pair fast.
		name = "Low Ceiling",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local function ceiling(x0: number, x1: number, over: number)
				-- 12.5 over the floor: a low bounce (head 10.2) and a jump (12.2) pass under, a high bounce does not
				table.insert(parts, Kit.hazard({ x1 - x0, 1, Kit.WIDTH }, { (x0 + x1) / 2, over + 13, 0 }))
			end
			local MELT = 1.6
			-- A: under the ceiling, low pad on the left
			add(parts, floor(FROM, 20, 0, 0, Kit.WIDTH, 2))
			add(parts, pad(20, 23, 0, -6, 10, LOW), decoy(pad(20, 23, 0, 6, 10, HIGH)))
			ceiling(18, 30, 0)
			-- B: open sky, high pad on the right up to a ledge 10 up
			add(parts, melting(26, 34, 0, 0, Kit.WIDTH, 3, MELT))
			add(parts, decoy(pad(34, 37, 0, -6, 10, LOW)), pad(34, 37, 0, 6, 10, HIGH))
			-- C: under the ceiling again, on the ledge
			add(parts, melting(40, 48, 10, 0, Kit.WIDTH, 2, MELT))
			add(parts, pad(48, 51, 10, 6, 10, LOW), decoy(pad(48, 51, 10, -6, 10, HIGH)))
			ceiling(46, 58, 10)
			-- D: open sky, high pad on the left up to the exit
			add(parts, melting(54, 62, 10, 0, Kit.WIDTH, 3, MELT))
			add(parts, decoy(pad(62, 65, 10, 6, 10, LOW)), pad(62, 65, 10, -6, 10, HIGH))
			add(parts, floor(68, 80, 20, 0, Kit.WIDTH, 1))
			add(parts, pit(ENTRY, 68, 0))
			return Kit.section(80, 20, parts)
		end,
	},
	{
		-- Twice: a floor rides back and forth on its rail (4.5 from the ground at either end, 8.5 at its far point):
		-- step on as it comes, ride it to the three-ring pad, and steer across onto the ledge 9 up.
		name = "Pad on Rails",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(parts, floor(FROM, 20, 0, 0, Kit.WIDTH, 2))
			local function rail(x0: number, top: number, phase: number)
				local slide = { kind = "slide", axis = "x", amp = 4, period = 2.4, phase = phase }
				table.insert(parts, floor(x0, x0 + 8, top, 0, 10, 3, { motion = slide, marker = "rail" }))
			end
			-- the ledge is across from the pad: steer as you go up
			rail(24.5, 0, 0)
			add(parts, pad(37, 41, 0, -6, 8, HIGH))
			add(parts, floor(45, 53, 9, 6.25, 11.5, 2), floor(53, 57, 9, 0, Kit.WIDTH, 1))
			rail(61.5, 9, 0.5)
			add(parts, pad(74, 78, 9, 6, 8, HIGH))
			add(parts, floor(82, 92, 18, -6.25, 11.5, 2))
			add(parts, pit(ENTRY, FROM, 0)) -- goo only in the opening hole (see SIDEWAYS_PIT)
			return Kit.section(92, 18, parts)
		end,
	},
	{
		-- A star pad throws high only while its rim glows; the plain pad beside it bounces you short of the ledge.
		-- Twice: the second star has a goo blade that sweeps it while it is dark, so you can't wait on it.
		name = "Star Bounce",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(parts, floor(FROM, 20, 0, 0, Kit.WIDTH, 2))
			add(parts, timedPad(20, 24, 0, 5, 10, STAR, 0.45, 0, "star"), decoy(pad(20, 24, 0, -6.5, 9, MID)))
			-- the ledge is over the plain pad's side: up on the star, then steer across
			add(parts, floor(27, 36, 15, -7.25, 9.5, 3), floor(36, 42, 15, 0, Kit.WIDTH, 1))
			local star, blade = sweptPad(42, 46, 15, 3.5, 8, STAR, 0.45, 0.5, "star")
			add(parts, star, blade, decoy(pad(42, 46, 15, -8, 8, MID)))
			add(parts, floor(49, 57, 30, -7.5, 9, 2), floor(57, 63, 30, 0, Kit.WIDTH, 3))
			add(parts, pit(ENTRY, FROM, 0)) -- goo only in the opening hole (see SIDEWAYS_PIT)
			return Kit.section(63, 30, parts)
		end,
	},
	{
		-- Arrow pads throw you backwards and across onto a ledge above and behind; holding forward overshoots it.
		-- Beams lead from each ledge to the next pad and crack as you land on them: no stopping on the way up.
		name = "Bounce Back",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local back = { -BACK, 0, 0 }
			-- a beam drops 2 s after you land on it: 24 studs of it is 1.5 s at a run
			local function beam(x: number, top: number, z: number, long: number): Kit.Part
				return Kit.slab(x, top, z, long, 3, "beam", {
					motion = { kind = "melt", on = "land", delay = 2, away = 4 },
					marker = "cracks",
				})
			end
			add(parts, floor(FROM, 22, 0, -7, 10, 2), arrowPad(22, 30, 0, -7, 10, HIGH, back))
			add(parts, floor(10, 18, 8, 7, 10, 3), beam(30, 8, 10, 24))
			add(parts, arrowPad(42, 50, 8, 7, 10, HIGH, back))
			add(parts, floor(30, 38, 16, -7, 10, 2), beam(50, 16, -10, 24))
			add(parts, arrowPad(62, 70, 16, -7, 10, HIGH, back))
			add(parts, floor(50, 58, 24, 7, 10, 3), beam(64, 24, 10, 12))
			add(parts, floor(70, 82, 24, 0, Kit.WIDTH, 1))
			add(parts, pit(ENTRY, 70, 0))
			return Kit.section(82, 24, parts)
		end,
	},
	{
		-- Five islands climbing 6 a step, each with a pad at its end: an island starts melting the moment you land
		-- on it, so keep bouncing (it drops after 1 s, back 4 s later).
		name = "Spent Springs",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			for i = 0, 4 do
				local x0, top = FROM + i * 15, i * 6
				add(
					parts,
					melting(x0, x0 + 8, top, 0, 14, 2 + i % 2, 1),
					pad(x0 + 8, x0 + 12, top, if i % 2 == 0 then OFF else -OFF, 8, MID)
				)
			end
			add(parts, floor(87, 97, 30, 0, Kit.WIDTH, 1))
			add(parts, pit(ENTRY, 87, 0))
			return Kit.section(97, 30, parts)
		end,
	},
	{
		-- Twice: a two-ring hop over a hole, then a three-ring pad that throws only while its rings glow. A goo blade
		-- sweeps the pad while it is dark, so step on as it lights, then steer across onto the ledge 11 up.
		name = "Ring Swap",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			-- 6.5-stud holes past 3-deep two-ring pads: a near-edge throw carries 10.1, the hop needs 10
			add(parts, floor(FROM, 21, 0, 0, 16, 2), pad(21, 24, 0, 0, 10, MID))
			add(parts, floor(30.5, 38.5, 0, 0, Kit.WIDTH, 3))
			local p1, b1 = sweptPad(38.5, 42.5, 0, -3.5, 8, HIGH, 0.5, 0, "rings3")
			add(parts, p1, b1)
			add(parts, floor(45.5, 53.5, 11, 7.5, 9, 1), pad(53.5, 56.5, 11, 7.5, 9, MID))
			add(parts, floor(63, 71, 11, 0, Kit.WIDTH, 2))
			local p2, b2 = sweptPad(71, 75, 11, -3.5, 8, HIGH, 0.5, 0.5, "rings3")
			add(parts, p2, b2)
			add(parts, floor(78, 84, 22, 7.5, 9, 3), floor(84, 90, 22, 0, Kit.WIDTH, 1))
			add(parts, pit(ENTRY, FROM, 0), pit(24, 30.5, 0), pit(56.5, 63, 11))
			return Kit.section(90, 22, parts)
		end,
	},
	{
		-- Four three-ring pads over the drop with 7.5-stud holes, then a sliding floor: hold forward all the way and
		-- time the last throw for the slide.
		name = "Spring Relay",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(parts, floor(FROM, 20, 0, 0, 14, 2))
			-- 7.5 forward and 2.5 across between pads: a near-edge throw carries 12.2, the hop needs 11.4
			for i = 0, 3 do
				local x0 = 20 + i * 10.5
				table.insert(parts, pad(x0, x0 + 3, 0, if i % 2 == 0 then OFF else -OFF, 8, HIGH))
			end
			-- the slide: in reach from the last pad only while it is on its way back
			local slide = { kind = "slide", axis = "x", amp = 3, period = 2.4 }
			add(parts, floor(62.5, 72.5, 0, 6, 10, 3, { motion = slide, marker = "rail" }))
			add(parts, floor(77, 89, 0, 0, Kit.WIDTH, 1))
			add(parts, pit(ENTRY, FROM, 0)) -- goo only in the opening hole (see SIDEWAYS_PIT)
			return Kit.section(89, 0, parts)
		end,
	},
	{
		-- Arrow pads throw you across the lane past tall goo pillars: each pillar stands beside a pad on its throw
		-- side, so a throw from the pad's back corner (or a late one off the pad before) runs into it; go from the middle.
		name = "Tilt Through Pillars",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(parts, floor(FROM, 20, 0, 0, 16, 2))
			-- 15 across and 7 forward a throw (hold forward through it and you outrun the pads)
			local pitch = 7
			for i = 0, 4 do
				local side = if i % 2 == 0 then -1 else 1
				local x0 = 20 + i * pitch
				table.insert(parts, arrowPad(x0, x0 + 8, 0, 7.5 * side, 8, MID, { 0, 0, -SIDE * side }))
			end
			-- a 2x2 pillar a stud ahead of each pad's middle, 2.5 off the lane's centre on its throw side, taller than
			-- any throw: a throw from middle to middle clears the pillars by about 0.7 studs
			for i = 0, 4 do
				local side = if i % 2 == 0 then -1 else 1
				table.insert(parts, Kit.hazard({ 2, 19, 2 }, { 25 + i * pitch, 6.5, -2.5 * side }))
			end
			add(parts, floor(58, 70, 0, 0, Kit.WIDTH, 3))
			add(parts, pit(ENTRY, FROM, 0)) -- goo only in the opening hole (see SIDEWAYS_PIT)
			return Kit.section(70, 0, parts)
		end,
	},
	{
		-- A climb of three star pads out of step, 15 up each: each throws only in its short glow and has a goo blade
		-- that sweeps it while it is dark; the plain pad beside it falls short, and the ledges between crack.
		name = "Star Tower",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(parts, floor(FROM, 20, 0, 0, Kit.WIDTH, 2))
			-- stars swap sides: each throws you across onto a ledge on its plain pad's side, and the next star stands
			-- on that side 4 on (a jump, too far to walk over)
			for i = 0, 2 do
				local x0, top = 20 + i * 16, i * 15
				local side = if i % 2 == 0 then 1 else -1
				local star, blade = sweptPad(x0, x0 + 4, top, 3.5 * side, 8, STAR, 0.35, i / 3, "star")
				add(parts, star, blade, decoy(pad(x0, x0 + 4, top, -8 * side, 8, MID)))
				if i < 2 then
					-- it drops 2.6 s after you land (a dark spell and the hop), so you can wait out one glow, no more
					add(parts, melting(x0 + 7, x0 + 12, top + 15, -7.5 * side, 9, 3 - i % 2, 2.6))
				end
			end
			add(parts, floor(59, 65, 45, -7.5, 9, 2), floor(65, 71, 45, 0, Kit.WIDTH, 1))
			add(parts, pit(ENTRY, FROM, 0)) -- goo only in the opening hole (see SIDEWAYS_PIT)
			return Kit.section(71, 45, parts)
		end,
	},
	{
		-- Pads throw you onto floors sliding across the lane out of step: land on a moving target, then hop to the
		-- next pad as it lines up.
		name = "Sliding Chain",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(parts, floor(FROM, 20, 0, 0, 14, 2))
			-- pad, a 6.5-stud hole (too far to jump, inside the throw's 10.1), the slider, a 4-stud jump to the next pad
			for i = 0, 2 do
				local x0 = 20 + i * 21.5
				table.insert(parts, pad(x0, x0 + 3, 0, if i % 2 == 0 then OFF else -OFF, 8, MID))
				local slider = floor(x0 + 9.5, x0 + 17.5, 0, 0, 8, 3, {
					motion = { kind = "slide", axis = "z", amp = 5, period = 2.4, phase = i / 3 },
					marker = "rail",
				})
				table.insert(parts, slider)
			end
			add(parts, floor(84.5, 96.5, 0, 0, Kit.WIDTH, 1))
			add(parts, pit(ENTRY, 84.5, 0))
			return Kit.section(96.5, 0, parts)
		end,
	},
	{
		-- Four three-ring beat pads out of step, 10 up each, left, right: each throws only while its rings glow and
		-- has a blade that sweeps it while dark; it throws you across onto a small ledge that cracks as you land, and
		-- the next pad is a jump on from there. No pad and no ledge to rest on.
		name = "Swap Climb",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			add(parts, floor(FROM, 20, 0, 0, 16, 2))
			for i = 0, 3 do
				local x0, top = 20 + i * 16, i * 10
				local side = if i % 2 == 0 then -1 else 1
				local p, b = sweptPad(x0, x0 + 4, top, OFF * side, 8, HIGH, 0.35, (i * 0.4) % 1, "rings3")
				add(parts, p, b)
				if i < 3 then
					-- across the lane from the pad, 10 up; it drops 2.2 s after you land (one dark spell and the hop)
					add(parts, melting(x0 + 7, x0 + 12, top + 10, -6.625 * side, 10.75, 3 - i % 2, 2.2))
				end
			end
			add(parts, floor(75, 80, 40, -6.625, 10.75, 3), floor(80, 86, 40, 0, Kit.WIDTH, 1))
			add(parts, pit(ENTRY, FROM, 0)) -- goo only in the opening hole (see SIDEWAYS_PIT)
			return Kit.section(86, 40, parts)
		end,
	},
}

return M
