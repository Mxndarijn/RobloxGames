--!strict
--[[
	PetRig: undo the client-only life on a cloned slime so a FollowPets copy is
	a plain rigid model.
	  * #71 procedural life: "LifeRoot" (with its LifeJoint / LifeWeld welds)
	    and Body.LifeSquash, and disabled factory WeldConstraints.
	  * slime rig (src/visuals/shared/SlimeRig, animated life): the
	    AnimationController + Animator are removed (pets never animate), Motor6D
	    Transforms are reset to identity and each joint's Part1 (with every
	    part welded to it) is put back at its rest pose (a clone taken mid-hop
	    copies the lifted CFrames, and the pet is anchored before any joint
	    solve), the "Mesh" skin's Size is restored (SlimeMotor squash) and the
	    "LifeSparkle" emitter (parented to SkinRoot) goes.
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
	local welds: { WeldConstraint } = {}
	local motors: { Motor6D } = {}
	local own: { [Instance]: boolean } = {}
	for _, inst in pet:GetDescendants() do
		own[inst] = true
		if inst:IsA("WeldConstraint") then
			inst.Enabled = true
			table.insert(welds, inst)
		elseif inst:IsA("Motor6D") then
			inst.Transform = CFrame.new()
			table.insert(motors, inst)
		end
	end
	for _, motor in motors do
		local p0, p1 = motor.Part0, motor.Part1
		if p0 and p1 and own[p0] and own[p1] then
			-- Part1 and the parts welded to it move as one; the walk never crosses into Part0.
			local group: { [BasePart]: boolean } = { [p1] = true }
			local queue: { BasePart } = { p1 }
			while #queue > 0 do
				local part = table.remove(queue) :: BasePart
				for _, weld in welds do
					local other = if weld.Part0 == part
						then weld.Part1
						elseif weld.Part1 == part then weld.Part0
						else nil
					if other and other ~= p0 and own[other] and not group[other] then
						group[other] = true
						table.insert(queue, other)
					end
				end
			end
			local delta = p0.CFrame * motor.C0 * motor.C1:Inverse() * p1.CFrame:Inverse()
			for part in group do
				part.CFrame = delta * part.CFrame
			end
		end
	end
end

return PetRig
