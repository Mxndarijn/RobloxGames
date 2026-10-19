--!strict
--[[
	SlimeActor (contract/slime-life.md): the life of one animated slime on top
	of SlimeMotor's idle pose, for SlimeLifeRunner's near LOD tier. Each frame
	it combines
	  ui/SlimeGait    its species gait (real hops, surges, waddles, hovering)
	  ui/SlimeBeats   the lane beat its ParadeChoreo plan says it is in
	  ui/SlimeReact   how it reacts to the local player, nerves, frights
	into one SlimeMotor.Mods, picks an emote, and plays the hop effects (a goo
	splat on landing, a goo string on take-off). Client-only; reads the model's
	replicated attributes, never decides anything.

	  SlimeActor.attach(model, motor, now) -> Actor
	  SlimeActor.update(actor, frame, now, serverNow, rand)   fills actor.mods / emote
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
local SlimeBeats = require(script.Parent:WaitForChild("SlimeBeats"))
local SlimeGait = require(script.Parent:WaitForChild("SlimeGait"))
local SlimeMotor = require(script.Parent:WaitForChild("SlimeMotor"))
local SlimePersona = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SlimePersona"))
local SlimeReact = require(script.Parent:WaitForChild("SlimeReact"))

local SlimeActor = {}

SlimeActor.NERVES_LOOK_DISTANCE = 26 -- studs: a nervous slime looks back at a player this close
SlimeActor.BUMP_SECONDS = 0.35
SlimeActor.BUMPED_SECONDS = 0.5
-- Face -> bones: lids shut (closed) or eyes bulging (pop), SlimeBones.Extra.
local FACES: { [string]: { closed: number, pop: number } } = table.freeze({
	happy = { closed = 1, pop = 0 },
	asleep = { closed = 1, pop = 0 },
	squeeze = { closed = 1, pop = 0 },
	sleepy = { closed = 0.6, pop = 0 },
	smug = { closed = 0.5, pop = 0 },
	dizzy = { closed = 0.5, pop = 0 },
	angry = { closed = 0.35, pop = 0 },
	focus = { closed = 0.3, pop = 0 },
	surprised = { closed = 0, pop = 1 },
	excited = { closed = 0, pop = 0.8 },
	worried = { closed = 0, pop = 0.4 },
} :: any)
local GOO = Color3.fromRGB(ParadeLane.COLOR[1], ParadeLane.COLOR[2], ParadeLane.COLOR[3])

-- What the runner measures once per frame for every actor.
export type Frame = {
	player: Vector3?, -- the local character's root position
	cash: number?, -- leaderstats Cash
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
}

local function rootOf(motor: SlimeMotor.Motor): BasePart?
	local p = motor.skinJoint.Part1
	return if p and p:IsA("BasePart") then p else nil
end

local function effects(actor: Actor)
	if actor.feet or actor.persona.gait ~= "Hop" then
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

function SlimeActor.attach(model: Model, motor: SlimeMotor.Motor, now: number): Actor
	local species = model:GetAttribute(Constants.SPECIES_ATTRIBUTE)
	local persona = SlimePersona.of(if type(species) == "string" then species else nil)
	local p = motor.body.Position
	local actor: Actor = {
		model = model,
		motor = motor,
		persona = persona,
		gait = SlimeGait.new(p.X, p.Z, now, math.random() * 2 * math.pi),
		gaitPose = {} :: any,
		beatPose = {} :: any,
		reactPose = {} :: any,
		mods = SlimeMotor.newMods(),
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
	}
	effects(actor)
	return actor
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
	local startAt, seconds, lead = ParadeLane.walkTimes(at, untilAt)
	local key = `{seed}|{at}|{untilAt}`
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

-- Yaw from the slime's heading to world point `at` (+ = left).
local function yawTo(body: BasePart, from: Vector3, at: Vector3): (number, number)
	local rel = body.CFrame:VectorToObjectSpace(at - from)
	local flat = Vector3.new(rel.X, 0, rel.Z)
	return math.atan2(-rel.X, -rel.Z), flat.Magnitude
end

function SlimeActor.update(actor: Actor, frame: Frame, now: number, serverNow: number, rand: () -> number)
	local model, body, mods = actor.model, actor.motor.body, actor.mods
	local pos = body.Position
	local look = body.CFrame.LookVector
	local state = model:GetAttribute("State")
	local wild = state == "Wild"
	local riding = model:GetAttribute(Constants.RIDING_ATTRIBUTE) == true

	-- Gait (frozen to the anchor while it rides the slide)
	local g = actor.gaitPose
	if riding then
		actor.gait = SlimeGait.new(pos.X, pos.Z, now, actor.gait.phase)
	end
	SlimeGait.step(actor.gait, actor.persona, pos.X, pos.Z, look.X, look.Z, now, rand, g)
	if riding then
		g.dx, g.dz, g.lift, g.sx, g.sy, g.tilt, g.roll = 0, 0, 0, 1, 1, 0, 0
	end
	mods.dx, mods.dz, mods.lift = g.dx, g.dz, g.lift
	mods.sx, mods.sy, mods.tilt, mods.roll = g.sx, g.sy, g.tilt, g.roll
	mods.jiggle = g.jiggle
	mods.air = if g.air then 1 else 0
	mods.vy = g.vy
	mods.yaw, mods.yawWeight, mods.lean = 0, 0, 0
	mods.closed, mods.pop = 0, 0
	local faceName: string? = g.face
	local emote: string? = nil
	actor.visible = Vector3.new(pos.X + g.dx, pos.Y, pos.Z + g.dz)
	actor.speed = math.sqrt(actor.gait.vx ^ 2 + actor.gait.vz ^ 2)
	if g.landed > 0 and actor.splat then
		actor.splat:Emit(math.max(3, math.floor(6 * g.landed + 0.5)))
	end
	if actor.string and actor.stringAt then
		local on = g.stringX ~= nil and g.stringAlpha > 0
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
			local beat, phase, u = ParadeChoreo.beatAt(plan, serverNow - startAt)
			if beat then
				local b = SlimeBeats.pose(beat.kind, phase, u, beat.side, now, actor.beatPose)
				standing = phase == "stop"
				if b.yaw then
					mods.yaw, mods.yawWeight = b.yaw, 1
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
				mods.lift += 0.25 * math.abs(math.sin(now * 11)) * k
				local player = frame.player
				local yaw, dist = 0, math.huge
				if player then
					yaw, dist = yawTo(body, actor.visible, player)
				end
				if dist < SlimeActor.NERVES_LOOK_DISTANCE then
					mods.yaw, mods.yawWeight = yaw, math.max(mods.yawWeight, 0.7 * k)
				else
					mods.yaw, mods.yawWeight = math.pi * 0.8, math.max(mods.yawWeight, 0.5 * k)
				end
			end
		end
	end

	-- The local player
	if wild and not riding and frame.player then
		local yaw, dist = yawTo(body, actor.visible, frame.player)
		local price = model:GetAttribute("Price")
		local afford = frame.cash ~= nil and (type(price) ~= "number" or price <= (frame.cash :: number))
		local r = SlimeReact.toPlayer(actor.persona.temper, dist, yaw, afford, now, actor.reactPose)
		if r.weight > 0 then
			local keep = if standing then 0.35 else 1 -- a beat in progress mostly wins
			if r.weight * keep > mods.yawWeight then
				mods.yaw, mods.yawWeight = r.yaw, r.weight * keep
			end
			mods.lift += r.lift * keep
			mods.sy *= 1 + (r.sy - 1) * keep
			mods.lean += r.lean * keep
			if not standing and not g.air then
				faceName = r.face or faceName
			end
			emote = emote or r.emote
		end
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

	face(mods, faceName)
	actor.emote = emote
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
