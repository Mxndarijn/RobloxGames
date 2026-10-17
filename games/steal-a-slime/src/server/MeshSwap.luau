--!strict
--[[
	MeshSwap (Roblox adapter, owner: Phoenix)

	For every BasePart under workspace.Map / workspace.Plots tagged with the
	attribute MeshAsset (WorldLayout placeholders) whose id is in
	Shared.MeshAssets, creates a MeshPart via AssetService:CreateMeshPartAsync,
	fits it into the placeholder's box at one uniform scale (MeshAssets.fit:
	native proportions, standing on the box bottom; a Model with a MeshSize
	attribute keeps that size: WorldProps), anchors it, makes it visual-only
	and hides the placeholder (which keeps collision, prompts and contract
	names). A Part slot's mesh is turned MeshAssets.IMPORT_YAW about its own
	vertical axis (the upload's front vs WorldLayout's kit axes). Parts
	tagged MeshStandIn = that mesh anywhere under the same Map or Plots root
	hide too (the spiral stand-in lives under Map.Chute, not
	beside the fountain slot). A slot with MeshStandInsCollide = false hands
	collision over in one step (setMeshCollision): its stand-ins' CanCollide
	goes off and parts tagged MeshCollider = that mesh go on (the fountain's
	Basin/Trim/Silo colliders, off in the map until then). Loading or failed, the
	colliders stay off and the stand-ins keep collision. Idempotent (a placeholder with a "Mesh" child
	is skipped). Any failure leaves the primitive placeholder. Holds no
	gameplay rules.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
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
		-- v30 C2: Automatic fidelity drops to a coarse LOD with distance and re-meshes as the camera
		-- moves (the "wrong until I walk" pop); the kit meshes are low-poly, so draw them whole. Set
		-- here: game scripts cannot write MeshPart.RenderFidelity (PluginOrOpenCloud only), which made
		-- apply() throw and left every world slot a primitive since #155.
		return AssetService:CreateMeshPartAsync(meshId, { RenderFidelity = Enum.RenderFidelity.Precise })
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
	local cf, box
	local fixed = nil
	if target:IsA("Model") then
		cf, box = target:GetBoundingBox()
		-- WorldProps skins carry their own MeshSize (native x one scale, as
		-- tall as the Model): the mesh stands on the box's bottom with its
		-- front (-Z) face on the box's front, where the board's SurfaceGui is.
		local attr = target:GetAttribute("MeshSize")
		if typeof(attr) == "Vector3" then
			fixed = attr
		end
	else
		cf, box = target.CFrame, target.Size
	end
	local size: { number }, drop: number
	if fixed then
		size, drop = { fixed.X, fixed.Y, fixed.Z }, 0
		cf = cf * CFrame.new(0, (fixed.Y - box.Y) / 2, (fixed.Z - box.Z) / 2)
	else
		-- One uniform scale into the box, standing on its bottom: a WorldProps
		-- Model's bounding box is the primitive prop's, not the mesh's, and
		-- stretching to it squashed the board 3.08:1 (WorldLayout slots are
		-- native x scale already, so they fit exactly).
		local fit, _, below = MeshAssets.fit(name, { box.X, box.Y, box.Z })
		size, drop = fit, below
	end
	local mesh = base:Clone()
	mesh.Name = "Mesh"
	mesh.Size = Vector3.new(size[1], size[2], size[3])
	-- WorldLayout slots (Parts) assume the kit's documented axes; turn the
	-- imported mesh back onto them (MeshAssets.IMPORT_YAW, about the box's own
	-- axis). WorldProps Models want the import front (-Z) as it comes.
	local turn = if target:IsA("Model") then 0 else math.rad(MeshAssets.IMPORT_YAW)
	mesh.CFrame = cf * CFrame.new(0, -drop, 0) * CFrame.Angles(0, turn, 0)
	-- RenderFidelity is Precise from the template (CreateMeshPartAsync options, v30 C2).
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

-- FEATURES.PlotSkins (CONTRACT.md §15): one MeshPart template per skin decor in
-- ReplicatedStorage.PlotSkinMeshes (named by mesh, native size). Clients clone
-- them over a plot's Mailbox_<i> slot (Visuals.PlotDecor.applySkin), so the skins
-- take no world mesh slot of their own. Yields; returns how many were published.
function MeshSwap.publishSkinTemplates(): number
	if not Config.FEATURES.PlotSkins then
		return 0
	end
	local folder = ReplicatedStorage:FindFirstChild("PlotSkinMeshes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "PlotSkinMeshes"
		folder.Parent = ReplicatedStorage
	end
	local count = 0
	for _, skin in Config.PLOT_SKINS do
		local name = skin.decor
		local meshId = name and MeshAssets.meshId(name)
		local entry = name and MeshAssets.get(name)
		local base = meshId and template(meshId)
		if name and entry and entry.size and base and not (folder :: Folder):FindFirstChild(name) then
			local mesh = base:Clone()
			mesh.Name = name
			mesh.Size = Vector3.new(entry.size[1], entry.size[2], entry.size[3])
			mesh.Anchored = true
			mesh.CanCollide = false
			mesh.CanQuery = false
			mesh.CanTouch = false
			mesh.Parent = folder
			count += 1
		end
	end
	return count
end

-- FEATURES.FountainTiers: the ring and crest meshes as templates in ReplicatedStorage.FountainTierMeshes
-- (named by mesh, native size); the client clones them round / over the fountain (FountainTierFx), so they
-- take no WorldLayout slot. Yields; returns how many were published.
function MeshSwap.publishFountainTierTemplates(): number
	if not Config.FEATURES.FountainTiers then
		return 0
	end
	local folder = ReplicatedStorage:FindFirstChild("FountainTierMeshes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "FountainTierMeshes"
		folder.Parent = ReplicatedStorage
	end
	local count = 0
	for _, name in { "fountain_tier_ring", "fountain_tier_crest" } do
		local meshId = MeshAssets.meshId(name)
		local entry = MeshAssets.get(name)
		local base = meshId and template(meshId)
		if entry and entry.size and base and not (folder :: Folder):FindFirstChild(name) then
			local mesh = base:Clone()
			mesh.Name = name
			mesh.Size = Vector3.new(entry.size[1], entry.size[2], entry.size[3])
			mesh.Anchored = true
			mesh.CanCollide = false
			mesh.CanQuery = false
			mesh.CanTouch = false
			mesh.Parent = folder
			count += 1
		end
	end
	return count
end

-- FEATURES.MergeVat3: the merge vat mesh as a template in ReplicatedStorage.MergeVatMeshes (named by mesh,
-- native size); the client stands a clone over the owner's plot vat (VatFx), so it takes no WorldLayout slot.
-- Also published in Studio so the pc-watcher shots can force the look with the flag off. Yields.
function MeshSwap.publishVatTemplates(): number
	if not (Config.FEATURES.MergeVat3 or RunService:IsStudio()) then
		return 0
	end
	local folder = ReplicatedStorage:FindFirstChild("MergeVatMeshes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "MergeVatMeshes"
		folder.Parent = ReplicatedStorage
	end
	local name = "merge_vat"
	local meshId = MeshAssets.meshId(name)
	local entry = MeshAssets.get(name)
	local base = meshId and template(meshId)
	if entry and entry.size and base and not (folder :: Folder):FindFirstChild(name) then
		local mesh = base:Clone()
		mesh.Name = name
		mesh.Size = Vector3.new(entry.size[1], entry.size[2], entry.size[3])
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.Parent = folder
		return 1
	end
	return 0
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
