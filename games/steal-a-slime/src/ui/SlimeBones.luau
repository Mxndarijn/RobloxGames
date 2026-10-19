--!strict
--[[
	SlimeBones: client-side life for the Bones inside a species mesh
	(contract/slime-bones.md). The rig is shared/modeling-kit/models/_slimerig.py;
	the reference motion is kit/bl_slime_anim.py.

	Pose math (numbers only, no Roblox APIs):
	  SlimeBones.kind(name) -> Kind?             "Root" | "Top" | "Side" | "Eyes" | "Lids" | "Accessory"
	  SlimeBones.preset(name) -> Preset?         accessory preset by name prefix
	  SlimeBones.body(sy, H) -> topDy, bulge, sideDown
	  SlimeBones.tilt(params, t, hopDt) -> radians   Top wobble
	  SlimeBones.blink(now, blinkAt, hopDt) -> 0..1  1 = eyes closed
	  SlimeBones.accessory(preset, t, phase, air) -> radians

	Driver (CFrame / Vector3 at call time only), used by SlimeMotor:
	  SlimeBones.attach(mesh, now, rand) -> Rig?   nil when the mesh has no Bones
	  SlimeBones.step(rig, params, clock, pose, now, rand, extra?)   near tier, every frame
	  SlimeBones.squish(rig, sy)                   mid tier: body squash only
	  SlimeBones.release(rig)                      every Transform to identity (far tier, release)

	Every move is given in the Mesh's own space (Y up) and turned into each
	bone's rest frame once at attach, so a frame builds a CFrame or two per bone
	and allocates no tables. Directions (side push, eyes in, lids out, accessory
	axes) come from where each bone's part is drawn (drawnAt), so the mesh's
	import turn needs no special case; turns are about that point too.
	Slimes never hop on their own (contract/slime-walk.md): the hop terms
	(hopDt) only show on a hop forced through SlimeMotor's LifeForce hook.
]]

local SlimeLife = if script then require(script.Parent.SlimeLife) else require("./SlimeLife")

local SlimeBones = {}

export type Kind = "Root" | "Top" | "Side" | "Eyes" | "Lids" | "Accessory"
export type Preset = "Wing" | "Ear" | "Ant" | "Tail" | "Fin" | "Tent"

SlimeBones.TOP_AT = 0.45 -- Top bone height as a share of the body height H (_slimerig.build_rig)
SlimeBones.BULGE = 0.55 -- side push per unit of squash
SlimeBones.SIDE_DROP = 0.3 -- side drop per unit of squash
SlimeBones.EYE_IN = 0.13 -- studs at mesh scale 1, before the eye share
SlimeBones.LID_OUT = 0.165
SlimeBones.EYE_SHARE = 0.6 -- share of an Eyes / Lids move the eye vertices get (their skin weight)
SlimeBones.EYE_SHARE_ATTRIBUTE = "EyeShare"
SlimeBones.BLINK_TIME = 0.13
SlimeBones.BLINK_EVERY = { 2.5, 5.5 }
SlimeBones.AIR_CLOSED = { 0.15, 0.8 } -- share of the hop's air time with happy closed eyes
SlimeBones.TILT_GAIN = 1.2 -- Top wobble, times SlimeLife params.wobble
SlimeBones.HOP_TILT = 0.1 -- radians of extra Top wobble over a hop

local SIDES = { SideL = true, SideR = true, SideF = true, SideB = true }

-- Name prefix -> preset (no prefix starts another, so the order doesn't matter).
local PRESET_OF: { { string } } = {
	{ "Wing", "Wing" },
	{ "Ear", "Ear" },
	{ "Ant", "Ant" },
	{ "Tail", "Tail" },
	{ "Fin", "Fin" },
	{ "Pec", "Fin" },
	{ "Tent", "Tent" },
	{ "Ribbon", "Tent" },
	{ "Band", "Tent" },
	{ "Flame", "Tent" },
}

-- Per preset: amplitude (deg), extra amplitude in the air (deg), frequency (Hz),
-- phase offset (rad), phase multiplier, axis ("tang" | "up" | "ant").
type PresetSpec = { amp: number, air: number, hz: number, offset: number, mult: number, axis: string }
local PRESETS: { [string]: PresetSpec } = table.freeze({
	Wing = { amp = 28, air = 10, hz = 4, offset = 0, mult = 0, axis = "tang" },
	Ear = { amp = 10, air = 14, hz = 1.3, offset = -0.8, mult = 0, axis = "tang" },
	Ant = { amp = 14, air = 0, hz = 2, offset = 0, mult = 1, axis = "ant" },
	Tail = { amp = 22, air = 0, hz = 2, offset = 0, mult = 1.5, axis = "up" },
	Fin = { amp = 12, air = 0, hz = 1.6, offset = 0, mult = 1, axis = "tang" },
	Tent = { amp = 16, air = 0, hz = 1.5, offset = 0, mult = 2, axis = "tang" },
})
SlimeBones.PRESETS = PRESETS

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

function SlimeBones.preset(name: string): Preset?
	for _, pair in PRESET_OF do
		if string.sub(name, 1, #pair[1]) == pair[1] then
			return pair[2] :: any
		end
	end
	return nil
end

function SlimeBones.kind(name: string): Kind?
	if name == "Root" or name == "Top" or name == "Eyes" or name == "Lids" then
		return name :: any
	elseif SIDES[name] then
		return "Side"
	elseif SlimeBones.preset(name) then
		return "Accessory"
	end
	return nil
end

-- Squash `sy` (SlimeLife pose: < 1 flatter, > 1 taller) of a body `H` studs high:
-- how far Top moves up (negative = down), how far the sides push out and how far they drop.
function SlimeBones.body(sy: number, H: number): (number, number, number)
	local squash = (1 - sy) * H
	return -squash, squash * SlimeBones.BULGE, -squash * SlimeBones.SIDE_DROP
end

local function hopSpan(): number
	return SlimeLife.WINDUP + SlimeLife.AIR + SlimeLife.LAND
end

-- `hopDt` = now - clock.hopAt (negative during the wind-up).
function SlimeBones.tilt(params: SlimeLife.Params, t: number, hopDt: number): number
	local tilt = params.wobble * SlimeBones.TILT_GAIN * math.sin(t * params.wobbleSpeed * 0.8 + 0.5)
	local u = (hopDt + SlimeLife.WINDUP) / hopSpan()
	if u >= 0 and u <= 1 then
		tilt += SlimeBones.HOP_TILT * math.sin(u * 2 * math.pi)
	end
	return tilt
end

-- 0 = eyes open, 1 = closed: the blink starting at `blinkAt`, or happy closed eyes in the air.
function SlimeBones.blink(now: number, blinkAt: number, hopDt: number): number
	local amount = 0
	local dt = now - blinkAt
	if dt >= 0 and dt <= SlimeBones.BLINK_TIME then
		amount = math.sin(math.pi * dt / SlimeBones.BLINK_TIME) ^ 0.3
	end
	local a0, a1 = SlimeBones.AIR_CLOSED[1] * SlimeLife.AIR, SlimeBones.AIR_CLOSED[2] * SlimeLife.AIR
	if hopDt > a0 and hopDt < a1 then
		-- Short ramps so the eyes don't snap.
		amount = math.max(amount, smooth(math.min(hopDt - a0, a1 - hopDt) / 0.05))
	end
	return amount
end

function SlimeBones.accessory(preset: Preset, t: number, phase: number, air: number): number
	local spec = PRESETS[preset]
	if not spec then
		return 0
	end
	return math.rad(spec.amp + spec.air * air) * math.sin(t * 2 * math.pi * spec.hz + spec.offset + phase * spec.mult)
end

-- Driver ------------------------------------------------------------------

local KIND_TOP, KIND_SIDE, KIND_EYES, KIND_LIDS, KIND_ACC = 1, 2, 3, 4, 5

type Entry = {
	bone: Bone,
	kind: number,
	dir: Vector3, -- bone-local move direction (Top: up, Side: outward, Eyes: in, Lids: out)
	up: Vector3, -- bone-local up (sides drop along it)
	axis: Vector3, -- bone-local rotation axis (Top tilt, accessories)
	shift: Vector3, -- bone-local: where the part is drawn minus where the bone reports its pivot
	preset: Preset?,
	phase: number,
}

export type Rig = {
	mesh: BasePart,
	entries: { Entry },
	H: number,
	eyeIn: number, -- studs at full blink
	lidOut: number,
	blinkAt: number,
	full: boolean, -- eyes / accessories were posed since the last rest
}

type Rand = () -> number

local function between(range: { number }, rand: Rand): number
	return range[1] + rand() * (range[2] - range[1])
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function unitOr(v: Vector3, fallback: Vector3): Vector3
	return if v.Magnitude > 1e-4 then v.Unit else fallback
end

-- Where a bone's part is drawn, from the bone's reported rest position (Mesh space). Measured in
-- Studio on an uploaded species mesh: the reported positions are the drawn ones mirrored in Z and
-- not scaled with the Mesh Size, while a Transform moves the part in plain Mesh-space studs and
-- rotates it about the reported (unscaled, mirrored) position.
function SlimeBones.drawnAt(reported: Vector3, scale: number): Vector3
	return Vector3.new(reported.X, reported.Y, -reported.Z) * scale
end

-- A Transform turning by `rot` about where the part is drawn (`shift` = drawn - reported pivot,
-- all bone-local), after moving it by `move`.
local function turnAbout(rot: CFrame, shift: Vector3, move: Vector3): CFrame
	return CFrame.new(move + shift - rot * shift) * rot
end

-- The bone's rest frame in the mesh's space: its CFrame chain up to the mesh.
local function restFrame(bone: Bone, mesh: Instance): CFrame
	local frame = bone.CFrame
	local parent = bone.Parent
	while parent and parent ~= mesh and parent:IsA("Bone") do
		frame = parent.CFrame * frame
		parent = parent.Parent
	end
	return frame
end

local function readNumber(get: () -> any): number?
	local ok, value = pcall(get)
	return if ok and type(value) == "number" and value == value and value > 0 then value else nil
end

function SlimeBones.attach(mesh: BasePart, now: number, rand: Rand): Rig?
	local found: { { bone: Bone, kind: Kind, rest: CFrame } } = {}
	local byName: { [string]: CFrame } = {}
	for _, d in mesh:GetDescendants() do
		if d:IsA("Bone") then
			local kind = SlimeBones.kind(d.Name)
			d.Transform = CFrame.new()
			if kind then
				local rest = restFrame(d, mesh)
				byName[d.Name] = rest
				if kind ~= "Root" then
					table.insert(found, { bone = d, kind = kind, rest = rest })
				end
			end
		end
	end
	if #found == 0 then
		return nil
	end
	local up = Vector3.new(0, 1, 0)
	local scale = readNumber(function()
		return (mesh :: any).Size.Y / (mesh :: any).MeshSize.Y
	end) or 1
	local function drawn(name: string): Vector3?
		local rest = byName[name]
		return if rest then SlimeBones.drawnAt(rest.Position, scale) else nil
	end
	local top, root = drawn("Top"), drawn("Root")
	local H = if top then (top.Y - (if root then root.Y else 0)) / SlimeBones.TOP_AT else 0
	local faceAt = drawn("Eyes") or drawn("Lids")
	local front = unitOr(if faceAt then flat(faceAt) else Vector3.zero, Vector3.new(0, 0, 1))
	local lateral = unitOr(up:Cross(front), Vector3.new(1, 0, 0))
	local share = readNumber(function()
		return mesh:GetAttribute(SlimeBones.EYE_SHARE_ATTRIBUTE)
	end) or SlimeBones.EYE_SHARE

	local entries: { Entry } = {}
	for _, f in found do
		local rot = f.rest.Rotation
		local at = SlimeBones.drawnAt(f.rest.Position, scale)
		local outward = unitOr(flat(at), front)
		local tang = up:Cross(outward)
		local kind, dir, axis, preset = KIND_ACC, Vector3.zero, up, nil
		if f.kind == "Top" then
			kind, dir, axis = KIND_TOP, up, lateral
		elseif f.kind == "Side" then
			kind, dir = KIND_SIDE, outward
		elseif f.kind == "Eyes" then
			kind, dir = KIND_EYES, -outward
		elseif f.kind == "Lids" then
			kind, dir = KIND_LIDS, outward
		else
			preset = SlimeBones.preset(f.bone.Name)
			local spec = PRESETS[preset :: Preset]
			axis = if spec.axis == "up" then up elseif spec.axis == "ant" then unitOr(tang + front * 0.6, up) else tang
		end
		table.insert(entries, {
			bone = f.bone,
			kind = kind,
			dir = rot:VectorToObjectSpace(dir),
			up = rot:VectorToObjectSpace(up),
			axis = rot:VectorToObjectSpace(unitOr(axis, up)),
			shift = rot:VectorToObjectSpace(at - f.rest.Position),
			preset = preset,
			phase = math.atan2(at.Z, at.X),
		})
	end
	return {
		mesh = mesh,
		entries = entries,
		H = H,
		eyeIn = SlimeBones.EYE_IN * scale / share,
		lidOut = SlimeBones.LID_OUT * scale / share,
		blinkAt = now + rand() * SlimeBones.BLINK_EVERY[2],
		full = false,
	}
end

local function writeBody(entry: Entry, topDy: number, bulge: number, drop: number, tilt: number)
	if entry.kind == KIND_TOP then
		entry.bone.Transform = turnAbout(CFrame.fromAxisAngle(entry.axis, tilt), entry.shift, entry.dir * topDy)
	elseif entry.kind == KIND_SIDE then
		entry.bone.Transform = CFrame.new(entry.dir * bulge + entry.up * drop)
	end
end

-- Extra life from contract/slime-life.md (ui/SlimeGait, SlimeBeats, SlimeReact), all optional:
-- air 0..1 (a gait hop), vy (its vertical speed, studs / s: ears flop), jiggle (Top crown lag, radians, + = forward),
-- closed 0..1 (lids shut: happy, asleep, squeeze), pop 0..1 (eyes bulge out: surprised).
export type Extra = { air: number?, vy: number?, jiggle: number?, closed: number?, pop: number? }

SlimeBones.POP_OUT = 0.5 -- share of the blink depth the eyes bulge out by at pop = 1
SlimeBones.EAR_FLOP = 0.06 -- radians of ear flop per stud / s of falling speed
SlimeBones.EAR_FLOP_MAX = 1.1

-- Extra ear angle from the vertical speed: the ears fly up while the slime falls.
function SlimeBones.earFlop(vy: number): number
	return math.clamp(-vy * SlimeBones.EAR_FLOP, -0.3, SlimeBones.EAR_FLOP_MAX)
end

function SlimeBones.step(
	rig: Rig,
	params: SlimeLife.Params,
	clock: SlimeLife.Clock,
	pose: SlimeLife.Pose,
	now: number,
	rand: Rand,
	extra: Extra?
)
	rig.full = true
	if now > rig.blinkAt + SlimeBones.BLINK_TIME then
		rig.blinkAt = now + between(SlimeBones.BLINK_EVERY, rand)
	end
	local t = now + clock.phase
	local hopDt = now - clock.hopAt
	local air = if hopDt > 0 and hopDt < SlimeLife.AIR then 1 else 0
	local topDy, bulge, drop = SlimeBones.body(pose.sy, rig.H)
	local tilt = SlimeBones.tilt(params, t, hopDt)
	local closed = SlimeBones.blink(now, rig.blinkAt, hopDt)
	local pop, flop = 0, 0
	if extra then
		air = math.max(air, extra.air or 0)
		tilt += extra.jiggle or 0
		closed = math.max(closed, extra.closed or 0)
		pop = math.clamp(extra.pop or 0, 0, 1) * (1 - closed)
		flop = SlimeBones.earFlop(extra.vy or 0)
	end
	for _, entry in rig.entries do
		local kind = entry.kind
		if kind == KIND_ACC then
			local angle = SlimeBones.accessory(entry.preset :: Preset, t, entry.phase, air)
			if entry.preset == "Ear" then
				angle += flop
			end
			entry.bone.Transform = turnAbout(CFrame.fromAxisAngle(entry.axis, angle), entry.shift, Vector3.zero)
		elseif kind == KIND_EYES then
			entry.bone.Transform = CFrame.new(entry.dir * (rig.eyeIn * (closed - SlimeBones.POP_OUT * pop)))
		elseif kind == KIND_LIDS then
			entry.bone.Transform = CFrame.new(entry.dir * (rig.lidOut * closed))
		else
			writeBody(entry, topDy, bulge, drop, tilt)
		end
	end
end

-- Mid LOD tier: only the body squash; eyes and accessories go back to rest once.
function SlimeBones.squish(rig: Rig, sy: number)
	local topDy, bulge, drop = SlimeBones.body(sy, rig.H)
	local calm = rig.full
	rig.full = false
	for _, entry in rig.entries do
		if entry.kind == KIND_TOP or entry.kind == KIND_SIDE then
			writeBody(entry, topDy, bulge, drop, 0)
		elseif calm then
			entry.bone.Transform = CFrame.new()
		end
	end
end

function SlimeBones.release(rig: Rig)
	for _, entry in rig.entries do
		entry.bone.Transform = CFrame.new()
	end
	rig.full = false
end

return SlimeBones
