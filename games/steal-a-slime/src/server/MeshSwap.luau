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
local FountainColliders = require(script.Parent.FountainColliders)
local MeshAssets = require(ReplicatedStorage.Shared.MeshAssets)
local VatDecor = require(ReplicatedStorage.Visuals.VatDecor)

local MeshSwap = {}

local cache: { [string]: MeshPart | false } = {}

-- `fidelity` (an Enum.CollisionFidelity name, MeshAssets.collision) goes into the CreateMeshPartAsync options: a game
-- script cannot write MeshPart.CollisionFidelity afterwards, and clones keep the collision made here. One template per
-- mesh id and fidelity.
local function template(meshId: string, fidelity: string?): MeshPart?
	local key = if fidelity then `{meshId}|{fidelity}` else meshId
	local hit = cache[key]
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
		local options: { [string]: any } = { RenderFidelity = Enum.RenderFidelity.Precise }
		if fidelity then
			options.CollisionFidelity = (Enum.CollisionFidelity :: any)[fidelity]
		end
		return AssetService:CreateMeshPartAsync(meshId, options)
	end)
	if ok and typeof(result) == "Instance" and result:IsA("MeshPart") then
		cache[key] = result
		return result
	end
	warn(`[Server] MeshSwap {key}: {result}`)
	cache[key] = false
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

-- A clone of a kit mesh's MeshPart at its native size (an entry with a meshId), or nil while it is not
-- uploaded or fails to load. Yields. For single runtime meshes that are not WorldLayout slots (ParadeView's lane).
function MeshSwap.load(name: string): MeshPart?
	local meshId = MeshAssets.meshId(name)
	local entry = MeshAssets.get(name)
	local base = meshId and template(meshId)
	if not base or not entry or not entry.size then
		return nil
	end
	local mesh = base:Clone()
	mesh.Name = name
	mesh.Size = Vector3.new(entry.size[1], entry.size[2], entry.size[3])
	return mesh
end

-- The one collision switch for a mesh: loaded = its MeshCollider parts
-- collide and its stand-ins don't; not loaded = colliders off and the
-- stand-ins back to their own CanCollide (decor like Pool stays off).
-- `colliders` (default = loaded) is what the MeshCollider parts get: FEATURES.FountainSplit turns the stand-ins off but
-- keeps the hand-placed colliders off too, the split pieces collide instead.
function MeshSwap.setMeshCollision(scope: Instance, name: string, loaded: boolean, colliders: boolean?)
	for _, d in scope:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("MeshCollider") == name then
				d.CanCollide = if colliders == nil then loaded else colliders
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

-- The collision fidelity a FountainSplit piece is made with: MeshAssets.COLLISION, except the slide piece, which only collides
-- with FEATURES.SlidePCD (else it is decor and the SlideColliders boxes are the slide).
local function splitFidelity(piece: string): string?
	if piece == "fountain_split_slide" and not Config.FEATURES.SlidePCD then
		return nil
	end
	return MeshAssets.collision(piece)
end

-- Set once the PCD slide is placed; apply() then retires the SlideColliders boxes it replaces after its scan (the scan walks a
-- snapshot of the map, which must not lose the very parts being destroyed).
local slidePcdPlaced = false

-- FEATURES.FountainSplit: the fountain slot gets MeshAssets.FOUNTAIN_SPLIT instead of the one slime_fountain mesh. Same
-- fit as swap() (one uniform scale into the slot box, standing on its bottom, turned IMPORT_YAW), each piece moved by its
-- entry offset (slot axes, scaled) so the assembled pieces sit exactly where the whole mesh drew. All pieces are created
-- first; if any fails (no id, no size, CreateMeshPartAsync error) nothing is placed and false is returned, so swap() goes on
-- with the single mesh and the hand-placed colliders. Only after all of them exist the stand-ins AND the MeshCollider parts
-- (Basin / Trim / Silo / Top) go non-colliding: the PCD pieces are the tower's collision. The slide piece is PCD with FEATURES.SlidePCD (apply()
-- then retires the Floor / Joint / Post / Brace boxes), else decor under the SlideColliders blocks (docs/COLLISION.md).
local function swapFountainSplit(target: BasePart, name: string, scope: Instance): boolean
	local bases: { MeshPart } = {}
	for _, piece in MeshAssets.FOUNTAIN_SPLIT do
		local entry = MeshAssets.get(piece)
		local meshId = MeshAssets.meshId(piece)
		local base = meshId and template(meshId, splitFidelity(piece))
		if not (base and entry and entry.size and entry.offset) then
			return false
		end
		table.insert(bases, base)
	end
	local _, scale, below = MeshAssets.fit(name, { target.Size.X, target.Size.Y, target.Size.Z })
	local k = scale or 1
	local turn = math.rad(MeshAssets.IMPORT_YAW)
	local meshes: { MeshPart } = {}
	for i, piece in MeshAssets.FOUNTAIN_SPLIT do
		local entry = MeshAssets.get(piece) :: MeshAssets.Entry
		local size, offset = entry.size :: { number }, entry.offset :: { number }
		local fidelity = splitFidelity(piece)
		local mesh = bases[i]:Clone()
		mesh.Name = piece
		mesh.Size = Vector3.new(size[1] * k, size[2] * k, size[3] * k)
		mesh.CFrame = target.CFrame
			* CFrame.new(0, -below, 0)
			* CFrame.new(offset[1] * k, offset[2] * k, offset[3] * k)
			* CFrame.Angles(0, turn, 0)
		mesh.Anchored = true
		mesh.CanCollide = fidelity ~= nil
		mesh.CanQuery = false
		mesh.CanTouch = false
		table.insert(meshes, mesh)
	end
	hide(target)
	hideStandIns(scope, name)
	for _, mesh in meshes do
		mesh.Parent = target
	end
	MeshSwap.setMeshCollision(scope, name, true, false)
	slidePcdPlaced = Config.FEATURES.SlidePCD
	return true
end

-- A part slot or a whole Model (WorldProps skins: its parts keep collision,
-- prompts and SurfaceGuis, only their look is hidden).
local function swap(target: BasePart | Model, name: string, scope: Instance): boolean
	if target:FindFirstChild("Mesh") then
		return false
	end
	if Config.FEATURES.FountainSplit and name == "slime_fountain" and target:IsA("BasePart") then
		if target:FindFirstChild(MeshAssets.FOUNTAIN_SPLIT[1]) then
			return false
		end
		if swapFountainSplit(target, name, scope) then
			return true
		end
	end
	local meshId = MeshAssets.meshId(name)
	local fidelity = MeshAssets.collision(name)
	local base = meshId and template(meshId, fidelity)
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
	-- MeshTint (WorldBorder giants): the slot's own Color multiplies the vertex colours, so one mesh wears several moods.
	if not target:IsA("Model") and target:GetAttribute("MeshTint") == true then
		mesh.Color = target.Color
	end
	-- B9: a skinned Model whose solid is its own invisible "Collider" part (the Top Earners board) widens that part to the
	-- skin's width and height, keeping its depth and front (the hand collider was 15 wide under a 20.6 wide mesh). A mesh
	-- that has a fidelity is the collider itself.
	if fixed and fidelity == nil then
		local collider = target:FindFirstChild("Collider")
		if collider and collider:IsA("BasePart") then
			local offset = collider.CFrame:PointToObjectSpace(cf.Position)
			collider.Size = Vector3.new(fixed.X, fixed.Y, collider.Size.Z)
			collider.CFrame = collider.CFrame * CFrame.new(offset.X, offset.Y, 0)
		end
	end
	mesh.Anchored = true
	mesh.CanCollide = fidelity ~= nil -- decor never collides; a mesh with a fidelity is solid
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
		-- the mesh is the collider now: the slot box under it (an invisible copy of its bbox) would only double it
		if fidelity then
			target.CanCollide = false
		end
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

-- Bug #16: every plot's MergeVat disc wears the merge_vat model (1 MeshPart per plot, child "VatMesh" of the disc),
-- independent of FEATURES.MergeVat3 (the 3-slime gameplay stays behind its flag; only the look changes). The disc
-- keeps its name, position, collision and MergePrompt; it and its Goo are only made invisible, and only once the
-- mesh is placed (template not loaded = the cylinder stays). Idempotent. Yields; returns how many vats got the model.
local VAT_MESH_NAME = "VatMesh"
function MeshSwap.swapPlotVats(): number
	local plots = workspace:FindFirstChild("Plots")
	if not plots then
		return 0
	end
	local name = VatDecor.MESH
	local meshId = MeshAssets.meshId(name)
	local fidelity = MeshAssets.collision(name) -- docs/COLLISION.md: set at CreateMeshPartAsync, the only place it sticks
	local base = meshId and template(meshId, fidelity)
	if not base then
		return 0
	end
	local count = 0
	for _, plot in plots:GetChildren() do
		local vat = plot:FindFirstChild("MergeVat")
		if vat and vat:IsA("BasePart") and not vat:FindFirstChild(VAT_MESH_NAME) then
			local pose = VatDecor.pose(vat.Position.X, vat.Position.Y, vat.Position.Z)
			local plotBase = plot:FindFirstChild("Base")
			local turn = if plotBase and plotBase:IsA("BasePart") then plotBase.CFrame.Rotation else CFrame.new()
			local mesh = base:Clone()
			mesh.Name = VAT_MESH_NAME
			mesh.Size = Vector3.new(pose.size[1], pose.size[2], pose.size[3])
			mesh.CFrame = CFrame.new(pose.position[1], pose.position[2], pose.position[3]) * turn
			mesh.Anchored = true
			mesh.CanCollide = fidelity ~= nil
			mesh.CanQuery = false
			mesh.CanTouch = false
			mesh.Parent = vat
			hide(vat)
			local goo = vat:FindFirstChild("Goo")
			if goo and goo:IsA("BasePart") then
				hide(goo)
			end
			count += 1
		end
	end
	return count
end

-- FEATURES.RainMagnet: the rain_magnet mesh as a template in ReplicatedStorage.RainMagnetMeshes (named by mesh,
-- native size); the client stands a clone on the owner's plot (RainMagnetFx), so it takes no WorldLayout slot.
-- Also published in Studio so the pc-watcher shot can force the look with the flag off. Yields.
function MeshSwap.publishRainMagnetTemplates(): number
	if not (Config.FEATURES.RainMagnet or RunService:IsStudio()) then
		return 0
	end
	local folder = ReplicatedStorage:FindFirstChild("RainMagnetMeshes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "RainMagnetMeshes"
		folder.Parent = ReplicatedStorage
	end
	local name = "rain_magnet"
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
	if slidePcdPlaced then
		slidePcdPlaced = false
		FountainColliders.retirePcd()
	end
	return count
end

return MeshSwap
