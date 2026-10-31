--!strict
--[[
	Speed Strip (obby idea 16, docs/obby-variants/16.json; contract/obby-sections.md)

	Yellow boost strips with chevrons make you fast (`boost`), and the gap after them is too long to clear at walking
	speed: run the strip, leap the gap. Dusky back strips (chevrons pointing at you) slow you down. Every variant also
	has a red goo hazard or a moving part, so no section is only "run and jump" (contract §10).

	Numbers against the checks (tests/ObbyCheck): a jump off a boost strip may span GAP_MAX x speed / 16, so a gap of
	`g` studs needs a boost of at least g x 16 / 6 (11 -> 30, 12 -> 32, 12.5 -> 34, 13 -> 35). Each boosted gap is over
	the 8.7 studs a walking jump reaches, so it needs the boost. Holes between boosted floors are at least 6 studs: a
	walker at 32 studs / s steps over holes up to about 5.

	Boost carry: in the game a boost eases back to 16 over 0.3 s once its `carry` runs out, also in the air, so every
	strip you leap from carries its speed for FLIGHT s (a boosted leap is in the air about 0.55 s).

	Hand-made only: the design file has no generator (each gap is checked against its own boost).
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

local FLIGHT = 0.8 -- seconds a forward strip keeps your speed after you leave it: a whole leap
local BACK_SPEED = 10 -- a back strip slows you to this
local BACK_PUSH = 4 -- and pushes back this hard (studs / s), which also points its chevrons at you
local SWEEP_LONG = 2 -- a sweeper block along the course
local SWEEP_TALL = 4 -- and its height over the floor
-- Sweeper periods per tier (a 10-wide block, amp 5, on a 12-wide strip leaves ~0.43 x period open; contract §10)
local EASY = 3.4 -- about 1.45 s
local MEDIUM = 2.6 -- about 1.05 s
local HARD = 2.1 -- about 0.8 s
local CRUSH = 2.4 -- Left, Right, Leap's crusher (about 0.8 s)

local function plain(x0: number, x1: number, top: number, z: number, wide: number, tone: number?): Kit.Part
	return Kit.slab((x0 + x1) / 2, top, z, x1 - x0, wide, "jelly", { tone = tone or 1 })
end

-- A forward strip from x0 to x1: yellow, chevrons, `speed` while you stand on it.
local function strip(
	x0: number,
	x1: number,
	top: number,
	z: number,
	wide: number,
	speed: number,
	extra: { [string]: any }?
): Kit.Part
	local part = Kit.slab((x0 + x1) / 2, top, z, x1 - x0, wide, "boost", {
		boost = { speed = speed, carry = FLIGHT },
		marker = "chevrons",
	})
	for k, v in (extra or {}) :: { [string]: any } do
		(part :: any)[k] = v
	end
	return part
end

-- A back strip: dusky (ObbyParts tone 2 for a slow boost), slows you and pushes you back.
local function backStrip(x0: number, x1: number, top: number, z: number, wide: number): Kit.Part
	return Kit.slab((x0 + x1) / 2, top, z, x1 - x0, wide, "boost", {
		boost = { speed = BACK_SPEED, carry = 0 },
		conveyor = { -BACK_PUSH, 0, 0 },
		marker = "chevrons",
	})
end

-- A red goo block standing on a floor whose top is `top` at x, sliding across the course round z = zc.
local function sweeper(
	x: number,
	top: number,
	zc: number,
	wide: number,
	amp: number,
	period: number,
	phase: number?
): Kit.Part
	return Kit.hazard({ SWEEP_LONG, SWEEP_TALL, wide }, { x, top + SWEEP_TALL / 2, zc }, {
		motion = { kind = "slide", axis = "z", amp = amp, period = period, phase = phase or 0 },
	})
end

-- A still red goo post on a floor (steer round it).
local function post(x: number, top: number, z: number, wide: number): Kit.Part
	return Kit.hazard({ SWEEP_LONG, SWEEP_TALL, wide }, { x, top + SWEEP_TALL / 2, z })
end

-- A red goo bed filling a stretch of the lane at floor level (not solid: touching it is a reset).
local function gooBed(x0: number, x1: number, top: number, z0: number, z1: number): Kit.Part
	return Kit.hazard({ x1 - x0, 1, z1 - z0 }, { (x0 + x1) / 2, top - 0.3, (z0 + z1) / 2 })
end

local M = {}
M.id = "SpeedStrip"
M.name = "Speed Strip"
M.idea = 16

M.variants = {
	{
		-- One long strip, then one gap you can only clear with its speed. A red goo block slides across the strip:
		-- go round it or wait for it.
		name = "First Boost",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length = 53
			return Kit.section(length, 0, {
				plain(0, 6, 0, 0, Kit.WIDTH, 1),
				strip(6, 30, 0, 0, 12, 30),
				sweeper(18, 0, 0, 10, 5, EASY),
				plain(41, length, 0, 0, Kit.WIDTH, 3), -- gap 11, landing 12 deep
			})
		end,
	},
	{
		-- The strip runs down an 8 degree slope past two red goo posts that each cover more than half of it, so you
		-- weave right then left at speed (a slalom); the landing sits 3 lower.
		name = "Downhill Dash",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length = 52
			local drop = 2.8 -- 20 studs at 8 degrees
			local function rampTop(x: number): number
				return -drop * (x - 4) / 20
			end
			return Kit.section(length, -drop - 3, {
				plain(0, 4, 0, 0, Kit.WIDTH, 1),
				-- 33, not the draft's 30: the checks give a 12-stud gap only to a boost of 32 or more
				Kit.ramp(4, 0, 24, -drop, 0, 12, "boost", {
					boost = { speed = 33, carry = FLIGHT },
					marker = "chevrons",
				}),
				post(8, rampTop(8), -3, 6), -- covers the left half and the middle: pass right
				post(20, rampTop(20), 3, 6), -- then the right half: cross over to the left
				plain(36, length, -drop - 3, 0, Kit.WIDTH, 3), -- gap 12, 3 lower
			})
		end,
	},
	{
		-- The landing is 3 higher: boost, jump at the very edge and climb onto it. A red goo block sweeps the
		-- take-off end of the strip, so time the edge.
		name = "Up a Step",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length = 50.5
			return Kit.section(length, 3, {
				plain(0, 4, 0, 0, Kit.WIDTH, 1),
				strip(4, 26, 0, 0, 12, 30),
				sweeper(23, 0, 0, 10, 5, EASY),
				plain(36.5, length, 3, 0, Kit.WIDTH, 3), -- gap 10.5, +3
			})
		end,
	},
	{
		-- A wide floor with only a middle stripe of boost: wander off it and you arrive too slow. A red goo block
		-- slides right across the stripe and pushes you off it if you don't time it.
		name = "Stay in the Yellow",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length = 51
			local from, to = 4, 28
			return Kit.section(length, 0, {
				plain(0, from, 0, 0, Kit.WIDTH, 1),
				strip(from, to, 0, 0, 8, 30, { boost = { speed = 30, carry = 0.4 } }),
				-- the plain floor either side: you can run there, but at walking speed
				Kit.prop({ to - from, Kit.THICK, 8 }, { (from + to) / 2, -Kit.THICK / 2, -8 }, "jelly", { tone = 2 }),
				Kit.prop({ to - from, Kit.THICK, 8 }, { (from + to) / 2, -Kit.THICK / 2, 8 }, "jelly", { tone = 2 }),
				sweeper(18, 0, 0, 8, 8, 3.6),
				plain(39, length, 0, 0, Kit.WIDTH, 3), -- gap 11
			})
		end,
	},
	{
		-- Two strip-and-gap pairs in a row: a red goo block slides across the first strip, and the second (the
		-- landing of the first leap) has a red goo post in the middle to steer round at speed.
		name = "Two Hops",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length = 66
			return Kit.section(length, 0, {
				plain(0, 4, 0, 0, Kit.WIDTH, 1),
				strip(4, 20, 0, 0, 12, 30),
				sweeper(13, 0, 0, 10, 5, EASY),
				strip(30, 46, 0, 0, 12, 30), -- gap 10
				post(38, 0, 0, 5),
				plain(56, length, 0, 0, Kit.WIDTH, 3), -- gap 10
			})
		end,
	},
	{
		-- The longest leap of the easy tier, onto a big landing so a late jump still counts. Two red goo blocks sweep
		-- the long strip out of step with each other.
		name = "Wide Landing",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length = 64.5
			return Kit.section(length, 0, {
				plain(0, 4, 0, 0, Kit.WIDTH, 1),
				-- 34, not the draft's 30: a 12.5-stud gap needs 33.4 in the checks
				strip(4, 32, 0, 0, 12, 34),
				sweeper(13, 0, 0, 10, 5, EASY),
				sweeper(26, 0, 0, 10, 5, EASY, 0.5),
				plain(44.5, length, 0, 0, Kit.WIDTH, 3), -- gap 12.5, landing 20 deep
			})
		end,
	},
	{
		-- The first stretch is a back strip (slows you, pushes you back) with a red goo bump popping up across it:
		-- hop the whole strip to reach the real boost, then get past a red goo block sliding across the strip.
		name = "Backwash",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 49
			return Kit.section(length, 0, {
				plain(0, 4, 0, 0, Kit.WIDTH, 1),
				backStrip(4, 12, 0, 0, Kit.WIDTH),
				-- a red goo bump pops up across the back strip: hop the whole strip, or time the bump
				Kit.hazard({ 2, 1.5, Kit.WIDTH }, { 8, -1.25, 0 }, {
					motion = { kind = "punch", axis = "y", amp = 2, period = 2.9, phase = 0.5 },
				}),
				strip(12, 26, 0, 0, 12, 30),
				sweeper(20, 0, 0, 10, 5, MEDIUM),
				plain(37, length, 0, 0, Kit.WIDTH, 3), -- gap 11
			})
		end,
	},
	{
		-- Dodge a red goo block on the strip, then a small hop onto a short pad sliding side to side: land on it and
		-- go straight on, while the speed lasts.
		name = "Carry the Speed",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 54
			return Kit.section(length, 0, {
				plain(0, 4, 0, 0, Kit.WIDTH, 1),
				strip(4, 20, 0, 0, 12, 30, { boost = { speed = 30, carry = 1.5 } }),
				sweeper(12, 0, 0, 10, 5, MEDIUM),
				-- gap 6 (the draft's 5 is walked over at 30 studs / s); the pad tops your speed up (see engineGaps)
				strip(26, 32, 0, 0, 8, 30, {
					boost = { speed = 30, carry = 1.5 },
					motion = { kind = "slide", axis = "z", amp = 4, period = 2.2 },
				}),
				plain(43, length, 0, 0, Kit.WIDTH, 3), -- long gap 11
			})
		end,
	},
	{
		-- No long strip, just short boost pads with gaps; each one tops up your speed for the next. The last three
		-- slide side to side out of step, so every hop is aimed.
		name = "Stepping Boosts",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 72
			local function pad(x0: number, moves: boolean, phase: number): Kit.Part
				return strip(x0, x0 + 5, 0, 0, 10, 32, {
					boost = { speed = 32, carry = 1.2 },
					motion = if moves
						then { kind = "slide", axis = "z", amp = 4, period = 2.2, phase = phase }
						else nil,
				})
			end
			return Kit.section(length, 0, {
				plain(0, 4, 0, 0, Kit.WIDTH, 1),
				pad(9.5, false, 0), -- gap 5.5 from the start pad
				pad(20.5, true, 0), -- gaps 6: the draft's 5 is walked over at 32
				pad(31.5, true, 1 / 3),
				pad(42.5, true, 2 / 3),
				plain(59.5, length, 0, 0, Kit.WIDTH, 3), -- last gap 12
			})
		end,
	},
	{
		-- Red goo bumps pop up out of the strip and sink back: hop them or run through as they drop.
		name = "Hurdles",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 53
			local parts = {
				plain(0, 4, 0, 0, Kit.WIDTH, 1),
				strip(4, 30, 0, 0, 12, 30),
			}
			local period = 2.9
			for i, x in { 11, 18, 25 } do
				-- hidden 0.5 under the strip top at rest, 1.5 over it when up
				table.insert(
					parts,
					Kit.hazard({ 2, 1.5, 12 }, { x, -1.25, 0 }, {
						motion = {
							kind = "punch",
							axis = "y",
							amp = 2,
							period = period,
							phase = -((i - 1) * 7 / Kit.WALK) / period % 1,
						},
					})
				)
			end
			table.insert(parts, plain(41, length, 0, 0, Kit.WIDTH, 3)) -- gap 11
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- The strip is off to one side with a red goo block on it; leap onto a target sliding side to side, when it
		-- lines up with you.
		name = "Sliding Landing",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 62
			return Kit.section(length, 0, {
				plain(0, 4, 0, 0, Kit.WIDTH, 1),
				strip(4, 24, 0, -6, 10, 30),
				sweeper(14, 0, -6, 8, 2, MEDIUM),
				-- gap 11 to a 10 x 10 target sliding 14 studs end to end in 2.6 s
				Kit.slab(40, 0, 0, 10, 10, "jelly", {
					tone = 2,
					motion = { kind = "slide", axis = "z", amp = 7, period = 2.6 },
				}),
				plain(50, length, 0, 0, Kit.WIDTH, 3), -- gap 5
			})
		end,
	},
	{
		-- The runway tiles melt a moment after you leave them, so there is no second run-up; a red goo block slides
		-- across the runway, so wait on a tile and go.
		name = "No Second Try",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local length = 51
			local parts = { plain(0, 4, 0, 0, Kit.WIDTH, 1) }
			for i = 0, 5 do
				local x0 = 4 + i * 4
				table.insert(
					parts,
					strip(x0, x0 + 4, 0, 0, 12, 30, {
						motion = { kind = "melt", on = "leave", delay = 0.6, away = -1 },
					})
				)
			end
			table.insert(parts, sweeper(18, 0, 0, 10, 5, MEDIUM))
			table.insert(parts, plain(39, length, 0, 0, Kit.WIDTH, 3)) -- gap 11
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- The strip blinks on and off over a plain floor and only boosts while it is there; a red goo block sweeps
		-- near the edge on its own beat. Jump while it is lit and the block is away.
		name = "Blink Boost",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local length = 50.5
			local lit, off = 0.75, 1.65
			return Kit.section(length, 0, {
				plain(0, 4, 0, 0, Kit.WIDTH, 1),
				plain(4, 26, 0, 0, 12, 2), -- the floor under the strip
				-- 0.2 over the floor, so you stand on it while it is lit
				strip(8, 26, 0.2, 0, 12, 34, {
					motion = { kind = "flip", period = lit + off, duty = lit / (lit + off) },
				}),
				sweeper(20, 0.2, 0, 10, 5, HARD),
				plain(38.5, length, 0, 0, Kit.WIDTH, 3), -- gap 12.5
			})
		end,
	},
	{
		-- Forward and back strips take turns; jump each back strip, land on the next forward one, get past a red goo
		-- block on the last one, then make the long leap onto a pad sliding side to side.
		name = "Back-and-Forth",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local length = 76
			local speed = 35 -- the draft's 32 covers 12 studs in the checks; the last gap is 13
			return Kit.section(length, 0, {
				plain(0, 4, 0, 0, Kit.WIDTH, 1),
				strip(4, 12, 0, 0, 12, speed),
				backStrip(12, 18, 0, 0, Kit.WIDTH),
				strip(18, 26, 0, 0, 12, speed),
				backStrip(26, 32, 0, 0, Kit.WIDTH),
				strip(32, 40, 0, 0, 12, speed),
				sweeper(36, 0, 0, 10, 5, HARD),
				Kit.slab(57, 0, 0, 8, 10, "jelly", {
					tone = 2,
					motion = { kind = "slide", axis = "z", amp = 6, period = 2.0 },
				}), -- gap 13
				plain(66, length, 0, 0, Kit.WIDTH, 3), -- gap 5
			})
		end,
	},
	{
		-- Two boost strips in opposite halves of the lane with red goo beside each; cut across a plain floor under a
		-- slamming crusher, then the long leap.
		name = "Left, Right, Leap",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local length = 71
			local speed = 35
			local crossFrom, crossTo = 20, 32
			local lift = 11
			return Kit.section(length, 0, {
				plain(0, 4, 0, 0, Kit.WIDTH, 1),
				strip(4, crossFrom, 0, -6.5, 11, speed, { boost = { speed = speed, carry = 1.2 } }),
				gooBed(4, crossFrom, 0, -1, Kit.HALF),
				plain(crossFrom, crossTo, 0, 0, Kit.WIDTH, 2),
				Kit.hazard({ 6, 4, Kit.WIDTH }, { (crossFrom + crossTo) / 2, lift + 2, 0 }, {
					motion = { kind = "punch", axis = "y", amp = -lift, period = CRUSH },
				}),
				strip(crossTo, 48, 0, 6.5, 11, speed, { boost = { speed = speed, carry = 1.2 } }),
				gooBed(crossTo, 48, 0, -Kit.HALF, 1),
				plain(61, length, 0, 0, Kit.WIDTH, 3), -- gap 13
			})
		end,
	},
	{
		-- Two boosted leaps, each one up a step, with only a short strip between them to rebuild speed; a red goo
		-- block sweeps each strip, so there is no calm run-up.
		name = "Double Leap Climb",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local length = 71
			local speed = 35 -- the draft's 34 covers 12.75 studs in the checks; the second gap is 13
			return Kit.section(length, 5, {
				plain(0, 4, 0, 0, Kit.WIDTH, 1),
				strip(4, 24, 0, 0, 12, speed),
				sweeper(16, 0, 0, 10, 5, HARD, 0.5),
				strip(36, 46, 2.5, 0, 12, speed), -- gap 12, +2.5
				sweeper(41, 2.5, 0, 10, 5, HARD),
				plain(59, length, 5, 0, Kit.WIDTH, 3), -- gap 13, +2.5
			})
		end,
	},
}

return M
