--!strict
--[[
	Arrow Maze (obby idea 23, docs/obby-variants/23.json; contract/obby-sections.md)

	A grid of 8 x 8 belt cells, three lanes across (z = -8, 0, 8) and 6..10 columns along the course. Every belt
	pushes one way (`conveyor`, arrows on it; double chevrons on fast belts); rest cells are raised jelly islands
	(ISLAND studs up, no arrows) where you stop and read; red cells are goo pits (a `hazard` just under the floor);
	pink cells are turning belts (`turn`: they run their arrow's way, then the other way). Belts that point off the
	lane edge, into a pit or into a red wall are dumps. A belt that runs you into a jelly wall or an island's side pins
	you there: a free stop to pick the next belt from. The exit ledge sits EXIT_HOP studs over the last column: a hop
	up to the flag.

	Holding forward never clears a maze (contract §10): the islands are ledges you have to hop onto, the dumps carry a
	walker off the lane or into goo, and the exit is a ledge (tests/obby/ArrowMaze.spec checks the maze without the
	exit hop as well).

	Layouts are three strings (lane 1 = left / -z, lane 2 = middle, lane 3 = right / +z), one character a column:
	  > < ^ v   belt pushing forward / back / left (-z) / right (+z) at the layout's `speed`
	  F B U D   the same at the `fast` speed (double chevrons)
	  T S s     turning belt (pink) starting forward / left / right, reversing past `turn.duty` of `turn.period`
	  .         rest island (raised ISLAND studs)      o   flat rest cell
	  x         red goo cell (bulges a little)         ~   goo trench (just under the floor: jump it)
	  _         hole
	Convention: a turning belt's first way (cycle < duty) is always the way the route wants it, so its window is
	duty * period (the spec bounds it per tier).

	`M.solve(layout)` is the cell model the generator keeps a layout by (and the spec checks every variant with): a
	belt carries you to the cell its arrow points at, an island, a flat rest cell, a wall stop or a ledge stop is a
	free choice, a slow belt (<= WEAK) lets you step off sideways, any belt lets you hop up onto a raised neighbour
	beside it, and riding forward you can jump one cell. It is stricter than the real game, so a layout it solves is
	solvable.
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

local CELL = 8 -- a cell is 8 x 8 studs
local LANE_Z = { -8, 0, 8 }
local ENTRY = 6 -- the entry pad before the grid
local EXIT = 6 -- the exit ledge after it
local ISLAND = 2.5 -- a rest island's top over its belts: a ledge you hop onto, not one you walk up
local EXIT_HOP = 3 -- the exit ledge over the last column
local STEP = 1 -- a ledge up to this high is walked onto (carried over); higher stops you against it
local RISE = Kit.RISE_MAX -- the highest ledge a hop gets onto
local WEAK = 10 -- a belt this slow lets you walk off it sideways
local RED_WALL_H = 8 -- a red wall: taller than a jump
local RED_WALL_T = 2
local PIT_TOP = 0.2 -- a goo cell bulges this far over the floor: not a floor, and touching its edge counts

-- Belt speeds per tier (studs / s), shifted up a notch from the drafts (contract §10).
local SPEED = { easy = 10, medium = 14, hard = 18 }

type Dir = { number } -- { dc, dl }: columns forward, lanes right

local DIRS: { [string]: Dir } = {
	[">"] = { 1, 0 },
	["<"] = { -1, 0 },
	["^"] = { 0, -1 },
	["v"] = { 0, 1 },
	F = { 1, 0 },
	B = { -1, 0 },
	U = { 0, -1 },
	D = { 0, 1 },
	T = { 1, 0 },
	S = { 0, -1 },
	s = { 0, 1 },
}
local FAST = { F = true, B = true, U = true, D = true }
local TURNS = { T = true, S = true, s = true }

export type Wall = { any } -- { col, lane, edge ("x+" | "z-" | "z+"), red? }

export type Layout = {
	lanes: { string },
	speed: number,
	fast: number?, -- F B U D
	back: number?, -- < (default speed): wrong-way belts you can't walk up
	turnSpeed: number?, -- T S s (default speed)
	speedAt: ((col: number, lane: number, ch: string) -> number?)?, -- per-cell override
	widths: { number }?, -- per column length (default CELL)
	base: ((col: number, lane: number) -> number)?, -- floor top per cell (default 0)
	walls: { Wall }?,
	turn: { period: number, duty: number, phases: { number }? }?,
	exitHop: number?,
}

export type Cell = {
	ch: string,
	col: number,
	lane: number,
	x0: number,
	x1: number,
	base: number,
	top: number,
	kind: string, -- "belt" | "turn" | "rest" | "red" | "hole"
	dir: Dir?,
	speed: number,
}

export type Grid = {
	cols: number,
	cells: { { Cell } }, -- cells[col][lane]
	gridEnd: number,
	exitTop: number,
	walls: { [string]: string }, -- "c,l,dc,dl" -> "jelly" | "red": blocks moving that way from (c, l)
	layout: Layout,
}

local M = {}
M.id = "ArrowMaze"
M.name = "Arrow Maze"
M.idea = 23
M.ISLAND = ISLAND
M.EXIT_HOP = EXIT_HOP
M.CELL = CELL

local function kindOf(ch: string): string
	if TURNS[ch] then
		return "turn"
	elseif DIRS[ch] then
		return "belt"
	elseif ch == "." or ch == "o" then
		return "rest"
	elseif ch == "x" or ch == "~" then
		return "red"
	elseif ch == "_" then
		return "hole"
	end
	error(`ArrowMaze: unknown cell {ch}`)
end

local function wallKey(c: number, l: number, dc: number, dl: number): string
	return `{c},{l},{dc},{dl}`
end

-- The cells, walls and exit of a layout.
function M.parse(layout: Layout): Grid
	local lanes = layout.lanes
	assert(#lanes == 3, "ArrowMaze: three lanes")
	local cols = #lanes[1]
	assert(#lanes[2] == cols and #lanes[3] == cols, "ArrowMaze: lanes of one length")
	local cells: { { Cell } } = {}
	local x = ENTRY
	for c = 1, cols do
		local w = if layout.widths then layout.widths[c] else CELL
		cells[c] = {}
		for l = 1, 3 do
			local ch = string.sub(lanes[l], c, c)
			local kind = kindOf(ch)
			local base = if layout.base then layout.base(c, l) else 0
			local speed = if FAST[ch]
				then layout.fast or layout.speed
				elseif TURNS[ch] then layout.turnSpeed or layout.speed
				elseif ch == "<" then layout.back or layout.speed
				else layout.speed
			if layout.speedAt then
				speed = layout.speedAt(c, l, ch) or speed
			end
			cells[c][l] = {
				ch = ch,
				col = c,
				lane = l,
				x0 = x,
				x1 = x + w,
				base = base,
				top = if ch == "." then base + ISLAND else base,
				kind = kind,
				dir = DIRS[ch],
				speed = speed,
			}
		end
		x += w
	end
	local walls: { [string]: string } = {}
	for _, w in (layout.walls or {}) :: { Wall } do
		local c, l, edge, red = w[1] :: number, w[2] :: number, w[3] :: string, w[4] == true
		local kind = if red then "red" else "jelly"
		local dc, dl = 0, 0
		if edge == "x+" then
			dc = 1
		elseif edge == "z-" then
			dl = -1
		else
			dl = 1
		end
		walls[wallKey(c, l, dc, dl)] = kind
		walls[wallKey(c + dc, l + dl, -dc, -dl)] = kind
	end
	local lastBase = -math.huge
	for l = 1, 3 do
		lastBase = math.max(lastBase, cells[cols][l].base)
	end
	return {
		cols = cols,
		cells = cells,
		gridEnd = x,
		exitTop = lastBase + (layout.exitHop or EXIT_HOP),
		walls = walls,
		layout = layout,
	}
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

-- Merged runs of equal cells along each lane: { lane, c0, c1 }, in column then lane order.
local function runsOf(g: Grid): { { number } }
	local runs = {}
	for l = 1, 3 do
		local c = 1
		while c <= g.cols do
			local a = g.cells[c][l]
			local c1 = c
			while c1 < g.cols do
				local b = g.cells[c1 + 1][l]
				local same = b.ch == a.ch and b.base == a.base and b.speed == a.speed and not TURNS[a.ch]
				if not same or g.walls[wallKey(c1, l, 1, 0)] then
					break
				end
				c1 += 1
			end
			table.insert(runs, { l, c, c1 })
			c = c1 + 1
		end
	end
	table.sort(runs, function(p, q)
		if p[2] ~= q[2] then
			return p[2] < q[2]
		end
		return p[1] < q[1]
	end)
	return runs
end

-- True when every floor part touches an earlier one (the order the section lists them): the shared makeable check
-- walks steps in that order.
function M.linked(layout: Layout): boolean
	local g = M.parse(layout)
	local startOf: { [string]: number } = {}
	local runs = runsOf(g)
	for _, run in runs do
		for c = run[2], run[3] do
			startOf[`{c},{run[1]}`] = run[2]
		end
	end
	local function floorAt(c: number, l: number): boolean
		if l < 1 or l > 3 or c < 1 or c > g.cols then
			return false
		end
		local kind = g.cells[c][l].kind
		return kind ~= "red" and kind ~= "hole"
	end
	for _, run in runs do
		local l, c0 = run[1], run[2]
		if floorAt(c0, l) and c0 > 1 then
			local ok = floorAt(c0, l - 1) or (floorAt(c0, l + 1) and startOf[`{c0},{l + 1}`] < c0)
			for dl = -1, 1 do
				ok = ok or floorAt(c0 - 1, l + dl)
			end
			if not ok then
				return false
			end
		end
	end
	return true
end

-- The section of a layout.
function M.grid(layout: Layout): Kit.Section
	local g = M.parse(layout)
	local parts: { Kit.Part } = {}
	table.insert(parts, Kit.slab(ENTRY / 2, 0, 0, ENTRY, Kit.WIDTH, "jelly", { tone = 3 }))
	local turnIndex = 0
	local turn = layout.turn
	for _, run in runsOf(g) do
		local l, c0, c1 = run[1], run[2], run[3]
		local a, b = g.cells[c0][l], g.cells[c1][l]
		local cx, len, z = (a.x0 + b.x1) / 2, b.x1 - a.x0, LANE_Z[l]
		if a.kind == "belt" or a.kind == "turn" then
			local d = a.dir :: Dir
			local v = { d[1] * a.speed, 0, d[2] * a.speed }
			if a.kind == "turn" then
				assert(turn, "ArrowMaze: a turning belt needs layout.turn")
				turnIndex += 1
				local phases = turn.phases or {}
				table.insert(
					parts,
					Kit.slab(cx, a.top, z, len, CELL, "jelly", {
						tone = 1,
						conveyor = v,
						marker = "arrows",
						motion = {
							kind = "turn",
							period = turn.period,
							duty = turn.duty,
							phase = phases[turnIndex] or 0,
						},
					})
				)
			else
				local tone = if d[1] > 0 or d[2] > 0 then 1 else 2
				table.insert(
					parts,
					Kit.slab(cx, a.top, z, len, CELL, "belt", {
						tone = tone,
						conveyor = v,
						marker = if FAST[a.ch] then "chevrons" else "arrows",
					})
				)
			end
		elseif a.kind == "rest" then
			table.insert(parts, Kit.slab(cx, a.top, z, len, CELL, "jelly", { tone = 2 }))
		elseif a.kind == "red" then
			local top = if a.ch == "~" then a.top - PIT_TOP else a.top + PIT_TOP
			table.insert(parts, Kit.hazard({ len, 1, CELL }, { cx, top - 0.5, z }))
		end
	end
	for _, w in (layout.walls or {}) :: { Wall } do
		local c, l, edge, red = w[1] :: number, w[2] :: number, w[3] :: string, w[4] == true
		local cell = g.cells[c][l]
		local base = cell.base
		local thick = if red then RED_WALL_T else 1
		local h = if red then RED_WALL_H else Kit.WALL_HEIGHT
		local size, pos
		if edge == "x+" then
			local nb = if c < g.cols then g.cells[c + 1][l].base else base
			base = math.max(base, nb)
			size, pos = { thick, h, CELL }, { cell.x1, base + h / 2, LANE_Z[l] }
		else
			local side = if edge == "z-" then -1 else 1
			local z = LANE_Z[l] + side * CELL / 2
			z = math.clamp(z, -Kit.HALF + thick / 2, Kit.HALF - thick / 2)
			size, pos = { cell.x1 - cell.x0, h, thick }, { (cell.x0 + cell.x1) / 2, base + h / 2, z }
		end
		if red then
			table.insert(parts, Kit.hazard(size, pos))
		else
			table.insert(parts, Kit.prop(size, pos, "jelly", { tone = 3 }))
		end
	end
	local length = g.gridEnd + EXIT
	table.insert(parts, Kit.slab(g.gridEnd + EXIT / 2, g.exitTop, 0, EXIT, Kit.WIDTH, "jelly", { tone = 3 }))
	return Kit.section(length, g.exitTop, parts)
end

---------------------------------------------------------------------------
-- The cell model
---------------------------------------------------------------------------

--[[
	True when the exit can be reached from the entry pad (see the header). States: free at a cell (you can stand there
	and pick) or carried on a belt cell the way it points. Entry is column 0 (any lane), the exit column cols + 1.
]]
function M.solve(layout: Layout): boolean
	local g = M.parse(layout)
	local cols = g.cols
	local seen: { [string]: boolean } = {}
	local queue: { { any } } = {}
	local reached = false

	local function topAt(c: number, l: number): number
		if c < 1 then
			return 0
		elseif c > cols then
			return g.exitTop
		end
		return g.cells[c][l].top
	end
	local function push(state: { any })
		local key = table.concat(state :: any, ",")
		if not seen[key] then
			seen[key] = true
			table.insert(queue, state)
		end
	end
	-- Arriving at (c, l) on foot or carried.
	local function enter(c: number, l: number)
		if l < 1 or l > 3 then
			return -- off the lane edge
		elseif c < 1 then
			push({ "free", 0, l })
			return
		elseif c > cols then
			reached = true
			return
		end
		local cell = g.cells[c][l]
		if cell.kind == "rest" then
			push({ "free", c, l })
		elseif cell.kind == "belt" then
			local d = cell.dir :: Dir
			push({ "carry", c, l, d[1], d[2] })
		elseif cell.kind == "turn" then
			local d = cell.dir :: Dir
			push({ "carry", c, l, d[1], d[2] })
			push({ "carry", c, l, -d[1], -d[2] })
		end
		-- red pits and holes: lost
	end
	local function wall(c: number, l: number, dc: number, dl: number): string?
		return g.walls[wallKey(c, l, dc, dl)]
	end

	push({ "free", 0, 2 })
	local head = 1
	while head <= #queue and not reached do
		local s = queue[head]
		head += 1
		local c, l = s[2] :: number, s[3] :: number
		local here = topAt(c, l)
		if s[1] == "free" then
			if c == 0 then
				for _, dl in { -1, 1 } do
					if l + dl >= 1 and l + dl <= 3 then
						push({ "free", 0, l + dl })
					end
				end
			end
			for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				local nc, nl = c + d[1], l + d[2]
				if nl >= 1 and nl <= 3 and nc >= 0 and not wall(c, l, d[1], d[2]) then
					if topAt(nc, nl) - here <= RISE then
						enter(nc, nl)
					end
				end
			end
		else
			local dc, dl = s[4] :: number, s[5] :: number
			local cell = g.cells[c][l]
			local nc, nl = c + dc, l + dl
			local w = wall(c, l, dc, dl)
			-- (run into a red wall: lost)
			if w == "jelly" or (not w and nl >= 1 and nl <= 3 and nc >= 0 and topAt(nc, nl) - here > STEP) then
				push({ "free", c, l }) -- pinned against a wall or a ledge
			elseif not w then
				enter(nc, nl)
			end
			for _, p in { { dl, dc }, { -dl, -dc } } do
				local pc, pl = c + p[1], l + p[2]
				if pl >= 1 and pl <= 3 and pc >= 0 and not wall(c, l, p[1], p[2]) then
					local rise = topAt(pc, pl) - here
					if (cell.speed <= WEAK and rise <= RISE) or (rise > STEP and rise <= RISE) then
						enter(pc, pl)
					end
				end
			end
			if dc == 1 and dl == 0 and c + 1 <= cols then
				-- riding forward: jump the next cell
				local jc = c + 2
				if not wall(c, l, 1, 0) and not wall(c + 1, l, 1, 0) and topAt(jc, l) - here <= RISE then
					enter(jc, l)
				end
			end
		end
	end
	return reached
end

-- Belt cells whose ride (no choices) ends lost: off the edge, in a pit, into a red wall, or round in a loop.
function M.dumps(layout: Layout): number
	local g = M.parse(layout)
	local n = 0
	for c = 1, g.cols do
		for l = 1, 3 do
			local cell = g.cells[c][l]
			if cell.kind == "belt" then
				local cc, ll = c, l
				local visited: { [string]: boolean } = {}
				local lost = false
				while true do
					local here = g.cells[cc][ll]
					if here.kind ~= "belt" then
						lost = here.kind == "red" or here.kind == "hole"
						break
					end
					local key = `{cc},{ll}`
					if visited[key] then
						lost = true
						break
					end
					visited[key] = true
					local d = here.dir :: Dir
					local w = g.walls[wallKey(cc, ll, d[1], d[2])]
					local nc, nl = cc + d[1], ll + d[2]
					if w then
						lost = w == "red"
						break
					elseif nl < 1 or nl > 3 then
						lost = true
						break
					elseif nc < 1 or nc > g.cols then
						break
					elseif g.cells[nc][nl].top - here.top > STEP then
						break
					end
					cc, ll = nc, nl
				end
				if lost then
					n += 1
				end
			end
		end
	end
	return n
end

---------------------------------------------------------------------------
-- Generator
---------------------------------------------------------------------------

export type GenOpts = { cols: number?, choices: number?, turns: number?, jumps: number?, reds: number? }

local TIER = {
	easy = { cols = { 6, 7 }, choices = 2, turns = { 0, 0 }, reds = { 1, 1 }, jumps = { 0, 0 }, dumps = 0 },
	medium = { cols = { 7, 8 }, choices = 3, turns = { 1, 1 }, reds = { 2, 2 }, jumps = { 0, 0 }, dumps = 3 },
	hard = { cols = { 9, 10 }, choices = 2, turns = { 2, 2 }, reds = { 2, 3 }, jumps = { 1, 1 }, dumps = 6 },
}
M.TIER = TIER

local TURN = {
	easy = { period = 5, duty = 0.36 },
	medium = { period = 4, duty = 1 / 3 },
	hard = { period = 3, duty = 0.36 },
}
M.TURN = TURN

local CHAR = { ["1,0"] = ">", ["-1,0"] = "<", ["0,-1"] = "^", ["0,1"] = "v" }

local function charOf(dc: number, dl: number): string
	return CHAR[`{dc},{dl}`]
end

-- Parts a section of `layout` adds, markers and all (mirrors ObbyCheck.partCount: arrows 3, chevrons 4).
function M.partCount(layout: Layout): number
	local section = M.grid(layout)
	local n = #section.parts
	for _, part in section.parts do
		if part.marker == "arrows" then
			n += 3
		elseif part.marker == "chevrons" then
			n += 4
		end
	end
	return n
end

-- One try at a layout for `tier` from `rng`; nil when it breaks a rule.
local function attempt(rng: any, tier: string, opts: GenOpts): (Layout?, { number }?)
	local t = TIER[tier]
	local cols = opts.cols or rng:int(t.cols[1], t.cols[2])
	local grid: { { string } } = { {}, {}, {} }
	local onRoute: { [string]: boolean } = {}
	-- The route: forward along a lane, now and then across to the next one.
	local route: { { number } } = {}
	local lane = rng:int(1, 3)
	local lastSwitch = -1
	for c = 1, cols do
		table.insert(route, { c, lane })
		if c < cols and c - lastSwitch >= 2 and rng:float() < 0.55 then
			local options = {}
			for _, nl in { lane - 1, lane + 1 } do
				if nl >= 1 and nl <= 3 then
					table.insert(options, nl)
				end
			end
			lane = rng:pick(options)
			table.insert(route, { c, lane })
			lastSwitch = c
		end
	end
	for i, p in route do
		local q = route[i + 1]
		local ch = if q then charOf(q[1] - p[1], q[2] - p[2]) else ">"
		grid[p[2]][p[1]] = ch
		onRoute[`{p[1]},{p[2]}`] = true
	end
	-- Choice cells: islands spread along the route (never two in a row).
	local choices = opts.choices or t.choices
	local islands: { number } = {}
	local n = #route
	for k = 1, choices do
		local i = math.clamp(math.floor(k * n / (choices + 1)) + rng:int(-1, 1), 1, n - 1)
		if islands[#islands] and i <= islands[#islands] + 1 then
			i = islands[#islands] + 2
		end
		if i <= n - 1 then
			table.insert(islands, i)
		end
	end
	if #islands < math.min(choices, 2) then
		return nil
	end
	local isIsland: { [number]: boolean } = {}
	for _, i in islands do
		local p = route[i]
		grid[p[2]][p[1]] = "."
		isIsland[i] = true
	end
	-- Turning belts right after an island, on a forward stretch.
	local turns = opts.turns or rng:int(t.turns[1], t.turns[2])
	local placed = 0
	for _, i in islands do
		if placed < turns then
			local p, q = route[i + 1], route[i + 2]
			if p and not isIsland[i + 1] and grid[p[2]][p[1]] == ">" and (q == nil or q[2] == p[2]) then
				grid[p[2]][p[1]] = "T"
				placed += 1
			end
		end
	end
	if placed < turns then
		return nil
	end
	-- A dump to jump: a forward cell between two forward belts of one lane pushes off the route.
	local jumps = opts.jumps or rng:int(t.jumps[1], t.jumps[2])
	local jumpedAt: { number }? = nil
	if jumps > 0 then
		local spots = {}
		for i = 2, n - 1 do
			local a, b, c = route[i - 1], route[i], route[i + 1]
			if
				a[2] == b[2]
				and b[2] == c[2]
				and grid[a[2]][a[1]] == ">"
				and grid[b[2]][b[1]] == ">"
				and not isIsland[i + 1]
			then
				table.insert(spots, i)
			end
		end
		if #spots == 0 then
			return nil
		end
		local i = rng:pick(spots)
		local b = route[i]
		local outward = if b[2] == 1 then "^" elseif b[2] == 3 then "v" else rng:pick({ "^", "v" })
		grid[b[2]][b[1]] = outward
		onRoute[`{b[1]},{b[2]}`] = false
		jumpedAt = b
	end
	-- Decoys: runs of off-route cells, each one belt (or a pit).
	local reds = opts.reds or rng:int(t.reds[1], t.reds[2])
	for l = 1, 3 do
		local c = 1
		while c <= cols do
			if grid[l][c] == nil then
				local c1 = c
				while c1 < cols and grid[l][c1 + 1] == nil and c1 - c < 2 do
					c1 += 1
				end
				local options: { string }
				if tier == "easy" then
					-- wrong picks loop back: back belts, or a push towards the middle lane
					options = if l == 2 then { "<" } else { "<", if l == 1 then "v" else "^" }
				else
					options = { "<", "^", "v", if l == 1 then "^" elseif l == 3 then "v" else "<" }
				end
				local ch = rng:pick(options)
				for k = c, c1 do
					grid[l][k] = ch
				end
				c = c1 + 1
			else
				c += 1
			end
		end
	end
	-- Red pits on off-route cells (not the first column: the entry is no place for a pit).
	local offRoute = {}
	for c = 2, cols do
		for l = 1, 3 do
			local ch = grid[l][c]
			if not onRoute[`{c},{l}`] and DIRS[ch] and not (jumpedAt and jumpedAt[1] == c and jumpedAt[2] == l) then
				table.insert(offRoute, { c, l })
			end
		end
	end
	for _ = 1, reds do
		if #offRoute == 0 then
			break
		end
		local k = rng:int(1, #offRoute)
		local p = table.remove(offRoute, k) :: { number }
		grid[p[2]][p[1]] = "x"
	end
	local lanes = {}
	for l = 1, 3 do
		lanes[l] = table.concat(grid[l])
	end
	local phases = {}
	for k = 1, turns do
		phases[k] = math.floor(rng:float() * 100) / 100
	end
	local layout: Layout = {
		lanes = lanes,
		speed = SPEED[tier],
		back = math.max(SPEED[tier], 18),
		turn = if turns > 0 then { period = TURN[tier].period, duty = TURN[tier].duty, phases = phases } else nil,
	}
	-- The rules: solvable, enough belts away from the route, the tier's dumps, the part budget.
	if not M.solve(layout) or not M.linked(layout) then
		return nil
	end
	local belts, away = 0, 0
	for l = 1, 3 do
		for c = 1, cols do
			local ch = string.sub(lanes[l], c, c)
			if DIRS[ch] then
				belts += 1
				if not onRoute[`{c},{l}`] then
					away += 1
				end
			end
		end
	end
	if away * 3 < belts then
		return nil
	end
	local dumps = M.dumps(layout)
	if (tier == "easy" and dumps > 0) or dumps < t.dumps then
		return nil
	end
	if M.partCount(layout) > 78 then
		return nil
	end
	local flat = {}
	for _, p in route do
		table.insert(flat, p[1] * 10 + p[2])
	end
	return layout, flat
end

-- Hand-made fallbacks when 50 tries fail (the spec checks seeds 1..300 never need them).
local FALLBACK: { [string]: Layout } = {}

-- The layout the generator makes for `seed` and `tier` (deterministic), and whether it fell back.
function M.generate(seed: number, tier: string, opts: GenOpts?): (Layout, boolean)
	local rng = Kit.rng(seed * 7919 + (if tier == "easy" then 1 elseif tier == "medium" then 2 else 3))
	for _ = 1, 50 do
		local layout = attempt(rng, tier, opts or {})
		if layout then
			return layout, false
		end
	end
	return FALLBACK[tier], true
end

---------------------------------------------------------------------------
-- Variants
---------------------------------------------------------------------------

-- A wall on edge "x+" (the cell's far end), "z-" or "z+" (its side) of cell (col, lane); red = a hazard wall.
local function edgeWall(c: number, l: number, edge: string, red: boolean?): Wall
	return { c, l, edge, red == true }
end

local E, MED, H = SPEED.easy, SPEED.medium, SPEED.hard
local BACK = 18 -- wrong-way belts on the easy and medium mazes: faster than you walk, they carry you back

-- Every hand-made variant's layout, in the design file's order (the spec solves each one).
local LAYOUTS: { Layout } = {
	-- 1 Follow the Flow: the side lanes push you into the middle, which carries you on, then bends left for two cells
	-- and back; two goo trenches across the lane to jump on the way (the draft had no hazard: §10).
	{
		lanes = { "vvv~>>v~v", ">>>~^>>~>", "^^^~^^^~^" },
		speed = E,
		widths = { 8, 8, 8, 5, 8, 8, 8, 6, 8 },
	},
	-- 2 Wrong Way Middle: the middle runs back faster than you walk; ride the left lane to the island, drop onto the
	-- back belt behind it (it pins you against the island) and step across to the right lane past its two-cell pit.
	{
		lanes = { ">>>xx>>", "<<.<<<<", ">xx>>>>" },
		speed = E,
		back = BACK,
	},
	-- 3 Rest Stops: islands every third cell; from each, the side belt that hops you forward; the other side pins you
	-- back against the island, the goo corners are the price of a careless step.
	{
		lanes = { "x>vx>vx", ".^>.^>.", "^<<^<<^" },
		speed = E,
		back = BACK,
	},
	-- 4 Side Step: two goo cells block the middle; a sideways belt drops you into a low side road round them, then
	-- pushes you back against the middle's ledge to hop out.
	{
		lanes = { "x>>>>v", ">^xox>", "<<<<<<" },
		speed = E,
		back = BACK,
		base = function(_c, l)
			return if l == 1 then -ISLAND else 0
		end,
	},
	-- 5 Loop Back: every wrong belt carries you back towards an island; walk forward across the sideways pushers.
	{
		lanes = { "v<<v<<x", ".^>>.^>", "^<<^<<x" },
		speed = E,
		back = BACK,
	},
	-- 6 Dead End Belt: the obvious forward belt ends at a red wall; the real way is the sideways belt that pushes you
	-- against the raised side road, which has two goo pits to jump while it carries you. The back lane outruns you.
	{
		lanes = { "x>>x>>x>", ".^>>>>>x", "<<<<<<<<" },
		speed = MED,
		back = BACK,
		base = function(_c, l)
			return if l == 1 then ISLAND else 0
		end,
		walls = { edgeWall(7, 2, "x+", true) },
	},
	-- 7 Edge Dumpers: the outer lanes shove you off the edge or into goo; island to island through the middle.
	{
		lanes = { "^^>v^^>v", ".>^.>>^.", "vvxvvvxv" },
		speed = MED,
	},
	-- 8 Fast Lane, Slow Lane: the fast lane runs straight at goo, hop off sideways onto the one island at full speed;
	-- or the slow lane: hop its island, jump its pit.
	{
		lanes = { "FFFFFFxx", "<<<<<.>>", ">>.>x>>>" },
		speed = MED,
		fast = 20,
		speedAt = function(_c, l, ch)
			if ch == "<" then
				return 18
			end
			return if l == 3 then 8 else nil
		end,
	},
	-- 9 Turn Signal: two pink belts swap forward and back; wait on the island before each until it points your way.
	-- The second one feeds a pit: jump it while the belt runs forward. The back lane outruns you (no slow walk round).
	{
		lanes = { "vvvvvvv", ".T>.Tx>", "x<<<<<x" },
		speed = MED,
		back = BACK,
		turn = { period = TURN.medium.period, duty = TURN.medium.duty, phases = { 0, 0.5 } },
	},
	-- 10 Belt Stairs: every column a step up; forward belts pin you at the next riser, sideways ones shove you while
	-- you hop, back belts drop you down a step.
	{
		lanes = { "v<<v<<", ">^>>^>", "<<^<<^" },
		speed = MED,
		back = BACK,
		base = function(c, _l)
			return 2 * c
		end,
		exitHop = 2,
	},
	-- 11 Wall Stops: no rest cells; each belt pins you against a jelly wall, pick the next belt from there; the belts
	-- that skip the walls dump you; a goo trench on the second ride to jump.
	{
		lanes = { "^^>>~>^^", ">>>vv>>>", "vvvxxxvv" },
		speed = MED,
		walls = { edgeWall(3, 2, "x+"), edgeWall(6, 1, "x+") },
	},
	-- 12 Rush Hour: fast belts, nearly every cell a dump, one snaking route with only two islands to stop and read.
	{
		lanes = { "^^>>v^^^>>", ".>^vv.v>^^", "vvvv>^>^vv" },
		speed = H,
		walls = {
			edgeWall(3, 2, "z+", true),
			edgeWall(8, 1, "z+", true),
			edgeWall(5, 1, "x+", true),
			edgeWall(4, 3, "x+", true),
		},
	},
	-- 13 Jump the Wrong One: single side-pushers sit in the only lane, goo on both sides; jump each from the belt
	-- before while you read the next arrow. Four of them, two with a single landing cell before the next.
	{
		lanes = { "xxxxxxxxxxx", ">>v>^>>v>^>", "xxxxxxxxxxx" },
		speed = 20,
	},
	-- 14 Fast Lane Gauntlet: fast belts feed two pink belts that swap sides; arrive when one points to the lane that
	-- goes on, or it throws you over the edge.
	{
		lanes = { "^^FD^^^^", "FFS.FFsF", "vvvvvvFF" },
		speed = H,
		fast = 22,
		turnSpeed = 22,
		turn = { period = TURN.hard.period, duty = TURN.hard.duty, phases = { 0, 0.5 } },
	},
}

FALLBACK.easy = LAYOUTS[3]
FALLBACK.medium = LAYOUTS[7]
FALLBACK.hard = LAYOUTS[12]

-- The generator's examples on the design page: a fixed seed and its numbers.
local SEEDS: { { any } } = {
	{ "Seed A: Two Picks", "easy", 11, { cols = 6, choices = 2 } },
	{ "Seed B: Long Carry", "easy", 27, { cols = 7, choices = 2, reds = 1 } },
	{ "Seed C: Three Picks", "medium", 42, { cols = 8, choices = 3, turns = 0 } },
	{ "Seed D: One Turner", "medium", 58, { cols = 8, turns = 1 } },
	{ "Seed F: Snake", "hard", 91, { cols = 10, choices = 2, turns = 0, reds = 3 } },
	{ "Seed G: Timed Pair", "hard", 104, { cols = 9, turns = 2, jumps = 1 } },
}

local NAMES = {
	{ "Follow the Flow", "easy" },
	{ "Wrong Way Middle", "easy" },
	{ "Rest Stops", "easy" },
	{ "Side Step", "easy" },
	{ "Loop Back", "easy" },
	{ "Dead End Belt", "medium" },
	{ "Edge Dumpers", "medium" },
	{ "Fast Lane, Slow Lane", "medium" },
	{ "Turn Signal", "medium" },
	{ "Belt Stairs", "medium" },
	{ "Wall Stops", "medium" },
	{ "Rush Hour", "hard" },
	{ "Jump the Wrong One", "hard" },
	{ "Fast Lane Gauntlet", "hard" },
}

-- The layout of variant `i` (1-based, as M.variants) for `seed`.
function M.layoutOf(i: number, _seed: number): Layout
	if i <= #LAYOUTS then
		return LAYOUTS[i]
	end
	local s = SEEDS[i - #LAYOUTS]
	return (M.generate(s[3], s[2], s[4]))
end

M.variants = {} :: { Kit.Variant }
for i, n in NAMES do
	table.insert(M.variants, {
		name = n[1],
		tier = n[2],
		build = function(seed: number): Kit.Section
			return M.grid(M.layoutOf(i, seed))
		end,
	})
end
for k, s in SEEDS do
	local i = #LAYOUTS + k
	table.insert(M.variants, {
		name = s[1],
		tier = s[2],
		build = function(seed: number): Kit.Section
			return M.grid(M.layoutOf(i, seed))
		end,
	})
end

M.generator = {
	tiers = { "easy", "medium", "hard" },
	build = function(seed: number, tier: string): Kit.Section
		return M.grid((M.generate(seed, tier)))
	end,
	examples = 6,
}

return M
