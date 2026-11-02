--!strict
--[[
	Vine Swing (obby idea 15, docs/obby-variants/15.json; contract/obby-sections.md)

	The feel (Merijn, 2026-11-01: "they are not fun"; reworked like a classic platformer rope swing): run or jump
	into a rope's green goo knob and you grab it, nothing to aim at. You swing on a real pendulum that keeps the run
	you came in with; hold the way you swing to pump it higher; jump to let go and you fly off with the swing's speed
	along its arc plus a small hop, a few dots showing the start of that flight (mint when it lands you safe). A
	chain of ropes flows: fly into the next knob and the swing carries on. The physics is src/shared/ObbySections/
	Vine, shared by ObbyMoves' vine controller and the checks.

	Every rope is a real pendulum (Kit `swing`, axis "x" along the course or across it), hanging from a pivot post
	`arm` studs over its knob's centre and swinging gently on server time until someone grabs it (Vine.period(arm)).
	The knob (the `vine` step, handprints) hangs HANG studs over the pad level. The rope above it and the pivot post
	are ghost decor. The windows (one full swing at full pump, the time a let go lands) and the player / masher bots
	are in tests/obby/VineSwing.spec.
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")
local Vine = if script then require(script.Parent.Vine) else require("./Vine")

local KNOB = 1.8 -- the grab knob (a ball) at the rope's end: the vine step
local HANG = 6 -- studs from a pad's top up to the bottom of the knob over it, at rest
local PIT = -4 -- top of the red goo pit under every chain (above the fall reset, so you see it get you)
local ENTRY = 10 -- the entry pad's length
local SWAY = table.freeze({ easy = 4, medium = 4, hard = 4 }) -- degrees an idle rope swings each way

export type Rope = {
	x: number, -- the knob's rest x (bottom of the swing)
	z: number?,
	ends: number?, -- the knob's bottom at rest (HANG by default)
	arm: number, -- pivot to knob centre
	tier: string,
	phase: number?,
	across: boolean?, -- swings across the lane (z) instead of along it
}

-- One rope: the knob (the vine step), the rope above it and the post it hangs from.
local function rope(parts: { Kit.Part }, r: Rope)
	local z = r.z or 0
	local ends = r.ends or HANG
	local axis = if r.across then nil else "x"
	local period = Vine.period(r.arm)
	table.insert(
		parts,
		Kit.prop({ KNOB, KNOB, KNOB }, { r.x, ends + KNOB / 2, z }, "blob", {
			shape = "ball",
			step = true,
			vine = { reach = Vine.REACH[r.tier], hint = Vine.HINT[r.tier] },
			motion = { kind = "swing", axis = axis, amp = SWAY[r.tier], arm = r.arm, period = period, phase = r.phase },
			marker = "handprints",
		})
	)
	local long = r.arm - KNOB / 2 -- knob top to the pivot
	local top = ends + KNOB + long -- the pivot's height
	table.insert(
		parts,
		Kit.prop({ 0.6, long, 0.6 }, { r.x, top - long / 2, z }, "goo", {
			ghost = true,
			motion = {
				kind = "swing",
				axis = axis,
				amp = SWAY[r.tier],
				arm = long / 2,
				period = period,
				phase = r.phase,
			},
		})
	)
	table.insert(parts, Kit.prop({ 1.6, 1.2, 1.6 }, { r.x, top + 0.6, z }, "post", { ghost = true }))
end

-- A pad from x0 to x1 with its top at `top`, `wide` across (default the lane), centred on z.
local function pad(
	parts: { Kit.Part },
	x0: number,
	x1: number,
	top: number,
	wide: number?,
	z: number?,
	extra: { [string]: any }?
)
	table.insert(parts, Kit.slab((x0 + x1) / 2, top, z or 0, x1 - x0, wide or Kit.WIDTH, "jelly", extra))
end

-- The entry pad (x 0..ENTRY, top 0).
local function entry(parts: { Kit.Part }, extra: { [string]: any }?)
	local e: { [string]: any } = { tone = 1 }
	for k, v in (extra or {}) :: { [string]: any } do
		e[k] = v
	end
	pad(parts, 0, ENTRY, 0, nil, nil, e)
end

-- The red goo pit from x0 to x1 (the whole lane), its top `top` (PIT by default).
local function pit(parts: { Kit.Part }, x0: number, x1: number, top: number?)
	local t = top or PIT
	table.insert(parts, Kit.hazard({ x1 - x0, 2, Kit.WIDTH }, { (x0 + x1) / 2, t - 1, 0 }))
end

-- Red goo strips flush with a pad's top all round it (x0..x1, z0..z1), `w` wide: miss the pad, land in goo.
local function ring(parts: { Kit.Part }, x0: number, x1: number, z0: number, z1: number, top: number, w: number)
	local y = top - 0.05 - 0.5
	local zc = (z0 + z1) / 2
	table.insert(parts, Kit.hazard({ w, 1, z1 - z0 + 2 * w }, { x0 - w / 2, y, zc }))
	table.insert(parts, Kit.hazard({ w, 1, z1 - z0 + 2 * w }, { x1 + w / 2, y, zc }))
	table.insert(parts, Kit.hazard({ x1 - x0, 1, w }, { (x0 + x1) / 2, y, z0 - w / 2 }))
	table.insert(parts, Kit.hazard({ x1 - x0, 1, w }, { (x0 + x1) / 2, y, z1 + w / 2 }))
end

-- Along-course ropes at `xs` (the same arm), phases taken in turn from `phases`.
local function ropes(parts: { Kit.Part }, tier: string, xs: { number }, arm: number, phases: { number }?)
	local ph = phases or { 0, 0.5 }
	for i, x in xs do
		rope(parts, { x = x, arm = arm, tier = tier, phase = ph[(i - 1) % #ph + 1] })
	end
end

local M = {}
M.id = "VineSwing"
M.name = "Vine Swing"
M.idea = 15

M.variants = {
	{
		-- One rope over a short goo pit onto a wide pad: it teaches the whole move.
		name = "First Swing",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			pit(parts, ENTRY, 24)
			ropes(parts, "easy", { 16 }, 7)
			local length = 36
			pad(parts, 24, length, 0, 16, nil, { tone = 2 })
			return Kit.section(length, 0, parts)
		end,
	},

	{
		-- Two ropes: fly from the first straight into the second, the swing carries on.
		name = "Two Vine Hop",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			pit(parts, ENTRY, 36)
			ropes(parts, "easy", { 16, 28 }, 7)
			local length = 48
			pad(parts, 36, length, 0, 16, nil, { tone = 2 })
			return Kit.section(length, 0, parts)
		end,
	},

	{
		-- Rope, a wide island to land and breathe, then a second rope: each swing is a fresh start.
		name = "Rest Island",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			pit(parts, ENTRY, 24)
			ropes(parts, "easy", { 16 }, 7)
			pad(parts, 24, 34, 0, 12, nil, { tone = 2 })
			pit(parts, 34, 48)
			ropes(parts, "easy", { 40 }, 7, { 0.5 })
			local length = 60
			pad(parts, 48, length, 0, nil, nil, { tone = 3 })
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- One long rope and a long pit: pump it up and let go high to sail across.
		name = "Long Lazy Vine",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			pit(parts, ENTRY, 30)
			ropes(parts, "easy", { 17 }, 11)
			local length = 42
			pad(parts, 30, length, 0, 14, nil, { tone = 2 })
			return Kit.section(length, 0, parts)
		end,
	},

	{
		-- Each rope hangs 3 studs lower than the last: the drops make every hand-over forgiving.
		name = "Swing Down",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local drop = 3
			local rise = -2 * drop
			local exit = 46
			pit(parts, ENTRY, exit, rise + PIT)
			for i, x in { 16, 27, 38 } do
				rope(parts, { x = x, ends = HANG - (i - 1) * drop, arm = 7, tier = "easy", phase = (i - 1) * 0.5 })
			end
			local length = 58
			pad(parts, exit, length, rise, nil, nil, { tone = 2 })
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- The ropes swing across the lane: hold left / right to pump, let go onto a pad at the lane's other edge.
		name = "Side Swing",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			-- the entry pad and the side pads hug opposite lane edges, too far apart to jump: only a rope gets you over
			pad(parts, 0, ENTRY, 0, 8, -8, { tone = 1 })
			rope(parts, { x = 15, arm = 7, tier = "easy", across = true })
			pad(parts, 12, 20, 0, 8, 8, { tone = 2 })
			rope(parts, { x = 27, arm = 7, tier = "easy", phase = 0.5, across = true })
			pad(parts, 24, 32, 0, 8, -8, { tone = 2 })
			-- no goo pit here: the side hops would read as unfair to the hazard runner; you fall and reset
			local length = 46
			pad(parts, 36, length, 0, nil, nil, { tone = 3 })
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Three ropes back to back: keep the swing going rope to rope.
		name = "Three Vine Chain",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			pit(parts, ENTRY, 53.5)
			ropes(parts, "medium", { 17, 30.5, 44 }, 7)
			local length = 63.5
			pad(parts, 53.5, length, 0, nil, nil, { tone = 2 })
			return Kit.section(length, 0, parts)
		end,
	},

	{
		-- Short, quick ropes: the moment to let go comes fast and often.
		name = "Quick Vines",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			pit(parts, ENTRY, 56.5)
			ropes(parts, "medium", { 16, 27, 38, 49 }, 5)
			local length = 66.5
			pad(parts, 56.5, length, 0, nil, nil, { tone = 2 })
			return Kit.section(length, 0, parts)
		end,
	},

	{
		-- A small pad between two ropes, framed by red goo: let go too early or too late and you land in goo.
		name = "Narrow Landing",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			pit(parts, ENTRY, 50.5)
			ropes(parts, "medium", { 17 }, 7)
			pad(parts, 26, 34, 0, 8, nil, { tone = 2 })
			ring(parts, 26, 34, -4, 4, 0, 3)
			ropes(parts, "medium", { 41 }, 7, { 0.5 })
			local length = 60.5
			pad(parts, 50.5, length, 0, nil, nil, { tone = 3 })
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Each rope hangs higher than the last: pump and let go on the upswing to gain height.
		name = "Vine Climb",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local climb = 2.5
			local exit = 56
			pit(parts, ENTRY, exit)
			for i, x in { 17, 31.5, 46 } do
				rope(parts, { x = x, ends = HANG + (i - 1) * climb, arm = 8, tier = "medium", phase = (i - 1) * 0.5 })
			end
			local rise = 2 * climb
			local length = 66
			pad(parts, exit, length, rise, nil, nil, { tone = 2 })
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- A red goo bar hangs between two ropes: let go high to fly over it instead of through it.
		name = "Over the Goo Bar",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local exit = 44
			pit(parts, ENTRY, exit)
			ropes(parts, "medium", { 17, 33 }, 9)
			-- 3 tall, its top 3.5 under the knobs' bottom: a low, flat let go runs into it
			table.insert(parts, Kit.hazard({ 2, 3, 16 }, { 25, HANG - 5, 0 }))
			local length = 54
			pad(parts, exit, length, 0, nil, nil, { tone = 2 })
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- A red goo bar rides up and down between two ropes: let go over it when it is low, under it when high.
		name = "Goo Sweeper",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local exit = 42
			pit(parts, ENTRY, exit)
			ropes(parts, "medium", { 17, 32 }, 8)
			table.insert(
				parts,
				Kit.hazard({ 2, 3, 16 }, { 24.5, HANG - 3, 0 }, {
					motion = { kind = "slide", axis = "y", amp = 4, period = 3.6 },
				})
			)
			local length = 52
			pad(parts, exit, length, 0, nil, nil, { tone = 2 })
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- The last rope throws you at a goo ladder on a high wall: let go on the upswing, climb out the top.
		name = "Vine to Ladder",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local wallAt = 44.5
			pit(parts, ENTRY, wallAt - 2)
			ropes(parts, "medium", { 17, 30.5 }, 7)
			local rise = HANG + 4
			local bottom = HANG - 4
			table.insert(
				parts,
				Kit.prop({ 2, rise - bottom, 10 }, { wallAt - 1, (bottom + rise) / 2, 0 }, "goo", {
					shape = "truss",
					step = true,
					marker = "handprints",
				})
			)
			local length = 54.5
			local deep = rise - PIT
			table.insert(
				parts,
				Kit.prop({ length - wallAt, deep, Kit.WIDTH }, { (wallAt + length) / 2, rise - deep / 2, 0 }, "jelly", {
					step = true,
					tone = 2,
				})
			)
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- Five ropes over red goo and no rest: keep the rhythm or start over.
		name = "Five Vine Run",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			pit(parts, ENTRY, 82)
			ropes(parts, "hard", { 17, 30.75, 44.5, 58.25, 72 }, 7)
			local length = 92
			pad(parts, 82, length, 0, nil, nil, { tone = 2 })
			return Kit.section(length, 0, parts)
		end,
	},

	{
		-- Four ropes of different lengths: every swing has its own beat.
		name = "Drifting Beat",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local exit = 66.75
			pit(parts, ENTRY, exit)
			local arms = { 6, 9, 5, 8 }
			for i, x in { 16, 28.5, 44.5, 55.75 } do
				rope(parts, { x = x, arm = arms[i], tier = "hard", phase = (i - 1) * 0.3 })
			end
			local length = 76.75
			pad(parts, exit, length, 0, nil, nil, { tone = 2 })
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Three ropes end over a small, low pad ringed by red goo: let go early and drop onto it.
		name = "Pinpoint Drop",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local low = -2
			pit(parts, ENTRY, 65.5, low + PIT)
			for i, x in { 17, 30.75, 44.5 } do
				rope(parts, { x = x, ends = low + HANG, arm = 7, tier = "hard", phase = (i - 1) * 0.5 })
			end
			pad(parts, 54.5, 60.5, low, 8, nil, { tone = 2 })
			ring(parts, 54.5, 60.5, -4, 4, low, 3)
			local length = 75.5
			pad(parts, 65.5, length, low, nil, nil, { tone = 3 })
			return Kit.section(length, low, parts)
		end,
	},
	{
		-- Two quick ropes, then one long rope over a wide pit: pump it all the way up for the big throw.
		name = "Long Swing Finale",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local exit = 59
			pit(parts, ENTRY, exit)
			ropes(parts, "hard", { 17, 29.5 }, 6)
			rope(parts, { x = 42, arm = 13, tier = "hard", phase = 0.25 })
			local length = 69
			pad(parts, exit, length, 0, nil, nil, { tone = 2 })
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Red goo floods up under the ropes from the moment you step on: no time to wait for a perfect swing.
		name = "Snapping Vine",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts, { trigger = "snap" })
			local exit = 68.25
			ropes(parts, "hard", { 17, 30.75, 44.5, 58.25 }, 7)
			-- the flood: from the pit up to a hanging player's feet (tests/obby/VineSwing.spec times it against the
			-- player bot's slowest run)
			local feet = HANG + KNOB / 2 - Vine.GRIP - Vine.FEET
			local stop = feet - PIT
			table.insert(
				parts,
				Kit.hazard({ exit - ENTRY - 1, 2, Kit.WIDTH }, { (ENTRY + exit) / 2, PIT - 1, 0 }, {
					motion = { kind = "rise", speed = 1.15, delay = 2, stop = stop },
					start = "snap",
				})
			)
			local length = 78.25
			pad(parts, exit, length, 0, nil, nil, { tone = 2 })
			return Kit.section(length, 0, parts)
		end,
	},
}

return M
