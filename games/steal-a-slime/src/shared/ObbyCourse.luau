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
  roll    a log (shape "log"): rolls round its own length once per `period` seconds and carries you sideways
  punch   shoots out `amp` along `axis` fast, holds, slides back and rests: a shove that knocks you off
  gust    a see-through wind zone: while frac(t / period + phase) < `duty` it blows the local player inside it
          along `axis` at `power` studs / s (negative = the other way)
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
	-- | "trampoline" | "blob" | "pipe" | "truss" | "fan" | "wind" | "plank" | "cannon" | "gate" | "belt" | "glow"
	-- | "log" | "wave" | "puncher" | "gust"
	shape: string?, -- "block" (default) | "disc" (a flat cylinder, size.x = diameter) | "ball" | "truss" (climbable)
	-- | "log" (a cylinder lying along x, size.y = size.z = diameter)
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
	GlowTrail = "Glow Trail",
	TwoWays = "Two Ways",
	RollingLogs = "Rolling Logs",
	GooWave = "Goo Wave",
	GooPunchers = "Goo Punchers",
	GustyBridge = "Gusty Bridge",
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

-- Bouncy jelly cubes, staggered across and up: real jumps, not steps.
BUILD.JellySteps = function(layout)
	local L = ({
		{ gap = 3, size = 3.5, z = { 0, 2.5, -2.5, 2.5, 0 }, top = { 0, 1, 2, 1, 0 } },
		{ gap = 3.5, size = 3.5, z = { -3, 0, 3, 0 }, top = { 1, 2, 3, 1.5 } },
		{ gap = 4, size = 4, z = { 2.5, -2.5, 2.5, -2.5 }, top = { 0, 2, 0.5, 2.5 } },
		{ gap = 3.5, size = 3, z = { -2, 2, -2, 2, 0 }, top = { 1, 2, 3, 2, 1 } },
		{ gap = 3, size = 3, z = { 0, 3, 0, -3, 0 }, top = { 0, 1, 2, 1, 0 } },
		{ gap = 4.5, size = 4, z = { 0, -1.5, 1.5 }, top = { 1.5, 3, 1.5 } },
	})[layout]
	local parts = {}
	local x = L.gap
	for i, z in L.z do
		table.insert(parts, slab(x + L.size / 2, L.top[i], z, L.size, L.size, "jelly", { tone = i % 3 + 1 }))
		x += L.size + L.gap
	end
	return { length = x, rise = 0, parts = parts }
end

-- Short goo beams sliding side to side, each one the other way: hop across when two line up.
BUILD.WobbleBridge = function(layout)
	local L = ({
		{ beams = 3, length = 7, width = 3, gap = 2.5, amp = 2.5, period = 3.2 },
		{ beams = 2, length = 12, width = 2.5, gap = 3, amp = 3, period = 3.6 },
		{ beams = 4, length = 5, width = 3, gap = 2.5, amp = 2.5, period = 2.8 },
		{ beams = 3, length = 7, width = 2.5, gap = 3, amp = 3, period = 3 },
		{ beams = 4, length = 5.5, width = 3, gap = 2.5, amp = 3, period = 3.4 },
		{ beams = 3, length = 8, width = 2.2, gap = 2.5, amp = 2, period = 2.6 },
	})[layout]
	local parts = {}
	local x = L.gap
	for i = 1, L.beams do
		local motion = { kind = "slide", axis = "z", amp = L.amp, period = L.period, phase = (i - 1) * 0.5 }
		table.insert(
			parts,
			slab(x + L.length / 2, 0, 0, L.length, L.width, "goo", { motion = motion, tone = i % 2 + 1 })
		)
		x += L.length + L.gap
	end
	return { length = x, rise = 0, parts = parts }
end

-- Bubble discs bobbing up and down, each against the one before: jump when the next one is low.
BUILD.BubbleHop = function(layout)
	local L = ({
		{ count = 4, gap = 3.5, size = 4.5, amp = 2.5, period = 2.8, z = { 0, 2, -2, 0 } },
		{ count = 5, gap = 2.8, size = 3.8, amp = 2, period = 2.6, z = { -2, 0, 2, 0, -2 } },
		{ count = 4, gap = 3.5, size = 4.5, amp = 3, period = 3.2, z = { 2, -2, 2, -2 } },
		{ count = 4, gap = 4, size = 4, amp = 2, period = 2.2, z = { 0, -2.5, 0, 2.5 } },
		{ count = 4, gap = 3.5, size = 4, amp = 3, period = 3, z = { -2, -2, 2, 2 } },
		{ count = 3, gap = 4.5, size = 5.5, amp = 3.5, period = 3.4, z = { 0, 3, -3 } },
	})[layout]
	local parts = {}
	local x = L.gap
	for i = 1, L.count do
		local motion = { kind = "slide", axis = "y", amp = L.amp, period = L.period, phase = (i - 1) * 0.5 }
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

-- Narrow goo belts that push you sideways off the edge: walk into the push, and jump the gaps.
BUILD.GooConveyor = function(layout)
	local L = ({
		{ length = 7, width = 5, gap = 2.5, belts = { { 0, 0, 10 }, { 0, 0, -10 }, { 0, 0, 10 } } },
		{ length = 5.5, width = 4.5, gap = 2.5, belts = { { 0, 0, -11 }, { 0, 0, 11 }, { 0, 0, -11 }, { 0, 0, 11 } } },
		{ length = 8, width = 5, gap = 3, belts = { { 0, 0, 10 }, { -6, 0, 6 }, { 0, 0, -10 } } },
		{ length = 9, width = 5.5, gap = 3, belts = { { 0, 0, 8 }, { 0, 0, -8 } } },
		{ length = 7, width = 4, gap = 2.5, belts = { { -5, 0, 9 }, { 0, 0, -9 }, { -5, 0, 9 } } },
		{ length = 12, width = 6, gap = 3, belts = { { 0, 0, 9 }, { 0, 0, -9 } } },
	})[layout]
	local parts = {}
	local x = L.gap
	for _, belt in L.belts do
		-- Orange pushes right, blue pushes left.
		local tone = if belt[3] >= 0 then 1 else 2
		table.insert(parts, slab(x + L.length / 2, 0, 0, L.length, L.width, "belt", { conveyor = belt, tone = tone }))
		x += L.length + L.gap
	end
	return { length = x, rise = 0, parts = parts }
end

-- Tiles that melt right after you land: keep hopping along the route, never stop.
BUILD.MeltingTiles = function(layout)
	local L = ({
		{ delay = 0.5, route = { 2, 1, 2, 3, 2 }, holes = { "2:2", "4:2" } },
		{ delay = 0.45, route = { 1, 1, 2, 3, 3 }, holes = { "1:2", "2:2", "3:1", "3:3", "4:2", "5:2" } },
		{ delay = 0.4, route = { 2, 3, 3, 2, 1 }, holes = { "2:1", "2:2", "3:2", "4:3", "5:2" } },
		{ delay = 0.5, route = { 3, 2, 1, 2, 3 }, holes = { "1:2", "3:2", "5:2", "2:3", "4:1" } },
		{ delay = 0.35, route = { 2, 2, 2, 2, 2 }, holes = {} },
		{ delay = 0.4, route = { 1, 2, 3, 2, 1 }, holes = { "1:2", "1:3", "3:1", "3:2", "5:2", "5:3" } },
	})[layout]
	local tile, gap = 3.5, 2.5
	local pitch = tile + gap
	local hole = {}
	for _, key in L.holes do
		hole[key] = true
	end
	local parts = {}
	for col, routeLane in L.route do
		local x = gap + (col - 1) * pitch + tile / 2
		for lane = 1, 3 do
			if not hole[`{col}:{lane}`] then
				local motion = { kind = "melt", delay = L.delay, away = 2.5 }
				local part = slab(x, 0, (lane - 2) * pitch, tile, tile, "tile", { motion = motion, tone = lane })
				part.step = lane == routeLane
				table.insert(parts, part)
			end
		end
	end
	return { length = gap + #L.route * pitch, rise = 0, parts = parts }
end

-- A round platform swept by spinning goo bars: jump them as they come round.
BUILD.Spinner = function(layout)
	-- spin: the disc's own turn (0 = still); bars: { height of the bar's centre, period, length }
	local L = ({
		{ spin = 0, bars = { { 1.1, 3.4, 18 } } },
		{ spin = 0, bars = { { 1.1, 3, 18 }, { 1.1, -4.6, 10 } } },
		{ spin = 7, bars = { { 1.1, -3.6, 18 } } },
		{ spin = 0, bars = { { 1.1, 2.6, 18 }, { 2.4, -3.8, 18 } } },
		{ spin = -8, bars = { { 1.1, 3.2, 18 }, { 1.1, 3.2, 18 } } },
		{ spin = 6, bars = { { 1.1, -2.8, 18 }, { 1.1, 4.4, 10 } } },
	})[layout]
	local gap, size = 2, 20
	local cx = gap + size / 2
	local disc = slab(cx, 0, 0, size, size, "jelly", { shape = "disc", tone = 2 })
	if L.spin ~= 0 then
		disc.motion = { kind = "spin", period = L.spin }
	end
	local parts = { disc }
	for i, b in L.bars do
		table.insert(
			parts,
			prop({ b[3], 1.2, 1.2 }, { cx, b[1], 0 }, "bar", {
				motion = { kind = "spin", period = b[2], phase = (i - 1) * 0.25 },
			})
		)
	end
	table.insert(parts, prop({ 1.6, 3.4, 1.6 }, { cx, 1.7, 0 }, "post"))
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
ObbyCourse.GUST = 14 -- sideways push of a wind gust (studs / s): stronger than you can lean into on a narrow bridge

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

-- Narrow goo terraces stepping down, swept by rolling blobs: time each drop between them.
BUILD.GooCascade = function(layout)
	local L = ({
		{ n = 4, len = 5, width = 6, drop = 2, gap = 3, blobs = { 2, 3 }, period = 2.2 },
		{ n = 5, len = 4, width = 5, drop = 1.5, gap = 2.5, blobs = { 1, 3, 5 }, period = 2 },
		{ n = 3, len = 7, width = 6, drop = 3, gap = 3.5, blobs = { 1, 2, 3 }, period = 2.6 },
		{ n = 4, len = 5, width = 5, drop = 2.5, gap = 3, blobs = { 2, 4 }, period = 1.8 },
		{ n = 4, len = 4.5, width = 6, drop = 2, gap = 3.5, blobs = { 1, 2, 3, 4 }, period = 2.4 },
		{ n = 4, len = 5.5, width = 5, drop = 1.5, gap = 2.5, blobs = { 1, 2, 3, 4 }, period = 2 },
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
		table.insert(parts, slab(cx, top, 0, L.len, L.width, "goo", { tone = i % 2 + 1 }))
		if blob[i] then
			-- Rolls from edge to edge of its terrace.
			local motion = { kind = "slide", axis = "z", amp = L.width / 2, period = L.period, phase = i * 0.3 }
			table.insert(parts, prop({ 3, 3, 3 }, { cx, top + 1.5, 0 }, "blob", { shape = "ball", motion = motion }))
		end
		x += L.len + L.gap
	end
	return { length = x, rise = -L.n * L.drop, parts = parts }
end

-- A see-through goo pipe with wide holes and a low roof: the roof cuts your jump short, so aim each hop.
BUILD.GooPipe = function(layout)
	-- roof: studs from the floor to the roof; holes: the gap before each floor, then the gap to the next pad
	local L = ({
		{ roof = 11, floors = { 4, 3, 3, 4 }, holes = { 2, 3.5, 3.5, 3.5, 2 }, z = { 0, -1.5, 1.5, 0 } },
		{
			roof = 10,
			floors = { 3, 3, 3, 3, 3 },
			holes = { 2, 3, 3, 3, 3, 2 },
			z = { -1.5, 1.5, -1.5, 1.5, 0 },
		},
		{ roof = 12, floors = { 5, 3, 3, 4 }, holes = { 2, 4, 4, 4, 2 }, z = { 0, 1.5, -1.5, 0 } },
		{
			roof = 10,
			floors = { 3, 2.5, 2.5, 2.5, 3 },
			holes = { 2, 3.5, 3.5, 3.5, 3.5, 2 },
			z = { 1.5, -1.5, 1.5, -1.5, 0 },
		},
		{ roof = 11, floors = { 4, 3, 3, 3, 4 }, holes = { 2, 4, 3, 4, 3, 2 }, z = { 0, 0, 0, 0, 0 } },
		{ roof = 13, floors = { 3, 3, 3, 3 }, holes = { 2, 4.5, 4.5, 4.5, 2 }, z = { -1.5, 1.5, -1.5, 1.5 } },
	})[layout]
	local parts = {}
	local x = 0
	for i, len in L.floors do
		x += L.holes[i]
		table.insert(parts, slab(x + len / 2, 0, L.z[i], len, 4, "goo", { tone = 2 }))
		x += len
	end
	x += L.holes[#L.holes]
	-- Walls and a roof the whole way along.
	local inner = 8
	local height = L.roof + 1
	table.insert(parts, prop({ x, height, 1 }, { x / 2, height / 2 - 1, -inner / 2 - 0.5 }, "pipe"))
	table.insert(parts, prop({ x, height, 1 }, { x / 2, height / 2 - 1, inner / 2 + 0.5 }, "pipe"))
	table.insert(parts, prop({ x, 1, inner + 2 }, { x / 2, L.roof + 0.5, 0 }, "pipe"))
	return { length = x, rise = 0, parts = parts }
end

-- Climbable jelly ladders between small ledges, with a jump across between climbs: the course climbs.
BUILD.StickyLadder = function(layout)
	-- { "truss", height, z } climbs; { "ledge", length, z, gap before } stands (gap 0 = right against it)
	local L = ({
		{
			row("truss", 6, 0),
			row("ledge", 3, 0, 0),
			row("ledge", 3, 3, 3),
			row("truss", 6, 3),
			row("ledge", 3, 3, 0),
			row("ledge", 4, 0, 3),
		},
		{
			row("truss", 4, 0),
			row("ledge", 3, 0, 0),
			row("ledge", 3, -3, 3.5),
			row("truss", 4, -3),
			row("ledge", 3, -3, 0),
			row("ledge", 3, 3, 3),
			row("truss", 4, 3),
			row("ledge", 4, 0, 0),
		},
		{
			row("truss", 8, 0),
			row("ledge", 3, 0, 0),
			row("ledge", 3, 3, 4),
			row("ledge", 3, -2, 3),
			row("truss", 6, -2),
			row("ledge", 4, 0, 0),
		},
		{
			row("truss", 5, -2),
			row("ledge", 3, -2, 0),
			row("ledge", 3, 2, 3),
			row("truss", 5, 2),
			row("ledge", 3, 2, 0),
			row("ledge", 3, -2, 3.5),
			row("truss", 4, -2),
			row("ledge", 4, 0, 0),
		},
		{
			row("truss", 4, 0),
			row("ledge", 3, 0, 0),
			row("ledge", 2.5, 0, 4),
			row("ledge", 2.5, 2.5, 3.5),
			row("truss", 8, 2.5),
			row("ledge", 4, 0, 0),
		},
		{
			row("truss", 10, 0),
			row("ledge", 3, 0, 0),
			row("ledge", 3, -3, 3),
			row("ledge", 3, 3, 3),
			row("ledge", 4, 0, 3),
		},
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
			x += it[4]
			table.insert(parts, slab(x + n / 2, top, z, n, 3, "jelly", { tone = i % 3 + 1 }))
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

-- Bubbles in an arc up and down that pop just after you land: climb them without stopping.
BUILD.PoppingBubbles = function(layout)
	local L = ({
		{ gap = 3, size = 3.5, delay = 0.6, z = { 0, 2.5, -2.5, 2.5, 0 }, top = { 1, 3, 5, 3, 1 } },
		{ gap = 3, size = 4, delay = 0.55, z = { -2.5, 2.5, -2.5, 2.5 }, top = { 1.5, 3.5, 5.5, 3 } },
		{ gap = 2.5, size = 3, delay = 0.5, z = { 0, 2, -2, 2, -2, 0 }, top = { 1, 2.5, 4, 5.5, 4, 2 } },
		{ gap = 3.5, size = 3.5, delay = 0.5, z = { 3, -3, 3, -3 }, top = { 1, 3, 5, 3 } },
		{ gap = 3.5, size = 4.5, delay = 0.45, z = { 0, -2, 2 }, top = { 2, 4.5, 2 } },
		{ gap = 3, size = 3.5, delay = 0.55, z = { 2, -2, 2, -2, 0 }, top = { 1, 3, 5, 3, 1 } },
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

-- Narrow planks that tip together like seesaws: the ends only meet when the planks are level, so jump then.
BUILD.SlimeSeesaw = function(layout)
	local L = ({
		{ count = 3, len = 8, width = 3, gap = 2.5, amp = 22, period = 3 },
		{ count = 2, len = 13, width = 3, gap = 3, amp = 18, period = 3.4 },
		{ count = 3, len = 8, width = 2.5, gap = 2.5, amp = 25, period = 2.6 },
		{ count = 3, len = 7, width = 3, gap = 3, amp = 28, period = 2.4 },
		{ count = 3, len = 8, width = 3, gap = 2.5, amp = 20, period = 3.2 },
		{ count = 4, len = 5.5, width = 3, gap = 2.5, amp = 30, period = 2.6 },
	})[layout]
	local parts = {}
	local x = L.gap
	for i = 1, L.count do
		local cx = x + L.len / 2
		-- All in step: where two planks meet, one end is up while the other is down.
		local motion = { kind = "rock", amp = L.amp, period = L.period, phase = 0 }
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

-- Narrow walkways split by gaps, each with a goo gate that drops and lifts: dash through while it is up.
BUILD.GooGates = function(layout)
	local L = ({
		{ slabs = { 8, 8, 8 }, width = 4, gap = 2.5, period = 2.4, shift = 0.33 },
		{ slabs = { 10, 10 }, width = 3.5, gap = 3, period = 2, shift = 0.5 },
		{ slabs = { 5.5, 5.5, 5.5, 5.5 }, width = 4, gap = 2.5, period = 2.6, shift = 0.25 },
		{ slabs = { 7, 7, 7 }, width = 3, gap = 3, period = 2.2, shift = 0.5 },
		{ slabs = { 12, 12 }, width = 4, gap = 3, period = 1.8, shift = 0.5 },
		{ slabs = { 8, 8, 8 }, width = 3.5, gap = 2.5, period = 3, shift = 0 },
	})[layout]
	local parts = {}
	local x = L.gap
	for i, len in L.slabs do
		local cx = x + len / 2
		table.insert(parts, slab(cx, 0, 0, len, L.width, "goo", { tone = 2 }))
		-- Rests half shut (bottom 4 studs up); its bottom sweeps from the floor to 8 studs up.
		local motion = { kind = "slide", axis = "y", amp = 4, period = L.period, phase = (i - 1) * L.shift }
		table.insert(parts, prop({ 1.2, 8, L.width + 1 }, { cx, 8, 0 }, "gate", { motion = motion }))
		x += len + L.gap
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

-- Long planks spinning flat round their middle: jump to the next one when the two point along the course.
BUILD.Turntables = function(layout)
	-- flip: every other plank turns the other way (their ends meet side by side; otherwise they cross)
	local L = ({
		{ count = 3, len = 8, width = 3, gap = 2.5, period = 6, flip = true },
		{ count = 3, len = 8, width = 2.5, gap = 2.5, period = 5, flip = false },
		{ count = 2, len = 12, width = 3, gap = 3, period = 7, flip = true },
		{ count = 3, len = 8, width = 3, gap = 3, period = 4.5, flip = true },
		{ count = 3, len = 7.5, width = 2.5, gap = 2.5, period = -5.5, flip = false },
		{ count = 4, len = 6, width = 3, gap = 2.2, period = 4, flip = true },
	})[layout]
	local parts = {}
	local x = L.gap
	for i = 1, L.count do
		local cx = x + L.len / 2
		local period = if L.flip and i % 2 == 0 then -L.period else L.period
		local motion = { kind = "spin", period = period }
		table.insert(parts, slab(cx, 0, 0, L.len, L.width, "jelly", { motion = motion, tone = i % 3 + 1 }))
		table.insert(parts, prop({ 1.6, 4, 1.6 }, { cx, -3, 0 }, "post"))
		x += L.len + L.gap
	end
	return { length = x, rise = 0, parts = parts }
end

-- Glowing tiles that light up one after another along a winding trail: follow the light, don't run ahead.
BUILD.GlowTrail = function(layout)
	-- moves from the first tile: "f" one column forward, "l" / "r" one lane left / right; lag: seconds per tile
	local L = ({
		{ period = 6, duty = 0.35, lag = 0.35, lane = 2, moves = "frfflfflf" },
		{ period = 6, duty = 0.35, lag = 0.35, lane = 1, moves = "ffrrfflffr" },
		{ period = 5, duty = 0.4, lag = 0.3, lane = 3, moves = "fflfflff" },
		{ period = 7, duty = 0.3, lag = 0.4, lane = 2, moves = "flfrrflff" },
		{ period = 6, duty = 0.35, lag = 0.35, lane = 2, moves = "fffffff" },
		{ period = 5.5, duty = 0.35, lag = 0.3, lane = 1, moves = "frfrflflf" },
	})[layout]
	local tile, pitch = 3.5, 4
	local col, lane = 1, L.lane
	local cells = { { col, lane } }
	for i = 1, #L.moves do
		local m = string.sub(L.moves, i, i)
		if m == "f" then
			col += 1
		elseif m == "l" then
			lane -= 1
		else
			lane += 1
		end
		table.insert(cells, { col, lane })
	end
	local parts = {}
	for i, cell in cells do
		local x = (pitch - tile) + (cell[1] - 1) * pitch + tile / 2
		local motion = { kind = "flip", period = L.period, duty = L.duty, phase = -(i - 1) * L.lag / L.period % 1 }
		table.insert(
			parts,
			slab(x, 0, (cell[2] - 2) * pitch, tile, tile, "glow", { motion = motion, tone = i % 3 + 1 })
		)
	end
	return { length = (pitch - tile) + col * pitch, rise = 0, parts = parts }
end

-- A wall splits the course: safe steps on the left, a fast tightrope with long jumps on the right.
BUILD.TwoWays = function(layout)
	-- safe: pad size, gap, pad tops; fast: beams, gap between them, beam width
	local L = ({
		{ size = 4, gap = 2.5, tops = { 0, 1, 2, 1, 0 }, beams = 3, fastGap = 4.5, width = 1.2 },
		{ size = 4.5, gap = 2.5, tops = { 0, 1.5, 3, 1.5 }, beams = 3, fastGap = 4, width = 1 },
		{ size = 4, gap = 2, tops = { 1, 2, 3, 2, 1 }, beams = 3, fastGap = 5, width = 1.2 },
		{ size = 3.5, gap = 2.5, tops = { 0, 1.5, 3, 1.5, 0 }, beams = 2, fastGap = 5, width = 0.9 },
		{ size = 4, gap = 2.5, tops = { 0, 1, 1.5, 1, 0 }, beams = 4, fastGap = 4, width = 1.2 },
		{ size = 5, gap = 3, tops = { 1, 2, 3, 2 }, beams = 3, fastGap = 5.5, width = 1.5 },
	})[layout]
	local side = 3.5
	local parts = {}
	local x = L.gap
	for i, t in L.tops do
		table.insert(parts, slab(x + L.size / 2, t, -side, L.size, L.size, "jelly", { tone = i % 3 + 1 }))
		x += L.size + L.gap
	end
	local length = x
	local beam = (length - (L.beams + 1) * L.fastGap) / L.beams
	local bx = L.fastGap
	for i = 1, L.beams do
		local part = slab(bx + beam / 2, 0, side, beam, L.width, "rope", { tone = i % 3 + 1 })
		part.step = nil -- the fast way; the safe steps are the reference path
		table.insert(parts, part)
		bx += beam + L.fastGap
	end
	-- See-through, so you can size up the other way before you pick.
	table.insert(parts, prop({ length - 2, 9, 1 }, { length / 2, 3.5, 0 }, "pipe"))
	return { length = length, rise = 0, parts = parts }
end

-- Wooden logs that roll under your feet and carry you sideways: walk into the roll to stay on.
BUILD.RollingLogs = function(layout)
	local L = ({
		{ count = 3, len = 8, d = 3.5, gap = 2.5, period = 2.4, flip = true, z = { 0, 0, 0 } },
		{ count = 2, len = 13, d = 4, gap = 3, period = 2.6, flip = true, z = { 0, 0 } },
		{ count = 3, len = 8, d = 3, gap = 2.5, period = 2, flip = true, z = { -1.5, 1.5, -1.5 } },
		{ count = 4, len = 5.5, d = 3.5, gap = 2.5, period = 2.2, flip = true, z = { 0, 0, 0, 0 } },
		{ count = 3, len = 8.5, d = 3, gap = 2.5, period = -1.8, flip = false, z = { 0, 0, 0 } },
		{ count = 3, len = 8, d = 3.5, gap = 3, period = 1.8, flip = true, z = { 1, -1, 1 } },
	})[layout]
	local parts = {}
	local x = L.gap
	for i = 1, L.count do
		local period = if L.flip and i % 2 == 0 then -L.period else L.period
		table.insert(
			parts,
			prop({ L.len, L.d, L.d }, { x + L.len / 2, -L.d / 2, L.z[i] }, "log", {
				shape = "log",
				step = true,
				motion = { kind = "roll", period = period },
				tone = i % 2 + 1,
			})
		)
		x += L.len + L.gap
	end
	return { length = x, rise = 0, parts = parts }
end

-- A tall goo wave sweeps up and down a narrow path: duck into a side bay when it comes your way.
BUILD.GooWave = function(layout)
	local L = ({
		{ segs = { 8, 8, 8 }, gap = 2.5, period = 6 },
		{ segs = { 12, 12 }, gap = 3, period = 5.5 },
		{ segs = { 6, 6, 6, 6 }, gap = 2, period = 6.5 },
		{ segs = { 8, 8, 8 }, gap = 2.5, period = 5 },
		{ segs = { 10, 10 }, gap = 3, period = 4.6 },
		{ segs = { 7, 7, 7 }, gap = 3, period = 5.4 },
	})[layout]
	local width, bay = 3, 4
	local parts = {}
	local x = L.gap
	for i, len in L.segs do
		local cx = x + len / 2
		table.insert(parts, slab(cx, 0, 0, len, width, "goo", { tone = 1 }))
		local sideZ = (if i % 2 == 1 then 1 else -1) * (width + bay) / 2
		local bayPart = slab(cx, 0, sideZ, bay, bay, "jelly", { tone = 2 })
		bayPart.step = nil
		table.insert(parts, bayPart)
		x += len + L.gap
	end
	local length = x
	local motion = { kind = "slide", axis = "x", amp = length / 2 - 3, period = L.period }
	table.insert(parts, prop({ 2, 7, width + 0.6 }, { length / 2, 3.7, 0 }, "wave", { motion = motion }))
	return { length = length, rise = 0, parts = parts }
end

-- Goo punchers shoot out across a narrow path on a beat: cross between the punches or get knocked off.
BUILD.GooPunchers = function(layout)
	-- at: puncher positions along the section; side: which side it punches from (1 = right)
	local L = ({
		{ segs = { 14, 14 }, gap = 2.5, at = { 6, 12, 20, 26 }, side = { 1, -1, 1, -1 }, period = 2.4, shift = 0.25 },
		{ segs = { 8.5, 8.5, 8.5 }, gap = 2.5, at = { 7, 18, 29 }, side = { 1, -1, 1 }, period = 2, shift = 0.33 },
		{ segs = { 30 }, gap = 2.5, at = { 6, 11, 16, 21, 26 }, side = { 1, -1, 1, -1, 1 }, period = 2.6, shift = 0.2 },
		{ segs = { 13, 13 }, gap = 3, at = { 7, 10, 23, 26 }, side = { 1, -1, -1, 1 }, period = 2.2, shift = 0.5 },
		{
			segs = { 8.5, 8.5, 8.5 },
			gap = 2.5,
			at = { 5, 9, 16, 20, 27, 31 },
			side = { 1, -1, 1, -1, 1, -1 },
			period = 2.8,
			shift = 0.17,
		},
		{ segs = { 30 }, gap = 2.5, at = { 8, 16, 24 }, side = { 1, 1, 1 }, period = 1.8, shift = 0.33 },
	})[layout]
	local width, reach = 3, 4
	local parts = {}
	local x = L.gap
	for _, len in L.segs do
		table.insert(parts, slab(x + len / 2, 0, 0, len, width, "goo", { tone = 2 }))
		x += len + L.gap
	end
	for i, at in L.at do
		local s = L.side[i]
		-- Rests just off the path's edge; a punch reaches across the whole path.
		local motion = { kind = "punch", axis = "z", amp = -s * reach, period = L.period, phase = (i - 1) * L.shift }
		table.insert(parts, prop({ 2.5, 3, 4 }, { at, 1.5, s * (width / 2 + 2.2) }, "puncher", { motion = motion }))
	end
	return { length = x, rise = 0, parts = parts }
end

-- A narrow bridge crossed by gusts of wind that blow on and off: wait out each gust in the calm gaps.
BUILD.GustyBridge = function(layout)
	-- gusts: { from, to, direction (1 = blows right) } along the section
	local L = ({
		{ segs = { 32 }, gap = 2, width = 3, gusts = { { 4, 10, 1 }, { 14, 20, -1 }, { 24, 30, 1 } }, period = 4 },
		{ segs = { 14, 14 }, gap = 2.5, width = 2.5, gusts = { { 4, 12, -1 }, { 20, 28, 1 } }, period = 3.6 },
		{
			segs = { 32 },
			gap = 2,
			width = 2.5,
			gusts = { { 3, 9, 1 }, { 12, 18, 1 }, { 21, 27, 1 }, { 30, 34, -1 } },
			period = 3.2,
		},
		{
			segs = { 9, 9, 9 },
			gap = 2,
			width = 3,
			gusts = { { 3, 10, 1 }, { 13, 20, -1 }, { 24, 31, 1 } },
			period = 4.4,
		},
		{ segs = { 32 }, gap = 2, width = 2, gusts = { { 5, 15, -1 }, { 20, 30, 1 } }, period = 5 },
		{
			segs = { 32 },
			gap = 2,
			width = 3,
			gusts = { { 4, 9, 1 }, { 9, 14, -1 }, { 18, 23, 1 }, { 23, 28, -1 } },
			period = 3,
		},
	})[layout]
	local parts = {}
	local x = L.gap
	for _, len in L.segs do
		table.insert(parts, slab(x + len / 2, 0, 0, len, L.width, "rope", { tone = 3 }))
		x += len + L.gap
	end
	for i, g in L.gusts do
		local motion = {
			kind = "gust",
			axis = "z",
			power = g[3] * ObbyCourse.GUST,
			period = L.period,
			duty = 0.45,
			phase = (i - 1) * 0.5,
		}
		local len = g[2] - g[1]
		table.insert(
			parts,
			prop({ len, 9, 14 }, { (g[1] + g[2]) / 2, 3.5, 0 }, "gust", { motion = motion, ghost = true })
		)
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
