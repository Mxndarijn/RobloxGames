--!strict
--[[
	SlimeMotor (v28 #17): procedural life for a RIGGED slime, driven by the
	Motor6Ds of src/visuals/shared/SlimeRig. This is the default motion
	(Config.FEATURES.SlimeAnimations = false) and the fallback whenever the
	uploaded animations don't load. No asset, no Animator.

	  SlimeMotor.attach(model, now, rand) -> Motor?   nil unless Body + both Motor6Ds
	  SlimeMotor.step(motor, now, rand, mods?) -> boolean    true on the frame a forced hop lands;
	                                                  mods = gait / beat / reaction life (contract/slime-life.md)
	  SlimeMotor.force(motor, kind, now)              "Hop" | "LookLeft" | "LookRight"
	  SlimeMotor.release(motor)                       Transforms identity, Size back

	Per frame: SlimeLife.pose -> ONE Transform written to both FaceRoot and
	SkinRoot (so face and skin stay together; hop lift, look yaw, wobble) plus
	the squash: the "Mesh" skin's Size, or a local SpecialMesh on a Ball Body.
	Body never moves (anchored, PrimaryPart, prompt, raycast target).
	Releasing is exact: Transform = identity, the skin Size restored, the
	LifeSquash mesh gone. The skin's original Size sits in the model attribute
	"LifeSkinSize" while it is squashed, so PetRig can restore a clone taken
	mid-squash.

	A species mesh with Bones (contract/slime-bones.md) keeps its Size: SlimeBones
	squashes and stretches it through the Top / Side bones, blinks and moves the
	accessories, and the Transform drops the squashed-centre offset.
]]

local SlimeBones = if script then require(script.Parent.SlimeBones) else require("./SlimeBones")
local SlimeLife = if script then require(script.Parent.SlimeLife) else require("./SlimeLife")

local SlimeMotor = {}

SlimeMotor.FACE = "FaceRoot"
SlimeMotor.SKIN_ROOT = "SkinRoot"
SlimeMotor.SKIN = "Mesh" -- SlimeMesh.MESH_NAME
SlimeMotor.SQUASH = "LifeSquash"
SlimeMotor.SKIN_SIZE_ATTRIBUTE = "LifeSkinSize"
SlimeMotor.FORCE_ATTRIBUTE = "LifeForce" -- client-only test hook (pc-watcher slime_motion): a kind to play now
SlimeMotor.MODE_ATTRIBUTE = "LifeMode"

-- Extra life on top of the idle pose (contract/slime-life.md), built by SlimeLifeRunner from ui/SlimeGait,
-- SlimeBeats and SlimeReact. dx / dz: world studs from the Body to the visible slime; lift: studs at size 1;
-- yaw: target turn from the heading (+ = left), taken by yawWeight 0..1; tilt (+ = nose down) and roll
-- (+ = lean right): radians; sx / sy: squash multipliers; lean: studs sideways (+ = right); jiggle, air, vy, closed,
-- pop: SlimeBones.Extra.
export type Mods = {
	dx: number,
	dz: number,
	lift: number,
	yaw: number,
	yawWeight: number,
	tilt: number,
	roll: number,
	sx: number,
	sy: number,
	lean: number,
	jiggle: number,
	air: number,
	vy: number,
	closed: number,
	pop: number,
}

SlimeMotor.SQUASH_LIMIT = { 0.45, 1.5 } -- sy with Mods (hops splat and stretch further than breathing)

function SlimeMotor.newMods(): Mods
	return {
		dx = 0,
		dz = 0,
		lift = 0,
		yaw = 0,
		yawWeight = 0,
		tilt = 0,
		roll = 0,
		sx = 1,
		sy = 1,
		lean = 0,
		jiggle = 0,
		air = 0,
		vy = 0,
		closed = 0,
		pop = 0,
	}
end

export type Motor = {
	model: Model,
	body: BasePart,
	face: Motor6D,
	skinJoint: Motor6D,
	skin: MeshPart?,
	skinSize: Vector3?,
	bodySize: Vector3, -- Body's size when skinSize was measured
	squash: SpecialMesh?,
	bones: SlimeBones.Rig?, -- the skin's Bones drive the squash instead of its Size
	params: SlimeLife.Params,
	clock: SlimeLife.Clock,
	pose: SlimeLife.Pose, -- scratch, reused every frame
	parked: boolean, -- far LOD tier: Transforms already reset, nothing written until it wakes
}

type Rand = () -> number

local function motorOf(body: BasePart, name: string): Motor6D?
	local m = body:FindFirstChild(name)
	return if m and m:IsA("Motor6D") and m.Part0 == body then m else nil
end

function SlimeMotor.attach(model: Model, now: number, rand: Rand): Motor?
	local body = model.PrimaryPart or model:FindFirstChild("Body")
	if not (body and body:IsA("BasePart")) then
		return nil
	end
	local face, skinJoint = motorOf(body, SlimeMotor.FACE), motorOf(body, SlimeMotor.SKIN_ROOT)
	if not (face and skinJoint) then
		return nil
	end
	local params = SlimeLife.params(model:GetAttribute("Tier") :: number?, model:GetAttribute("State") :: string?)
	local skinPart = model:FindFirstChild(SlimeMotor.SKIN)
	local skin: MeshPart? = if skinPart and skinPart:IsA("MeshPart") then skinPart else nil
	local squash: SpecialMesh? = nil
	if
		not skin
		and body:IsA("Part")
		and body.Shape == Enum.PartType.Ball
		and body.Transparency < 1
		and not body:FindFirstChildWhichIsA("DataModelMesh")
	then
		local mesh = Instance.new("SpecialMesh")
		mesh.Name = SlimeMotor.SQUASH
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = body
		squash = mesh
	end
	local bones = if skin then SlimeBones.attach(skin, now, rand) else nil
	if skin and not bones then
		model:SetAttribute(SlimeMotor.SKIN_SIZE_ATTRIBUTE, skin.Size)
	end
	return {
		model = model,
		body = body,
		face = face,
		skinJoint = skinJoint,
		skin = skin,
		skinSize = if skin then skin.Size else nil,
		bodySize = body.Size,
		squash = squash,
		bones = bones,
		params = params,
		clock = SlimeLife.newClock(params, now, rand),
		pose = { lift = 0, yaw = 0, pitch = 0, roll = 0, sx = 1, sy = 1, sz = 1 },
		parked = false,
	}
end

-- Plays `kind` now: a hop starts its squat, a look turns to the side.
function SlimeMotor.force(motor: Motor, kind: string, now: number)
	local clock, params = motor.clock, motor.params
	if kind == "Hop" then
		clock.hopAt = now + SlimeLife.WINDUP
	elseif kind == "LookLeft" or kind == "LookRight" then
		clock.lookFrom = SlimeLife.lookYaw(clock, now)
		clock.lookTo = (if kind == "LookLeft" then 1 else -1) * params.lookYaw
		clock.lookAt = now
		clock.nextLook = now + SlimeLife.LOOK_TIME + params.lookEvery[1]
	end
end

function SlimeMotor.step(motor: Motor, now: number, rand: Rand, mods: Mods?): boolean
	local forced = motor.model:GetAttribute(SlimeMotor.FORCE_ATTRIBUTE)
	if type(forced) == "string" then
		motor.model:SetAttribute(SlimeMotor.FORCE_ATTRIBUTE, nil)
		SlimeMotor.force(motor, forced, now)
	end
	local landed = SlimeLife.advance(motor.clock, motor.params, now, rand)
	motor.parked = false
	local pose = SlimeLife.pose(motor.params, motor.clock, now, motor.pose)
	local offset = Vector3.zero
	if mods then
		pose.lift += mods.lift
		pose.yaw += (mods.yaw - pose.yaw) * math.clamp(mods.yawWeight, 0, 1)
		pose.pitch -= mods.tilt -- a turn about +X lifts the nose
		pose.roll -= mods.roll -- a turn about +Z leans left
		pose.sy = math.clamp(pose.sy * mods.sy, SlimeMotor.SQUASH_LIMIT[1], SlimeMotor.SQUASH_LIMIT[2])
		pose.sx *= mods.sx
		pose.sz *= mods.sx
		offset = motor.body.CFrame:VectorToObjectSpace(Vector3.new(mods.dx, 0, mods.dz)) + Vector3.new(mods.lean, 0, 0)
		offset = Vector3.new(offset.X, 0, offset.Z)
	end
	local size = (motor.model:GetAttribute("Size") :: number?) or 1
	local r = motor.body.Size.Y / 2
	local lift = pose.lift * size
	local bones = motor.bones
	-- Rock and turn around the bottom centre; the squashed centre sits r * sy up
	-- (bones squash the mesh from its foot, so a boned skin keeps its centre).
	local transform = CFrame.new(offset.X, -r + lift, offset.Z)
		* CFrame.Angles(0, pose.yaw, 0)
		* CFrame.Angles(pose.pitch, 0, pose.roll)
		* CFrame.new(0, if bones then r else r * pose.sy, 0)
	motor.face.Transform = transform
	motor.skinJoint.Transform = transform
	if bones then
		SlimeBones.step(bones, motor.params, motor.clock, pose, now, rand, mods)
		return landed
	end
	local scale = Vector3.new(pose.sx, pose.sy, pose.sz)
	if motor.skin and motor.skinSize then
		motor.skin.Size = motor.skinSize * scale
	end
	if motor.squash then
		motor.squash.Scale = scale
		motor.squash.Offset = Vector3.new(0, lift - r * (1 - pose.sy), 0)
	end
	return landed
end

-- LOD mid tier: idle squish only (no hop, look or wobble), `amp` times the normal amplitude.
-- The caller decides how often (every Nth frame); the bottom stays on the ground.
function SlimeMotor.stepSquish(motor: Motor, now: number, amp: number)
	motor.parked = false
	local sy = SlimeLife.squishY(motor.params, motor.clock, now, amp)
	if motor.bones then
		motor.face.Transform = CFrame.new()
		motor.skinJoint.Transform = CFrame.new()
		SlimeBones.squish(motor.bones, sy)
		return
	end
	local sxz = 1 / math.sqrt(sy)
	local r = motor.body.Size.Y / 2
	local transform = CFrame.new(0, r * (sy - 1), 0)
	motor.face.Transform = transform
	motor.skinJoint.Transform = transform
	local scale = Vector3.new(sxz, sy, sxz)
	if motor.skin and motor.skinSize then
		motor.skin.Size = motor.skinSize * scale
	end
	if motor.squash then
		motor.squash.Scale = scale
		motor.squash.Offset = Vector3.new(0, -r * (1 - sy), 0)
	end
end

local function rest(motor: Motor)
	motor.face.Transform = CFrame.new()
	motor.skinJoint.Transform = CFrame.new()
	if motor.bones then
		SlimeBones.release(motor.bones)
	elseif motor.skin and motor.skinSize then
		-- at the model's current scale: the server may have rescaled it since attach
		motor.skin.Size = motor.skinSize * (motor.body.Size.Y / math.max(motor.bodySize.Y, 1e-6))
	end
	if motor.squash then
		motor.squash.Scale = Vector3.one
		motor.squash.Offset = Vector3.zero
	end
end

-- LOD far tier: back to the exact rest pose once, then a no-op until a step wakes it.
-- Returns true on the call that wrote.
function SlimeMotor.park(motor: Motor): boolean
	if motor.parked then
		return false
	end
	motor.parked = true
	rest(motor)
	return true
end

function SlimeMotor.release(motor: Motor)
	rest(motor)
	if motor.squash then
		motor.squash:Destroy()
	end
	motor.model:SetAttribute(SlimeMotor.SKIN_SIZE_ATTRIBUTE, nil)
end

return SlimeMotor
