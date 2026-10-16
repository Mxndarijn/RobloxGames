--!strict
--[[
	PetRig: undo the client-only life on a cloned slime so a FollowPets copy is
	a plain rigid model.
	  * #71 procedural life: "LifeRoot" (with its LifeJoint / LifeWeld welds)
	    and Body.LifeSquash, and disabled factory WeldConstraints.
	  * slime rig (src/visuals/shared/SlimeRig, animated life): the
	    AnimationController + Animator are removed (pets never animate), Motor6D
	    Transforms are reset to identity (a clone taken mid-hop must not freeze
	    in that pose), the "Mesh" skin's Size is restored (SlimeMotor squash)
	    and the "LifeSparkle" emitter (parented to SkinRoot) goes.
	The FaceRoot / SkinRoot parts and their Motor6Ds stay: they are the pet's
	joints.
]]

local PetRig = {}

PetRig.ROOT_NAME = "LifeRoot"
PetRig.SQUASH_NAME = "LifeSquash"
PetRig.SPARKLE_NAME = "LifeSparkle"
PetRig.CONTROLLER_NAME = "AnimationController"

function PetRig.stripLife(pet: Instance)
	pet:SetAttribute("LifeAnimating", nil) -- set by SlimeLifeRunner on an animated slime
	pet:SetAttribute("LifeMode", nil)
	pet:SetAttribute("LifeForce", nil)
	-- SlimeMotor squashes the "Mesh" skin by Size; a clone taken mid-squash gets its rest size back.
	local restSize = pet:GetAttribute("LifeSkinSize")
	local skin = pet:FindFirstChild("Mesh")
	if typeof(restSize) == "Vector3" and skin and skin:IsA("MeshPart") then
		skin.Size = restSize
	end
	pet:SetAttribute("LifeSkinSize", nil)
	for _, inst in pet:GetDescendants() do
		local name = inst.Name
		if
			name == PetRig.ROOT_NAME
			or name == PetRig.SQUASH_NAME
			or name == PetRig.SPARKLE_NAME
			or name == PetRig.CONTROLLER_NAME
		then
			inst:Destroy()
		end
	end
	for _, inst in pet:GetDescendants() do
		if inst:IsA("WeldConstraint") then
			inst.Enabled = true
		elseif inst:IsA("Motor6D") then
			inst.Transform = CFrame.new()
		end
	end
end

return PetRig
