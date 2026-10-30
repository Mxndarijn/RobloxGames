--!strict
--[[
	ObbyCourse (pure, contract/obby.md)

	The Goo Gauntlet sky course as data. `pick(slot)` chooses the sections of one rotation (Config.OBBY.ORDER: one
	section per tier entry, no section twice, none from the course before it inside one chain of CHAIN_SLOTS
	rotations) and a layout for each. `build(slot)` lays the course out: a start pad, then each section followed by a
	checkpoint pad, the last one being the finish. Every server and client gets the same course for the same slot.

	Course-local frame: x runs forward along the course, y up, z to the right. A part's `pos` is its centre. Parts
	flagged `step` are the walking path in order; tests check their gaps and rises at rest. Moving parts carry a
	`motion` the client plays at server time (visuals/client/ObbyFx); the server only uses the checkpoints and floors.
	`toWorld` / `toLocal` map between this frame and the world for a Frame (origin + yaw, from WorldLayout.OBBY).
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")

local OBBY = Config.OBBY

export type Vec = { number } -- { x, y, z }

--[[
	Motion kinds (t = server time):
	  slide   offset `amp` along `axis` ("x" | "y" | "z") by sin(2π(t / period + phase))
	  spin    turns round its own vertical axis once per `period` seconds (negative = the other way)
	  melt    the local player standing on it: it fades and drops away `delay` s later, back after `away` s
	  flip    solid while frac(t / period + phase) < `duty`, see-through and not solid otherwise
	  shrink  its width and depth breathe between 1 and `min` times full size: cos(2π(t / period + phase))
	  bounce  the local player landing on it is thrown straight up at `power` studs / s (trampolines, cannons)
	  lift    a see-through wind column: the local player inside it rises at `power` studs / s
	  swing   a pendulum: swings `amp` degrees either side across the course, `arm` studs below its pivot
	  rock    a seesaw plank: tips `amp` degrees forward and back round its centre
]]
export type Motion = {
	kind: string,
	axis: string?,
	amp: number?,
	period: number?,
	phase: number?,
	delay: number?,
	away: number?,
	duty: number?,
	min: number?,
	power: number?,
	arm: number?,
}

export type Part = {
	size: Vec,
	pos: Vec,
	look: string, -- "start" | "pad" | "finish" | "jelly" | "goo" | "bubble" | "ice" | "rope" | "tile" | "post" | "bar"
	-- | "trampoline" | "blob" | "pipe" | "truss" | "fan" | "wind" | "plank" | "cannon" | "gate"
	shape: string?, -- "block" (default) | "disc" (a flat cylinder, size.x = diameter) | "ball" | "truss" (climbable)
	ghost: boolean?, -- no collision (wind, pendulum rods)
	motion: Motion?,
	conveyor: Vec?, -- surface velocity in course-local studs / s
	ice: boolean?, -- no friction
	step: boolean?, -- on the walking path, in order
	tone: number?, -- colour variant 1..3 for the look
}

export type Pick = { id: string, tier: string, layout: number }

export type Checkpoint = {
	index: number, -- 1..#picks; the last one is the finish
	pos: Vec, -- pad top centre
	size: Vec, -- pad footprint (x, _, z) and the height above the top that counts as standing on it (y)
}

export type Course = {
	slot: number,
	picks: { Pick },
	parts: { Part },
	start: Vec, -- where a runner appears (above the start pad)
	startTop: number, -- the start pad's top
	checkpoints: { Checkpoint },
	length: number,
}

export type Frame = { origin: Vec, yaw: number } -- yaw in degrees: forward = (sin yaw, 0, cos yaw)

type Section = { length: number, rise: number, parts: { Part } }

local ObbyCourse = {}

ObbyCourse.START_LENGTH = 12
ObbyCourse.PAD_LENGTH = 8 -- checkpoint pad depth along the course
ObbyCourse.FINISH_LENGTH = 12
ObbyCourse.WIDTH = 12 -- pad width across the course
ObbyCourse.STAND_HEIGHT = 9 -- studs above a pad top that count as standing on it
ObbyCourse.THICK = 1 -- platform thickness

ObbyCourse.NAMES = table.freeze({
	JellySteps = "Jelly Steps",
	WobbleBridge = "Wobble Bridge",
	BubbleHop = "Bubble Hop",
	GooConveyor = "Goo Conveyor",
	MeltingTiles = "Melting Tiles",
	Spinner = "Spinner",
	LilyLift = "Lily Lift",
	JellyWallHop = "Jelly Wall Hop",
	Tightrope = "Tightrope",
	FlipFloor = "Flip Floor",
	IceGauntlet = "Ice Gauntlet",
	ShrinkingPads = "Shrinking Pads",
	TrampolineField = "Trampoline Field",
	GooCascade = "Goo Cascade",
	GooPipe = "Goo Pipe",
	StickyLadder = "Sticky Ladder",
	BlobPendulums = "Blob Pendulums",
	FanShaft = "Fan Shaft",
	PoppingBubbles = "Popping Bubbles",
	SlimeSeesaw = "Slime Seesaw",
	SlimeCannon = "Slime Cannon",
	GooGates = "Goo Gates",
	BlobDrop = "Blob Drop",
	Turntables = "Turntables",
})

---------------------------------------------------------------------------
-- Part helpers (section-local: x from the section start, top of the entry level at y = 0)
---------------------------------------------------------------------------

-- A platform whose top is at `top`, centred on (x, z), `sx` long and `sz` wide.
local function slab(
	x: number,
	top: number,
	z: number,
	sx: number,
	sz: number,
	look: string,
	extra: { [string]: any }?
): Part
	local part: { [string]: any } = {
		size = { sx, ObbyCourse.THICK, sz },
		pos = { x, top - ObbyCourse.THICK / 2, z },
		look = look,
		step = true,
	}
	if extra then
		for k, v in extra do
			part[k] = v
		end
	end
	return part :: any
end

local function prop(size: Vec, pos: Vec, look: string, extra: { [string]: any }?): Part
	local part: { [string]: any } = { size = size, pos = pos, look = look }
	if extra then
		for k, v in extra do
			part[k] = v
		end
	end
	return part :: any
end

---------------------------------------------------------------------------
-- Sections: (layout 1..LAYOUTS) -> Section
---------------------------------------------------------------------------

local BUILD: { [string]: (layout: number) -> Section } = {}

-- A layout row of mixed values ({ kind, length, top, ... }); typed loosely on purpose.
local function row(...: any): { any }
	return { ... }
end

-- Bouncy jelly cubes, staggered across and up.
BUILD.JellySteps = function(layout)
	local L = ({
		{ gap = 2.5, size = 4, z = { 0, 2.5, -2.5, 2.5, 0 }, top = { 0, 1, 2, 1, 0 } },
		{ gap = 2.5, size = 4, z = { -3, 0, 3, 0, -3 }, top = { 0, 1, 1.5, 1, 0.5 } },
		{ gap = 3.5, size = 4.5, z = { 2.5, -2.5, 2.5, -2.5 }, top = { 0, 2, 0.5, 2.5 } },
		{ gap = 3, size = 4, z = { -2, 2, -2, 2 }, top = { 1, 2, 3, 2 } },
		{ gap = 2, size = 3.5, z = { 0, 3, 0, -3, 0, 3 }, top = { 0, 0, 1, 1, 0, 0 } },
		{ gap = 4, size = 5, z = { 0, 0, 0 }, top = { 1.5, 3, 1.5 } },
	})[layout]
	local parts = {}
	local x = L.gap
	for i, z in L.z do
		table.insert(parts, slab(x + L.size / 2, L.top[i], z, L.size, L.size, "jelly", { tone = i % 3 + 1 }))
		x += L.size + L.gap
	end
	return { length = x, rise = 0, parts = parts }
end

-- Long goo beams that sway from side to side.
BUILD.WobbleBridge = function(layout)
	local L = ({
		{ beams = 2, length = 11, width = 3, gap = 2.5, amp = 1.2, period = 3, shift = 0.5 },
		{ beams = 1, length = 22, width = 3, gap = 2.5, amp = 1.8, period = 3.4, shift = 0 },
		{ beams = 3, length = 7, width = 2.5, gap = 2, amp = 1.5, period = 2.6, shift = 0.33 },
		{ beams = 2, length = 12, width = 2.5, gap = 2, amp = 2, period = 3.8, shift = 0.25 },
		{ beams = 4, length = 5, width = 3, gap = 2.5, amp = 1.2, period = 2.2, shift = 0.5 },
		{ beams = 1, length = 26, width = 2.2, gap = 2.5, amp = 1, period = 2.6, shift = 0 },
	})[layout]
	local parts = {}
	local x = L.gap
	for i = 1, L.beams do
		local motion = { kind = "slide", axis = "z", amp = L.amp, period = L.period, phase = (i - 1) * L.shift }
		table.insert(parts, slab(x + L.length / 2, 0, 0, L.length, L.width, "goo", { motion = motion }))
		x += L.length + L.gap
	end
	return { length = x, rise = 0, parts = parts }
end

-- Floating bubble discs that bob up and down.
BUILD.BubbleHop = function(layout)
	local L = ({
		{ count = 4, gap = 3, size = 5, amp = 1.2, period = 2.4, z = { 0, 2, -2, 0 } },
		{ count = 5, gap = 2.5, size = 4, amp = 1.5, period = 2.8, z = { -2, 0, 2, 0, -2 } },
		{ count = 4, gap = 3, size = 5, amp = 1.8, period = 2.2, z = { 2, -2, 2, -2 } },
		{ count = 5, gap = 2.5, size = 4, amp = 1, period = 2, z = { 0, -2.5, 0, 2.5, 0 } },
		{ count = 4, gap = 3.5, size = 4.5, amp = 2.2, period = 3, z = { -2, -2, 2, 2 } },
		{ count = 3, gap = 4.5, size = 6, amp = 2.5, period = 2.6, z = { 0, 3, -3 } },
	})[layout]
	local parts = {}
	local x = L.gap
	for i = 1, L.count do
		local motion = { kind = "slide", axis = "y", amp = L.amp, period = L.period, phase = (i - 1) * 0.2 }
		table.insert(
			parts,
			slab(
				x + L.size / 2,
				0,
				L.z[i],
				L.size,
				L.size,
				"bubble",
				{ shape = "disc", motion = motion, tone = i % 3 + 1 }
			)
		)
		x += L.size + L.gap
	end
	return { length = x, rise = 0, parts = parts }
end

-- Goo belts that push you sideways (or back) while you cross.
BUILD.GooConveyor = function(layout)
	local L = ({
		{ length = 8, width = 10, gap = 3, belts = { { 0, 0, 6 }, { 0, 0, -6 }, { 0, 0, 6 } } },
		{ length = 7, width = 9, gap = 2.5, belts = { { 0, 0, -7 }, { 0, 0, 7 }, { 0, 0, -7 } } },
		{ length = 8, width = 10, gap = 3, belts = { { 0, 0, 8 }, { -5, 0, 0 }, { 0, 0, -8 } } },
		{ length = 5.5, width = 10, gap = 2.5, belts = { { 0, 0, -6 }, { 0, 0, 6 }, { 0, 0, -6 }, { 0, 0, 6 } } },
		{ length = 10, width = 9, gap = 3, belts = { { -6, 0, 0 }, { 0, 0, 7 } } },
		{ length = 7, width = 8, gap = 2.5, belts = { { 0, 0, 9 }, { 0, 0, 9 }, { 0, 0, -9 } } },
	})[layout]
	local parts = {}
	local x = L.gap
	for _, belt in L.belts do
		table.insert(parts, slab(x + L.length / 2, 0, 0, L.length, L.width, "goo", { conveyor = belt, tone = 2 }))
		x += L.length + L.gap
	end
	return { length = x, rise = 0, parts = parts }
end

-- A grid of tiles that melt away a moment after you step on them.
BUILD.MeltingTiles = function(layout)
	local L = ({
		{ cols = 6, delay = 0.7, holes = {} },
		{ cols = 7, delay = 0.6, holes = { ["2:1"] = true, ["4:3"] = true, ["6:1"] = true } },
		{ cols = 6, delay = 0.5, holes = { ["2:3"] = true, ["3:1"] = true, ["5:3"] = true } },
		{ cols = 7, delay = 0.8, holes = { ["1:1"] = true, ["3:3"] = true, ["5:1"] = true, ["7:3"] = true } },
		{ cols = 6, delay = 0.45, holes = {} },
		{
			cols = 7,
			delay = 0.6,
			holes = { ["2:1"] = true, ["2:3"] = true, ["4:2"] = true, ["6:1"] = true, ["6:3"] = true },
		},
	})[layout]
	local tile, gap = 4, 0.5
	local parts = {}
	for col = 1, L.cols do
		local x = gap + (col - 1) * (tile + gap) + tile / 2
		for lane = 1, 3 do
			if not L.holes[`{col}:{lane}`] then
				local motion = { kind = "melt", delay = L.delay, away = 2.5 }
				local part = slab(x, 0, (lane - 2) * (tile + gap), tile, tile, "tile", { motion = motion, tone = lane })
				part.step = lane == 2 -- the middle row is the reference path
				table.insert(parts, part)
			end
		end
	end
	return { length = gap + L.cols * (tile + gap), rise = 0, parts = parts }
end

-- A round platform swept by a spinning goo bar.
BUILD.Spinner = function(layout)
	local L = ({
		{ period = 4, bars = 1 },
		{ period = -3.2, bars = 1 },
		{ period = 4.4, bars = 2 },
		{ period = 3, bars = 1 },
		{ period = -4.4, bars = 2 },
		{ period = 5, bars = 3 },
	})[layout]
	local gap, size = 2, 22
	local cx = gap + size / 2
	local parts = { slab(cx, 0, 0, size, size, "jelly", { shape = "disc", tone = 2 }) }
	for i = 1, L.bars do
		table.insert(
			parts,
			prop({ size - 2, 1.2, 1.2 }, { cx, 1.1, 0 }, "bar", {
				motion = { kind = "spin", period = L.period, phase = (i - 1) * 0.5 / L.bars },
			})
		)
	end
	table.insert(parts, prop({ 1.6, 3, 1.6 }, { cx, 1.5, 0 }, "post"))
	return { length = gap * 2 + size, rise = 0, parts = parts }
end

-- Lily pads that glide from side to side.
BUILD.LilyLift = function(layout)
	local L = ({
		{ count = 4, amp = 3.5, period = 3.6, phases = { 0, 0.5, 0, 0.5 } },
		{ count = 4, amp = 3.5, period = 3, phases = { 0, 0.25, 0.5, 0.75 } },
		{ count = 4, amp = 4.5, period = 4, phases = { 0, 0.5, 0.2, 0.7 } },
		{ count = 4, amp = 2.5, period = 2.4, phases = { 0, 0, 0, 0 } },
		{ count = 4, amp = 4, period = 3.2, phases = { 0, 0.5, 0.5, 0 } },
		{ count = 3, amp = 5, period = 4.4, phases = { 0, 0.33, 0.66 } },
	})[layout]
	local size, gap = 5, 3
	local parts = {}
	local x = gap
	for i = 1, L.count do
		local motion = { kind = "slide", axis = "z", amp = L.amp, period = L.period, phase = L.phases[i] }
		table.insert(
			parts,
			slab(x + size / 2, 0, 0, size, size, "jelly", { shape = "disc", motion = motion, tone = 1 })
		)
		x += size + gap
	end
	return { length = x, rise = 0, parts = parts }
end

-- Zigzag ledges up a jelly wall: the course climbs.
BUILD.JellyWallHop = function(layout)
	local L = ({
		{ count = 5, rise = 2.5, z = { -3.5, 3.5, -3.5, 3.5, 0 } },
		{ count = 6, rise = 2.5, z = { 3.5, -3.5, 3.5, -3.5, 3.5, 0 } },
		{ count = 5, rise = 3, z = { 0, -4, 0, 4, 0 } },
		{ count = 6, rise = 2, z = { -4, -1, 2, 4, 1, -2 } },
		{ count = 4, rise = 3, z = { 3.5, -3.5, 3.5, 0 } },
		{ count = 5, rise = 3.5, z = { -3, 3, -3, 3, 0 } },
	})[layout]
	local size, spacing, gap = 4, 5.5, 2
	local parts = {}
	for i = 1, L.count do
		local x = gap + size / 2 + (i - 1) * spacing
		table.insert(parts, slab(x, i * L.rise, L.z[i], size, size, "jelly", { tone = i % 3 + 1 }))
	end
	local top = L.count * L.rise
	local wallX = gap + (L.count - 1) * spacing / 2 + size / 2
	table.insert(parts, prop({ (L.count - 1) * spacing + size, top + 2, 1 }, { wallX, (top + 2) / 2 - 1, 7 }, "jelly"))
	return { length = gap * 2 + size + (L.count - 1) * spacing, rise = top, parts = parts }
end

-- Thin beams with gaps and side steps.
BUILD.Tightrope = function(layout)
	local L = ({
		{ width = 1.2, length = 8, gap = 2.5, z = { 0, 2, -2 } },
		{ width = 1, length = 5.5, gap = 2.5, z = { -2.5, 0, 2.5, 0 } },
		{ width = 0.9, length = 8, gap = 3, z = { 2, -2, 1 } },
		{ width = 1.1, length = 4.5, gap = 2, z = { -3, -1, 1, 3, 1 } },
		{ width = 1.4, length = 12.5, gap = 3.5, z = { -1.5, 1.5 } },
		{ width = 0.8, length = 7, gap = 2.5, z = { 0, 0, 0 } },
	})[layout]
	local parts = {}
	local x = L.gap
	for i, z in L.z do
		table.insert(parts, slab(x + L.length / 2, 0, z, L.length, L.width, "rope", { tone = i % 3 + 1 }))
		x += L.length + L.gap
	end
	return { length = x, rise = 0, parts = parts }
end

-- Tiles in two colours that take turns being solid.
BUILD.FlipFloor = function(layout)
	local L = ({
		{ count = 7, period = 4, duty = 0.65, z = { 0, 0, 0, 0, 0, 0, 0 } },
		{ count = 7, period = 3.4, duty = 0.65, z = { -2, 0, 2, 0, -2, 0, 2 } },
		{ count = 7, period = 4, duty = 0.6, z = { 2, 2, -2, -2, 2, 2, 0 } },
		{ count = 6, period = 2.8, duty = 0.7, z = { 0, 0, 0, 0, 0, 0 } },
		{ count = 7, period = 4.6, duty = 0.6, z = { 0, 2, 0, -2, 0, 2, 0 } },
		{ count = 5, period = 3.2, duty = 0.65, z = { -2, 2, -2, 2, 0 } },
	})[layout]
	local tile, gap = 4, 1
	local parts = {}
	local x = gap
	for i = 1, L.count do
		local group = (i - 1) % 2
		local motion = { kind = "flip", period = L.period, phase = group * 0.5, duty = L.duty }
		table.insert(parts, slab(x + tile / 2, 0, L.z[i], tile, tile, "tile", { motion = motion, tone = group + 1 }))
		x += tile + gap
	end
	return { length = x, rise = 0, parts = parts }
end

-- A slippery path with spinning sweepers on posts.
BUILD.IceGauntlet = function(layout)
	local L = ({
		{ length = 30, width = 7, sweepers = { { 10, 3 }, { 21, -3.5 } } },
		{ length = 32, width = 7, sweepers = { { 8, -3 }, { 16, 3.4 }, { 24, -3 } } },
		{ length = 28, width = 5.5, sweepers = { { 9, 2.6 }, { 19, -2.6 } } },
		{ length = 30, width = 6, sweepers = { { 7, -2.8 }, { 15, 2.8 }, { 23, -2.8 } } },
		{ length = 26, width = 8, sweepers = { { 13, 2.2 } } },
		{ length = 32, width = 6.5, sweepers = { { 6, 3.2 }, { 12, -3.2 }, { 20, 3.2 }, { 26, -3.2 } } },
	})[layout]
	local gap = 2
	local parts = { slab(gap + L.length / 2, 0, 0, L.length, L.width, "ice", { ice = true }) }
	for i, s in L.sweepers do
		local x = gap + s[1]
		table.insert(parts, prop({ 1.2, 3, 1.2 }, { x, 1.5, 0 }, "post"))
		table.insert(
			parts,
			prop({ L.width + 1, 1, 1 }, { x, 1.2, 0 }, "bar", {
				motion = { kind = "spin", period = s[2], phase = (i - 1) * 0.3 },
			})
		)
	end
	return { length = gap * 2 + L.length, rise = 0, parts = parts }
end

-- Pads that shrink and grow back.
BUILD.ShrinkingPads = function(layout)
	local L = ({
		{ count = 4, gap = 3, period = 3, min = 0.3, z = { 0, 0, 0, 0 } },
		{ count = 4, gap = 2.5, period = 2.6, min = 0.3, z = { 0, 1.5, -1.5, 1.5 } },
		{ count = 4, gap = 3, period = 3.4, min = 0.2, z = { 2, -2, 2, -2 } },
		{ count = 4, gap = 2.5, period = 2.2, min = 0.4, z = { 0, 0, 0, 0 } },
		{ count = 3, gap = 4, period = 4, min = 0.25, z = { 0, 2.5, -2.5 } },
		{ count = 4, gap = 3, period = 2.8, min = 0.3, z = { -2.5, 2.5, -2.5, 2.5 } },
	})[layout]
	local size = 5
	local parts = {}
	local x = L.gap
	for i = 1, L.count do
		local motion = { kind = "shrink", period = L.period, phase = (i - 1) * 0.2, min = L.min }
		table.insert(parts, slab(x + size / 2, 0, L.z[i], size, size, "jelly", { motion = motion, tone = 3 }))
		x += size + L.gap
	end
	return { length = x, rise = 0, parts = parts }
end

-- Launch speeds (studs / s straight up) and the fan's lift; tests check every gap against them.
ObbyCourse.TRAMPOLINE = 62 -- about 9.8 studs high
ObbyCourse.CANNON = 75 -- about 14 studs high: long enough in the air to walk across a wide gap
ObbyCourse.FAN_LIFT = 30

-- Trampolines that bounce you up to higher ledges.
BUILD.TrampolineField = function(layout)
	local L = ({
		{ gap = 2.5, items = { row("t", 5, 0, 0), row("l", 6, 6, 0), row("t", 5, 6, 2), row("l", 6, 12, 0) } },
		{ gap = 3, items = { row("t", 4, 0, -2), row("l", 5, 7, 2), row("t", 4, 7, -2), row("l", 6, 7, 0) } },
		{ gap = 2, items = { row("t", 6, 0, 0), row("t", 6, 4, 0), row("l", 8, 10, 0) } },
		{ gap = 3, items = { row("t", 5, 0, 0), row("l", 5, 5, 0), row("t", 5, 2, 0), row("l", 5, 9, 0) } },
		{ gap = 2.5, items = { row("t", 4, 0, 3), row("t", 4, 0, -3), row("t", 4, 0, 3), row("l", 6, 6, 0) } },
		{ gap = 4, items = { row("t", 6, 0, 0), row("l", 4, 8, 0), row("t", 6, 8, 0) } },
	})[layout]
	local parts = {}
	local x, top = L.gap, 0
	for i, it in L.items do
		local kind, len, t, z = it[1], it[2], it[3], it[4]
		if kind == "t" then
			local motion = { kind = "bounce", power = ObbyCourse.TRAMPOLINE }
			table.insert(parts, slab(x + len / 2, t, z, len, 6, "trampoline", { motion = motion, tone = i % 2 + 1 }))
		else
			table.insert(parts, slab(x + len / 2, t, z, len, 6, "jelly", { tone = 2 }))
		end
		x += len + L.gap
		top = t
	end
	return { length = x, rise = top, parts = parts }
end

-- Goo terraces stepping down, with blobs rolling across them.
BUILD.GooCascade = function(layout)
	local L = ({
		{ n = 4, len = 7, drop = 1.5, gap = 1, blobs = { 2, 3 }, period = 2.6 },
		{ n = 5, len = 5.5, drop = 1, gap = 0.5, blobs = { 1, 3, 5 }, period = 2.2 },
		{ n = 3, len = 9, drop = 2.5, gap = 1.5, blobs = { 1, 2, 3 }, period = 3 },
		{ n = 4, len = 6, drop = 2, gap = 1.5, blobs = { 2, 4 }, period = 2 },
		{ n = 6, len = 4, drop = 1, gap = 1, blobs = { 2, 4, 6 }, period = 2.4 },
		{ n = 4, len = 7.5, drop = 1, gap = 0.5, blobs = { 1, 2, 3, 4 }, period = 2.8 },
	})[layout]
	local blob = {}
	for _, i in L.blobs do
		blob[i] = true
	end
	local parts = {}
	local x = L.gap
	for i = 1, L.n do
		local top = -i * L.drop
		local cx = x + L.len / 2
		table.insert(parts, slab(cx, top, 0, L.len, 10, "goo", { tone = i % 2 + 1 }))
		if blob[i] then
			local motion = { kind = "slide", axis = "z", amp = 3.5, period = L.period, phase = i * 0.3 }
			table.insert(parts, prop({ 3, 3, 3 }, { cx, top + 1.5, 0 }, "blob", { shape = "ball", motion = motion }))
		end
		x += L.len + L.gap
	end
	return { length = x, rise = -L.n * L.drop, parts = parts }
end

-- A see-through goo pipe with holes in its floor.
BUILD.GooPipe = function(layout)
	local L = ({
		{ width = 7, floors = { 8, 6, 6 }, holes = { 1, 3, 3, 3 } },
		{ width = 7, floors = { 5, 5, 5, 5 }, holes = { 1, 2.5, 2.5, 2.5, 2.5 } },
		{ width = 7, floors = { 10, 4, 8 }, holes = { 1, 4, 3.5, 2 } },
		{ width = 4, floors = { 4, 4, 4, 4, 4 }, holes = { 1, 2, 2, 2, 2, 2 } },
		{ width = 7, floors = { 6, 3, 3, 6 }, holes = { 1, 3, 3, 3, 3 } },
		{ width = 3, floors = { 12, 12 }, holes = { 1, 4, 1 } },
	})[layout]
	local parts = {}
	local x = 0
	for i, len in L.floors do
		x += L.holes[i]
		table.insert(parts, slab(x + len / 2, 0, 0, len, L.width, "goo", { tone = 2 }))
		x += len
	end
	x += L.holes[#L.holes]
	-- Walls and a roof the whole way along, high enough for a full jump.
	local inner, height = 8, 15
	table.insert(parts, prop({ x, height, 1 }, { x / 2, height / 2 - 1, -inner / 2 - 0.5 }, "pipe"))
	table.insert(parts, prop({ x, height, 1 }, { x / 2, height / 2 - 1, inner / 2 + 0.5 }, "pipe"))
	table.insert(parts, prop({ x, 1, inner + 2 }, { x / 2, height - 0.5, 0 }, "pipe"))
	return { length = x, rise = 0, parts = parts }
end

-- Climbable jelly ladders up to ledges: the course climbs.
BUILD.StickyLadder = function(layout)
	local L = ({
		{ row("truss", 8, 0), row("ledge", 6, 0), row("truss", 6, 0), row("ledge", 5, 0) },
		{
			row("truss", 4, 0),
			row("ledge", 4, 0),
			row("truss", 4, 0),
			row("ledge", 4, 0),
			row("truss", 4, 0),
			row("ledge", 5, 0),
		},
		{ row("truss", 10, 0), row("ledge", 8, 0) },
		{ row("truss", 6, -2), row("ledge", 5, 0), row("truss", 6, 2), row("ledge", 6, 0) },
		{ row("truss", 4, 0), row("ledge", 6, 0), row("truss", 8, 0), row("ledge", 5, 0) },
		{ row("truss", 12, 0), row("ledge", 8, 0) },
	})[layout]
	local parts = {}
	local x, top = 1, 0
	for i, it in L do
		local kind, n, z = it[1], it[2], it[3]
		if kind == "truss" then
			table.insert(parts, prop({ 2, n, 2 }, { x + 1, top + n / 2, z }, "truss", { shape = "truss", step = true }))
			x += 2
			top += n
		else
			table.insert(parts, slab(x + n / 2, top, z, n, 6, "jelly", { tone = i % 3 + 1 }))
			x += n
		end
	end
	return { length = x + 2, rise = top, parts = parts }
end

-- Swinging goo blobs on rods over a beam.
BUILD.BlobPendulums = function(layout)
	local L = ({
		{ beams = { 30 }, width = 3, amp = 55, arm = 8, period = 2.6, at = { 8, 16, 24 }, phases = { 0, 0.33, 0.66 } },
		{
			beams = { 14, 14 },
			width = 3,
			amp = 55,
			arm = 8,
			period = 2.2,
			at = { 6, 13, 21, 28 },
			phases = { 0, 0.5, 0, 0.5 },
		},
		{ beams = { 30 }, width = 4, amp = 65, arm = 10, period = 3, at = { 7, 15, 23 }, phases = { 0, 0.5, 0 } },
		{
			beams = { 9, 9, 9 },
			width = 3,
			amp = 50,
			arm = 8,
			period = 2.4,
			at = { 6.5, 17.5, 28.5 },
			phases = { 0, 0.33, 0.66 },
		},
		{ beams = { 30 }, width = 2.5, amp = 45, arm = 7, period = 1.8, at = { 10, 20 }, phases = { 0, 0.5 } },
		{
			beams = { 30 },
			width = 3.5,
			amp = 60,
			arm = 9,
			period = 2.8,
			at = { 6, 12, 18, 24 },
			phases = { 0, 0.5, 0, 0.5 },
		},
	})[layout]
	local gap = 2
	local parts = {}
	local x = gap
	for _, len in L.beams do
		table.insert(parts, slab(x + len / 2, 0, 0, len, L.width, "goo", { tone = 1 }))
		x += len + gap
	end
	for i, at in L.at do
		local px = gap + at
		local swing = { kind = "swing", amp = L.amp, period = L.period, phase = L.phases[i], arm = L.arm }
		table.insert(parts, prop({ 3, 3, 3 }, { px, 1.5, 0 }, "blob", { shape = "ball", motion = swing }))
		local rod = table.clone(swing)
		rod.arm = L.arm / 2
		table.insert(
			parts,
			prop({ 0.4, L.arm, 0.4 }, { px, 1.5 + L.arm / 2, 0 }, "rope", { motion = rod, ghost = true })
		)
	end
	return { length = x, rise = 0, parts = parts }
end

-- Fans whose wind lifts you up to the next ledge.
BUILD.FanShaft = function(layout)
	local L = ({
		{ row("fan", 8, 0), row("ledge", 6, 0), row("fan", 6, 0), row("ledge", 5, 0) },
		{ row("fan", 10, 0), row("ledge", 8, 0) },
		{ row("fan", 6, 0), row("ledge", 4, 0), row("fan", 6, 0), row("ledge", 4, 0) },
		{ row("fan", 12, 0), row("ledge", 6, 0) },
		{ row("fan", 4, 0), row("ledge", 5, 0), row("fan", 8, 0), row("ledge", 5, 0) },
		{ row("fan", 8, -3), row("ledge", 5, 2), row("fan", 4, 2), row("ledge", 6, 0) },
	})[layout]
	local size = 5
	local parts = {}
	local x, top = 2, 0
	for _, it in L do
		local kind, n, z = it[1], it[2], it[3]
		if kind == "fan" then
			local cx = x + size / 2
			table.insert(parts, slab(cx, top, z, size, size, "fan", { shape = "disc" }))
			local h = n + 4 -- the wind reaches 4 studs over the ledge, so you float up and step across
			local lift = { kind = "lift", power = ObbyCourse.FAN_LIFT }
			table.insert(
				parts,
				prop({ size, h, size }, { cx, top + h / 2, z }, "wind", { motion = lift, ghost = true, step = true })
			)
			x += size + 1
			top += n
		else
			table.insert(parts, slab(x + n / 2, top, z, n, 5, "jelly", { tone = 3 }))
			x += n + 2
		end
	end
	return { length = x, rise = top, parts = parts }
end

-- Bubbles that pop a moment after you land on them.
BUILD.PoppingBubbles = function(layout)
	local L = ({
		{ gap = 2.5, size = 4, delay = 1, z = { 0, 2, -2, 2, 0 }, top = { 0, 1, 2, 1, 0 } },
		{ gap = 3, size = 5, delay = 0.8, z = { -2, 2, -2, 2 }, top = { 0, 0, 0, 0 } },
		{ gap = 2, size = 3.5, delay = 1.2, z = { 0, 0, 0, 0, 0, 0 }, top = { 0, 0.5, 1, 1.5, 2, 2.5 } },
		{ gap = 3, size = 3.5, delay = 0.7, z = { 3, -3, 3, -3, 0 }, top = { 0, 0, 0, 0, 0 } },
		{ gap = 4, size = 6, delay = 0.6, z = { 0, 0, 0 }, top = { 1, 2, 1 } },
		{ gap = 2.5, size = 4, delay = 1, z = { 2, 2, -2, -2, 0 }, top = { 0, 2, 4, 2, 0 } },
	})[layout]
	local parts = {}
	local x = L.gap
	for i, z in L.z do
		local motion = { kind = "melt", delay = L.delay, away = 2 }
		table.insert(
			parts,
			slab(
				x + L.size / 2,
				L.top[i],
				z,
				L.size,
				L.size,
				"bubble",
				{ shape = "disc", motion = motion, tone = i % 3 + 1 }
			)
		)
		x += L.size + L.gap
	end
	return { length = x, rise = 0, parts = parts }
end

-- Planks that rock like seesaws.
BUILD.SlimeSeesaw = function(layout)
	local L = ({
		{ count = 3, len = 8, width = 4, gap = 2.5, amp = 12, period = 3, phases = { 0, 0.5, 0 } },
		{ count = 2, len = 13, width = 4, gap = 3, amp = 10, period = 3.6, phases = { 0, 0.5 } },
		{ count = 4, len = 6, width = 4, gap = 2, amp = 15, period = 2.6, phases = { 0, 0.25, 0.5, 0.75 } },
		{ count = 3, len = 8, width = 3, gap = 2.5, amp = 14, period = 2.4, phases = { 0, 0, 0 } },
		{ count = 3, len = 9, width = 4, gap = 2, amp = 8, period = 4, phases = { 0, 0.33, 0.66 } },
		{ count = 4, len = 6, width = 3.5, gap = 2, amp = 18, period = 3.2, phases = { 0, 0.5, 0, 0.5 } },
	})[layout]
	local parts = {}
	local x = L.gap
	for i = 1, L.count do
		local cx = x + L.len / 2
		local motion = { kind = "rock", amp = L.amp, period = L.period, phase = L.phases[i] }
		table.insert(parts, slab(cx, 0, 0, L.len, L.width, "plank", { motion = motion, tone = i % 2 + 1 }))
		table.insert(parts, prop({ 1, 2, 1 }, { cx, -2, 0 }, "post"))
		x += L.len + L.gap
	end
	return { length = x, rise = 0, parts = parts }
end

-- Slime cannons that throw you high over wide gaps.
BUILD.SlimeCannon = function(layout)
	-- { kind, length, top, z, gap after }
	local L = ({
		{ row("c", 4, 0, 0, 8), row("i", 8, 0, 0, 2) },
		{ row("c", 4, 0, 0, 6), row("i", 5, 3, 0, 2), row("c", 4, 3, 0, 6), row("i", 5, 3, 0, 2) },
		{ row("c", 4, 0, 0, 9), row("i", 8, -2, 0, 2) },
		{ row("c", 4, 0, 0, 6), row("i", 4, 8, 0, 2), row("i", 8, 8, 0, 2) },
		{ row("c", 4, 0, -3, 7), row("c", 4, 0, 3, 7), row("i", 8, 0, 0, 2) },
		{ row("c", 4, 0, 0, 9), row("i", 6, 0, 0, 2), row("i", 4, 1, 0, 2) },
	})[layout]
	local parts = {}
	local x, top = 2, 0
	for i, it in L do
		local kind, len, t, z, after = it[1], it[2], it[3], it[4], it[5]
		if kind == "c" then
			local motion = { kind = "bounce", power = ObbyCourse.CANNON }
			table.insert(parts, slab(x + len / 2, t, z, len, 5, "cannon", { motion = motion }))
		else
			table.insert(parts, slab(x + len / 2, t, z, len, 7, "jelly", { tone = i % 3 + 1 }))
		end
		x += len + after
		top = t
	end
	return { length = x, rise = top, parts = parts }
end

-- A walkway through goo gates that drop and lift.
BUILD.GooGates = function(layout)
	local L = ({
		{ slabs = { 30 }, width = 6, gates = { 8, 16, 24 }, period = 2.8, phases = { 0, 0.33, 0.66 } },
		{ slabs = { 30 }, width = 5, gates = { 10, 20 }, period = 2.2, phases = { 0, 0.5 } },
		{ slabs = { 32 }, width = 6, gates = { 6, 12, 18, 24 }, period = 3, phases = { 0, 0.25, 0.5, 0.75 } },
		{ slabs = { 14, 14 }, width = 6, gates = { 7, 23 }, period = 2.5, phases = { 0, 0.5 } },
		{ slabs = { 28 }, width = 4, gates = { 9, 19 }, period = 1.8, phases = { 0, 0.5 } },
		{ slabs = { 30 }, width = 6, gates = { 7, 15, 23 }, period = 3.4, phases = { 0, 0, 0 } },
	})[layout]
	local gap = 2
	local parts = {}
	local x = gap
	for _, len in L.slabs do
		table.insert(parts, slab(x + len / 2, 0, 0, len, L.width, "goo", { tone = 2 }))
		x += len + gap
	end
	for i, at in L.gates do
		-- Rests half shut (bottom 4 studs up); its bottom sweeps from the floor to 8 studs up.
		local motion = { kind = "slide", axis = "y", amp = 4, period = L.period, phase = L.phases[i] }
		table.insert(parts, prop({ 1.2, 8, L.width + 1 }, { gap + at, 8, 0 }, "gate", { motion = motion }))
	end
	return { length = x, rise = 0, parts = parts }
end

-- Thin paths under goo blobs that drop and bounce back up.
BUILD.BlobDrop = function(layout)
	local L = ({
		{ paths = { { 30, 0 } }, width = 2.5, blobs = { 8, 15, 22 }, period = 2.4, shift = 0.33 },
		{ paths = { { 30, 0 } }, width = 2, blobs = { 6, 12, 18, 24 }, period = 2, shift = 0.5 },
		{ paths = { { 13, 0 }, { 13, 0 } }, width = 2.5, blobs = { 6, 20, 26 }, period = 2.8, shift = 0.33 },
		{ paths = { { 30, 0 } }, width = 3, blobs = { 5, 10, 15, 20, 25 }, period = 2.6, shift = 0.2 },
		{ paths = { { 28, 0 } }, width = 1.6, blobs = { 10, 20 }, period = 3, shift = 0.5 },
		{ paths = { { 8, -2 }, { 8, 2 }, { 8, -2 } }, width = 2.5, blobs = { 6, 16, 26 }, period = 2.2, shift = 0.33 },
	})[layout]
	local gap = 2
	local parts = {}
	local spans = {}
	local x = gap
	for _, path in L.paths do
		local len, z = path[1], path[2]
		table.insert(parts, slab(x + len / 2, 0, z, len, L.width, "rope", { tone = 2 }))
		table.insert(spans, { x, x + len, z })
		x += len + gap
	end
	for i, at in L.blobs do
		local bx = gap + at
		local z = 0
		for _, s in spans do
			if bx >= s[1] and bx <= s[2] then
				z = s[3]
			end
		end
		-- Rests 6 studs up; at the bottom of its drop it sits on the path.
		local motion = { kind = "slide", axis = "y", amp = 4, period = L.period, phase = (i - 1) * L.shift }
		table.insert(parts, prop({ 4, 4, 4 }, { bx, 6, z }, "blob", { shape = "ball", motion = motion }))
	end
	return { length = x, rise = 0, parts = parts }
end

-- Spinning turntables that carry you round; some with a sweeping bar.
BUILD.Turntables = function(layout)
	local L = ({
		{ size = 8, gap = 3, period = 6, flip = true, z = { 0, 0, 0 }, bars = {} },
		{ size = 6, gap = 2, period = 4, flip = false, z = { 0, 0, 0, 0 }, bars = {} },
		{ size = 12, gap = 3, period = 5, flip = true, z = { 0, 0 }, bars = { 1, 2 } },
		{ size = 7, gap = 3.5, period = 3, flip = false, z = { 0, 0, 0 }, bars = {} },
		{ size = 8, gap = 3, period = -4.5, flip = false, z = { -2, 2, -2 }, bars = { 2 } },
		{ size = 5.5, gap = 2.5, period = 3.5, flip = true, z = { 0, 0, 0, 0 }, bars = {} },
	})[layout]
	local bar = {}
	for _, i in L.bars do
		bar[i] = true
	end
	local parts = {}
	local x = L.gap
	for i, z in L.z do
		local cx = x + L.size / 2
		local period = if L.flip and i % 2 == 0 then -L.period else L.period
		local motion = { kind = "spin", period = period }
		table.insert(
			parts,
			slab(cx, 0, z, L.size, L.size, "jelly", { shape = "disc", motion = motion, tone = i % 3 + 1 })
		)
		if bar[i] then
			local sweep = { kind = "spin", period = -period * 0.8 }
			table.insert(parts, prop({ L.size - 1.5, 1, 1 }, { cx, 1, z }, "bar", { motion = sweep }))
		end
		x += L.size + L.gap
	end
	return { length = x, rise = 0, parts = parts }
end

ObbyCourse.BUILD = table.freeze(BUILD)

---------------------------------------------------------------------------
-- Rotation
---------------------------------------------------------------------------

function ObbyCourse.slot(now: number): number
	return math.floor(now / OBBY.ROTATION_SECONDS)
end

-- Server time the rotation `slot` starts.
function ObbyCourse.slotStart(slot: number): number
	return slot * OBBY.ROTATION_SECONDS
end

local function seedOf(slot: number): number
	return (math.floor(slot) * 2654435761 + 1013) % 2147483646 + 1
end

local function rawPick(slot: number, avoid: { [string]: boolean }): { Pick }
	local rng = Rng.new(seedOf(slot))
	local used: { [string]: boolean } = {}
	local out: { Pick } = {}
	for _, tier in OBBY.ORDER do
		local pool = (OBBY.SECTIONS :: any)[tier] :: { string }
		local options = {}
		for _, id in pool do
			if not used[id] and not avoid[id] then
				table.insert(options, id)
			end
		end
		if #options == 0 then
			for _, id in pool do
				if not used[id] then
					table.insert(options, id)
				end
			end
		end
		local id = options[rng:int(1, #options)]
		used[id] = true
		table.insert(out, { id = id, tier = tier, layout = rng:int(1, OBBY.LAYOUTS) })
	end
	return out
end

-- The sections of rotation `slot`. Inside one chain of CHAIN_SLOTS rotations no section of a course comes back in
-- the next one; the first course of a chain starts fresh.
function ObbyCourse.pick(slot: number): { Pick }
	local anchor = slot - slot % OBBY.CHAIN_SLOTS
	local picks = rawPick(anchor, {})
	for s = anchor + 1, slot do
		local avoid = {}
		for _, p in picks do
			avoid[p.id] = true
		end
		picks = rawPick(s, avoid)
	end
	return picks
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

local function offset(part: Part, dx: number, dy: number): Part
	local moved = table.clone(part)
	moved.pos = { part.pos[1] + dx, part.pos[2] + dy, part.pos[3] }
	return moved
end

-- One section with the layout given, in section-local coordinates.
function ObbyCourse.section(id: string, layout: number): Section
	local build = BUILD[id]
	assert(build, `unknown obby section {id}`)
	return build(math.clamp(math.floor(layout), 1, OBBY.LAYOUTS))
end

-- Lays out `picks` (default: the sections of `slot`).
function ObbyCourse.build(slot: number, picks: { Pick }?): Course
	local chosen = picks or ObbyCourse.pick(slot)
	local W, S = ObbyCourse.WIDTH, ObbyCourse.STAND_HEIGHT
	local parts: { Part } = { slab(ObbyCourse.START_LENGTH / 2, 0, 0, ObbyCourse.START_LENGTH, W, "start") }
	local checkpoints: { Checkpoint } = {}
	local x, y = ObbyCourse.START_LENGTH, 0
	for i, pick in chosen do
		local section = ObbyCourse.section(pick.id, pick.layout)
		for _, part in section.parts do
			table.insert(parts, offset(part, x, y))
		end
		x += section.length
		y += section.rise
		local last = i == #chosen
		local depth = if last then ObbyCourse.FINISH_LENGTH else ObbyCourse.PAD_LENGTH
		table.insert(parts, slab(x + depth / 2, y, 0, depth, W, if last then "finish" else "pad"))
		table.insert(checkpoints, { index = i, pos = { x + depth / 2, y, 0 }, size = { depth, S, W } })
		x += depth
	end
	return {
		slot = slot,
		picks = chosen,
		parts = parts,
		start = { ObbyCourse.START_LENGTH / 3, OBBY.RESPAWN_LIFT, 0 },
		startTop = 0,
		checkpoints = checkpoints,
		length = x,
	}
end

-- True when course-local `p` stands on checkpoint `cp` (over its pad, up to STAND_HEIGHT above the top).
function ObbyCourse.onCheckpoint(cp: Checkpoint, p: Vec): boolean
	return math.abs(p[1] - cp.pos[1]) <= cp.size[1] / 2
		and math.abs(p[3] - cp.pos[3]) <= cp.size[3] / 2
		and p[2] >= cp.pos[2] - 1
		and p[2] <= cp.pos[2] + cp.size[2]
end

-- Top of the pad a runner last reached: 0 = the start pad, i = checkpoint i.
function ObbyCourse.padTop(course: Course, reached: number): number
	local cp = course.checkpoints[reached]
	return if cp then cp.pos[2] else course.startTop
end

-- Where a runner who last reached pad `reached` respawns (course-local).
function ObbyCourse.respawn(course: Course, reached: number): Vec
	local cp = course.checkpoints[reached]
	if not cp then
		return table.clone(course.start)
	end
	return { cp.pos[1], cp.pos[2] + OBBY.RESPAWN_LIFT, cp.pos[3] }
end

-- A runner heading from pad `reached` to the next one has fallen below this height (course-local y).
function ObbyCourse.fallHeight(course: Course, reached: number): number
	local from = ObbyCourse.padTop(course, reached)
	local nextCp = course.checkpoints[reached + 1]
	local to = if nextCp then nextCp.pos[2] else from
	return math.min(from, to) - OBBY.FALL_DEPTH
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local function axes(frame: Frame): (number, number)
	local a = math.rad(frame.yaw)
	return math.sin(a), math.cos(a)
end

-- Course-local point -> world.
function ObbyCourse.toWorld(frame: Frame, p: Vec): Vec
	local fx, fz = axes(frame)
	local o = frame.origin
	-- right = forward x up = (-fz, 0, fx)
	return { o[1] + fx * p[1] - fz * p[3], o[2] + p[2], o[3] + fz * p[1] + fx * p[3] }
end

-- World point -> course-local.
function ObbyCourse.toLocal(frame: Frame, p: Vec): Vec
	local fx, fz = axes(frame)
	local o = frame.origin
	local dx, dz = p[1] - o[1], p[3] - o[3]
	return { dx * fx + dz * fz, p[2] - o[2], -dx * fz + dz * fx }
end

-- Display names of a course's sections, in order.
function ObbyCourse.names(picks: { Pick }): { string }
	local out = {}
	for _, p in picks do
		table.insert(out, ObbyCourse.NAMES[p.id] or p.id)
	end
	return out
end

return table.freeze(ObbyCourse)
