--!strict
--[[
	LocalCopy (client only)

	Helpers for the egg shows (EggHatchFx, EggSmashFx), which play on a local copy while the real model is hidden:
	  * setHidden(model, hidden): hides (or shows again) a model on this client only. A Mystery Egg's nest stays.
	  * copyOf(model): a local, anchored copy that nothing treats as a slime (no tags, attributes, prompts, guis,
	    scripts or nest), or nil when it can't be cloned.
]]

local LocalCopy = {}

local function inNest(d: Instance, model: Instance): boolean
	local nest = model:FindFirstChild("Nest")
	return nest ~= nil and d:IsDescendantOf(nest)
end

-- Hides (or shows again) a model on this client only: parts, decals, and the lights and sparkles on it (EggFx's
-- ready glow). The egg's nest stays.
function LocalCopy.setHidden(model: Model, hidden: boolean)
	local value = if hidden then 1 else 0
	for _, d in model:GetDescendants() do
		if inNest(d, model) then
			continue
		elseif d:IsA("BasePart") or d:IsA("Decal") then
			(d :: any).LocalTransparencyModifier = value
		elseif d:IsA("Light") or d:IsA("ParticleEmitter") then
			(d :: any).Enabled = not hidden
		end
	end
end

-- A local copy of a model that nothing else treats as a slime: no tags, attributes, prompts, guis, scripts or nest.
function LocalCopy.copyOf(model: Model): Model?
	local was = model.Archivable
	model.Archivable = true
	local ok, copy = pcall(model.Clone, model)
	model.Archivable = was
	if not ok or not copy then
		return nil
	end
	local c = copy :: Model
	for _, tag in c:GetTags() do
		c:RemoveTag(tag)
	end
	for name in c:GetAttributes() do
		c:SetAttribute(name, nil)
	end
	for _, d in c:GetDescendants() do
		for _, tag in d:GetTags() do
			d:RemoveTag(tag)
		end
		if d:IsA("ProximityPrompt") or d:IsA("BillboardGui") or d:IsA("SurfaceGui") or d:IsA("LuaSourceContainer") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.LocalTransparencyModifier = 0
		elseif d:IsA("Decal") then
			d.LocalTransparencyModifier = 0
		end
	end
	local nest = c:FindFirstChild("Nest")
	if nest then
		nest:Destroy()
	end
	c.Archivable = false
	return c
end

return table.freeze(LocalCopy)
