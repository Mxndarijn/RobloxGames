--!strict
--[[
	SlimeRig (owner: Archer): the skeleton of a slime Model, so Animators can
	play on it (v28 #17, v28-ALIVE-NEEDS.md).

	SlimeRig.attach(model, body)
	  Adds two small invisible parts, FaceRoot and SkinRoot, each joined to Body
	  by a Motor6D of the same name (Part0 Body, Part1 the root, identity C0/C1
	  at Body's pivot) and an AnimationController + Animator. Eyes and mouth
	  move onto FaceRoot, every other decoration onto SkinRoot (their
	  WeldConstraint now holds them to that root, not to Body). The animations
	  move both roots with the same Transform, so face and skin stay together;
	  Body never moves (anchored, PrimaryPart, prompt and raycast target).
	SlimeRig.anchorFor(model, body) -> BasePart
	  What a later-added skin (SlimeMesh's Mesh / Accessory) welds to.
	SlimeRig.isRigged(model) -> boolean
	SlimeRig.animator(model) -> Animator?

	Pet clones are undone by src/visuals/client/PetRig.stripLife.
]]

local SlimeRig = {}

SlimeRig.FACE_ROOT = "FaceRoot"
SlimeRig.SKIN_ROOT = "SkinRoot"
SlimeRig.CONTROLLER = "AnimationController"
SlimeRig.ANIMATOR = "Animator"

local FACE_PREFIXES = { "Eye", "Pupil", "Mouth", "Smile", "Cheek", "Lash", "Brow", "Tongue" }

function SlimeRig.isFacePart(name: string): boolean
	for _, prefix in FACE_PREFIXES do
		if string.sub(name, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

local function makeRoot(name: string, body: BasePart): Part
	local root = Instance.new("Part")
	root.Name = name
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.CFrame = body.CFrame
	root.Transparency = 1
	root.CastShadow = false
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Massless = true
	root.Anchored = false
	return root
end

local function joint(body: BasePart, root: BasePart)
	local motor = Instance.new("Motor6D")
	motor.Name = root.Name
	motor.Part0 = body
	motor.Part1 = root
	motor.Parent = body
end

function SlimeRig.attach(model: Model, body: BasePart)
	local face = makeRoot(SlimeRig.FACE_ROOT, body)
	local skin = makeRoot(SlimeRig.SKIN_ROOT, body)
	face.Parent = model
	skin.Parent = model
	joint(body, face)
	joint(body, skin)
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child ~= body and child ~= face and child ~= skin then
			for _, weld in child:GetChildren() do
				if weld:IsA("WeldConstraint") and weld.Part0 == body then
					weld.Part0 = if SlimeRig.isFacePart(child.Name) then face else skin
				end
			end
		end
	end
	local controller = Instance.new("AnimationController")
	controller.Name = SlimeRig.CONTROLLER
	local animator = Instance.new("Animator")
	animator.Name = SlimeRig.ANIMATOR
	animator.Parent = controller
	controller.Parent = model
end

function SlimeRig.isRigged(model: Instance): boolean
	return model:FindFirstChild(SlimeRig.FACE_ROOT) ~= nil
		and model:FindFirstChild(SlimeRig.SKIN_ROOT) ~= nil
		and SlimeRig.animator(model) ~= nil
end

function SlimeRig.animator(model: Instance): Animator?
	local controller = model:FindFirstChild(SlimeRig.CONTROLLER)
	local animator = controller and controller:FindFirstChild(SlimeRig.ANIMATOR)
	return if animator and animator:IsA("Animator") then animator else nil
end

function SlimeRig.anchorFor(model: Instance, body: BasePart): BasePart
	local skin = model:FindFirstChild(SlimeRig.SKIN_ROOT)
	return if skin and skin:IsA("BasePart") then skin else body
end

return SlimeRig
