--!strict
--[[
	Glow Memory (obby idea 10, docs/obby-variants/10.json; contract/obby-sections.md)

	A grid of same-looking green tiles, a row at a time across the lane, with a 4.5+ stud hole between rows (too long
	to walk over). One tile per row is safe; the others are fakes that crack and drop 0.2 s after you land
	(`melt`, gone until you are reset). The safe path is shown for a moment, then every tile looks the same again:
	remember it and hop it.

	The path is seeded (`pathOf`): the next safe tile is in the same lane or the one next to it, never more than
	`maxRun` rows in one lane, so it is never a straight line. Every variant uses its seed for the path, so a course
	does not teach one fixed answer.

	How the path is shown (the variants are these modes on top of the seeded path):
	  all      every safe tile glows together (`flip` with `solid = true`: only the glow blinks, the tile stays solid)
	  two      two safe tiles a row, both glow: remember the one dark tile to skip
	  crumbs   `all`, and every third path tile carries a star that stays (breadcrumbs)
	  seq      the safe tiles light one by one from the front (staggered flip phases), optionally lingering together
	  trigger  a button on the entry pad starts the glow on the local player's clock (`start` group "show")
	  pink     the fakes are shown instead: pink slabs pop up out of them (a `path` overlay hidden inside the tile)
	  board    the floor never glows: a lit map board stands at the back of the entry pad, behind you
	  once     the entry pad starts a single glow of the whole (split) grid; it comes back only after a reset
	  rounds   two paths take turns every round: the other path's own tiles fade out (`flip`), shared tiles glow
	  hot      `all` with the fastest melt (0.75 s): no stop at all between the pad and the exit

	No waiting it out (review, contract §10): in every mode but `once` and `rounds` the safe tiles melt too, `melt`
	seconds after you land (easy 2 s, medium 1.4 s, hard 1 s, Hot Feet 0.75 s). Standing on a safe tile to wait for
	the next glow drops you, so you must remember the path from the pad, not one tile at a time.

	Overlays (`pop`): a ghost slab hidden inside its tile rides a `path` up 0.6 studs for `on` seconds of every
	`period`, so a tile can glow while its own motion is a melt. The path is made of POP_STEP holds that add up to
	the exact period, so overlays stay in step with each other (seq modes). Kit times it (Kit.pathAt), so ObbyFx
	plays what the checks see.
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
local FAKE_DELAY = 0.2 -- seconds a fake tile holds you: its crack is the only tell
local POP_UP = 0.6 -- studs an overlay rises out of its tile while shown
local POP_STEP = 0.25 -- seconds per hold point of an overlay's path (glow times are multiples of it)
local ONCE = 600 -- the period of a glow on a start clock: it does not come back before a reset

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
	on: number?, -- seconds the glow lasts
	period: number?, -- seconds between glows
	stagger: number?, -- seq: seconds between one tile lighting and the next
	lit: number?, -- seq: seconds each tile stays lit
	linger: number?, -- seq: seconds the whole path stays lit after the last tile lights
	melt: number?, -- seconds a safe tile holds you (nil = it stays)
	maxRun: number?,
	snake: boolean?,
	sign: string?,
	salt: number,
}

local function fake(): Kit.Motion
	return { kind = "melt", on = "land", delay = FAKE_DELAY, away = -1 }
end

-- A glow-only flip: lit from `from` for `on` seconds of every `period` (the tile stays solid).
local function glow(from: number, on: number, period: number): Kit.Motion
	return { kind = "flip", solid = true, period = period, duty = on / period, phase = (1 - from / period) % 1 }
end

-- A ghost slab hidden inside `tile` that pops up out of it for `on` seconds from `from` of every `period`: `a`
-- hidden holds then `b` shown holds of POP_STEP each, the rest of the period split between rising and sinking.
local function pop(tile: Part, look: string, tone: number, from: number, on: number, period: number): Part
	local n = math.floor((period - 0.1) / POP_STEP)
	local b = math.clamp(math.floor(on / POP_STEP + 0.5), 1, n - 1)
	local a = n - b
	local points = {}
	for k = 1, n do
		table.insert(points, if k <= a then { 0, 0, 0 } else { 0, POP_UP, 0 })
	end
	local moving = period - n * POP_STEP
	local shownAt = a * POP_STEP + moving / 2
	local top = tile.pos[2] + tile.size[2] / 2
	return Kit.prop({ tile.size[1] - 0.6, 0.4, tile.size[3] - 0.6 }, { tile.pos[1], top - 0.5, tile.pos[3] }, look, {
		tone = tone,
		ghost = true,
		motion = {
			kind = "path",
			points = points,
			period = period,
			hold = POP_STEP,
			loop = true,
			phase = ((shownAt - from) / period) % 1,
		},
	})
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
	local on, period = o.on or 3, o.period or 10
	local mode = o.mode

	local parts: { Part } = {}
	local entry =
		Kit.slab(entryLong / 2, 0, 0, entryLong, Kit.WIDTH, "pad", { marker = `sign:{o.sign or "Remember the glow"}` })
	table.insert(parts, entry)
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
				tile.motion = fake()
				if mode == "pink" then
					table.insert(extra, pop(tile, "jelly", 1, 0, on, period))
				end
			elseif mode == "once" then
				tile.motion = glow(0, on, ONCE)
				tile.start = "look"
			elseif mode == "rounds" then
				if path[k] == l and other[k] == l then
					tile.motion = glow(0, on, period) -- on both paths: glows at every round start
				else
					-- one path's own tile: there for its round, faded out (not solid) for the other
					local phase = if path[k] == l then 0 else 0.5
					tile.motion = { kind = "flip", period = 2 * period, duty = 0.5, phase = phase }
				end
			elseif mode == "board" or mode == "pink" then
				-- nothing on the floor tells these safe tiles apart; they still melt under you
				if o.melt then
					tile.motion = { kind = "melt", on = "land", delay = o.melt, away = -1 }
				end
			else
				-- all, two, crumbs, seq, trigger: when this tile glows in the cycle
				local from, lit = 0, on
				if mode == "seq" then
					local stagger = o.stagger or 0.6
					from = stagger * (k - 1)
					lit = if o.linger then stagger * o.rows + o.linger - from else (o.lit or stagger)
				end
				local group = if mode == "trigger" then "show" else nil
				if o.melt then
					tile.motion = { kind = "melt", on = "land", delay = o.melt, away = -1 }
					local glowing = pop(tile, "glow", 1, from, lit, period)
					glowing.start = group
					table.insert(extra, glowing)
				else
					tile.motion = glow(from, lit, period)
					tile.start = group
				end
				if mode == "crumbs" and k % 3 == 1 then
					tile.marker = "star"
				end
			end
		end
	end

	if mode == "trigger" then
		-- the button: a pink plate at the side of the entry pad, the glow starts when you step on it
		table.insert(
			extra,
			Kit.prop({ 3, 0.4, 3 }, { entryLong - 2.5, 0.2, -8 }, "bar", { ghost = true, trigger = "show" })
		)
	elseif mode == "once" then
		entry.trigger = "look"
	elseif mode == "board" then
		-- a dark board standing over the back of the entry pad (above head height), one lit cell per row: row 1 at the
		-- bottom, each cell in its lane's own z, so it reads the right way round once you turn back to the grid
		local cell, bottom = 1.4, 5.5
		local high = o.rows * cell + 0.6
		table.insert(extra, Kit.prop({ 0.5, high, Kit.WIDTH }, { 0.5, bottom + high / 2, 0 }, "post", { ghost = true }))
		for k = 1, o.rows do
			local y = bottom + 0.3 + (k - 0.5) * cell
			table.insert(
				extra,
				Kit.prop({ 0.3, cell - 0.3, wide - 1 }, { 0.9, y, zs[path[k]] }, "glow", { tone = 1, ghost = true })
			)
		end
	end
	for _, p in extra do
		table.insert(parts, p)
	end
	return Kit.section(length, rise, parts)
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

-- Tuned one notch up from the drafts (contract §10), then tightened in review: shorter glows, 4.5 to 5 stud hops
-- (the draft's 3 is walkable), more rows, seeded paths that never run straight, and safe tiles that melt under you
-- so nobody waits on one for the next glow.
M.variants = {
	-- Two wide lanes, five rows, the whole path glows together (draft 4 s every 8 s).
	variant(
		"First Steps",
		"easy",
		{ mode = "all", rows = 5, lanes = 2, on = 2.5, period = 8, melt = 2, maxRun = 2, salt = 1 }
	),
	-- Two safe tiles a row: remember the one that stays dark.
	variant("Two of Three", "easy", { mode = "two", rows = 6, on = 2.5, period = 8, melt = 2, salt = 2 }),
	-- Every third path tile keeps a star: remember the rows in between.
	variant("Breadcrumbs", "easy", { mode = "crumbs", rows = 7, on = 2.5, period = 9, melt = 2, salt = 3 }),
	-- The path lights front to back, 0.5 s a tile, then stays lit 1 s.
	variant(
		"Chime Path",
		"easy",
		{ mode = "seq", rows = 6, stagger = 0.5, linger = 1, period = 9, melt = 2, salt = 4 }
	),
	-- The glow only starts once you step on the entry pad's button, then comes back every 8 s.
	variant(
		"Show Me Pad",
		"medium",
		{ mode = "trigger", rows = 7, on = 2, period = 8, melt = 1.4, sign = "Step on the button", salt = 5 }
	),
	-- The path changes lane every row.
	variant(
		"Snake Trail",
		"medium",
		{ mode = "all", rows = 7, snake = true, on = 2, period = 10, melt = 1.4, salt = 6 }
	),
	-- The fakes are shown instead (pink), two a row on even rows.
	variant(
		"Pink Traps",
		"medium",
		{ mode = "pink", rows = 7, on = 2, period = 10, melt = 1.4, sign = "Pink = fake", salt = 7 }
	),
	-- Each row 2.5 studs higher: you lose sight of the top rows as you climb.
	variant(
		"Memory Stairs",
		"medium",
		{ mode = "all", rows = 6, climb = 2.5, on = 2, period = 10, melt = 1.4, salt = 8 }
	),
	-- One tile at a time, 0.5 s apart, each lit only 1 s (the notes are an engine gap).
	variant(
		"Song Path",
		"medium",
		{ mode = "seq", rows = 6, stagger = 0.5, lit = 1, period = 8, melt = 1.4, salt = 9 }
	),
	-- The floor never glows: read the board at the back of the entry pad, turn round, go.
	variant(
		"Map Behind You",
		"medium",
		{ mode = "board", rows = 7, entry = 8, melt = 1.4, sign = "Map behind you", salt = 10 }
	),
	-- Eight rows, a 1.5 s flash every 10 s.
	variant("Quick Flash", "hard", {
		mode = "all",
		rows = 8,
		long = 7,
		gap = 4.75,
		entry = 6,
		exit = 4,
		on = 1.5,
		period = 10,
		melt = 1,
		maxRun = 2,
		salt = 11,
	}),
	-- Two 4-row grids with a rest pad and 4.5-stud holes (a 4-stud hole is walked over); both glow once, 2.5 s, when you reach the entry pad (again after a reset).
	variant("Two Grids, One Look", "hard", {
		mode = "once",
		rows = 8,
		split = 4,
		long = 6,
		gap = 4.5,
		entry = 5,
		exit = 4,
		on = 2.5,
		maxRun = 2,
		sign = "One look only",
		salt = 12,
	}),
	-- Two paths take turns every 8 s: the other path's own tiles fade out, mid-run too.
	variant(
		"New Every Round",
		"hard",
		{ mode = "rounds", rows = 7, on = 2, period = 8, maxRun = 2, sign = "New path every 8 s", salt = 13 }
	),
	-- One tile lit at a time, 0.5 s apart: faster than you run.
	variant("Trail Run", "hard", {
		mode = "seq",
		rows = 8,
		long = 7,
		gap = 4.75,
		entry = 6,
		exit = 4,
		stagger = 0.5,
		lit = 0.75,
		period = 8,
		melt = 1,
		maxRun = 2,
		salt = 14,
	}),
	-- Safe tiles melt 0.75 s after you land: know the whole path before you leave the pad.
	variant("Hot Feet", "hard", {
		mode = "hot",
		rows = 8,
		long = 7,
		gap = 4.75,
		entry = 6,
		exit = 4,
		on = 2,
		period = 10,
		melt = 0.75,
		maxRun = 2,
		sign = "Don't stop!",
		salt = 15,
	}),
}

-- The generator: a seeded mode, row count and glow time inside each tier's band (design "difficulty").
type Gen = { modes: { string }, rows: { number }, on: { number }, period: number, melt: number, salt: number }
local GEN: { [string]: Gen } = {
	easy = {
		modes = { "all", "two", "crumbs", "seq" },
		rows = { 5, 6 },
		on = { 2.5, 3 },
		period = 8,
		melt = 2,
		salt = 101,
	},
	medium = {
		modes = { "all", "snake", "pink", "seq", "trigger", "board" },
		rows = { 6, 7 },
		on = { 2, 2.5 },
		period = 10,
		melt = 1.4,
		salt = 102,
	},
	hard = {
		modes = { "flash", "trail", "hot", "rounds" },
		rows = { 7, 8 },
		on = { 1.5, 2 },
		period = 10,
		melt = 1,
		salt = 103,
	},
}

M.generator = {
	tiers = { "easy", "medium", "hard" },
	examples = 6,
	build = function(seed: number, tier: string): Kit.Section
		local g = GEN[tier] or GEN.easy
		local rng = Kit.rng(seed * 104729 + g.salt)
		local mode = g.modes[rng:int(1, #g.modes)]
		local rows = rng:int(g.rows[1], g.rows[2])
		local on = g.on[1] + math.floor(rng:float() * 2 + 0.5) * (g.on[2] - g.on[1]) / 2
		local o: Opts = {
			mode = mode,
			rows = rows,
			on = on,
			period = g.period,
			melt = g.melt,
			maxRun = if tier == "easy" then 3 else 2,
			salt = g.salt + rng:int(1, 1000),
		}
		if rows >= 7 then
			o.long, o.gap, o.entry, o.exit = 7, 4.75, 6, 4
		end
		if mode == "snake" then
			o.mode, o.snake = "all", true
		elseif mode == "flash" then
			o.mode = "all"
		elseif mode == "seq" then
			o.stagger, o.linger, o.period = 0.5, if tier == "easy" then 1 else 0.5, 9
		elseif mode == "trail" then
			o.mode, o.stagger, o.lit, o.period = "seq", 0.5, 0.75, 8
		elseif mode == "pink" then
			o.sign = "Pink = fake"
		elseif mode == "trigger" then
			o.sign, o.period = "Step on the button", 8
		elseif mode == "board" then
			o.entry, o.sign = 10, "Map behind you"
		elseif mode == "hot" then
			o.melt, o.sign = 0.75, "Don't stop!"
		elseif mode == "rounds" then
			o.period, o.on, o.melt, o.sign = 8, 2, nil, "New path every 8 s"
		end
		return build(o, seed)
	end,
}

return M
