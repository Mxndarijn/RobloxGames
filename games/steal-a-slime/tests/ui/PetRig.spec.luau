--!strict
-- FollowPets clones of a living slime (#71) must lose the life rig and get
-- their factory welds back (src/visuals/client/PetRig.luau).
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local PetRig = UiHarness.ui("../visuals/client/PetRig")
local new = UiHarness.Instance.new

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
