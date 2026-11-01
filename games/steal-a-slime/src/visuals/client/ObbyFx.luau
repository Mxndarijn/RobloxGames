--!strict
--[[
	ObbyFx (VisualsClient module, contract/obby-sections.md §4, §5, §8 and §10b)

	Plays the obby course's moving and per-player parts on this client. Every part of workspace.Obby.Course with a
	behaviour carries `ObbySpec` (JSON of its ObbyCourse.Part behaviour fields, course-local) and `ObbyBase` (its rest
	CFrame in world space); the Course model carries `ObbyFrame` (the course frame: X forward, Y up, Z right), which
	turns course-local vectors into world ones. Motions (`motion.kind`, ObbyCourse.Motion):
	  * slide   moves `amp` along `axis` and carries a player standing on it (surface velocity)
	  * spin    turns round its vertical axis and shoves what it hits (angular velocity)
	  * melt    the local player standing on it (`on = "land"`) or leaving it (`on = "leave"`): cracks and darkens over
	            `delay`, drops away for `away` s (-1: until the next reset); `spread` s after it is gone the tiles in
	            `next` (part ids) start melting too
	  * flip    solid in its `duty` share of the period, blinks just before it goes, see-through and not solid
	            otherwise; with `solid = true` only its glow blinks on and off and it stays solid
	  * shrink  its width and depth (a cylinder: its round face) breathe between full size and `min`
	  * bounce  the local player landing on it is thrown up at `power` plus `throw` (course-local); with `duty` it
	            only throws while `cycle < duty`, and its rim glows `warn` s before it goes
	  * lift    the local player inside the wind column rises at `power`; entering catches a fall; at `cap` studs
	            above the column's bottom they hover; with `duty` it runs only while `cycle < duty` and fades 0.8 s
	            before it stops
	  * swing   a pendulum swinging across the course, `arm` studs below its pivot (shoves what it hits)
	  * rock    a seesaw plank tipping forward and back round its centre
	  * roll    a log rolling round its own length; its turn carries a player standing on it sideways
	  * punch   shoots out along its axis, holds, slides back and rests; always a hazard (touching it resets you)
	  * gust    a see-through wind zone that blows on and off; while on, the local player inside is pushed
	  * path    moves through course-local `points` (hold `hold` s at each), ping-pong or `loop` (`jump`: the way back
	            to the first point is instant), `once` with a `start` clock; carries a rider; `spinRoll` rolls a ball
	  * sink    lowers `depth` studs at `speed` while the local player stands on it, rises back once they leave
	  * rise    a flood: rises at `speed` after `delay` on its `start` clock, up to `stop` studs
	  * drop    a collapsing piece: on its `start` clock it cracks 0.8 s before `at`, then falls away until the reset
	  * sweep   turns between -`amp` and +`amp` degrees round its vertical axis, `hold` s at each end
	  * turn    a belt whose conveyor runs one way while `cycle < duty` and the other way after; its chevrons flip
	  * pattern a crusher / puncher running a list of `beats` ({ at (s into the period), kind, amount }) per period
	Timing has one source (contract §11): every clocked motion's offset, turn, scale and on / off comes from
Kit.offsetAt / Kit.conveyorAt (src/shared/ObbySections/Kit, the functions tests/ObbyCheck samples), turned into the
world with ObbyFrame; the velocity a carrying part hands a rider is the difference of two Kit samples VEL_DT apart,
and the tells (blinks, glows, cracks) look ahead on the same Kit clock. A `start` part whose clock has not started
is asked at time nil, as the checks do. Only rock and roll (no Kit clock yet: the checks treat them as still) and
the player-driven melt, sink, bounce landings and lift columns are timed here.
Per-player parts (contract §5, the clocks and keys in ObbyClock): a `trigger` part starts its clock on the first
	touch; a `start` part plays on that clock and sits at rest until it starts; a `key` part is picked up on touch; a
	`gate` opens once the player holds its `need` keys. Hazards: the frame the local player's root or any limb is
	inside a `hazard` part (its box grown by HAZARD_PAD), ObbyFall.reset("hazard"). Every reset (ObbyFall.onReset)
	clears the clocks, keys, melted tiles and collapsed pieces and puts every part back at rest.
	Warnings are the part's own Color and Transparency (no extra parts). Decor parts parented under a part (its
	markers) move and fade with it. A part's `beat` snaps its period to the beat clock, and it pulses on the beat.
	It also turns the Goo Rings' swirls (the portal's and the ring home's: the "Mesh" swapped into a slot with
	Constants.GOO_SPIN, round its GOO_PIVOT's Z axis; the invisible slot itself stays put).
	Every change is local: each player collides with their own copy, so platforms move smoothly at frame rate.
	Parts farther than MAX_DISTANCE from the camera are skipped. Never fires remotes. Call `tick` once a frame.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Visuals = ReplicatedStorage:WaitForChild("Visuals")
local Constants = require(Shared:WaitForChild("Constants"))
local ObbyClock = require(script.Parent:WaitForChild("ObbyClock"))
local ObbyFall = require(script.Parent:WaitForChild("ObbyFall"))
local ObbyLook = require(Visuals:WaitForChild("ObbyLook"))
-- The one source of motion timing (contract §11): the checks sample the same functions.
local Kit = require(Shared:WaitForChild("ObbySections"):WaitForChild("Kit"))

local ObbyFx = {}

ObbyFx.MAX_DISTANCE = 260 -- studs from the camera
ObbyFx.FIND_EVERY = 1 -- seconds between looks for a new course
ObbyFx.FLIP_WARN = 0.5 -- seconds a flip tile blinks before it goes
ObbyFx.GONE_TRANSPARENCY = 0.85
ObbyFx.BOUNCE_COOLDOWN = 0.4 -- seconds before the same pad throws you again
ObbyFx.BOUNCE_WARN = 0.8 -- seconds a timed pad's rim glows before it throws (when its motion gives no `warn`)
ObbyFx.GUST_ON_TRANSPARENCY = 0.6
ObbyFx.GUST_OFF_TRANSPARENCY = 0.96
ObbyFx.GUST_WARN = 0.6 -- seconds a gust flickers before it starts blowing
ObbyFx.LIFT_FADE = 0.8 -- seconds a timed lift fades before it stops (contract §4)
ObbyFx.LIFT_HOVER_GAIN = 4 -- studs/s of upward speed per stud under a lift's cap (a soft spring to the hover height)
ObbyFx.MELT_DARKEN = 0.55 -- share of the way to black a melting tile darkens by the time it drops
ObbyFx.MELT_FADE = 0.35 -- share of the way to GONE a melting tile fades by the time it drops
ObbyFx.CRACK_SLOW = 0.35 -- seconds between crack ticks when the warning starts
ObbyFx.CRACK_FAST = 0.08 -- ... and just before it drops
ObbyFx.DROP_WARN = 0.8 -- seconds a collapsing piece cracks before it falls (contract §4)
ObbyFx.DROP_FALL = 0.8 -- seconds it takes to fall away and fade out
ObbyFx.DROP_DEPTH = 18 -- studs it falls in that time
ObbyFx.PUNCH_TELL = 0.4 -- seconds a puncher / pattern crusher glows before it shoots out
ObbyFx.TURN_WARN = 1 -- seconds a turning belt glows and ticks before it changes way (contract §4)
ObbyFx.GLOW = 0.55 -- share of the way to white a glowing tell goes
ObbyFx.BEAT_PULSE = 0.35 -- share of the way to white a beat part flashes on the beat
ObbyFx.BEAT_PULSE_SECONDS = 0.15
ObbyFx.BLINK_RATE = 8 -- blinks a second in a blinking tell
ObbyFx.GATE_FADE = 0.5 -- seconds an opened gate takes to fade out
ObbyFx.LOCK_FULL = Color3.fromRGB(255, 205, 60) -- a filled lock icon on a gate: the key's gold
ObbyFx.HAZARD_PAD = 0.5 -- studs a hazard's box grows by for the limb test (about half a limb's thickness)
ObbyFx.TOUCH_PAD = 0.6 -- studs for triggers
ObbyFx.KEY_PAD = 1.5 -- studs for keys (they float, so grabbing them is generous)
ObbyFx.TOUCH_REACH = 6 -- studs past a part's half diagonal before the limb test is skipped
ObbyFx.SOUND_RANGE = 40 -- studs from the root: parts farther off make no sound
ObbyFx.SOUND_GAP = 0.06 -- seconds between two plays of one sound
ObbyFx.VEL_DT = 0.02 -- seconds between the two Kit samples a carrying part's velocity is taken from
ObbyFx.LOOK_STEP = 0.05 -- seconds between the Kit samples a tell looks ahead with

-- Short, quiet built-in sounds (rbxasset://, nothing uploaded). The pitch makes one file do two jobs.
ObbyFx.SOUNDS = table.freeze({
	tick = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.2, pitch = 1 },
	go = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.3, pitch = 1.5 },
	chime = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.35, pitch = 2.2 },
	gate = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.3, pitch = 0.7 },
	crack = { id = "rbxasset://sounds/action_footsteps_plastic.mp3", volume = 0.2, pitch = 1.6 },
	drop = { id = "rbxasset://sounds/impact_water.mp3", volume = 0.15, pitch = 0.7 },
	boing = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.3, pitch = 0.8 },
	slam = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.3, pitch = 0.6 },
	splat = { id = "rbxasset://sounds/impact_water.mp3", volume = 0.3, pitch = 1.3 },
})

export type Controller = { tick: (camera: Camera?) -> (), stop: () -> () }

type Spec = { [string]: any }

type Decor = { part: BasePart, rel: CFrame, transparency: number, color: Color3 }

-- One part of the course with a behaviour, its rest state and the local player's state for it.
type Mover = {
	part: BasePart,
	id: string,
	spec: Spec,
	motion: Spec,
	kind: string, -- "" when it has no motion
	kit: Kit.Part, -- the Part-shaped table Kit's clocks read (motion, beat, conveyor)
	glowKit: Kit.Part?, -- flip with `solid`: the same motion without `solid`, for when its glow is lit
	frame: CFrame, -- the course frame's rotation: course-local -> world
	base: CFrame,
	size: Vector3,
	transparency: number,
	color: Color3,
	collide: boolean,
	vel0: Vector3,
	period: number, -- Kit.periodOf (always positive)
	sign: number, -- -1 when the data's period is negative (rock / roll the other way)
	phase: number,
	start: string?,
	beat: boolean,
	axis: Vector3, -- gust: world direction it blows
	throw: Vector3?, -- bounce: world launch velocity on top of `power`
	cylinder: boolean,
	decor: { Decor },
	lights: { Instance }, -- emitters, sparkles and lights a picked-up key turns off
	-- per player, cleared on every reset
	meltAt: number?, -- melt: local clock time it starts (or started) melting
	stood: boolean, -- melt "leave": the player has stood on it
	spreadDone: boolean,
	nextCrack: number,
	readyAt: number, -- bounce: local clock time it may throw again
	offset: number, -- sink: studs it has gone down
	inside: boolean, -- lift: the root was inside last frame
	warned: boolean, -- turn: the tick for the coming change has played
	wasOut: boolean, -- pattern: it was out of its rest position last frame (a slam sounds as it leaves)
	fell: boolean, -- drop: the fall sound has played
	droppedAt: number, -- drop: local clock time it started falling
	rolled: CFrame, -- path with spinRoll: the ball's turn so far
	lastPos: Vector3?, -- path with spinRoll: where it was last frame
	taken: boolean, -- key
	openedAt: number?, -- gate
	fade: number, -- 0 at rest .. 1 hidden: what its decor shows
	live: boolean, -- hazard: dangerous this frame
	paint: Color3, -- the colour this frame
}

-- The local player this frame.
type Local = { standingOn: BasePart?, root: BasePart?, humanoid: Humanoid?, limbs: { BasePart } }

-- What one part's motion sees this frame.
type Now = {
	t: number?, -- seconds on its clock; nil = its `start` clock has not started (Kit puts it at rest)
	cycle: number, -- 0..1 of its period (0 while not started)
	clock: number,
	dt: number,
	me: Local,
	near: boolean, -- the local player is close enough to hear it
}

local TAU = 2 * math.pi
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local UP = Vector3.yAxis

---------------------------------------------------------------------------
-- Sounds
---------------------------------------------------------------------------

local sounds: { [string]: Sound } = {}
local lastPlayed: { [string]: number } = {}

-- Plays one of ObbyFx.SOUNDS once (not positional, in the SFX group so the mute setting holds).
function ObbyFx.sound(name: string)
	local def = (ObbyFx.SOUNDS :: any)[name]
	if not def then
		return
	end
	local now = os.clock()
	if now - (lastPlayed[name] or -math.huge) < ObbyFx.SOUND_GAP then
		return
	end
	lastPlayed[name] = now
	local s = sounds[name]
	if not s or s.Parent == nil then
		local created = Instance.new("Sound")
		created.Name = "ObbyFx_" .. name
		created.SoundId = def.id
		created.Volume = def.volume
		created.PlaybackSpeed = def.pitch
		local sfx = SoundService:FindFirstChild("SFX")
		created.SoundGroup = if sfx and sfx:IsA("SoundGroup") then sfx else nil
		created.Parent = SoundService
		sounds[name] = created
		s = created
	end
	s.TimePosition = 0
	s:Play()
end

local function hear(now: Now, name: string)
	if now.near then
		ObbyFx.sound(name)
	end
end

---------------------------------------------------------------------------
-- Reading the data
---------------------------------------------------------------------------

local function num(t: Spec?, key: string, default: number): number
	local v = t and t[key]
	return if type(v) == "number" and v == v then v else default
end

-- A course-local { x, y, z } as a world vector (nil for anything else).
local function worldVec(frame: CFrame, v: any): Vector3?
	if type(v) ~= "table" then
		return nil
	end
	local x, y, z = v[1], v[2], v[3]
	if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
		return nil
	end
	return frame:VectorToWorldSpace(Vector3.new(x, y, z))
end

-- A gust's push direction: along course x or z, as the checks push the walker; any other axis does not push.
local function gustAxis(frame: CFrame, axis: any): Vector3
	if axis == "x" then
		return frame.XVector
	elseif axis == "z" then
		return frame.ZVector
	end
	return Vector3.zero
end

-- A pattern's beats with named fields (Kit.patternAt reads { at, kind, amount }; positional ones are accepted too).
local function namedBeats(motion: Spec): { Kit.Beat }
	local out: { Kit.Beat } = {}
	if type(motion.beats) == "table" then
		for _, b in motion.beats do
			if type(b) == "table" then
				local at = b.at or b[1]
				local kind = b.kind or b[2]
				local amount = b.amount or b[3]
				if type(at) == "number" and type(kind) == "string" then
					table.insert(
						out,
						{ at = at, kind = kind, amount = if type(amount) == "number" then amount else nil }
					)
				end
			end
		end
	end
	return out
end

-- The Part-shaped table Kit's clocks read, from a part's ObbySpec (offsets come back course-local).
local function kitPart(spec: Spec, motion: Spec?): Kit.Part
	return {
		size = { 1, 1, 1 },
		pos = { 0, 0, 0 },
		look = "",
		motion = motion :: any,
		beat = if type(spec.beat) == "number" and spec.beat > 0 then spec.beat else nil,
		conveyor = if type(spec.conveyor) == "table" then spec.conveyor else nil,
	}
end

local function mover(part: BasePart, frame: CFrame): Mover?
	local raw = part:GetAttribute(Constants.OBBY_SPEC)
	local base = part:GetAttribute(Constants.OBBY_BASE)
	if type(raw) ~= "string" then
		return nil
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(decoded) ~= "table" then
		return nil
	end
	local spec: Spec = decoded
	local motion: Spec = if type(spec.motion) == "table" then spec.motion else {}
	local kind = if type(motion.kind) == "string" then motion.kind else ""
	local id = part:GetAttribute(Constants.OBBY_ID)
	local start = if type(spec.start) == "string" then spec.start else nil
	if kind == "pattern" then
		motion = table.clone(motion)
		motion.beats = namedBeats(motion)
	end
	local kit = kitPart(spec, if kind ~= "" then motion else nil)
	local glowKit: Kit.Part? = nil
	if kind == "flip" and motion.solid == true then
		local lit = table.clone(motion)
		lit.solid = nil
		glowKit = kitPart(spec, lit)
	end
	local axis = gustAxis(frame, motion.axis)
	if kind == "gust" and num(motion, "power", 0) < 0 then
		axis = -axis -- the axis points the way it blows
	end
	local restCf = if typeof(base) == "CFrame" then base else part.CFrame
	local decor: { Decor } = {}
	local lights: { Instance } = {}
	for _, d in part:GetDescendants() do
		if d:IsA("BasePart") and d.Parent == part then
			table.insert(decor, {
				part = d,
				rel = restCf:ToObjectSpace(d.CFrame),
				transparency = d.Transparency,
				color = d.Color,
			})
		elseif d:IsA("ParticleEmitter") or d:IsA("Sparkles") or d:IsA("Light") then
			table.insert(lights, d)
		end
	end
	return {
		part = part,
		id = if type(id) == "string" then id else part.Name,
		spec = spec,
		motion = motion,
		kind = kind,
		kit = kit,
		glowKit = glowKit,
		frame = frame,
		base = restCf,
		size = part.Size,
		transparency = part.Transparency,
		color = part.Color,
		collide = part.CanCollide,
		vel0 = part.AssemblyLinearVelocity,
		period = Kit.periodOf(kit),
		sign = if num(motion, "period", 1) < 0 then -1 else 1,
		phase = num(motion, "phase", 0),
		start = start,
		beat = type(spec.beat) == "number",
		axis = axis,
		throw = worldVec(frame, motion.throw),
		cylinder = part:IsA("Part") and (part :: Part).Shape == Enum.PartType.Cylinder,
		decor = decor,
		lights = lights,
		meltAt = nil,
		stood = false,
		spreadDone = false,
		nextCrack = 0,
		readyAt = 0,
		offset = 0,
		inside = false,
		warned = false,
		wasOut = false,
		fell = false,
		droppedAt = 0,
		rolled = CFrame.identity,
		lastPos = nil,
		taken = false,
		openedAt = nil,
		fade = 0,
		live = true,
		paint = part.Color,
	}
end

---------------------------------------------------------------------------
-- Setting a part's state
---------------------------------------------------------------------------

-- Moves the part (and its decor) to `cf` with surface velocity `vel`; `twist` turns the decor round the part.
local function place(m: Mover, cf: CFrame, vel: Vector3?, twist: CFrame?)
	local part = m.part
	part.CFrame = cf
	if vel then
		part.AssemblyLinearVelocity = vel
	end
	local at = if twist then cf * twist else cf
	for _, d in m.decor do
		d.part.CFrame = at * d.rel
	end
end

-- Solid or not (never solid when it was not at rest: hazards, ghosts) and how see-through; decor fades with it.
local function look(m: Mover, solid: boolean, transparency: number)
	local part = m.part
	local collide = m.collide and solid
	if part.CanCollide ~= collide then
		part.CanCollide = collide
	end
	if part.Transparency ~= transparency then
		part.Transparency = transparency
	end
	local span = 1 - m.transparency
	local fade = if span <= 0 then 0 else math.clamp((transparency - m.transparency) / span, 0, 1)
	if fade ~= m.fade then
		m.fade = fade
		for _, d in m.decor do
			d.part.Transparency = d.transparency + (1 - d.transparency) * fade
		end
	end
end

local function glow(m: Mover, k: number)
	m.paint = m.paint:Lerp(WHITE, ObbyFx.GLOW * math.clamp(k, 0, 1))
end

local function blinkOn(clock: number): boolean
	return math.floor(clock * ObbyFx.BLINK_RATE) % 2 == 0
end

-- The cracking tell (melt, drop): darker by `k` (0..1), crack ticks coming faster.
local function crack(m: Mover, now: Now, k: number)
	m.paint = m.color:Lerp(BLACK, ObbyFx.MELT_DARKEN * math.clamp(k, 0, 1))
	if now.clock >= m.nextCrack then
		m.nextCrack = now.clock + ObbyFx.CRACK_SLOW + (ObbyFx.CRACK_FAST - ObbyFx.CRACK_SLOW) * k
		hear(now, "crack")
	end
end

local function rest(m: Mover)
	local part = m.part
	place(m, m.base, m.vel0)
	part.AssemblyAngularVelocity = Vector3.zero
	if part.Size ~= m.size then
		part.Size = m.size
	end
	look(m, true, m.transparency)
	m.paint = m.color
	if part.Color ~= m.color then
		part.Color = m.color
	end
	m.rolled = CFrame.identity
	m.lastPos = nil
end

-- True when the point `p` is inside `part` grown by `pad` studs (balls and cylinders by their round shape).
local function inside(part: BasePart, p: Vector3, pad: number): boolean
	local q = part.CFrame:PointToObjectSpace(p)
	local size = part.Size
	if part:IsA("Part") then
		local shape = (part :: Part).Shape
		if shape == Enum.PartType.Ball then
			return q.Magnitude <= size.X / 2 + pad
		elseif shape == Enum.PartType.Cylinder then
			local r = math.min(size.Y, size.Z) / 2 + pad
			return math.abs(q.X) <= size.X / 2 + pad and q.Y * q.Y + q.Z * q.Z <= r * r
		end
	end
	return math.abs(q.X) <= size.X / 2 + pad and math.abs(q.Y) <= size.Y / 2 + pad and math.abs(q.Z) <= size.Z / 2 + pad
end

-- True when the root or any limb of the local player is inside `part` grown by `pad`.
local function touching(part: BasePart, me: Local, pad: number): boolean
	local root = me.root
	if not root then
		return false
	end
	local reach = part.Size.Magnitude / 2 + ObbyFx.TOUCH_REACH
	local d = part.Position - root.Position
	if d:Dot(d) > reach * reach then
		return false
	end
	if inside(part, root.Position, pad) then
		return true
	end
	for _, limb in me.limbs do
		if inside(part, limb.Position, pad) then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------
-- Motions: Kit's clocks (src/shared/ObbySections/Kit) put into the world
---------------------------------------------------------------------------

-- Kit's state of a part at `t` (nil = its `start` clock has not started): the world offset of its centre, its extra
-- turn round the vertical axis (degrees), its footprint scale and whether it is there / acting.
local function kitAt(m: Mover, t: number?): (Vector3, number, number, boolean)
	local dx, dy, dz, dyaw, scale, on = Kit.offsetAt(m.kit, t)
	return m.frame:VectorToWorldSpace(Vector3.new(dx, dy, dz)), dyaw, scale, on
end

local function onAt(m: Mover, t: number?): boolean
	local _, _, _, on = kitAt(m, t)
	return on
end

-- The world velocity of a part's centre at `t`: two Kit samples VEL_DT apart (zero while its clock has not started).
local function velAt(m: Mover, t: number?, off: Vector3): Vector3
	if t == nil then
		return Vector3.zero
	end
	local ahead = kitAt(m, t + ObbyFx.VEL_DT)
	return (ahead - off) / ObbyFx.VEL_DT
end

-- Radians a second a part turns round the vertical axis at `t`: two Kit samples VEL_DT apart.
local function turnRateAt(m: Mover, t: number?, dyaw: number): number
	if t == nil then
		return 0
	end
	local _, ahead = kitAt(m, t + ObbyFx.VEL_DT)
	return math.rad((ahead - dyaw + 180) % 360 - 180) / ObbyFx.VEL_DT
end

-- Seconds until `test(t + s)` holds, looking up to `within` s ahead in LOOK_STEP steps on the part's own clock; nil
-- when it does not within that, or the clock has not started. The tells use it, so they warn of what Kit will do.
local function lead(t: number?, within: number, test: (number) -> boolean): number?
	if t == nil then
		return nil
	end
	local s = ObbyFx.LOOK_STEP
	while s <= within + 1e-6 do
		if test(t + s) then
			return s
		end
		s += ObbyFx.LOOK_STEP
	end
	return nil
end

local function outAt(m: Mover, t: number): boolean
	local off = kitAt(m, t)
	return off.Magnitude > 0.01
end

-- Moves a part to Kit's offset now, handing a rider the offset's velocity on top of the part's belt (as the checks'
-- walker is carried: belt plus the floor's own move).
local function translate(m: Mover, now: Now): Vector3
	local off = kitAt(m, now.t)
	place(m, m.base + off, m.vel0 + velAt(m, now.t, off))
	return off
end

type Play = (m: Mover, now: Now) -> ()

local PLAY: { [string]: Play } = {}

function PLAY.slide(m, now)
	translate(m, now)
end

function PLAY.rise(m, now)
	translate(m, now)
end

-- spin and sweep: Kit's turn round the course's vertical axis through the part's centre.
function PLAY.spin(m, now)
	local off, dyaw = kitAt(m, now.t)
	local up = m.frame.YVector
	place(m, CFrame.new(m.base.Position + off) * CFrame.fromAxisAngle(up, math.rad(dyaw)) * m.base.Rotation)
	m.part.AssemblyAngularVelocity = up * turnRateAt(m, now.t, dyaw)
end

PLAY.sweep = PLAY.spin

function PLAY.swing(m, now)
	-- Kit gives the centre's offset round a pivot `arm` above the rest position, swinging across the course; the part
	-- turns with it round the course's forward axis, by the angle read back from that offset.
	local off = kitAt(m, now.t)
	local arm = num(m.motion, "arm", 0)
	local angle = 0
	if math.abs(arm) > 1e-3 then
		local o = m.frame:VectorToObjectSpace(off)
		angle = math.atan2(-o.Z / arm, 1 - o.Y / arm)
	end
	local turn = CFrame.fromAxisAngle(m.frame.XVector, angle)
	place(m, CFrame.new(m.base.Position + off) * turn * m.base.Rotation, m.vel0 + velAt(m, now.t, off))
end

function PLAY.rock(m, now)
	-- No Kit clock (the checks treat a seesaw as still): tips forward and back round its own Z axis.
	local amp = math.rad(num(m.motion, "amp", 0)) * m.sign
	place(m, m.base * CFrame.Angles(0, 0, amp * math.sin(TAU * now.cycle)))
	m.part.AssemblyAngularVelocity = if now.t == nil
		then Vector3.zero
		else m.base.ZVector * (amp * TAU / m.period * math.cos(TAU * now.cycle))
end

function PLAY.roll(m, now)
	-- No Kit clock (the checks treat a log as still): rolls round its own length (the log's X axis).
	place(m, m.base * CFrame.Angles(TAU * now.cycle * m.sign, 0, 0))
	m.part.AssemblyAngularVelocity = if now.t == nil then Vector3.zero else m.base.XVector * (TAU / m.period * m.sign)
end

-- punch and pattern: Kit's offset along the axis; glows PUNCH_TELL s before Kit shoots it out (a pattern also slams
-- each time it leaves its rest position).
function PLAY.punch(m, now)
	local out = translate(m, now).Magnitude > 0.01
	if m.kind == "pattern" then
		if out and not m.wasOut then
			hear(now, "slam")
		end
		m.wasOut = out
	end
	if not out then
		local left = lead(now.t, ObbyFx.PUNCH_TELL, function(t)
			return outAt(m, t)
		end)
		if left then
			glow(m, 1 - left / ObbyFx.PUNCH_TELL)
		end
	end
end

PLAY.pattern = PLAY.punch

function PLAY.gust(m, now)
	local part = m.part
	local on = onAt(m, now.t)
	local warn = not on and lead(now.t, ObbyFx.GUST_WARN, function(t)
		return onAt(m, t)
	end) ~= nil
	local transparency = ObbyFx.GUST_OFF_TRANSPARENCY
	if on then
		transparency = ObbyFx.GUST_ON_TRANSPARENCY
	elseif warn and blinkOn(now.clock) then
		transparency = (ObbyFx.GUST_ON_TRANSPARENCY + ObbyFx.GUST_OFF_TRANSPARENCY) / 2
	end
	look(m, true, transparency)
	local root = now.me.root
	if on and root and inside(part, root.Position, 0) then
		local power = math.abs(num(m.motion, "power", 0))
		local v = root.AssemblyLinearVelocity
		local along = v:Dot(m.axis)
		if m.axis ~= Vector3.zero and along < power then
			root.AssemblyLinearVelocity = v + m.axis * (power - along)
		end
	end
end

function PLAY.bounce(m, now)
	local motion = m.motion
	local on = onAt(m, now.t)
	if type(motion.duty) == "number" then
		if on then
			glow(m, 1)
		else
			local warn = num(motion, "warn", ObbyFx.BOUNCE_WARN)
			local left = lead(now.t, warn, function(t)
				return onAt(m, t)
			end)
			if left then
				glow(m, 1 - left / warn)
			end
		end
	end
	local me = now.me
	if on and me.standingOn == m.part and me.root and now.clock >= m.readyAt then
		m.readyAt = now.clock + ObbyFx.BOUNCE_COOLDOWN
		if me.humanoid then
			me.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
		-- straight up at `power`, plus the tilted pad's `throw` on top of the speed the player already had
		local v = me.root.AssemblyLinearVelocity
		me.root.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
			+ UP * num(motion, "power", 50)
			+ (m.throw or Vector3.zero)
		hear(now, "boing")
	end
end

function PLAY.lift(m, now)
	local motion = m.motion
	local on = onAt(m, now.t)
	local transparency = m.transparency
	if type(motion.duty) == "number" then
		if not on then
			transparency = ObbyFx.GUST_OFF_TRANSPARENCY
		else
			-- the swirl fades over the last LIFT_FADE s before Kit turns it off
			local left = lead(now.t, ObbyFx.LIFT_FADE, function(t)
				return not onAt(m, t)
			end)
			if left then
				local k = 1 - left / ObbyFx.LIFT_FADE
				transparency = m.transparency + (ObbyFx.GUST_OFF_TRANSPARENCY - m.transparency) * k
			end
		end
	end
	look(m, true, transparency)
	local root = now.me.root
	local isIn = on and root ~= nil and inside(m.part, root.Position, 0)
	if root and isIn then
		local power = num(motion, "power", 50)
		local v = root.AssemblyLinearVelocity
		local cap = motion.cap
		local vy = v.Y
		if type(cap) == "number" then
			local q = m.part.CFrame:PointToObjectSpace(root.Position)
			local height = q.Y + m.part.Size.Y / 2
			vy = math.clamp((cap - height) * ObbyFx.LIFT_HOVER_GAIN, -power, power)
			if not m.inside then
				vy = math.max(vy, 0) -- entering catches a fall
			end
		elseif vy < power or not m.inside then
			vy = power
		end
		root.AssemblyLinearVelocity = Vector3.new(v.X, vy, v.Z)
	end
	m.inside = isIn
end

function PLAY.flip(m, now)
	local glowKit = m.glowKit
	if glowKit then
		-- `solid`: only the glow blinks, on Kit's clock for the same motion without `solid`; the part stays solid
		local function lit(t: number?): boolean
			local _, _, _, _, _, on = Kit.offsetAt(glowKit, t)
			return on
		end
		local on = lit(now.t)
		local warning = on
			and blinkOn(now.clock)
			and lead(now.t, ObbyFx.FLIP_WARN, function(t)
				return not lit(t)
			end) ~= nil
		if on and not warning then
			glow(m, 1)
		end
		look(m, true, m.transparency)
		return
	end
	local on = onAt(m, now.t)
	local warning = on
		and blinkOn(now.clock)
		and lead(now.t, ObbyFx.FLIP_WARN, function(t)
			return not onAt(m, t)
		end) ~= nil
	if not on then
		look(m, false, ObbyFx.GONE_TRANSPARENCY)
		m.live = false
	elseif warning then
		look(m, true, 0.5)
	else
		look(m, true, m.transparency)
	end
end

function PLAY.shrink(m, now)
	local _, _, s = kitAt(m, now.t)
	local size = m.size
	-- A cylinder's round face is its Y and Z (a disc lies on its side); a block breathes in X and Z.
	m.part.Size = if m.cylinder
		then Vector3.new(size.X, size.Y * s, size.Z * s)
		else Vector3.new(size.X * s, size.Y, size.Z * s)
	place(m, m.base)
end

local byId: { [string]: Mover } = {}

function PLAY.melt(m, now)
	local motion = m.motion
	local delay = num(motion, "delay", 0.7)
	local away = num(motion, "away", 2.5)
	local standing = now.me.standingOn == m.part
	if m.meltAt == nil then
		if motion.on == "leave" then
			if standing then
				m.stood = true
			elseif m.stood then
				m.meltAt = now.clock
			end
		elseif standing then
			m.meltAt = now.clock
		end
	end
	local since = if m.meltAt then now.clock - m.meltAt else -1
	if since < 0 then
		look(m, true, m.transparency)
	elseif since < delay then
		local k = since / delay
		crack(m, now, k)
		look(m, true, m.transparency + (ObbyFx.GONE_TRANSPARENCY - m.transparency) * k * ObbyFx.MELT_FADE)
	elseif away < 0 or since < delay + away then
		if not m.spreadDone then
			m.spreadDone = true
			hear(now, "drop")
			-- the tiles after it start melting `spread` s after this one is gone
			local spread = num(motion, "spread", 0)
			if type(motion.next) == "table" then
				for _, id in motion.next do
					local n = if type(id) == "string" then byId[id] else nil
					if n and n.meltAt == nil then
						n.meltAt = now.clock + spread
					end
				end
			end
		end
		look(m, false, ObbyFx.GONE_TRANSPARENCY)
		m.live = false
	else
		m.meltAt = nil
		m.stood = false
		m.spreadDone = false
		look(m, true, m.transparency)
	end
end

function PLAY.path(m, now)
	local off = kitAt(m, now.t)
	local vel = velAt(m, now.t, off)
	local pos = m.base.Position + off
	if m.motion.spinRoll ~= true then
		place(m, CFrame.new(pos) * m.base.Rotation, m.vel0 + vel)
		return
	end
	-- A rolling ball turns by the way it went since last frame (a `jump` back to the first point is not rolled).
	local up = m.frame.YVector
	local radius = math.max(math.min(m.size.X, m.size.Y, m.size.Z) / 2, 0.1)
	local last = m.lastPos
	m.lastPos = pos
	if last then
		local step = pos - last
		local axis = up:Cross(step)
		if axis.Magnitude > 1e-4 and step.Magnitude < math.max(4 * radius, 4) then
			m.rolled = CFrame.fromAxisAngle(axis.Unit, step.Magnitude / radius) * m.rolled
		end
	end
	place(m, CFrame.new(pos) * m.rolled * m.base.Rotation, m.vel0 + vel)
	local spin = up:Cross(vel)
	m.part.AssemblyAngularVelocity = if spin.Magnitude > 1e-3
		then spin.Unit * (vel.Magnitude / radius)
		else Vector3.zero
end

function PLAY.sink(m, now)
	local depth = num(m.motion, "depth", 2)
	local speed = num(m.motion, "speed", 2)
	local down = now.me.standingOn == m.part
	local before = m.offset
	m.offset = math.clamp(before + (if down then speed else -speed) * now.dt, 0, depth)
	local rate = if now.dt > 0 then (m.offset - before) / now.dt else 0
	place(m, m.base - UP * m.offset, -UP * rate)
end

function PLAY.drop(m, now)
	if onAt(m, now.t) then
		-- cracks over the DROP_WARN s before Kit says it goes
		local left = lead(now.t, ObbyFx.DROP_WARN, function(t)
			return not onAt(m, t)
		end)
		if left == nil then
			rest(m)
			return
		end
		crack(m, now, 1 - left / ObbyFx.DROP_WARN)
		place(m, m.base)
		look(m, true, m.transparency)
		return
	end
	if not m.fell then
		m.fell = true
		m.droppedAt = now.clock
		hear(now, "drop")
	end
	local f = math.clamp((now.clock - m.droppedAt) / ObbyFx.DROP_FALL, 0, 1)
	m.paint = m.color:Lerp(BLACK, ObbyFx.MELT_DARKEN)
	place(m, m.base - UP * (ObbyFx.DROP_DEPTH * f * f), Vector3.zero)
	look(m, false, m.transparency + (1 - m.transparency) * f)
	m.live = false
end

local FLIPPED = CFrame.Angles(0, math.pi, 0)

-- True while a turning belt runs the way its data says (Kit.conveyorAt reverses it past its duty).
local function forwardAt(m: Mover, t: number?): boolean
	local c = m.kit.conveyor
	local belt = Kit.conveyorAt(m.kit, t)
	if not c or not belt then
		return true
	end
	return belt[1] * c[1] + belt[2] * c[2] + belt[3] * c[3] >= 0
end

function PLAY.turn(m, now)
	local forward = forwardAt(m, now.t)
	local warning = lead(now.t, ObbyFx.TURN_WARN, function(t)
		return forwardAt(m, t) ~= forward
	end) ~= nil
	if warning and not m.warned then
		hear(now, "tick")
	end
	m.warned = warning
	if warning then
		glow(m, if blinkOn(now.clock) then 1 else 0.4)
	end
	place(m, m.base, worldVec(m.frame, Kit.conveyorAt(m.kit, now.t)) or m.vel0, if forward then nil else FLIPPED)
end

---------------------------------------------------------------------------
-- The controller
---------------------------------------------------------------------------

-- The part under the local player's feet (a short ray down from the root), or nil.
local function floorUnder(root: BasePart?, params: RaycastParams): BasePart?
	if not root then
		return nil
	end
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -4.5, 0), params)
	return if hit and hit.Instance:IsA("BasePart") then hit.Instance else nil
end

type Swirl = { part: BasePart, pivot: CFrame, offset: CFrame, speed: number, mesh: BasePart?, rel: CFrame }

-- The Goo Ring swirl parts under `containers`, each with its rest offset from the ring centre.
local function findSwirls(containers: { Instance }): { Swirl }
	local out: { Swirl } = {}
	for _, container in containers do
		for _, d in container:GetDescendants() do
			local speed = d:GetAttribute(Constants.GOO_SPIN)
			local pivot = d:GetAttribute(Constants.GOO_PIVOT)
			if d:IsA("BasePart") and typeof(speed) == "number" and typeof(pivot) == "CFrame" then
				table.insert(out, {
					part = d,
					pivot = pivot,
					offset = pivot:ToObjectSpace(d.CFrame),
					speed = speed,
					mesh = nil,
					rel = CFrame.identity,
				})
			end
		end
	end
	return out
end

-- The lock icons on a gate (decor named "Lock..."), in name order: one fills per key held.
local function locks(m: Mover): { Decor }
	local out: { Decor } = {}
	for _, d in m.decor do
		if string.sub(string.lower(d.part.Name), 1, 4) == "lock" then
			table.insert(out, d)
		end
	end
	table.sort(out, function(a, b)
		return a.part.Name < b.part.Name
	end)
	return out
end

function ObbyFx.start(): Controller
	local all: { Mover } = {} -- every part with a behaviour
	local movers: { Mover } = {} -- with a motion
	local hazards: { Mover } = {}
	local triggers: { Mover } = {}
	local keys: { Mover } = {}
	local gates: { Mover } = {}
	local lockIcons: { [Mover]: { Decor } } = {}
	local hasBeat = false
	local lastBeat = -1
	local course: Instance? = nil
	local nextFind = 0
	local lastClock = os.clock()
	local swirls: { Swirl } = {}
	local swirlKey: { Instance? } = {}
	local nextSwirlFind = 0
	local character: Model? = nil
	local limbs: { BasePart } = {}

	-- Turns every Goo Ring swirl near the camera; looks for new rings (portal, a rebuilt course) every FIND_EVERY.
	local function spinSwirls(clock: number, camPos: Vector3?)
		if clock >= nextSwirlFind then
			nextSwirlFind = clock + ObbyFx.FIND_EVERY
			local folder = workspace:FindFirstChild(Constants.OBBY_FOLDER)
			local portal = folder and folder:FindFirstChild(Constants.OBBY_PORTAL)
			local built = folder and folder:FindFirstChild(Constants.OBBY_COURSE)
			if portal ~= swirlKey[1] or built ~= swirlKey[2] then
				swirlKey = { portal, built }
				local containers: { Instance } = {}
				for _, c in { portal, built } do
					if c then
						table.insert(containers, c)
					end
				end
				swirls = findSwirls(containers)
			end
		end
		local far = ObbyFx.MAX_DISTANCE * ObbyFx.MAX_DISTANCE
		for _, sw in swirls do
			local d = if camPos then sw.pivot.Position - camPos else Vector3.zero
			if sw.part.Parent ~= nil and d:Dot(d) <= far then
				local mesh = sw.mesh
				if mesh == nil or mesh.Parent ~= sw.part then
					-- the swap lands later (it loads): pick the mesh up, at rest, the first frame it is there
					local found = sw.part:FindFirstChild("Mesh")
					if not (found and found:IsA("BasePart")) then
						continue
					end
					mesh = found
					sw.mesh = found
					sw.rel = sw.part.CFrame:ToObjectSpace(found.CFrame)
				end
				(mesh :: BasePart).CFrame = sw.pivot * CFrame.Angles(0, 0, clock * sw.speed) * sw.offset * sw.rel
			end
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.RespectCanCollide = true -- a melted tile, an open gate or a hazard is not a floor

	local function setLights(m: Mover, on: boolean)
		for _, l in m.lights do
			(l :: any).Enabled = on
		end
	end

	-- Forgets the local player's course state (clocks, keys, melted and collapsed parts) and puts every part at rest.
	local function clear()
		ObbyClock.clear()
		for _, m in all do
			m.meltAt = nil
			m.stood = false
			m.spreadDone = false
			m.nextCrack = 0
			m.readyAt = 0
			m.offset = 0
			m.inside = false
			m.warned = false
			m.wasOut = false
			m.fell = false
			m.droppedAt = 0
			m.openedAt = nil
			m.live = true
			if m.part.Parent ~= nil then
				rest(m)
				if m.taken then
					m.taken = false
					setLights(m, true)
				end
			end
		end
		lastBeat = -1
	end

	local stopListening = ObbyFall.onReset(function()
		clear()
	end)

	local function scan(model: Instance)
		ObbyClock.clear()
		all, movers, hazards, triggers, keys, gates = {}, {}, {}, {}, {}, {}
		lockIcons = {}
		table.clear(byId)
		hasBeat = false
		local frameAttr = model:GetAttribute(Constants.OBBY_FRAME)
		local frame = if typeof(frameAttr) == "CFrame" then frameAttr.Rotation else CFrame.identity
		for _, child in model:GetChildren() do
			if child:IsA("BasePart") then
				local m = mover(child, frame)
				if m then
					local spec = m.spec
					table.insert(all, m)
					byId[m.id] = m
					if PLAY[m.kind] then
						table.insert(movers, m)
					end
					if spec.hazard == true then
						table.insert(hazards, m)
					end
					if type(spec.trigger) == "string" then
						table.insert(triggers, m)
					end
					if type(spec.key) == "string" then
						table.insert(keys, m)
					end
					if type(spec.gate) == "table" and type(spec.gate.group) == "string" then
						table.insert(gates, m)
						lockIcons[m] = locks(m)
					end
					hasBeat = hasBeat or m.beat
				end
			end
		end
		params.FilterDescendantsInstances = { model }
	end

	local function body(): Local
		local char = Players.LocalPlayer and Players.LocalPlayer.Character
		if char ~= character then
			character = char
			limbs = {}
			if char then
				for _, c in char:GetChildren() do
					if c:IsA("BasePart") and c.Name ~= "HumanoidRootPart" then
						table.insert(limbs, c)
					end
				end
			end
		end
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		local alive = humanoid ~= nil and humanoid.Health > 0
		return {
			standingOn = if alive then floorUnder(root, params) else nil,
			root = if alive then root else nil,
			humanoid = humanoid,
			limbs = if alive then limbs else {},
		}
	end

	-- Triggers, keys and gates: the local player's own clocks and pickups.
	local function perPlayer(me: Local, clock: number)
		for _, m in triggers do
			local group = m.spec.trigger :: string
			if
				not ObbyClock.running(group)
				and (me.standingOn == m.part or touching(m.part, me, ObbyFx.TOUCH_PAD))
				and ObbyClock.start(group)
			then
				ObbyFx.sound("go")
			end
		end
		for _, m in keys do
			if not m.taken and touching(m.part, me, ObbyFx.KEY_PAD) then
				m.taken = true
				ObbyClock.addKey(m.spec.key :: string)
				look(m, false, 1)
				setLights(m, false)
				ObbyFx.sound("chime")
			end
		end
		for _, m in gates do
			local gate = m.spec.gate
			local held = ObbyClock.keys(gate.group)
			local need = num(gate, "need", 1)
			local icons = lockIcons[m]
			for i, icon in icons do
				local want = if i <= held then ObbyFx.LOCK_FULL else icon.color
				if icon.part.Color ~= want then
					icon.part.Color = want
				end
			end
			if held >= need then
				if m.openedAt == nil then
					m.openedAt = clock
					ObbyFx.sound("gate")
				end
				local f = math.clamp((clock - (m.openedAt :: number)) / ObbyFx.GATE_FADE, 0, 1)
				look(m, false, m.transparency + (1 - m.transparency) * f)
			elseif m.openedAt ~= nil then
				m.openedAt = nil
				look(m, true, m.transparency)
			end
		end
	end

	local function tick(camera: Camera?)
		local clock = os.clock()
		local dt = math.min(clock - lastClock, 0.1) -- a long hitch must not sink a pad all the way at once
		lastClock = clock
		spinSwirls(clock, if camera then camera.CFrame.Position else nil)
		if course == nil or course.Parent == nil then
			if clock < nextFind then
				return
			end
			nextFind = clock + ObbyFx.FIND_EVERY
			local folder = workspace:FindFirstChild(Constants.OBBY_FOLDER)
			local found = folder and folder:FindFirstChild(Constants.OBBY_COURSE)
			if not found then
				all, movers, hazards, triggers, keys, gates = {}, {}, {}, {}, {}, {}
				course = nil
				return
			end
			course = found
			scan(found)
		end
		if #all == 0 then
			return
		end
		local serverTime = workspace:GetServerTimeNow()
		local camPos = if camera then camera.CFrame.Position else nil
		local me = body()
		local root = me.root
		local far = ObbyFx.MAX_DISTANCE * ObbyFx.MAX_DISTANCE
		local hearFar = ObbyFx.SOUND_RANGE * ObbyFx.SOUND_RANGE
		-- the beat clock: a flash on beat parts, and one quiet tick when one is near
		local beatLen = Kit.beat(1)
		local beatIndex = math.floor(serverTime / beatLen)
		local beatPulse = math.max(0, 1 - (serverTime % beatLen) / ObbyFx.BEAT_PULSE_SECONDS) * ObbyFx.BEAT_PULSE
		local beatHeard = false
		for _, m in movers do
			local part = m.part
			if part.Parent == nil or m.taken then
				continue
			end
			local d = if camPos then m.base.Position - camPos else Vector3.zero
			if d:Dot(d) > far then
				continue
			end
			-- Server time, or seconds on its `start` clock (nil until that starts: Kit puts it at rest, as the checks)
			local t: number? = serverTime
			if m.start then
				t = ObbyClock.elapsed(m.start)
			end
			local r = if root then m.base.Position - root.Position else nil
			local now: Now = {
				t = t,
				-- Only the fraction of the cycle: server time is ~1.8e9 s, and CFrame angles are 32-bit floats.
				cycle = if t then (t / m.period + m.phase) % 1 else 0,
				clock = clock,
				dt = dt,
				me = me,
				near = r ~= nil and r:Dot(r) <= hearFar,
			}
			m.live = true
			m.paint = m.color
			PLAY[m.kind](m, now)
			if m.beat then
				m.paint = m.paint:Lerp(WHITE, beatPulse)
				beatHeard = beatHeard or now.near
			end
			if part.Color ~= m.paint then
				part.Color = m.paint
			end
		end
		if hasBeat and beatIndex ~= lastBeat then
			if beatHeard and lastBeat >= 0 then
				ObbyFx.sound("tick")
			end
			lastBeat = beatIndex
		end
		if not root or not ObbyLook.isInside() then
			return
		end
		perPlayer(me, clock)
		for _, m in hazards do
			if m.live and m.part.Parent ~= nil and touching(m.part, me, ObbyFx.HAZARD_PAD) then
				ObbyFx.sound("splat")
				if ObbyFall.reset("hazard") then
					return
				end
			end
		end
	end

	return {
		tick = tick,
		stop = function()
			stopListening()
			all, movers, hazards, triggers, keys, gates = {}, {}, {}, {}, {}, {}
			table.clear(byId)
			course = nil
			swirls = {}
			swirlKey = {}
		end,
	}
end

return ObbyFx
