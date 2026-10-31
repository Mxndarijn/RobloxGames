--!strict
--[[
	Clue Doors (obby idea 29, docs/obby-variants/29.json; contract/obby-sections.md)

	A clue room: a framed board shows a clue, then a wall of 2 or 3 framed curtains each wears one symbol of the same
	kind. Walk through the door that fits the clue. Behind every door is a 16-stud corridor that looks the same from
	outside; behind a wrong door its floor is a trapdoor (`melt`, 0.25 s, gone until you are reset) over red goo, so a
	wrong guess sends you back to the start pad (too long to run and jump across before it drops). The right corridor's
	floor is the walking path (`step`); it ends at a 6-stud hole before the exit pad, and the jump in to the door floor
	is a hole too, so holding forward never clears a room.

	Every variant rolls its clue from its seed (`roll*`): the clue kind's symbols, the distractors and which door is
	right, so a course never teaches one fixed answer. Exactly one door fits (tests/obby/ClueDoors.spec solves every
	roll with its own solver). Easy symbols differ in both colour and shape. No words: shapes, dots and slimes.

	Clue kinds:
	  match   same colour and shape          shape   same shape, every door one colour
	  slime   same slime (silhouette + colour)  shadow  the board shows a dark outline, the doors full colour slimes
	  count   as many dots                    cross   the board crosses out every door but one
	  next    a row like A B A B ? : the door that fills the gap
	  mix     board A a colour splash, board B a grey shape: the door with both (the others share one half each)

	The room (`room`): a 9-stud jelly door wall with 6-wide openings (3 doors, corridors 8 wide) or 8-wide ones (2 doors,
	corridors 12 wide), a walk-through `pad` curtain in each opening (ghost, opaque) with the symbol on its face, 9-stud
	dividers between the corridors, the trapdoors and one red goo pit under them. Optional `gates`: a jelly wall in
	front of every door that is shut (solid) for `duty` of a beat-snapped period (`flip`), so you go through while open.

	Symbols are ghost decor drawn on a plane (`Plane`): facing "x" (towards a runner coming down the course), "z" (to
	the right, a board on the left side of the lane) or "y" (lying flat on a floor). Shapes: circle, square, diamond,
	plus, stripe; slimes: round, ears, horns, antenna (a body disc with eyes and its features); dots; a colour splash; a
	blank box for the gap in a row. A blinking board (`blink`) is a `flip` on the beat clock: the backing's glow pulses
	(`solid`) and the symbols only show in the lit share.

	Tuned per contract §10: easies open with one or two long jumps (5.5-6 studs, narrow side hops, a beam or a slow
	bobbing hop); mediums put a timed hop (bobbing past the rise limit, sliding past the gap limit, a swaying beam) or a
	sweeping goo bar on top of a rule clue; hards chain two rooms, split the clue, close the doors on a beat over a
	cracking floor or make you carry the clue over opposite-moving hops.
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

type Part = Kit.Part
type Rng = typeof(Kit.rng(1))

local WALL_H = Kit.WALL_HEIGHT -- door wall and dividers: over a jump plus a head
local FACE = 0.2 -- thickness of a board, a curtain symbol layer
-- studs behind a door: a wrong trapdoor holds you 0.25 s (4 studs of running), so a jump in from the door wall
-- (8.7), 4 studs of running and a jump out (8.7) still end over the exit hole: 21.4 < 1 + CORRIDOR + EXIT_GAP - 1
local CORRIDOR = 16
local EXIT_GAP = 6 -- the hole after the corridors: over the 3.6 a walker crosses, the longest jump allowed
local EXIT_LONG = 6
local TRAP_DELAY = 0.25 -- seconds a trapdoor holds you: its crack is the only tell
local PIT_DROP = 4 -- the goo pit's top under the corridor floors
local DOOR_SYM = 2.6 -- symbol size on a curtain
local SYM_Y = 6 -- curtain symbol centre over the floor: over a head, still eye level

-- Six colours (look, tone): red, green, blue, yellow, purple, orange.
local COLOURS: { { any } } = {
	{ "bar", 1 },
	{ "glow", 2 },
	{ "glow", 3 },
	{ "glow", 1 },
	{ "tile", 1 },
	{ "tile", 2 },
}
local SHAPES = { "circle", "square", "diamond", "plus", "stripe" }
local SLIMES = { "round", "ears", "horns", "antenna" }

export type Sym = {
	t: string, -- "shape" | "grey" | "slime" | "shadow" | "dots" | "splash" | "blank"
	shape: string?,
	col: number?,
	kind: string?,
	n: number?,
	cross: boolean?,
}

-- A rolled clue: the board(s) (each a row of symbols), one symbol per door, the right door.
export type Clue = { kind: string, boards: { { Sym } }, doors: { Sym }, right: number }

-- A built room: its clue plus where the corridors are (tests/obby/ClueDoors.spec).
export type Room = {
	kind: string,
	boards: { { Sym } },
	doors: { Sym },
	right: number,
	centres: { number },
	x0: number,
	x1: number,
	top: number,
}

---------------------------------------------------------------------------
-- Rolls
---------------------------------------------------------------------------

local function range(n: number): { number }
	local out = {}
	for i = 1, n do
		out[i] = i
	end
	return out
end

-- `n` different entries of `list`, in a seeded order.
local function pickN<T>(rng: Rng, list: { T }, n: number): { T }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = rng:int(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	local out = {}
	for i = 1, n do
		out[i] = copy[i]
	end
	return out
end

local function copySym(s: Sym, cross: boolean?): Sym
	local c = table.clone(s)
	c.cross = cross
	return c
end

-- Same colour and shape (`one`: every door the same colour, match by shape only).
local function rollMatch(rng: Rng, n: number, one: boolean?): Clue
	local shapes = pickN(rng, SHAPES, n)
	local cols = pickN(rng, range(#COLOURS), n)
	local single = rng:int(1, #COLOURS)
	local doors = {}
	for i = 1, n do
		doors[i] = { t = "shape", shape = shapes[i], col = if one then single else cols[i] }
	end
	local right = rng:int(1, n)
	return {
		kind = if one then "shape" else "match",
		boards = { { copySym(doors[right]) } },
		doors = doors,
		right = right,
	}
end

local function rollSlime(rng: Rng, n: number): Clue
	local kinds = pickN(rng, SLIMES, n)
	local cols = pickN(rng, range(#COLOURS), n)
	local doors = {}
	for i = 1, n do
		doors[i] = { t = "slime", kind = kinds[i], col = cols[i] }
	end
	local right = rng:int(1, n)
	return { kind = "slime", boards = { { copySym(doors[right]) } }, doors = doors, right = right }
end

local function rollShadow(rng: Rng, n: number): Clue
	local kinds = pickN(rng, SLIMES, n)
	local cols = pickN(rng, range(#COLOURS), n)
	local doors = {}
	for i = 1, n do
		doors[i] = { t = "slime", kind = kinds[i], col = cols[i] }
	end
	local right = rng:int(1, n)
	return { kind = "shadow", boards = { { { t = "shadow", kind = kinds[right] } } }, doors = doors, right = right }
end

-- Dots: every door a different count of 1..`most`.
local function rollCount(rng: Rng, n: number, most: number): Clue
	local counts = pickN(rng, range(most), n)
	local doors = {}
	for i = 1, n do
		doors[i] = { t = "dots", n = counts[i] }
	end
	local right = rng:int(1, n)
	return { kind = "count", boards = { { { t = "dots", n = counts[right] } } }, doors = doors, right = right }
end

-- The board crosses out every door but the right one.
local function rollCross(rng: Rng, n: number): Clue
	local clue = rollMatch(rng, n)
	local row = {}
	for i, d in clue.doors do
		if i ~= clue.right then
			table.insert(row, copySym(d, true))
		end
	end
	-- the crossed symbols in a seeded order, so their place on the board says nothing
	return { kind = "cross", boards = { pickN(rng, row, #row) }, doors = clue.doors, right = clue.right }
end

local PATTERNS = { { 1, 2 }, { 1, 2, 3 }, { 1, 1, 2 } } -- AB, ABC, AAB

-- A row of 4 or 5 symbols in a repeating pattern, then a blank: the door shows what fills it.
local function rollNext(rng: Rng, n: number): Clue
	local pattern = PATTERNS[rng:int(1, #PATTERNS)]
	local members = 0
	for _, k in pattern do
		members = math.max(members, k)
	end
	local shapes = pickN(rng, SHAPES, math.max(members, n))
	local cols = pickN(rng, range(#COLOURS), math.max(members, n))
	local syms: { Sym } = {}
	for i = 1, #shapes do
		syms[i] = { t = "shape", shape = shapes[i], col = cols[i] }
	end
	local long = rng:int(4, 5)
	local row = {}
	for i = 1, long do
		table.insert(row, copySym(syms[pattern[(i - 1) % #pattern + 1]]))
	end
	table.insert(row, { t = "blank" })
	local answer = pattern[long % #pattern + 1]
	-- the doors: the answer and the other symbols (other pattern members first: they are the tempting wrong ones)
	local wrong = {}
	for i = 1, #syms do
		if i ~= answer then
			table.insert(wrong, i)
		end
	end
	local picks = { answer }
	for i = 1, n - 1 do
		table.insert(picks, wrong[i])
	end
	picks = pickN(rng, picks, n)
	local doors, right = {}, 1
	for i, k in picks do
		doors[i] = copySym(syms[k])
		if k == answer then
			right = i
		end
	end
	return { kind = "next", boards = { row }, doors = doors, right = right }
end

-- Board A a colour, board B a shape: the right door has both, one other the same colour, one the same shape.
local function rollMix(rng: Rng): Clue
	local cols = pickN(rng, range(#COLOURS), 2)
	local shapes = pickN(rng, SHAPES, 2)
	local list: { Sym } = {
		{ t = "shape", shape = shapes[1], col = cols[1] },
		{ t = "shape", shape = shapes[2], col = cols[1] },
		{ t = "shape", shape = shapes[1], col = cols[2] },
	}
	local order = pickN(rng, { 1, 2, 3 }, 3)
	local doors, right = {}, 1
	for i, k in order do
		doors[i] = list[k]
		if k == 1 then
			right = i
		end
	end
	return {
		kind = "mix",
		boards = { { { t = "splash", col = cols[1] } }, { { t = "grey", shape = shapes[1] } } },
		doors = doors,
		right = right,
	}
end

-- A clue of `kind` for `n` doors.
local function roll(rng: Rng, kind: string, n: number, most: number?): Clue
	if kind == "match" then
		return rollMatch(rng, n)
	elseif kind == "shape" then
		return rollMatch(rng, n, true)
	elseif kind == "slime" then
		return rollSlime(rng, n)
	elseif kind == "shadow" then
		return rollShadow(rng, n)
	elseif kind == "count" then
		return rollCount(rng, n, most or 3)
	elseif kind == "cross" then
		return rollCross(rng, n)
	elseif kind == "next" then
		return rollNext(rng, n)
	elseif kind == "mix" then
		return rollMix(rng)
	end
	error(`unknown clue kind {kind}`)
end

---------------------------------------------------------------------------
-- Drawing symbols
---------------------------------------------------------------------------

-- A face to draw on: its centre, and which way it faces ("x": towards -x, a runner coming down the course; "z":
-- towards +z; "y": up, lying on a floor). `u` runs to the viewer's right, `v` up the face, `d` out of it.
type Plane = { x: number, y: number, z: number, facing: string }

local function at(pl: Plane, u: number, v: number, d: number): Kit.Vec
	if pl.facing == "x" then
		return { pl.x - d, pl.y + v, pl.z + u }
	elseif pl.facing == "z" then
		return { pl.x + u, pl.y + v, pl.z + d }
	end
	return { pl.x + v, pl.y + d, pl.z + u }
end

local function decor(tone: number, extra: { [string]: any }?): { [string]: any }
	local e: { [string]: any } = { ghost = true, tone = tone }
	if extra then
		for k, v in extra do
			e[k] = if type(v) == "table" then table.clone(v) else v
		end
	end
	return e
end

-- A `du` x `dv` rectangle on the face at (u, v, d), turned `angle` degrees in the face.
local function rect(
	pl: Plane,
	u: number,
	v: number,
	d: number,
	du: number,
	dv: number,
	angle: number,
	look: string,
	tone: number,
	extra: { [string]: any }?
): Part
	local e = decor(tone, extra)
	local size
	if pl.facing == "x" then
		size = { FACE, dv, du }
		e.pitch = if angle ~= 0 then angle else nil
	elseif pl.facing == "z" then
		size = { du, dv, FACE }
		e.roll = if angle ~= 0 then angle else nil
	else
		size = { dv, FACE, du }
		e.yaw = if angle ~= 0 then angle else nil
	end
	return Kit.prop(size, at(pl, u, v, d), look, e)
end

-- A round disc `dia` across on the face.
local function disc(
	pl: Plane,
	u: number,
	v: number,
	d: number,
	dia: number,
	look: string,
	tone: number,
	extra: { [string]: any }?
): Part
	local e = decor(tone, extra)
	e.shape = "disc"
	if pl.facing == "x" then
		e.roll = 90
	elseif pl.facing == "z" then
		e.pitch = 90
	end
	return Kit.prop({ dia, FACE, dia }, at(pl, u, v, d), look, e)
end

local function colourOf(sym: Sym): (string, number)
	local c = COLOURS[sym.col or 1]
	return c[1], c[2]
end

-- How wide a symbol of size `s` is on a board.
local function widthOf(sym: Sym, s: number): number
	if sym.t == "slime" or sym.t == "shadow" then
		return 1.5 * s
	elseif sym.t == "dots" then
		return math.min(sym.n or 1, 3) * 0.42 * s + 0.3 * s
	elseif sym.t == "splash" then
		return 1.4 * s
	end
	return 1.15 * s
end

-- A shape of size `s` centred at (u, v, d).
local function shapeAt(
	parts: { Part },
	pl: Plane,
	u: number,
	v: number,
	d: number,
	shape: string,
	s: number,
	look: string,
	tone: number,
	extra: { [string]: any }?
)
	if shape == "circle" then
		table.insert(parts, disc(pl, u, v, d, s, look, tone, extra))
	elseif shape == "square" then
		table.insert(parts, rect(pl, u, v, d, 0.85 * s, 0.85 * s, 0, look, tone, extra))
	elseif shape == "diamond" then
		table.insert(parts, rect(pl, u, v, d, 0.72 * s, 0.72 * s, 45, look, tone, extra))
	elseif shape == "plus" then
		table.insert(parts, rect(pl, u, v, d, s, 0.32 * s, 0, look, tone, extra))
		table.insert(parts, rect(pl, u, v, d + 0.01, 0.32 * s, s, 0, look, tone, extra))
	else -- stripe
		table.insert(parts, rect(pl, u, v, d, s, 0.38 * s, 0, look, tone, extra))
	end
end

-- A slime of size `s`: body disc, its features and (in colour) two eyes; a shadow is all dark, no eyes.
local function slimeAt(
	parts: { Part },
	pl: Plane,
	u: number,
	v: number,
	d: number,
	kind: string,
	s: number,
	look: string,
	tone: number,
	eyes: boolean,
	extra: { [string]: any }?
)
	local by = v - 0.12 * s
	table.insert(parts, disc(pl, u, by, d, s, look, tone, extra))
	if kind == "ears" then
		for _, side in { -1, 1 } do
			table.insert(
				parts,
				rect(pl, u + side * 0.28 * s, by + 0.55 * s, d, 0.24 * s, 0.42 * s, 0, look, tone, extra)
			)
		end
	elseif kind == "horns" then
		for _, side in { -1, 1 } do
			table.insert(
				parts,
				rect(pl, u + side * 0.55 * s, by + 0.2 * s, d, 0.32 * s, 0.32 * s, 45, look, tone, extra)
			)
		end
	elseif kind == "antenna" then
		table.insert(parts, rect(pl, u, by + 0.62 * s, d, 0.09 * s, 0.4 * s, 0, look, tone, extra))
		table.insert(parts, disc(pl, u, by + 0.84 * s, d, 0.24 * s, look, tone, extra))
	end
	if eyes then
		for _, side in { -1, 1 } do
			table.insert(parts, disc(pl, u + side * 0.18 * s, by + 0.08 * s, d + FACE, 0.2 * s, "post", 1, extra))
		end
	end
end

-- Draws `sym` (size `s`) centred at (u, v) on the face, its first layer at depth `d`. `ink` is the look of dots,
-- crosses and the blank box on this face (light on a dark board, dark on a light curtain).
local function drawSym(
	parts: { Part },
	pl: Plane,
	u: number,
	v: number,
	d: number,
	sym: Sym,
	s: number,
	ink: string,
	extra: { [string]: any }?
)
	local t = sym.t
	if t == "shape" then
		local look, tone = colourOf(sym)
		shapeAt(parts, pl, u, v, d, sym.shape or "circle", s, look, tone, extra)
	elseif t == "grey" then
		shapeAt(parts, pl, u, v, d, sym.shape or "circle", s, "pad", 1, extra)
	elseif t == "slime" then
		local look, tone = colourOf(sym)
		slimeAt(parts, pl, u, v, d, sym.kind or "round", s, look, tone, true, extra)
	elseif t == "shadow" then
		slimeAt(parts, pl, u, v, d, sym.kind or "round", s, "post", 1, false, extra)
	elseif t == "dots" then
		local n = sym.n or 1
		local rows: { number } = if n > 3 then { 3, n - 3 } else { n }
		local step = 0.42 * s
		for r, count in rows do
			local rv = v + (if #rows == 2 then (if r == 1 then 0.22 * s else -0.22 * s) else 0)
			for k = 1, count do
				local du = (k - (count + 1) / 2) * step
				table.insert(parts, disc(pl, u + du, rv, d, 0.3 * s, ink, 1, extra))
			end
		end
	elseif t == "splash" then
		local look, tone = colourOf(sym)
		table.insert(parts, disc(pl, u, v, d, 0.9 * s, look, tone, extra))
		table.insert(parts, disc(pl, u + 0.52 * s, v + 0.36 * s, d, 0.34 * s, look, tone, extra))
		table.insert(parts, disc(pl, u - 0.48 * s, v - 0.4 * s, d, 0.28 * s, look, tone, extra))
	elseif t == "blank" then
		local dark = if ink == "pad" then "post" else "pad"
		table.insert(parts, rect(pl, u, v, d, 0.8 * s, 0.8 * s, 0, ink, 1, extra))
		table.insert(parts, rect(pl, u, v, d + FACE, 0.56 * s, 0.56 * s, 0, dark, 1, extra))
	end
	if sym.cross then
		for _, a in { 45, -45 } do
			table.insert(parts, rect(pl, u, v, d + 2 * FACE, 0.14 * s, 1.3 * s, a, ink, 1, extra))
		end
	end
end

export type BoardOpts = {
	s: number, -- symbol size
	w: number?, -- at least this wide
	h: number, -- tall
	look: string?, -- the backing: "post" (dark, default) or "pad" (light, for shadows)
	blink: { beat: number, on: number }?, -- lit `on` seconds of every `beat` beats: glow pulses, symbols show
}

-- A framed board with a row of symbols on plane `pl` (its backing's centre). Returns its width.
local function board(parts: { Part }, pl: Plane, syms: { Sym }, o: BoardOpts): number
	local total = 0
	for _, sym in syms do
		total += widthOf(sym, o.s)
	end
	local w = math.max(o.w or 0, total + 1)
	local look = o.look or "post"
	local ink = if look == "post" then "pad" else "post"
	local backExtra, symExtra = nil, nil
	if o.blink then
		local duty = o.blink.on / Kit.beat(o.blink.beat)
		backExtra = { beat = o.blink.beat, motion = { kind = "flip", solid = true, duty = duty } }
		symExtra = { beat = o.blink.beat, motion = { kind = "flip", duty = duty } }
	end
	table.insert(parts, rect(pl, 0, 0, -FACE, w + 0.8, o.h + 0.8, 0, "plank", 1))
	table.insert(parts, rect(pl, 0, 0, 0, w, o.h, 0, look, 1, backExtra))
	local u = -total / 2
	for _, sym in syms do
		local sw = widthOf(sym, o.s)
		drawSym(parts, pl, u + sw / 2, 0, FACE, sym, o.s, ink, symExtra)
		u += sw
	end
	return w
end

---------------------------------------------------------------------------
-- Floors and the room
---------------------------------------------------------------------------

local function trap(): Kit.Motion
	return { kind = "melt", on = "land", delay = TRAP_DELAY, away = -1 }
end

-- A walking-path floor from x0 to x1, top `top`, `wide` across centred on z.
local function floor(
	parts: { Part },
	x0: number,
	x1: number,
	top: number,
	tone: number,
	wide: number?,
	z: number?,
	extra: { [string]: any }?
): Part
	local e: { [string]: any } = { tone = tone }
	for k, v in (extra or {}) :: { [string]: any } do
		e[k] = v
	end
	local p = Kit.slab((x0 + x1) / 2, top, z or 0, x1 - x0, wide or Kit.WIDTH, "jelly", e)
	table.insert(parts, p)
	return p
end

export type RoomOpts = {
	long: number?, -- corridor length (default CORRIDOR)
	gates: { beat: number, duty: number }?, -- doors shut `duty` of every `beat` beats
}

local function doorCentres(n: number): ({ number }, number, number)
	if n == 2 then
		return { -6, 6 }, 8, 12 -- centres, opening, corridor width
	end
	return { -8, 0, 8 }, 6, 8
end

--[[
	The door wall at x = D (1 thick, on a floor whose top is `top`), the curtains with the clue's door symbols, the
	corridors behind (the right one a step, the others trapdoors), the dividers and the goo pit. Insert it right after
	the door floor so the right corridor is the next step. Returns the room record (its corridor end is `x1`).
]]
local function room(parts: { Part }, D: number, top: number, clue: Clue, o: RoomOpts?): Room
	local opts: RoomOpts = o or {}
	local n = #clue.doors
	local centres, open, wide = doorCentres(n)
	local long = opts.long or CORRIDOR
	local x0, x1 = D + 1, D + 1 + long
	local cx = (x0 + x1) / 2
	-- the right corridor first (it is the next step), then the trapdoors behind the other doors
	for i, z in centres do
		if i == clue.right then
			floor(parts, x0, x1, top, 2, wide, z)
		end
	end
	for i, z in centres do
		if i ~= clue.right then
			table.insert(
				parts,
				Kit.prop(
					{ long, Kit.THICK, wide },
					{ cx, top - Kit.THICK / 2, z },
					"jelly",
					{ tone = 2, motion = trap() }
				)
			)
		end
	end
	table.insert(parts, Kit.hazard({ long, 0.6, Kit.WIDTH }, { cx, top - PIT_DROP, 0 }))
	-- door wall pieces between the openings
	local edges = { -Kit.HALF }
	for _, z in centres do
		table.insert(edges, z - open / 2)
		table.insert(edges, z + open / 2)
	end
	table.insert(edges, Kit.HALF)
	for k = 1, #edges, 2 do
		local a, b = edges[k], edges[k + 1]
		table.insert(
			parts,
			Kit.wall(
				D + 0.5,
				(a + b) / 2,
				b - a,
				WALL_H,
				false,
				{ pos = { D + 0.5, top + WALL_H / 2, (a + b) / 2 }, tone = 3 }
			)
		)
	end
	-- dividers between the corridors
	for k = 1, n - 1 do
		local z = (centres[k] + centres[k + 1]) / 2
		table.insert(parts, Kit.wall(cx, z, long, WALL_H, true, { pos = { cx, top + WALL_H / 2, z }, tone = 3 }))
	end
	-- curtains, their symbols and (optional) the closing gates in front
	for i, z in centres do
		table.insert(parts, Kit.prop({ 0.4, WALL_H, open }, { D + 0.2, top + WALL_H / 2, z }, "pad", { ghost = true }))
		local pl: Plane = { x = D, y = top + SYM_Y, z = z, facing = "x" }
		local s = if clue.doors[i].t == "slime" then 2.4 else DOOR_SYM
		drawSym(parts, pl, 0, 0, FACE / 2 + 0.02, clue.doors[i], s, "post")
		if opts.gates then
			table.insert(
				parts,
				Kit.prop({ 0.6, WALL_H, open + 0.6 }, { D - 0.75, top + WALL_H / 2, z }, "jelly", {
					tone = 3,
					beat = opts.gates.beat,
					motion = { kind = "flip", duty = opts.gates.duty },
				})
			)
		end
	end
	return {
		kind = clue.kind,
		boards = clue.boards,
		doors = clue.doors,
		right = clue.right,
		centres = centres,
		x0 = x0,
		x1 = x1,
		top = top,
	}
end

-- The hole after the last corridors and the exit pad. Returns the section length.
local function exit(parts: { Part }, x: number, top: number): number
	local x0 = x + EXIT_GAP
	floor(parts, x0, x0 + EXIT_LONG, top, 1)
	return x0 + EXIT_LONG
end

-- Board planes: over the door wall at D (bottom `lift` over the floor top), or floating `back` studs before it.
local function overWall(D: number, top: number, h: number, z: number?, lift: number?): Plane
	return { x = D - 0.15, y = top + (lift or WALL_H + 0.4) + h / 2, z = z or 0, facing = "x" }
end

local function floating(x: number, top: number, h: number, z: number?, lift: number?): Plane
	return { x = x, y = top + (lift or 7.5) + h / 2, z = z or 0, facing = "x" }
end

-- A hop: a (moving) 1-thick floor `long` x `wide`; `look` "beam" makes it a narrow beam.
local function hop(
	parts: { Part },
	x0: number,
	long: number,
	top: number,
	z: number,
	wide: number,
	motion: Kit.Motion?,
	look: string?
): number
	local extra: { [string]: any } = {}
	extra.motion = motion
	extra.look = look
	floor(parts, x0, x0 + long, top, 3, wide, z, extra)
	return x0 + long
end

local function slideZ(amp: number, period: number, phase: number): Kit.Motion
	return { kind = "slide", axis = "z", amp = amp, period = period, phase = phase }
end

local function slideX(amp: number, period: number, phase: number): Kit.Motion
	return { kind = "slide", axis = "x", amp = amp, period = period, phase = phase }
end

local function bob(amp: number, period: number, phase: number): Kit.Motion
	return { kind = "slide", axis = "y", amp = amp, period = period, phase = phase }
end

---------------------------------------------------------------------------
-- The standard room section
---------------------------------------------------------------------------

export type HopSpec = {
	gap: number,
	long: number,
	top: number,
	z: number?,
	wide: number?,
	motion: Kit.Motion?,
	look: string?,
}

export type Std = {
	entry: number, -- entry pad length
	hops: { HopSpec }?, -- between the entry pad and the door floor
	gap: number, -- the hole onto the door floor
	top: number, -- door floor top (and the exit)
	floorLong: number, -- door floor length
	clue: Clue,
	where: string, -- "wall" | "raised" | "back" | "entry" | "none"
	back: number?, -- "back": studs before the door wall
	s: number?, -- board symbol size
	w: number?,
	h: number?,
	look: string?,
	blink: { beat: number, on: number }?,
	sweep: { amp: number, period: number }?, -- a red goo bar sliding across in front of a "raised" board
	gates: { beat: number, duty: number }?,
	floorMelt: number?, -- the door floor cracks `floorMelt` s after you land and drops away (back 2 s later)
	bar: { amp: number, period: number, wide: number? }?, -- a low red goo bar sweeping across the door floor
}

-- Entry pad, hops, door floor, the room, exit; then the board(s) where `o.where` says.
local function standard(o: Std): (Kit.Section, { Room })
	local parts: { Part } = {}
	floor(parts, 0, o.entry, 0, 1)
	local x = o.entry
	for _, h in (o.hops or {}) :: { HopSpec } do
		x = hop(parts, x + h.gap, h.long, h.top, h.z or 0, h.wide or 10, h.motion, h.look)
	end
	local f0 = x + o.gap
	local D = f0 + o.floorLong
	floor(
		parts,
		f0,
		D,
		o.top,
		1,
		nil,
		nil,
		if o.floorMelt then { motion = { kind = "melt", on = "land", delay = o.floorMelt, away = 2 } } else nil
	)
	local r = room(parts, D, o.top, o.clue, { gates = o.gates })
	local length = exit(parts, r.x1, o.top)

	local s, h = o.s or 3, o.h or 5
	local boards = o.clue.boards
	if o.where ~= "none" then
		for k, syms in boards do
			local z = if #boards == 2 then (if k == 1 then -6 else 6) else 0
			local pl: Plane
			if o.where == "wall" then
				pl = overWall(D, o.top, h, z)
			elseif o.where == "raised" then
				pl = overWall(D, o.top, h, z, 12.6)
			elseif o.where == "back" then
				pl = floating(D - (o.back or 14), o.top, h, z)
			else -- "entry": floating over the hole after the entry pad
				pl = floating(o.entry + 2, 0, h, z, 5.5)
			end
			board(parts, pl, syms, { s = s, w = o.w, h = h, look = o.look, blink = o.blink })
		end
	end
	if o.sweep then
		-- out of reach (its bottom over a jumping head), it only hides the board half the time
		table.insert(
			parts,
			Kit.hazard({ 0.6, h + 0.4, 6 }, { D - 1.2, o.top + 12.6 + h / 2, 0 }, {
				motion = slideZ(o.sweep.amp, o.sweep.period, 0),
			})
		)
	end
	if o.bar then
		-- low enough to hit walking (jump it or slip past it), 3 studs before the doors
		table.insert(
			parts,
			Kit.hazard(
				{ 1, 2.4, o.bar.wide or 5 },
				{ D - 3, o.top + 1.2, 0 },
				{ motion = slideZ(o.bar.amp, o.bar.period, 0.25) }
			)
		)
	end
	return Kit.section(length, o.top, parts), { r }
end

---------------------------------------------------------------------------
-- Variants
---------------------------------------------------------------------------

local function rngFor(seed: number, salt: number): Rng
	return Kit.rng(seed * 7919 + salt)
end

type Make = (seed: number) -> (Kit.Section, { Room })

-- A hop bobbing up and down `amp` (the jump off it is only short enough near its top).
local function bobHop(
	gap: number,
	top: number,
	amp: number,
	period: number,
	phase: number,
	z: number?,
	wide: number?
): HopSpec
	return { gap = gap, long = 6, top = top, z = z, wide = wide or 10, motion = bob(amp, period, phase) }
end

-- A narrow hop sliding across the lane; two of them in opposite phase are only close enough some of the time.
local function swayHop(gap: number, top: number, amp: number, period: number, phase: number): HopSpec
	return { gap = gap, long = 6, top = top, wide = 8, motion = slideZ(amp, period, phase) }
end

-- Colour Match: one coloured shape on a board 14 studs before three doors; a narrow hop off to one side, then a
-- long jump up onto the door floor.
local function colourMatch(seed: number): (Kit.Section, { Room })
	local rng = rngFor(seed, 1)
	local side = if rng:int(1, 2) == 1 then -4 else 4
	return standard({
		entry = 10,
		hops = { { gap = 5.5, long = 6, top = 0.5, z = side, wide = 8 } },
		gap = 6,
		top = 1.5,
		floorLong = 12,
		clue = roll(rng, "match", 3),
		where = "back",
		back = 14,
		s = 3.6,
		w = 8,
		h = 6,
	})
end

-- Two Doors: a huge board over two wide doors; a 4-wide beam over the drop, then a long jump onto the door floor.
local function twoDoors(seed: number): (Kit.Section, { Room })
	local rng = rngFor(seed, 2)
	local kind = if rng:int(1, 2) == 1 then "match" else "shape"
	return standard({
		entry = 10,
		hops = { { gap = 5.5, long = 10, top = 0.5, wide = 4, look = "beam" } },
		gap = 6,
		top = 1,
		floorLong = 8,
		clue = roll(rng, kind, 2),
		where = "wall",
		s = 4.4,
		w = 10,
		h = 7,
	})
end

-- Same Slime: the board over the doors shows a slime; two zig-zag hops, pick the door with that slime.
local function sameSlime(seed: number): (Kit.Section, { Room })
	local rng = rngFor(seed, 3)
	local side = if rng:int(1, 2) == 1 then -4 else 4
	return standard({
		entry = 10,
		hops = {
			{ gap = 5.5, long = 6, top = 0.5, z = side, wide = 8 },
			{ gap = 5.5, long = 6, top = 1, z = -side, wide = 8 },
		},
		gap = 5.5,
		top = 2,
		floorLong = 8,
		clue = roll(rng, "slime", 3),
		where = "wall",
		s = 3.4,
		w = 8,
		h = 6,
	})
end

-- Shape Only: every door the same colour, match by shape alone; a slow bobbing hop, best left from its top.
local function shapeOnly(seed: number): (Kit.Section, { Room })
	local rng = rngFor(seed, 4)
	return standard({
		entry = 10,
		hops = { bobHop(5, 0.5, 1.5, 3.6, 0) },
		gap = 5,
		top = 2.5,
		floorLong = 12,
		clue = roll(rng, "shape", 3),
		where = "back",
		back = 14,
		s = 3.6,
		w = 8,
		h = 6,
	})
end

-- Floor Clue: the symbol is painted big on the 10 x 10 pad you land on, then one more jump up to the doors.
local function floorClue(seed: number): (Kit.Section, { Room })
	local rng = rngFor(seed, 5)
	local clue = roll(rng, "match", 3)
	local parts: { Part } = {}
	floor(parts, 0, 8, 0, 1)
	local p0 = 8 + 6
	local top = 2
	floor(parts, p0, p0 + 10, 1, 3, 10, 0)
	local f0 = p0 + 10 + 5
	local D = f0 + 6
	floor(parts, f0, D, top, 1)
	local r = room(parts, D, top, clue)
	local length = exit(parts, r.x1, top)
	local pl: Plane = { x = p0 + 5, y = 1 + 0.02 + FACE / 2 + FACE, z = 0, facing = "y" }
	board(parts, pl, clue.boards[1], { s = 5, w = 7, h = 7 })
	return Kit.section(length, top, parts), { r }
end

-- Count the Dots: the door with as many dots as the board (up to 4 or 5); the bobbing hop is only high enough to
-- reach the door floor near its top.
local function countDots(seed: number): (Kit.Section, { Room })
	local rng = rngFor(seed, 6)
	local most = if rng:int(1, 2) == 1 then 4 else 5
	return standard({
		entry = 8,
		hops = { bobHop(5, 0, 2, 2.8, 0) },
		gap = 5,
		top = 3,
		floorLong = 8,
		clue = roll(rng, "count", 3, most),
		where = "wall",
		s = 3.4,
		w = 8,
		h = 5,
	})
end

-- Cross Out: the board crosses out two symbols; the door left over is the way. The hop slides to and fro along the
-- course: get on when it is close, ride it, get off when it nears the door floor.
local function crossOut(seed: number): (Kit.Section, { Room })
	local rng = rngFor(seed, 7)
	return standard({
		entry = 8,
		hops = { { gap = 6.5, long = 6, top = 0.5, wide = 10, motion = slideX(2.5, 3.4, 0) } },
		gap = 6.5,
		top = 1.5,
		floorLong = 8,
		clue = roll(rng, "cross", 3),
		where = "wall",
		s = 3,
		w = 10,
		h = 5,
	})
end

-- What Comes Next: a row in a pattern and a blank; the door that fills it. Read it balancing on a beam that sways
-- across the lane.
local function whatNext(seed: number): (Kit.Section, { Room })
	local rng = rngFor(seed, 8)
	return standard({
		entry = 8,
		hops = { { gap = 5, long = 10, top = 0.5, wide = 4, look = "beam", motion = slideZ(6, 3.2, 0) } },
		gap = 5.5,
		top = 1.5,
		floorLong = 8,
		clue = roll(rng, "next", 3),
		where = "wall",
		s = 2.2,
		h = 4,
	})
end

-- Shadow Clue: a dark outline on a light board 14 studs back; the doors show slimes in colour. A side hop, then a
-- bobbing one that only reaches the door floor near its top.
local function shadowClue(seed: number): (Kit.Section, { Room })
	local rng = rngFor(seed, 9)
	return standard({
		entry = 8,
		hops = {
			{ gap = 5.5, long = 6, top = 0.5, z = 5, wide = 8 } :: HopSpec,
			bobHop(5.5, 0.5, 2, 2.8, 0, -3, 8),
		},
		gap = 5,
		top = 3.5,
		floorLong = 10,
		clue = roll(rng, "shadow", 3),
		where = "back",
		back = 14,
		s = 3.6,
		w = 8,
		h = 6,
		look = "pad",
	})
end

-- Behind the Sweep: a red goo bar slides across in front of a raised board and hides it half the time; a low goo
-- bar sweeps the door floor, so you slip in behind it (or jump it).
local function behindSweep(seed: number): (Kit.Section, { Room })
	local rng = rngFor(seed, 10)
	return standard({
		entry = 8,
		hops = { { gap = 6, long = 6, top = 0.5, wide = 10 } },
		gap = 5.5,
		top = 1.5,
		floorLong = 10,
		clue = roll(rng, "match", 3),
		where = "raised",
		s = 3.4,
		w = 8,
		h = 6,
		sweep = { amp = 9, period = 3.4 },
		bar = { amp = 7.5, period = 3, wide = 9 },
	})
end

-- Blink Board: the board only shows its clue 0.8 s of every 3.6 s beat bar; catch it, then time the bobbing hop.
local function blinkBoard(seed: number): (Kit.Section, { Room })
	local rng = rngFor(seed, 11)
	local kind = if rng:int(1, 2) == 1 then "match" else "slime"
	return standard({
		entry = 10,
		hops = { bobHop(5, 0.5, 2, 3, 0) },
		gap = 5,
		top = 3,
		floorLong = 8,
		clue = roll(rng, kind, 3),
		where = "wall",
		s = 3.4,
		w = 8,
		h = 6,
		blink = { beat = 6, on = 0.8 },
	})
end

-- Side Glance: three hops bobbing out of step, the board 12 studs off to the left facing them: read it while hopping.
local function sideGlance(seed: number): (Kit.Section, { Room })
	local rng = rngFor(seed, 12)
	local kind = if rng:int(1, 2) == 1 then "match" else "count"
	local clue = roll(rng, kind, 3, 4)
	local parts: { Part } = {}
	floor(parts, 0, 8, 0, 1)
	local x = 8
	local mids = {}
	for k = 1, 3 do
		local x0 = x + 5.5
		x = hop(parts, x0, 6, 0.5 * k, 3, 10, bob(2, 2.6, (k - 1) / 3))
		mids[k] = x0 + 3
	end
	local top = 2.5
	local f0 = x + 5.5
	local D = f0 + 6
	floor(parts, f0, D, top, 1)
	local r = room(parts, D, top, clue)
	local length = exit(parts, r.x1, top)
	local pl: Plane = { x = mids[2], y = 1 + 3.5, z = -11.5, facing = "z" }
	board(parts, pl, clue.boards[1], { s = 3.2, w = 8, h = 5 })
	return Kit.section(length, top, parts), { r }
end

-- Two Rooms: a bobbing hop, room 1 (three doors, a rule clue on its own board), then room 2 (two doors) whose board
-- hangs inside room 1's corridors: the one in the right corridor tells the truth, the others show the wrong door.
-- Room 2's door floor cracks 2.5 s after you land, so you must already know the answer.
local function twoRooms(seed: number): (Kit.Section, { Room })
	local rng = rngFor(seed, 13)
	local kinds = { "cross", "count", "next" }
	local clue1 = roll(rng, kinds[rng:int(1, #kinds)], 3, 5)
	local clue2 = roll(rng, if rng:int(1, 2) == 1 then "match" else "shadow", 2)
	local parts: { Part } = {}
	floor(parts, 0, 8, 0, 1)
	local hx = hop(parts, 13.5, 6, 0, 0, 10, bob(2, 2.4, 0))
	local top1 = 2.5
	local f1 = hx + 5.5
	local D1 = f1 + 6
	floor(parts, f1, D1, top1, 1)
	local r1 = room(parts, D1, top1, clue1)
	local top2 = 4
	local f2 = r1.x1 + EXIT_GAP
	local D2 = f2 + 6
	floor(parts, f2, D2, top2, 1, nil, nil, { motion = { kind = "melt", on = "land", delay = 2.5, away = 2 } })
	local r2 = room(parts, D2, top2, clue2)
	local length = exit(parts, r2.x1, top2)
	board(parts, overWall(D1, top1, 5), clue1.boards[1], { s = if clue1.kind == "next" then 2.2 else 3, w = 8, h = 5 })
	-- room 2's boards, one per room-1 corridor, high at its far end
	local wrong2 = if clue2.right == 1 then 2 else 1
	for i, z in r1.centres do
		local syms = if i == clue1.right
			then clue2.boards[1]
			else {
				if clue2.kind == "shadow"
					then { t = "shadow", kind = clue2.doors[wrong2].kind }
					else copySym(clue2.doors[wrong2]),
			}
		board(parts, { x = r1.x1 - 0.6, y = top1 + 5.8 + 1.6, z = z, facing = "x" }, syms, {
			s = 2.4,
			w = 5,
			h = 3.2,
			look = if clue2.kind == "shadow" then "pad" else nil,
		})
	end
	return Kit.section(length, top2, parts), { r1, r2 }
end

-- Mix Clue: board A a colour, board B a shape: the door with both. Three narrow hops sway across the lane in
-- opposite phase, close enough to jump between only part of the time.
local function mixClue(seed: number): (Kit.Section, { Room })
	local rng = rngFor(seed, 14)
	return standard({
		entry = 8,
		hops = {
			swayHop(5, 0.5, 7, 3.4, 0),
			swayHop(6, 1, 7, 3.4, 0.5),
			swayHop(6, 1.5, 7, 3.4, 0),
		},
		gap = 5,
		top = 2,
		floorLong = 8,
		clue = roll(rng, "mix", 3),
		where = "wall",
		s = 3.2,
		w = 7,
		h = 5,
	})
end

-- Closing Doors: the doors open 1 s of every 3.6 s beat bar; the door floor cracks 3.4 s after you land, so time the
-- landing too. Read the board 20 studs back while you time the bobbing hop.
local function closingDoors(seed: number): (Kit.Section, { Room })
	local rng = rngFor(seed, 15)
	local kinds = { "match", "cross", "count" }
	return standard({
		entry = 10,
		hops = { bobHop(5, 0.5, 2, 2.6, 0) },
		gap = 5,
		top = 3,
		floorLong = 6,
		clue = roll(rng, kinds[rng:int(1, #kinds)], 3, 5),
		where = "back",
		back = 20,
		s = 3.2,
		w = 8,
		h = 5,
		gates = { beat = 6, duty = 0.72 },
		floorMelt = 3.4,
	})
end

-- Remember It: the board at the start, four narrow hops bobbing in opposite phase, then three doors with no board.
local function rememberIt(seed: number): (Kit.Section, { Room })
	local rng = rngFor(seed, 16)
	local hops = {}
	for k = 1, 4 do
		local odd = k % 2 == 1
		table.insert(hops, bobHop(5.5, 0, 2, 2.2, if odd then 0 else 0.5, if odd then -3 else 3, 8))
	end
	return standard({
		entry = 8,
		hops = hops,
		gap = 5.5,
		top = 0,
		floorLong = 6,
		clue = roll(rng, if rng:int(1, 2) == 1 then "match" else "slime", 3),
		where = "entry",
		s = 3.4,
		w = 8,
		h = 5,
	})
end

-- Clue Up High: three blocks climb 3 studs each to a ledge 9 up, the middle one bobbing; the board lies flat on the
-- ledge, readable only from up there. Drop down to the door floor and pick.
local function clueUpHigh(seed: number): (Kit.Section, { Room })
	local rng = rngFor(seed, 17)
	local clue = roll(rng, if rng:int(1, 2) == 1 then "cross" else "shadow", 3)
	local parts: { Part } = {}
	floor(parts, 0, 8, 0, 1)
	floor(parts, 12.5, 20.5, 3, 3, 8, -6)
	floor(parts, 24.5, 32.5, 6, 3, 8, -6, { motion = bob(1, 2.6, 0) })
	floor(parts, 36.5, 44.5, 9, 3, 8, -6)
	local f0 = 50.5
	local D = f0 + 6
	floor(parts, f0, D, 0, 1)
	local r = room(parts, D, 0, clue)
	local length = exit(parts, r.x1, 0)
	local pl: Plane = { x = 40.5, y = 9 + 0.02 + FACE / 2 + FACE, z = -6, facing = "y" }
	board(parts, pl, clue.boards[1], {
		s = if clue.kind == "cross" then 2.6 else 3.6,
		w = 6.8,
		h = 6.8,
		look = if clue.kind == "shadow" then "pad" else nil,
	})
	return Kit.section(length, 0, parts), { r }
end

local MAKES: { Make } = {
	colourMatch,
	twoDoors,
	sameSlime,
	shapeOnly,
	floorClue,
	countDots,
	crossOut,
	whatNext,
	shadowClue,
	behindSweep,
	blinkBoard,
	sideGlance,
	twoRooms,
	mixClue,
	closingDoors,
	rememberIt,
	clueUpHigh,
}

---------------------------------------------------------------------------
-- Generator
---------------------------------------------------------------------------

local GEN: { [string]: { kinds: { string }, twists: { string }, salt: number } } = {
	easy = { kinds = { "match", "shape", "slime" }, twists = { "wall", "back" }, salt = 901 },
	medium = {
		kinds = { "count", "cross", "next", "shadow" },
		twists = { "wall", "back", "sweep", "blink" },
		salt = 902,
	},
	hard = {
		kinds = { "cross", "next", "shadow", "mix", "count" },
		twists = { "gates", "blink", "remember" },
		salt = 903,
	},
}

-- A seeded room from the tier's clue kinds, approach and board twist (design "generator"). Easy: one narrow side
-- hop (or a slow bobbing one) and a long jump up. Medium: a bobbing hop you leave near its top. Hard: two or three
-- narrow hops swaying in opposite phase (or bobbing ones for "remember"), plus closing doors on a cracking floor, a
-- short blink or no board at the doors.
local function generate(seed: number, tier: string): (Kit.Section, { Room })
	local g = GEN[tier] or GEN.easy
	local rng = rngFor(seed, g.salt)
	local kind = g.kinds[rng:int(1, #g.kinds)]
	local twist = g.twists[rng:int(1, #g.twists)]
	local doors = if tier == "easy" and kind ~= "slime" then rng:int(2, 3) else 3
	local clue = roll(rng, kind, doors, if tier == "hard" then 5 else 4)
	local hops: { HopSpec } = {}
	local top, gap = 1.5, 4.5
	if tier == "easy" then
		if rng:int(1, 2) == 1 then
			local side = if rng:int(1, 2) == 1 then -4 else 4
			hops = { { gap = 5.5, long = 6, top = 0.5, z = side, wide = 8 } }
			gap = 5.5 + rng:int(0, 1) * 0.5
		else
			hops = { bobHop(5, 0.5, 1.5, 3.6, 0) }
			top = 2.5
		end
	elseif tier == "medium" then
		hops = { bobHop(5, 0, 2, rng:int(26, 30) / 10, 0) }
		top, gap = 3, 5
	else
		local period = rng:int(30, 34) / 10
		if twist == "remember" then
			for k = 1, 3 do
				local odd = k % 2 == 1
				table.insert(hops, bobHop(5.5, 0, 2, period, if odd then 0 else 0.5, if odd then -3 else 3, 8))
			end
			top, gap = 0, 5
		else
			local count = rng:int(2, 3)
			for k = 1, count do
				table.insert(hops, swayHop(if k == 1 then 5 else 6, 0.5 * k, 7, period, if k % 2 == 1 then 0 else 0.5))
			end
			top = 0.5 * count + 0.5
		end
	end
	local back = rng:int(12, 16)
	local o: Std = {
		entry = if twist == "remember" then 8 else 10,
		hops = hops,
		gap = gap,
		top = top,
		floorLong = if twist == "back" then back else 8,
		clue = clue,
		where = "wall",
		s = if kind == "next" then 2.2 else 3.2,
		w = 8,
		h = 5,
		look = if kind == "shadow" then "pad" else nil,
	}
	if twist == "back" then
		o.where, o.back = "back", back
	elseif twist == "sweep" then
		o.where, o.sweep, o.w = "raised", { amp = 9, period = 3.4 }, 8
		o.bar = { amp = 7.5, period = rng:int(30, 32) / 10, wide = 9 }
		o.floorLong = 10
	elseif twist == "blink" then
		o.blink = { beat = 6, on = if tier == "hard" then 0.8 else 1 }
	elseif twist == "gates" then
		o.gates = { beat = 6, duty = 0.72 }
		o.floorLong = 6
		o.floorMelt = 3.4
	elseif twist == "remember" then
		o.where = "entry"
	end
	if kind == "mix" then
		o.w = 7 -- two boards side by side
		if o.where == "raised" then
			o.where = "wall"
		end
	end
	return standard(o)
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

local M = {}
M.id = "ClueDoors"
M.name = "Clue Doors"
M.idea = 29

local NAMES: { { string } } = {
	{ "Colour Match", "easy" },
	{ "Two Doors", "easy" },
	{ "Same Slime", "easy" },
	{ "Shape Only", "easy" },
	{ "Floor Clue", "easy" },
	{ "Count the Dots", "medium" },
	{ "Cross Out", "medium" },
	{ "What Comes Next", "medium" },
	{ "Shadow Clue", "medium" },
	{ "Behind the Sweep", "medium" },
	{ "Blink Board", "medium" },
	{ "Side Glance", "medium" },
	{ "Two Rooms", "hard" },
	{ "Mix Clue", "hard" },
	{ "Closing Doors", "hard" },
	{ "Remember It", "hard" },
	{ "Clue Up High", "hard" },
}

local variants: { Kit.Variant } = {}
for i, entry in NAMES do
	local make = MAKES[i]
	table.insert(variants, {
		name = entry[1],
		tier = entry[2],
		build = function(seed: number): Kit.Section
			local section = make(seed)
			return section
		end,
	})
end
M.variants = variants

M.generator = {
	tiers = { "easy", "medium", "hard" },
	examples = 6,
	build = function(seed: number, tier: string): Kit.Section
		local section = generate(seed, tier)
		return section
	end,
}

-- The section and its rooms (clue, right door, corridors) for variant `index` (0 = the generator at `tier`).
function M.inspect(index: number, seed: number, tier: string?): (Kit.Section, { Room })
	if index == 0 then
		return generate(seed, tier or "easy")
	end
	return MAKES[index](seed)
end

M.SHAPES = SHAPES
M.SLIMES = SLIMES
M.COLOURS = #COLOURS

return M
