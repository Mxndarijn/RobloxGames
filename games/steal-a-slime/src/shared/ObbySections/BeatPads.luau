--!strict
--[[
	Beat Pads (obby idea 18, docs/obby-variants/18.json; contract/obby-sections.md)

	Pink jelly pads breathe on the beat clock (Kit.BPM): a `shrink` motion snapped to whole beats with `beat`, so every
	pad is at full size exactly on a beat tick and flashes with it (ObbyFx). Between beats a pad shrinks round its own
	centre: wait in the middle, jump when the gap to the next pad has closed. Standing near an edge while it shrinks
	drops you. Static blue pads (the entry, drums, the exit ledge) never move.

	Hand-made on purpose: the patterns (on-beat, off-beat, waltz, speed-up) have to sound like music. Variants are
	appended, never reordered.

	Timing: a pad's scale is min + (1 - min) * (1 + cos(2 pi cycle)) / 2, full at cycle 0 (Kit.offsetAt). A jump is
	on while the edge-to-edge gap to the next pad is at most Kit.GAP_MAX; tests/obby/BeatPads.spec measures that
	window for every pair and holds it to the tier's band (contract §10: easy 1.4..2.0 s, medium 1.0..1.4 s, hard
	0.75..1.0 s), tuned to just above the low end; it also checks you can wait on each pad (while it is a character
	wide) until the next jump opens. Every gap at full size is at least 4 studs (or a rise of 3), so holding forward never crosses.
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

local ENTRY_LONG = 8 -- the static entry pad at x 0..8
local EXIT_LONG = 8 -- the static exit ledge
local PAD_LOOK = "jelly" -- tone 1: pink beat pads
local PAD_TONE = 1
local REST_TONE = 3 -- blue: entry, drums and the exit never move
local GAP = 4 -- between two beat pads: too long to walk over (ObbyCheck.walkStop)

-- Seconds a jump between a static pad and a beat pad stays open, per tier (just above the low
-- end of its contract §10 band: not too easy).
local EDGE = { easy = 1.5, medium = 1.05, hard = 0.8 }

-- One pad of a lay-out: `long` along the course, `wide` across, `gap` studs of air before it, `up` studs higher than
-- the step before. `beats` = its period in beats (nil: a static drum pad), `min` its smallest scale, `phase` the
-- share of its period it runs ahead. `flip` makes it a flip tile instead (solid that share of each period, round its
-- beat). `beside` puts its centre that far past the centre of the pad before (rows side by side), `quiet` leaves out
-- the beat flash and tick, `goo` puts a red goo plate under it.
type Pad = {
	long: number,
	wide: number?,
	gap: number?,
	up: number?,
	z: number?,
	beside: number?,
	beats: number?,
	min: number?,
	phase: number?,
	flip: number?,
	quiet: boolean?,
	goo: boolean?,
}

type Layout = {
	tier: string,
	pads: { Pad },
	dark: number?, -- light radius of a dark zone over the pads
}

local function padPart(cx: number, top: number, pad: Pad): Kit.Part
	local wide = pad.wide or pad.long
	local z = pad.z or 0
	local beats = pad.beats
	if beats == nil then
		return Kit.slab(cx, top, z, pad.long, wide, PAD_LOOK, { tone = REST_TONE })
	end
	local period = Kit.beat(beats)
	if pad.flip then
		-- Solid for `flip` of the period, centred on its beat; blinks before it goes (ObbyFx).
		return Kit.slab(cx, top, z, pad.long, wide, "glow", {
			tone = 3,
			beat = beats,
			motion = { kind = "flip", duty = pad.flip, period = period, phase = ((pad.phase or 0) + pad.flip / 2) % 1 },
		})
	end
	return Kit.slab(cx, top, z, pad.long, wide, PAD_LOOK, {
		tone = PAD_TONE,
		beat = if pad.quiet then nil else beats,
		motion = { kind = "shrink", min = pad.min or 0.5, period = period, phase = (pad.phase or 0) % 1 },
	})
end

-- The gap between a static pad and beat pad `pad` that keeps the jump open `window` seconds a period: the beat pad's
-- near edge pulls back (1 - scale) * long / 2 as it shrinks, and the jump is on while the gap is under Kit.GAP_MAX.
local function edgeGap(pad: Pad?, window: number): number
	if pad == nil or pad.beats == nil or pad.flip then
		return GAP
	end
	local min = pad.min or 0.5
	local share = math.clamp(window / Kit.beat(pad.beats), 0, 1)
	local scale = min + (1 - min) * (1 + math.cos(math.pi * share)) / 2
	return math.clamp(Kit.GAP_MAX - (1 - scale) * pad.long / 2, GAP, Kit.GAP_MAX)
end

-- Lays the pads out along the course from a static entry pad to a static exit ledge. A gap the pad doesn't set is
-- GAP between two beat pads and edgeGap next to a static one.
local function lay(layout: Layout): Kit.Section
	local edge = EDGE[layout.tier]
	local parts = {}
	table.insert(parts, Kit.slab(ENTRY_LONG / 2, 0, 0, ENTRY_LONG, Kit.WIDTH, PAD_LOOK, { tone = REST_TONE }))
	local x, top = ENTRY_LONG, 0
	local goo = {}
	local prev: Pad? = nil
	local prevX = 0
	for _, pad in layout.pads do
		top += pad.up or 0
		local gap = pad.gap
		if gap == nil then
			if pad.beats == nil then
				gap = edgeGap(prev, edge)
			elseif prev == nil or prev.beats == nil then
				gap = edgeGap(pad, edge)
			else
				gap = GAP
			end
		end
		local beside = pad.beside
		local cx = if beside then prevX + beside else x + (gap :: number) + pad.long / 2
		prev, prevX = pad, cx
		x = math.max(x, cx + pad.long / 2)
		table.insert(parts, padPart(cx, top, pad))
		if pad.goo then
			-- A red goo plate just under the pad's top: it shows round your feet while the pad is small.
			table.insert(goo, Kit.hazard({ pad.long, 0.5, pad.wide or pad.long }, { cx, top - 0.65, pad.z or 0 }))
		end
	end
	local padsTo = x
	x += edgeGap(prev, edge)
	local length = x + EXIT_LONG
	table.insert(parts, Kit.slab(x + EXIT_LONG / 2, top, 0, EXIT_LONG, Kit.WIDTH, PAD_LOOK, { tone = REST_TONE }))
	for _, g in goo do
		table.insert(parts, g)
	end
	if layout.dark then
		-- See-through night over the pads (ObbyMoves dims the view and lights a small circle round you).
		local x0, height = ENTRY_LONG, top + 16
		table.insert(
			parts,
			Kit.prop({ padsTo - x0, height + 8, Kit.WIDTH }, { (x0 + padsTo) / 2, height / 2 - 4, 0 }, "dark", {
				ghost = true,
				zone = { kind = "dark", light = layout.dark },
			})
		)
	end
	return Kit.section(length, top, parts)
end

-- `n` copies of `pad`, the k-th with phase `phase(k)` and `up` from `up(k)` when given; `between` is the gap between
-- two of them (the first keeps its edge gap).
local function run(
	n: number,
	pad: Pad,
	phase: ((number) -> number)?,
	up: ((number) -> number)?,
	between: number?
): { Pad }
	local out = {}
	for k = 1, n do
		local p = table.clone(pad)
		if k > 1 and between then
			p.gap = between
		end
		if phase then
			p.phase = phase(k)
		end
		if up then
			p.up = up(k)
		end
		table.insert(out, p)
	end
	return out
end

local M = {}
M.id = "BeatPads"
M.name = "Beat Pads"
M.idea = 18

M.variants = {
	{
		-- Every pad swells together on one slow beat: wait in the middle, hop when they are all big.
		name = "Four on the Floor",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			return lay({ tier = "easy", pads = run(5, { long = 10, beats = 6, min = 0.45 }) })
		end,
	},
	{
		-- Two groups a quarter of a period apart: the next pad swells as yours shrinks, so you hop on every "and".
		name = "Ping Pong",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			return lay({
				tier = "easy",
				pads = run(6, { long = 10, beats = 6, min = 0.5 }, function(k)
					return if k % 2 == 0 then 0.25 else 0
				end),
			})
		end,
	},
	{
		-- Ride the swell: each pad peaks one beat after the one before it, so you hop on every beat without a wait.
		name = "Ride the Wave",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			return lay({
				tier = "easy",
				pads = run(6, { long = 10, beats = 6, min = 0.45 }, function(k)
					return -(k - 1) / 6
				end),
			})
		end,
	},
	{
		-- Two beat pads, a big steady drum pad to rest on, two more beat pads.
		name = "Drum Rest",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local beat = { long = 9, wide = 10, beats = 6, min = 0.4 }
			return lay({ tier = "easy", pads = { beat, beat, { long = 14, wide = 14 }, beat, beat } })
		end,
	},
	{
		-- The swell rolls toward you: each pad peaks one beat before the one behind it.
		name = "Backwave",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			return lay({
				tier = "medium",
				pads = run(7, { long = 8, wide = 9, beats = 5, min = 0.25 }, function(k)
					return (k - 1) / 5
				end),
			})
		end,
	},
	{
		-- Pads peak half a beat late, on the "and": the flash and the tick still mark the beat.
		name = "Off-Beat Hop",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			return lay({
				tier = "medium",
				pads = run(6, { long = 9, beats = 5, min = 0.6, phase = 0.5 / 5 }, nil, nil, 5),
			})
		end,
	},
	{
		-- The tempo rises along the section: six-beat pads, then four, then three.
		name = "Speed Up",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local beats = { 6, 6, 4, 4, 3, 3 }
			local mins = { 0.1, 0.1, 0.45, 0.45, 0.65, 0.65 }
			local pads = {}
			for k = 1, 6 do
				table.insert(pads, { long = 9, beats = beats[k], min = mins[k] })
			end
			return lay({ tier = "medium", pads = pads })
		end,
	},
	{
		-- A three-count bar: pads 1, 2 and 3 peak in turn and every third pad is a step up.
		name = "Waltz",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			return lay({
				tier = "medium",
				pads = run(6, { long = 9, beats = 6, min = 0.35 }, function(k)
					return -((k - 1) % 3) / 3
				end, function(k)
					return if k % 3 == 0 then 2.5 else 0
				end),
			})
		end,
	},
	{
		-- Syncopation: a long slow pad you wait on, then two quick pads one beat apart. Twice.
		name = "Hold and Hurry",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local hold = { long = 12, wide = 10, beats = 8, min = 0.1 }
			local function hurry(beatAfter: number): Pad
				return { long = 9, beats = 3, min = 0.6, phase = -beatAfter / 3 }
			end
			return lay({ tier = "medium", pads = { hold, hurry(1), hurry(2), hold, hurry(1), hurry(2) } })
		end,
	},
	{
		-- A staircase of beat pads: every jump is up a step and on time.
		name = "Beat Stairs",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			return lay({
				tier = "medium",
				pads = run(6, { long = 9, up = 3, beats = 4, min = 0.2 }, nil, nil, 3),
			})
		end,
	},
	{
		-- Pads swing from one side of the lane to the other: every on-beat jump is also a sideways one.
		name = "Zigzag Groove",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local pads = run(6, { long = 9, beats = 5, min = 0.5 }, nil, nil, 2.5)
			for k, pad in pads do
				pad.z = if k % 2 == 1 then -6.25 else 6.25
			end
			return lay({ tier = "medium", pads = pads })
		end,
	},
	{
		-- Beat pads mixed with flip tiles that vanish on the off-beat: one rhythm, two kinds of pad.
		name = "Beat and Flip",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local beat = { long = 9, beats = 5, min = 0.5 }
			local flip = { long = 9, beats = 5, flip = 0.4 }
			return lay({ tier = "medium", pads = { beat, flip, beat, flip, beat } })
		end,
	},
	{
		-- The middle two pads have no flash or tick and peak half a beat late: keep time by their size alone.
		name = "Silent Bar",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local pads = run(6, { long = 9, beats = 5, min = 0.3 })
			for k = 3, 4 do
				-- Quiet and on the "and": the ticks you still hear from pads 1-2 and 5-6 are the wrong moment here.
				pads[k].quiet = true
				pads[k].phase = 0.5 / 5
			end
			return lay({ tier = "medium", pads = pads })
		end,
	},
	{
		-- A quick beat and pads that shrink almost to nothing: land on the beat, jump straight on.
		name = "Double Time",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			return lay({ tier = "hard", pads = run(7, { long = 8, beats = 4, min = 0.05 }) })
		end,
	},
	{
		-- Each pad sits on a red goo plate that shows round your feet off the beat: stay in the middle.
		name = "Goo Heartbeat",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			return lay({ tier = "hard", pads = run(6, { long = 10, beats = 4, min = 0.25, goo = true }) })
		end,
	},
	{
		-- Two rows keep different beats (three and four beats a pad): cross between rows when they line up.
		name = "Two Drummers",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local pads = {}
			for k = 1, 6 do
				local beside = if k == 1 then nil else 6.5
				table.insert(pads, { long = 9, beside = beside, z = -6, beats = 3, min = 0.15 })
				table.insert(pads, { long = 9, beside = 6.5, z = 6, beats = 4, min = 0.15 })
			end
			return lay({ tier = "hard", pads = pads })
		end,
	},
	{
		-- Stairs that speed up: every pad a step higher and the beat quicker as you climb.
		name = "Rush Climb",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local beats = { 5, 5, 4, 4, 3, 3, 3 }
			local mins = { 0.08, 0.08, 0.1, 0.1, 0.4, 0.4, 0.4 }
			local gaps: { number? } = { nil, 4.5, GAP, GAP, GAP, GAP, GAP }
			local pads = {}
			for k = 1, 7 do
				table.insert(pads, { long = 8, gap = gaps[k], up = 3, beats = beats[k], min = mins[k] })
			end
			return lay({ tier = "hard", pads = pads })
		end,
	},
	{
		-- Dark: only the beat flash lights the pads, so you see where to land just when it is safe.
		name = "Night Groove",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			return lay({ tier = "hard", pads = run(6, { long = 9, beats = 4, min = 0.2 }), dark = 7 })
		end,
	},
}

return M
