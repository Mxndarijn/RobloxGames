--!strict
--[[
	PetRig: undo the client-only life rig (src/ui/SlimeLifeRunner, #71) on a
	cloned slime so a FollowPets copy is a plain rigid model. The runner adds
	"LifeRoot" (with its LifeJoint / LifeWeld welds and LifeSparkle emitter
	as children) and Body.LifeSquash, and disables the factory WeldConstraints.
]]

local PetRig = {}

PetRig.ROOT_NAME = "LifeRoot"
PetRig.SQUASH_NAME = "LifeSquash"

function PetRig.stripLife(pet: Instance)
	for _, inst in pet:GetDescendants() do
		if inst.Name == PetRig.ROOT_NAME or inst.Name == PetRig.SQUASH_NAME then
			inst:Destroy()
		end
	end
	for _, inst in pet:GetDescendants() do
		if inst:IsA("WeldConstraint") then
			inst.Enabled = true
		end
	end
end

return PetRig
