--!strict
--[[
	SlimeMotor (v28 #17): procedural life for a RIGGED slime, driven by the
	Motor6Ds of src/visuals/shared/SlimeRig. This is the default motion
	(Config.FEATURES.SlimeAnimations = false) and the fallback whenever the
	uploaded animations don't load. No asset, no Animator.

	  SlimeMotor.attach(model, now, rand) -> Motor?   nil unless Body + both Motor6Ds
	  SlimeMotor.step(motor, now, rand) -> boolean    true on the frame a hop lands
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
]]

local SlimeLife = if script then require(script.Parent.SlimeLife) else require("./SlimeLife")

local SlimeMotor = {}

SlimeMotor.FACE = "FaceRoot"
SlimeMotor.SKIN_ROOT = "SkinRoot"
SlimeMotor.SKIN = "Mesh" -- SlimeMesh.MESH_NAME
SlimeMotor.SQUASH = "LifeSquash"
SlimeMotor.SKIN_SIZE_ATTRIBUTE = "LifeSkinSize"
SlimeMotor.FORCE_ATTRIBUTE = "LifeForce" -- client-only test hook (pc-watcher slime_motion): a kind to play now
SlimeMotor.MODE_ATTRIBUTE = "LifeMode"

export type Motor = {
	model: Model,
	body: BasePart,
	face: Motor6D,
	skinJoint: Motor6D,
	skin: MeshPart?,
	skinSize: Vector3?,
	squash: SpecialMesh?,
	params: SlimeLife.Params,
	clock: SlimeLife.Clock,
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
	if skin then
		model:SetAttribute(SlimeMotor.SKIN_SIZE_ATTRIBUTE, skin.Size)
	end
	return {
		model = model,
		body = body,
		face = face,
		skinJoint = skinJoint,
		skin = skin,
		skinSize = if skin then skin.Size else nil,
		squash = squash,
		params = params,
		clock = SlimeLife.newClock(params, now, rand),
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

function SlimeMotor.step(motor: Motor, now: number, rand: Rand): boolean
	local forced = motor.model:GetAttribute(SlimeMotor.FORCE_ATTRIBUTE)
	if type(forced) == "string" then
		motor.model:SetAttribute(SlimeMotor.FORCE_ATTRIBUTE, nil)
		SlimeMotor.force(motor, forced, now)
	end
	local landed = SlimeLife.advance(motor.clock, motor.params, now, rand)
	local pose = SlimeLife.pose(motor.params, motor.clock, now)
	local size = (motor.model:GetAttribute("Size") :: number?) or 1
	local r = motor.body.Size.Y / 2
	local lift = pose.lift * size
	-- Rock and turn around the bottom centre; the squashed centre sits r * sy up.
	local transform = CFrame.new(0, -r + lift, 0)
		* CFrame.Angles(0, pose.yaw, 0)
		* CFrame.Angles(pose.pitch, 0, pose.roll)
		* CFrame.new(0, r * pose.sy, 0)
	motor.face.Transform = transform
	motor.skinJoint.Transform = transform
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

function SlimeMotor.release(motor: Motor)
	motor.face.Transform = CFrame.new()
	motor.skinJoint.Transform = CFrame.new()
	if motor.skin and motor.skinSize then
		motor.skin.Size = motor.skinSize
	end
	if motor.squash then
		motor.squash:Destroy()
	end
	motor.model:SetAttribute(SlimeMotor.SKIN_SIZE_ATTRIBUTE, nil)
end

return SlimeMotor
