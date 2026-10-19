--!strict
-- FollowPets clones of a living slime (#71) must lose the life rig and get
-- their factory welds back (src/visuals/client/PetRig.luau).
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local PetRig = UiHarness.ui("../visuals/client/PetRig")
local new = UiHarness.Instance.new
local CFrame = (require("@lune/roblox") :: any).CFrame

-- A slime as SlimeLifeRunner leaves it: LifeRoot + welds + sparkle, LifeSquash
-- on Body, factory WeldConstraint disabled.
local function livingSlime(): any
	local model = new("Model")
	local body = new("Part")
	body.Name = "Body"
	body.Parent = model
	local squash = new("SpecialMesh")
	squash.Name = "LifeSquash"
	squash.Parent = body
	local eye = new("Part")
	eye.Name = "Eye"
	eye.Parent = model
	local constraint = new("WeldConstraint")
	constraint.Part0 = body
	constraint.Part1 = eye
	constraint.Enabled = false
	constraint.Parent = eye
	local root = new("Part")
	root.Name = "LifeRoot"
	root.Parent = model
	local lifeWeld = new("Weld")
	lifeWeld.Name = "LifeWeld"
	lifeWeld.Parent = root
	local sparkle = new("ParticleEmitter")
	sparkle.Name = "LifeSparkle"
	sparkle.Parent = root
	return model
end

describe("PetRig.stripLife", function()
	it("removes LifeRoot, LifeSquash and the sparkle, and re-enables welds", function()
		local pet = livingSlime():Clone()
		PetRig.stripLife(pet)
		expect(UiHarness.find(pet, "LifeRoot")).toBeNil()
		expect(UiHarness.find(pet, "LifeSquash")).toBeNil()
		expect(UiHarness.find(pet, "LifeSparkle")).toBeNil()
		expect(UiHarness.find(pet, "LifeWeld")).toBeNil()
		local welds = 0
		for _, inst in UiHarness.descendants(pet) do
			if inst:IsA("WeldConstraint") then
				welds += 1
				expect(inst.Enabled).toBe(true)
			end
		end
		expect(welds).toBe(1)
		expect(UiHarness.find(pet, "Body") ~= nil).toBe(true)
	end)

	it("leaves a slime without a life rig untouched", function()
		local model = new("Model")
		local part = new("Part")
		part.Name = "Body"
		part.Parent = model
		PetRig.stripLife(model)
		expect(#model:GetChildren()).toBe(1)
	end)
end)

-- A rigged slime (src/visuals/shared/SlimeRig) mid-animation: Animator, a
-- moved Motor6D and the animated sparkle under SkinRoot.
local function animatedSlime(): any
	local model = new("Model")
	local body = new("Part")
	body.Name = "Body"
	body.Parent = model
	local skin = new("Part")
	skin.Name = "SkinRoot"
	skin.Parent = model
	local motor = new("Motor6D")
	motor.Name = "SkinRoot"
	motor.Part0 = body
	motor.Part1 = skin
	motor.Transform = CFrame.new(0, 0.9, 0) :: any
	motor.Parent = body
	local controller = new("AnimationController")
	controller.Name = "AnimationController"
	controller.Parent = model
	local animator = new("Animator")
	animator.Name = "Animator"
	animator.Parent = controller
	local sparkle = new("ParticleEmitter")
	sparkle.Name = "LifeSparkle"
	sparkle.Parent = skin
	return model
end

describe("PetRig.stripLife on a rigged, animated slime", function()
	it("removes the Animator and the sparkle, keeps the joints and resets the pose", function()
		local pet = animatedSlime():Clone()
		PetRig.stripLife(pet)
		expect(UiHarness.find(pet, "AnimationController")).toBeNil()
		expect(UiHarness.find(pet, "Animator")).toBeNil()
		expect(UiHarness.find(pet, "LifeSparkle")).toBeNil()
		local motor = UiHarness.find(pet, "SkinRoot")
		expect(motor ~= nil).toBe(true)
		local joints = 0
		for _, inst in UiHarness.descendants(pet) do
			if inst:IsA("Motor6D") then
				joints += 1
				expect(inst.Transform.Position.Y).toBe(0)
			end
		end
		expect(joints).toBe(1)
	end)
end)

-- A species slime cloned mid-hop: SkinRoot and the mesh welded to it are lifted off their rest pose, the ring
-- welded to Body is not.
local function hoppingSlime(): any
	local model = new("Model")
	local body = new("Part")
	body.Name = "Body"
	body.CFrame = CFrame.new(10, 2, -4)
	body.Parent = model
	local skin = new("Part")
	skin.Name = "SkinRoot"
	skin.CFrame = CFrame.new(10, 2.9, -4) * CFrame.Angles(0.2, 0, 0)
	skin.Parent = model
	local motor = new("Motor6D")
	motor.Name = "SkinRoot"
	motor.Part0 = body
	motor.Part1 = skin
	motor.Transform = CFrame.new(0, 0.9, 0) * CFrame.Angles(0.2, 0, 0)
	motor.Parent = body
	local mesh = new("MeshPart")
	mesh.Name = "Mesh"
	mesh.CFrame = skin.CFrame * CFrame.new(0, 0.5, 0)
	mesh.Parent = model
	local meshWeld = new("WeldConstraint")
	meshWeld.Part0 = skin
	meshWeld.Part1 = mesh
	meshWeld.Parent = mesh
	local ring = new("Part")
	ring.Name = "Puddle"
	ring.CFrame = CFrame.new(10, 0.5, -4)
	ring.Parent = model
	local ringWeld = new("WeldConstraint")
	ringWeld.Part0 = body
	ringWeld.Part1 = ring
	ringWeld.Parent = ring
	return model
end

describe("PetRig.stripLife on a slime cloned mid-hop", function()
	local pet = hoppingSlime():Clone()
	PetRig.stripLife(pet)
	local function at(name: string): any
		return pet:FindFirstChild(name).CFrame -- a part, not the Motor6D under Body that shares its name
	end
	it("puts the joint's part back at its rest pose on Body", function()
		expect(at("SkinRoot").Position.Y).toBeCloseTo(2, 1e-5)
		expect(at("SkinRoot").UpVector.Y).toBeCloseTo(1, 1e-5)
	end)
	it("moves the parts welded to it along", function()
		expect(at("Mesh").Position.Y).toBeCloseTo(2.5, 1e-5)
		expect(at("Mesh").Position.Z).toBeCloseTo(-4, 1e-5)
		expect(at("Mesh").UpVector.Y).toBeCloseTo(1, 1e-5)
		expect(at("Mesh").Position.X).toBeCloseTo(10, 1e-5)
	end)
	it("leaves Body and the parts welded to Body where they are", function()
		expect(at("Body").Position.Y).toBe(2)
		expect(at("Puddle").Position.Y).toBeCloseTo(0.5, 1e-6)
	end)
end)
