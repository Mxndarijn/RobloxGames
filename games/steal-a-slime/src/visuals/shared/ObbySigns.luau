--!strict
--[[
	ObbySigns (Instance builders, no Roblox API at load time; docs/obby-signs-proposal.html, style A)

	The obby's picture signs: wordless pictures that show how a section works. Every pictogram is built from Frames,
	UICorner (circles, pills), UIStroke (rings, outlines) and rotated Frames (lines, arrows, chevrons); the only
	text is digits, and only where the number is the message (a stopwatch's seconds, Rising Goo's 3 2 1). No image
	uploads.

	One visual language across the set (two blind tests with three judges; contract/obby-sections.md §8b):
	  * fixed colours: red is danger only (a hazard, a fake or breaking tile), green is safe / the target only (a safe
	    tile, a lit pad, the cannon's target ring), yellow is a thing you use (a pad, a button, a key, a vent, a vine,
	    the speed pad), lilac is an ordinary platform; white is the runner, its jumps and the arrows
	  * the mechanic is the biggest thing on the board, and the runner is on every board that asks you to do something
	  * white dots are only ever the runner's own jump, evenly spaced (a launch by cannon, vent or spring draws the
	    same); a falling or rolling hazard is a solid red shape with motion streaks behind it
	  * speed is the yellow pad with chevrons; there is no lightning bolt; "watch" is an almond eye
	  * one arrow style (`arrow`) in three weights, one motion cue per picture, no leftward arrow, no step numbers: a
	    board of steps shows them left to right with an arrow between (`THEN`); a stopwatch's sweep is its seconds on
	    a ten-second dial
	  * one runner size (`runner`, 20 x 42 grid units; only Glow Memory's runner on a tile is drawn small), one ghost
	    for "where it was / goes" (`ghostBox`, `ghostRunner`: the shape as a faded lilac outline), one crack (thick
	    near black, edged white), motion streaks only on the trailing side (above a falling thing), one cannon
	    (`cannon`: wheel, tapered barrel, muzzle ring), stopwatch digits white, bold and outlined; "look" is the eye
	  * every picture draws inside the slot's safe margin (`SIZE.margin`) and keeps within 3..97 of its grid

	  ObbySigns.IDS                      every pictogram id, sorted
	  ObbySigns.has(id) -> boolean
	  ObbySigns.paint(gui, slots, deps?, height?) fills a banner's SurfaceGui: a picture per slot across the lane
	  ObbySigns.boosters(banner, deps?)  a flaming booster engine under each end of a banner (adornments, particles)

	Every sign in the obby is the same banner (ObbyCourse.SIGN: lane-wide, the height over the floor, the slot sizes),
	hovering on two boosters: one picture is one square slot, placed over the part of the lane it is about. The
	cannon's four steps are four slots (cannon1..cannon4) with an arrow between each. A slot draws on a 100 x 100
	grid (x right, y down, like the proposal's SVGs).

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
	-- Drawn out to 200 studs, a landmark sign (the guide's 200 to 300): sections run 60 to 120 studs, so from
	-- anywhere in one the next section's entry board already shows. A whole 7.2-stud picture (5 on the cannon's
	-- board of four) reads on a 720p screen from about 40 studs and its main shape is still a 30 px patch at 100;
	-- ObbyFx bobs the banner out to its MAX_DISTANCE (260), so it never shows standing still.
	maxDistance = 200,
	rim = 0.12, -- studs: the board's white rim
	phonePxPerStud = 10.7, -- at the read distance below
	readDistance = 26,
	minShapePx = 14, -- the main shape on a phone at the read distance
	minLine = 0.12, -- studs: the thinnest stroke or dot on any board
	-- A slot's safe margin each side (a fraction of the slot): the picture's grid is drawn inside it, and every
	-- picture keeps its shapes within 3..97 of that grid, so nothing comes nearer than about 8% to the slot's edge.
	margin = 0.05,
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

-- Line widths and dot sizes on the 100-unit panel grid (a board of four draws its slots 5 studs big: thin is still
-- 0.25 studs there, a pixel on a phone at 60 studs).
local W = table.freeze({ thin = 5, line = 7, bold = 9, dot = 4.4 })

local function rgb(r: number, g: number, b: number): { number }
	return table.freeze({ r, g, b })
end

-- Colours, one meaning each across the set (the second blind test's palette): hazard red is danger only, green is
-- safe / the target only, yellow (gold, boost) is a thing you use, lilac (violet) is an ordinary platform. Other
-- colours are a thing's own look where the sign shows that thing (ice, wind, the cannon, Glow Memory's pink fakes).
local C = table.freeze({
	board = rgb(46, 38, 70), -- ObbyParts.COLORS.sign
	white = rgb(255, 255, 255),
	hazard = rgb(215, 20, 25), -- the hazard look
	hazardEdge = rgb(90, 0, 10),
	gold = rgb(255, 205, 60), -- a thing you use: keys, buttons, vents, vines, spring pads
	orange = rgb(255, 150, 50), -- the cannon's band, the booster's band
	violet = rgb(185, 140, 255), -- an ordinary platform
	gate = rgb(150, 90, 220),
	grey = rgb(140, 136, 166),
	dim = rgb(96, 92, 124), -- a dead vent, a dark platform
	sweep = rgb(112, 104, 150), -- a stopwatch's sweep
	barrel = rgb(70, 66, 96), -- the cannon look
	pink = rgb(255, 126, 194),
	boost = rgb(255, 215, 50),
	slow = rgb(110, 120, 200), -- the slow strip, Sliding Maze's walls
	bubble = rgb(170, 190, 255), -- Moon Jump's bubble
	wind = rgb(205, 230, 250), -- wind columns, ice
	tile = rgb(98, 92, 140), -- a Glow Memory tile that shows nothing
	safe = rgb(80, 215, 120),
	flame = rgb(255, 90, 30), -- the booster flame's middle
	blue = rgb(90, 170, 255), -- the booster flame's tail
	ink = rgb(22, 16, 34), -- a crack's line (near black, edged white so it shows on any tile)
	jet = rgb(215, 238, 255), -- a geyser's water jet
	wood = rgb(176, 112, 62), -- the cannon's wheel
})

--------------------------------------------------------------------------------------------------------------------
-- Pen: draws GuiObjects on a panel's 100 x 100 grid

type Pen = {
	d: Deps,
	parent: any,
	z: number,
	px: number, -- canvas pixels per grid unit
	bg: { number }, -- the colour behind the panel (crescents and covers paint with it)
	o: number, -- where the grid's 0 sits in the frame, in percent (a slot's safe margin)
	k: number, -- the grid's 100 as a fraction of the frame
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
	f.Position = d.UDim2.fromScale((pen.o + cx * pen.k) / 100, (pen.o + cy * pen.k) / 100)
	f.Size = d.UDim2.fromScale(w * pen.k / 100, h * pen.k / 100)
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

-- The one arrow of the set: a round-ended white stroke with an open head, in three weights (W.line, W.bold and,
-- for a lone big arrow, 11). From (x1, y1) to its tip at (x2, y2).
local function arrow(pen: Pen, x1: number, y1: number, x2: number, y2: number, width: number, c: { number }?)
	local ink = c or C.white
	line(pen, x1, y1, x2, y2, width, ink)
	head(pen, x2, y2, math.deg(math.atan2(y2 - y1, x2 - x1)), width * 2.2, width, ink)
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

-- A jump arc: `n + 1` points from (x0, y0) to (x1, y1), `h` units above the straight line at its middle, evenly
-- spaced along the curve (so the dots never bunch at the top).
local function arc(x0: number, y0: number, x1: number, y1: number, h: number, n: number): { { number } }
	local fine, lengths = {}, { 0 }
	for i = 0, 64 do
		local t = i / 64
		table.insert(fine, { x0 + (x1 - x0) * t, y0 + (y1 - y0) * t - h * 4 * t * (1 - t) })
		if i > 0 then
			local a, b = fine[i], fine[i + 1]
			table.insert(lengths, lengths[i] + math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2))
		end
	end
	local out, k = {}, 1
	for i = 0, n do
		local want = lengths[65] * i / n
		while k < 64 and lengths[k + 1] < want do
			k += 1
		end
		local span = lengths[k + 1] - lengths[k]
		local f = if span > 0 then math.clamp((want - lengths[k]) / span, 0, 1) else 0
		local a, b = fine[k], fine[k + 1]
		table.insert(out, { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f })
	end
	return out
end

-- Points on an ellipse round (cx, cy) with radii (rx, ry) from angle `a0` to `a1` (degrees, 0 = right, 90 = down).
local function oval(cx: number, cy: number, rx: number, ry: number, a0: number, a1: number, n: number): { { number } }
	local out = {}
	for i = 0, n do
		local a = math.rad(a0 + (a1 - a0) * i / n)
		table.insert(out, { cx + math.cos(a) * rx, cy + math.sin(a) * ry })
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

-- A curved arrow along `points`, its tip at the last point (and at the first too when `both`).
local function curvedArrow(pen: Pen, points: { { number } }, width: number, both: boolean?)
	path(pen, points, width, C.white)
	local a, b = points[#points - 1], points[#points]
	head(pen, b[1], b[2], math.deg(math.atan2(b[2] - a[2], b[1] - a[1])), width * 2.2, width, C.white)
	if both then
		local p, q = points[2], points[1]
		head(pen, q[1], q[2], math.deg(math.atan2(q[2] - p[2], q[1] - p[1])), width * 2.2, width, C.white)
	end
end

-- The runner: a round head over a capsule body, in a box w x h whose top-left is (x, y) (the proposal's `fig`).
-- `alpha` fades it (a ghost: where the runner was).
local function figure(pen: Pen, x: number, y: number, w: number, h: number, c: { number }?, alpha: number?)
	local ink = c or C.white
	box(pen, x + w / 2, y + h * 27.5 / 40, w * 14 / 20, h * 25 / 40, ink, { full = true, alpha = alpha })
	dot(pen, x + w / 2, y + h * 7 / 40, w * 6.5 / 20, ink, { alpha = alpha })
end

-- The runner at the one size of the set (deliberately small cases, a runner on a memory tile, use `figure`): 20 x 42
-- units, its middle at x = `cx`, its feet at y = `foot`.
local RUNNER = table.freeze({ w = 20, h = 42 })
local function runner(pen: Pen, cx: number, foot: number)
	figure(pen, cx - RUNNER.w / 2, foot - RUNNER.h, RUNNER.w, RUNNER.h)
end

-- The one ghost of the set ("where it was" / "where it goes"): the thing's shape as a faded lilac outline.
local GHOST = table.freeze({ c = C.violet, alpha = 0.45, stroke = 3.5 })
local function ghostBox(pen: Pen, cx: number, cy: number, w: number, h: number, o: Opts?): any
	local opts: Opts = if o then table.clone(o) else {}
	opts.hollow, opts.stroke, opts.alpha = true, GHOST.stroke, GHOST.alpha
	return box(pen, cx, cy, w, h, GHOST.c, opts)
end
local function ghostRunner(pen: Pen, cx: number, foot: number)
	local w, h, x, y = RUNNER.w, RUNNER.h, cx - RUNNER.w / 2, foot - RUNNER.h
	ghostBox(pen, x + w / 2, y + h * 27.5 / 40, w * 14 / 20, h * 25 / 40, { full = true })
	ghostBox(pen, x + w / 2, y + h * 7 / 40, w * 13 / 20, w * 13 / 20, { full = true })
end

-- The runner's own jump (white dots only ever mean this): dots along `points`, ending in a solid arrow along the last
-- stretch (so its head follows the jump's line). A launch (a cannon, a vent, a spring) draws the same.
local function jumpArrow(pen: Pen, points: { { number } }, c: { number }?)
	local ink = c or C.white
	local n = #points
	dots(pen, table.move(points, 1, n - 3, 1, {}), W.dot, ink)
	arrow(pen, points[n - 2][1], points[n - 2][2], points[n][1], points[n][2], W.line, ink)
end

-- Motion streaks on the trailing side of a moving thing (above a falling one, never below or beside): `n` short
-- strokes from (x, y) on, pointing `angle` degrees (the way it came from), `gap` apart across, `len` the longest. The
-- middle one is longest and the outer ones start further back and are shorter (speed lines, never two equal upright
-- bars that read as a pause sign).
local function streaks(pen: Pen, x: number, y: number, angle: number, len: number, gap: number, n: number)
	local a = math.rad(angle)
	local ux, uy = math.cos(a), math.sin(a)
	local px, py = -uy, ux
	for k = 1, n do
		local off = (k - (n + 1) / 2) * gap
		local edge = math.abs(off) / math.max(gap, 1)
		local back = edge * len * 0.6
		local long = len * (1.2 - 0.6 * edge)
		local sx, sy = x + px * off + ux * back, y + py * off + uy * back
		line(pen, sx, sy, sx + ux * long, sy + uy * long, W.thin * 0.6, C.white, 0.3)
	end
end

-- A hazard ball: flat red with a dark rim (the hazard look; no shine), the same everywhere.
local function ball(pen: Pen, cx: number, cy: number, r: number)
	dot(pen, cx, cy, r, C.hazard, { stroke = 4, strokeColor = C.hazardEdge })
end

-- A crack: a thick near-black zigzag with a thin white edge across a tile centred at (cx, cy), `s` its size (the one
-- crack of the set: it shows on lilac, green, red and pink alike).
local function crack(pen: Pen, cx: number, cy: number, s: number)
	local zig = {
		{ cx - 0.42 * s, cy - 0.3 * s },
		{ cx - 0.1 * s, cy + 0.15 * s },
		{ cx + 0.12 * s, cy - 0.2 * s },
		{ cx + 0.42 * s, cy + 0.3 * s },
	}
	path(pen, zig, W.thin + 3, C.white)
	path(pen, zig, W.thin + 0.5, C.ink)
end

-- The crumbling floor, big: a row of floor pieces; the one behind the runner has cracked and drops (tipped, streaks
-- over it), the one under the runner cracks right through, the one ahead is whole, and one arrow says keep going. `kind` is the floor: "tile" (Melting Floor: lilac tiles), "plank" (Collapsing
-- Bridge: narrow planks) or "glow" (Glow Memory's hot feet: even the green tiles crack). Same idea, same drawing; the
-- floor's shape tells them apart.
local function crumble(pen: Pen, kind: string)
	local ink = if kind == "glow" then C.safe else C.violet
	local top = 62
	if kind == "plank" then
		-- a plank behind, cracked, dropped and tipped (streaks above it: it falls)
		box(pen, 15, 83, 12, 18, ink, { round = 2, rot = 24 })
		crack(pen, 15, 83, 11)
		streaks(pen, 15, 69, -90, 10, 7, 3)
		-- the plank under the runner cracks, the rest of the bridge is whole
		for i, x in { 32, 47, 62, 77, 92 } do
			box(pen, x, top + 10, 11, 20, ink, { round = 2 })
			if i == 2 then
				crack(pen, x, top + 10, 12)
			end
		end
	else
		-- the tile behind has cracked through and drops, a broken piece falling off it (streaks above: falling)
		box(pen, 17, 84, 20, 13, ink, { round = 3, rot = 20 })
		crack(pen, 17, 84, 16)
		box(pen, 31, 91, 8, 6, ink, { round = 1.5, rot = -30 })
		streaks(pen, 17, 70, -90, 10, 8, 3)
		box(pen, 50, top + 9, 32, 18, ink, { round = 3 })
		crack(pen, 57, top + 9, 18)
		box(pen, 84, top + 9, 22, 18, ink, { round = 3 })
	end
	runner(pen, 47, top)
	arrow(pen, 66, 36, 92, 36, W.bold)
end

-- Digits (the only text a sign may show), with a dark outline so they hold on any fill behind them.
local function digits(pen: Pen, cx: number, cy: number, w: number, h: number, text: string, c: { number }): any
	assert(string.match(text, "^[%d ]+$"), `obby sign text must be digits: {text}`)
	local d = pen.d
	local label = d.Instance.new("TextLabel")
	label.Name = "Digits"
	label.AnchorPoint = d.Vector2.new(0.5, 0.5)
	label.Position = d.UDim2.fromScale((pen.o + cx * pen.k) / 100, (pen.o + cy * pen.k) / 100)
	label.BackgroundTransparency = 1
	label.Font = d.Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = color(pen, c)
	label.TextStrokeColor3 = color(pen, C.board)
	label.TextStrokeTransparency = 0
	-- A font stops at 100 px, under a big slot's digits: fit the size to the box (FredokaOne digits are about 0.62 em
	-- wide, a space 0.3), and where that is over 100 px draw the label smaller and scale it up
	local _, spaces = string.gsub(text, " ", "")
	local em = 0.62 * (#text - spaces) + 0.3 * spaces
	local size = math.min(h * pen.px * 0.95, w * pen.px / em)
	local k = math.max(1, size / 100)
	label.Size = d.UDim2.fromScale(w * pen.k / 100 / k, h * pen.k / 100 / k)
	label.TextSize = size / k
	-- a thick dark outline round the glyphs (the text stroke is a pixel; this holds on any fill behind); a UIScale
	-- scales it with the text, so it is drawn that much thinner
	local outline = d.Instance.new("UIStroke")
	outline.ApplyStrokeMode = d.Enum.ApplyStrokeMode.Contextual
	outline.Color = color(pen, C.board)
	outline.Thickness = math.max(2, size * 0.07) / k
	outline.Parent = label
	if k > 1 then
		local scale = d.Instance.new("UIScale")
		scale.Scale = k
		scale.Parent = label
	end
	pen.z += 1
	label.ZIndex = pen.z
	label.Parent = pen.parent
	return label
end

-- A frame that clips what is drawn in it to the rectangle (x0, y0)..(x1, y1); returns a pen whose 100 x 100 grid is
-- that rectangle.
local function clip(pen: Pen, x0: number, y0: number, x1: number, y1: number): Pen
	local d = pen.d
	local f = d.Instance.new("Frame")
	f.Name = "Clip"
	f.BackgroundTransparency = 1
	f.ClipsDescendants = true
	f.Position = d.UDim2.fromScale((pen.o + x0 * pen.k) / 100, (pen.o + y0 * pen.k) / 100)
	f.Size = d.UDim2.fromScale((x1 - x0) * pen.k / 100, (y1 - y0) * pen.k / 100)
	pen.z += 1
	f.ZIndex = pen.z
	f.Parent = pen.parent
	return { d = d, parent = f, z = pen.z, px = pen.px * (x1 - x0) / 100, bg = pen.bg, o = 0, k = 1 }
end

-- The stopwatch, only where the seconds are the message: a thick ring with a crown, a sweep from twelve as big as the
-- seconds on a ten-second dial (4 s is four tenths of the face) and the seconds big inside. The crown reaches
-- `r + W.line + 7` above `cy`.
local function stopwatch(pen: Pen, cx: number, cy: number, r: number, seconds: string)
	box(pen, cx, cy - r - W.line - 4, math.max(r * 0.45, 8), 6, C.white, { round = 1.5 })
	dot(pen, cx, cy, r, C.board)
	-- the sweep: a fan of spokes from the middle, 5 degrees apart (a spoke is wider than the gap at the rim)
	local turn = math.clamp((tonumber(seconds) or 0) / 10, 0, 1) * 360
	local reach = r - W.line / 2
	for a = 0, turn, 5 do
		local t = math.rad(a - 90)
		line(pen, cx, cy, cx + math.cos(t) * reach * 0.9, cy + math.sin(t) * reach * 0.9, 4, C.sweep)
	end
	ring(pen, cx, cy, r, W.line, C.white)
	-- the seconds: white, bold and big (the glyph is about two thirds of the dial), outlined dark
	digits(pen, cx, cy + r * 0.04, r * 1.75, r * 2, seconds, C.white)
end

-- The cannon, one classic cartoon cannon for every step, side view: a tapered dark barrel (a round breech, two
-- narrowing lengths and a flared muzzle ring, one white outline round the lot) turned `rot` degrees (0 = muzzle right)
-- round its wheel's hub at (cx, cy), and a big wooden wheel with spokes over the barrel's back. `rider` puts the
-- runner's head out of the muzzle (you are inside); `ghost` draws the set's ghost (where it swings to).
local CANNON = table.freeze({
	-- the barrel's lengths along its axis from the hub: { middle, length, thickness }
	parts = { { 5, 22, 22 }, { 18, 12, 19 }, { 27, 10, 16 }, { 34, 6, 24 } },
	breech = { -3, 11 }, -- the round back: { where, radius }
	wheel = 11,
	edge = 2.5, -- the white outline
})
local function cannon(pen: Pen, cx: number, cy: number, rot: number, s: number, rider: boolean?, ghost: boolean?)
	local a = math.rad(rot)
	local ux, uy = math.cos(a), math.sin(a)
	local function at(u: number): (number, number)
		return cx + ux * u * s, cy + uy * u * s
	end
	if ghost then
		local x, y = at(15)
		ghostBox(pen, x, y, 40 * s, 18 * s, { round = 8 * s, rot = rot })
		x, y = at(34)
		ghostBox(pen, x, y, 6 * s, 22 * s, { round = 2 * s, rot = rot })
		if rider then
			x, y = at(43)
			ghostBox(pen, x, y, 13 * s, 13 * s, { full = true })
		end
		ghostBox(pen, cx, cy, 2 * CANNON.wheel * s, 2 * CANNON.wheel * s, { full = true })
		return
	end
	if rider then
		local x, y = at(42)
		dot(pen, x, y, 7 * s, C.white)
	end
	-- the outline: every piece a little bigger in white, then the pieces in the barrel's colour over it
	for pass = 1, 2 do
		local e = if pass == 1 then CANNON.edge else 0
		local ink = if pass == 1 then C.white else C.barrel
		local bx, by = at(CANNON.breech[1])
		dot(pen, bx, by, CANNON.breech[2] * s + e, ink)
		for _, p in CANNON.parts do
			local x, y = at(p[1])
			box(pen, x, y, p[2] * s + 2 * e, p[3] * s + 2 * e, ink, { round = 2 * s, rot = rot })
		end
	end
	-- a shine along the barrel's top (a round barrel, not a box)
	local sx, sy = at(2)
	local ex, ey = at(28)
	local nx, ny = uy * 5 * s, -ux * 5 * s
	line(pen, sx + nx, sy + ny, ex + nx * 0.7, ey + ny * 0.7, 2.5, C.white, 0.55)
	-- the wheel over the barrel's back: wood, four spokes, a white hub
	local r = CANNON.wheel * s
	dot(pen, cx, cy, r, C.wood, { stroke = 3, strokeColor = C.white })
	for k = 0, 3 do
		local t = math.rad(k * 45 + 22.5)
		line(
			pen,
			cx - math.cos(t) * r * 0.78,
			cy - math.sin(t) * r * 0.78,
			cx + math.cos(t) * r * 0.78,
			cy + math.sin(t) * r * 0.78,
			2.6,
			C.ink,
			0.25
		)
	end
	dot(pen, cx, cy, 3.2 * s, C.white)
end

-- The cannon's target: a green ring lying on the floor at (cx, cy), `w` wide, with a soft green glow round it (a
-- landing spot, not a switch: no rail, no dot).
local function target(pen: Pen, cx: number, cy: number, w: number)
	box(pen, cx, cy, w * 1.25, w * 0.5, C.safe, { full = true, alpha = 0.72 })
	box(pen, cx, cy, w, w * 0.36, C.safe, { full = true, alpha = 0.45, stroke = 4, strokeColor = C.safe })
end

-- A grid of rounded square tiles: `cols` x `rows` cells of `cell` units from top-left (x0, y0), row-major index i.
-- `path[i]`: green with a glow (safe, the way); `bad[i]`: the danger tile (hazard red, a rim and a crack); `pink[i]`:
-- Glow Memory's pink fake, the same danger tile in its own pink; else a plain tile that shows nothing.
type GridOpts = { path: { [number]: boolean }?, bad: { [number]: boolean }?, pink: { [number]: boolean }? }
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
			local corner = math.max(cell * 0.18, 2)
			if o.path and o.path[i] then
				box(pen, cx, cy, cell + gap * 1.6, cell + gap * 1.6, C.safe, { round = corner + 2, alpha = 0.55 })
				box(pen, cx, cy, cell, cell, C.safe, { round = corner })
			elseif o.bad and o.bad[i] then
				box(pen, cx, cy, cell, cell, C.hazard, { round = corner, stroke = 3, strokeColor = C.hazardEdge })
				crack(pen, cx, cy, cell * 0.8)
			elseif o.pink and o.pink[i] then
				box(pen, cx, cy, cell, cell, C.pink, { round = corner, stroke = 3, strokeColor = C.hazard })
				crack(pen, cx, cy, cell * 0.8)
			else
				box(
					pen,
					cx,
					cy,
					cell,
					cell,
					C.tile,
					{ round = corner, stroke = 2, strokeColor = C.white, strokeAlpha = 0.6 }
				)
			end
		end
	end
end

-- Watch: an almond eye (two curved lids meeting in points) with a round iris and a dark pupil, `w` wide. `look` moves
-- the iris sideways (-1 = looking left, 1 = right).
local function eye(pen: Pen, cx: number, cy: number, w: number, look: number?)
	local lid = w * 0.5
	path(pen, curve({ cx - w / 2, cy }, { cx, cy - lid }, { cx + w / 2, cy }, 8), W.thin, C.white)
	path(pen, curve({ cx - w / 2, cy }, { cx, cy + lid }, { cx + w / 2, cy }, 8), W.thin, C.white)
	local ix = cx + (look or 0) * w * 0.16
	dot(pen, ix, cy, w * 0.19, C.white)
	dot(pen, ix, cy, w * 0.085, C.board)
end

-- Red goo across the bottom from `top` down to 94 (x 7..93), up arrows in it: goo that rises. A thin strip (under 18
-- units) has its arrows poking up out of it.
local function risingGoo(pen: Pen, top: number)
	local h = 94 - top
	box(pen, 50, (top + 94) / 2, 86, h, C.hazard, { round = 3, stroke = 3, strokeColor = C.hazardEdge })
	if h >= 18 then
		for _, x in { 22, 50, 78 } do
			arrow(pen, x, top + h * 0.82, x, top + h * 0.3, W.thin)
		end
	else
		for _, x in { 30, 70 } do
			arrow(pen, x, top + h * 0.6, x, top - 10, W.thin)
		end
	end
end

-- A spring pad: a yellow plate (a thing you use) on an open white zigzag coil over a grey foot, its plate's top at
-- `top` (a few wide zigs with gaps between, so it reads as a spring, not a stack).
local function spring(pen: Pen, cx: number, top: number, w: number)
	local coil = {}
	for k = 0, 6 do
		table.insert(coil, { cx + (if k % 2 == 0 then -w * 0.3 else w * 0.3), top + 9 + k * 2.4 })
	end
	path(pen, coil, W.thin * 0.7, C.white)
	box(pen, cx, top + 26, w * 0.9, 5, C.grey, { round = 2 })
	box(pen, cx, top + 4, w, 8, C.gold, { round = 3 })
end

-- A dashed outline of the box (x0, y0)..(x1, y1) in the ghost's faded lilac: a floor that is there but not this one.
local function dashedBox(pen: Pen, x0: number, y0: number, x1: number, y1: number)
	local width, dash, gap = 3, 6, 4
	local function edge(ax: number, ay: number, bx: number, by: number)
		local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
		local n = math.max(1, math.floor((len + gap) / (dash + gap)))
		local step = (len + gap) / n
		for i = 0, n - 1 do
			-- a round-ended stroke grows by its width, so each dash is drawn that much shorter
			local t0 = (i * step + width / 2) / len
			local t1 = (i * step + step - gap - width / 2) / len
			line(
				pen,
				ax + (bx - ax) * t0,
				ay + (by - ay) * t0,
				ax + (bx - ax) * t1,
				ay + (by - ay) * t1,
				width,
				GHOST.c,
				GHOST.alpha
			)
		end
	end
	edge(x0, y0, x1, y0)
	edge(x1, y0, x1, y1)
	edge(x1, y1, x0, y1)
	edge(x0, y1, x0, y0)
end

-- Wait: an hourglass (two glass bulbs meeting in a waist between a top and a bottom bar, sand in the bottom bulb),
-- `h` tall, centred at (cx, cy).
local function hourglass(pen: Pen, cx: number, cy: number, h: number)
	local w, t, b = h * 0.6, cy - h / 2, cy + h / 2
	path(pen, {
		{ cx - w / 2, t },
		{ cx, cy },
		{ cx - w / 2, b },
		{ cx + w / 2, b },
		{ cx, cy },
		{ cx + w / 2, t },
		{ cx - w / 2, t },
	}, W.thin * 0.8, C.white)
	box(pen, cx, b - h * 0.12, w * 0.5, h * 0.14, C.white, { round = 1 })
	line(pen, cx - w * 0.7, t, cx + w * 0.7, t, W.line, C.white)
	line(pen, cx - w * 0.7, b, cx + w * 0.7, b, W.line, C.white)
end

--------------------------------------------------------------------------------------------------------------------
-- Pictograms (every one keeps its shapes, strokes included, within 3..97 of its grid: the slot's safe margin)

type Draw = (pen: Pen) -> ()
local PICTURES: { [string]: Draw } = {}

-- Aim the Cannon: four steps on one board, left to right with an arrow between each (ObbySigns.paint draws those):
-- jump into the cannon, it swings with you inside, it launches you on your jump arc, you land in the green ring.
PICTURES.cannon1 = function(pen)
	box(pen, 50, 92, 92, 4, C.white, { round = 2, alpha = 0.5 })
	cannon(pen, 57, 79, -30, 0.9)
	runner(pen, 15, 90)
	jumpArrow(pen, arc(26, 46, 82, 56, 22, 8))
end

-- It swings, you inside: the cannon tipped one way (the runner's head out of its muzzle), the set's ghost of it tipped
-- the other way, and a two-headed arc over both.
PICTURES.cannon2 = function(pen)
	box(pen, 50, 94, 92, 4, C.white, { round = 2, alpha = 0.5 })
	cannon(pen, 50, 80, -145, 0.95, true, true)
	cannon(pen, 50, 80, -35, 0.95, true)
	curvedArrow(pen, oval(50, 80, 36, 52, -140, -40, 10), W.line, true)
end

-- It fires you: your head out of the muzzle, then your own white jump arc into the green target ring.
PICTURES.cannon3 = function(pen)
	box(pen, 50, 94, 92, 4, C.white, { round = 2, alpha = 0.5 })
	target(pen, 80, 86, 24)
	cannon(pen, 21, 80, -45, 0.85, true)
	jumpArrow(pen, arc(52, 46, 78, 76, 20, 7))
end

-- Land in the ring: from the ghost (where you flew from), your jump arc down onto the ring.
PICTURES.cannon4 = function(pen)
	target(pen, 66, 87, 34)
	ghostRunner(pen, 16, 52)
	jumpArrow(pen, arc(28, 24, 54, 46, 16, 7))
	runner(pen, 66, 84)
end

-- Rolling Blobs: a red ball rolls down at you, step aside: the ghost in the ball's line, the runner beside it.
PICTURES.blobs = function(pen)
	box(pen, 50, 95, 92, 4, C.white, { round = 2, alpha = 0.5 })
	streaks(pen, 32, 17, -90, 10, 10, 3)
	ball(pen, 32, 36, 16)
	ghostRunner(pen, 32, 92)
	arrow(pen, 47, 75, 64, 75, W.line)
	runner(pen, 80, 92)
end

-- Climb: red drops fall down the ladder; wait for one to pass, then climb.
PICTURES.drips = function(pen)
	for _, x in { 32, 68 } do
		line(pen, x, 8, x, 92, 7, C.violet)
	end
	for _, y in { 24, 44, 64, 84 } do
		line(pen, 32, y, 68, y, 6, C.violet)
	end
	streaks(pen, 50, 16, -90, 10, 8, 3)
	ball(pen, 50, 34, 12)
	runner(pen, 50, 94)
end

-- Glow Memory: watch, the glowing green tiles are the path (the runner, deliberately small, on one); the plain ones
-- are not. The variants add their twist on the same grid (GlowMemory picks one per variant through the section's
-- `sign`).
PICTURES.glow = function(pen)
	eye(pen, 50, 16, 40)
	grid(pen, 19.5, 32, 18, 3.5, 3, 3, { path = { [2] = true, [4] = true, [5] = true, [8] = true } })
	figure(pen, 44, 46, 12, 24)
end

-- Step on the button, then the path glows: the runner's foot presses a big yellow button (press lines round it), an
-- arrow, the lit green path.
PICTURES.glowButton = function(pen)
	box(pen, 28, 92, 38, 5, C.grey, { round = 2 })
	box(pen, 28, 85, 30, 11, C.gold, { full = true, stroke = 3, strokeColor = C.white })
	for _, side in { -1, 1 } do
		line(pen, 28 + side * 15, 75, 28 + side * 18, 70, 3.5, C.white)
		line(pen, 28 + side * 18.5, 83, 28 + side * 22, 83, 3.5, C.white)
	end
	runner(pen, 28, 81)
	arrow(pen, 48, 60, 58, 60, W.line)
	grid(pen, 64, 38, 13, 3.5, 2, 3, { path = { [1] = true, [4] = true, [5] = true } })
end

-- Pink tiles are the fakes: they crack (the grid on its floor).
PICTURES.glowPink = function(pen)
	eye(pen, 50, 16, 40)
	box(pen, 50, 62.5, 67, 67, C.dim, { round = 5, alpha = 0.55 })
	grid(pen, 19.5, 32, 18, 3.5, 3, 3, { pink = { [1] = true, [3] = true, [5] = true, [9] = true } })
end

-- The map is behind you: the eye looks back at the sign, the runner walks on.
PICTURES.glowBehind = function(pen)
	line(pen, 28, 60, 28, 94, W.line, C.grey)
	box(pen, 28, 35, 40, 42, C.board, { round = 4, stroke = W.thin, strokeColor = C.white })
	grid(pen, 12, 19, 9.5, 2.5, 3, 3, { path = { [2] = true, [4] = true, [8] = true } })
	eye(pen, 74, 26, 30, -1)
	runner(pen, 74, 94)
end

-- One look only: the path shows once (the eye over it), then the grid goes plain.
PICTURES.glowOnce = function(pen)
	eye(pen, 22.5, 28, 32)
	grid(pen, 7, 46, 14, 3, 2, 3, { path = { [2] = true, [3] = true, [6] = true } })
	arrow(pen, 43, 70, 56, 70, W.line)
	grid(pen, 63, 46, 14, 3, 2, 3, {})
end

-- A new path every 8 seconds.
PICTURES.glowRounds = function(pen)
	stopwatch(pen, 50, 31, 14, "8")
	grid(pen, 8, 52, 12, 3, 2, 3, { path = { [2] = true, [3] = true, [5] = true } })
	arrow(pen, 41, 73, 57, 73, W.line)
	grid(pen, 65, 52, 12, 3, 2, 3, { path = { [1] = true, [4] = true, [6] = true } })
end

-- Hot feet: even the safe tiles crack soon after you land (green, cracked through, a piece falling), so keep running.
PICTURES.glowRush = function(pen)
	crumble(pen, "glow")
end

-- Beat Pads: a row of pads, one lit and pulsing on the beat (full rings round it, the note right over it); the runner
-- jumps onto the lit one.
PICTURES.beat = function(pen)
	box(pen, 74, 82, 38, 19, C.white, { full = true, hollow = true, stroke = 3, alpha = 0.6 })
	box(pen, 74, 82, 30, 14, C.white, { full = true, hollow = true, stroke = 3, alpha = 0.25 })
	box(pen, 20, 82, 22, 9, C.violet, { full = true, alpha = 0.5 })
	box(pen, 46, 82, 14, 9, C.violet, { full = true, alpha = 0.5 })
	box(pen, 74, 82, 22, 9, C.violet, { full = true, stroke = 2, strokeColor = C.white })
	-- an eighth note right over the lit pad: a tilted oval head, a stem and a flag
	box(pen, 79, 44, 14, 10, C.white, { full = true, rot = -22 })
	line(pen, 85, 42, 85, 17, W.thin, C.white)
	line(pen, 85, 17, 92, 25, W.thin, C.white)
	runner(pen, 20, 78)
	jumpArrow(pen, arc(30, 40, 60, 71, 16, 8))
end

-- Key Run: grab the gold keys, the gate opens.
PICTURES.key = function(pen)
	-- the key: its ring's stroke lies outside r, so the ring's left edge is at 22 - 10 - 7 = 5
	ring(pen, 22, 50, 10, 7, C.gold)
	line(pen, 36, 50, 54, 50, 8, C.gold)
	line(pen, 51, 50, 51, 62, 7, C.gold)
	line(pen, 43, 50, 43, 59, 7, C.gold)
	arrow(pen, 59, 50, 67, 50, W.line)
	box(pen, 84, 52, 20, 80, C.gate, { round = 3, alpha = 0.45, stroke = 3, strokeColor = C.white })
	-- the padlock: a shackle ring whose lower half the gold body hides, so it reads as an arch
	ring(pen, 84, 38, 5, 4.5, C.gold)
	box(pen, 84, 51, 18, 20, C.gold, { round = 3 })
end

-- Clue Doors: the board's symbol, walk through the door with the same symbol (white symbols: the shape is the clue).
PICTURES.clue = function(pen)
	box(pen, 50, 23, 40, 26, C.board, { round = 4, stroke = W.thin, strokeColor = C.white })
	box(pen, 50, 23, 14, 14, C.white, { rot = 45, round = 2 })
	-- arched doors standing on the floor line: drawn in a frame that clips them at the line (their rounded bottoms
	-- run on below it), so nothing of them reaches the slot's edge
	local doors = clip(pen, 0, 0, 100, 95)
	for _, door in { 19, 50, 81 } do
		-- the frame is 95 units tall, so y (and the height) scale by 100 / 95 inside it
		box(doors, door, 80 / 0.95, 22, 56 / 0.95, C.board, { round = 11, stroke = W.thin, strokeColor = C.white })
	end
	pen.z = doors.z
	line(pen, 5, 95, 95, 95, W.thin, C.white)
	dot(pen, 19, 72, 8, C.white)
	box(pen, 50, 72, 15, 15, C.white, { round = 2 })
	box(pen, 81, 72, 14, 14, C.white, { rot = 45, round = 2 })
	curvedArrow(pen, curve({ 73, 23 }, { 84, 25 }, { 84, 42 }, 5), W.line)
end

-- Moon Jump: inside the bubble (a see-through dome over the floor) your jump floats high and far: the ghost of a
-- normal small hop beside a big floaty arc to a high ledge. Two Moons' lower gravity reads the same: a big float.
local function moonJump(pen: Pen)
	local dome = clip(pen, 0, 0, 100, 94)
	box(dome, 50, 100, 86, 164, C.bubble, { full = true, alpha = 0.78, stroke = W.thin, strokeColor = C.white })
	pen.z = dome.z
	box(pen, 50, 93, 86, 5, C.white, { round = 2, alpha = 0.4 })
	box(pen, 80, 60, 20, 7, C.violet, { round = 2 })
	runner(pen, 20, 92)
	-- a normal hop, as the set's ghost, beside the big float
	dots(pen, arc(32, 86, 58, 90, 12, 4), W.dot * 0.8, GHOST.c, GHOST.alpha)
	jumpArrow(pen, arc(32, 54, 78, 54, 28, 11))
end

PICTURES.moon = moonJump
PICTURES.moon2 = moonJump

-- Speed Strip: the yellow pad with chevrons is fast (chevrons only ever mean speed), blue with a snail is slow.
PICTURES.speed = function(pen)
	box(pen, 50, 28, 92, 34, C.boost, { round = 5 })
	for _, x in { 34, 54, 74 } do
		head(pen, x, 28, 0, 12, W.line, C.board)
	end
	box(pen, 50, 72, 92, 34, C.slow, { round = 5 })
	-- the snail, big: a round white shell with a spiral in the strip's colour, a long foot, a head with two eye
	-- stalks with round tips
	local sx = -10
	box(pen, 66 + sx, 83, 48, 7, C.white, { full = true })
	dot(pen, 57 + sx, 69, 13, C.white)
	local spiral = {}
	for i = 0, 18 do
		local a = 1 + i * (2.6 * math.pi - 1) / 18
		table.insert(spiral, { 57 + sx + math.cos(a) * 1.2 * a, 69 + math.sin(a) * 1.2 * a })
	end
	path(pen, spiral, 3.5, C.slow)
	dot(pen, 86 + sx, 78, 5, C.white)
	line(pen, 84 + sx, 75, 81 + sx, 63, W.thin, C.white)
	line(pen, 88 + sx, 75, 92 + sx, 63, W.thin, C.white)
	dot(pen, 81 + sx, 62, 3, C.white)
	dot(pen, 92 + sx, 62, 3, C.white)
end

-- Arrow Maze: a conveyor floor (rollers under a lilac belt, arrows printed on it) carries the runner its arrow's way.
PICTURES.belts = function(pen)
	box(pen, 50, 80, 92, 22, C.violet, { round = 11 })
	for _, x in { 13, 87 } do
		dot(pen, x, 80, 5, C.board)
	end
	arrow(pen, 24, 80, 42, 80, W.line)
	arrow(pen, 56, 80, 74, 80, W.line)
	runner(pen, 48, 69)
	arrow(pen, 66, 42, 92, 42, W.bold)
end

-- Lights Out: everything is dark but one green pad in a bright beam of light: jump to it.
PICTURES.dark = function(pen)
	box(pen, 70, 43, 28, 70, C.white, { alpha = 0.72 })
	box(pen, 70, 80, 44, 18, C.safe, { full = true, alpha = 0.6 })
	box(pen, 70, 80, 36, 13, C.safe, { full = true, alpha = 0.4 })
	box(pen, 70, 80, 30, 9, C.safe, { round = 3 })
	box(pen, 20, 88, 30, 7, C.dim, { round = 2 })
	runner(pen, 20, 84)
	jumpArrow(pen, arc(31, 46, 60, 72, 24, 8))
end

-- Vine Swing: hang on the yellow vine under the branch, and let go to fly on to the ledge.
PICTURES.vine = function(pen)
	box(pen, 30, 9, 48, 7, C.violet, { round = 3 })
	line(pen, 38, 12, 22, 46, W.line, C.gold)
	runner(pen, 20, 90)
	box(pen, 82, 82, 24, 7, C.violet, { round = 2 })
	jumpArrow(pen, arc(36, 48, 82, 74, 24, 9))
end

-- Geyser Field: the dead vent (dark) waits (an hourglass over it); the live vent (yellow, a thing you use) shoots a
-- water jet up that lifts the runner standing on it (an up arrow in the jet).
PICTURES.geyser = function(pen)
	box(pen, 20, 88, 28, 9, C.dim, { full = true })
	hourglass(pen, 20, 64, 24)
	box(pen, 66, 67, 20, 34, C.jet, { round = 6, stroke = 2, strokeColor = C.white })
	arrow(pen, 66, 79, 66, 58, W.thin, C.board)
	box(pen, 66, 88, 34, 10, C.gold, { full = true, stroke = 3, strokeColor = C.white })
	runner(pen, 66, 50)
end

-- Updraft: jump into the wind column, it carries you up.
PICTURES.updraft = function(pen)
	box(pen, 17, 74, 28, 8, C.violet, { round = 2 })
	box(pen, 70, 47, 38, 76, C.wind, { round = 4, alpha = 0.6, stroke = 3, strokeColor = C.white })
	box(pen, 70, 90, 44, 8, C.violet, { round = 2 })
	runner(pen, 17, 70)
	dots(pen, arc(29, 34, 48, 40, 12, 4), W.dot, C.white)
	arrow(pen, 70, 78, 70, 20, W.bold)
end

-- Two Roads: one symbol per road. Fast: the speed pad (yellow with chevrons).
PICTURES.fast = function(pen)
	box(pen, 50, 50, 92, 52, C.boost, { round = 8 })
	for _, x in { 32, 56, 80 } do
		head(pen, x, 50, 0, 17, W.bold, C.board)
	end
end

PICTURES.safe = function(pen)
	-- a top with rounded upper corners and square lower ones (x 18..82, y 12..44), and a diamond whose side corners
	-- are exactly those lower corners: straight flanks into a point
	box(pen, 50, 28, 64, 32, C.safe, { round = 12 })
	box(pen, 50, 38.5, 64, 11, C.safe)
	box(pen, 50, 44, 45.25, 45.25, C.safe, { rot = 45 })
	path(pen, { { 34, 40 }, { 46, 53 }, { 67, 27 } }, 10, C.white)
end

-- Bail out, from above: the fast road (the speed pad's yellow with chevrons, pointing the way the roads run) and the
-- safe road (green, a tick) side by side; a lilac plank across between them, the runner on it and one arrow along it
-- from the fast road to the safe one.
PICTURES.bail = function(pen)
	box(pen, 19, 50, 22, 84, C.boost, { round = 4 })
	for _, y in { 22, 40 } do
		head(pen, 19, y, -90, 10, W.line, C.board)
	end
	box(pen, 81, 50, 22, 84, C.safe, { round = 4 })
	path(pen, { { 73, 30 }, { 79, 37 }, { 89, 23 } }, W.line, C.white)
	box(pen, 50, 70, 46, 16, C.violet, { round = 3, stroke = 2, strokeColor = C.white })
	runner(pen, 42, 63)
	arrow(pen, 34, 70, 64, 70, W.thin)
end

-- Terraced roads, side view: three ledges stepping up left to right like terraces, each the top of its own block;
-- this road's ledge is solid lilac with the runner standing on it, the other two are dashed outlines at their
-- heights. Low, middle, high read as one choice side by side.
local TERRACE = { { 8, 34, 80 }, { 37, 63, 66 }, { 66, 92, 52 } } -- low, middle, high: { x0, x1, top }
local TERRACE_FOOT = 92
local function floors(pen: Pen, which: number)
	for i, t in TERRACE do
		if i == which then
			local x0, x1, top = t[1], t[2], t[3]
			box(pen, (x0 + x1) / 2, (top + TERRACE_FOOT) / 2, x1 - x0, TERRACE_FOOT - top, C.violet, {
				round = 2,
				stroke = 2,
				strokeColor = C.white,
			})
		else
			dashedBox(pen, t[1], t[3], t[2], TERRACE_FOOT)
		end
	end
	local t = TERRACE[which]
	runner(pen, (t[1] + t[2]) / 2, t[3] - 1)
end

PICTURES.low = function(pen)
	floors(pen, 1)
end
PICTURES.middle = function(pen)
	floors(pen, 2)
end
PICTURES.high = function(pen)
	floors(pen, 3)
end

-- The door shuts 4 s after you step in: the doorway behind the runner with its solid gate half down (a down arrow on
-- it), a small stopwatch, the runner running on.
PICTURES.door4 = function(pen)
	box(pen, 50, 94, 92, 4, C.white, { round = 2, alpha = 0.5 })
	box(pen, 22, 63, 28, 54, C.board, { round = 3, stroke = W.thin, strokeColor = C.white })
	box(pen, 22, 49, 28, 26, C.gate, { round = 2 })
	arrow(pen, 22, 39, 22, 57, W.thin)
	stopwatch(pen, 77, 35, 13, "4")
	runner(pen, 50, 92)
	arrow(pen, 66, 72, 92, 72, W.bold)
end

-- Key Run's clock: the key is the star (big), the stopwatch hangs on its tip like a badge (grabbing it starts 9 s),
-- and a small strip of red goo below rises after.
PICTURES.clock9 = function(pen)
	ring(pen, 21, 46, 10, 7, C.gold)
	line(pen, 35, 46, 68, 46, 8, C.gold)
	line(pen, 46, 46, 46, 58, 7, C.gold)
	line(pen, 55, 46, 55, 56, 7, C.gold)
	stopwatch(pen, 76, 33, 14, "9")
	risingGoo(pen, 82)
end

-- Rising Goo's countdown before the goo starts.
PICTURES.countdown = function(pen)
	digits(pen, 50, 36, 92, 56, "3 2 1", C.white)
	risingGoo(pen, 72)
end

-- Crusher Alley: the red crusher comes down (streaks above it, a down arrow beside, its spot on the floor red); run
-- under it once it lifts.
PICTURES.crusher = function(pen)
	box(pen, 50, 92, 88, 8, C.violet, { round = 2 })
	box(pen, 50, 92, 40, 8, C.hazard, { round = 2, alpha = 0.35 })
	box(pen, 50, 42, 40, 28, C.hazard, { round = 3, stroke = 3, strokeColor = C.hazardEdge })
	streaks(pen, 50, 24, -90, 14, 11, 3)
	arrow(pen, 83, 18, 83, 46, W.line)
	runner(pen, 15, 88)
	arrow(pen, 30, 72, 70, 72, W.line)
end

-- Melting Floor: a tile cracks and drops soon after you step on it, so keep moving.
PICTURES.melt = function(pen)
	crumble(pen, "tile")
end

-- Goo Rides: step on the ride, it carries you along its rail to its stop (the set's ghost of the platform).
PICTURES.ride = function(pen)
	line(pen, 8, 90, 92, 90, W.line, C.grey)
	line(pen, 8, 84, 8, 90, W.thin, C.grey)
	line(pen, 92, 84, 92, 90, W.thin, C.grey)
	line(pen, 26, 80, 26, 88, W.thin, C.grey)
	box(pen, 26, 76, 24, 10, C.violet, { round = 3 })
	runner(pen, 26, 71)
	ghostBox(pen, 74, 76, 24, 10, { round = 3 })
	arrow(pen, 42, 76, 58, 76, W.line)
end

-- Bounce Chain: a spring pad throws you up onto the high ledge.
PICTURES.bounce = function(pen)
	spring(pen, 20, 66, 30)
	box(pen, 80, 36, 26, 8, C.violet, { round = 3 })
	runner(pen, 20, 66)
	jumpArrow(pen, arc(32, 32, 76, 30, 20, 8))
end

-- Ice Slide: on the shiny ice you keep sliding: skid marks behind the runner's feet, shine on the ice.
PICTURES.ice = function(pen)
	box(pen, 50, 86, 90, 14, C.wind, { round = 4 })
	line(pen, 70, 82, 80, 90, 3, C.white)
	line(pen, 80, 82, 88, 88, 3, C.white)
	-- the skid: two long marks on the ice behind the runner's feet
	line(pen, 8, 81, 46, 81, 3, C.white, 0.2)
	line(pen, 14, 84.5, 46, 84.5, 3, C.white, 0.2)
	runner(pen, 56, 79)
	arrow(pen, 70, 50, 92, 50, W.bold)
end

-- Merry-go-round: the disk turns you; jump off where it points the right way.
PICTURES.spin = function(pen)
	box(pen, 50, 72, 60, 20, C.violet, { full = true, stroke = 3, strokeColor = C.white })
	runner(pen, 50, 70)
	curvedArrow(pen, oval(50, 72, 38, 21, -60, 15, 8), W.thin)
	curvedArrow(pen, oval(50, 72, 38, 21, 120, 195, 8), W.thin)
end

-- Two Roads: the course forks; pick a road.
PICTURES.fork = function(pen)
	line(pen, 50, 88, 50, 60, 13, C.violet)
	line(pen, 50, 62, 18, 24, 13, C.violet)
	line(pen, 50, 62, 82, 24, 13, C.violet)
	arrow(pen, 36, 44, 16, 20, W.line)
	arrow(pen, 64, 44, 84, 20, W.line)
	runner(pen, 50, 93)
end

-- Rising Goo: the red goo rises behind you; climb before it reaches you.
PICTURES.rising = function(pen)
	risingGoo(pen, 78)
	box(pen, 24, 64, 26, 8, C.violet, { round = 2 })
	box(pen, 52, 44, 26, 8, C.violet, { round = 2 })
	box(pen, 80, 24, 26, 8, C.violet, { round = 2 })
	runner(pen, 24, 60)
	arrow(pen, 40, 34, 68, 8, W.bold)
end

-- Collapsing Bridge: the planks fall away behind you; don't stop.
PICTURES.collapse = function(pen)
	crumble(pen, "plank")
end

-- Sliding Maze: red panels slide across the way; blue walls are safe. Wait for the gap, then go.
PICTURES.panels = function(pen)
	box(pen, 50, 7, 92, 8, C.slow, { round = 2 })
	box(pen, 50, 93, 92, 8, C.slow, { round = 2 })
	box(pen, 60, 44, 24, 50, C.hazard, { round = 3, stroke = 3, strokeColor = C.hazardEdge })
	line(pen, 30, 80, 88, 80, W.line, C.white)
	head(pen, 88, 80, 0, W.line * 2.2, W.line, C.white)
	head(pen, 30, 80, 180, W.line * 2.2, W.line, C.white)
	runner(pen, 15, 72)
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

-- Steps of one mechanic that a board shows left to right: an arrow in the gap between a step and the next.
local THEN: { [string]: string } = { cannon1 = "cannon2", cannon2 = "cannon3", cannon3 = "cannon4" }

-- Fills `gui` (on a banner's face) with the banner: a dark plate with a white rim and one slot per picture, each
-- centred at its `z` across the lane (left to right as the runner sees it), and an arrow between two steps of one
-- mechanic. `height` is the banner's (default: the height ObbyCourse gives a board of this many pictures); the
-- slots are that less the margins.
function ObbySigns.paint(gui: any, slots: { ObbyCourse.Slot }, deps: Deps?, height: number?): any
	local d = deps or defaults()
	local S, G = ObbySigns.SIZE, ObbyCourse.SIGN
	local w = G.width
	local h = height or ObbyCourse.bannerHeight((ObbyCourse.slotSize(#slots)))
	local side = h - 2 * G.pad
	local rimPx = math.round(S.rim * S.pixelsPerStud)
	local pen0: Pen = { d = d, parent = gui, z = 0, px = 1, bg = C.board, o = 0, k = 1 }

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
		slot.Position = d.UDim2.fromScale((s.z + w / 2 - side / 2) / w, G.pad / h)
		slot.Size = d.UDim2.fromScale(side / w, side / h)
		slot.ZIndex = 2
		slot.Parent = root
		-- the picture's 100 x 100 grid sits inside the slot's safe margin, so nothing reaches the slot's edge
		local k = 1 - 2 * S.margin
		draw({
			d = d,
			parent = slot,
			z = 2,
			px = side * S.pixelsPerStud / 100 * k,
			bg = C.board,
			o = 100 * S.margin,
			k = k,
		})
		local next = slots[i + 1]
		if next and THEN[s.id] == next.id then
			-- a square a bit wider than the gap, centred in it; the chevron keeps to the gap
			local gap = next.z - s.z - side
			local square = gap + 2 * G.pad
			local arrowBox = d.Instance.new("Frame")
			arrowBox.Name = "Then"
			arrowBox.BackgroundTransparency = 1
			arrowBox.Position = d.UDim2.fromScale(((s.z + next.z) / 2 + w / 2 - square / 2) / w, (h - square) / 2 / h)
			arrowBox.Size = d.UDim2.fromScale(square / w, square / h)
			arrowBox.ZIndex = 3
			arrowBox.Parent = root
			local pen: Pen =
				{ d = d, parent = arrowBox, z = 3, px = square * S.pixelsPerStud / 100, bg = C.board, o = 0, k = 1 }
			head(pen, 50 + 50 * gap / square * 0.75, 50, 0, 46 * gap / square, 34 * gap / square, C.white)
		end
	end
	return root
end

-- A booster engine under each end of `banner` (a lane-wide part, its axes the course's): a chunky body with an orange
-- band, a bell nozzle pointing down and a flame of built-in fire particles blowing down. All adornments, an
-- attachment and an emitter on the banner, so they follow its hover and add no parts.
function ObbySigns.boosters(banner: any, deps: Deps?)
	local d = deps or defaults()
	local B, G = ObbySigns.SIZE.booster, ObbyCourse.SIGN
	local pen: Pen = { d = d, parent = banner, z = 0, px = 1, bg = C.board, o = 0, k = 1 }
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
	local out = {}
	for _, slot in root:GetChildren() do
		if slot:IsA("Frame") then
			local side = slot.Size.X.Scale * ObbyCourse.SIGN.width -- slots (and the arrows between) are square
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
