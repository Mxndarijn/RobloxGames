--!strict
--[[
	RingPad (pure)

	A round floor pad you stand on, lit step by step round the circle (a charge, a countdown). Two styles:
	  "ring"    (default) one smooth circle: `segments` thin blocks with no gaps (72 by default), so the light sweeps
	            round it smoothly;
	  "pieces"  `segments` curved pieces (12 by default) with a straight cut `gap` studs wide between them, the same
	            width from the inner edge to the outer; each piece is `curve` straight blocks and lights as a whole.
	`segments` is how many steps the ring lights in. RingPadView builds and colours the parts; this module holds the
	shape and the rules.

	Local frame: y up, the pad's front is -Z, segments run clockwise seen from above, segment 1 starting at the front.

	  local shape = RingPad.shape({ radius = 4.6, width = 1.6 })   -- defaults fill the rest
	  RingPad.blocks(shape)                       -> { Block }  where every block goes (local frame)
	  RingPad.inside(shape, dx, dy, dz)           -> boolean    a point (offset from the centre on the floor) is on it
	  RingPad.hold(since, onPad, blocked, now, seconds) -> (fired, since)  stand-to-activate timer
	  RingPad.charge(n, since, now, seconds)      -> lit segments while someone stands on it (0 .. n)
	  RingPad.countdown(n, startedAt, endsAt, now) -> lit segments left of a running timer (1 .. n, 0 when over)
]]

export type Style = "ring" | "pieces"

export type Options = {
	style: Style?, -- "ring" (one smooth circle) or "pieces" (curved pieces with cuts)
	segments: number?, -- steps the ring lights in: blocks round the circle, or pieces
	curve: number?, -- "pieces": straight blocks per piece, at least 2 (more = rounder)
	radius: number?, -- studs from the centre to the middle of the ring
	width: number?, -- studs across the ring
	thickness: number?, -- studs thick
	lift: number?, -- studs the ring's underside sits above the floor
	gap: number?, -- "pieces": studs wide, the cut between two pieces (0 = no cuts)
	reach: number?, -- studs from the centre (flat) that count as standing on it; default the ring's outer edge
	height: number?, -- studs above the floor a standing point may be
}

export type Shape = {
	style: Style,
	segments: number,
	curve: number,
	radius: number,
	width: number,
	thickness: number,
	lift: number,
	gap: number,
	reach: number,
	height: number,
}

-- One straight block of a piece: centred at (x, y, z) in the pad's local frame, turned `yaw` radians about +Y,
-- `length` along its own X (the ring's direction), `width` along its Z (across the ring), `thickness` tall.
export type Block = {
	segment: number,
	index: number,
	yaw: number,
	x: number,
	y: number,
	z: number,
	length: number,
	width: number,
	thickness: number,
}

local RingPad = {}

RingPad.DEFAULTS = table.freeze({
	style = "ring" :: Style,
	segments = table.freeze({ ring = 72, pieces = 12 }),
	curve = 4,
	radius = 4.6,
	width = 1.6,
	thickness = 0.12,
	lift = 0.05,
	gap = 0.2,
	height = 7,
})

local function positive(name: string, value: number)
	if type(value) ~= "number" or value ~= value or value <= 0 then
		error(`RingPad: {name} must be a positive number`, 3)
	end
end

-- The full shape from `options` over RingPad.DEFAULTS. Bad sizes are programming errors and throw.
function RingPad.shape(options: Options?): Shape
	local o: Options = options or {}
	local d = RingPad.DEFAULTS
	local style: Style = o.style or d.style
	if style ~= "ring" and style ~= "pieces" then
		error(`RingPad: unknown style {style}`, 2)
	end
	local pieces = style == "pieces"
	local shape: Shape = {
		style = style,
		segments = o.segments or d.segments[style],
		curve = if pieces then o.curve or d.curve else 1,
		radius = o.radius or d.radius,
		width = o.width or d.width,
		thickness = o.thickness or d.thickness,
		lift = o.lift or d.lift,
		gap = if pieces then o.gap or d.gap else 0,
		reach = 0,
		height = o.height or d.height,
	}
	shape.reach = o.reach or (shape.radius + shape.width / 2)
	for _, key in { "segments", "curve", "radius", "width", "thickness", "reach", "height" } do
		positive(key, (shape :: any)[key])
	end
	if shape.segments % 1 ~= 0 or shape.curve % 1 ~= 0 then
		error("RingPad: segments and curve must be whole numbers", 2)
	end
	if shape.width >= 2 * shape.radius then
		error("RingPad: width must be less than twice the radius", 2)
	end
	if pieces and shape.curve < 2 then
		error("RingPad: curve must be at least 2", 2)
	end
	if shape.segments < 3 then
		error("RingPad: segments must be at least 3", 2)
	end
	local inner = shape.radius - shape.width / 2
	if shape.gap < 0 or shape.gap >= inner * math.sin(math.pi / shape.segments) or shape.lift < 0 then
		error("RingPad: gap must be at least 0 and narrower than a piece's inner edge, lift at least 0", 2)
	end
	return table.freeze(shape)
end

local OVERLAP = 0.02 -- studs each block runs into its neighbour, so no hairline shows between neighbouring blocks

--[[
	Every block, segment by segment (`segment` 1..segments, `index` 1..curve).
	"ring": one block per segment, as long as the outer edge over its angle, so the blocks meet at the outside and
	overlap a little on the inside: one closed circle.
	"pieces": the first and last block of a piece lie
	along the cut next to them, their end face `gap / 2` from the cut's centre line, so every cut is a strip of even
	width. The blocks between follow the circle, as long as the outer edge over their angle, and overlap a little on
	the inside of the ring.
]]
function RingPad.blocks(shape: Shape): { Block }
	local n, k = shape.segments, shape.curve
	local piece = 2 * math.pi / n
	local outer = shape.radius + shape.width / 2
	local y = shape.lift + shape.thickness / 2
	local out: { Block } = {}
	local half = shape.gap / 2
	local cutAngle = math.atan(half / outer) -- angle the cut takes up on each side of its centre line, at the outer edge
	local step = (piece - 2 * cutAngle) / k -- outer-edge angle per block
	local capLength = outer * math.tan(cutAngle + step) - half + OVERLAP
	local midLength = 2 * outer * math.tan(step / 2) + OVERLAP

	local function add(segment: number, index: number, angle: number, along: number, length: number)
		-- the block's centre: on the middle line at `angle`, moved `along` studs round the ring (clockwise)
		local sin, cos = math.sin(angle), math.cos(angle)
		table.insert(out, {
			segment = segment,
			index = index,
			yaw = -angle,
			x = shape.radius * sin + along * cos,
			y = y,
			z = -shape.radius * cos + along * sin,
			length = length,
			width = shape.width,
			thickness = shape.thickness,
		})
	end

	if shape.style == "ring" then
		local length = 2 * outer * math.tan(piece / 2) + OVERLAP
		for s = 1, n do
			add(s, 1, (s - 0.5) * piece, 0, length)
		end
		return out
	end

	for s = 1, n do
		local first = (s - 1) * piece -- the cut before this piece, clockwise from the front
		local last = s * piece
		add(s, 1, first, half + capLength / 2, capLength)
		for j = 2, k - 1 do
			add(s, j, first + cutAngle + (j - 0.5) * step, 0, midLength)
		end
		add(s, k, last, -(half + capLength / 2), capLength)
	end
	return out
end

-- True when a point `dx`, `dz` studs (flat) from the centre and `dy` studs above the floor stands on the pad.
function RingPad.inside(shape: Shape, dx: number, dy: number, dz: number): boolean
	if dx ~= dx or dy ~= dy or dz ~= dz then
		return false
	end
	return dx * dx + dz * dz <= shape.reach * shape.reach and dy >= -1 and dy <= shape.height
end

--[[
	The stand-to-activate timer. `since` = when the stander stepped on (nil = not on it), `onPad` = on it now,
	`blocked` = it can't fire now (say a lock already runs). Returns whether it fires this tick and the new `since`.
	Stepping off, being blocked or firing starts the count again from zero.
]]
function RingPad.hold(
	since: number?,
	onPad: boolean,
	blocked: boolean,
	now: number,
	seconds: number
): (boolean, number?)
	if not onPad or blocked then
		return false, nil
	end
	if since == nil then
		return false, now
	end
	if now - since >= seconds then
		return true, nil
	end
	return false, since
end

-- Pieces lit while someone has stood on it since `since`: one more each `seconds / n`, all of them at `seconds`.
function RingPad.charge(n: number, since: number, now: number, seconds: number): number
	local share = if seconds > 0 then math.clamp((now - since) / seconds, 0, 1) else 1
	return math.floor(share * n)
end

-- Pieces still lit of a timer running from `startedAt` to `endsAt`: all at the start, one fewer as each 1/n runs
-- out, never below one while it runs, 0 once it is over.
function RingPad.countdown(n: number, startedAt: number, endsAt: number, now: number): number
	if now >= endsAt then
		return 0
	end
	local total = endsAt - startedAt
	local share = if total > 0 then (endsAt - now) / total else 1
	return math.clamp(math.ceil(share * n), 1, n)
end

return table.freeze(RingPad)
