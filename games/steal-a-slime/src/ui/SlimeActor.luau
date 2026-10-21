--!strict
--[[
	SlimeActor (contract/slime-life.md): the life of one animated slime on top
	of SlimeMotor's idle pose, for every SlimeLifeRunner motor rig. Each frame
	it combines
	  ui/SlimeGait    its species gait (real hops, surges, waddles, hovering)
	  ui/SlimeBeats   the lane beat its ParadeChoreo plan says it is in
	  ui/SlimeReact   how it reacts to the local player, nerves, frights
	into one SlimeMotor.Mods, picks an emote, and plays the hop effects (a goo
	splat on landing, a goo string on take-off). Client-only; reads the model's
	replicated attributes, never decides anything.

	Off the lane math the drawn spot follows the stepwise Body through Lib StepTrack (3D, so the slide and an escape
	glide draw at frame rate), and the heading through its own filter (Mods.heading). With FEATURES.SlimeAlive a pad
	slime fidgets (ui/SlimeFidget), reacts to the local player and drops in / hops over when it is put down or moved;
	an escaping slime races home stretched and sweating; a riding slime sits back on the slide; a lean spring and a
	squash spring (Lib Spring) add follow-through on top.

	  SlimeActor.attach(model, motor, now, prevState?, movedFrom?) -> Actor
	    prevState = the model's State before this rig (a Carried slime put on its pad drops in)
	    movedFrom = where its Body stood before it jumped to this pad unrigged (it hops over from there)
	  SlimeActor.setState(actor, prev, state, now)            the State changed and the rig stays (Wild / Pad / Escaping)
	  SlimeActor.settle(actor, pushX, pushZ, dt)               after SlimeSpacing: the push, and where the tag hangs
	  SlimeActor.update(actor, frame, now, serverNow, rand, full)   fills actor.mods / emote
	    full (default true) = the near tier: reactions to the player, emote, hop effects.
	    false = mid / far: the smooth lane glide, gait and lane beats only, so a slime
	    across the plaza moves without the Body's replication steps and still hops.
	  SlimeActor.frighten(actor, now, watch, delay)           a neighbour was grabbed
	  SlimeActor.watch(actor, at, untilAt, face)              look at a spot for a while
	  SlimeActor.bump(actor, now, hit)                        caught up with the slime ahead
	  SlimeActor.release(actor)                               effects gone
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local ParadeChoreo = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ParadeChoreo"))
local ParadeLane = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ParadeLane"))
local Lib = ReplicatedStorage:WaitForChild("Lib"):WaitForChild("core")
local SlimeAttention = require(script.Parent:WaitForChild("SlimeAttention"))
local SlimeBeats = require(script.Parent:WaitForChild("SlimeBeats"))
local SlimeFidget = require(script.Parent:WaitForChild("SlimeFidget"))
local SlimeGait = require(script.Parent:WaitForChild("SlimeGait"))
local SlimeMotor = require(script.Parent:WaitForChild("SlimeMotor"))
local SlimePersona = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SlimePersona"))
local SlimeReact = require(script.Parent:WaitForChild("SlimeReact"))
local Spring = require(Lib:WaitForChild("Spring"))
local StepTrack = require(Lib:WaitForChild("StepTrack"))

local SlimeActor = {}

SlimeActor.NERVES_LOOK_DISTANCE = 26 -- studs: a nervous slime looks back at a player this close
SlimeActor.TURN_RATE = 6 -- 1 / s: how fast the body turns to a new look (shortest way round)
SlimeActor.MAX_TURN = 4.5 -- rad / s: never turns faster than this (no snapping when a player walks round it)
SlimeActor.NEAR_DEAD_ZONE = 3.5 -- studs: a player this close keeps the slime's last look (the angle swings too fast up close)
SlimeActor.CORRECT_RATE = 2.5 -- 1 / s: a lane slime's drawn spot absorbs what the server adds on top of lane math (spacing)
-- ... and up to this much faster while the Body is CATCH_ERROR studs or more off the drawn spot (the lane queue holds
-- it back or lets it catch up), so a queued slime is drawn within about half a stud of its Body. The replication
-- wobble (a few hundredths of a stud) stays on the slow rate.
SlimeActor.CATCH_RATE = 8
SlimeActor.CATCH_ERROR = 1
SlimeActor.SNAP = 6 -- studs: a jump this big in one frame is a teleport (or the end of the ride): the drawn spot jumps too
SlimeActor.LATERAL_RATE = 2 -- 1 / s: the estimate of the slime's sideways place on the lane
-- The Body replicates about this late: beats are looked up this far back, so a pose starts when the slime stops.
SlimeActor.REPLICATION_LAG = 0.12
SlimeActor.MOVE_JUMP = 1.5 -- studs: a pad slime's Body jumping this far in one frame was moved (Move, a swap): it hops over
SlimeActor.SNAP_JUMP = 60 -- studs: further than this a pad move is a teleport, no hop
-- FEATURES.SlimeAlive springs (Lib Spring: f Hz, zeta, r). Lean: tilt from the forward acceleration of the drawn
-- spot (gain rad per stud / s^2, capped at max), so a slime rocks back as it sets off and forward as it stops.
-- Squash: kicked by landings (kick = squash speed per unit of splat), capped at max either way.
SlimeActor.LEAN = table.freeze({ f = 2.2, zeta = 0.32, r = 0, gain = 0.018, max = 0.3 })
SlimeActor.SQUASH = table.freeze({ f = 2.6, zeta = 0.32, r = 0, kick = 1.3, max = 0.3 })
-- A hop's jelly: squash speed kicked into the squash spring per unit of landing (down) and take-off (up), so the
-- body rings two or three times after every jump.
SlimeActor.HOP_JELLY = table.freeze({ land = 1.3, launch = 0.7 })
SlimeActor.ESCAPE_SPEED = 10 -- studs / s: an escaping slime this fast leans and stretches fully
-- A slime on the move faces where it goes: a reaction (the player, nerves, a fright) only turns it this far
-- (radians), a glance; it turns round to face you only while it stands still.
SlimeActor.GLANCE = 0.45
SlimeActor.MOVING = 0.8 -- studs / s: faster than this a slime counts as on the move
SlimeActor.AIR_TURN = 0.85 -- share of a look turn a hopper drops while it squats and jumps (it jumps nose first)
SlimeActor.AIR_RATE = 14 -- 1 / s: how fast that share fades in and out
-- The name tag and the Buy card hang on a TagAnchor that follows the drawn slime through this spring (Lib Spring:
-- f Hz, zeta, r): it glides along with a hopper's leaps instead of jumping, and never steps with the Body.
SlimeActor.TAG = table.freeze({ f = 3, zeta = 1, r = 0.5 })
-- The tag rises with the slime (a float, a slow rise in a fidget) through a softer spring, so a quick hop only nudges
-- it and the slime never rises into its own label.
SlimeActor.TAG_LIFT = table.freeze({ f = 1.2, zeta = 1, r = 0 })
SlimeActor.PAD_LEAN = 0.3 -- studs: a pad slime leans towards you at most this far (it stays on its pad)
-- Eyes lead: the face turns ahead of the body by this share of the turn still to go (at most FACE_LEAD radians), and
-- takes the attention glances on its own, so the eyes move first and the body follows.
SlimeActor.FACE_LEAD_SHARE = 0.5
SlimeActor.FACE_LEAD = 0.22 -- more and the face parts of a side-on slime (Gummy) slide off its silhouette
SlimeActor.FACE_LEAD_RATE = 20 -- 1 / s: the eyes dart there in about 50 ms, never in a single frame
SlimeActor.BUMP_SECONDS = 0.35
SlimeActor.BUMPED_SECONDS = 0.5
-- Face -> bones: lids shut (closed) or eyes bulging (pop), SlimeBones.Extra.
-- The lids are a blink: the eyes sink in while the closed-eye arcs slide out, so a face is either fully shut
-- (closed = 1) or open (0). Anything in between leaves the eyes half sunk with no arcs: they look gone.
local FACES: { [string]: { closed: number, pop: number } } = table.freeze({
	happy = { closed = 1, pop = 0 },
	asleep = { closed = 1, pop = 0 },
	squeeze = { closed = 1, pop = 0 },
	sleepy = { closed = 0, pop = 0 },
	smug = { closed = 0, pop = 0 },
	dizzy = { closed = 0, pop = 0.3 },
	angry = { closed = 0, pop = 0 },
	focus = { closed = 0, pop = 0 },
	surprised = { closed = 0, pop = 1 },
	excited = { closed = 0, pop = 0.8 },
	worried = { closed = 0, pop = 0.4 },
} :: any)
local GOO = Color3.fromRGB(ParadeLane.COLOR[1], ParadeLane.COLOR[2], ParadeLane.COLOR[3])
local ALIVE = Config.FEATURES.SlimeAlive == true

-- What the runner measures once per frame for every actor.
export type Frame = {
	player: Vector3?, -- the local character's root position
	cash: number?, -- leaderstats Cash
	userId: number?, -- the local player's UserId (their own pad slimes greet them)
}

export type Actor = {
	model: Model,
	motor: SlimeMotor.Motor,
	persona: SlimePersona.Persona,
	gait: SlimeGait.State,
	gaitPose: SlimeGait.Pose,
	beatPose: SlimeBeats.Pose,
	reactPose: SlimeReact.Pose,
	mods: SlimeMotor.Mods,
	yaw: number, -- smoothed turn from the heading
	yawWeight: number, -- smoothed share of that turn
	reactYaw: number, -- last turn towards the local player (kept inside NEAR_DEAD_ZONE)
	ax: number, -- smooth anchor: where the Body is, without its replication steps
	az: number,
	hasAnchor: boolean,
	corrX: number, -- lane slimes: the Body minus the lane math, filtered
	corrZ: number,
	hasCorr: boolean,
	lateral: number, -- lane slimes: sideways place on the lane (estimated from the Body)
	hasLateral: boolean,
	lastNow: number,
	species: string?,
	plan: ParadeChoreo.Plan?,
	planKey: string?,
	emote: string?,
	visible: Vector3, -- where the slime is drawn (Body + gait offset), for bumps and emotes
	speed: number,
	frightAt: number,
	watchAt: Vector3?,
	watchUntil: number,
	watchFace: string?,
	bumpAt: number,
	bumpedAt: number,
	feet: Attachment?,
	splat: ParticleEmitter?,
	stringAt: Attachment?,
	string: Beam?,
	state: string?, -- the model's State as this actor last saw it
	track: StepTrack.Track, -- the smooth spot off the lane math
	heading: number, -- smoothed Body yaw (radians)
	hasHeading: boolean,
	lastBody: Vector3?, -- the Body's position last frame (a pad Move shows as a jump)
	moveX: number, -- an "arrive" hop starts this far from the new spot (world studs)
	moveZ: number,
	fwd: number, -- last forward speed of the drawn spot (lean spring)
	fwdAt: number,
	accel: number, -- smoothed forward acceleration
	lean: Spring.Spring,
	squash: Spring.Spring,
	fidget: SlimeFidget.State,
	fidgetPose: SlimeFidget.Pose,
	attention: SlimeAttention.State, -- glances and head tilts while it watches something
	airK: number, -- 0..1: how much a hopper's crouch / jump holds back look turns
	pushX: number, -- SlimeSpacing push (world studs), carried between frames
	pushZ: number,
	tagX: Spring.Spring, -- where the tag hangs (world x / z), following the drawn slime
	tagZ: Spring.Spring,
	tagY: Spring.Spring, -- how far the tag rises with the slime's lift (studs)
	hopLift: number, -- this frame's hop arc (part of mods.lift the tag leaves out)
	faceLead: number, -- the face's turn on top of the body, eased (radians)
	hasTag: boolean,
	tagOffset: Vector3, -- the TagAnchor's offset from the Body (world axes)
}

local function rootOf(motor: SlimeMotor.Motor): BasePart?
	local p = motor.skinJoint.Part1
	return if p and p:IsA("BasePart") then p else nil
end

local function effects(actor: Actor)
	if actor.feet then
		return
	end
	local root = rootOf(actor.motor)
	if not root then
		return
	end
	local feet = Instance.new("Attachment")
	feet.Name = "LifeFeet"
	feet.Position = Vector3.new(0, -actor.motor.body.Size.Y / 2, 0)
	feet.Parent = root
	local splat = Instance.new("ParticleEmitter")
	splat.Name = "LifeSplat"
	splat.Texture = "rbxasset://textures/particles/smoke_main.dds"
	splat.Color = ColorSequence.new(GOO)
	splat.LightEmission = 0.15
	splat.Rate = 0
	splat.Lifetime = NumberRange.new(0.35, 0.55)
	splat.Speed = NumberRange.new(5, 9)
	splat.SpreadAngle = Vector2.new(75, 75)
	splat.EmissionDirection = Enum.NormalId.Top
	splat.Acceleration = Vector3.new(0, -45, 0)
	splat.Drag = 1
	splat.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0.1) })
	splat.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	splat.Parent = feet
	actor.feet, actor.splat = feet, splat
	if actor.persona.gait ~= "Hop" then
		return
	end
	-- The goo string runs from the take-off spot (a Terrain attachment) to the slime's feet.
	local at = Instance.new("Attachment")
	at.Name = "LifeGooFrom"
	at.Parent = workspace.Terrain
	local beam = Instance.new("Beam")
	beam.Name = "LifeGooString"
	beam.Attachment0 = at
	beam.Attachment1 = feet
	beam.Color = ColorSequence.new(GOO)
	beam.FaceCamera = true
	beam.Segments = 6
	beam.LightInfluence = 0.6
	local size = (actor.model:GetAttribute("Size") :: number?) or 1
	beam.Width0 = 1.1 * size
	beam.Width1 = 0.5 * size
	beam.Enabled = false
	beam.Parent = feet
	actor.feet, actor.splat, actor.stringAt, actor.string = feet, splat, at, beam
end

function SlimeActor.attach(
	model: Model,
	motor: SlimeMotor.Motor,
	now: number,
	prevState: string?,
	movedFrom: Vector3?
): Actor
	local species = model:GetAttribute(Constants.SPECIES_ATTRIBUTE)
	local persona = SlimePersona.of(if type(species) == "string" then species else nil)
	local p = motor.body.CFrame.Position
	local actor: Actor = {
		model = model,
		motor = motor,
		persona = persona,
		gait = SlimeGait.new(p.X, p.Z, now, math.random() * 2 * math.pi),
		gaitPose = {} :: any,
		beatPose = {} :: any,
		reactPose = {} :: any,
		mods = SlimeMotor.newMods(),
		yaw = 0,
		yawWeight = 0,
		reactYaw = 0,
		ax = p.X,
		az = p.Z,
		hasAnchor = false,
		corrX = 0,
		corrZ = 0,
		hasCorr = false,
		lateral = 0,
		hasLateral = false,
		lastNow = now,
		species = if type(species) == "string" then species else nil,
		plan = nil,
		planKey = nil,
		emote = nil,
		visible = p,
		speed = 0,
		frightAt = -math.huge,
		watchAt = nil,
		watchUntil = 0,
		watchFace = nil,
		bumpAt = -math.huge,
		bumpedAt = -math.huge,
		state = nil,
		track = StepTrack.new(p.X, p.Y, p.Z, now),
		heading = 0,
		hasHeading = false,
		lastBody = nil,
		moveX = 0,
		moveZ = 0,
		fwd = 0,
		fwdAt = now,
		accel = 0,
		lean = Spring.new(SlimeActor.LEAN.f, SlimeActor.LEAN.zeta, SlimeActor.LEAN.r, 0),
		squash = Spring.new(SlimeActor.SQUASH.f, SlimeActor.SQUASH.zeta, SlimeActor.SQUASH.r, 0),
		fidget = SlimeFidget.new(persona.temper, now, math.random),
		fidgetPose = {} :: any,
		attention = SlimeAttention.new(now, math.random),
		airK = 0,
		pushX = 0,
		pushZ = 0,
		tagX = Spring.new(SlimeActor.TAG.f, SlimeActor.TAG.zeta, SlimeActor.TAG.r, p.X),
		tagZ = Spring.new(SlimeActor.TAG.f, SlimeActor.TAG.zeta, SlimeActor.TAG.r, p.Z),
		tagY = Spring.new(SlimeActor.TAG_LIFT.f, SlimeActor.TAG_LIFT.zeta, SlimeActor.TAG_LIFT.r, 0),
		hopLift = 0,
		faceLead = 0,
		hasTag = false,
		tagOffset = Vector3.zero,
	}
	local state = model:GetAttribute("State")
	actor.state = if type(state) == "string" then state else nil
	if ALIVE and actor.state == "Pad" and prevState == "Carried" then
		SlimeFidget.play(actor.fidget, "drop", now) -- put down on its pad
	elseif ALIVE and actor.state == "Pad" and movedFrom then
		actor.moveX, actor.moveZ = movedFrom.X - p.X, movedFrom.Z - p.Z
		SlimeFidget.play(actor.fidget, "arrive", now) -- moved while it had no rig: it hops over all the same
	end
	return actor
end

-- The model's State changed and the rig stays (both states animated): an escape that reaches the pad lands.
function SlimeActor.setState(actor: Actor, prev: string?, state: string?, now: number)
	actor.state = state
	if not ALIVE then
		return
	end
	if state == "Pad" and (prev == "Escaping" or prev == "Carried") then
		SlimeFidget.play(actor.fidget, if prev == "Carried" then "drop" else "hop", now)
	end
end

-- The lane plan from the model's ChoreoSeed / LaneAt / LaneUntil (the server builds the same one).
local function planOf(actor: Actor): (ParadeChoreo.Plan?, number, number)
	local model = actor.model
	local seed = model:GetAttribute(Constants.CHOREO_SEED_ATTRIBUTE)
	local at = model:GetAttribute(Constants.LANE_AT_ATTRIBUTE)
	local untilAt = model:GetAttribute(Constants.LANE_UNTIL_ATTRIBUTE)
	if type(seed) ~= "number" or type(at) ~= "number" or type(untilAt) ~= "number" then
		actor.plan, actor.planKey = nil, nil
		return nil, 0, 0
	end
	-- The Species attribute can land after the rig: the temperament (and so the plan) follows it.
	local species = model:GetAttribute(Constants.SPECIES_ATTRIBUTE)
	if type(species) == "string" and species ~= actor.species then
		actor.species = species
		actor.persona = SlimePersona.of(species)
	end
	local startAt, seconds, lead = ParadeLane.walkTimes(at, untilAt)
	local key = `{seed}|{at}|{untilAt}|{actor.persona.temper}`
	if actor.planKey ~= key then
		actor.plan = ParadeChoreo.plan(seed, actor.persona.temper, seconds, lead)
		actor.planKey = key
	end
	return actor.plan, startAt, untilAt
end

local function face(mods: SlimeMotor.Mods, name: string?)
	local f = if name then FACES[name] else nil
	if f then
		mods.closed = math.max(mods.closed, f.closed)
		mods.pop = math.max(mods.pop, f.pop)
	end
end

local function wrap(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- A lane slime's spot by lane math at server time `t` (the same ParadeLane.pose + ParadeChoreo the server runs),
-- and its velocity. nil off the lane or outside the walk (ride, drain).
local function laneSpot(actor: Actor, pos: Vector3, t: number, dt: number): (number?, number, number, number)
	local model = actor.model
	local at = model:GetAttribute(Constants.LANE_AT_ATTRIBUTE)
	local untilAt = model:GetAttribute(Constants.LANE_UNTIL_ATTRIBUTE)
	if type(at) ~= "number" or type(untilAt) ~= "number" or ParadeLane.phase(at, untilAt, t) ~= "Walk" then
		actor.hasLateral = false
		return nil, 0, 0, 0
	end
	local plan, startAt = planOf(actor)
	local lifetime = untilAt - at
	local function ahead(when: number): number
		return if plan then ParadeChoreo.offset(plan, when - startAt) * ParadeLane.walkSpeed(lifetime) else 0
	end
	-- Sideways place: the Body's offset from the centreline along the lane normal, filtered.
	local s = math.clamp(ParadeLane.distance(at, untilAt, t) + ahead(t), -ParadeLane.LEAD_LENGTH, ParadeLane.LENGTH)
	local cx, cz = ParadeLane.offsetAt(s, 0)
	local nx, nz = ParadeLane.offsetAt(s, 1)
	nx, nz = nx - cx, nz - cz
	local n2 = nx * nx + nz * nz
	if n2 > 1e-6 then
		local lateral = ((pos.X - cx) * nx + (pos.Z - cz) * nz) / n2
		if actor.hasLateral then
			actor.lateral += (lateral - actor.lateral) * (1 - math.exp(-dt * SlimeActor.LATERAL_RATE))
		else
			actor.lateral, actor.hasLateral = lateral, true
		end
	end
	local p1 = ParadeLane.pose(at, untilAt, actor.lateral, t, ahead(t)).position
	local p0 = ParadeLane.pose(at, untilAt, actor.lateral, t - 0.1, ahead(t - 0.1)).position
	return p1[1], p1[3], (p1[1] - p0[1]) / 0.1, (p1[3] - p0[3]) / 0.1
end

-- Where the slime is drawn from, smooth at frame rate. The Body replicates in steps; a lane slime follows its
-- lane math plus a slow correction towards the Body, anything else a fast filter of the Body.
local function anchor(
	actor: Actor,
	pos: Vector3,
	onLane: boolean,
	serverNow: number,
	dt: number,
	now: number
): (number, number, number?, number?)
	local lx, lz, vx, vz = nil, 0, 0, 0
	if onLane then
		lx, lz, vx, vz = laneSpot(actor, pos, serverNow - SlimeActor.REPLICATION_LAG, dt)
	end
	if lx then
		-- The correction can grow large on purpose (the lane queue holds a slime back several studs), so only a
		-- sudden jump in it is a teleport. Snapping on its size made every queued slime follow the stepwise Body.
		local cx, cz = pos.X - lx, pos.Z - lz
		local jx, jz = cx - actor.corrX, cz - actor.corrZ
		if not actor.hasCorr or jx * jx + jz * jz > SlimeActor.SNAP ^ 2 then
			actor.corrX, actor.corrZ, actor.hasCorr = cx, cz, true
		else
			local err = math.sqrt(jx * jx + jz * jz)
			local rate = SlimeActor.CORRECT_RATE
				+ SlimeActor.CATCH_RATE * math.clamp(err / SlimeActor.CATCH_ERROR, 0, 1)
			local k = 1 - math.exp(-dt * rate)
			actor.corrX += jx * k
			actor.corrZ += jz * k
		end
		actor.ax, actor.az, actor.hasAnchor = lx + actor.corrX, lz + actor.corrZ, true
		StepTrack.reset(actor.track, actor.ax, pos.Y, actor.az, now) -- leaving the lane math starts from here
		return actor.ax, actor.az, vx, vz
	end
	actor.hasCorr = false
	if not actor.hasAnchor then
		StepTrack.reset(actor.track, pos.X, pos.Y, pos.Z, now)
	end
	local x, _, z, tvx, _, tvz = StepTrack.step(actor.track, pos.X, pos.Y, pos.Z, now)
	actor.ax, actor.az, actor.hasAnchor = x, z, true
	return x, z, tvx, tvz
end

-- Yaw from the slime's heading to world point `at` (+ = left).
local function yawTo(body: BasePart, from: Vector3, at: Vector3): (number, number)
	local rel = body.CFrame:VectorToObjectSpace(at - from)
	local flat = Vector3.new(rel.X, 0, rel.Z)
	return math.atan2(-rel.X, -rel.Z), flat.Magnitude
end

function SlimeActor.update(
	actor: Actor,
	frame: Frame,
	now: number,
	serverNow: number,
	rand: () -> number,
	full: boolean?
)
	local detailed = full ~= false
	if detailed then
		effects(actor) -- once, the first time the slime is near
	end
	local model, body, mods = actor.model, actor.motor.body, actor.mods
	local pos = body.CFrame.Position
	local look = body.CFrame.LookVector
	local state = model:GetAttribute("State")
	local wild = state == "Wild"
	local pad = state == "Pad"
	local escaping = state == "Escaping"
	-- On the fountain slide (Riding); the lead-in from the slide mouth also says Riding, but there it walks.
	local laneAt = model:GetAttribute(Constants.LANE_AT_ATTRIBUTE)
	local riding = model:GetAttribute(Constants.RIDING_ATTRIBUTE) == true
		and (type(laneAt) ~= "number" or serverNow - laneAt < ParadeLane.RIDE_SECONDS)

	local dt = math.max(now - actor.lastNow, 0)
	actor.lastNow = now

	-- A pad slime whose Body jumped was moved (Move, a swap): it hops over from where it was drawn.
	local last = actor.lastBody
	actor.lastBody = pos
	local moved = false
	if pad and last then
		local jx, jz = pos.X - last.X, pos.Z - last.Z
		local j2 = jx * jx + jz * jz
		if j2 > SlimeActor.MOVE_JUMP ^ 2 then
			moved = true
			actor.hasAnchor = false
			if ALIVE and j2 < SlimeActor.SNAP_JUMP ^ 2 then
				actor.moveX, actor.moveZ = actor.visible.X - pos.X, actor.visible.Z - pos.Z
				SlimeFidget.play(actor.fidget, "arrive", now)
			end
		end
	end

	-- Heading: the Body turns in replication steps; the drawn slime turns smoothly (Mods.heading).
	local bodyYaw = math.atan2(-look.X, -look.Z)
	local oldHeading = actor.heading
	if not actor.hasHeading or moved then
		actor.heading, actor.hasHeading, oldHeading = bodyYaw, true, bodyYaw
	else
		actor.heading = StepTrack.angle(actor.heading, bodyYaw, dt)
	end
	local turnRate = if dt > 0 then wrap(actor.heading - oldHeading) / dt else 0

	-- Gait from the smooth anchor (frozen while it rides the slide; none on a pad or an escape)
	local ax, az, vx, vz = anchor(actor, pos, wild and not riding, serverNow, dt, now)
	local ay = actor.track.oy
	local g = actor.gaitPose
	local st = actor.gait
	if riding or not wild then
		st.stage, st.visX, st.visZ, st.side, st.lastX, st.lastZ, st.lastT = "ground", ax, az, 0, ax, az, now
		st.vx, st.vz, st.landedAt, st.changedAt = 0, 0, now - 10, now
	end
	if wild then
		SlimeGait.step(st, actor.persona, ax, az, look.X, look.Z, now, rand, g, vx, vz)
	end
	if riding or not wild then
		g.dx, g.dz, g.lift, g.sx, g.sy, g.tilt, g.roll, g.jiggle = 0, 0, 0, 1, 1, 0, 0, 0
		g.air, g.vy, g.face, g.landed, g.stringX, g.stringZ, g.stringAlpha = false, 0, nil, 0, nil, nil, 0
		g.launched = 0
	end
	-- Offsets are from the smooth anchor; the Transform needs them from the replicated Body.
	g.dx += ax - pos.X
	g.dz += az - pos.Z
	mods.dx, mods.dz, mods.lift = g.dx, g.dz, g.lift
	-- the hop arc itself doesn't lift the tag (it would bob with every hop); a float's hover and slow rises do
	actor.hopLift = if actor.persona.gait == "Hop" then g.lift else 0
	mods.dy = ay - pos.Y
	mods.heading = wrap(actor.heading - bodyYaw)
	mods.sx, mods.sy, mods.tilt, mods.roll = g.sx, g.sy, g.tilt, g.roll
	mods.jiggle = g.jiggle
	mods.air = if g.air then 1 else 0
	mods.vy = g.vy
	mods.yaw, mods.yawWeight, mods.lean = 0, 0, 0
	local spin = 0 -- a spin beat / fidget: added on top of the smoothed heading, never chased (no jump mid-spin)
	local faceGlance = 0 -- SlimeAttention glances, for the face alone
	mods.closed, mods.pop = 0, 0
	local faceName: string? = g.face
	local emote: string? = nil
	actor.visible = Vector3.new(pos.X + g.dx, ay, pos.Z + g.dz)
	actor.speed = math.sqrt(actor.gait.vx ^ 2 + actor.gait.vz ^ 2)
	if detailed and g.landed > 0 and actor.splat then
		actor.splat:Emit(math.max(3, math.floor(6 * g.landed + 0.5)))
	end
	if actor.string and actor.stringAt then
		local on = detailed and g.stringX ~= nil and g.stringAlpha > 0
		actor.string.Enabled = on
		if on then
			actor.stringAt.WorldPosition =
				Vector3.new(g.stringX :: number, pos.Y - body.Size.Y / 2, g.stringZ :: number)
			actor.string.Transparency = NumberSequence.new(1 - 0.7 * g.stringAlpha)
		end
	end

	-- Lane beat
	local standing = false
	if wild and not riding and Config.FEATURES.SlimeChoreo then
		local plan, startAt, untilAt = planOf(actor)
		if plan then
			local beat, phase, u = ParadeChoreo.beatAt(plan, serverNow - SlimeActor.REPLICATION_LAG - startAt)
			if beat then
				local b = SlimeBeats.pose(beat.kind, phase, u, beat.side, now, actor.beatPose)
				standing = phase == "stop"
				if b.yaw then
					mods.yaw, mods.yawWeight = b.yaw, 1
				end
				if b.spin then
					spin = b.spin
				end
				mods.lean += b.lean
				mods.tilt += b.tilt
				mods.roll += b.roll
				mods.lift += b.lift
				mods.sx *= b.sx
				mods.sy *= b.sy
				if b.face and not g.air then
					faceName = b.face
				end
				emote = b.emote
			end
			-- Nerves before the drain: sweat, quick little bounces, glances back.
			local k = SlimeReact.nerves(untilAt - serverNow - Config.DESPAWN_TELEGRAPH_SECONDS)
			if k > 0 then
				faceName = faceName or "worried"
				emote = emote or "sweat"
				mods.lift += 0.15 * (0.5 - 0.5 * math.cos(now * 8)) * k
				local player = frame.player
				local yaw, dist = 0, math.huge
				if player then
					yaw, dist = yawTo(body, actor.visible, player)
				end
				-- a glance back, unless a beat already holds the turn
				local want = if dist < SlimeActor.NERVES_LOOK_DISTANCE then 0.7 * k else 0.5 * k
				if want > mods.yawWeight then
					mods.yaw = if dist < SlimeActor.NERVES_LOOK_DISTANCE then yaw else math.pi * 0.8
					if actor.speed > SlimeActor.MOVING then
						mods.yaw = math.clamp(wrap(mods.yaw), -SlimeActor.GLANCE, SlimeActor.GLANCE)
					end
					mods.yawWeight = want
				end
			end
		end
	end

	-- The local player (looked at from the anchor, not the hop: a jump must not swing the turn). Near tier only.
	if detailed and wild and not riding and frame.player then
		local yaw, dist = yawTo(body, Vector3.new(ax, pos.Y, az), frame.player)
		if dist < SlimeActor.NEAR_DEAD_ZONE then
			yaw = actor.reactYaw
		else
			actor.reactYaw = yaw
		end
		local price = model:GetAttribute("Price")
		local afford = frame.cash ~= nil and (type(price) ~= "number" or price <= (frame.cash :: number))
		local r = SlimeReact.toPlayer(actor.persona.temper, dist, yaw, afford, now, actor.reactPose)
		if actor.speed > SlimeActor.MOVING then
			r.yaw = math.clamp(wrap(r.yaw), -SlimeActor.GLANCE, SlimeActor.GLANCE) -- on the move: a glance
		end
		if r.weight > 0 then
			local glance, headTilt = SlimeAttention.step(actor.attention, now, rand, r.weight)
			faceGlance = glance
			mods.roll += headTilt * (if standing then 0.35 else 1) * (if g.air then 0 else 1)
		end
		if r.weight > 0 then
			local keep = if standing then 0.35 else 1 -- a beat in progress mostly wins
			if r.weight * keep > mods.yawWeight then
				mods.yaw, mods.yawWeight = r.yaw, r.weight * keep
			end
			-- a hopper's hops are bounce enough
			mods.lift += r.lift * keep * (if actor.persona.gait == "Hop" then 0.3 else 1)
			mods.sy *= 1 + (r.sy - 1) * keep
			mods.lean += r.lean * keep
			if not standing and not g.air then
				faceName = r.face or faceName
			end
			emote = emote or r.emote
		end
	end

	if ALIVE then
		if riding then
			-- on the slide: sits back, stretched and grinning, leaning into the spiral
			mods.tilt -= 0.16
			mods.sy *= 0.92
			mods.sx *= 1.05
			mods.roll += math.clamp(-turnRate * 0.12, -0.3, 0.3)
			faceName = "excited"
		elseif escaping then
			-- racing home: leans into it, flattened and rippling, worried and sweating (no bounce)
			local tvx, tvz = actor.track.vx, actor.track.vz
			local k = math.clamp(math.sqrt(tvx * tvx + tvz * tvz) / SlimeActor.ESCAPE_SPEED, 0, 1)
			mods.tilt += 0.26 * k
			mods.sy *= 1 - 0.1 * k + 0.05 * math.sin(now * 19) * k
			mods.sx *= 1 + 0.05 * k
			mods.roll += 0.06 * math.sin(now * 9.5) * k
			faceName = "worried"
			emote = "sweat"
		elseif pad then
			-- The local player: close by, the slime greets them and fidgets more often (SlimeFidget mood "near").
			local toYaw, toDist = 0, math.huge
			if detailed and frame.player then
				toYaw, toDist = yawTo(body, Vector3.new(ax, pos.Y, az), frame.player)
			end
			SlimeFidget.setMood(actor.fidget, if toDist < SlimeReact.NEAR then "near" else "idle", now, rand)
			local fp = SlimeFidget.step(actor.fidget, now, rand, actor.fidgetPose)
			local fidgeting = actor.fidget.kind ~= nil
			mods.lift += fp.lift
			mods.sx *= fp.sx
			mods.sy *= fp.sy
			mods.tilt += fp.tilt
			mods.roll += fp.roll
			if fp.yawWeight > 0 then
				mods.yaw, mods.yawWeight = fp.yaw, fp.yawWeight
			end
			if fp.spin ~= 0 then
				spin = fp.spin
			end
			mods.dx += actor.moveX * fp.carry
			mods.dz += actor.moveZ * fp.carry
			faceName = fp.face or faceName
			emote = fp.emote
			if fp.splat > 0 then
				Spring.kick(actor.squash, -fp.splat * SlimeActor.SQUASH.kick)
				if detailed and actor.splat then
					actor.splat:Emit(math.floor(4 + 3 * fp.splat))
				end
			end
			-- The local player: your own slime greets you (the "pick me" pose); anyone else's reacts by temperament.
			if detailed and frame.player and fp.yawWeight < 0.5 then
				local yaw, dist = toYaw, toDist
				if dist < SlimeActor.NEAR_DEAD_ZONE then
					yaw = actor.reactYaw
				else
					actor.reactYaw = yaw
				end
				local own = frame.userId ~= nil and model:GetAttribute("OwnerUserId") == frame.userId
				local r = SlimeReact.toPlayer(actor.persona.temper, dist, yaw, own, now, actor.reactPose)
				if r.weight > 0 then
					local keep = if fidgeting then 0.35 else 1
					-- watching is never a frozen stare: quick glances round you and a head tilt now and then
					local glance, headTilt = SlimeAttention.step(actor.attention, now, rand, r.weight)
					if r.weight * keep > mods.yawWeight then
						mods.yaw, mods.yawWeight = r.yaw, r.weight * keep
					end
					faceGlance = glance
					mods.roll += headTilt * keep
					mods.lift += r.lift * keep
					mods.sy *= 1 + (r.sy - 1) * keep
					mods.lean += math.clamp(r.lean, -SlimeActor.PAD_LEAN, SlimeActor.PAD_LEAN) * keep
					if not fidgeting then
						faceName = r.face or faceName
					end
					emote = emote or r.emote
				end
			end
		end
		-- Follow-through: rocks back as it sets off and forward as it stops (a hopper's hop has its own tilt).
		local fwd = (vx or 0) * look.X + (vz or 0) * look.Z
		local target = 0
		if dt > 0 and not g.air and (escaping or (wild and not riding and actor.persona.gait ~= "Hop")) then
			local a = (fwd - actor.fwd) / dt
			actor.accel += (a - actor.accel) * (1 - math.exp(-dt * 12))
			target = math.clamp(-actor.accel * SlimeActor.LEAN.gain, -SlimeActor.LEAN.max, SlimeActor.LEAN.max)
		else
			actor.accel = 0
		end
		actor.fwd = fwd
		local L = SlimeActor.LEAN
		mods.tilt += math.clamp(Spring.step(actor.lean, dt, target), -L.max, L.max)
		-- Jelly: the squash spring rings out after a kick (hops, put-downs, fidget landings).
		if g.landed > 0 then
			Spring.kick(actor.squash, -g.landed * SlimeActor.HOP_JELLY.land)
		end
		if g.launched > 0 then
			Spring.kick(actor.squash, g.launched * SlimeActor.HOP_JELLY.launch)
		end
		local S = SlimeActor.SQUASH
		local sq = math.clamp(Spring.step(actor.squash, dt, 0), -S.max, S.max)
		mods.sy *= 1 + sq
		mods.sx *= 1 / math.sqrt(math.max(0.5, 1 + sq))
		actor.visible = Vector3.new(pos.X + mods.dx, ay, pos.Z + mods.dz)
	end

	-- Frights, watching, bumps
	local since = now - actor.frightAt
	local jump = SlimeReact.startle(since)
	if jump > 0 then
		mods.lift += jump
		faceName = "surprised"
		emote = "alert"
	end
	local watchAt = actor.watchAt
	if watchAt and now < actor.watchUntil then
		local yaw = yawTo(body, actor.visible, watchAt)
		if wild and actor.speed > SlimeActor.MOVING then
			yaw = math.clamp(yaw, -2 * SlimeActor.GLANCE, 2 * SlimeActor.GLANCE)
		end
		mods.yaw, mods.yawWeight = yaw, 0.9
		if jump <= 0 and not g.air then
			faceName = actor.watchFace or faceName
		end
		emote = emote or (if actor.watchFace == "worried" then "dots" else "alert")
	elseif watchAt then
		actor.watchAt = nil
	end
	local b = now - actor.bumpAt
	if b >= 0 and b < SlimeActor.BUMP_SECONDS then
		mods.sy *= 1 - 0.22 * math.sin(math.pi * b / SlimeActor.BUMP_SECONDS)
		faceName = "surprised"
		emote = emote or "alert"
	end
	local h = now - actor.bumpedAt
	if h >= 0 and h < SlimeActor.BUMPED_SECONDS then
		mods.lift += 0.8 * math.sin(math.pi * h / SlimeActor.BUMPED_SECONDS)
		faceName = "surprised"
		emote = emote or "ask"
	end

	-- A hopper jumps nose first: while it squats and flies, look turns let go (a spin beat plays as given).
	if actor.persona.gait == "Hop" and wild then
		local want = if actor.gait.stage ~= "ground" then 1 else 0
		actor.airK += (want - actor.airK) * (1 - math.exp(-dt * SlimeActor.AIR_RATE))
		if math.abs(mods.yaw) <= math.pi + 1e-3 then
			mods.yawWeight *= 1 - SlimeActor.AIR_TURN * actor.airK
		end
	end

	-- Turn smoothly, the shortest way round and never faster than MAX_TURN. A spin (a turn past half a circle)
	-- plays as given.
	local k = 1 - math.exp(-dt * SlimeActor.TURN_RATE)
	-- the eyes lead: the face is already turned part of the way the body is still turning, and glances on its own
	local toGo = if math.abs(mods.yaw) > math.pi + 1e-3 then 0 else wrap(wrap(mods.yaw) - actor.yaw) * mods.yawWeight
	-- eased: a reaction starting or ending (or a new turn) moved the target by up to FACE_LEAD in one frame
	local leadTarget =
		math.clamp(toGo * SlimeActor.FACE_LEAD_SHARE + faceGlance, -SlimeActor.FACE_LEAD, SlimeActor.FACE_LEAD)
	actor.faceLead += (leadTarget - actor.faceLead) * (1 - math.exp(-dt * SlimeActor.FACE_LEAD_RATE))
	mods.faceLead = actor.faceLead
	if math.abs(mods.yaw) > math.pi + 1e-3 then
		actor.yaw, actor.yawWeight = mods.yaw, mods.yawWeight
	else
		local target = wrap(mods.yaw)
		local turn = if mods.yawWeight > 0.01 then wrap(target - actor.yaw) * k else 0
		local most = SlimeActor.MAX_TURN * dt
		actor.yaw = wrap(actor.yaw + math.clamp(turn, -most, most))
		actor.yawWeight += (mods.yawWeight - actor.yawWeight) * k
	end
	mods.yaw, mods.yawWeight = actor.yaw, actor.yawWeight
	mods.spin = spin

	face(mods, faceName)
	actor.emote = if detailed then emote else nil
	-- Where the slime stands this frame, its sideways lean included (SlimeSpacing keeps these apart).
	local right = body.CFrame.RightVector
	actor.visible =
		Vector3.new(pos.X + mods.dx + right.X * mods.lean, actor.visible.Y, pos.Z + mods.dz + right.Z * mods.lean)
end

-- After SlimeSpacing (the runner's second pass): adds the push that keeps this slime clear of its neighbours and
-- moves the tag after the drawn slime. Call once a frame after update.
function SlimeActor.settle(actor: Actor, pushX: number, pushZ: number, dt: number)
	local mods = actor.mods
	actor.pushX, actor.pushZ = pushX, pushZ
	mods.dx += pushX
	mods.dz += pushZ
	local pos = actor.motor.body.CFrame.Position
	local right = actor.motor.body.CFrame.RightVector
	local x, z = pos.X + mods.dx + right.X * mods.lean, pos.Z + mods.dz + right.Z * mods.lean
	actor.visible = Vector3.new(x, actor.visible.Y, z)
	local size = (actor.model:GetAttribute("Size") :: number?) or 1
	local lift = math.max(mods.lift - actor.hopLift, 0) * size
	if not actor.hasTag or dt <= 0 then
		Spring.reset(actor.tagX, x)
		Spring.reset(actor.tagZ, z)
		Spring.reset(actor.tagY, lift)
		actor.hasTag = true
	else
		Spring.step(actor.tagX, dt, x)
		Spring.step(actor.tagZ, dt, z)
		Spring.step(actor.tagY, dt, lift)
	end
	actor.tagOffset = Vector3.new(actor.tagX.y - pos.X, mods.dy + math.max(actor.tagY.y, 0), actor.tagZ.y - pos.Z)
end

function SlimeActor.frighten(actor: Actor, now: number, watch: Vector3, delay: number)
	actor.frightAt = now + delay
	actor.watchAt = watch
	actor.watchUntil = now + SlimeReact.WATCH_SECONDS
	actor.watchFace = "surprised"
end

function SlimeActor.watch(actor: Actor, at: Vector3, untilAt: number, faceName: string?)
	actor.watchAt = at
	actor.watchUntil = untilAt
	actor.watchFace = faceName
end

-- `hit` = this slime ran into the one ahead (else it was the one hit).
function SlimeActor.bump(actor: Actor, now: number, hit: boolean)
	if hit then
		actor.bumpAt = now
	else
		actor.bumpedAt = now
	end
end

function SlimeActor.release(actor: Actor)
	if actor.stringAt then
		actor.stringAt:Destroy()
	end
	if actor.feet then
		actor.feet:Destroy() -- with its splat emitter and the string beam
	end
	actor.feet, actor.splat, actor.stringAt, actor.string = nil, nil, nil, nil
end

return SlimeActor
