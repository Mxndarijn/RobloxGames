--!strict
--[[
	Two Roads (obby idea 11, docs/obby-variants/11.json; contract/obby-sections.md)

	The lane splits into roads you can study from the fork: a short, hard road (route "fast", on the right, z > 0)
	and a long, safe one (the main path, on the left, z < 0), with a see-through divider between them where they run
	side by side. Some variants stack the roads (a miss on the high road lands on the low one), add a third road
	("top" / "bottom"), a hidden one ("secret") or a crossing plank ("bail"). A `sign:` marker on each road's first
	pad says which is which.

	Walk-forward rule (contract §9, §11): every walking line needs a gap of 4 or more, a ledge over 1 stud, a wall or
	a hazard. Short hops on the safe roads therefore always climb or drop (1.5 or 3 studs), never sit level.

	Variants are appended, never reordered (a pick stores the index). Hand-made: the seed is ignored.
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

type Part = Kit.Part

local ENTRY = 8 -- the shared pad before the fork
local EXIT = 8 -- the shared pad where the roads join
local ROAD = 11 -- a side-by-side road's width (z 1..12 or -12..-1)
local LEFT, RIGHT = -6.5, 6.5 -- road centres: safe on the left, fast on the right
local PAD = 8 -- a small pad's width across the road
local BLOB_LONG, BLOB_TALL = 3, 4 -- a sliding goo blob: too tall to hop over, short to run past
local POST_SWING = 7 -- a goo post on a beam waits beside it, then dashes across to the other side

-- A walking slab from x0 to x1 (along the course) with its top at `top`.
local function slab(
	x0: number,
	x1: number,
	top: number,
	z: number,
	w: number,
	look: string,
	extra: { [string]: any }?
): Part
	return Kit.slab((x0 + x1) / 2, top, z, x1 - x0, w, look, extra)
end

-- `n` pads between x0 and x1: `before` studs of hole first, `gap` between pads, `after` studs before x1. Returns
-- each pad's { from, to }.
local function lay(x0: number, x1: number, n: number, gap: number, before: number, after: number): { { number } }
	local long = (x1 - x0 - before - after - gap * (n - 1)) / n
	local out = {}
	local x = x0 + before
	for _ = 1, n do
		table.insert(out, { x, x + long })
		x += long + gap
	end
	return out
end

local function entry(parts: { Part }, extra: { [string]: any }?)
	local e: { [string]: any } = extra or {}
	e.tone = e.tone or 1
	table.insert(parts, slab(0, ENTRY, 0, 0, Kit.WIDTH, "jelly", e))
end

local function exit(parts: { Part }, length: number, rise: number)
	table.insert(parts, slab(length - EXIT, length, rise, 0, Kit.WIDTH, "jelly", { tone = 3 }))
end

-- The see-through wall between two side-by-side roads (solid: you can't swap halfway), from y0 to y1.
local function divider(parts: { Part }, x0: number, x1: number, y0: number, y1: number)
	table.insert(parts, Kit.prop({ x1 - x0, y1 - y0, 1 }, { (x0 + x1) / 2, (y0 + y1) / 2, 0 }, "pipe"))
end

-- A red goo sweeper: a bar across a road `road` wide, two studs short of it, sliding side to side so the way past
-- opens on one side, then the other. SWEEP[tier] is its period: the open window it leaves a runner is about 1.7 s
-- (easy), 1.1 s (medium) or 0.9 s (hard) (tests/ObbyCheck.windows).
local SWEEP = table.freeze({ easy = 4, medium = 2.8, hard = 2.4 })
local function blob(x: number, z: number, top: number, road: number, period: number, phase: number): Part
	local wide = road - 2
	local amp = math.min(if road >= ROAD then 1 else 1.5, Kit.HALF - math.abs(z) - wide / 2)
	return Kit.hazard({ BLOB_LONG, BLOB_TALL, wide }, { x, top + BLOB_TALL / 2, z }, {
		motion = { kind = "slide", axis = "z", amp = amp, period = period, phase = phase },
	})
end

-- A still goo pool from x0 to x1 whose top sits at `top` (under the pads, so it only catches a miss).
local function pool(x0: number, x1: number, top: number, z: number, w: number): Part
	return Kit.hazard({ x1 - x0, 1, w }, { (x0 + x1) / 2, top - 0.5, z })
end

-- Contiguous stair treads from x0 to x1, one per top in `tops`.
local function stairs(
	parts: { Part },
	x0: number,
	x1: number,
	tops: { number },
	z: number,
	w: number,
	extra: { [string]: any }?
)
	local long = (x1 - x0) / #tops
	for i, top in tops do
		local e: { [string]: any } = if i == 1 and extra then table.clone(extra) else {}
		e.tone = e.tone or (i % 3 + 1)
		table.insert(parts, slab(x0 + (i - 1) * long, x0 + i * long, top, z, w, "jelly", e))
	end
end

-- A red goo post that waits beside a beam (at z + POST_SWING / 2), dashes across it, waits on the other side and
-- dashes back: `hold` s at each side, `period` s a round trip.
local function post(x: number, z: number, top: number, hold: number, period: number, phase: number): Part
	return Kit.hazard({ 1.5, 4, 1.5 }, { x, top + 2, z + POST_SWING / 2 }, {
		motion = {
			kind = "path",
			points = { { 0, 0, 0 }, { 0, 0, -POST_SWING } },
			hold = hold,
			period = period,
			phase = phase,
		},
	})
end

local FAST = { route = "fast", marker = "sign:FAST" }
local SAFE = { marker = "sign:SAFE" }

local function fastFirst(i: number, extra: { [string]: any }?): { [string]: any }
	local e: { [string]: any } = if extra then table.clone(extra) else {}
	e.route = "fast"
	if i == 1 then
		e.marker = e.marker or FAST.marker
	end
	return e
end

local M = {}
M.id = "TwoRoads"
M.name = "Two Roads"
M.idea = 11

M.variants = {
	{
		-- The first lesson: one 6-stud jump over a goo pit on the right, or a slow staircase down into the pit and
		-- back up on the left. A goo sweeper waits on each road: at the pit's bottom, and past the big jump.
		name = "One Big Jump",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length = 50
			local parts = {}
			entry(parts)
			stairs(parts, ENTRY, length - EXIT, { -2.5, -5, -7.5, -5, -2.5 }, LEFT, ROAD, SAFE)
			table.insert(parts, blob(25, LEFT, -7.5, ROAD, SWEEP.easy, 0))
			table.insert(
				parts,
				slab(ENTRY + 6, length - EXIT, 0, RIGHT, ROAD, "goo", { route = "fast", marker = FAST.marker })
			)
			table.insert(parts, pool(ENTRY, ENTRY + 6, -4, RIGHT, ROAD))
			table.insert(parts, blob(31, RIGHT, 0, ROAD, SWEEP.easy, 0.5))
			divider(parts, ENTRY, length - EXIT, -9, 9)
			exit(parts, length, 0)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Side by side: five hops that climb and drop 2 studs past a goo sweeper on the left, three 6-stud jumps
		-- past a goo sweeper on the right.
		name = "Left or Right",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length = 60
			local x0, x1 = ENTRY, length - EXIT
			local parts = {}
			entry(parts)
			local tops = { 2, 4, 2, 4, 2 }
			for i, p in lay(x0, x1, 5, 3, 3, 3) do
				table.insert(
					parts,
					slab(p[1], p[2], tops[i], LEFT, ROAD, "jelly", if i == 1 then SAFE else { tone = i % 3 + 1 })
				)
				if i == 3 then
					table.insert(parts, blob((p[1] + p[2]) / 2, LEFT, tops[i], ROAD, SWEEP.easy, 0.5))
				end
			end
			for i, p in lay(x0, x1, 3, 5.9, 5.9, 5.9) do
				table.insert(parts, slab(p[1], p[2], 0, RIGHT, ROAD, "goo", fastFirst(i)))
				if i == 2 then
					table.insert(parts, blob((p[1] + p[2]) / 2, RIGHT, 0, ROAD, SWEEP.easy, 0))
				end
			end
			divider(parts, x0, x1, -4, 12)
			exit(parts, length, 0)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- The safe road climbs stairs over a hill (a goo sweeper on top); the fast road stays low and jumps 5.5-stud
		-- gaps over goo, on and off a stone that slides back and forth.
		name = "Over the Hill",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length = 70
			local x0, x1 = ENTRY, length - EXIT
			local parts = {}
			entry(parts)
			stairs(parts, x0, x1, { 3, 6, 9, 12, 9, 6, 3 }, LEFT, ROAD, SAFE)
			table.insert(parts, blob(x0 + (x1 - x0) * 3.5 / 7, LEFT, 12, ROAD, SWEEP.easy, 0))
			for i, p in lay(x0, x1, 3, 5.5, 5.5, 5.5) do
				local extra = fastFirst(i)
				if i == 2 then
					extra.motion = { kind = "slide", axis = "x", amp = 1.5, period = 3.2 }
					extra.marker = "ghostStop"
				end
				table.insert(parts, slab(p[1], p[2], 0, RIGHT, ROAD, "goo", extra))
			end
			table.insert(parts, pool(x0, x1, -3, RIGHT, ROAD))
			divider(parts, x0, x1, -4, 20)
			exit(parts, length, 0)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- The fast road runs 9 studs over the safe floor: miss a jump and you land on the slow road, not at the
		-- start. Its middle pad slides, so you time the jumps on and off it. Two goo sweepers patrol the low road.
		name = "Safety Net",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length = 68
			local parts = {}
			entry(parts)
			table.insert(parts, slab(8, 11, -3, 0, Kit.WIDTH, "jelly", { tone = 2, marker = SAFE.marker }))
			table.insert(parts, slab(11, 14, -6, 0, Kit.WIDTH, "jelly", { tone = 3 }))
			table.insert(parts, slab(14, 54, -9, 0, Kit.WIDTH, "goo", { tone = 1 }))
			table.insert(parts, slab(54, 57, -6, 0, Kit.WIDTH, "jelly", { tone = 3 }))
			table.insert(parts, slab(57, 60, -3, 0, Kit.WIDTH, "jelly", { tone = 2 }))
			table.insert(parts, blob(25, 0, -9, Kit.WIDTH, SWEEP.easy, 0))
			table.insert(parts, blob(43, 0, -9, Kit.WIDTH, SWEEP.easy, 0.5))
			table.insert(
				parts,
				slab(14, 30, 0, 0, Kit.WIDTH, "jelly", { route = "fast", marker = FAST.marker, tone = 1 })
			)
			table.insert(
				parts,
				slab(36, 52.5, 0, 0, Kit.WIDTH, "jelly", {
					route = "fast",
					tone = 2,
					motion = { kind = "slide", axis = "x", amp = 1.5, period = 3.2 },
					marker = "ghostStop",
				})
			)
			exit(parts, length, 0)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- A thin balance beam on the right (one 5.5-stud hop, then a goo post that dashes across it), or a wide
		-- bridge that ramps down past a goo sweeper and steps back up on the left.
		name = "Beam or Bridge",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length = 50
			local parts = {}
			entry(parts)
			table.insert(parts, Kit.ramp(8, 0, 20, -4, LEFT, ROAD, "jelly", { tone = 2, marker = SAFE.marker }))
			table.insert(parts, slab(20, 31, -4, LEFT, ROAD, "goo", { tone = 1 }))
			table.insert(parts, slab(31, 35, -1.5, LEFT, ROAD, "jelly", { tone = 3 }))
			table.insert(parts, Kit.ramp(35, -1.5, 42, 0, LEFT, ROAD, "jelly", { tone = 2 }))
			table.insert(parts, blob(25.5, LEFT, -4, ROAD, SWEEP.easy, 0))
			table.insert(parts, slab(8, 23, 0, RIGHT, 3, "beam", { route = "fast", marker = FAST.marker }))
			table.insert(parts, slab(28.5, 42, 0, RIGHT, 3, "beam", { route = "fast" }))
			table.insert(parts, post(36, RIGHT, 0, 1.4, 4, 0))
			exit(parts, length, 0)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Stairs over the top (a goo sweeper on the way down) on the left, or one orange spring pad on the right that
		-- throws you over a wall, onto a landing a goo sweeper patrols.
		name = "Spring Shortcut",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length = 60
			local x0, x1 = ENTRY, length - EXIT
			local parts = {}
			entry(parts)
			stairs(parts, x0, x1, { 3, 6, 9, 12, 9, 6, 3 }, LEFT, ROAD, SAFE)
			table.insert(parts, blob(x0 + (x1 - x0) * 5.5 / 7, LEFT, 6, ROAD, SWEEP.easy, 0)) -- on the way down
			table.insert(
				parts,
				slab(12.5, 20.5, 0, RIGHT, ROAD, "spring", {
					route = "fast",
					motion = { kind = "bounce", power = 70, throw = { 14, 0, 0 } },
					marker = "rings2",
				})
			)
			table.insert(parts, Kit.prop({ 1, 10, ROAD }, { 27.5, 5, RIGHT }, "jelly", { tone = 2 }))
			table.insert(parts, slab(30, x1, 0, RIGHT, ROAD, "goo", { route = "fast", marker = FAST.marker }))
			table.insert(parts, blob(44, RIGHT, 0, ROAD, SWEEP.easy, 0.5))
			divider(parts, x0, x1, -1, 20)
			exit(parts, length, 0)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Four small pads with 6-stud jumps on the right (two slide, the last has a goo sweeper), five hops that
		-- climb and drop 2 on the left (the last pad swept too), and a plank halfway across the divider to bail out
		-- onto the safe road.
		name = "Bail Out",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 70
			local x0, x1 = ENTRY, length - EXIT
			local parts = {}
			entry(parts)
			-- Four hops, then a long last pad whose goo sweeper sits level with the one on the last fast pad.
			local safe = lay(x0, 46, 4, 3, 3, 0)
			table.insert(safe, { 49, x1 - 3 })
			local tops = { 2, 4, 2, 4, 2 }
			for i, p in safe do
				table.insert(
					parts,
					slab(p[1], p[2], tops[i], LEFT, ROAD, "jelly", if i == 1 then SAFE else { tone = i % 3 + 1 })
				)
				if i == 5 then
					table.insert(parts, blob(53, LEFT, tops[i], ROAD, SWEEP.medium, 0))
				end
			end
			local fast = lay(x0, x1, 4, 6, 6, 6)
			for i, p in fast do
				local extra = fastFirst(i, { tone = 2 })
				if i == 1 or i == 3 then
					extra.motion = { kind = "slide", axis = "z", amp = 1.5, period = 2.6, phase = (i - 1) / 4 }
				end
				table.insert(parts, slab(p[1], p[2], 0, RIGHT, PAD, "goo", extra))
				if i == 4 then
					table.insert(parts, blob((p[1] + p[2]) / 2, RIGHT, 0, PAD, SWEEP.medium, 0.5))
				end
			end
			-- The plank: from the second fast pad's left edge to the safe road, through an opening in the divider.
			local px = (fast[2][1] + fast[2][2]) / 2
			table.insert(parts, Kit.slab(px, 0, 0.75, 3, 5.5, "beam", { route = "bail", marker = "sign:BAIL" }))
			divider(parts, x0, px - 2, -1, 12)
			divider(parts, px + 2, x1, -1, 12)
			exit(parts, length, 0)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- A gate on the safe road opens and shuts on the beat: arrive while it is shut and you wait, then dodge a
		-- goo sweeper behind it. The fast road jumps three 6-stud gaps past goo sweepers.
		name = "Closing Gate",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 60
			local x0, x1 = ENTRY, length - EXIT
			local parts = {}
			entry(parts)
			table.insert(parts, slab(8, 18, 1.5, LEFT, ROAD, "jelly", { tone = 1, marker = SAFE.marker }))
			table.insert(parts, slab(18, 36, 3, LEFT, ROAD, "jelly", { tone = 2 }))
			table.insert(parts, slab(36, x1, 1.5, LEFT, ROAD, "jelly", { tone = 3 }))
			table.insert(
				parts,
				Kit.prop({ 1, Kit.WALL_HEIGHT, ROAD }, { 28, 3 + Kit.WALL_HEIGHT / 2, LEFT }, "gate", {
					motion = { kind = "flip", duty = 0.5 },
					beat = 13,
				})
			)
			table.insert(parts, blob(44, LEFT, 1.5, ROAD, SWEEP.medium, 0))
			local fast = lay(x0, x1, 2, 6, 6, 6)
			for i, p in fast do
				table.insert(parts, slab(p[1], p[2], 0, RIGHT, ROAD, "goo", fastFirst(i)))
				table.insert(parts, blob((p[1] + p[2]) / 2, RIGHT, 0, ROAD, SWEEP.medium, (i - 1) / 2))
			end
			divider(parts, x0, x1, -1, 12)
			exit(parts, length, 0)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Both roads in plain sight, but a faint sparkle under the safe road's hill marks a see-through ledge that
		-- cuts straight under it: drop in before the hill, duck past one goo sweeper, one jump up at the end. The
		-- hill has a sweeper on top; the fast road runs past three.
		name = "Secret Ledge",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 70
			local x0, x1 = ENTRY, length - EXIT
			local parts = {}
			entry(parts)
			stairs(parts, 12, 56, { 3, 6, 9, 6, 3 }, LEFT, ROAD, SAFE)
			table.insert(parts, blob(34, LEFT, 9, ROAD, SWEEP.medium, 0.5))
			table.insert(parts, slab(x0, 57.5, -3.5, -7, PAD, "pipe", { route = "secret", marker = "star" }))
			table.insert(parts, blob(34, -7, -3.5, PAD, SWEEP.medium, 0))
			local fast = slab(14, 56, 0, RIGHT, ROAD, "goo", { route = "fast", marker = FAST.marker })
			table.insert(parts, fast)
			table.insert(parts, blob(23, RIGHT, 0, ROAD, SWEEP.medium, 0))
			table.insert(parts, blob(35, RIGHT, 0, ROAD, SWEEP.medium, 1 / 3))
			table.insert(parts, blob(47, RIGHT, 0, ROAD, SWEEP.medium, 2 / 3))
			divider(parts, x0, x1, -5, 16)
			exit(parts, length, 0)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Three roads like terraces at the fork: the higher you climb, the fewer but longer the jumps (the top road's
		-- middle pad blinks, the middle road's slides, the bottom road has a goo sweeper). Fall off a high road's
		-- inner edge and you land one road lower.
		name = "Three Floors",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length, rise = 80, 3.5
			local parts = {}
			entry(parts)
			-- middle (main), z -4..4: four 5-stud gaps
			for i, p in lay(8, 72, 5, 5, 0, 0) do
				local extra: { [string]: any } = { tone = 2 }
				if i == 1 then
					extra.marker = "sign:MIDDLE"
				elseif i == 3 then
					extra.motion = { kind = "slide", axis = "x", amp = 1.5, period = 2.6 }
				end
				table.insert(parts, slab(p[1], p[2], 3.5, 0, PAD, "jelly", extra))
			end
			-- bottom, z -12..-4: seven 3-stud hops that climb and drop 2
			for i, p in lay(8, 72, 7, 3, 3, 0) do
				local extra: { [string]: any } = { route = "bottom", tone = 1 }
				if i == 1 then
					extra.marker = "sign:SAFE"
				end
				local top = if i % 2 == 1 then 2 else 0
				table.insert(parts, slab(p[1], p[2], top, -8, PAD, "jelly", extra))
				if i == 4 then
					table.insert(parts, blob((p[1] + p[2]) / 2, -8, top, PAD, SWEEP.medium, 0))
				end
			end
			-- top, z 4..12: a stair, then two 6-stud gaps
			table.insert(parts, slab(8, 13, 3.5, 8, PAD, "jelly", { route = "top", tone = 3, marker = FAST.marker }))
			table.insert(parts, slab(13, 29, 7, 8, PAD, "jelly", { route = "top", tone = 3 }))
			table.insert(
				parts,
				slab(
					35,
					43,
					7,
					8,
					PAD,
					"glow",
					{ route = "top", motion = { kind = "flip", duty = 0.55, period = 2.6 } }
				)
			)
			table.insert(parts, slab(49, 72, 7, 8, PAD, "jelly", { route = "top", tone = 3 }))
			exit(parts, length, rise)
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- Wait or walk: the short right road is three blinking pads you wait on; the left road is six small pads
		-- that slide back and forth together, so you never stop, but take more jumps.
		name = "Wait or Walk",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 70
			local x0, x1 = ENTRY, length - EXIT
			local parts = {}
			entry(parts)
			for i, p in lay(x0, x1, 6, 4.2, 4.2, 4.2) do
				local extra: { [string]: any } = {
					tone = i % 3 + 1,
					motion = { kind = "slide", axis = "x", amp = 1, period = 2.6 },
				}
				if i == 1 then
					extra.marker = SAFE.marker
				end
				table.insert(parts, slab(p[1], p[2], 0, LEFT, PAD, "jelly", extra))
			end
			for i, p in lay(x0, x1, 3, 4.5, 4.5, 4.5) do
				table.insert(
					parts,
					slab(
						p[1],
						p[2],
						0,
						RIGHT,
						ROAD,
						"glow",
						fastFirst(i, {
							motion = { kind = "flip", duty = 0.7, period = 2.6, phase = (i - 1) / 3 },
						})
					)
				)
			end
			divider(parts, x0, x1, -1, 12)
			exit(parts, length, 0)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- The road splits twice: pick a road, meet on a wide join pad, pick again. Four ways through.
		name = "Two Forks",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length, rise = 94, 4
			local parts = {}
			entry(parts)
			-- One half: four climbing hops (three pads, the middle one swept by goo) on the left (`safe`), one long pad
			-- with a 6-stud gap at each end on the right (`fast`). The caller orders them so the steps next to each
			-- fast pad read in walking order.
			local function half(
				x0: number,
				x1: number,
				from: number,
				fastTop: number,
				route: string
			): ({ Part }, { Part })
				local tops = { 1.5, 3, 4.5 }
				local safe = {}
				for i, p in lay(x0, x1, 3, 2.5, 2.5, 2.5) do
					table.insert(
						safe,
						slab(
							p[1],
							p[2],
							from + tops[i],
							LEFT,
							ROAD,
							"jelly",
							if i == 1 then SAFE else { tone = i % 3 + 1 }
						)
					)
					if i == 2 then
						table.insert(
							safe,
							blob(
								(p[1] + p[2]) / 2,
								LEFT,
								from + tops[i],
								ROAD,
								SWEEP.medium,
								if from > 0 then 0.5 else 0
							)
						)
					end
				end
				local f = lay(x0, x1, 1, 0, 6, 6)[1]
				local extra: { [string]: any } = { route = route, marker = FAST.marker }
				if route == "fast2" then
					extra.motion = { kind = "slide", axis = "x", amp = 1.5, period = 3 }
				end
				local fast = { slab(f[1], f[2], fastTop, RIGHT, ROAD, "goo", extra) }
				if route == "fast1" then
					table.insert(fast, blob((f[1] + f[2]) / 2, RIGHT, fastTop, ROAD, SWEEP.medium, 0))
				end
				divider(parts, x0, x1, from - 2, from + 14)
				return safe, fast
			end
			local function add(list: { Part })
				table.move(list, 1, #list, #parts + 1, parts)
			end
			local safe1, fast1 = half(8, 42, 0, 1, "fast1")
			local safe2, fast2 = half(52, 86, 2, 3, "fast2")
			add(safe1)
			table.insert(parts, slab(42, 52, 2, 0, Kit.WIDTH, "jelly", { tone = 2 }))
			add(fast1)
			add(safe2)
			add(fast2)
			exit(parts, length, rise)
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- The safe road goes up and over a hill whose top tread blinks away; the fast road ducks under a low roof,
		-- where a jump carries less far, over five tight gaps on and off a pad that slides back and forth.
		name = "Low Roof",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 70
			local x0, x1 = ENTRY, length - EXIT
			local parts = {}
			entry(parts)
			stairs(parts, x0, x1, { 3, 6, 9, 12, 9, 6, 3 }, LEFT, ROAD, SAFE)
			-- The hill's top tread blinks (a goo sweeper here would close the roofed road in the fairness runner).
			local peak = parts[#parts - 3]
			peak.look = "glow"
			peak.motion = { kind = "flip", duty = 0.6, period = 2.6 }
			for i, p in lay(x0, x1, 4, 4.4, 4.4, 4.4) do
				local extra = fastFirst(i, { tone = 2 })
				if i == 3 then
					extra.motion = { kind = "slide", axis = "x", amp = 1, period = 2.6 }
					extra.marker = "ghostStop"
				end
				table.insert(parts, slab(p[1], p[2], 0, RIGHT, PAD, "goo", extra))
			end
			-- The roof: its bottom 10.5 over the floor, so a jump under it carries about 6 studs, not 8.7.
			table.insert(parts, Kit.prop({ x1 - x0, 1, ROAD }, { (x0 + x1) / 2, 11, RIGHT }, "jelly", { tone = 3 }))
			divider(parts, x0, x1, -1, 22)
			exit(parts, length, 0)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- The short road is a yellow speed strip (past a goo sweeper) and one 11-stud gap you only clear at
		-- speed; the long road winds round on six climbing pads, one swept by goo.
		name = "Boost Gap",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 70
			local x0, x1 = ENTRY, length - EXIT
			local parts = {}
			entry(parts)
			local tops = { 1.5, 3, 1.5, 3, 1.5, 3 }
			local bends = { -1.5, 0, 1.5, 1.5, 0, -1.5 }
			for i, p in lay(x0, x1, 6, 3, 3, 3) do
				table.insert(
					parts,
					slab(
						p[1],
						p[2],
						tops[i],
						LEFT + bends[i],
						PAD,
						"jelly",
						if i == 1 then SAFE else { tone = i % 3 + 1 }
					)
				)
				if i == 3 then
					table.insert(parts, blob((p[1] + p[2]) / 2, LEFT + bends[i], tops[i], PAD, SWEEP.medium, 0.5))
				end
			end
			table.insert(
				parts,
				slab(
					x0,
					32,
					0,
					RIGHT,
					ROAD,
					"boost",
					{ route = "fast", boost = { speed = 30, carry = 0.5 }, marker = "chevrons" }
				)
			)
			table.insert(parts, blob(21, RIGHT, 0, ROAD, SWEEP.medium, 0))
			table.insert(parts, slab(43, x1, 0, RIGHT, ROAD, "goo", { route = "fast", marker = FAST.marker }))
			divider(parts, x0, x1, -1, 12)
			exit(parts, length, 0)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- The short road hops small islands across a red goo pool with 6-stud jumps (one slides back and forth, one
		-- side to side, one blinks); the long road is a dry side ledge over a wall of steps with two goo sweepers.
		name = "Island Hop or Ledge",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local length = 76
			local x0, x1 = ENTRY, length - EXIT
			local parts = {}
			entry(parts)
			stairs(parts, x0, x1, { 3, 6, 9, 12, 12, 9, 6, 3 }, -7, PAD, SAFE)
			local tread = (x1 - x0) / 8
			table.insert(parts, blob(x0 + tread * 4, -7, 12, PAD, SWEEP.hard, 0))
			table.insert(parts, blob(x0 + tread * 5.5, -7, 9, PAD, SWEEP.hard, 0.7))
			for i, p in lay(x0, x1, 4, 6, 6, 6) do
				local extra = fastFirst(i, { tone = 2 })
				if i == 2 then
					extra.motion = { kind = "slide", axis = "x", amp = 1, period = 2.4 }
					extra.marker = "ghostStop"
				elseif i == 4 then
					extra.motion = { kind = "slide", axis = "z", amp = 1.5, period = 2.4, phase = 0.5 }
				elseif i == 3 then
					extra.motion = { kind = "flip", duty = 0.6, period = 2.4 }
				end
				table.insert(parts, slab(p[1], p[2], 0, RIGHT, PAD, if i == 3 then "glow" else "goo", extra))
			end
			table.insert(parts, pool(x0, x1, -0.5, RIGHT, ROAD))
			divider(parts, x0, x1, -3, 23)
			exit(parts, length, 0)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Neither road is easy: the safe road climbs and drops 3 studs over 4-stud gaps past two goo sweepers; the
		-- fast road is three 3-wide beams with 6-stud jumps and red goo posts that wait beside the beam, then dash
		-- across it.
		name = "Knife Edge",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local length = 80
			local x0, x1 = ENTRY, length - EXIT
			local parts = {}
			entry(parts)
			local tops = { 3, 6, 3, 6, 3, 6 }
			for i, p in lay(x0, x1, 6, 4, 4, 4) do
				table.insert(
					parts,
					slab(p[1], p[2], tops[i], LEFT, PAD, "jelly", if i == 1 then SAFE else { tone = i % 3 + 1 })
				)
				-- Two goo sweepers, each where the fast road under the same stretch is a beam, not a hole (the
				-- shared fairness runner can't follow a road through a stretch where both roads have holes).
				if i == 2 or i == 4 then
					table.insert(parts, blob(p[1] + 1.5, LEFT, tops[i], PAD, SWEEP.hard, if i == 4 then 0.5 else 0))
				end
			end
			for i, p in lay(x0, x1, 3, 6, 6, 6) do
				table.insert(parts, slab(p[1], p[2], 0, RIGHT, 3, "beam", fastFirst(i)))
				local long = p[2] - p[1]
				for k = 1, 2 do
					table.insert(parts, post(p[1] + long * k / 3, RIGHT, 0, 0.9, 2.6, (i - 1) / 3))
				end
			end
			divider(parts, x0, x1, -1, 15)
			exit(parts, length, 0)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Step into the section and the safe road's door starts its countdown: dawdle at the fork and it drops shut,
		-- and only the hard road (6-stud jumps, sliding pads, a goo sweeper) is left.
		name = "Door Behind You",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local length = 70
			local x0, x1 = ENTRY, length - EXIT
			local parts = {}
			entry(parts, { trigger = "door" })
			local safe = lay(x0, x1, 7, 2.5, 2.5, 2.5)
			local tops = { 2, 4, 2, 4, 2, 4, 2 }
			for i, p in safe do
				table.insert(
					parts,
					slab(
						p[1],
						p[2],
						tops[i],
						LEFT,
						ROAD,
						"jelly",
						if i == 1 then { marker = "sign:DOOR 4s" } else { tone = i % 3 + 1 }
					)
				)
			end
			-- The door hangs over the fourth safe pad and drops shut for good 3.6 s after you step in.
			local dx = (safe[4][1] + safe[4][2]) / 2
			local doorTall, doorLift = 11, 13 -- at rest its bottom hangs 13 over the pad: above a jumping head
			table.insert(
				parts,
				Kit.prop({ 1, doorTall, ROAD }, { dx, tops[4] + doorLift + doorTall / 2, LEFT }, "gate", {
					start = "door",
					motion = {
						kind = "path",
						points = { { 0, 0, 0 }, { 0, -doorLift, 0 } },
						once = true,
						hold = 3.6,
						period = 4.2,
					},
				})
			)
			for i, p in lay(x0, x1, 4, 6, 6, 6) do
				local extra = fastFirst(i, { tone = 2 })
				if i == 2 or i == 4 then
					extra.motion =
						{ kind = "slide", axis = "z", amp = 1.5, period = 2.4, phase = if i == 4 then 0.5 else 0 }
				end
				table.insert(parts, slab(p[1], p[2], 0, RIGHT, PAD, "goo", extra))
				if i == 3 then
					table.insert(parts, blob((p[1] + p[2]) / 2, RIGHT, 0, PAD, SWEEP.hard, 0))
				end
			end
			divider(parts, x0, x1, -1, 28)
			exit(parts, length, 0)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- One hard high road of 6-stud jumps. Its second tile is cracked and darkening: stand on it and it drops
		-- away onto a secret beam below that skips the last two jumps (past two goo posts sliding across it). The
		-- third pad slides back and forth; the last has a goo sweeper.
		name = "Cracked Shortcut",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local length = 80
			local high = 2.5
			local parts = {}
			entry(parts)
			local pads = lay(ENTRY, length - EXIT, 4, 6, 6, 6)
			for i, p in pads do
				local extra: { [string]: any } = { tone = i % 3 + 1 }
				local z = 3.5
				if i == 2 then
					z = -1
					extra.motion = { kind = "melt", delay = 0.8, away = -1 }
					extra.marker = "cracks"
				elseif i == 3 then
					extra.motion = { kind = "slide", axis = "x", amp = 1, period = 2.4 }
				end
				table.insert(parts, slab(p[1], p[2], high, z, PAD, if i == 2 then "tile" else "jelly", extra))
				if i == 4 then
					table.insert(parts, blob((p[1] + p[2]) / 2, z, high, PAD, SWEEP.hard, 0))
				end
			end
			local beamFrom = pads[2][1] + 1
			table.insert(
				parts,
				slab(beamFrom, length - EXIT, high - 5, -3.5, 3, "beam", { route = "secret", marker = "rail" })
			)
			for k = 1, 2 do
				local x = beamFrom + (length - EXIT - beamFrom) * k / 3
				table.insert(
					parts,
					Kit.hazard({ 1.5, 4, 1.5 }, { x, high - 5 + 2, -3.5 }, {
						motion = { kind = "slide", axis = "z", amp = 2, period = 2, phase = (k - 1) / 2 },
					})
				)
			end
			exit(parts, length, 0)
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Three terraced roads, all hard in their own way: the bottom has the most jumps (climbing and dropping 3,
		-- past a goo sweeper), the middle blinks and slides, the top has the fewest but longest jumps, over goo and
		-- past a goo sweeper.
		name = "Three Roads, No Easy One",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local length, rise = 90, 3.5
			local x0, x1 = ENTRY, length - EXIT
			local parts = {}
			entry(parts)
			-- middle (main), z -4..4: four 5.5-stud gaps
			for i, p in lay(x0, x1, 5, 5.5, 0, 0) do
				local extra: { [string]: any } = { tone = 2 }
				if i == 1 then
					extra.marker = "sign:MIDDLE"
				elseif i == 3 then
					extra.motion = { kind = "flip", duty = 0.6, period = 2.2 }
				elseif i == 4 then
					extra.motion = { kind = "slide", axis = "x", amp = 1, period = 2.6 }
				end
				table.insert(parts, slab(p[1], p[2], 3.5, 0, PAD, if i == 3 then "glow" else "jelly", extra))
			end
			-- bottom, z -12..-4: six 4-stud gaps, climbing and dropping 3
			local tops = { 3, 0.5, 3.5, 0.5, 3.5, 0.5 }
			for i, p in lay(x0, x1, 6, 4, 4, 0) do
				local extra: { [string]: any } = { route = "bottom", tone = 1 }
				if i == 1 then
					extra.marker = "sign:LOW"
				elseif i == 3 then
					extra.motion = { kind = "slide", axis = "x", amp = 1, period = 2.2 }
				end
				table.insert(parts, slab(p[1], p[2], tops[i], -8, PAD, "jelly", extra))
				if i == 5 then
					table.insert(parts, blob((p[1] + p[2]) / 2, -8, tops[i], PAD, SWEEP.hard, 0))
				end
			end
			-- top, z 4..12: a stair, then two 6-stud gaps over goo
			table.insert(parts, slab(8, 13, 3.5, 8, PAD, "jelly", { route = "top", tone = 3, marker = "sign:HIGH" }))
			table.insert(parts, slab(13, 31, 7, 8, PAD, "jelly", { route = "top", tone = 3 }))
			table.insert(
				parts,
				slab(37, 45, 7, 8, PAD, "jelly", {
					route = "top",
					tone = 1,
					motion = { kind = "slide", axis = "x", amp = 1.5, period = 2.4 },
				})
			)
			table.insert(parts, slab(51, x1, 7, 8, PAD, "jelly", { route = "top", tone = 3 }))
			table.insert(parts, pool(31, 37, 4, 8, PAD))
			table.insert(parts, pool(45, 51, 4, 8, PAD))
			table.insert(parts, blob(66, 8, 7, PAD, SWEEP.hard, 0))
			exit(parts, length, rise)
			return Kit.section(length, rise, parts)
		end,
	},
}

return M
