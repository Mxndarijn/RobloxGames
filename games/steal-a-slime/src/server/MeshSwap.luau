--!strict
--[[
	MeshSwap (Roblox adapter, owner: Phoenix)

	For every BasePart under workspace.Map / workspace.Plots tagged with the
	attribute MeshAsset (WorldLayout placeholders) whose id is in
	Shared.MeshAssets, creates a MeshPart via AssetService:CreateMeshPartAsync,
	fits it to the placeholder's box and CFrame, anchors it, makes it visual-only
	and hides the placeholder (which keeps collision, prompts and contract
	names). Parts tagged MeshStandIn = that mesh anywhere under the same Map
	or Plots root hide too (the spiral stand-in lives under Map.Chute, not
	beside the fountain slot). A slot with MeshStandInsCollide = false hands
	collision over in one step (setMeshCollision): its stand-ins' CanCollide
	goes off and parts tagged MeshCollider = that mesh go on (the fountain's
	Basin/Silo colliders, off in the map until then). Loading or failed, the
	colliders stay off and the stand-ins keep collision. Idempotent (a placeholder with a "Mesh" child
	is skipped). Any failure leaves the primitive placeholder. Holds no
	gameplay rules.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeshAssets = require(ReplicatedStorage.Shared.MeshAssets)

local MeshSwap = {}

local cache: { [string]: MeshPart | false } = {}

local function template(meshId: string): MeshPart?
	local hit = cache[meshId]
	if hit == false then
		return nil
	end
	-- `if hit then` widens MeshPart | false to MeshPart | true under luau-lsp.
	if typeof(hit) == "Instance" then
		return hit
	end
	local ok, result = pcall(function()
		return AssetService:CreateMeshPartAsync(meshId)
	end)
	if ok and typeof(result) == "Instance" and result:IsA("MeshPart") then
		cache[meshId] = result
		return result
	end
	warn(`[Server] MeshSwap {meshId}: {result}`)
	cache[meshId] = false
	return nil
end

local function hide(part: BasePart)
	part.Transparency = 1
	for _, d in part:GetChildren() do
		if d:IsA("Decal") or d:IsA("Texture") then
			(d :: Decal).Transparency = 1
		end
	end
end

local function hideStandIns(scope: Instance, name: string)
	for _, d in scope:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("MeshStandIn") == name then
			hide(d)
		end
	end
end

-- The one collision switch for a mesh: loaded = its MeshCollider parts
-- collide and its stand-ins don't; not loaded = colliders off and the
-- stand-ins back to their own CanCollide (decor like Pool stays off).
function MeshSwap.setMeshCollision(scope: Instance, name: string, loaded: boolean)
	for _, d in scope:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("MeshCollider") == name then
				d.CanCollide = loaded
			elseif d:GetAttribute("MeshStandIn") == name then
				local own = d:GetAttribute("StandInCanCollide")
				if loaded then
					if own == nil then
						d:SetAttribute("StandInCanCollide", d.CanCollide)
					end
					d.CanCollide = false
				elseif own ~= nil then
					d.CanCollide = own == true
				end
			end
		end
	end
end

-- A part slot or a whole Model (WorldProps skins: its parts keep collision,
-- prompts and SurfaceGuis, only their look is hidden).
local function swap(target: BasePart | Model, name: string, scope: Instance): boolean
	if target:FindFirstChild("Mesh") then
		return false
	end
	local meshId = MeshAssets.meshId(name)
	local base = meshId and template(meshId)
	if not base then
		return false
	end
	local cf, size
	if target:IsA("Model") then
		cf, size = target:GetBoundingBox()
	else
		cf, size = target.CFrame, target.Size
	end
	local mesh = base:Clone()
	mesh.Name = "Mesh"
	mesh.Size = size
	mesh.CFrame = cf
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.CanTouch = false
	if target:IsA("Model") then
		for _, d in target:GetDescendants() do
			if d:IsA("BasePart") then
				hide(d)
			end
		end
	else
		hide(target)
	end
	hideStandIns(scope, name)
	mesh.Parent = target
	if target:GetAttribute("MeshStandInsCollide") == false then
		MeshSwap.setMeshCollision(scope, name, true)
	end
	return true
end

-- Returns how many placeholders got a mesh.
function MeshSwap.apply(): number
	local count = 0
	for _, root in { workspace:FindFirstChild("Map"), workspace:FindFirstChild("Plots") } do
		if root then
			for _, inst in root:GetDescendants() do
				local name = inst:GetAttribute("MeshAsset")
				if
					(inst:IsA("BasePart") or inst:IsA("Model"))
					and typeof(name) == "string"
					and swap(inst :: any, name, root)
				then
					count += 1
				end
			end
		end
	end
	return count
end

return MeshSwap
