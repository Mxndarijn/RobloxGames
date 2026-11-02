--!strict
--[[
	ObbyVinePose (VisualsClient helper, contract/obby-sections.md §7)

	The look of a character hanging on a vine rope, on this client: arms up on the knob (each shoulder turned in the
	torso's frame: a Motor6D's C0, or the torso attachment of the new rig's AnimationConstraint, put back exactly by
	`lower`) and where the hands meet (the rope's Beam ends there). Joint edits never replicate, so ObbyMoves poses
	the local player and ObbyVineSync every other player hanging on a rope.
]]

local ObbyVinePose = {}

ObbyVinePose.ARM_UP = math.rad(165) -- each arm raised this far from hanging down ...
ObbyVinePose.ARM_FORWARD = math.rad(12) -- ... and this far forward, hands on the knob over your head
ObbyVinePose.ROPE_WIDTH = 0.35 -- the Beam from the knob to the hands

export type Saved = { { joint: Instance, c0: CFrame } }

-- Raises `character`'s arms; returns what `lower` needs to put them back.
function ObbyVinePose.raise(character: Model): Saved
	local saved: Saved = {}
	for _, d in character:GetDescendants() do
		local name = d.Name
		local side = if name == "RightShoulder" or name == "Right Shoulder"
			then -1
			elseif name == "LeftShoulder" or name == "Left Shoulder" then 1
			else 0
		if side == 0 then
			continue
		end
		local turn = CFrame.Angles(-ObbyVinePose.ARM_FORWARD, 0, 0) * CFrame.Angles(0, 0, side * ObbyVinePose.ARM_UP)
		if d:IsA("Motor6D") then
			local c0 = d.C0
			table.insert(saved, { joint = d :: Instance, c0 = c0 })
			d.C0 = CFrame.new(c0.Position) * turn * c0.Rotation
		elseif d:IsA("AnimationConstraint") then
			local a0 = d.Attachment0
			if a0 then
				local c0 = a0.CFrame
				table.insert(saved, { joint = a0 :: Instance, c0 = c0 })
				a0.CFrame = CFrame.new(c0.Position) * turn * c0.Rotation
			end
		end
	end
	return saved
end

-- Puts the arms `raise` turned back exactly.
function ObbyVinePose.lower(saved: Saved)
	for _, a in saved do
		local j = a.joint
		if j.Parent then
			if j:IsA("Motor6D") then
				j.C0 = a.c0
			elseif j:IsA("Attachment") then
				j.CFrame = a.c0
			end
		end
	end
	table.clear(saved)
end

-- The rope between `knob` and the hands: a Beam from the knob's centre (its ObbyVineGrip attachment) to the
-- returned attachment, which the caller puts between the hands each frame. Destroy both when the hold ends.
function ObbyVinePose.rope(knob: BasePart): (Beam, Attachment)
	local a0 = knob:FindFirstChild("ObbyVineGrip")
	if not (a0 and a0:IsA("Attachment")) then
		local made = Instance.new("Attachment")
		made.Name = "ObbyVineGrip"
		made.Parent = knob
		a0 = made
	end
	local a1 = Instance.new("Attachment")
	a1.Name = "ObbyVineHands"
	a1.WorldPosition = knob.Position
	a1.Parent = workspace.Terrain
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0 :: Attachment
	beam.Attachment1 = a1
	beam.Width0 = ObbyVinePose.ROPE_WIDTH
	beam.Width1 = ObbyVinePose.ROPE_WIDTH
	beam.Color = ColorSequence.new(knob.Color)
	beam.FaceCamera = true
	beam.Segments = 1
	beam.LightEmission = 0
	beam.Transparency = NumberSequence.new(0)
	beam.Parent = knob
	return beam, a1
end

-- Between `character`'s hands (an R6 arm's far end along the raised arm), or nil without both hands.
function ObbyVinePose.grip(character: Model): Vector3?
	local right = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	local left = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
	if not (right and left and right:IsA("BasePart") and left:IsA("BasePart")) then
		return nil
	end
	local function tip(p: BasePart): Vector3
		return if p.Name == "RightHand" or p.Name == "LeftHand"
			then p.Position
			else (p.CFrame * CFrame.new(0, -p.Size.Y / 2, 0)).Position
	end
	return (tip(right) + tip(left)) / 2
end

return ObbyVinePose
