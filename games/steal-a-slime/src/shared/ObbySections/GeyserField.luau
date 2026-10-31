--!strict
--[[
	Geyser Field (obby idea 21, docs/obby-variants/21.json; contract/obby-sections.md)

	Vents on a beat throw you up to high ledges. Looks follow contract §8: a geyser vent is an orange `spring` disc
	with 1..3 rings for its height (a timed `bounce`: it throws only while cycle < duty and its rim glows before it
	goes); a geyser column you ride out of a red goo pit is a timed `wind` column (`lift` with `cap`); a red geyser is
	a red see-through `hazard` column that is only there while it blows (`flip` on a duty: touching it while it blows
	sends you back to the start pad). A one-shot vent has a see-through bubble cap (the `trigger`): touching it starts
	the vent's own clock (`start`), the vent blows once after its fuse and then refills for the rest of its period.

	Every variant opens with a 4-stud jump off the entry pad (a walker holding forward drops into it: ObbyCheck
	.walkStop), and every climb is a rise of 7.5+ studs (over a plain jump's 7.2) or a gap of 8 at a rise of 3, so the
	geysers are the only way up (tests/obby/GeyserField.spec takes them away and checks nothing can be made).

	Timing (contract §10; tests/obby/GeyserField.spec measures each one, the shared checks only see crossings):
	  * a vent under a red column: arrive after the red one stops and be thrown before it blows again;
	  * a one-shot vent: its fuse is the time you have to get onto the vent after touching its bubbles;
	  * a pit column: jump in while it blows with time left to ride up to the hover and step off (or on into the next);
	  * a red walkway or field geyser: walk past it while it is dry (ObbyCheck.fairness, the real crossing).
	Easy windows 1.4..2.0 s, medium 1.0..1.4, hard 0.75..1.0. Vents under a red column sit on rocks with a 3-stud
	strip the red never reaches (z 4..7): the place to wait.

	Hand-made on purpose (see the design file: launch height, beat and landing spot have to fit together). Variants are
	appended, never reordered.
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

local ENTRY = 10 -- the entry pad: x 0..ENTRY, full lane
local JUMP_IN = 4 -- the hole after it: too long to walk over
local FROM = ENTRY + JUMP_IN -- where the first rock starts
local VENT = 8 -- a vent's diameter (a bounce pad needs 8 across)
local VENT_UP = 0.2 -- a vent sits this far proud of its rock
local ROOT = 3 -- feet to the root part a lift column holds (ObbyFx lifts the root)
local LIFT = 40 -- pit column speed (studs / s)
local COLUMN = 8 -- pit column width
local PUFF = 20 -- a puff's speed (Third Time)
local PUFF_HOVER = 3 -- feet over the vent a puff holds you
local RED_HIGH = 7 -- a red geyser column's height over its floor
local PIT_DOWN = 4 -- a red goo pit's top under the rock it sits by

-- Launch speed that throws you `high` studs up.
local function power(high: number): number
	return math.sqrt(2 * Kit.GRAVITY * high)
end

-- The share of the period to run ahead so the motion is on from `from` s into each period (on while cycle < duty).
local function phaseFor(from: number, period: number): number
	return (-from / period) % 1
end

local function rings(high: number): string
	return if high >= 13 then "rings3" elseif high >= 9 then "rings2" else "rings1"
end

local function entry(parts: { Kit.Part })
	table.insert(parts, Kit.slab(ENTRY / 2, 0, 0, ENTRY, Kit.WIDTH, "jelly", { tone = 1 }))
end

-- A rock (a step) from x0 to x1 with its top at `top`, `wide` across, centred on z.
local function rock(x0: number, x1: number, top: number, z: number?, wide: number?, tone: number?): Kit.Part
	return Kit.slab((x0 + x1) / 2, top, z or 0, x1 - x0, wide or Kit.WIDTH, "jelly", { tone = tone or 3 })
end

type VentOpts = {
	period: number,
	from: number?, -- seconds into the period it starts blowing
	blow: number, -- seconds it blows
	island: boolean?, -- the vent is its own rock (no rock under it)
	start: string?, -- a one-shot: runs on this trigger group's clock
}

-- A green geyser vent (a step) centred on (x, z) on a floor whose top is `top`: throws you `high` studs up.
local function vent(x: number, top: number, z: number, high: number, o: VentOpts): Kit.Part
	local up = if o.island then 0 else VENT_UP
	return Kit.slab(x, top + up, z, VENT, VENT, "spring", {
		shape = "disc",
		marker = rings(high),
		start = o.start,
		motion = {
			kind = "bounce",
			power = power(high),
			period = o.period,
			duty = o.blow / o.period,
			phase = phaseFor(o.from or 0, o.period),
		},
	})
end

-- A one-shot vent: the bubble cap over it (`size` across, `round` for a disc, else a block) starts its clock; it blows
-- `fuse` s later for `blow` s, then refills for `refill` s (and blows again each period after that).
local function oneShot(
	parts: { Kit.Part },
	x: number,
	top: number,
	z: number,
	high: number,
	fuse: number,
	blow: number,
	refill: number,
	group: string,
	cap: { x: number, z: number, sx: number, sz: number, round: boolean }
)
	table.insert(
		parts,
		vent(x, top, z, high, { period = fuse + blow + refill, from = fuse, blow = blow, start = group })
	)
	local h = 3
	table.insert(
		parts,
		Kit.prop({ cap.sx, h, cap.sz }, { cap.x, top + VENT_UP + h / 2, cap.z }, "bubble", {
			ghost = true,
			shape = if cap.round then "disc" else nil,
			trigger = group,
			tone = 3,
		})
	)
end

-- A red geyser column `d` across on a floor whose top is `top`: there (and deadly) `onFor` s from `from` s into each
-- `period`.
local function red(x: number, top: number, z: number, d: number, period: number, from: number, onFor: number): Kit.Part
	return Kit.hazard({ d, RED_HIGH, d }, { x, top + RED_HIGH / 2, z }, {
		shape = "disc",
		motion = { kind = "flip", period = period, duty = onFor / period, phase = phaseFor(from, period) },
	})
end

-- A red goo pit under x0..x1 whose top is `top`: always there.
local function pit(x0: number, x1: number, top: number): Kit.Part
	return Kit.hazard({ x1 - x0, 1, Kit.WIDTH }, { (x0 + x1) / 2, top - 0.5, 0 })
end

-- A timed geyser column (a step you ride) from `bottom` up, centred on (x, z): it holds your feet at `hover` while it
-- blows `onFor` s from `from` s into each `period`.
local function column(
	x: number,
	z: number,
	bottom: number,
	hover: number,
	period: number,
	from: number,
	onFor: number
): Kit.Part
	local cap = hover + ROOT - bottom
	local h = cap + 1
	return Kit.prop({ COLUMN, h, COLUMN }, { x, bottom + h / 2, z }, "wind", {
		ghost = true,
		step = true,
		motion = {
			kind = "lift",
			power = LIFT,
			cap = cap,
			period = period,
			duty = onFor / period,
			phase = phaseFor(from, period),
		},
	})
end

-- A puff over a vent whose top is `ventTop`: a short timed column that lifts you PUFF_HOVER studs and drops you back.
local function puff(x: number, ventTop: number, z: number, period: number, from: number, onFor: number): Kit.Part
	local cap = PUFF_HOVER + ROOT
	return Kit.prop({ VENT, cap + 1, VENT }, { x, ventTop + (cap + 1) / 2, z }, "wind", {
		ghost = true,
		shape = "disc",
		motion = {
			kind = "lift",
			power = PUFF,
			cap = cap,
			period = period,
			duty = onFor / period,
			phase = phaseFor(from, period),
		},
	})
end

-- Rocks for vents under a red column: 14 across (z -7..7), the vent at z -3 under a 10-wide red column at z -2, so
-- the strip z 4..7 is always safe.
local STRIP_WIDE = 14
local VENT_Z = -3
local RED_Z = -2
local RED_D = 10

-- A red geyser curtain across the whole lane in the gap between two islands, from `bottom` up to `top`: there (and
-- deadly) `onFor` s from `from` s into each `period`. It reaches higher than any throw, so you can only fly through it
-- while it is dry.
local CURTAIN = 3 -- a curtain's thickness along the course
local function curtain(x: number, bottom: number, top: number, period: number, from: number, onFor: number): Kit.Part
	return Kit.hazard({ CURTAIN, top - bottom, Kit.WIDTH }, { x, (bottom + top) / 2, 0 }, {
		motion = { kind = "flip", period = period, duty = onFor / period, phase = phaseFor(from, period) },
	})
end

local M = {}
M.id = "GeyserField"
M.name = "Geyser Field"
M.idea = 21

M.variants = {
	{
		-- One big geyser on its own island over red goo: hop onto it, wait for the short blow, ride it up to the ledge.
		name = "Old Faithful",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			table.insert(parts, rock(FROM, 22, 0))
			table.insert(parts, vent(30, 0, 0, 14, { period = 3.5, blow = 0.7, island = true }))
			table.insert(parts, rock(38, 50, 12, 0, Kit.WIDTH, 2))
			table.insert(parts, pit(22, 38, -PIT_DOWN))
			return Kit.section(50, 12, parts)
		end,
	},
	{
		-- Three small geysers blowing together on a quick beat, each a hop up onto the next small rock over red goo.
		name = "Hop Pools",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local top = 0
			for i = 0, 2 do
				local x0 = FROM + i * 14
				table.insert(parts, rock(x0, x0 + 10, top, 0, 16, if i % 2 == 0 then 3 else 2))
				table.insert(parts, vent(x0 + 5.5, top, 0, 11, { period = 2.4, blow = 0.5 }))
				top += 8
			end
			table.insert(parts, rock(56, 66, top, 0, Kit.WIDTH, 2))
			table.insert(parts, pit(FROM + 10, 56, -PIT_DOWN))
			return Kit.section(66, top, parts)
		end,
	},
	{
		-- Two geysers under red columns that blow right after them: wait on the safe strip while the red one blows,
		-- then step onto the vent before the next green blow (the countdown is the rim glow).
		name = "Bubble Countdown",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			table.insert(parts, rock(FROM, 30, 0, 0, STRIP_WIDE))
			table.insert(parts, vent(24, 0, VENT_Z, 12, { period = 4, blow = 0.6 }))
			table.insert(parts, red(24, VENT_UP, RED_Z, RED_D, 4, 0.85, 2.05))
			table.insert(parts, rock(32, 48, 9, 0, STRIP_WIDE, 2))
			table.insert(parts, vent(42, 9, VENT_Z, 12, { period = 4, from = 2, blow = 0.6 }))
			table.insert(parts, red(42, 9 + VENT_UP, RED_Z, RED_D, 4, 2.85, 2.05))
			table.insert(parts, rock(50, 60, 18))
			return Kit.section(60, 18, parts)
		end,
	},
	{
		-- A green geyser up onto a 10-wide walkway with two red geysers across it on alternating beats (wait in the
		-- pocket between them), then a green one up to the exit.
		name = "Red Lesson",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			table.insert(parts, rock(FROM, 26, 0))
			table.insert(parts, vent(21, 0, 0, 12, { period = 4, blow = 1 }))
			table.insert(parts, rock(28, 68, 9, 0, 10, 2))
			table.insert(parts, vent(63, 9, 0, 12, { period = 4, from = 2, blow = 1 }))
			table.insert(parts, rock(70, 80, 18))
			-- 12 across on the 10-wide walkway: no way round them.
			table.insert(parts, red(36, 9, 0, 12, 4, 1, 1.55))
			table.insert(parts, red(53, 9, 0, 12, 4, 3, 1.55))
			return Kit.section(80, 18, parts)
		end,
	},
	{
		-- Two one-shot geysers over red goo: touch the bubbles and the vent blows once 1.4 s later.
		name = "Fuse Pool",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			table.insert(parts, rock(FROM, 26, 0, 0, 12))
			oneShot(parts, 21, 0, 0, 12, 1.4, 0.6, 3, "fuse1", { x = 21, z = 0, sx = 11, sz = 11, round = true })
			table.insert(parts, rock(30, 42, 9, 0, 12, 2))
			oneShot(parts, 37, 9, 0, 12, 1.4, 0.6, 3, "fuse2", { x = 37, z = 0, sx = 11, sz = 11, round = true })
			table.insert(parts, rock(46, 56, 18, 0, 16))
			table.insert(parts, pit(26, 46, -PIT_DOWN))
			return Kit.section(56, 18, parts)
		end,
	},
	{
		-- Four island vents over the drop, each on its own beat, with a red curtain in every gap on yet another beat:
		-- read which blow gets you through the curtain while it is dry.
		name = "Off-Beat Row",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			table.insert(parts, rock(FROM, 22, 0))
			local beats = { 2.6, 3.2, 2.8, 3.6 }
			local curtains = { { 3.9, 1.1, 1.7 }, { 4.8, 1.1, 2.1 }, { 4.2, 1.1, 1.8 } }
			local top = 0
			for i, period in beats do
				local x = 30 + (i - 1) * 14
				table.insert(parts, vent(x, top, 0, 12, { period = period, blow = 0.5, island = true }))
				local c = curtains[i]
				if c then
					table.insert(parts, curtain(x + 7, top - 8, top + 16, c[1], c[2], c[3]))
				end
				top += 7.5
			end
			table.insert(parts, rock(82, 92, top))
			return Kit.section(92, top, parts)
		end,
	},
	{
		-- Three one-shot geysers with a 1 s fuse on small rocks over red goo that zigzag; the last ledge is off to the
		-- side.
		name = "One Shot",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			table.insert(parts, rock(FROM, 26, 0))
			oneShot(parts, 21, 0, 0, 12, 1, 0.4, 5, "shot1", { x = 21, z = 0, sx = 11, sz = 11, round = true })
			table.insert(parts, rock(28, 38, 9, 5, 10, 2))
			oneShot(parts, 33, 9, 5, 12, 1, 0.4, 5, "shot2", { x = 33, z = 5, sx = 10, sz = 10, round = false })
			table.insert(parts, rock(40, 50, 18, -5, 10))
			oneShot(parts, 45, 18, -5, 12, 1, 0.4, 5, "shot3", { x = 45, z = -5, sx = 10, sz = 10, round = false })
			table.insert(parts, rock(52, 62, 27, 6, 12, 2))
			table.insert(parts, pit(26, 52, -PIT_DOWN))
			return Kit.section(62, 27, parts)
		end,
	},
	{
		-- Each rock has a green vent under a red column that blows 1 s after the green one: wait on the strip, step on
		-- once the red one stops.
		name = "Red Neighbours",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local top = 0
			for i = 0, 2 do
				local a = FROM + i * 19
				table.insert(parts, rock(a, a + 16, top, 0, STRIP_WIDE, if i % 2 == 0 then 3 else 2))
				table.insert(parts, vent(a + 10, top, VENT_Z, 11, { period = 3, blow = 0.45 }))
				table.insert(parts, red(a + 10, top + VENT_UP, RED_Z, RED_D, 3, 1, 1.3))
				top += 8
			end
			table.insert(parts, rock(71, 81, top))
			table.insert(parts, pit(FROM + 16, 71, -PIT_DOWN))
			return Kit.section(81, top, parts)
		end,
	},
	{
		-- Fast geysers (1.8 s beat, 0.4 s blow) under a red column that blows just after, switching sides each rock: land
		-- on the strip, then get on in the short gap.
		name = "Quick Spouts",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local top = 0
			for i = 0, 3 do
				local a = FROM + i * 16
				local side = if i % 2 == 0 then 1 else -1
				table.insert(parts, rock(a, a + 12, top, 0, STRIP_WIDE, if i % 2 == 0 then 3 else 2))
				table.insert(parts, vent(a + 7, top, side * VENT_Z, 11, { period = 1.8, blow = 0.4 }))
				table.insert(parts, red(a + 7, top + VENT_UP, side * RED_Z, RED_D, 1.8, 0.65, 0.4))
				top += 7.5
			end
			table.insert(parts, rock(78, 88, top))
			return Kit.section(88, top, parts)
		end,
	},
	{
		-- Puff, puff, BIG: a red column covers each vent, then two short puffs count you in and the third blow throws you
		-- up. Step on after the red one drops and before the BIG.
		name = "Third Time",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local rocks = { { FROM, 26 }, { 28, 40 }, { 42, 54 } }
			local top = 0
			local period = 3.6
			for i, r in rocks do
				local x = r[2] - 5
				local o = (i - 1) * 1.2 -- each rock a little later: you land as its puffs go
				table.insert(parts, rock(r[1], r[2], top, 0, STRIP_WIDE, if i % 2 == 0 then 2 else 3))
				table.insert(parts, vent(x, top, VENT_Z, 14, { period = period, from = o + 1.5, blow = 0.4 }))
				table.insert(parts, puff(x, top + VENT_UP, VENT_Z, period, o + 0.45, 0.25))
				table.insert(parts, puff(x, top + VENT_UP, VENT_Z, period, o + 0.9, 0.25))
				table.insert(parts, red(x, top + VENT_UP, RED_Z, RED_D, period, o + 2, 2))
				top += 10.5
			end
			table.insert(parts, rock(56, 66, top))
			return Kit.section(66, top, parts)
		end,
	},
	{
		-- The vents sit at the bottom of red goo pits: jump off the edge into the column while it blows and it holds
		-- you over the next ledge.
		name = "Spout Catch",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			table.insert(parts, rock(FROM, 24, 0))
			table.insert(parts, column(32, 0, -PIT_DOWN, 11.5, 3, 0, 1.95))
			table.insert(parts, rock(37.5, 50, 10, 0, Kit.WIDTH, 2))
			table.insert(parts, column(58, 0, 10 - PIT_DOWN, 21.5, 3, 1.5, 1.95))
			table.insert(parts, rock(63.5, 74, 20))
			table.insert(parts, pit(24, 37.5, -PIT_DOWN))
			table.insert(parts, pit(50, 63.5, 10 - PIT_DOWN))
			return Kit.section(74, 20, parts)
		end,
	},
	{
		-- Small island vents 8 apart, each blowing 0.9 s after the last: a launch lands you on the next one just as it
		-- blows, four in a row. The red curtain in each gap is dry only on the chain's beat: miss it and you wait two
		-- beats on a small island over the drop.
		name = "Chain Reaction",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			table.insert(parts, rock(FROM, 24, 0))
			for i = 0, 3 do
				local x = 32 + i * 16
				local top = 1 + i * 3
				table.insert(parts, vent(x, top, 0, 14, { period = 3.6, from = i * 0.9, blow = 0.5, island = true }))
				if i < 3 then
					-- on for the beat after the chain's throw (blow + flight + a breath), dry on the next
					table.insert(parts, curtain(x + 8, top - 8, top + 18, 7.2, i * 0.9 + 1.4, 3.6))
				end
			end
			table.insert(parts, rock(92, 102, 13))
			return Kit.section(102, 13, parts)
		end,
	},
	{
		-- A field of red geysers in two rows across the lane, each on its own beat: pick the one that is dry, then
		-- pick the green geyser that blows next.
		name = "Red Field",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			table.insert(parts, rock(FROM, 46, 0))
			table.insert(parts, vent(40, 0, -6, 14, { period = 3.4, blow = 0.6 }))
			table.insert(parts, vent(40, 0, 6, 14, { period = 2.6, from = 1.3, blow = 0.6 }))
			table.insert(parts, rock(48, 82, 8, 0, Kit.WIDTH, 2))
			table.insert(parts, vent(77, 8, -6, 14, { period = 3, from = 0.5, blow = 0.6 }))
			table.insert(parts, vent(77, 8, 6, 14, { period = 3.6, from = 2, blow = 0.6 }))
			table.insert(parts, rock(84, 94, 18))
			-- Row A: three pools across the lane.
			table.insert(parts, red(24, 0, -8, 8, 2.4, 0, 1.0))
			table.insert(parts, red(24, 0, 0, 8, 3.0, 0.8, 1.6))
			table.insert(parts, red(24, 0, 8, 8, 3.6, 1.6, 2.2))
			-- Row B: two big pools across the lane.
			table.insert(parts, red(62, 8, -6, 12, 2.8, 0, 1.15))
			table.insert(parts, red(62, 8, 6, 12, 3.4, 1.2, 1.75))
			return Kit.section(94, 18, parts)
		end,
	},
	{
		-- One-shot geysers with a 0.75 s fuse on small rocks over red goo: landing anywhere on a rock lights its fuse,
		-- so get onto the vent at once or wait 6 s for it to refill.
		name = "Dry Run",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			table.insert(parts, rock(FROM, 26, 0))
			oneShot(parts, 21, 0, 0, 12, 0.75, 0.4, 6, "dry1", { x = 21, z = 0, sx = 11, sz = 11, round = true })
			local top = 9
			for i = 0, 2 do
				local a = 29 + i * 15
				table.insert(parts, rock(a, a + 12, top, 0, 12, if i % 2 == 0 then 2 else 3))
				oneShot(parts, a + 7, top, 0, 12, 0.75, 0.4, 6, `dry{i + 2}`, {
					x = a + 6,
					z = 0,
					sx = 12,
					sz = 12,
					round = false,
				})
				top += 9
			end
			table.insert(parts, rock(74, 84, top, 0, 16))
			table.insert(parts, pit(26, 74, -PIT_DOWN))
			return Kit.section(84, top, parts)
		end,
	},
	{
		-- A tall climb: every landing ledge has a red geyser that blows 1.5 s after the green one that threw you, over
		-- its own vent. Chain straight on, or wait on the ledge's strip and catch the short gap.
		name = "Summit Spouts",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local period = 3.4
			table.insert(parts, rock(FROM, 26, 0))
			table.insert(parts, vent(21, 0, VENT_Z, 14, { period = period, blow = 0.5 }))
			for i = 1, 3 do
				local a = 29 + (i - 1) * 13
				local top = i * 10
				local o = (i - 1) * 0.75 -- the green that throws you here
				table.insert(parts, rock(a, a + 10, top, 0, STRIP_WIDE, if i % 2 == 0 then 3 else 2))
				table.insert(parts, vent(a + 5, top, VENT_Z, 14, { period = period, from = o + 0.75, blow = 0.5 }))
				table.insert(parts, red(a + 5, top + VENT_UP, RED_Z, RED_D, period, o + 1.5, 2.28))
			end
			table.insert(parts, rock(68, 78, 40))
			return Kit.section(78, 40, parts)
		end,
	},
	{
		-- Three columns out of one red goo pit with no floor between: ride one, walk off into the next as it comes
		-- up, and step off the last onto the exit ledge.
		name = "Pit Spouts",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			table.insert(parts, rock(FROM, 24, 0))
			local bottom = -8
			table.insert(parts, column(32, 0, bottom, 1.5, 3, 0.4, 1.15))
			table.insert(parts, column(43, 0, bottom, 3.5, 3, 1, 1.6))
			table.insert(parts, column(54, 0, bottom, 7.5, 3, 2, 1.6))
			table.insert(parts, rock(59.5, 70, 6))
			table.insert(parts, pit(24, 59.5, bottom))
			return Kit.section(70, 6, parts)
		end,
	},
}

return M
