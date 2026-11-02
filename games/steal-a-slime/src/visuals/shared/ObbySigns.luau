--!strict
--[[
	ObbySigns (Instance builders, no Roblox API at load time; docs/obby-signs-proposal.html, style A)

	The obby's picture signs: wordless pictures that show how a section works. Every pictogram is built from Frames,
	UICorner (circles, pills), UIStroke (rings, outlines) and rotated Frames (lines, arrows, chevrons); the only
	text is digits (a stopwatch's seconds, a countdown, the cannon's step numbers). No image uploads.

	  ObbySigns.IDS                      every pictogram id, sorted
	  ObbySigns.has(id) -> boolean
	  ObbySigns.paint(gui, slots, deps?) fills a banner's SurfaceGui: a picture per slot at its place across the lane
	  ObbySigns.boosters(banner, deps?)  a flaming booster engine under each end of a banner (adornments, particles)

	Every sign in the obby is the same banner (ObbyCourse.SIGN: lane-wide, the height over the floor, the slot size),
	hovering on two boosters: one picture is one square slot, placed over the part of the lane it is about. The
	cannon's four steps are four slots (cannon1..cannon4, each with its step number). A slot draws on a 100 x 100 grid
	(x right, y down, like the proposal's SVGs).

	`deps` ({ Instance, Enum, UDim, UDim2, Color3, Vector2, Vector3, CFrame, ColorSequence, ColorSequenceKeypoint,
	NumberSequence, NumberSequenceKeypoint, NumberRange }) is the Roblox globals in the game and @lune/roblox's in
	tests. ObbyCourse hangs the banners and ObbyParts builds them (contract/obby-sections.md §8b).
]]

export type Deps = {
	Instance: any,
	Enum: any,
	UDim: any,
	UDim2: any,
	Color3: any,
	Vector2: any,
	Vector3: any?,
	CFrame: any?,
	ColorSequence: any?,
	ColorSequenceKeypoint: any?,
	NumberSequence: any?,
	NumberSequenceKeypoint: any?,
	NumberRange: any?,
}

local ObbyCourse = if script
	then require((game :: any):GetService("ReplicatedStorage").Shared.ObbyCourse)
	else require("../../shared/ObbyCourse")

local ObbySigns = {}

-- Sizes. Read distance on a phone (landscape, 390 px tall): one stud at 26 studs is about 10.7 px
-- (guides/roblox-world-labels.md), so a 14 px shape is 1.3 studs; the main shape of every pictogram is at least that.
-- The board's geometry (post, height, slot, margins) is ObbyCourse.SIGN; these are how it is drawn.
ObbySigns.SIZE = table.freeze({
	pixelsPerStud = 50,
	maxDistance = 60,
	rim = 0.12, -- studs: the board's white rim
	phonePxPerStud = 10.7, -- at the read distance below
	readDistance = 26,
	minShapePx = 14, -- the main shape on a phone at the read distance
	minLine = 0.12, -- studs: the thinnest stroke or dot on any board
	-- The boosters under the banner's ends (studs): a body, an orange band and a bell nozzle pointing down, and a
	-- flame of built-in fire particles. Body + nozzle make ObbyCourse.SIGN.hang; the radius stays within SIGN.reach.
	booster = table.freeze({
		radius = 0.85,
		body = 1.2,
		nozzle = 0.7,
		band = 0.3,
		inset = 1.2, -- the booster's middle in from the banner's end
		flameRate = 30, -- particles a second per booster (a course has a handful of banners in view)
		flameSpeed = 7,
		flameLife = 0.4,
		flameSize = 1.6,
		texture = "rbxasset://textures/particles/fire_main.dds",
	}),
})

-- Line widths and dot sizes on the 100-unit panel grid.
local W = table.freeze({ thin = 4, line = 5.5, bold = 7.5, dot = 3.4 })

local function rgb(r: number, g: number, b: number): { number }
	return table.freeze({ r, g, b })
end

-- Colours: the obby's looks (visuals/shared/ObbyParts LOOKS) where a sign shows that thing, else the sign's own.
local C = table.freeze({
	board = rgb(46, 38, 70), -- ObbyParts.COLORS.sign
	white = rgb(255, 255, 255),
	hazard = rgb(215, 20, 25), -- the hazard look
	hazardEdge = rgb(90, 0, 10),
	shine = rgb(255, 138, 138),
	mint = rgb(108, 242, 194), -- the cannon's aim dots on target
	gold = rgb(255, 205, 60), -- keys, glow tiles
	star = rgb(255, 220, 80),
	orange = rgb(255, 150, 50), -- spring pads, belts, the cannon's band
	lime = rgb(150, 230, 70), -- goo, ladders, vines
	sticky = rgb(175, 240, 40),
	print = rgb(95, 145, 20),
	violet = rgb(185, 140, 255), -- jelly
	gate = rgb(150, 90, 220),
	grey = rgb(140, 136, 166),
	barrel = rgb(70, 66, 96), -- the cannon look
	pink = rgb(255, 126, 194),
	boost = rgb(255, 215, 50),
	slow = rgb(110, 120, 200), -- the back strip
	night = rgb(13, 10, 26),
	warm = rgb(255, 226, 170),
	green = rgb(80, 215, 120),
	moon = rgb(200, 190, 255),
	vent = rgb(168, 98, 58),
	wind = rgb(205, 230, 250),
	tile = rgb(79, 122, 74), -- a plain Glow Memory tile on the sign
	safe = rgb(80, 215, 120),
	flame = rgb(255, 90, 30), -- the booster flame's middle
	blue = rgb(90, 170, 255), -- the booster flame's tail
})

--------------------------------------------------------------------------------------------------------------------
-- Pen: draws GuiObjects on a panel's 100 x 100 grid

type Pen = {
	d: Deps,
	parent: any,
	z: number,
	px: number, -- canvas pixels per grid unit
	bg: { number }, -- the colour behind the panel (crescents and covers paint with it)
}

type Opts = {
	alpha: number?, -- 0 = solid
	round: number?, -- corner radius in grid units; nil = square corners
	full: boolean?, -- fully rounded (a circle or a pill)
	rot: number?, -- degrees, clockwise
	stroke: number?, -- outline width in grid units
	strokeColor: { number }?,
	strokeAlpha: number?,
	hollow: boolean?, -- outline only
}

local function color(pen: Pen, c: { number }): any
	return pen.d.Color3.fromRGB(c[1], c[2], c[3])
end

-- A Frame centred at (cx, cy), w x h grid units.
local function box(pen: Pen, cx: number, cy: number, w: number, h: number, c: { number }, o: Opts?): any
	local d, opts = pen.d, o or {}
	local f = d.Instance.new("Frame")
	f.Name = "Shape"
	f.AnchorPoint = d.Vector2.new(0.5, 0.5)
	f.Position = d.UDim2.fromScale(cx / 100, cy / 100)
	f.Size = d.UDim2.fromScale(w / 100, h / 100)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color(pen, c)
	f.BackgroundTransparency = if opts.hollow then 1 else (opts.alpha or 0)
	f.Rotation = opts.rot or 0
	pen.z += 1
	f.ZIndex = pen.z
	if opts.full then
		local corner = d.Instance.new("UICorner")
		corner.CornerRadius = d.UDim.new(0.5, 0)
		corner.Parent = f
	elseif opts.round then
		local corner = d.Instance.new("UICorner")
		corner.CornerRadius = d.UDim.new(0, math.round(opts.round * pen.px))
		corner.Parent = f
	end
	if opts.stroke then
		local stroke = d.Instance.new("UIStroke")
		stroke.ApplyStrokeMode = d.Enum.ApplyStrokeMode.Border
		stroke.Thickness = opts.stroke * pen.px
		stroke.Color = color(pen, opts.strokeColor or c)
		stroke.Transparency = opts.strokeAlpha or (if opts.hollow then opts.alpha or 0 else 0)
		stroke.Parent = f
	end
	f.Parent = pen.parent
	return f
end

local function dot(pen: Pen, cx: number, cy: number, r: number, c: { number }, o: Opts?): any
	local opts: Opts = if o then table.clone(o) else {}
	opts.full = true
	return box(pen, cx, cy, 2 * r, 2 * r, c, opts)
end

local function ring(pen: Pen, cx: number, cy: number, r: number, width: number, c: { number }, alpha: number?): any
	return box(pen, cx, cy, 2 * r, 2 * r, c, { full = true, hollow = true, stroke = width, alpha = alpha })
end

-- A straight stroke with round ends from (x1, y1) to (x2, y2).
local function line(
	pen: Pen,
	x1: number,
	y1: number,
	x2: number,
	y2: number,
	width: number,
	c: { number },
	alpha: number?
): any
	local dx, dy = x2 - x1, y2 - y1
	local length = math.sqrt(dx * dx + dy * dy) + width
	return box(
		pen,
		(x1 + x2) / 2,
		(y1 + y2) / 2,
		length,
		width,
		c,
		{ full = true, rot = math.deg(math.atan2(dy, dx)), alpha = alpha }
	)
end

-- An open chevron whose tip is at (x, y), pointing `angle` degrees (0 = right, 90 = down).
local function head(pen: Pen, x: number, y: number, angle: number, size: number, width: number, c: { number })
	for _, side in { -1, 1 } do
		local a = math.rad(angle + 180 + side * 40)
		line(pen, x, y, x + math.cos(a) * size, y + math.sin(a) * size, width, c)
	end
end

-- An arrow from (x1, y1) to its tip at (x2, y2).
local function arrow(pen: Pen, x1: number, y1: number, x2: number, y2: number, width: number, c: { number })
	line(pen, x1, y1, x2, y2, width, c)
	head(pen, x2, y2, math.deg(math.atan2(y2 - y1, x2 - x1)), width * 2.2, width, c)
end

-- Points on a quadratic curve from p0 through the pull of control point p1 to p2.
local function curve(p0: { number }, p1: { number }, p2: { number }, n: number): { { number } }
	local out = {}
	for i = 0, n do
		local t = i / n
		local a, b, c = (1 - t) * (1 - t), 2 * (1 - t) * t, t * t
		table.insert(out, { a * p0[1] + b * p1[1] + c * p2[1], a * p0[2] + b * p1[2] + c * p2[2] })
	end
	return out
end

-- A jump arc: `n + 1` points from (x0, y0) to (x1, y1), `h` units above the straight line at its middle.
local function arc(x0: number, y0: number, x1: number, y1: number, h: number, n: number): { { number } }
	local out = {}
	for i = 0, n do
		local t = i / n
		table.insert(out, { x0 + (x1 - x0) * t, y0 + (y1 - y0) * t - h * 4 * t * (1 - t) })
	end
	return out
end

local function dots(pen: Pen, points: { { number } }, r: number, c: { number }, alpha: number?)
	for _, p in points do
		dot(pen, p[1], p[2], r, c, { alpha = alpha })
	end
end

-- A polyline through `points` (a curve is a chain of short strokes).
local function path(pen: Pen, points: { { number } }, width: number, c: { number }, alpha: number?)
	for i = 2, #points do
		line(pen, points[i - 1][1], points[i - 1][2], points[i][1], points[i][2], width, c, alpha)
	end
end

-- A curved arrow along `points`, its tip at the last point.
local function curvedArrow(pen: Pen, points: { { number } }, width: number, c: { number })
	path(pen, points, width, c)
	local a, b = points[#points - 1], points[#points]
	head(pen, b[1], b[2], math.deg(math.atan2(b[2] - a[2], b[1] - a[1])), width * 2.2, width, c)
end

-- The runner: a round head over a capsule body, in a box w x h whose top-left is (x, y) (the proposal's `fig`).
local function figure(pen: Pen, x: number, y: number, w: number, h: number, c: { number }?)
	local ink = c or C.white
	box(pen, x + w / 2, y + h * 27.5 / 40, w * 14 / 20, h * 25 / 40, ink, { full = true })
	dot(pen, x + w / 2, y + h * 7 / 40, w * 6.5 / 20, ink)
end

-- An eight-point star: two squares a quarter turn apart (the course's star marker).
local function star(pen: Pen, cx: number, cy: number, size: number)
	box(pen, cx, cy, size * 0.72, size * 0.72, C.star)
	box(pen, cx, cy, size * 0.72, size * 0.72, C.star, { rot = 45 })
end

-- A crescent: a disc with a disc of `cover` (the colour behind it) bitten out of its upper right.
local function crescent(pen: Pen, cx: number, cy: number, r: number, c: { number }, cover: { number }, alpha: number?)
	dot(pen, cx, cy, r, c, { alpha = alpha })
	dot(pen, cx + r * 0.45, cy - r * 0.35, r * 0.82, cover)
end

-- Digits (the only text a sign may show).
local function digits(pen: Pen, cx: number, cy: number, w: number, h: number, text: string, c: { number }): any
	assert(string.match(text, "^[%d ]+$"), `obby sign text must be digits: {text}`)
	local d = pen.d
	local label = d.Instance.new("TextLabel")
	label.Name = "Digits"
	label.AnchorPoint = d.Vector2.new(0.5, 0.5)
	label.Position = d.UDim2.fromScale(cx / 100, cy / 100)
	label.Size = d.UDim2.fromScale(w / 100, h / 100)
	label.BackgroundTransparency = 1
	label.Font = d.Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = color(pen, c)
	label.TextScaled = true
	pen.z += 1
	label.ZIndex = pen.z
	label.Parent = pen.parent
	return label
end

-- The jump button: a ring with an up chevron.
local function jumpButton(pen: Pen, cx: number, cy: number, r: number)
	ring(pen, cx, cy, r, W.thin, C.white)
	head(pen, cx, cy - r * 0.35, -90, r * 0.6, W.thin, C.white)
end

-- A stopwatch: a ring with a crown and the seconds inside.
local function stopwatch(pen: Pen, cx: number, cy: number, r: number, seconds: string)
	box(pen, cx, cy - r - 3, r * 0.5, 6, C.white, { round = 1.5 })
	ring(pen, cx, cy, r, W.line, C.white)
	digits(pen, cx, cy + r * 0.06, r * 1.3, r * 1.2, seconds, C.white)
end

-- The cannon barrel at (cx, cy), turned `rot` degrees (0 = muzzle right), with its orange band at the muzzle.
local function barrel(pen: Pen, cx: number, cy: number, rot: number, scale: number)
	local a = math.rad(rot)
	box(
		pen,
		cx,
		cy,
		34 * scale,
		18 * scale,
		C.barrel,
		{ round = 8 * scale, rot = rot, stroke = 3, strokeColor = C.white }
	)
	local bx, by = cx + math.cos(a) * 13 * scale, cy + math.sin(a) * 13 * scale
	box(pen, bx, by, 8 * scale, 22 * scale, C.orange, { round = 3 * scale, rot = rot })
end

-- A grid of rounded tiles: `cols` x `rows` cells of `cell` units from top-left (x0, y0); `lit[i]` (row-major index)
-- makes cell i gold with a glow, `fake[i]` pink, `cracked[i]` adds a red crack.
type GridOpts = { lit: { [number]: boolean }?, fake: { [number]: boolean }?, cracked: { [number]: boolean }? }
local function grid(
	pen: Pen,
	x0: number,
	y0: number,
	cell: number,
	gap: number,
	cols: number,
	rows: number,
	o: GridOpts
)
	for r = 1, rows do
		for c = 1, cols do
			local i = (r - 1) * cols + c
			local cx, cy = x0 + (c - 1) * (cell + gap) + cell / 2, y0 + (r - 1) * (cell + gap) + cell / 2
			if o.lit and o.lit[i] then
				box(pen, cx, cy, cell + 6, cell + 6, C.gold, { round = 6, alpha = 0.6 })
				box(pen, cx, cy, cell, cell, C.gold, { round = 4 })
			elseif o.fake and o.fake[i] then
				box(pen, cx, cy, cell, cell, C.pink, { round = 4 })
			else
				box(
					pen,
					cx,
					cy,
					cell,
					cell,
					C.tile,
					{ round = 4, stroke = 2, strokeColor = C.white, strokeAlpha = 0.5 }
				)
			end
			if o.cracked and o.cracked[i] then
				local s = cell / 20
				path(pen, {
					{ cx - 4 * s, cy + 6 * s },
					{ cx, cy },
					{ cx - 5 * s, cy - 3 * s },
					{ cx, cy - 9 * s },
				}, 3, C.hazard)
			end
		end
	end
end

-- The eye over the Glow Memory grids: an almond (a pill) with a dark pupil.
local function eye(pen: Pen, cx: number, cy: number)
	box(pen, cx, cy, 40, 17, C.white, { full = true })
	dot(pen, cx, cy, 6.5, C.board)
end

--------------------------------------------------------------------------------------------------------------------
-- Pictograms

type Draw = (pen: Pen) -> ()
local PICTURES: { [string]: Draw } = {}

-- Aim the Cannon: four steps, one slot each, numbered.
local function stepNumber(pen: Pen, n: number)
	dot(pen, 9, 9, 8, C.white)
	digits(pen, 9, 10, 11, 13, tostring(n), C.board)
end

local function cannonWalkIn(pen: Pen)
	stepNumber(pen, 1)
	box(pen, 50, 87, 92, 6, C.white, { round = 2, alpha = 0.5 })
	barrel(pen, 68, 57, -25, 1.25)
	dot(pen, 64, 73, 8.5, C.grey, { stroke = 2.5, strokeColor = C.white })
	figure(pen, 8, 48, 18, 36)
	arrow(pen, 30, 66, 46, 66, W.bold, C.white)
end

local function cannonSwings(pen: Pen)
	stepNumber(pen, 2)
	curvedArrow(pen, curve({ 50, 44 }, { 30, 44 }, { 16, 70 }, 6), W.line, C.white)
	curvedArrow(pen, curve({ 50, 44 }, { 70, 44 }, { 84, 70 }, 6), W.line, C.white)
	box(pen, 50, 76, 28, 36, C.barrel, { round = 11, stroke = 3, strokeColor = C.white })
	box(pen, 50, 59, 32, 8, C.orange, { round = 3 })
	dots(pen, arc(46, 36, 18, 14, 4, 4), W.dot, C.hazard)
	dots(pen, arc(54, 36, 84, 14, 4, 4), W.dot, C.hazard)
end

local function cannonJump(pen: Pen)
	stepNumber(pen, 3)
	barrel(pen, 22, 58, -30, 1.1)
	dot(pen, 20, 71, 7.5, C.grey, { stroke = 2.5, strokeColor = C.white })
	dots(pen, arc(38, 46, 84, 62, 46, 8), W.dot, C.mint)
	box(pen, 84, 79, 28, 6, C.white, { round = 2, alpha = 0.3 })
	star(pen, 84, 68, 20)
	jumpButton(pen, 50, 84, 12)
	for _, ray in { { 34, 84, 27, 84 }, { 36, 74, 31, 70 }, { 64, 74, 69, 70 }, { 66, 84, 73, 84 } } do
		line(pen, ray[1], ray[2], ray[3], ray[4], W.thin, C.gold)
	end
end

local function cannonLand(pen: Pen)
	stepNumber(pen, 4)
	dots(pen, arc(4, 40, 46, 56, 34, 7), W.dot, C.mint)
	box(pen, 58, 82, 56, 10, C.white, { round = 3, alpha = 0.2 })
	star(pen, 58, 66, 22)
	figure(pen, 50, 34, 16, 32)
	line(pen, 38, 72, 32, 68, W.thin, C.white)
	line(pen, 80, 72, 86, 68, W.thin, C.white)
end

PICTURES.cannon1 = cannonWalkIn
PICTURES.cannon2 = cannonSwings
PICTURES.cannon3 = cannonJump
PICTURES.cannon4 = cannonLand

-- Rolling Blobs: red balls roll down at you, step aside.
PICTURES.blobs = function(pen)
	path(pen, { { 30, 10 }, { 70, 10 }, { 96, 96 }, { 4, 96 }, { 30, 10 } }, W.thin, C.white, 0.45)
	for _, x in { 38, 48, 58 } do
		line(pen, x, 16, x, 30, W.thin, C.white)
	end
	dot(pen, 46, 54, 19, C.hazard, { stroke = 4, strokeColor = C.hazardEdge })
	dot(pen, 39, 47, 4.5, C.shine)
	figure(pen, 72, 58, 18, 36)
	curvedArrow(pen, curve({ 44, 88 }, { 58, 96 }, { 72, 84 }, 5), W.line, C.white)
end

-- Climb: red drops fall down the ladder; wait for one to pass, then climb.
PICTURES.drips = function(pen)
	for _, x in { 30, 70 } do
		line(pen, x, 22, x, 96, 6, C.lime)
	end
	for _, y in { 38, 56, 74, 92 } do
		line(pen, 30, y, 70, y, 6, C.lime)
	end
	box(pen, 50, 12, 26, 13, C.grey, { round = 3, stroke = 2.5, strokeColor = C.white })
	-- the drop: a dark outline under a red teardrop (a disc with a corner of a square on top)
	box(pen, 50, 39, 19, 19, C.hazardEdge, { rot = 45, round = 2 })
	dot(pen, 50, 52, 14, C.hazardEdge)
	box(pen, 50, 40, 14, 14, C.hazard, { rot = 45, round = 2 })
	dot(pen, 50, 52, 11, C.hazard)
	arrow(pen, 88, 28, 88, 74, W.bold, C.white)
	figure(pen, 2, 56, 19, 38)
end

-- Glow Memory: watch, the glowing tiles are the path, the others crack. The variants add their twist on the same
-- board (GlowMemory picks one per variant through the section's `sign`).
local GLOW_PATH = { [2] = true, [4] = true, [8] = true }

PICTURES.glow = function(pen)
	eye(pen, 50, 13)
	grid(pen, 16.5, 31, 19, 5, 3, 3, { lit = GLOW_PATH, cracked = { [6] = true } })
end

-- Step on the button, then the path glows.
PICTURES.glowButton = function(pen)
	box(pen, 22, 90, 38, 9, C.grey, { round = 3 })
	box(pen, 22, 84, 20, 8, C.gold, { full = true })
	figure(pen, 13, 44, 18, 36)
	arrow(pen, 38, 58, 50, 50, W.line, C.white)
	grid(pen, 56, 18, 18, 5, 2, 3, { lit = { [1] = true, [4] = true, [5] = true } })
end

-- Pink tiles are the fakes: they crack.
PICTURES.glowPink = function(pen)
	eye(pen, 50, 13)
	local pink = { [1] = true, [3] = true, [5] = true, [9] = true }
	grid(pen, 16.5, 31, 19, 5, 3, 3, { fake = pink, cracked = pink })
end

-- The map is behind you: turn round, read it, go.
PICTURES.glowBehind = function(pen)
	box(pen, 28, 52, 44, 56, C.board, { round = 4, stroke = W.thin, strokeColor = C.white })
	grid(pen, 11, 31, 10, 3.5, 3, 4, { lit = { [2] = true, [6] = true, [8] = true, [10] = true } })
	figure(pen, 66, 50, 18, 36)
	curvedArrow(pen, curve({ 84, 48 }, { 84, 14 }, { 54, 14 }, 6), W.line, C.white)
end

-- One look only: the path glows once.
PICTURES.glowOnce = function(pen)
	eye(pen, 36, 13)
	dot(pen, 76, 13, 11, C.white)
	digits(pen, 76, 14, 14, 17, "1", C.board)
	grid(pen, 16.5, 31, 19, 5, 3, 3, { lit = GLOW_PATH })
end

-- A new path every 8 seconds.
PICTURES.glowRounds = function(pen)
	stopwatch(pen, 50, 24, 17, "8")
	grid(pen, 3, 52, 11, 3, 3, 3, { lit = { [2] = true, [4] = true, [8] = true } })
	grid(pen, 58, 52, 11, 3, 3, 3, { lit = { [3] = true, [5] = true, [7] = true } })
	arrow(pen, 44, 62, 56, 62, W.thin, C.white)
	arrow(pen, 56, 80, 44, 80, W.thin, C.white)
end

-- Hot feet: even the safe tiles crack soon after you land, so keep running.
PICTURES.glowRush = function(pen)
	grid(pen, 5, 60, 28, 3, 3, 1, { lit = { [1] = true, [2] = true, [3] = true }, cracked = { [1] = true } })
	figure(pen, 46, 18, 18, 36)
	for _, y in { 30, 40, 50 } do
		line(pen, 26, y, 38, y, W.thin, C.white)
	end
	arrow(pen, 72, 40, 92, 40, W.bold, C.white)
end

-- Beat Pads: count the beat, jump on the gold beat from full pad to full pad.
PICTURES.beat = function(pen)
	dot(pen, 26, 14, 6, C.white, { alpha = 0.5 })
	dot(pen, 48, 14, 6, C.white, { alpha = 0.5 })
	dot(pen, 72, 14, 9.5, C.gold)
	box(pen, 24, 86, 42, 15, C.violet, { full = true, stroke = 2.5, strokeColor = C.white })
	box(pen, 78, 86, 42, 15, C.violet, { full = true, stroke = 2.5, strokeColor = C.white })
	box(pen, 78, 86, 18, 7, C.white, { full = true, hollow = true, stroke = 2, alpha = 0.3 })
	figure(pen, 15, 46, 18, 36)
	dots(pen, arc(36, 46, 72, 64, 30, 8), W.dot, C.white)
	head(pen, 74, 68, 60, 10, W.line, C.white)
end

-- Key Run: grab the gold keys, the gate opens.
PICTURES.key = function(pen)
	ring(pen, 18, 50, 13, 7, C.gold)
	line(pen, 33, 50, 54, 50, 7, C.gold)
	line(pen, 50, 50, 50, 61, 6, C.gold)
	line(pen, 42, 50, 42, 58, 6, C.gold)
	arrow(pen, 58, 50, 67, 50, W.line, C.white)
	box(pen, 85, 52, 24, 78, C.gate, { round = 3, alpha = 0.45, stroke = 2.5, strokeColor = C.white })
	ring(pen, 85, 32, 7, 4.5, C.gold)
	box(pen, 85, 34, 9, 9, C.gate, { alpha = 0.45 })
	line(pen, 78, 32, 78, 42, 4.5, C.gold)
	box(pen, 85, 50, 20, 16, C.gold, { round = 3 })
end

-- Clue Doors: the board's symbol, walk through the door with the same symbol.
PICTURES.clue = function(pen)
	box(pen, 50, 21, 40, 32, C.board, { round = 4, stroke = W.thin, strokeColor = C.white })
	box(pen, 50, 21, 15, 15, C.violet, { rot = 45, round = 2 })
	for _, door in { 15, 50, 85 } do
		box(pen, door, 78, 23, 40, C.board, { round = 11, stroke = W.thin, strokeColor = C.white })
	end
	box(pen, 50, 98, 100, 6, C.board)
	line(pen, 2, 95, 98, 95, W.thin, C.white)
	dot(pen, 15, 76, 7.5, C.mint)
	box(pen, 50, 76, 14, 14, C.orange, { round = 2 })
	box(pen, 85, 76, 14, 14, C.violet, { rot = 45, round = 2 })
	curvedArrow(pen, curve({ 72, 22 }, { 86, 26 }, { 86, 50 }, 5), W.line, C.white)
end

-- Sticky Walls: jump at the green wall, you stick, jump again to the next wall.
PICTURES.sticky = function(pen)
	box(pen, 15, 51, 19, 74, C.sticky, { round = 3 })
	box(pen, 85, 43, 19, 74, C.sticky, { round = 3 })
	for _, drip in { { 11, 89 }, { 19, 89 }, { 81, 81 }, { 89, 81 } } do
		box(pen, drip[1], drip[2], 5, 5, C.sticky, { rot = 45 })
	end
	dot(pen, 15, 35, 5.5, C.print)
	for _, finger in { { 10.5, 25 }, { 15, 24 }, { 19.5, 25 } } do
		box(pen, finger[1], finger[2], 3, 9, C.print, { full = true })
	end
	figure(pen, 25, 50, 16, 32)
	line(pen, 30, 84, 30, 87, W.thin, C.white)
	line(pen, 30, 92, 30, 95, W.thin, C.white)
	dots(pen, arc(43, 52, 72, 36, 28, 8), W.dot, C.white)
	head(pen, 74, 39, 30, 10, W.line, C.white)
end

-- Moon Jump: inside the bubble your jump goes high and far.
local function moonJump(pen: Pen, moons: number)
	dot(pen, 50, 96, 46, C.moon, { alpha = 0.6, stroke = W.thin, strokeColor = C.white })
	for i = 1, moons do
		crescent(pen, 30 + (i - 1) * 26 + (if moons == 1 then 14 else 0), 22, 11, C.star, C.board)
	end
	box(pen, 78, 54, 28, 7, C.white, { round = 2 })
	figure(pen, 12, 62, 16, 32)
	local far = if moons == 1 then 78 else 92
	dots(pen, arc(28, 62, far, 46, if moons == 1 then 36 else 44, 10), W.dot, C.white)
	arrow(pen, 18, 56, 18, 38, W.line, C.white)
end

PICTURES.moon = function(pen)
	moonJump(pen, 1)
end
-- The same, lower gravity: two moons, a longer jump.
PICTURES.moon2 = function(pen)
	moonJump(pen, 2)
end

-- Speed Strip: yellow is fast (lightning), blue is slow (snail).
PICTURES.speed = function(pen)
	box(pen, 50, 27, 94, 32, C.boost, { round = 5 })
	for _, x in { 18, 34, 50 } do
		head(pen, x, 27, 0, 11, W.line, C.board)
	end
	path(pen, { { 80, 13 }, { 68, 29 }, { 80, 27 }, { 70, 42 } }, W.line, C.board)
	box(pen, 50, 73, 94, 32, C.slow, { round = 5 })
	for _, x in { 8, 24, 40 } do
		head(pen, x, 73, 180, 11, W.line, C.white)
	end
	ring(pen, 74, 70, 9, W.thin, C.white)
	line(pen, 60, 81, 90, 81, W.thin, C.white)
	line(pen, 89, 80, 86, 66, W.thin, C.white)
end

-- Arrow Maze: the floor carries you the arrow's way; pink tiles switch direction.
PICTURES.belts = function(pen)
	box(pen, 26, 59, 44, 58, C.orange, { round = 4 })
	arrow(pen, 10, 80, 38, 80, 6, C.board)
	line(pen, 8, 44, 14, 44, W.thin, C.board)
	line(pen, 8, 52, 14, 52, W.thin, C.board)
	figure(pen, 18, 30, 16, 32, C.white)
	box(pen, 75, 59, 42, 58, C.pink, { round = 4 })
	arrow(pen, 62, 48, 88, 48, W.line, C.board)
	arrow(pen, 88, 70, 62, 70, W.line, C.board)
end

-- Lights Out: in the dark, jump to the glowing green.
PICTURES.dark = function(pen)
	box(pen, 50, 50, 98, 98, C.night, { round = 8 })
	crescent(pen, 18, 18, 10, C.white, C.night, 0.2)
	dot(pen, 22, 64, 21, C.warm, { alpha = 0.78 })
	figure(pen, 15, 48, 15, 32)
	box(pen, 22, 82, 30, 5, C.white, { round = 2, alpha = 0.5 })
	dot(pen, 76, 58, 18, C.green, { alpha = 0.72 })
	dot(pen, 76, 60, 10, C.green)
	box(pen, 76, 64, 20, 8, C.green)
	box(pen, 76, 70, 30, 5, C.green, { round = 2 })
	dots(pen, arc(34, 48, 62, 48, 22, 7), W.dot, C.white)
	head(pen, 64, 51, 45, 10, W.line, C.white)
end

-- Vine Swing: jump to the green knob, swing, press jump to let go.
PICTURES.vine = function(pen)
	box(pen, 50, 9, 50, 7, C.white, { round = 3 })
	line(pen, 50, 12, 32, 54, W.line, C.lime)
	dot(pen, 31, 57, 7.5, C.lime, { stroke = 2, strokeColor = C.white })
	figure(pen, 23, 60, 15, 30)
	local swing = {}
	for i = 0, 9 do
		local a = math.rad(145 - i * 110 / 9)
		table.insert(swing, { 50 + math.cos(a) * 44, 33 + math.sin(a) * 44 })
	end
	dots(pen, swing, 2.4, C.white, 0.4)
	arrow(pen, 80, 52, 90, 32, W.line, C.white)
	jumpButton(pen, 80, 84, 11)
end

-- Geyser Field: a dead vent, wait; a glowing rim throws you up.
PICTURES.geyser = function(pen)
	for y = 8, 92, 12 do
		line(pen, 50, y, 50, y + 4, 3.5, C.white, 0.5)
	end
	box(pen, 24, 87, 38, 13, C.vent, { full = true })
	figure(pen, 16, 50, 17, 34)
	line(pen, 15, 9, 33, 9, W.line, C.white)
	line(pen, 15, 35, 33, 35, W.line, C.white)
	line(pen, 17, 10, 31, 34, W.thin, C.white)
	line(pen, 31, 10, 17, 34, W.thin, C.white)
	box(pen, 76, 87, 46, 17, C.gold, { full = true, hollow = true, stroke = 3 })
	box(pen, 76, 87, 36, 12, C.orange, { full = true })
	line(pen, 56, 80, 52, 76, W.thin, C.gold)
	line(pen, 96, 80, 100, 76, W.thin, C.gold)
	arrow(pen, 76, 76, 76, 44, W.bold, C.white)
	figure(pen, 69, 4, 15, 30)
end

-- Updraft: jump into the wind column, it carries you up.
PICTURES.updraft = function(pen)
	box(pen, 19, 70, 32, 8, C.white, { round = 2 })
	box(pen, 69, 48, 38, 80, C.wind, { round = 4, alpha = 0.65, stroke = 2.5, strokeColor = C.white })
	box(pen, 69, 91, 44, 9, C.grey, { round = 2 })
	for _, s in { { 58, 68, 1 }, { 80, 58, -1 }, { 60, 34, 1 } } do
		head(pen, s[1], s[2], if s[3] > 0 then 0 else 180, 7, W.thin, C.white)
	end
	figure(pen, 62, 18, 15, 30)
	arrow(pen, 86, 46, 86, 28, W.line, C.white)
	figure(pen, 13, 36, 15, 30)
	dots(pen, arc(29, 40, 54, 44, 14, 6), 2.8, C.white)
end

-- Two Roads: one symbol per road.
PICTURES.fast = function(pen)
	path(pen, { { 64, 8 }, { 34, 54 }, { 64, 48 }, { 36, 92 } }, 13, C.boost)
end

PICTURES.safe = function(pen)
	box(pen, 50, 38, 62, 46, C.safe, { round = 12 })
	box(pen, 50, 60, 44, 44, C.safe, { rot = 45, round = 4 })
	path(pen, { { 34, 46 }, { 46, 60 }, { 68, 34 } }, 9, C.white)
end

-- Bail out: cross the plank from the fast road to the safe one.
PICTURES.bail = function(pen)
	line(pen, 84, 8, 84, 92, 10, C.white, 0.55)
	line(pen, 16, 8, 16, 92, 10, C.white, 0.55)
	arrow(pen, 72, 22, 32, 70, 11, C.white)
end

-- Terraced roads, low on the left to high on the right: the gold one is this road.
local TERRACES = { { 20, 88 }, { 50, 68 }, { 80, 48 } }
local function terraces(pen: Pen, which: number)
	for i, t in TERRACES do
		local on = i == which
		box(pen, t[1], t[2], 38, 10, if on then C.gold else C.white, { round = 3, alpha = if on then 0 else 0.45 })
	end
	local t = TERRACES[which]
	figure(pen, t[1] - 9, t[2] - 41, 18, 36)
end

PICTURES.low = function(pen)
	terraces(pen, 1)
end
PICTURES.middle = function(pen)
	terraces(pen, 2)
end
PICTURES.high = function(pen)
	terraces(pen, 3)
end

-- The door shuts 4 s after you start.
PICTURES.door4 = function(pen)
	box(pen, 30, 62, 40, 66, C.gate, { round = 6, stroke = W.line, strokeColor = C.white })
	dot(pen, 42, 64, 4, C.white)
	stopwatch(pen, 74, 30, 18, "4")
end

-- Key Run's clock: 9 s from the first key.
PICTURES.clock9 = function(pen)
	stopwatch(pen, 50, 56, 34, "9")
end

-- Rising Goo's countdown before the goo starts.
PICTURES.countdown = function(pen)
	digits(pen, 50, 52, 96, 60, "3 2 1", C.gold)
end

local IDS = {}
for id in PICTURES do
	table.insert(IDS, id)
end
table.sort(IDS)
ObbySigns.IDS = table.freeze(IDS)

function ObbySigns.has(id: string): boolean
	return PICTURES[id] ~= nil
end

local function defaults(): Deps
	return {
		Instance = Instance,
		Enum = Enum,
		UDim = UDim,
		UDim2 = UDim2,
		Color3 = Color3,
		Vector2 = Vector2,
		Vector3 = Vector3,
		CFrame = CFrame,
		ColorSequence = ColorSequence,
		ColorSequenceKeypoint = ColorSequenceKeypoint,
		NumberSequence = NumberSequence,
		NumberSequenceKeypoint = NumberSequenceKeypoint,
		NumberRange = NumberRange,
	}
end

-- Fills `gui` (on a banner's face) with the banner: a dark plate with a white rim and one slot per picture, each
-- centred at its `z` across the lane (left to right as the runner sees it).
function ObbySigns.paint(gui: any, slots: { ObbyCourse.Slot }, deps: Deps?): any
	local d = deps or defaults()
	local S, G = ObbySigns.SIZE, ObbyCourse.SIGN
	local w, h = G.width, ObbyCourse.bannerHeight()
	local rimPx = math.round(S.rim * S.pixelsPerStud)
	local pen0: Pen = { d = d, parent = gui, z = 0, px = 1, bg = C.board }

	local root = d.Instance.new("Frame")
	root.Name = "Picture"
	root.AnchorPoint = d.Vector2.new(0.5, 0.5)
	root.Position = d.UDim2.fromScale(0.5, 0.5)
	root.Size = d.UDim2.new(1, -2 * rimPx, 1, -2 * rimPx)
	root.BorderSizePixel = 0
	root.BackgroundColor3 = color(pen0, C.board)
	root.ZIndex = 1
	local corner = d.Instance.new("UICorner")
	corner.CornerRadius = d.UDim.new(0, math.round(0.4 * S.pixelsPerStud))
	corner.Parent = root
	local rim = d.Instance.new("UIStroke")
	rim.ApplyStrokeMode = d.Enum.ApplyStrokeMode.Border
	rim.Thickness = rimPx
	rim.Color = color(pen0, C.white)
	rim.Parent = root
	root.Parent = gui

	for i, s in slots do
		local draw = PICTURES[s.id]
		assert(draw, `unknown obby sign picture {s.id}`)
		local slot = d.Instance.new("Frame")
		slot.Name = `Slot{i}`
		slot.BackgroundTransparency = 1
		slot.ClipsDescendants = true
		slot.Position = d.UDim2.fromScale((s.z + w / 2 - G.slot / 2) / w, G.pad / h)
		slot.Size = d.UDim2.fromScale(G.slot / w, G.slot / h)
		slot.ZIndex = 2
		slot.Parent = root
		draw({ d = d, parent = slot, z = 2, px = G.slot * S.pixelsPerStud / 100, bg = C.board })
	end
	return root
end

-- A booster engine under each end of `banner` (a lane-wide part, its axes the course's): a chunky body with an orange
-- band, a bell nozzle pointing down and a flame of built-in fire particles blowing down. All adornments, an
-- attachment and an emitter on the banner, so they follow its hover and add no parts.
function ObbySigns.boosters(banner: any, deps: Deps?)
	local d = deps or defaults()
	local B, G = ObbySigns.SIZE.booster, ObbyCourse.SIGN
	local pen: Pen = { d = d, parent = banner, z = 0, px = 1, bg = C.board }
	local bottom = -banner.Size.Y / 2
	local up = d.CFrame.Angles(math.rad(-90), 0, 0) -- an adornment's axis (its Z) pointing up
	for _, side in { -1, 1 } do
		local z = side * (G.width / 2 - B.inset)
		local function adorn(class: string, y: number, c: { number }): any
			local a = d.Instance.new(class)
			a.Name = "Booster"
			a.Adornee = banner
			a.CFrame = d.CFrame.new(0, y, z) * up
			a.Color3 = color(pen, c)
			a.Parent = banner
			return a
		end
		local body = adorn("CylinderHandleAdornment", bottom - B.body / 2, C.barrel)
		body.Radius, body.Height = B.radius, B.body
		local band = adorn("CylinderHandleAdornment", bottom - B.body / 2, C.orange)
		band.Radius, band.Height = B.radius + 0.08, B.band
		local cap = adorn("SphereHandleAdornment", bottom - B.body, C.grey)
		cap.Radius = B.radius * 0.75
		-- the bell: a cone (its tip at the adornment's origin) whose tip is in the body and whose mouth opens down
		local bell = adorn("ConeHandleAdornment", bottom - B.body, C.grey)
		bell.CFrame = d.CFrame.new(0, bottom - B.body, z) * d.CFrame.Angles(math.rad(90), 0, 0)
		bell.Radius, bell.Height = B.radius * 0.9, B.nozzle
		local flameAt = d.Instance.new("Attachment")
		flameAt.Name = "BoosterFlame"
		flameAt.Position = d.Vector3.new(0, bottom - B.body - B.nozzle, z)
		flameAt.Parent = banner
		local flame = d.Instance.new("ParticleEmitter")
		flame.Name = "Flame"
		flame.Texture = B.texture
		flame.EmissionDirection = d.Enum.NormalId.Bottom
		flame.Rate = B.flameRate
		flame.Speed = d.NumberRange.new(B.flameSpeed * 0.7, B.flameSpeed)
		flame.Lifetime = d.NumberRange.new(B.flameLife * 0.6, B.flameLife)
		flame.SpreadAngle = d.Vector2.new(8, 8)
		flame.LightEmission = 0.5 -- full emission washes out to white against the bright sky
		flame.Color = d.ColorSequence.new({
			d.ColorSequenceKeypoint.new(0, color(pen, C.orange)),
			d.ColorSequenceKeypoint.new(0.5, color(pen, C.flame)),
			d.ColorSequenceKeypoint.new(1, color(pen, C.blue)),
		})
		flame.Size = d.NumberSequence.new({
			d.NumberSequenceKeypoint.new(0, B.flameSize),
			d.NumberSequenceKeypoint.new(1, B.flameSize * 0.2),
		})
		flame.Transparency = d.NumberSequence.new({
			d.NumberSequenceKeypoint.new(0, 0),
			d.NumberSequenceKeypoint.new(0.6, 0.2),
			d.NumberSequenceKeypoint.new(1, 1),
		})
		flame.Parent = flameAt
	end
end

-- Every GuiObject a board holds, for the specs: (name, class, size in studs (w, h), text).
function ObbySigns.shapes(root: any): { { name: string, class: string, w: number, h: number, text: string? } }
	local side = ObbyCourse.SIGN.slot
	local out = {}
	for _, slot in root:GetChildren() do
		if slot:IsA("Frame") then
			for _, child in slot:GetChildren() do
				if child:IsA("GuiObject") then
					table.insert(out, {
						name = child.Name,
						class = child.ClassName,
						w = child.Size.X.Scale * side,
						h = child.Size.Y.Scale * side,
						text = if child:IsA("TextLabel") then child.Text else nil,
					})
				end
			end
		end
	end
	return out
end

return table.freeze(ObbySigns)
