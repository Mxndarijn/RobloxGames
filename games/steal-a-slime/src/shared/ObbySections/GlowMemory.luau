--!strict
--[[
	Glow Memory (obby idea 10, docs/obby-variants/10.json; contract/obby-sections.md)

	A grid of same-looking green tiles, a row at a time across the lane, with a 4.5+ stud hole between rows (too long
	to walk over). One tile per row is safe; the others are fakes (`Kit.trap`): they give way the moment
	you touch them (no standing, no jump-off), crack and drop, and stay gone until you are reset. The safe path is shown for a moment, then every tile looks the same again:
	remember it and hop it.

	The path is seeded (`pathOf`): the next safe tile is in the same lane or the one next to it, never more than
	`maxRun` rows in one lane, so it is never a straight line. Every variant uses its seed for the path, so a course
	does not teach one fixed answer.

	How the path is shown (Merijn: every memory section shows its route while you are before its sign and hides it
	once you pass it; no flash timers, no button): a lit slab lies on every safe tile (`shown`, a ghost with a `reveal`
	line at the entry pad's back edge, where the entry sign hangs). Each runner's own client shows them while that
	runner's root is before the line and hides them once past it (visuals/client/ObbySignFade, Config.OBBY.ROUTE_REVEAL),
	so you read the path from the run-up, step onto the entry pad and it is gone; a fall or reset to the start shows it
	again. The modes on top of the seeded path:
	  all      every safe tile is lit
	  two      two safe tiles a row, both lit: remember the one dark tile to skip
	  crumbs   `all`, and every third path tile carries a star that stays (breadcrumbs)
	  pink     the fakes are shown instead: a pink slab on each fake
	  rounds   two paths take turns every round: the other path's own tiles fade out (`flip`); the shared tiles are lit

	No waiting it out (review, contract §10): in every mode but `rounds` and One Look the safe tiles melt `melt` seconds
	after you land (easy 2 s, medium 1.4 s, hard 1 s, Hot Feet 0.75 s), so you must cross from memory, not stand
	about.
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

type Part = Kit.Part

local LANES3 = { -8, 0, 8 } -- lane centres: three 8-wide lanes fill the 24-stud lane
local LANES2 = { -6, 6 } -- two 12-wide lanes
local TILE_LONG = 8
local GAP = 4.5 -- studs between rows: over the 3.6 a walker crosses without jumping, under GAP_MAX
local ENTRY_LONG = 8
local EXIT_LONG = 6
local MID_LONG = 8 -- the rest pad between two grids
local SHOWN_THICK = 0.2 -- the lit slab lying on a tile
local SHOWN_INSET = 0.6 -- studs narrower than its tile, so the tile's edge shows round it

type Opts = {
	mode: string,
	rows: number,
	lanes: number?,
	long: number?,
	gap: number?,
	entry: number?,
	exit: number?,
	climb: number?, -- studs each row is higher than the one before
	split: number?, -- a rest pad after this row
	period: number?, -- rounds: seconds a path holds before the other takes over
	melt: number?, -- seconds a safe tile holds you (nil = it stays)
	maxRun: number?,
	snake: boolean?,
	sign: string?, -- the entry sign's picture for this mode (visuals/shared/ObbySigns), nil = the plain glow one
	salt: number,
}

-- The lit slab lying on `tile` (look `look`, tone `tone`), shown only while the runner is before course x `line`.
local function shown(tile: Part, look: string, tone: number, line: number): Part
	local top = tile.pos[2] + tile.size[2] / 2
	return Kit.prop(
		{ tile.size[1] - SHOWN_INSET, SHOWN_THICK, tile.size[3] - SHOWN_INSET },
		{ tile.pos[1], top + SHOWN_THICK / 2, tile.pos[3] },
		look,
		{ tone = tone, ghost = true, reveal = line }
	)
end

-- Is the path fine: never more than `maxRun` rows in one lane, at least two lanes used.
local function pathOk(p: { number }, maxRun: number): boolean
	local run, used = 1, { [p[1]] = true }
	local lanesUsed = 1
	for k = 2, #p do
		run = if p[k] == p[k - 1] then run + 1 else 1
		if run > maxRun then
			return false
		end
		if not used[p[k]] then
			used[p[k]] = true
			lanesUsed += 1
		end
	end
	return lanesUsed >= 2
end

-- The safe lane of every row: the same lane or the one next to it each row (always a 4-ish stud hop).
local function pathOf(rng: any, rows: number, lanes: number, o: Opts): { number }
	local maxRun = o.maxRun or 3
	for _ = 1, 200 do
		local p = { rng:int(1, lanes) }
		for k = 2, rows do
			local opts = {}
			for d = -1, 1 do
				local l = p[k - 1] + d
				if l >= 1 and l <= lanes and not (o.snake and d == 0) then
					table.insert(opts, l)
				end
			end
			p[k] = opts[rng:int(1, #opts)]
		end
		if pathOk(p, maxRun) then
			return p
		end
	end
	-- never reached in practice: a zigzag always passes
	local p = {}
	for k = 1, rows do
		p[k] = if k % 2 == 1 then 1 else 2
	end
	return p
end

-- Builds one grid for mode `o.mode` with the path from `seed`.
local function build(o: Opts, seed: number): Kit.Section
	local rng = Kit.rng(seed * 7919 + o.salt)
	local lanes = o.lanes or 3
	local zs = if lanes == 2 then LANES2 else LANES3
	local wide = Kit.WIDTH / lanes
	local long, gap = o.long or TILE_LONG, o.gap or GAP
	local entryLong, exitLong = o.entry or ENTRY_LONG, o.exit or EXIT_LONG
	local climb = o.climb or 0
	local period = o.period or 8
	local mode = o.mode

	local parts: { Part } = {}
	local entry = Kit.slab(entryLong / 2, 0, 0, entryLong, Kit.WIDTH, "pad")
	table.insert(parts, entry)
	-- the entry pad's back edge: the entry sign hangs over it (ObbyCourse.signs), the route hides once you pass it
	local line = entry.pos[1] - entry.size[1] / 2
	local grid: { { Part } } = {}
	local x = entryLong + gap
	for k = 1, o.rows do
		local row = {}
		for l = 1, lanes do
			local tile = Kit.slab(x + long / 2, climb * k, zs[l], long, wide, "glow", { tone = 2 })
			tile.step = nil
			table.insert(parts, tile)
			row[l] = tile
		end
		grid[k] = row
		x += long + gap
		if o.split and k == o.split then
			table.insert(parts, Kit.slab(x + MID_LONG / 2, climb * k, 0, MID_LONG, Kit.WIDTH, "pad"))
			x += MID_LONG + gap
		end
	end
	local rise = climb * o.rows
	table.insert(parts, Kit.slab(x + exitLong / 2, rise, 0, exitLong, Kit.WIDTH, "pad"))
	local length = x + exitLong

	-- Which tiles are safe: the path, plus a second tile a row in `two` (every row) and `pink` (odd rows), plus the
	-- second path in `rounds`. Every lane has a fake in some row, so no lane can be jumped straight.
	local path, other = {}, {}
	local safe: { { boolean } } = {}
	for _ = 1, 200 do
		path = pathOf(rng, o.rows, lanes, o)
		other = {}
		safe = {}
		for k = 1, o.rows do
			safe[k] = {}
			safe[k][path[k]] = true
		end
		if mode == "two" or mode == "pink" then
			for k = 1, o.rows do
				if mode == "two" or k % 2 == 1 then
					local l = path[k]
					while l == path[k] do
						l = rng:int(1, lanes)
					end
					safe[k][l] = true
				end
			end
		elseif mode == "rounds" then
			other = pathOf(rng, o.rows, lanes, o)
			for k = 1, o.rows do
				safe[k][other[k]] = true
			end
		end
		local ok = true
		for l = 1, lanes do
			local faked = false
			for k = 1, o.rows do
				faked = faked or not safe[k][l]
			end
			ok = ok and faked
		end
		if mode == "rounds" then
			local differ = 0
			for k = 1, o.rows do
				differ += if path[k] ~= other[k] then 1 else 0
			end
			ok = ok and differ * 3 >= o.rows * 2
		end
		if ok then
			break
		end
	end

	local extra: { Part } = {}
	for k = 1, o.rows do
		for l = 1, lanes do
			local tile = grid[k][l]
			local onPath = path[k] == l or (mode == "rounds" and other[k] == l)
			if onPath then
				tile.step = true
			end
			if not safe[k][l] then
				tile.motion = Kit.trap()
				if mode == "pink" then
					table.insert(extra, shown(tile, "jelly", 1, line))
				end
			elseif mode == "rounds" and path[k] ~= other[k] then
				-- one path's own tile: there for its round, faded out (not solid) for the other
				local phase = if path[k] == l then 0 else 0.5
				tile.motion = { kind = "flip", period = 2 * period, duty = 0.5, phase = phase }
			else
				if o.melt then
					tile.motion = { kind = "melt", on = "land", delay = o.melt, away = -1 }
				end
				if mode ~= "pink" then
					table.insert(extra, shown(tile, "glow", 1, line))
				end
				if mode == "crumbs" and k % 3 == 1 then
					tile.marker = "star"
				end
			end
		end
	end

	for _, p in extra do
		table.insert(parts, p)
	end
	local section = Kit.section(length, rise, parts)
	section.sign = o.sign -- the mode's picture on the entry sign; nil = the idea's ("glow")
	return section
end

local function variant(name: string, tier: string, o: Opts): Kit.Variant
	return {
		name = name,
		tier = tier,
		build = function(seed: number): Kit.Section
			return build(o, seed)
		end,
	}
end

local M = {}
M.id = "GlowMemory"
M.name = "Glow Memory"
M.idea = 10

-- Tuned one notch up from the drafts (contract §10), then tightened in review: 4.5 to 5 stud hops (the draft's 3 is
-- walkable), more rows, seeded paths that never run straight, and safe tiles that melt under you. Every variant shows
-- its path the same way (lit before the entry sign, gone past it); they differ in the grid and the twist.
M.variants = {
	-- Two wide lanes, five rows.
	variant("First Steps", "easy", { mode = "all", rows = 5, lanes = 2, melt = 2, maxRun = 2, salt = 1 }),
	-- Two safe tiles a row: remember the one that stays dark.
	variant("Two of Three", "easy", { mode = "two", rows = 6, melt = 2, salt = 2 }),
	-- Every third path tile keeps a star: remember the rows in between.
	variant("Breadcrumbs", "easy", { mode = "crumbs", rows = 7, melt = 2, salt = 3 }),
	-- Six rows of three lanes.
	variant("Chime Path", "easy", { mode = "all", rows = 6, melt = 2, salt = 4 }),
	-- Seven rows, the medium melt.
	variant("Show Me Pad", "medium", { mode = "all", rows = 7, melt = 1.4, salt = 5 }),
	-- The path changes lane every row.
	variant("Snake Trail", "medium", { mode = "all", rows = 7, snake = true, melt = 1.4, salt = 6 }),
	-- The fakes are shown instead (pink), two a row on even rows.
	variant("Pink Traps", "medium", { mode = "pink", rows = 7, melt = 1.4, sign = "glowPink", salt = 7 }),
	-- Each row 2.5 studs higher: you lose sight of the top rows from the run-up.
	variant("Memory Stairs", "medium", { mode = "all", rows = 6, climb = 2.5, melt = 1.4, salt = 8 }),
	-- Six rows, never more than two in one lane.
	variant("Song Path", "medium", { mode = "all", rows = 6, melt = 1.4, maxRun = 2, salt = 9 }),
	-- Seven rows, never more than two in one lane.
	variant("Map Behind You", "medium", { mode = "all", rows = 7, melt = 1.4, maxRun = 2, salt = 10 }),
	-- Eight rows, shorter tiles, the hard melt.
	variant("Quick Flash", "hard", {
		mode = "all",
		rows = 8,
		long = 7,
		gap = 4.75,
		entry = 6,
		exit = 4,
		melt = 1,
		maxRun = 2,
		salt = 11,
	}),
	-- Two 4-row grids with a rest pad and 4.5-stud holes (a 4-stud hole is walked over): both from one look.
	variant("Two Grids, One Look", "hard", {
		mode = "all",
		rows = 8,
		split = 4,
		long = 6,
		gap = 4.5,
		entry = 5,
		exit = 4,
		maxRun = 2,
		salt = 12,
	}),
	-- Two paths take turns every 8 s: the other path's own tiles fade out, mid-run too.
	variant(
		"New Every Round",
		"hard",
		{ mode = "rounds", rows = 7, period = 8, maxRun = 2, sign = "glowRounds", salt = 13 }
	),
	-- Eight rows, the path changes lane every row.
	variant("Trail Run", "hard", {
		mode = "all",
		rows = 8,
		long = 7,
		gap = 4.75,
		entry = 6,
		exit = 4,
		snake = true,
		melt = 1,
		maxRun = 2,
		salt = 14,
	}),
	-- Safe tiles melt 0.75 s after you land: no stop at all between the pad and the exit.
	variant("Hot Feet", "hard", {
		mode = "all",
		rows = 8,
		long = 7,
		gap = 4.75,
		entry = 6,
		exit = 4,
		melt = 0.75,
		maxRun = 2,
		sign = "glowRush",
		salt = 15,
	}),
}

-- The generator: a seeded mode and row count inside each tier's band (design "difficulty").
type Gen = { modes: { string }, rows: { number }, melt: number, salt: number }
local GEN: { [string]: Gen } = {
	easy = { modes = { "all", "two", "crumbs" }, rows = { 5, 6 }, melt = 2, salt = 101 },
	medium = { modes = { "all", "snake", "pink" }, rows = { 6, 7 }, melt = 1.4, salt = 102 },
	hard = { modes = { "all", "hot", "rounds" }, rows = { 7, 8 }, melt = 1, salt = 103 },
}

M.generator = {
	tiers = { "easy", "medium", "hard" },
	examples = 6,
	build = function(seed: number, tier: string): Kit.Section
		local g = GEN[tier] or GEN.easy
		local rng = Kit.rng(seed * 104729 + g.salt)
		local mode = g.modes[rng:int(1, #g.modes)]
		local rows = rng:int(g.rows[1], g.rows[2])
		local o: Opts = {
			mode = mode,
			rows = rows,
			melt = g.melt,
			maxRun = if tier == "easy" then 3 else 2,
			salt = g.salt + rng:int(1, 1000),
		}
		if rows >= 7 then
			o.long, o.gap, o.entry, o.exit = 7, 4.75, 6, 4
		end
		if mode == "snake" then
			o.mode, o.snake = "all", true
		elseif mode == "pink" then
			o.sign = "glowPink"
		elseif mode == "hot" then
			o.mode, o.melt, o.sign = "all", 0.75, "glowRush"
		elseif mode == "rounds" then
			o.period, o.melt, o.sign = 8, nil, "glowRounds"
		end
		return build(o, seed)
	end,
}

return M
