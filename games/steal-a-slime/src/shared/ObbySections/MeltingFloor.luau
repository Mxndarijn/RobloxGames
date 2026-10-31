--!strict
--[[
	Melting Floor (obby idea 2, docs/obby-variants/2.json; contract/obby-sections.md)

	Tiles crack, darken and drop away a moment after you land on them (`melt`, ObbyFx plays the cracks and the crack
	ticks): you can never stand still. Spreading tiles (darker tone, `cracks` marker) start their neighbours melting
	`spread` s after they are gone; Burnt Bridge tiles melt when you step off them. Variants are appended, never
	reordered (a pick stores the index); 17..22 are fixed Melt Grid draws and M.generator draws fresh grids per seed.

	Timing: the checks don't time melts, so every hold is set from a runner model (tests/obby/MeltingFloor.spec): a
	jump carries about 90 % of its full reach (less going up), a re-jump costs 0.1 s, so the time a runner must stand
	on a tile is (its length along the way - what the jump in carried over) / 16 + 0.1. `holdFor` computes it and the
	grids never set a hold under it. Every walking line meets a hole of 5 studs (a walker drops through 4.4 or more;
	the grids space their columns 5 apart), a lane change it misses, or a floor that melts away under a walker before
	it crosses (the ladder), so holding forward never clears a variant, and jumping on every landing doesn't either.

	Kit gaps (simplified, see the variants): no shrink or flip started by landing (Shrinking Puddles breathe on a
	clock, Flip-Over flips on a clock and shows its red side as a hazard plate while the tile is gone), no part with two
	motions (Melting Ferries: the ferries slide, the stones between them melt).
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

type Part = Kit.Part

local ENTRY = 6 -- entry pad length (full lane width)
local EXIT = 6 -- exit pad length
local REJUMP = 0.1 -- seconds from landing to the next take-off when you don't need to run
local REACH = 0.9 -- share of a full running jump a runner counts on
local MARGIN = 0.03 -- seconds a melting route tile must outlast the runner on it

local function melt(delay: number, away: number, extra: { [string]: any }?): Kit.Motion
	local m: { [string]: any } = { kind = "melt", delay = delay, away = away }
	if extra then
		for k, v in extra do
			m[k] = v
		end
	end
	return m :: any
end

local function entry(parts: { Part })
	table.insert(parts, Kit.slab(ENTRY / 2, 0, 0, ENTRY, Kit.WIDTH, "jelly", { tone = 1 }))
end

-- The exit pad from x0, top `top`; returns the section length.
local function exit(parts: { Part }, x0: number, top: number, z: number?, wide: number?): number
	table.insert(parts, Kit.slab(x0 + EXIT / 2, top, z or 0, EXIT, wide or Kit.WIDTH, "jelly", { tone = 3 }))
	return x0 + EXIT
end

-- How far (flat) a running jump that lands `rise` studs higher carries a runner.
local function jumpReach(rise: number): number
	local v, g = Kit.JUMP_SPEED, Kit.GRAVITY
	local disc = v * v - 2 * g * math.max(rise, 0)
	if disc < 0 then
		return 0
	end
	local t = (v + math.sqrt(disc)) / g
	return Kit.WALK * t * REACH
end

-- Seconds a runner must stand on a tile `long` studs along the way it runs, reached over a `gap` stud hole and
-- `rise` studs up.
local function holdFor(long: number, gap: number, rise: number): number
	local carried = math.max(0, jumpReach(rise) - gap)
	return math.max(0, long - carried) / Kit.WALK + REJUMP
end

-- Rounds a hold up to the next 0.05 s.
local function roundUp(x: number): number
	return math.ceil(x * 20 - 1e-6) / 20
end

local function topOf(p: Part): number
	return p.pos[2] + p.size[2] / 2
end

-- Flat gap between two parts at rest (discs by their circles).
local function gapOf(a: Part, b: Part): number
	if a.shape == "disc" and b.shape == "disc" then
		local d = math.sqrt((a.pos[1] - b.pos[1]) ^ 2 + (a.pos[3] - b.pos[3]) ^ 2)
		return math.max(0, d - a.size[1] / 2 - b.size[1] / 2)
	end
	local ax0, ax1, _, _, az0, az1 = Kit.bounds(a)
	local bx0, bx1, _, _, bz0, bz1 = Kit.bounds(b)
	local dx = math.max(0, bx0 - ax1, ax0 - bx1)
	local dz = math.max(0, bz0 - az1, az0 - bz1)
	return math.sqrt(dx * dx + dz * dz)
end

--[[
	The runner model over the main route: it lands on each step after a jump, runs what the jump didn't carry, takes
	off again (REJUMP). Every melt tile starts on landing or `spread` s after a spreading neighbour is gone. Returns
	nil when every melting route tile is still there when the runner leaves it, else the first one that is not.
]]
local function runnerProblem(section: Kit.Section): (number?, boolean)
	local parts = section.parts
	local steps: { number } = {}
	for i, p in parts do
		if p.step and p.route == nil then
			table.insert(steps, i)
		end
	end
	local land: { [number]: number } = {}
	local leave: { [number]: number } = {}
	local t = 0
	for k, i in steps do
		local p = parts[i]
		if k == 1 then
			land[i], leave[i] = 0, 0
		else
			local from = steps[k - 1]
			if gapOf(parts[from], p) > Kit.GAP_MAX then
				local best = math.huge
				for j = 1, k - 1 do
					local g = gapOf(parts[steps[j]], p)
					if g < best then
						best, from = g, steps[j]
					end
				end
			end
			local rise = topOf(p) - topOf(parts[from])
			local v, g = Kit.JUMP_SPEED, Kit.GRAVITY
			local air = (v + math.sqrt(math.max(v * v - 2 * g * math.max(rise, 0), 0))) / g
			land[i] = t + air
			local into = math.max(0, jumpReach(rise) - gapOf(parts[from], p))
			local prev, nxt = parts[steps[k - 1]], parts[steps[math.min(k + 1, #steps)]]
			local dx, dz = math.abs(nxt.pos[1] - prev.pos[1]), math.abs(nxt.pos[3] - prev.pos[3])
			local long = if dx >= dz then p.size[1] else p.size[3]
			leave[i] = land[i] + math.max(0, long - into) / Kit.WALK + REJUMP
			t = leave[i]
		end
	end
	local start: { [number]: number } = {}
	for _, i in steps do
		local m = parts[i].motion
		if m and m.kind == "melt" and m.on ~= "leave" then
			start[i] = land[i]
		end
	end
	for _ = 1, #parts do
		local changed = false
		for i, s in start do
			local m = parts[i].motion :: Kit.Motion
			for _, n in (m.next or {}) :: { number | string } do
				local j = n :: number
				local at = s + (m.delay or 0) + (m.spread or 0)
				if start[j] == nil or at < start[j] - 1e-9 then
					start[j] = at
					changed = true
				end
			end
		end
		if not changed then
			break
		end
	end
	for k, i in steps do
		local m = parts[i].motion
		if k > 1 and k < #steps and m and m.kind == "melt" and m.on ~= "leave" then
			if start[i] + (m.delay or 0) < leave[i] + MARGIN then
				return i, start[i] < land[i] - 1e-9
			end
		end
	end
	return nil, false
end

-- Until the runner model outruns every melt (0.05 s at a time): a tile that goes under the runner by itself holds
-- longer, a spreading melt that catches it up spreads slower. A grid is always solvable.
local function settle(section: Kit.Section): Kit.Section
	for _ = 1, 80 do
		local i, bySpread = runnerProblem(section)
		if i == nil then
			return section
		end
		if bySpread then
			for _, p in section.parts do
				local m = p.motion
				if m and m.kind == "melt" and m.spread then
					m.spread = math.floor((m.spread + 0.05) * 100 + 0.5) / 100
				end
			end
		else
			local m = section.parts[i].motion :: Kit.Motion
			m.delay = math.floor(((m.delay or 0) + 0.05) * 100 + 0.5) / 100
		end
	end
	error(`MeltingFloor: a grid the runner can't outrun (part {runnerProblem(section)})`)
end

---------------------------------------------------------------------------
-- Melt grid (variants 17..22 and the generator)
---------------------------------------------------------------------------

export type GridConfig = {
	seed: number,
	cols: number, -- columns along the course (5..7)
	rows: number, -- 2 (10-wide tiles) or 3 (8-wide tiles)
	tile: number, -- tile length along the course (8 or 10)
	gap: number, -- hole between columns (4..5)
	holes: number, -- off-route cells left out
	hold: number, -- seconds a tile holds (raised per route tile to what the runner model needs)
	away: number, -- seconds gone (-1: until the reset)
	spreading: number, -- spreading tiles (-1: every tile)
	spread: number?, -- seconds after a spreading tile is gone its neighbours start melting
	rise: number, -- studs each column climbs
	bends: number?, -- at most this many row changes along the route (nil: any)
}

local function buildGrid(cfg: GridConfig): Kit.Section
	local rng = Kit.rng(cfg.seed)
	local rows, cols = cfg.rows, cfg.cols
	local wide = if rows == 3 then 8 else 10
	local zs = if rows == 3 then { -8, 0, 8 } else { -6, 6 }
	local pitch = cfg.tile + cfg.gap

	-- The route: one tile per column, moving at most one row between columns.
	local route = {}
	local bends = 0
	route[1] = rng:int(1, rows)
	for c = 2, cols do
		local r = route[c - 1]
		if cfg.bends == nil or bends < cfg.bends then
			local step = rng:int(-1, 1)
			if r + step < 1 or r + step > rows then
				step = -step
			end
			r += step
		end
		if r ~= route[c - 1] then
			bends += 1
		end
		route[c] = r
	end

	-- Holes: off-route cells, shuffled.
	local off = {}
	for c = 1, cols do
		for r = 1, rows do
			if route[c] ~= r then
				table.insert(off, { c, r })
			end
		end
	end
	for i = #off, 2, -1 do
		local j = rng:int(1, i)
		off[i], off[j] = off[j], off[i]
	end
	local hole: { [number]: boolean } = {}
	for i = 1, math.min(cfg.holes, #off) do
		hole[off[i][1] * 10 + off[i][2]] = true
	end

	-- Spreading tiles.
	local cells = {}
	for c = 1, cols do
		for r = 1, rows do
			if not hole[c * 10 + r] then
				table.insert(cells, { c, r })
			end
		end
	end
	local spreads: { [number]: boolean } = {}
	if cfg.spreading < 0 then
		for _, cell in cells do
			spreads[cell[1] * 10 + cell[2]] = true
		end
	else
		local pool = table.clone(cells)
		for i = #pool, 2, -1 do
			local j = rng:int(1, i)
			pool[i], pool[j] = pool[j], pool[i]
		end
		for i = 1, math.min(cfg.spreading, #pool) do
			spreads[pool[i][1] * 10 + pool[i][2]] = true
		end
	end

	local parts: { Part } = {}
	entry(parts)
	local index: { [number]: number } = {}
	for _, cell in cells do
		local c, r = cell[1], cell[2]
		local key = c * 10 + r
		local x0 = ENTRY + cfg.gap + (c - 1) * pitch
		local top = c * cfg.rise
		local onRoute = route[c] == r
		local hold = cfg.hold
		if onRoute then
			-- what the runner model needs on this tile (the route only moves forward: its length along x)
			hold = math.max(hold, roundUp(holdFor(cfg.tile, cfg.gap, cfg.rise) + MARGIN))
		end
		local spreading = spreads[key] == true
		local extra: { [string]: any } = {
			tone = if spreading then 3 else 1 + (c + r) % 2,
			motion = melt(hold, cfg.away, if spreading then { spread = cfg.spread or 0.3 } else nil),
		}
		if spreading then
			extra.marker = "cracks"
		end
		local part = Kit.slab(x0 + cfg.tile / 2, top, zs[r], cfg.tile, wide, "tile", extra)
		if not onRoute then
			part.step = nil -- a decoy: a floor, not the path
		end
		table.insert(parts, part)
		index[key] = #parts
	end
	-- Spreading tiles melt their 4 neighbours.
	for _, cell in cells do
		local c, r = cell[1], cell[2]
		local part = parts[index[c * 10 + r]]
		if part.motion and part.motion.spread then
			local nextList = {}
			for _, d in { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } } do
				local n = index[(c + d[1]) * 10 + (r + d[2])]
				if n and math.abs(r + d[2] - r) <= 1 and r + d[2] >= 1 and r + d[2] <= rows then
					table.insert(nextList, n)
				end
			end
			part.motion.next = nextList
		end
	end
	local length = exit(parts, ENTRY + cfg.gap + cols * pitch, (cols + 1) * cfg.rise)
	return settle(Kit.section(length, (cols + 1) * cfg.rise, parts))
end

---------------------------------------------------------------------------
-- Hand-made variants
---------------------------------------------------------------------------

-- A run of melt tiles along x: `list` holds { long, wide, z, top } per tile; `gap` before each; returns the x after.
local function tileRun(
	parts: { Part },
	x: number,
	gap: number,
	list: { { number } },
	look: string,
	motionOf: (i: number) -> Kit.Motion?,
	extraOf: ((i: number) -> { [string]: any }?)?
): number
	for i, t in list do
		x += gap
		local extra: { [string]: any } = { tone = 1 + i % 2, motion = motionOf(i) }
		local more = extraOf and extraOf(i)
		if more then
			for k, v in more do
				extra[k] = v
			end
		end
		table.insert(parts, Kit.slab(x + t[1] / 2, t[4] or 0, t[3] or 0, t[1], t[2], look, extra))
		x += t[1]
	end
	return x
end

local function grid(seed: number, cfg: { [string]: any }): Kit.Section
	local full = table.clone(cfg)
	full.seed = seed
	return buildGrid(full :: any)
end

local M = {}
M.id = "MeltingFloor"
M.name = "Melting Floor"
M.idea = 2
M.holdFor = holdFor
M.buildGrid = buildGrid
M.runnerProblem = runnerProblem

M.variants = {
	{
		-- Four huge slabs over 5-stud holes, each holding 1.1 s: lots of room to land, but run straight across or drop.
		name = "Big Slabs",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local x = tileRun(parts, ENTRY, 5, { { 14, 24 }, { 14, 24 }, { 14, 24 }, { 14, 24 } }, "tile", function()
				return melt(1.1, 2.5)
			end)
			return Kit.section(exit(parts, x + 5, 0), 0, parts)
		end,
	},
	{
		-- A tile melts once you step off it (gone for this run): you can stop to think, never go back. Tightened per
		-- §10: every other tile is a hot tile (darker, cracked) that melts 1.2 s after you land on it; 5-stud holes.
		name = "Burnt Bridge",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local list = {}
			for i = 1, 6 do
				table.insert(list, { 10, 10, if i % 2 == 1 then -5 else 5 })
			end
			local x = tileRun(parts, ENTRY, 5, list, "tile", function(i)
				if i % 2 == 0 then
					return melt(1.2, 3)
				end
				return melt(0.2, -1, { on = "leave" })
			end, function(i)
				return if i % 2 == 0 then { tone = 3, marker = "cracks" } else nil
			end)
			return Kit.section(exit(parts, x + 5, 0), 0, parts)
		end,
	},
	{
		-- Two lanes zigzag left and right, each tile holds 0.9 s: a calm rhythm of side-to-side hops. The lanes
		-- sit 4 studs apart so the hop is a 4.5-stud diagonal and no walking line runs along both.
		name = "Slow Drip",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local list = {}
			for i = 1, 8 do
				table.insert(list, { 10, 10, if i % 2 == 1 then -7 else 7 })
			end
			local x = tileRun(parts, ENTRY, 2, list, "tile", function()
				return melt(0.9, 2.5)
			end)
			return Kit.section(exit(parts, x + 2, 0), 0, parts)
		end,
	},
	{
		-- A 3 x 5 field with no holes: any route works, keep moving. Three cracked tiles (they move per seed) melt
		-- their neighbours half a second after they go, so read the field and keep away from them.
		name = "Open Field",
		tier = "easy",
		build = function(seed: number): Kit.Section
			return grid(seed, {
				cols = 5,
				rows = 3,
				tile = 8,
				gap = 5,
				holes = 0,
				hold = 0.85,
				away = 3,
				spreading = 3,
				spread = 0.5,
				rise = 0,
			})
		end,
	},
	{
		-- Pink goo bubbles swell after you land, then pop; a new one grows back in the same spot.
		name = "Bubble Pop",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local list = {}
			for i = 1, 6 do
				table.insert(list, { 10, 10, if i % 2 == 1 then -4 else 4 })
			end
			local x = tileRun(parts, ENTRY, 4, list, "bubble", function()
				return melt(0.9, 2.5)
			end, function()
				return { shape = "disc" }
			end)
			return Kit.section(exit(parts, x + 4, 0), 0, parts)
		end,
	},
	{
		-- Square stones scattered over three lanes, up and down a step, holding under half a second: read where the
		-- next one is while you are still in the air, no time to aim twice.
		name = "Stepping Stones",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local lanes = { -8, 0, 8, 8, 0, -8, 0 }
			local tops = { 0, 1.5, 3, 1.5, 3, 4.5, 3 }
			local list = {}
			for i, z in lanes do
				table.insert(list, { 8, 8, z, tops[i] })
			end
			local x = tileRun(parts, ENTRY, 4, list, "tile", function()
				return melt(0.45, 2.5)
			end)
			return Kit.section(exit(parts, x + 4, 3), 3, parts)
		end,
	},
	{
		-- Lane-wide strips one after another: hop-hop-hop, each strip drops 0.4 s after you land, faster than you can
		-- walk across it, so holding forward falls through. Red goo blocks sit on every other strip, left then right:
		-- weave while you hop.
		name = "Melting Ladder",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local list = {}
			for _ = 1, 8 do
				table.insert(list, { 8, 24 })
			end
			local x = tileRun(parts, ENTRY, 3, list, "tile", function()
				return melt(0.4, 2)
			end)
			for i = 2, 8, 2 do
				local cx = ENTRY + i * 11 - 4
				local z = if i % 4 == 2 then -6 else 6
				table.insert(parts, Kit.hazard({ 3, 3, 12 }, { cx, 1.5, z }))
			end
			return Kit.section(exit(parts, x + 3, 0), 0, parts)
		end,
	},
	{
		-- Landing on a tile also melts the tiles beside it 0.3 s after it is gone: a sideways hop lands you on a tile
		-- that is already going.
		name = "Spreading Melt",
		tier = "medium",
		build = function(seed: number): Kit.Section
			return grid(seed, {
				cols = 5,
				rows = 3,
				tile = 8,
				gap = 5,
				holes = 0,
				hold = 0.5,
				away = 2.5,
				spreading = -1,
				spread = 0.25,
				rise = 0,
			})
		end,
	},
	{
		-- Goo puddles breathe in from their edges and out again, each a beat behind the last: arrive while yours is
		-- big and leave before it is small. (Kit: shrink runs on a clock, not from your landing.)
		name = "Shrinking Puddles",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local list = {}
			for i = 1, 6 do
				table.insert(list, { 12, 12, if i % 2 == 1 then -6 else 6 })
			end
			local period = 2.6
			local x = tileRun(parts, ENTRY, 4, list, "goo", function(i)
				return { kind = "shrink", min = 0.15, period = period, phase = (-(i - 1) * 1.0 / period) % 1 } :: any
			end)
			return Kit.section(exit(parts, x + 2, 0), 0, parts)
		end,
	},
	{
		-- Tiles in two lanes flip over on a clock, a wave that runs with you: while one is turned, its red goo
		-- underside is up (a hazard plate) and it is no floor. Each hop is a timed diagonal over a 5-stud hole, so
		-- holding forward drops in the first one. (Kit: flips run on a clock, not from your landing.)
		name = "Flip-Over",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local period, duty = 3.2, 0.6
			local x = ENTRY
			for i = 1, 7 do
				x += 5
				local z = if i % 2 == 1 then -5 else 5
				local reach = (x - ENTRY) / Kit.WALK
				local phase = (0.15 - reach / period) % 1
				table.insert(
					parts,
					Kit.slab(x + 4, 0, z, 8, 10, "tile", {
						tone = 1 + i % 2,
						motion = { kind = "flip", period = period, duty = duty, phase = phase },
					})
				)
				-- the red side: on exactly while the tile is turned away, standing a little proud of the floor line
				table.insert(
					parts,
					Kit.hazard({ 8, 0.8, 10 }, { x + 4, 0, z }, {
						motion = { kind = "flip", period = period, duty = 1 - duty, phase = (phase - duty) % 1 },
					})
				)
				x += 8
			end
			return Kit.section(exit(parts, x + 5, 0), 0, parts)
		end,
	},
	{
		-- Melting tiles climb like stairs, 3 studs a step: every jump is a step up and costs a little time.
		name = "Melt Stairs",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local list = {}
			for i = 1, 7 do
				table.insert(list, { 10, 10, if i % 2 == 1 then -2 else 2, (i - 1) * 3 })
			end
			local x = tileRun(parts, ENTRY, 3, list, "tile", function()
				return melt(0.55, 2.5)
			end)
			return Kit.section(exit(parts, x + 3, 18), 18, parts)
		end,
	},
	{
		-- The route makes an X: near-left, the centre tile, far-right, where a key waits on a safe pad; back over the
		-- centre (wait for it to come back) and through the opened gate to the far-left tile and out.
		name = "Back Again",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local hold, away = 0.5, 2
			-- 2: near-left, 3: centre
			table.insert(parts, Kit.slab(16, 0, -8, 8, 8, "tile", { tone = 1, motion = melt(hold, away) }))
			table.insert(parts, Kit.slab(28, 0, 0, 8, 8, "tile", { tone = 2, motion = melt(hold, away) }))
			-- 4: far-right safe pad with the key
			table.insert(parts, Kit.slab(40, 0, 8, 8, 8, "jelly", { tone = 2 }))
			table.insert(parts, Kit.prop({ 2, 2, 2 }, { 40, 3, 8 }, "key", { key = "x", ghost = true }))
			-- 6: far-left tile behind an L of gate
			table.insert(parts, Kit.slab(40, 0, -8, 8, 8, "tile", { tone = 1, motion = melt(hold, away) }))
			table.insert(
				parts,
				Kit.prop({ 1, Kit.WALL_HEIGHT, 9 }, { 35.5, Kit.WALL_HEIGHT / 2, -7.5 }, "gate", {
					gate = { group = "x", need = 1 },
				})
			)
			table.insert(
				parts,
				Kit.prop({ 9, Kit.WALL_HEIGHT, 1 }, { 40.5, Kit.WALL_HEIGHT / 2, -3.5 }, "gate", {
					gate = { group = "x", need = 1 },
				})
			)
			-- the exit sits on the left only: the far-left tile is the one way to it
			return Kit.section(exit(parts, 48, 0, -8, 8), 0, parts)
		end,
	},
	{
		-- Short stones that melt almost at once and never come back, spaced wide: one clean run or start over.
		name = "Quick Drips",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local list = {}
			for i = 1, 8 do
				table.insert(list, { 6, 8, if i % 2 == 1 then -5 else 5 })
			end
			local x = tileRun(parts, ENTRY, 5, list, "tile", function()
				return melt(0.35, -1)
			end)
			return Kit.section(exit(parts, x + 5, 0), 0, parts)
		end,
	},
	{
		-- A holed grid where every tile spreads its melt: only the route that never doubles back beside a used tile
		-- gets through.
		name = "One Way Out",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			-- route rows per column (1 = left): a snake with no doubling back; three decoys beside it
			local routeRows = { 1, 2, 3, 3, 2, 1 }
			local decoys = { [2 * 10 + 1] = true, [3 * 10 + 1] = true, [5 * 10 + 3] = true }
			local parts = {}
			entry(parts)
			local zs = { -8, 0, 8 }
			local index = {}
			local hold = math.max(0.4, roundUp(holdFor(8, 4, 0) + MARGIN))
			for c = 1, 6 do
				for r = 1, 3 do
					local key = c * 10 + r
					local onRoute = routeRows[c] == r
					if onRoute or decoys[key] then
						local x0 = ENTRY + 4 + (c - 1) * 12
						local part = Kit.slab(x0 + 4, 0, zs[r], 8, 8, "tile", {
							tone = 3,
							marker = "cracks",
							motion = melt(hold, 3, { spread = 0.25 }),
						})
						if not onRoute then
							part.step = nil -- a decoy beside the route
						end
						table.insert(parts, part)
						index[key] = #parts
					end
				end
			end
			for key, i in index do
				local c, r = key // 10, key % 10
				local nextList = {}
				for _, d in { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } } do
					local n = index[(c + d[1]) * 10 + (r + d[2])]
					if n and r + d[2] >= 1 and r + d[2] <= 3 then
						table.insert(nextList, n)
					end
				end
				table.sort(nextList)
				local m = parts[i].motion :: Kit.Motion
				m.next = nextList
			end
			return settle(Kit.section(exit(parts, ENTRY + 4 + 6 * 12, 0), 0, parts))
		end,
	},
	{
		-- Ferries slide side to side on rails, each out of step, with a melting stone between every two: wait on the
		-- ferry if you like, but a stone gives you 0.4 s and never comes back, so jump on it only when the next ferry
		-- will be in front of you. (Kit: a part carries one motion, so the ferries slide and the stones melt.)
		name = "Melting Ferries",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local list = {}
			for i = 1, 6 do
				table.insert(list, if i % 2 == 1 then { 10, 10, 0 } else { 6, 8, 0 })
			end
			local period = 2.4
			local x = tileRun(parts, ENTRY, 5, list, "tile", function(i)
				if i % 2 == 0 then
					return melt(0.4, -1)
				end
				return { kind = "slide", axis = "z", amp = 6, period = period, phase = ((i - 1) * 0.175) % 1 } :: any
			end, function(i)
				return if i % 2 == 1 then { marker = "rail" } else { tone = 3 }
			end)
			return Kit.section(exit(parts, x + 5, 0), 0, parts)
		end,
	},
	{
		-- Bubbles that pop fast, two that blink in and out on their own, small ones among big ones: read two bubbles
		-- ahead or you run out of floor.
		name = "Pop Sprint",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {}
			entry(parts)
			local sizes = { 8, 10, 8, 8, 10, 8, 8 }
			local blink = { [3] = true, [6] = true }
			local list = {}
			for i, d in sizes do
				table.insert(list, { d, d, if i % 2 == 1 then -2 else 2 })
			end
			local x = tileRun(parts, ENTRY, 4, list, "bubble", function(i)
				if blink[i] then
					return { kind = "flip", period = 2.4, duty = 0.6, phase = (i * 0.37) % 1 } :: any
				end
				return melt(roundUp(holdFor(sizes[i], 4, 0) + 0.05), 3)
			end, function(i)
				return { shape = "disc", tone = if blink[i] then 3 else 1 + i % 2 }
			end)
			return Kit.section(exit(parts, x + 4, 0), 0, parts)
		end,
	},
	{
		name = "Melt Grid A",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			return grid(11, {
				cols = 5,
				rows = 3,
				tile = 8,
				gap = 5,
				holes = 3,
				hold = 0.9,
				away = 2.5,
				spreading = 0,
				rise = 0,
			})
		end,
	},
	{
		name = "Melt Grid B",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			return grid(27, {
				cols = 6,
				rows = 2,
				tile = 10,
				gap = 5,
				holes = 3,
				hold = 0.85,
				away = 2.5,
				spreading = 0,
				rise = 0,
			})
		end,
	},
	{
		name = "Melt Grid C",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			return grid(40, {
				cols = 6,
				rows = 3,
				tile = 8,
				gap = 5,
				holes = 7,
				hold = 0.5,
				away = 2.5,
				spreading = 0,
				rise = 1.5,
				bends = 2,
			})
		end,
	},
	{
		name = "Melt Grid D",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			return grid(58, {
				cols = 6,
				rows = 3,
				tile = 8,
				gap = 5,
				holes = 5,
				hold = 0.5,
				away = 2.5,
				spreading = 4,
				spread = 0.3,
				rise = 0,
			})
		end,
	},
	{
		name = "Melt Grid E",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			return grid(73, {
				cols = 7,
				rows = 3,
				tile = 8,
				gap = 5,
				holes = 12,
				hold = 0.35,
				away = -1,
				spreading = 0,
				rise = 0,
			})
		end,
	},
	{
		name = "Melt Grid F",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			return grid(91, {
				cols = 6,
				rows = 3,
				tile = 8,
				gap = 5,
				holes = 6,
				hold = 0.4,
				away = 3,
				spreading = -1,
				spread = 0.25,
				rise = 2,
			})
		end,
	},
}

-- Fresh grids per seed: the tier sets the hold, holes, spreading, climb and whether tiles come back.
local function generate(seed: number, tier: string): Kit.Section
	local rng = Kit.rng(seed * 7 + (if tier == "easy" then 1 elseif tier == "medium" then 2 else 3))
	local rows = if rng:int(1, 3) == 1 then 2 else 3
	local cols = rng:int(5, 7)
	local cells = rows * cols
	local cfg: { [string]: any } = { seed = seed, rows = rows, cols = cols, gap = 5, spread = 0.3 }
	if tier == "easy" then
		cfg.tile = if rng:int(1, 2) == 1 then 8 else 10
		cfg.holes = rng:int(0, 3)
		cfg.hold = 0.85 + rng:int(0, 2) * 0.05
		cfg.away = 2.5
		cfg.spreading = rng:int(0, 2)
		cfg.spread = 0.5
		cfg.rise = 0
	elseif tier == "medium" then
		cfg.tile = 8
		cfg.holes = math.floor((cells - cols) * (0.4 + rng:float() * 0.2))
		cfg.hold = 0.5 + rng:int(0, 3) * 0.05
		cfg.away = 2.5
		cfg.spreading = rng:int(0, 5)
		cfg.rise = rng:int(0, 3) * 0.5
	else
		cfg.tile = 8
		cfg.holes = math.floor((cells - cols) * (0.7 + rng:float() * 0.3))
		cfg.hold = 0.35 + rng:int(0, 2) * 0.05
		cfg.away = -1
		cfg.spreading = if rng:int(1, 2) == 1 then -1 else rng:int(2, 6)
		cfg.spread = 0.25
		cfg.rise = rng:int(0, 2)
	end
	-- 7 columns of 10-stud tiles would run past 110 studs
	if cfg.tile == 10 and cols == 7 then
		cfg.cols = 6
	end
	return buildGrid(cfg :: any)
end

M.generator = {
	tiers = { "easy", "medium", "hard" },
	build = generate,
	examples = 6,
}

return M
