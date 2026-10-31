--!strict
--[[
	Goo Rides (obby idea 3, docs/obby-variants/3.json; contract/obby-sections.md)

	Wide jelly rafts and lifts carry you over gaps too long to jump and up walls too high to climb. Each ride is a
	small timed puzzle: when it docks, where it goes, when to get off. Every ride shows a dotted ghost of where it
	stops (`ghostStop`) and a rail line under its path; red see-through goo sits where a ride you must leave is
	heading (touching it = back to the start pad).

	Rides are `path` motions (hold at each stop, move, hold at the next). A ride's dock hold starts `at` seconds into
	server time (`shuttle(..., at)`), so a chain of rides can be timed to hand you on. "Waits for You" and "Sink and
	Swap" run on a per-player clock that starts when you step on the raft (`trigger` + `start` on the raft itself).

	Walking forward never clears a ride: a raft is crossed on foot in about 0.6 s, far less than any trip, so a walker
	steps off its front into the gap (ObbyCheck.straightWalk). tests/obby/GooRides.spec measures every handoff's
	window (how long you can step or jump from one ride to the next, before goo reaches you) against its tier.
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

local RAIL_DROP = 2.5 -- the rail line under a ride sits this far under its top
local RAIL_THICK = 0.3

-- A path motion's phase so that its cycle starts (the dock hold begins) `at` seconds into its clock.
local function phaseAt(at: number, period: number): number
	return (-at / period) % 1
end

-- A ride going between its rest and `far` (an offset) and back: `hold` s at each stop, `move` s each way; its dock
-- hold starts `at` s into the clock.
local function shuttle(far: Kit.Vec, hold: number, move: number, at: number?): Kit.Motion
	local period = 2 * hold + 2 * move
	return {
		kind = "path",
		points = { { 0, 0, 0 }, far },
		hold = hold,
		period = period,
		phase = phaseAt(at or 0, period),
	}
end

-- A raft (or lift deck) whose rear edge is at x0 at rest, `long` along x and `wide` across, top at `top`.
local function raft(
	x0: number,
	top: number,
	z: number,
	long: number,
	wide: number,
	motion: Kit.Motion,
	tone: number,
	extra: { [string]: any }?
): Kit.Part
	local fields: { [string]: any } = { motion = motion, marker = "ghostStop", tone = tone }
	if extra then
		for k, v in extra do
			fields[k] = v
		end
	end
	return Kit.slab(x0 + long / 2, top, z, long, wide, "jelly", fields)
end

-- A dock or ledge from x0 to x1 (full lane width unless `wide` / `z` say otherwise).
local function dock(x0: number, x1: number, top: number, tone: number, z: number?, wide: number?): Kit.Part
	return Kit.slab((x0 + x1) / 2, top, z or 0, x1 - x0, wide or Kit.WIDTH, "goo", { tone = tone })
end

-- The rail line under a ride running along x from x0 to x1 (decor: no collision).
local function railX(x0: number, x1: number, top: number, z: number): Kit.Part
	return Kit.prop({ x1 - x0, RAIL_THICK, 0.6 }, { (x0 + x1) / 2, top - RAIL_DROP, z }, "post", { ghost = true })
end

-- The rail line under a ride running across the lane at x from z0 to z1.
local function railZ(x: number, z0: number, z1: number, top: number): Kit.Part
	return Kit.prop({ 0.6, RAIL_THICK, z1 - z0 }, { x, top - RAIL_DROP, (z0 + z1) / 2 }, "post", { ghost = true })
end

-- The guide pole beside a lift going from y0 to y1 at (x, z).
local function pole(x: number, z: number, y0: number, y1: number): Kit.Part
	return Kit.prop({ 0.6, y1 - y0, 0.6 }, { x, (y0 + y1) / 2, z }, "post", { ghost = true })
end

-- The solid face under a ledge whose front edge is at x0 and top at `top`, from `from` up to the ledge.
local function face(x0: number, top: number, from: number, tone: number): Kit.Part
	local h = top - Kit.THICK - from
	return Kit.prop({ 1, h, Kit.WIDTH }, { x0 + 0.5, from + h / 2, 0 }, "jelly", { tone = tone })
end

-- A tall red goo block from x0 to x1 and z0 to z1, from `bottom` up `height` studs (a ride you stay on runs into it).
local function goo(x0: number, x1: number, z0: number, z1: number, bottom: number, height: number): Kit.Part
	return Kit.hazard({ x1 - x0, height, z1 - z0 }, { (x0 + x1) / 2, bottom + height / 2, (z0 + z1) / 2 })
end

---------------------------------------------------------------------------
-- Variants
---------------------------------------------------------------------------

-- 1. One wide raft over a gap too long to jump; it waits 1 s at each end.
local function firstFerry(_seed: number): Kit.Section
	local length = 58
	local parts = {}
	table.insert(parts, dock(0, 10, 0, 1))
	table.insert(parts, raft(10, 0, 0, 10, 10, shuttle({ 28, 0, 0 }, 1, 2.2), 1))
	table.insert(parts, railX(10, 48, 0, 0))
	table.insert(parts, dock(48, length, 0, 2))
	return Kit.section(length, 0, parts)
end

-- 2. The raft sits at your dock until you step on (its clock starts then), goes 0.6 s later, waits 1.2 s at the far
-- ledge (a hop up) and comes back. After the first trip it keeps shuttling on that clock.
local function waitsForYou(_seed: number): Kit.Section
	local length, rise = 62, 1.5
	local far = { 32, 0, 0 }
	local period = 0.6 * 3 + 2 * 2.2
	local parts = {}
	table.insert(parts, dock(0, 10, 0, 1))
	table.insert(
		parts,
		raft(10, 0, 0, 10, 10, {
			kind = "path",
			-- one zero-length leg at the far stop: 0.6 s at your dock, 1.2 s at the far ledge
			points = { { 0, 0, 0 }, far, far },
			loop = true,
			hold = 0.6,
			period = period,
		}, 2, { trigger = "ride", start = "ride" })
	)
	table.insert(parts, railX(10, 52, 0, 0))
	table.insert(parts, dock(52, length, rise, 3))
	return Kit.section(length, rise, parts)
end

-- 3. A lift up a wall far too high to jump; it waits 1 s at the top and the bottom. Its top stop stands 4 studs off
-- the ledge: jump across while it waits (walking off drops you back down).
local function upTheLift(_seed: number): Kit.Section
	local length, rise = 42, 16
	local parts = {}
	table.insert(parts, dock(0, 12, 0, 1))
	table.insert(parts, raft(12, 0, 0, 10, 10, shuttle({ 0, rise, 0 }, 1, 2.4), 2))
	table.insert(parts, pole(17, 5.6, -1, rise + 1))
	table.insert(parts, face(26, rise, -1, 3))
	table.insert(parts, dock(26, length, rise, 2))
	return Kit.section(length, rise, parts)
end

-- 4. Three ferries over three gaps, each docking just as you reach it from the last (0.6 s waits).
local function ferryLine(_seed: number): Kit.Section
	local hold, move, travel = 0.6, 1.5, 16
	local parts = {}
	table.insert(parts, dock(0, 8, 0, 1))
	local x = 8
	for k = 1, 3 do
		-- the next ferry's dock wait starts about when you step off this one and cross the pad
		table.insert(parts, raft(x, 0, 0, 9, 9, shuttle({ travel, 0, 0 }, hold, move, (k - 1) * 2.6), k))
		table.insert(parts, railX(x, x + 9 + travel, 0, 0))
		x += 9 + travel
		table.insert(parts, dock(x, x + 8, 0, k % 2 + 1))
		x += 8
	end
	return Kit.section(x, 0, parts)
end

-- 5. The way on is off to the side: the shuttle carries you across the lane to where the path goes on. A 4-stud
-- jump on and off (5.5 studs), so you can only make it around the 0.6 s the shuttle waits on your side. The trip
-- across is slow (2.2 s): stand on the deck and wait; hopping on across it runs you off its front long before it
-- gets to the exit lane (ObbyCheck.masher).
local function sideShuttle(_seed: number): Kit.Section
	local length = 52
	local side = 7.5 -- the shuttle's two stops (z 3..12 and -12..-3); the entry and exit lanes are z 4..12 / -12..-4
	local parts = {}
	table.insert(parts, dock(0, 12, 0, 1, 8, 8))
	table.insert(parts, raft(17.5, 0, side, 9, 9, shuttle({ 0, 0, -2 * side }, 0.6, 2.2), 2))
	table.insert(parts, railZ(22, -Kit.HALF, Kit.HALF, 0))
	table.insert(parts, dock(32, length, 0, 2, -8, 8))
	return Kit.section(length, 0, parts)
end

-- 6. Three lifts in a row, each to a higher ledge (8, 10 and 12 up), each at its bottom as you reach it. Each top
-- stop stands STAIR_GAP studs off its ledge: wait on the deck and jump across while it waits at the top (walking or
-- hopping off early drops you into the gap).
local STAIR_GAP = 5
local function stairLifts(_seed: number): Kit.Section
	local parts = {}
	table.insert(parts, dock(0, 8, 0, 1))
	local x, top = 8, 0
	for k, up in { 8, 10, 12 } do
		table.insert(parts, raft(x, top, 0, 9, 9, shuttle({ 0, up, 0 }, 0.8, 1.8, (k - 1) * 3), k))
		table.insert(parts, pole(x + 4.5, 5.1, top - 1, top + up + 1))
		x += 9 + STAIR_GAP
		table.insert(parts, face(x, top + up, top - 1, k))
		top += up
		table.insert(parts, dock(x, x + 8 + (if k == 3 then 1 else 0), top, k % 2 + 1))
		x += 8 + (if k == 3 then 1 else 0)
	end
	return Kit.section(x, top, parts)
end

-- 7. The ferry never stops: it swings past your dock (3 studs at its closest), you jump on, hop the goo bump in
-- the middle of its deck and jump off as it swings past the far dock.
local function driveBy(_seed: number): Kit.Section
	local length = 65
	local amp, period = 15, 5
	local centre = 10 + 3 + 5 + amp -- rest centre: the near extreme's rear edge 3 studs from the dock
	local function swing(): Kit.Motion
		return { kind = "slide", axis = "x", amp = amp, period = period }
	end
	local parts = {}
	table.insert(parts, dock(0, 10, 0, 1))
	table.insert(parts, Kit.slab(centre, 0, 0, 10, 10, "jelly", { motion = swing(), marker = "ghostStop", tone = 2 }))
	table.insert(parts, Kit.hazard({ 2, 1.5, 10 }, { centre, 0.75, 0 }, { motion = swing() }))
	table.insert(parts, railX(centre - amp - 5, centre + amp + 5, 0, 0))
	table.insert(parts, dock(centre + amp + 5 + 3, length, 0, 2))
	return Kit.section(length, 0, parts)
end

-- 8. The ferry heads into a red goo wall; the way on is a ledge beside its path, so step off sideways in time.
local function intoTheGoo(_seed: number): Kit.Section
	local length = 60
	local z = 3.5 -- the raft's line (z -1..8); the ledge is 3 studs to its side (z -12..-4)
	local parts = {}
	table.insert(parts, dock(0, 10, 0, 1))
	table.insert(parts, raft(10, 0, z, 9, 9, shuttle({ 36, 0, 0 }, 1, 2.7), 2))
	table.insert(parts, railX(10, 55, 0, z))
	table.insert(parts, goo(30, 32, -1.5, 9.5, -1, 11))
	table.insert(parts, dock(28.5, length, 0, 2, -8, 8))
	return Kit.section(length, 0, parts)
end

-- 9. A ferry across and a lift up meet for about a second: jump from one to the other, neither reaches alone.
local function midAirSwap(_seed: number): Kit.Section
	local length, rise = 62, 14
	local parts = {}
	table.insert(parts, dock(0, 8, 0, 1))
	table.insert(parts, raft(8, 0, 0, 9, 9, shuttle({ 20, 0, 0 }, 0.4, 1.4), 1))
	table.insert(parts, railX(8, 37, 0, 0))
	-- the lift sits at the bottom while the ferry waits at its far end
	table.insert(parts, raft(38, 0, 0, 9, 9, shuttle({ 0, rise, 0 }, 0.4, 1.4, 1.8), 3))
	table.insert(parts, pole(42.5, 5.1, -1, rise + 1))
	table.insert(parts, face(47, rise, -1, 2))
	table.insert(parts, dock(47, length, rise, 2))
	return Kit.section(length, rise, parts)
end

-- 10. A wide raft carries you through three tall goo gates that each block half its deck, right, left, right:
-- walk across the moving deck to the open side before each one (1.5 s apart).
local function walkTheDeck(_seed: number): Kit.Section
	local length = 70
	local parts = {}
	table.insert(parts, dock(0, 10, 0, 1))
	table.insert(parts, raft(10, 0, 0, 10, 16, shuttle({ 40, 0, 0 }, 0.8, 5), 2))
	table.insert(parts, railX(10, 60, 0, 0))
	for k, x in { 22, 34, 46 } do
		local right = k % 2 == 1
		table.insert(parts, goo(x, x + 2, if right then 0 else -Kit.HALF, if right then Kit.HALF else 0, -1, 11))
	end
	table.insert(parts, dock(60, length, 0, 2))
	return Kit.section(length, 0, parts)
end

-- 11. Ride a lift up to a ferry line; step across only while both sit at the top together (0.8 s).
local function liftToFerry(_seed: number): Kit.Section
	local length, rise = 62, 14
	local parts = {}
	table.insert(parts, dock(0, 8, 0, 1))
	table.insert(parts, raft(8, 0, 0, 9, 9, shuttle({ 0, rise, 0 }, 0.8, 1.5), 1))
	table.insert(parts, pole(12.5, 5.1, -1, rise + 1))
	-- the ferry's dock wait starts as the lift gets to the top
	table.insert(parts, raft(17, rise, 0, 9, 9, shuttle({ 24, 0, 0 }, 0.8, 1.5, 2.3), 3))
	table.insert(parts, railX(17, 50, rise, 0))
	table.insert(parts, face(50, rise, -1, 2))
	table.insert(parts, dock(50, length, rise, 2))
	return Kit.section(length, rise, parts)
end

-- 12. Two lifts 3 studs apart run out of step; hop across as the low one meets the high one, then onto the ledge.
local function liftLadder(_seed: number): Kit.Section
	local length, rise = 44, 20
	local parts = {}
	table.insert(parts, dock(0, 8, 0, 1))
	table.insert(parts, raft(8, 0, 0, 9, 9, shuttle({ 0, 10, 0 }, 0.6, 1.4), 1))
	table.insert(parts, raft(20, 10, 0, 9, 9, shuttle({ 0, 10, 0 }, 0.6, 1.4, 2), 3))
	table.insert(parts, pole(18.5, 5.1, -1, rise + 1))
	table.insert(parts, face(32, rise, -1, 2))
	table.insert(parts, dock(32, length, rise, 2))
	return Kit.section(length, rise, parts)
end

-- 13. Three ferries that each stop for half a second at the handoff: off one, over a 6-stud pad, onto the next.
-- The two pads between them melt QUICK_MELT s after you land (cracks warn, back 2.5 s later): no waiting a whole
-- trip for the next ferry; get off as this one docks and the next one is there.
local QUICK_MELT = 2.4
local QUICK = { hold = 0.5, move = 1.6, travel = 16, lead = 3.5 }
local function quickStop(_seed: number): Kit.Section
	local q = QUICK
	local parts = {}
	table.insert(parts, dock(0, 8, 0, 1))
	local x = 8
	for k = 1, 3 do
		table.insert(parts, raft(x, 0, 0, 9, 9, shuttle({ q.travel, 0, 0 }, q.hold, q.move, (k - 1) * q.lead), k))
		table.insert(parts, railX(x, x + 9 + q.travel, 0, 0))
		x += 9 + q.travel
		if k == 3 then
			table.insert(parts, dock(x, x + 8, 0, 1))
			x += 8
		else
			local pad = dock(x, x + 6, 0, k % 2 + 1)
			pad.motion = { kind = "melt", delay = QUICK_MELT, away = 2.5 }
			pad.marker = "cracks"
			table.insert(parts, pad)
			x += 6
		end
	end
	return Kit.section(x, 0, parts)
end

-- 14. The ferry takes turns: one trip to the exit stop (a 2-stud hop to the exit ledge), the next into the goo
-- stop. Its ghost marks the exit stop; board only for the trip that goes there.
local function wrongStop(_seed: number): Kit.Section
	local length = 60
	local exit = { 22, 0, -7.5 } -- the raft (9 x 9) at x 32..41, z -12..-3
	local arch = { 22, 0, 7.5 } -- x 32..41, z 3..12: inside the goo
	local parts = {}
	table.insert(parts, dock(0, 10, 0, 1))
	table.insert(
		parts,
		raft(10, 0, 0, 9, 9, {
			kind = "path",
			points = { { 0, 0, 0 }, exit, { 0, 0, 0 }, arch },
			loop = true,
			hold = 0.8,
			period = 4 * 0.8 + 4 * 2,
		}, 2)
	)
	table.insert(parts, railX(10, 41, 0, 0))
	-- the goo over the wrong stop: the exit trip passes it 1 stud clear, the wrong one runs every deck spot into it
	table.insert(parts, goo(28.5, 42, 3.5, Kit.HALF, -1, 11))
	table.insert(parts, dock(43, length, 0, 2, -7.5, 9))
	return Kit.section(length, 0, parts)
end

-- 15. Step on a raft and it sinks towards red goo (1.5 studs a second) without reaching the far side; the way out
-- is a ferry passing beside and above it every 4 s: board when it comes, jump up before you sink out of reach.
local function sinkAndSwap(_seed: number): Kit.Section
	local length, rise = 55, 2.5
	local parts = {}
	table.insert(parts, dock(0, 10, 0, 1))
	table.insert(
		parts,
		raft(10, 0, -6.5, 10, 10, {
			kind = "path",
			points = { { 0, 0, 0 }, { 6, -6, 0 } },
			once = true,
			hold = 0.3,
			period = 3.9,
		}, 2, { trigger = "sink", start = "sink", marker = "cracks" })
	)
	table.insert(parts, raft(20, rise, 3, 9, 9, shuttle({ 13, 0, 0 }, 0.6, 1.4), 3))
	table.insert(parts, railX(20, 42, rise, 3))
	table.insert(parts, goo(10, 42, -Kit.HALF, Kit.HALF, -7, 2))
	table.insert(parts, dock(42, length, rise, 2))
	return Kit.section(length, rise, parts)
end

-- 16. Three ferries, no pads: the first two each run into red goo. Jump from ride to ride as the next one comes
-- back past you, in the second before the goo reaches you.
local function tripleTransfer(_seed: number): Kit.Section
	local length = 80
	local hold, move, travel = 0.4, 3, 20
	local period = 2 * hold + 2 * move
	local lead = 3.955 -- seconds each ferry runs ahead of the one before
	local lanes = { 7, -7, 7 }
	local rests = { 8, 24, 40 }
	local parts = {}
	table.insert(parts, dock(0, 8, 0, 1))
	for k = 1, 3 do
		local motion = shuttle({ travel, 0, 0 }, hold, move)
		motion.phase = ((k - 1) * lead / period) % 1
		table.insert(parts, raft(rests[k], 0, lanes[k], 9, 9, motion, k))
		table.insert(parts, railX(rests[k], rests[k] + 9 + travel, 0, lanes[k]))
	end
	-- the goo the first two run into, over their far stops
	table.insert(parts, goo(26, 38, 2, 12, -1, 9))
	table.insert(parts, goo(42, 54, -12, -2, -1, 9))
	table.insert(parts, dock(69, length, 0, 2))
	return Kit.section(length, 0, parts)
end

-- 17. A fast ferry shoots towards a goo wall; the exit ledge flashes past beside it: well under a second to jump.
local function express(_seed: number): Kit.Section
	local length = 62
	local z = 3.5
	local parts = {}
	table.insert(parts, dock(0, 10, 0, 1))
	table.insert(parts, raft(10, 0, z, 9, 9, shuttle({ 40, 0, 0 }, 0.5, 2.4), 3))
	table.insert(parts, railX(10, 59, 0, z))
	table.insert(parts, goo(37, 39, -1.5, 9.5, -1, 11))
	table.insert(parts, dock(35.5, length, 0, 2, -8, 8))
	return Kit.section(length, 0, parts)
end

-- 18. Two fast lifts with red goo caps 3 studs over their top stops: ride the first, hop to the second, step off at
-- the exit before either carries you into its cap.
local function shaftRush(_seed: number): Kit.Section
	local length, rise = 45, 20.5
	local up, hold, move = 16, 0.5, 2
	local parts = {}
	table.insert(parts, dock(0, 8, 0, 1))
	table.insert(parts, raft(8, 0, 0, 9, 9, shuttle({ 0, up, 0 }, hold, move), 1))
	table.insert(parts, goo(7.5, 17.5, -5, 5, up + 3, 2))
	-- the second lift leaves its bottom stop (10) 1.2 s after the first leaves its own (0)
	table.insert(parts, raft(20, 10, 0, 9, 9, shuttle({ 0, up, 0 }, hold, move, 1.2), 3))
	table.insert(parts, goo(19.5, 29.5, -5, 5, 10 + up + 3, 2))
	table.insert(parts, pole(18.5, 5.1, -1, 10 + up + 1))
	table.insert(parts, dock(29, length, rise, 2))
	return Kit.section(length, rise, parts)
end

local M = {}
M.id = "GooRides"
M.name = "Goo Rides"
M.idea = 3

M.variants = {
	{ name = "First Ferry", tier = "easy", build = firstFerry },
	{ name = "Waits for You", tier = "easy", build = waitsForYou },
	{ name = "Up the Lift", tier = "easy", build = upTheLift },
	{ name = "Ferry Line", tier = "easy", build = ferryLine },
	{ name = "Side Shuttle", tier = "easy", build = sideShuttle },
	{ name = "Stair Lifts", tier = "easy", build = stairLifts },
	{ name = "Drive-by", tier = "medium", build = driveBy },
	{ name = "Into the Goo", tier = "medium", build = intoTheGoo },
	{ name = "Mid-air Swap", tier = "medium", build = midAirSwap },
	{ name = "Walk the Deck", tier = "medium", build = walkTheDeck },
	{ name = "Lift to Ferry", tier = "medium", build = liftToFerry },
	{ name = "Lift Ladder", tier = "medium", build = liftLadder },
	{ name = "Quick Stop", tier = "medium", build = quickStop },
	{ name = "Wrong Stop", tier = "medium", build = wrongStop },
	{ name = "Sink and Swap", tier = "hard", build = sinkAndSwap },
	{ name = "Triple Transfer", tier = "hard", build = tripleTransfer },
	{ name = "Express", tier = "hard", build = express },
	{ name = "Shaft Rush", tier = "hard", build = shaftRush },
}

return M
