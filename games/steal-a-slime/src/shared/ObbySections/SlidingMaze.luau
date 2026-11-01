--!strict
--[[
	Sliding Maze (obby idea 25, docs/obby-variants/25.json; contract/obby-sections.md)

	A walled maze on a 3 x N grid of 8-stud cells (3 columns across the 24-stud lane, N rows along the course) whose
	red see-through panels move: a cross wall slides across the lane on a dark groove (a `path` shuttle: hold, slide,
	hold) between its passage and the jelly wall beside it (or a second passage, for a swap panel); a long wall in a
	divider and a lift door rise out of the way. A passage is open while its panel is away. Fixed walls and the
	blocks that fill unused cells are blue jelly, 9 studs tall (over a jump) and safe to touch; the red panels are
	hazards (touch = back to the start pad). Panels only travel on cell edges, so every cell centre is a safe place to
	stand and wait.

	Every maze is a Layout (the open edges between cells, the cells in use, the panels) built by `build`: floor,
	blocks, walls merged into runs, panels and grooves. Hand-made variants write theirs with `maze` (chains of
	cells); the generator (M.generator) grows a seeded maze (a solution path that turns, dead-end branches, panels on
	the path's crossings) and proves it with `M.solve`, a timed solver walking the cell graph with the shared runner
	(16 studs / s, 0.3 s per turn) against the panels' own clocks (Kit.offsetAt, the curves ObbyFx plays), from every
	start moment of a beat. The specs (tests/obby/SlidingMaze.spec) run the same solver over every variant.

	Every variant opens with a 5-stud jump onto the maze floor (Lookout Maze: a drop off the lookout and stairs out),
	and inside, a fixed wall stops every straight line, so walking forward never clears one.

	Kit limits (engineGaps): a hazard sliding along the course gets swept to the section's end by ObbyCheck, so the
	long walls lift instead of sliding along; a `trigger` starts its clock once per run, so Pull the Plug's door
	runs its open / shut cycle from the first press instead of holding open while you stand on the plate; and The
	Chaser's wall is a row-by-row red flood (`rise` on a `start` clock) rolling down the maze at the chaser's speed.
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

local M = {}
M.id = "SlidingMaze"
M.name = "Sliding Maze"
M.idea = 25

local CELL = 8 -- a maze cell, studs
local ENTRY_LONG = 4 -- the entry pad
local ENTRY_GAP = 5 -- the jump onto the maze floor: a walker drops 3 studs before the far edge (ObbyCheck.walkStop)
local X0 = ENTRY_LONG + ENTRY_GAP -- where the maze floor starts
local EXIT_LONG = 3 -- the exit pad past the last row
local WALL_TONE = 3 -- blue jelly walls: far from the red of the sliding panels
local OUTER = Kit.HALF - 0.5 -- the outer walls' centres (z)
local DOOR_THICK = 0.6 -- a sliding panel, inside its 1-stud wall line
local DOOR_LONG = CELL - 0.2
local DOOR_TALL = Kit.WALL_HEIGHT - 0.2
local DOOR_FLOAT = 0.1 -- a panel's bottom over the floor
local LIFT_UP = 13 -- a lift door (Stop and Go) rises this far: over a jumping head
local GROOVE = 0.8 -- the dark groove under a panel's travel
local GROOVE_THICK = 0.06

-- Runner numbers of the timed solver (Collapsing Bridge's runner, idea 24).
local RUN = Kit.WALK
local TURN = 0.3 -- seconds lost on a turn
local HALF = CELL / 2 / RUN -- cell centre to its edge
local DT = 0.05 -- the solver's time step
local PASS = 0.1 -- seconds either side of the edge time a body is in a panel's plane
local MAX_WAIT = 16 -- seconds the solver waits at most for one edge

export type Timing = {
	shut: number, -- holds the panel spends in its rest slot (passage shut)
	open: number, -- holds it spends parked (passage open)
	hold: number, -- seconds a hold
	move: number, -- seconds a slide
	phase: number?,
}

-- A panel as the layout states it: it rests in the edge between cells `a` and `b` and slides across to column
-- `park` (`swap`: that slot is a passage too), or (`lift`, and always in a side edge) rises. `start`: it runs on
-- that trigger's clock.
export type DoorSpec = {
	a: string,
	b: string,
	park: number?,
	swap: boolean?,
	lift: boolean?,
	time: Timing,
	start: string?,
}

-- A resolved panel: kind "cross" (in the line between rows `line` and `line + 1`, sliding from column `from` to
-- `to`), "lift" (that line, column `from`, rising) or "slift" (in side line `line` between columns `line` and
-- `line + 1`, row `from`, rising). `index` is its part in the built section.
export type Door = {
	kind: string,
	line: number,
	from: number,
	to: number,
	time: Timing,
	start: string?,
	index: number,
}

export type Chaser = { speed: number, delay: number, rise: number }

export type Layout = {
	rows: number,
	entry: { [number]: boolean }?, -- the columns open into the first row (nil: the whole first line)
	exit: { [number]: boolean }?, -- the columns open out of the last row (nil: the whole last line)
	open: { [string]: boolean }, -- edge keys (crossKey / sideKey) that are passages
	used: { [string]: boolean }, -- cell keys that are part of the maze (the rest are jelly blocks)
	doors: { Door },
	tops: { number }, -- floor top of each row
	ramps: { [number]: number }, -- line r -> column of the ramp up to the next terrace
	plates: { { row: number, col: number, group: string } },
	chaser: Chaser?,
	x0: number, -- where the maze floor starts
	lookout: boolean?, -- the lead is a raised lookout (Lookout Maze) instead of the entry pad and jump
	generated: boolean?, -- grown by the generator (not a fallback)
}

local function cellKey(r: number, c: number): string
	return `{r}:{c}`
end

-- The edge between rows r and r + 1 in column c ("x", cross line r: 0 = entry, rows = exit) or between columns
-- k and k + 1 in row r ("z", side line k).
local function crossKey(r: number, c: number): string
	return `x{r}:{c}`
end
local function sideKey(r: number, k: number): string
	return `z{r}:{k}`
end

local function parseCell(s: string): (number, number)
	local r, c = string.match(s, "^(%d+):(%d)$")
	assert(r and c, `sliding maze: bad cell {s}`)
	return tonumber(r) :: number, tonumber(c) :: number
end

-- The edge key between two neighbouring cells.
local function edgeBetween(a: string, b: string): string
	local r1, c1 = parseCell(a)
	local r2, c2 = parseCell(b)
	if c1 == c2 and math.abs(r1 - r2) == 1 then
		return crossKey(math.min(r1, r2), c1)
	elseif r1 == r2 and math.abs(c1 - c2) == 1 then
		return sideKey(r1, math.min(c1, c2))
	end
	error(`sliding maze: cells {a} and {b} are not neighbours`)
end

local function zOf(c: number): number
	return -Kit.HALF - CELL / 2 + CELL * c -- -8, 0, 8
end

local function sideZ(k: number): number
	return -Kit.HALF + CELL * k -- -4, 4
end

local function lineX(L: Layout, r: number): number
	return L.x0 + CELL * r
end

local function rowX(L: Layout, r: number): number
	return L.x0 + CELL * r - CELL / 2
end

---------------------------------------------------------------------------
-- Layouts
---------------------------------------------------------------------------

export type MazeSpec = {
	rows: number,
	entry: (number | { number })?, -- a column or a list of them
	exit: (number | { number })?,
	chains: { string }, -- "r:c r:c ...": neighbouring cells, each pair an open edge
	doors: { DoorSpec }?,
	tops: { number }?,
	ramps: { [number]: number }?,
	plates: { { row: number, col: number, group: string } }?,
	chaser: Chaser?,
	lookout: boolean?,
}

local function columns(v: (number | { number })?): { [number]: boolean }?
	if v == nil then
		return nil
	end
	local out = {}
	for _, c in (if type(v) == "number" then { v } else v) :: { number } do
		out[c] = true
	end
	return out
end

-- A layout from chains of cells (each pair of neighbours in a chain is a passage) and panel specs.
local function maze(spec: MazeSpec): Layout
	local L: Layout = {
		rows = spec.rows,
		entry = columns(spec.entry),
		exit = columns(spec.exit),
		open = {},
		used = {},
		doors = {},
		tops = spec.tops or table.create(spec.rows, 0),
		ramps = spec.ramps or {},
		plates = spec.plates or {},
		chaser = spec.chaser,
		x0 = if spec.lookout then 8 else X0,
		lookout = spec.lookout,
	}
	for _, chain in spec.chains do
		local prev: string? = nil
		for cell in string.gmatch(chain, "%S+") do
			local r, c = parseCell(cell)
			assert(r >= 1 and r <= spec.rows and c >= 1 and c <= 3, `sliding maze: cell {cell} out of the grid`)
			L.used[cell] = true
			if prev then
				L.open[edgeBetween(prev, cell)] = true
			end
			prev = cell
		end
	end
	for _, d in (spec.doors or {}) :: { DoorSpec } do
		local r1, c1 = parseCell(d.a)
		local r2, c2 = parseCell(d.b)
		local key = edgeBetween(d.a, d.b)
		assert(L.open[key], `sliding maze: door {d.a}-{d.b} on a wall`)
		local door: Door
		if c1 == c2 then
			local line = math.min(r1, r2)
			if d.lift then
				door = { kind = "lift", line = line, from = c1, to = c1, time = d.time, start = d.start, index = 0 }
			else
				local park = d.park :: number
				local slot = crossKey(line, park)
				assert(if d.swap then L.open[slot] else not L.open[slot], `sliding maze: door {d.a}-{d.b} park slot`)
				door = { kind = "cross", line = line, from = c1, to = park, time = d.time, start = d.start, index = 0 }
			end
		else
			-- A long wall (in a side line) only rises: a hazard sliding along the course can't be measured fairly
			-- (ObbyCheck sweeps an x-moving hazard to the section's end).
			assert(d.lift, `sliding maze: door {d.a}-{d.b} in a side line must be a lift`)
			door = {
				kind = "slift",
				line = math.min(c1, c2),
				from = r1,
				to = r1,
				time = d.time,
				start = d.start,
				index = 0,
			}
		end
		table.insert(L.doors, door)
	end
	return L
end

local function timing(shut: number, open: number, hold: number, move: number, phase: number?): Timing
	return { shut = shut, open = open, hold = hold, move = move, phase = phase }
end

local function periodOf(t: Timing): number
	return (t.shut + t.open) * t.hold + 2 * t.move
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

-- A panel's shuttle: `shut` holds in its rest slot, a slide of `move` s by `offset`, `open` holds parked, back.
local function shuttle(t: Timing, offset: Kit.Vec): Kit.Motion
	local points = {}
	for _ = 1, t.shut do
		table.insert(points, { 0, 0, 0 })
	end
	for _ = 1, t.open do
		table.insert(points, table.clone(offset))
	end
	return {
		kind = "path",
		points = points,
		period = periodOf(t),
		hold = t.hold,
		loop = true,
		phase = t.phase,
	}
end

-- A fixed wall from (x0, z0) to (x1, z1) (one of them a line), standing on `base`, `tall` high.
local function wallPart(x0: number, x1: number, z0: number, z1: number, base: number, tall: number): Kit.Part
	local sx, sz = math.max(x1 - x0, 1), math.max(z1 - z0, 1)
	return Kit.prop({ sx, tall, sz }, { (x0 + x1) / 2, base + tall / 2, (z0 + z1) / 2 }, "jelly", { tone = WALL_TONE })
end

local function build(L: Layout): Kit.Section
	local N = L.rows
	local tops = L.tops
	local parts: { Kit.Part } = {}
	local x0 = L.x0
	local xEnd = lineX(L, N)
	local low, high = math.huge, -math.huge
	for r = 1, N do
		low, high = math.min(low, tops[r]), math.max(high, tops[r])
	end

	-- The lead: an entry pad and the jump in, or the lookout (4 studs over the maze floor) you drop off.
	if L.lookout then
		table.insert(parts, Kit.slab(x0 / 2, 0, 0, x0, Kit.WIDTH, "jelly", { tone = 2 }))
	else
		table.insert(parts, Kit.slab(ENTRY_LONG / 2, 0, 0, ENTRY_LONG, Kit.WIDTH, "jelly", { tone = 2 }))
	end

	-- Floors: one slab per run of rows at one height (a chaser needs one per row), a ramp up each terrace step.
	local r = 1
	while r <= N do
		local r1 = r
		while r1 < N and tops[r1 + 1] == tops[r] and not L.chaser do
			r1 += 1
		end
		local fx0, fx1 = lineX(L, r - 1), lineX(L, r1)
		local floor = Kit.slab((fx0 + fx1) / 2, tops[r], 0, fx1 - fx0, Kit.WIDTH, "goo", { tone = 1 + (r % 2) })
		if L.chaser and r == 1 then
			floor.trigger = "chaser"
		end
		table.insert(parts, floor)
		local rampCol = L.ramps[r1]
		if rampCol and r1 < N then
			local lx = lineX(L, r1)
			table.insert(parts, Kit.ramp(lx - 6, tops[r1], lx, tops[r1 + 1], zOf(rampCol), CELL, "goo", { tone = 2 }))
		end
		r = r1 + 1
	end

	-- The way out: an exit pad (or two stairs up out of a sunken maze) with a star over it.
	if tops[N] < 0 then
		local up = tops[N] / 2
		table.insert(parts, Kit.slab(xEnd + 2, tops[N] - up, 0, 4, Kit.WIDTH, "jelly", { tone = 1 }))
		table.insert(parts, Kit.slab(xEnd + 6, 0, 0, 4, Kit.WIDTH, "jelly", { tone = 2, marker = "star" }))
	else
		table.insert(
			parts,
			Kit.slab(xEnd + EXIT_LONG / 2, tops[N], 0, EXIT_LONG, Kit.WIDTH, "jelly", { tone = 2, marker = "star" })
		)
	end
	local length = if tops[N] < 0 then xEnd + 8 else xEnd + EXIT_LONG
	local rise = if tops[N] < 0 then 0 else tops[N]

	-- Outer walls along both lane edges, a full wall over the highest floor beside them: over the lookout too, or a
	-- jump off it lands on their tops and runs along them over the maze (ObbyCheck.masher).
	local outerTop = (if L.lookout then math.max(high, 0) else high) + Kit.WALL_HEIGHT
	for _, side in { -1, 1 } do
		table.insert(parts, wallPart(x0, xEnd, side * OUTER - 0.5, side * OUTER + 0.5, low, outerTop - low))
	end

	-- Sealed cells (not part of the maze) are solid jelly blocks, merged along each column.
	local function used(rr: number, c: number): boolean
		return rr >= 1 and rr <= N and L.used[cellKey(rr, c)] == true
	end
	for c = 1, 3 do
		local rr = 1
		while rr <= N do
			if not used(rr, c) then
				local r1 = rr
				while r1 < N and not used(r1 + 1, c) and tops[r1 + 1] == tops[rr] do
					r1 += 1
				end
				local z0 = if c == 1 then -Kit.HALF else sideZ(c - 1)
				local z1 = if c == 3 then Kit.HALF else sideZ(c)
				table.insert(parts, wallPart(lineX(L, rr - 1), lineX(L, r1), z0, z1, tops[rr], Kit.WALL_HEIGHT))
				rr = r1 + 1
			else
				rr += 1
			end
		end
	end

	-- Is the edge a wall? Not a passage, between two maze cells (a block already fills a sealed one).
	local function crossWall(line: number, c: number): boolean
		if line == 0 then
			return L.entry ~= nil and not L.entry[c] and used(1, c)
		elseif line == N then
			return L.exit ~= nil and not L.exit[c] and used(N, c)
		end
		return not L.open[crossKey(line, c)] and used(line, c) and used(line + 1, c)
	end
	local function sideWall(rr: number, k: number): boolean
		return not L.open[sideKey(rr, k)] and used(rr, k) and used(rr, k + 1)
	end

	-- Cross lines: runs of walled columns, one part each.
	for line = 0, N do
		local x = lineX(L, line) + (if line == 0 then 0.5 elseif line == N then -0.5 else 0)
		local below = tops[math.max(line, 1)]
		local above = tops[math.min(line + 1, N)]
		local base, tall = math.min(below, above), math.abs(above - below) + Kit.WALL_HEIGHT
		local c = 1
		while c <= 3 do
			if crossWall(line, c) then
				local c1 = c
				while c1 < 3 and crossWall(line, c1 + 1) do
					c1 += 1
				end
				local z0 = if c == 1 then -Kit.HALF else zOf(c) - CELL / 2
				local z1 = if c1 == 3 then Kit.HALF else zOf(c1) + CELL / 2
				table.insert(parts, wallPart(x - 0.5, x + 0.5, z0, z1, base, tall))
				c = c1 + 1
			else
				c += 1
			end
		end
	end

	-- Side lines: runs of walled rows at one height.
	for k = 1, 2 do
		local rr = 1
		while rr <= N do
			if sideWall(rr, k) then
				local r1 = rr
				while r1 < N and sideWall(r1 + 1, k) and tops[r1 + 1] == tops[rr] do
					r1 += 1
				end
				local z = sideZ(k)
				table.insert(
					parts,
					wallPart(lineX(L, rr - 1), lineX(L, r1), z - 0.5, z + 0.5, tops[rr], Kit.WALL_HEIGHT)
				)
				rr = r1 + 1
			else
				rr += 1
			end
		end
	end

	-- Plates (a glowing pad in a side room starts its group's clock).
	for _, p in L.plates do
		local top = tops[p.row]
		table.insert(
			parts,
			Kit.prop({ 6, 0.3, 6 }, { rowX(L, p.row), top + 0.15, zOf(p.col) }, "glow", { tone = 1, trigger = p.group })
		)
	end

	-- Sliding panels and their grooves.
	for _, d in L.doors do
		local motion: Kit.Motion
		local panel: Kit.Part
		if d.kind == "slift" then
			local top = tops[d.from]
			motion = shuttle(d.time, { 0, LIFT_UP, 0 })
			panel = Kit.hazard(
				{ DOOR_LONG, DOOR_TALL, DOOR_THICK },
				{ rowX(L, d.from), top + DOOR_FLOAT + DOOR_TALL / 2, sideZ(d.line) }
			)
		else
			local top = tops[math.max(d.line, 1)]
			local x, z = lineX(L, d.line), zOf(d.from)
			if d.kind == "lift" then
				motion = shuttle(d.time, { 0, LIFT_UP, 0 })
			else
				motion = shuttle(d.time, { 0, 0, CELL * (d.to - d.from) })
				local gz = (zOf(d.from) + zOf(d.to)) / 2
				table.insert(
					parts,
					Kit.prop(
						{ GROOVE, GROOVE_THICK, CELL * (math.abs(d.to - d.from) + 1) },
						{ x, top + 0.01 + GROOVE_THICK / 2, gz },
						"post",
						{ ghost = true }
					)
				)
			end
			panel = Kit.hazard({ DOOR_THICK, DOOR_TALL, DOOR_LONG }, { x, top + DOOR_FLOAT + DOOR_TALL / 2, z })
		end
		panel.motion = motion
		panel.start = d.start
		table.insert(parts, panel)
		d.index = #parts
	end

	-- The chaser: a red flood under every row rising on the chaser clock, one row after another at its speed.
	local chaser = L.chaser
	if chaser then
		for rr = 1, N do
			local top = tops[rr]
			local tall = 6
			table.insert(
				parts,
				Kit.hazard({ CELL, tall, Kit.WIDTH }, { rowX(L, rr), top - 0.3 - tall / 2, 0 }, {
					start = "chaser",
					motion = {
						kind = "rise",
						speed = chaser.rise,
						delay = chaser.delay + (rr - 1) * CELL / chaser.speed,
						stop = tall,
					},
				})
			)
		end
	end

	return Kit.section(length, rise, parts)
end

---------------------------------------------------------------------------
-- Timed solver
---------------------------------------------------------------------------

-- The walkable z range of column c (between its walls) and x range of row r, as body-centre ranges.
local function colRange(c: number): (number, number)
	local lo = if c == 1 then -OUTER + 0.5 else sideZ(c - 1) + 0.5
	local hi = if c == 3 then OUTER - 0.5 else sideZ(c) - 0.5
	return lo + 1, hi - 1
end

-- Some of [lo, hi] (at least 0.3) lies outside [b0, b1].
local function freeOf(lo: number, hi: number, b0: number, b1: number): boolean
	return (math.min(hi, b0) - lo) >= 0.3 or (hi - math.max(lo, b1)) >= 0.3
end

-- Is edge `key` (a passage) clear of every panel at time t (panel clocks: server time, or since `started[g]`)?
local function clearAt(L: Layout, section: Kit.Section, key: string, t: number, started: { [string]: number }): boolean
	local kind, a, b = string.match(key, "^(%a)(%d+):(%d)$")
	local line, slot = tonumber(a) :: number, tonumber(b) :: number
	for _, d in L.doors do
		local part = section.parts[d.index]
		local clock: number? = t
		if part.start then
			local s = started[part.start]
			clock = if s then t - s else nil
		end
		if kind == "x" and (d.kind == "cross" or d.kind == "lift") and d.line == line then
			local dx, dy, dz = Kit.offsetAt(part, clock)
			local _ = dx
			if d.kind == "lift" then
				if d.from == slot and DOOR_FLOAT + dy < Kit.HEAD + 0.5 then
					return false
				end
			else
				local lo, hi = colRange(slot)
				local pz = part.pos[3] + dz
				if not freeOf(lo, hi, pz - DOOR_LONG / 2 - 1, pz + DOOR_LONG / 2 + 1) then
					return false
				end
			end
		elseif kind == "z" and d.kind == "slift" and d.line == slot and d.from == line then
			local _, dy = Kit.offsetAt(part, clock)
			if DOOR_FLOAT + dy < Kit.HEAD + 0.5 then
				return false
			end
		end
	end
	return true
end

-- A body in the panel's plane from t - PASS to t + PASS finds the edge clear the whole time.
local function passable(L: Layout, section: Kit.Section, key: string, t: number, started: { [string]: number }): boolean
	local k = -PASS
	while k <= PASS + 1e-9 do
		if not clearAt(L, section, key, t + k, started) then
			return false
		end
		k += DT
	end
	return true
end

-- The four moves: +x (on down the course), -x (back), +z (right), -z (left).
local MOVES = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function edgeOf(r: number, c: number, mr: number, mc: number): string
	if mr ~= 0 then
		return crossKey(if mr > 0 then r else r - 1, c)
	end
	return sideKey(r, if mc > 0 then c else c - 1)
end

-- Seconds after `t0` (the moment the runner lands in the first row and starts any trigger there) a runner gets out
-- of the far end, or nil when it can't (a dead maze, or the chaser catches it everywhere).
function M.solve(L: Layout, section: Kit.Section, t0: number): number?
	local N = L.rows
	local deadline: { number } = {}
	for r = 1, N do
		deadline[r] = math.huge
		local ch = L.chaser
		if ch then
			-- the flood's top passes the floor 0.3 / rise s after its delay; keep 0.2 s clear of it
			deadline[r] = t0 + ch.delay + (r - 1) * CELL / ch.speed + 0.3 / ch.rise - 0.2
		end
	end
	local plateAt: { [string]: string } = {}
	for _, p in L.plates do
		plateAt[cellKey(p.row, p.col)] = p.group
	end
	type State = { r: number, c: number, dir: number, t: number, started: { [string]: number }, mask: string }
	local best: { [string]: number } = {}
	local open: { State } = {}
	local function push(s: State)
		local key = `{s.r}:{s.c}:{s.dir}:{s.mask}`
		if best[key] and best[key] <= s.t + 1e-9 then
			return
		end
		best[key] = s.t
		table.insert(open, s)
	end
	local chaserStart: { [string]: number } = if L.chaser then { chaser = t0 } else {}
	for c = 1, 3 do
		if (L.entry == nil or L.entry[c]) and L.used[cellKey(1, c)] then
			local started = table.clone(chaserStart)
			local mask = ""
			local g = plateAt[cellKey(1, c)]
			if g then
				started[g] = t0
				mask = g
			end
			push({ r = 1, c = c, dir = 1, t = t0, started = started, mask = mask })
		end
	end
	local finish: number? = nil
	while #open > 0 do
		local bi = 1
		for i = 2, #open do
			if open[i].t < open[bi].t then
				bi = i
			end
		end
		local s = table.remove(open, bi) :: State
		if finish and s.t >= finish then
			break
		end
		local key = `{s.r}:{s.c}:{s.dir}:{s.mask}`
		if best[key] < s.t - 1e-9 then
			continue
		end
		-- Out of the far end.
		if s.r == N and (L.exit == nil or (L.exit :: any)[s.c]) then
			local out = s.t + (if s.dir ~= 1 then TURN else 0) + HALF
			if out < deadline[N] + HALF and (finish == nil or out < finish) then
				finish = out
			end
		end
		for dir, mv in MOVES do
			local nr, nc = s.r + mv[1], s.c + mv[2]
			if nr >= 1 and nr <= N and nc >= 1 and nc <= 3 then
				local edge = edgeOf(s.r, s.c, mv[1], mv[2])
				if L.open[edge] and L.used[cellKey(nr, nc)] then
					local ready = s.t + (if dir ~= s.dir then TURN else 0)
					local t = ready
					while t <= ready + MAX_WAIT do
						-- You leave this cell's row at the edge (a cross move) or on arrival (a side move).
						local leave = if mv[1] ~= 0 then t + HALF else t + 2 * HALF
						if leave > deadline[s.r] then
							break
						end
						if passable(L, section, edge, t + HALF, s.started) then
							local arrive = t + 2 * HALF
							if arrive < deadline[nr] then
								local started, mask = s.started, s.mask
								local g = plateAt[cellKey(nr, nc)]
								if g and started[g] == nil then
									started = table.clone(started)
									started[g] = arrive
									mask = mask .. g
								end
								push({ r = nr, c = nc, dir = dir, t = arrive, started = started, mask = mask })
							end
							break
						end
						t += DT
					end
				end
			end
		end
	end
	return if finish then finish - t0 else nil
end

-- The longest stretch of moments (seconds) a runner can set off across passage `key` within `span` s (panels on a
-- `start` clock: that clock started at 0).
function M.window(L: Layout, section: Kit.Section, key: string, span: number): number
	local started = setmetatable({}, {
		__index = function()
			return 0
		end,
	}) :: any
	local bestRun, run = 0, 0
	local t = 0
	while t <= span do
		if passable(L, section, key, t, started) then
			run += DT
			bestRun = math.max(bestRun, run)
		else
			run = 0
		end
		t += DT
	end
	return bestRun
end

-- The passages a panel can close: the slots on its line it travels over.
function M.doorEdges(L: Layout): { string }
	local out, seen = {}, {}
	for _, d in L.doors do
		local list = {}
		if d.kind == "slift" then
			table.insert(list, sideKey(d.from, d.line))
		else
			for c = math.min(d.from, d.to), math.max(d.from, d.to) do
				table.insert(list, crossKey(d.line, c))
			end
		end
		for _, key in list do
			if L.open[key] and not seen[key] then
				seen[key] = true
				table.insert(out, key)
			end
		end
	end
	return out
end

-- The longest period of any panel.
function M.longestPeriod(L: Layout): number
	local p = 0
	for _, d in L.doors do
		p = math.max(p, periodOf(d.time))
	end
	return p
end

---------------------------------------------------------------------------
-- Generator
---------------------------------------------------------------------------

export type GenOpts = {
	rows: number?,
	walls: number?,
	dead: number?,
	beats: string?, -- "shared" | "two" | "own"
	turny: boolean?,
	chaser: boolean?,
	early: boolean?, -- dead ends only off the first three rows
}

-- Per tier: rows, panels, dead ends, the panel timing (tuned per contract §10) and how the beats are shared.
local TIERS = {
	easy = { rows = { 5, 6 }, walls = { 4, 5 }, dead = { 0, 0 }, time = timing(1, 1, 1.2, 0.25), beats = "shared" },
	medium = { rows = { 8, 9 }, walls = { 6, 7 }, dead = { 1, 2 }, time = timing(2, 1, 0.8, 0.25), beats = "two" },
	hard = { rows = { 10, 12 }, walls = { 7, 9 }, dead = { 3, 3 }, time = timing(2, 1, 0.62, 0.2), beats = "own" },
}

local function shuffle<T>(rng: any, list: { T }): { T }
	for i = #list, 2, -1 do
		local j = rng:int(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

-- One try at a seeded maze: nil when it comes out wrong (too few dead ends, over the part budget, unsolvable).
-- Park-Miller's first draws from a small seed are tiny: scramble the seed and skip a few.
local function rngOf(seed: number): any
	local rng = Kit.rng((seed * 48271 + 11) % 2147483646 + 1)
	for _ = 1, 3 do
		rng:float()
	end
	return rng
end

local function generateOnce(seed: number, tier: string, opts: GenOpts): (Layout?, Kit.Section?)
	local T = TIERS[tier]
	local rng = rngOf(seed)
	local N = opts.rows :: number
	local walls = opts.walls or rng:int(T.walls[1], T.walls[2])
	local dead = opts.dead or rng:int(T.dead[1], T.dead[2])
	local beats = opts.beats :: string
	local chaser = opts.chaser == true

	-- The solution path: one run of columns per row, turning on most rows.
	local spec: MazeSpec = { rows = N, chains = {}, doors = {} }
	local cin = rng:int(1, 3)
	spec.entry = cin
	local outs = {}
	local cells: { string } = {}
	local onPath: { [string]: boolean } = {}
	for r = 1, N do
		local cout = cin
		local turn = if opts.turny then 0.95 else 0.7
		if rng:float() < turn then
			local choices = {}
			for c = 1, 3 do
				if c ~= cin then
					table.insert(choices, c)
				end
			end
			cout = rng:pick(choices)
		end
		local step = if cout >= cin then 1 else -1
		for c = cin, cout, step do
			table.insert(cells, cellKey(r, c))
			onPath[cellKey(r, c)] = true
		end
		outs[r] = cout
		cin = cout
	end
	spec.exit = outs[N]
	table.insert(spec.chains, table.concat(cells, " "))

	-- Dead ends: chains of 1..3 cells off the path, each grown from a path cell (forward ones first: they tempt).
	local usedCell: { [string]: boolean } = table.clone(onPath)
	local openCross: { [string]: boolean } = {}
	for r = 1, N - 1 do
		openCross[crossKey(r, outs[r])] = true
	end
	local function free(r: number, c: number): boolean
		return r >= 1 and r <= N and c >= 1 and c <= 3 and not usedCell[cellKey(r, c)]
	end
	local made = 0
	for _ = 1, dead do
		local starts = {}
		for _, cell in cells do
			local r, c = parseCell(cell)
			for _, mv in (if opts.early and r > 3 then {} else MOVES) :: { { number } } do
				if free(r + mv[1], c + mv[2]) then
					table.insert(starts, { r, c, r + mv[1], c + mv[2], mv[1] })
				end
			end
		end
		if #starts == 0 then
			break
		end
		shuffle(rng, starts)
		table.sort(starts, function(p, q)
			return math.abs(p[5]) > math.abs(q[5])
		end)
		local pick = starts[rng:int(1, math.min(#starts, 3))]
		local chain = { cellKey(pick[1], pick[2]), cellKey(pick[3], pick[4]) }
		usedCell[chain[2]] = true
		if pick[5] ~= 0 then
			openCross[crossKey(math.min(pick[1], pick[3]), pick[2])] = true
		end
		local r, c = pick[3], pick[4]
		for _ = 1, 2 do
			if rng:float() < 0.6 then
				local nexts = {}
				for _, mv in MOVES do
					if free(r + mv[1], c + mv[2]) then
						table.insert(nexts, mv)
					end
				end
				if #nexts > 0 then
					local mv = rng:pick(nexts)
					if mv[1] ~= 0 then
						openCross[crossKey(math.min(r, r + mv[1]), c)] = true
					end
					r, c = r + mv[1], c + mv[2]
					usedCell[cellKey(r, c)] = true
					table.insert(chain, cellKey(r, c))
				end
			end
		end
		table.insert(spec.chains, table.concat(chain, " "))
		made += 1
	end
	if made < dead then
		return nil, nil
	end

	-- Panels on the path's crossings, parked in a walled slot next door (or swapping with a dead end's passage).
	local lines = {}
	for r = 1, N - 1 do
		table.insert(lines, r)
	end
	shuffle(rng, lines)
	local chosen = {}
	for i = 1, math.min(walls, #lines) do
		table.insert(chosen, lines[i])
	end
	table.sort(chosen)
	local base = T.time
	for i, r in chosen do
		local c = outs[r]
		local parks, swaps = {}, {}
		for _, p in { c - 1, c + 1 } do
			if p >= 1 and p <= 3 then
				table.insert(if openCross[crossKey(r, p)] then swaps else parks, p)
			end
		end
		local park, swap = nil, false
		if #parks > 0 then
			park = rng:pick(parks)
		else
			park, swap = rng:pick(swaps), true
		end
		local phase = 0
		if beats == "two" then
			phase = if i % 2 == 0 then 0.5 else 0
		elseif beats == "own" then
			phase = math.floor(rng:float() * 20) / 20
		end
		table.insert(spec.doors :: { DoorSpec }, {
			a = cellKey(r, c),
			b = cellKey(r + 1, c),
			park = park,
			swap = swap,
			time = timing(base.shut, base.open, base.hold, base.move, phase),
		})
	end
	if chaser then
		spec.chaser = { speed = 5.5, delay = 4, rise = 6 }
	end

	local L = maze(spec)
	L.generated = true
	local ok, section = pcall(build, L)
	if not ok then
		return nil, nil
	end
	-- Proof: from every start moment over a period the runner gets out, waiting at most one beat a panel.
	local period = math.max(M.longestPeriod(L), 1)
	local walk = (2 * N + 6) * (2 * HALF + TURN)
	local t0 = 0
	while t0 < period do
		local took = M.solve(L, section, t0)
		if took == nil or took > walk + #L.doors * period then
			return nil, nil
		end
		t0 += 0.1
	end
	return L, section
end

-- Hand-made fallbacks when 50 seeds in a row fail (never seen in the specs; kept so a pick always builds).
local fallback: { [string]: () -> Layout }

-- A seeded maze of `tier`: the rows, the beat style and the chaser come from the seed once, the maze itself from
-- up to 50 tries until the solver proves one.
local function generate(seed: number, tier: string, opts: GenOpts?): (Layout, Kit.Section)
	local T = TIERS[tier]
	local o: GenOpts = table.clone(opts or {})
	local rng = rngOf(seed + 104729)
	o.rows = o.rows or rng:int(T.rows[1], T.rows[2])
	if o.beats == nil then
		o.beats = if tier == "medium" and rng:float() < 0.5 then "own" else T.beats
	end
	if o.chaser == nil then
		o.chaser = tier == "hard" and (o.rows :: number) <= 11 and rng:float() < 0.5
	end
	for k = 0, 49 do
		local L, section = generateOnce(seed + k * 7919, tier, o)
		if L and section and #section.parts <= 80 then
			return L, section
		end
	end
	local L = fallback[tier]()
	return L, build(L)
end

---------------------------------------------------------------------------
-- Variants
---------------------------------------------------------------------------

local plans: { [number]: (seed: number) -> Layout } = {}

-- Phases that put each panel's open hold round time `at[i]` (seconds) on its clock: a wave a runner can walk with.
local function wave(t: Timing, at: number): Timing
	local period = periodOf(t)
	local centre = t.shut * t.hold + t.move + t.open * t.hold / 2 -- the open hold's middle, into the cycle
	return timing(t.shut, t.open, t.hold, t.move, ((centre - at) / period) % 1)
end

local function phased(t: Timing, phase: number): Timing
	return timing(t.shut, t.open, t.hold, t.move, phase % 1)
end

-- Panel timings per variant (tuned per contract §10: easy windows 1.4..2.0 s, medium 1.0..1.4, hard 0.75..1.0).
local SWAP = timing(1, 1, 1.0, 0.25) -- Swap Sides: the gap jumps a cell every 1.25 s (2.5 s a round trip)
local BREATHE = timing(1, 1, 1.2, 0.25) -- Breathing Walls: 1.45 s open, 1.45 s shut
local STOP = timing(1, 1, 1.2, 0.3) -- Stop and Go: a 3 s beat, each row open half of it
local LOOKOUT = timing(1, 1, 1.2, 0.25) -- Lookout Maze: one 2.9 s beat
local DOMINO = timing(2, 1, 0.8, 0.25) -- Domino Doors: open about 1.0 s of 2.9
local DOMINO_STEP = 1.6 -- the walk from one panel to the next: keep moving and every door is open
local LANE = timing(2, 1, 0.85, 0.3) -- Lane Change: each panel of a run up 0.85 s, the next one 1.05 s later
local LANE_STEP = 1.05
local LANE_OUT = timing(2, 1, 0.8, 0.25) -- Lane Change's way out: open about 1.0 s
local REWIRE = timing(1, 1, 0.95, 0.3) -- Rewire: the wiring holds 0.95 s, then flips
local PLUG = timing(5, 3, 1.0, 0.3) -- Pull the Plug: open 3 s from the press (no dawdling), shut 5 s
local CLIMB = timing(2, 1, 0.75, 0.25) -- Climbing Maze: a 2.75 s beat, open about 1.0 s
local CHASE = timing(2, 1, 0.68, 0.2) -- The Chaser: open about 0.85 s
local CROSS = timing(2, 1, 0.6, 0.2) -- Crossfire: open about 0.75 s, cross and long walls 0.9 s apart

plans[1] = function(_seed: number): Layout
	-- Three red walls, each a panel that swaps between two cells (the third cell is jelly): stand in the room and
	-- step through whichever side is open.
	return maze({
		rows = 5,
		exit = { 1, 3 }, -- the middle never runs straight through: every swap panel visits it
		chains = {
			"1:1 1:2 1:3",
			"2:1 2:2 2:3",
			"3:1 3:2 3:3",
			"4:1 4:2 4:3",
			"5:1 5:2 5:3",
			"1:1 2:1",
			"1:2 2:2",
			"2:2 3:2",
			"2:3 3:3",
			"3:1 4:1",
			"3:2 4:2",
			"4:2 5:2",
			"4:3 5:3",
		},
		doors = {
			{ a = "1:1", b = "2:1", park = 2, swap = true, time = phased(SWAP, 0) },
			{ a = "2:3", b = "3:3", park = 2, swap = true, time = phased(SWAP, 0.25) },
			{ a = "3:2", b = "4:2", park = 1, swap = true, time = phased(SWAP, 0.5) },
			{ a = "4:2", b = "5:2", park = 3, swap = true, time = phased(SWAP, 0.75) },
		},
	})
end

plans[2] = function(_seed: number): Layout
	-- A 3 x 5 zigzag whose four panels all open together and all shut together.
	return maze({
		rows = 6,
		entry = 3,
		exit = 3,
		chains = { "1:3 2:3 2:2 3:2 3:1 4:1 4:2 5:2 5:3 6:3" },
		doors = {
			{ a = "1:3", b = "2:3", park = 2, time = BREATHE },
			{ a = "2:2", b = "3:2", park = 3, time = BREATHE },
			{ a = "3:1", b = "4:1", park = 2, time = BREATHE },
			{ a = "4:2", b = "5:2", park = 1, time = BREATHE },
			{ a = "5:3", b = "6:3", park = 2, time = BREATHE },
		},
	})
end

plans[3] = function(_seed: number): Layout
	-- Three rows of three lift doors on opposite beats round two 8-stud rooms: through one row, wait, through the next.
	local doors: { DoorSpec } = {}
	for c = 1, 3 do
		table.insert(doors, { a = `2:{c}`, b = `3:{c}`, lift = true, time = phased(STOP, 0) })
		table.insert(doors, { a = `3:{c}`, b = `4:{c}`, lift = true, time = phased(STOP, 0.5) })
		table.insert(doors, { a = `4:{c}`, b = `5:{c}`, lift = true, time = phased(STOP, 0) })
	end
	return maze({
		rows = 6,
		entry = 2,
		exit = 3,
		chains = {
			"1:2 1:1 2:1",
			"2:1 2:2 2:3",
			"3:1 3:2 3:3",
			"4:1 4:2 4:3",
			"5:1 5:2",
			"2:1 3:1",
			"2:2 3:2",
			"2:3 3:3",
			"3:1 4:1",
			"3:2 4:2",
			"3:3 4:3",
			"4:1 5:1",
			"4:2 5:2",
			"4:3 5:3",
			"5:2 6:2 6:3",
		},
		doors = doors,
	})
end

plans[4] = function(_seed: number): Layout
	-- The maze floor is 4 studs under the start pad: plan the route from up there, drop in, climb out at the end.
	return maze({
		rows = 6,
		exit = 2,
		lookout = true,
		tops = { -4, -4, -4, -4, -4, -4 },
		chains = {
			"1:1 1:2 1:3",
			"1:2 2:2 2:1 3:1 4:1 4:2 4:3 5:3 6:3 6:2",
			"1:3 2:3 3:3 3:2", -- the dead end that looks like the way on
		},
		doors = {
			{ a = "1:2", b = "2:2", park = 1, time = LOOKOUT },
			{ a = "3:1", b = "4:1", park = 2, time = LOOKOUT },
			{ a = "5:3", b = "6:3", park = 2, time = LOOKOUT },
		},
	})
end

plans[5] = function(_seed: number): Layout
	-- Five panels down a zigzag, each opening a cell's walk after the one before: keep moving and you ride the wave
	-- of open doors; stop once and you wait a whole beat at every door after.
	local cells: { { any } } = {
		{ "1:2", "2:2", 3 },
		{ "2:3", "3:3", 2 },
		{ "3:2", "4:2", 3 },
		{ "4:1", "5:1", 2 },
		{ "5:2", "6:2", 3 },
	}
	local doors: { DoorSpec } = {}
	for i, d in cells do
		table.insert(doors, { a = d[1], b = d[2], park = d[3], time = wave(DOMINO, (i - 1) * DOMINO_STEP) })
	end
	return maze({
		rows = 8,
		entry = 1,
		exit = 2,
		chains = {
			"1:1 1:2 2:2 2:3 3:3 3:2 4:2 4:1 5:1 5:2 6:2 6:3 7:3 7:2 8:2",
			"6:2 6:1 7:1 8:1", -- a dead end
		},
		doors = doors,
	})
end

plans[6] = function(_seed: number): Layout
	-- Three corridors split by jelly dividers. In each divider a run of three red panels lifts one after another,
	-- so the gap travels along it; every corridor dead-ends, so slip across through the moving gap.
	local doors: { DoorSpec } = {}
	for i, r in { 2, 3, 4 } do
		table.insert(doors, { a = `{r}:1`, b = `{r}:2`, lift = true, time = wave(LANE, (i - 1) * LANE_STEP) })
	end
	for i, r in { 8, 7, 6 } do -- the second gap travels back towards you
		table.insert(doors, { a = `{r}:2`, b = `{r}:3`, lift = true, time = wave(LANE, 0.4 + (i - 1) * LANE_STEP) })
	end
	-- and the last step out of the right corridor is a cross wall sliding in from the middle's dead end
	table.insert(doors, { a = "8:3", b = "9:3", park = 2, time = phased(LANE_OUT, 0.3) })
	return maze({
		rows = 9,
		entry = 1,
		exit = 3,
		chains = {
			"1:1 2:1 3:1 4:1", -- the left corridor ends at line 4
			"1:2 2:2 3:2 4:2 5:2 6:2 7:2 8:2", -- the middle one at line 8
			"5:3 6:3 7:3 8:3 9:3", -- the right one runs to the exit
			"2:1 2:2",
			"3:1 3:2",
			"4:1 4:2",
			"6:2 6:3",
			"7:2 7:3",
			"8:2 8:3",
		},
		doors = doors,
	})
end

plans[7] = function(_seed: number): Layout
	-- Two corridors run into one red panel that swaps between them: the one that led on now ends in red, so read
	-- the wiring before you pick a side. Three times, the last two back to back.
	return maze({
		rows = 8,
		entry = 2,
		exit = 2,
		chains = {
			"1:1 1:2 1:3",
			"1:1 2:1 3:1", -- the left way to the first panel
			"1:3 2:3 2:2 3:2", -- the right way round to it
			"2:3 3:3", -- a dead end
			"3:1 4:1",
			"3:2 4:2",
			"4:1 4:2 4:3",
			"4:2 5:2 6:2",
			"4:3 5:3 6:3",
			"6:2 7:2",
			"6:3 7:3",
			"7:2 7:3",
			"7:3 8:3 8:2",
			"7:2 8:2",
		},
		doors = {
			{ a = "3:1", b = "4:1", park = 2, swap = true, time = phased(REWIRE, 0) },
			{ a = "6:2", b = "7:2", park = 3, swap = true, time = phased(REWIRE, 0.3) },
			-- right behind it the last panel rewires on the other beat: read both at once
			{ a = "7:3", b = "8:3", park = 2, swap = true, time = phased(REWIRE, 0.8) },
		},
	})
end

plans[8] = function(_seed: number): Layout
	-- The way on is shut until you step on the glowing plate in the side room; then it opens for 3.6 s.
	return maze({
		rows = 7,
		entry = 2,
		exit = 2,
		chains = {
			"1:2 2:2 2:3 3:3 4:3 4:2 5:2 5:3 6:3 7:3 7:2",
			"2:2 2:1", -- plate room 1
			"5:2 5:1", -- plate room 2
		},
		plates = { { row = 2, col = 1, group = "plug1" }, { row = 5, col = 1, group = "plug2" } },
		doors = {
			-- At rest shut; from the press it slides open within 0.3 s.
			{
				a = "3:3",
				b = "4:3",
				park = 2,
				start = "plug1",
				time = phased(PLUG, PLUG.shut * PLUG.hold / periodOf(PLUG)),
			},
			{
				a = "6:3",
				b = "7:3",
				park = 2,
				start = "plug2",
				time = phased(PLUG, PLUG.shut * PLUG.hold / periodOf(PLUG)),
			},
		},
	})
end

plans[9] = function(_seed: number): Layout
	-- Three 3 x 3 mazes on terraces 2 studs apart, joined by ramps: the way through is also the way up.
	return maze({
		rows = 9,
		entry = 1,
		exit = 3,
		tops = { 2, 2, 2, 4, 4, 4, 6, 6, 6 },
		ramps = { [3] = 3, [6] = 1 },
		chains = {
			"1:1 1:2 2:2 2:3 3:3",
			"2:2 2:1 3:1 3:2", -- dead end
			"3:3 4:3 4:2 5:2 5:1 6:1",
			"5:2 5:3 6:3 6:2", -- dead end
			"6:1 7:1 7:2 8:2 8:3 9:3",
			"8:2 8:1 9:1", -- dead end
		},
		doors = {
			{ a = "1:2", b = "2:2", park = 3, time = phased(CLIMB, 0) },
			{ a = "2:3", b = "3:3", park = 2, time = phased(CLIMB, 0.5) },
			{ a = "4:2", b = "5:2", park = 3, time = phased(CLIMB, 0) },
			{ a = "5:1", b = "6:1", park = 2, time = phased(CLIMB, 0.5) },
			{ a = "7:2", b = "8:2", park = 1, time = phased(CLIMB, 0) },
			{ a = "8:3", b = "9:3", park = 2, time = phased(CLIMB, 0.5) },
		},
	})
end

plans[10] = function(_seed: number): Layout
	-- Stepping into the maze starts a red flood rolling down it behind you, a row at a time at 7 studs / s, while
	-- the panels ahead open on a wave timed to the runner.
	return maze({
		rows = 10,
		entry = 2,
		exit = 2,
		chaser = { speed = 7, delay = 3, rise = 6 },
		chains = {
			"1:2 2:2 2:1 3:1 4:1 4:2 4:3 5:3 6:3 7:3 7:2 8:2 8:1 9:1 10:1 10:2",
			"2:2 2:3 3:3 3:2", -- dead ends
			"4:2 5:2 5:1 6:1 6:2",
			"8:2 8:3 9:3 9:2",
		},
		doors = {
			{ a = "3:1", b = "4:1", park = 2, time = wave(CHASE, 2.35) },
			{ a = "6:3", b = "7:3", park = 2, time = wave(CHASE, 5.45) },
			{ a = "7:2", b = "8:2", park = 3, time = wave(CHASE, 7.05) },
			{ a = "9:1", b = "10:1", park = 2, time = wave(CHASE, 9.15) },
		},
	})
end

plans[11] = function(_seed: number): Layout
	-- Cross walls slide across the lane on one beat and long walls lift out of the dividers 0.9 s later: the straight
	-- way on always ends, the real way turns through a long wall, then a cross wall, zigzagging on the gaps.
	local long = phased(CROSS, -0.9 / periodOf(CROSS))
	local across = phased(CROSS, 0)
	return maze({
		rows = 9,
		entry = 2,
		exit = 2,
		chains = {
			"1:2 2:2 2:1 3:1 4:1 4:2 5:2 6:2 6:3 7:3 8:3 8:2 9:2",
			"2:2 3:2", -- the straight ways on end
			"4:1 5:1",
			"6:2 7:2",
			"8:3 9:3",
		},
		doors = {
			{ a = "1:2", b = "2:2", park = 1, time = across } :: DoorSpec,
			{ a = "2:2", b = "2:1", lift = true, time = long },
			{ a = "3:1", b = "4:1", park = 2, time = across },
			{ a = "4:1", b = "4:2", lift = true, time = long },
			{ a = "4:2", b = "5:2", park = 3, time = across },
			{ a = "6:2", b = "6:3", lift = true, time = long },
			{ a = "6:3", b = "7:3", park = 2, swap = true, time = across },
			{ a = "8:3", b = "8:2", lift = true, time = long },
			{ a = "8:2", b = "9:2", park = 1, time = across },
		},
	})
end

-- The generator's examples on the variants page, each its fixed seed.
local EXAMPLES: { { seed: number, tier: string, opts: GenOpts } } = {
	{ seed = 1104, tier = "easy", opts = { rows = 5, walls = 4, dead = 0, beats = "shared" } },
	{ seed = 2290, tier = "easy", opts = { rows = 6, walls = 4, dead = 0, beats = "shared", turny = true } },
	{ seed = 3817, tier = "medium", opts = { rows = 8, walls = 6, dead = 1, beats = "two", early = true } },
	{ seed = 4472, tier = "medium", opts = { rows = 9, walls = 7, dead = 2, beats = "own" } },
	{ seed = 5903, tier = "hard", opts = { rows = 12, walls = 9, dead = 3, beats = "own", chaser = false } },
	{ seed = 6631, tier = "hard", opts = { rows = 10, walls = 7, dead = 2, beats = "own", chaser = true } },
}
for i, ex in EXAMPLES do
	plans[11 + i] = function(_seed: number): Layout
		return (generate(ex.seed, ex.tier, ex.opts))
	end
end

fallback = {
	easy = function()
		return plans[2](1)
	end,
	medium = function()
		return plans[5](1)
	end,
	hard = function()
		return plans[10](1)
	end,
}

local NAMES = {
	{ "Swap Sides", "easy" },
	{ "Breathing Walls", "easy" },
	{ "Stop and Go", "easy" },
	{ "Lookout Maze", "easy" },
	{ "Domino Doors", "medium" },
	{ "Lane Change", "medium" },
	{ "Rewire", "medium" },
	{ "Pull the Plug", "medium" },
	{ "Climbing Maze", "medium" },
	{ "The Chaser", "hard" },
	{ "Crossfire", "hard" },
	{ "Seed: First Steps", "easy" },
	{ "Seed: Side Steps", "easy" },
	{ "Seed: Fork", "medium" },
	{ "Seed: Own Beats", "medium" },
	{ "Seed: Long Haul", "hard" },
	{ "Seed: Hunted", "hard" },
}

M.variants = {}
for i, nt in NAMES do
	local plan = plans[i]
	table.insert(M.variants, {
		name = nt[1],
		tier = nt[2],
		build = function(seed: number): Kit.Section
			return build(plan(seed))
		end,
	})
end

M.generator = {
	tiers = { "easy", "medium", "hard" },
	examples = #EXAMPLES,
	build = function(seed: number, tier: string): Kit.Section
		local _, section = generate(seed, tier)
		return section
	end,
}

-- The layout behind a variant (index; 0 = the generator with `tier`) and seed, built: for the specs' solver.
function M.layoutOf(variant: number, seed: number, tier: string?): (Layout, Kit.Section)
	if variant == 0 then
		return generate(seed, tier or "easy")
	end
	local L = plans[variant](seed)
	return L, build(L)
end

return M
