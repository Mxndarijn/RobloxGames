--!strict
--[[
	StealGhost

	While a thief carries a slime away, a see-through copy stays on its pad, so everyone can see which slime is
	being taken while it is still "there". The copy is a plain snapshot of the slime model: no prompts, tags or
	attributes, anchored, no collision or queries, faded to Config.STEAL_GHOST_TRANSPARENCY. WorldView builds it
	when the slime is carried off and removes it when the slime is stolen or goes home.

	`wants` is the rule (tests/StealGhost.spec.luau). `build` only touches Roblox APIs when called.
]]

local Scene = if script then require(script.Parent.Scene) else require("./Scene")

local StealGhost = {}

StealGhost.NAME = "StealGhost"

-- A ghost shows on the pad only while someone other than the owner carries a pad slime.
function StealGhost.wants(entry: Scene.Entry): boolean
	return entry.state == "Carried"
		and entry.plotIndex ~= nil
		and entry.pad ~= nil
		and entry.carrierUserId ~= nil
		and entry.ownerUserId ~= 0
		and entry.carrierUserId ~= entry.ownerUserId
end

-- Same look from either side: an already see-through part gets more see-through, never less.
function StealGhost.fade(transparency: number, ghost: number): number
	return 1 - (1 - transparency) * (1 - ghost)
end

-- Copies `model` (its current pose) and rests the copy at `at` under `parent`.
function StealGhost.build(model: Model, at: CFrame, parent: Instance, ghost: number): Model
	local CollectionService = game:GetService("CollectionService")
	local copy = model:Clone()
	copy.Name = StealGhost.NAME
	for name in copy:GetAttributes() do
		copy:SetAttribute(name, nil)
	end
	for _, tag in CollectionService:GetTags(copy) do
		CollectionService:RemoveTag(copy, tag)
	end
	-- Collect first: destroying while walking GetDescendants can skip instances.
	local doomed: { Instance } = {}
	for _, d in copy:GetDescendants() do
		for _, tag in CollectionService:GetTags(d) do
			CollectionService:RemoveTag(d, tag)
		end
		if
			d:IsA("ProximityPrompt")
			or d:IsA("BillboardGui")
			or d:IsA("BaseScript")
			or d:IsA("Sound")
			or d:IsA("ParticleEmitter")
		then
			table.insert(doomed, d)
		elseif d:IsA("WeldConstraint") then
			-- A carry weld points at the thief's character: never pull the copy along.
			local p0, p1 = d.Part0, d.Part1
			if not (p0 and p0:IsDescendantOf(copy) and p1 and p1:IsDescendantOf(copy)) then
				table.insert(doomed, d)
			end
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.CastShadow = false
			d.Transparency = StealGhost.fade(d.Transparency, ghost)
		elseif d:IsA("Decal") then
			d.Transparency = StealGhost.fade(d.Transparency, ghost)
		end
	end
	for _, d in doomed do
		d:Destroy()
	end
	copy:PivotTo(at)
	copy.Parent = parent
	return copy
end

return StealGhost
