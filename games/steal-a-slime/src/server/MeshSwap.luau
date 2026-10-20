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

	applyAll() is the boot path: prefetch() fetches every template the slots
	need on PREFETCH_WORKERS threads at once (one CreateMeshPartAsync after
	another left a fresh server in primitives for many seconds), then apply()
	and swapPlotVats() place them from the cache, then the workspace attribute
	WorldMeshesReady goes true for the client's loading screen.
]]

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)
local FountainColliders = require(script.Parent.FountainColliders)
local Habitats = require(ReplicatedStorage.Shared.Habitats)
local MeshAssets = require(ReplicatedStorage.Shared.MeshAssets)
local PetCloud = require(ReplicatedStorage.Visuals.PetCloud)
local PvpModels = require(ReplicatedStorage.Shared.PvpModels)
local Retry = require(ReplicatedStorage.Shared.Retry)
local VatDecor = require(ReplicatedStorage.Visuals.VatDecor)

local MeshSwap = {}

-- Templates fetched at the same time by prefetch().
MeshSwap.PREFETCH_WORKERS = 8
-- Waits (seconds) between the tries of the pet cloud load: 1 try + #delays retries, then the pets keep their Mount.
MeshSwap.PET_CLOUD_RETRY_DELAYS = { 2, 5, 15, 30, 60 }

local cache: { [string]: MeshPart | false } = {}
-- Keys whose CreateMeshPartAsync is running, with the threads waiting for it: a second ask for the same template
-- waits for the first fetch instead of starting its own.
local inflight: { [string]: { thread } } = {}

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
	local waiting = inflight[key]
	if waiting then
		table.insert(waiting, coroutine.running())
		coroutine.yield()
		return template(meshId, fidelity)
	end
	inflight[key] = {}
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
	local made = if ok and typeof(result) == "Instance" and result:IsA("MeshPart") then result else nil
	if made then
		cache[key] = made
	else
		warn(`[Server] MeshSwap {key}: {result}`)
		cache[key] = false
	end
	local waiters = inflight[key]
	inflight[key] = nil
	for _, thread in waiters do
		task.spawn(thread)
	end
	return made
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
	-- MeshMaterial / MeshTransparency (the jar tower's glass): the mesh wears that material and transparency instead of
	-- opaque SmoothPlastic, so a glass shell stays see-through.
	local material = target:GetAttribute("MeshMaterial")
	if typeof(material) == "string" then
		local ok, value = pcall(function()
			return (Enum.Material :: any)[material]
		end)
		if ok and value then
			mesh.Material = value
		end
	end
	local clear = target:GetAttribute("MeshTransparency")
	if typeof(clear) == "number" then
		mesh.Transparency = math.clamp(clear, 0, 1)
	end
	-- A skinned Model carries its tint as a Color3 (Props.STAND_STYLES: the blue Upgrade Shop stand).
	local modelTint = if target:IsA("Model") then target:GetAttribute("MeshTint") else nil
	if typeof(modelTint) == "Color3" then
		mesh.Color = modelTint
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
			-- MeshKeep parts are decor beside the skin (the shop stands' crates, anvil...): they stay visible.
			if d:IsA("BasePart") and d:GetAttribute("MeshKeep") ~= true then
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

-- FEATURES.Habitats: one MeshPart template per habitat overlay in ReplicatedStorage.HabitatMeshes (named by
-- mesh, native size). The client clones them onto the pads (HabitatFx): a MeshPart keeps the kit's vertex
-- colours, a script-made FileMesh SpecialMesh draws plain white. Yields; returns how many were published.
function MeshSwap.publishHabitatTemplates(): number
	if not Config.FEATURES.Habitats then
		return 0
	end
	local folder = ReplicatedStorage:FindFirstChild(Constants.HABITAT_MESHES)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Constants.HABITAT_MESHES
		folder.Parent = ReplicatedStorage
	end
	local count = 0
	for _, habitat in Habitats.LIST do
		local name = habitat.overlay
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
			mesh.CastShadow = false
			mesh.Parent = folder
			count += 1
		end
	end
	return count
end

-- FEATURES.PvP: one MeshPart template per placed-marker mesh (PvpModels.MARKER_MESHES: Goo Traps, Bounce Pad) in
-- ReplicatedStorage.PvpMarkerMeshes (named by mesh, native size, decor). The client (ui/PvpEffects) clones them for a
-- placed trap: a MeshPart keeps the kit's vertex colours, a script-made FileMesh draws white. Yields; returns how many
-- were published.
function MeshSwap.publishPvpMarkerTemplates(): number
	if not Config.FEATURES.PvP then
		return 0
	end
	local folder = ReplicatedStorage:FindFirstChild(Constants.PVP_MARKER_MESHES)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Constants.PVP_MARKER_MESHES
		folder.Parent = ReplicatedStorage
	end
	local count = 0
	for _, name in PvpModels.MARKER_MESHES do
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
			mesh.CastShadow = false
			mesh.Parent = folder
			count += 1
		end
	end
	return count
end

-- The follow pet's cloud as ONE template, ReplicatedStorage.PetCloudMeshes.pet_cloud (native size, decor), cloned by
-- the client (FollowPets). A failed load is forgotten and tried again after each of PET_CLOUD_RETRY_DELAYS; pets
-- never wait for it. Yields; returns whether the template is published.
function MeshSwap.publishPetCloudTemplate(): boolean
	local meshId = MeshAssets.meshId(PetCloud.MESH)
	local entry = MeshAssets.get(PetCloud.MESH)
	if not (meshId and entry and entry.size) then
		return false
	end
	local folder = ReplicatedStorage:FindFirstChild(PetCloud.FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = PetCloud.FOLDER
		folder.Parent = ReplicatedStorage
	end
	if (folder :: Folder):FindFirstChild(PetCloud.MESH) then
		return true
	end
	local base = Retry.run(function()
		local made = template(meshId)
		if not made then
			cache[meshId] = nil -- template() remembers a failure; forget it so the next try asks again
		end
		return made
	end, MeshSwap.PET_CLOUD_RETRY_DELAYS, task.wait)
	if not base then
		warn(`[Server] MeshSwap {PetCloud.MESH}: no template after {1 + #MeshSwap.PET_CLOUD_RETRY_DELAYS} tries`)
		return false
	end
	local mesh = base:Clone()
	mesh.Name = PetCloud.MESH
	mesh.Size = Vector3.new(entry.size[1], entry.size[2], entry.size[3])
	PetCloud.decor(mesh)
	mesh.Parent = folder
	return true
end

-- Bug #16: every plot's MergeVat disc wears the merge_vat model (1 MeshPart per plot, child "VatMesh" of the disc),
-- independent of FEATURES.MergeVat3 (the 3-slime gameplay stays behind its flag; only the look changes). The disc
-- keeps its name, position, collision and MergePrompt; it is only made invisible, and only once the
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
			count += 1
		end
	end
	return count
end

type Job = { meshId: string, fidelity: string? }

-- Every template apply() and swapPlotVats() will ask for, once each.
local function slotJobs(): { Job }
	local jobs: { Job } = {}
	local seen: { [string]: boolean } = {}
	local function add(name: string, fidelity: string?)
		local meshId = MeshAssets.meshId(name)
		local key = if fidelity then `{meshId}|{fidelity}` else meshId
		if meshId and key and not seen[key] then
			seen[key] = true
			table.insert(jobs, { meshId = meshId, fidelity = fidelity })
		end
	end
	for _, root in { workspace:FindFirstChild("Map"), workspace:FindFirstChild("Plots") } do
		if root then
			for _, inst in root:GetDescendants() do
				local name = inst:GetAttribute("MeshAsset")
				if not ((inst:IsA("BasePart") or inst:IsA("Model")) and typeof(name) == "string") then
					continue
				end
				if Config.FEATURES.FountainSplit and name == "slime_fountain" then
					for _, piece in MeshAssets.FOUNTAIN_SPLIT do
						add(piece, splitFidelity(piece))
					end
				else
					add(name, MeshAssets.collision(name))
				end
			end
		end
	end
	add(VatDecor.MESH, MeshAssets.collision(VatDecor.MESH))
	return jobs
end

-- Fetches every slot template on PREFETCH_WORKERS threads and returns once all have answered (a failed one is
-- cached as failed). Places nothing. Yields; returns how many templates it asked for.
function MeshSwap.prefetch(): number
	local jobs = slotJobs()
	local workers = math.min(MeshSwap.PREFETCH_WORKERS, #jobs)
	if workers == 0 then
		return 0
	end
	local main = coroutine.running()
	local nextJob, finished, parked = 1, 0, false
	for _ = 1, workers do
		task.spawn(function()
			while nextJob <= #jobs do
				local job = jobs[nextJob]
				nextJob += 1
				pcall(template, job.meshId, job.fidelity)
			end
			finished += 1
			if finished == workers and parked then
				task.spawn(main)
			end
		end)
	end
	if finished < workers then
		parked = true
		coroutine.yield()
	end
	return #jobs
end

-- The boot path: prefetch, place the slot meshes and the merge vats, then mark the world ready for the clients'
-- loading screen. Each step is pcall'd; the attribute is set whatever happened, so no client waits on a failure.
-- Yields; returns how many meshes were placed.
function MeshSwap.applyAll(): number
	local placed = 0
	for _, step in { MeshSwap.prefetch, MeshSwap.apply, MeshSwap.swapPlotVats } do
		local ok, result = pcall(step)
		if not ok then
			warn(`[Server] MeshSwap: {result}`)
		elseif step ~= MeshSwap.prefetch then
			placed += result
		end
	end
	workspace:SetAttribute(Constants.WORLD_MESHES_READY_ATTRIBUTE, true)
	return placed
end

-- Swaps every slot in `instances` and their descendants; `scope` is the Map or Plots root they sit under.
local function applyTo(instances: { Instance }, scope: Instance): number
	local count = 0
	for _, top in instances do
		local list = { top }
		for _, d in top:GetDescendants() do
			table.insert(list, d)
		end
		for _, inst in list do
			local name = inst:GetAttribute("MeshAsset")
			if
				(inst:IsA("BasePart") or inst:IsA("Model"))
				and typeof(name) == "string"
				and swap(inst :: any, name, scope)
			then
				count += 1
			end
		end
	end
	return count
end

-- Meshes for slots added after boot (server/BaseFloors' upper floors). Yields while a template loads.
function MeshSwap.applyUnder(instances: { Instance }): number
	local plots = workspace:FindFirstChild("Plots")
	return if plots then applyTo(instances, plots) else 0
end

-- Returns how many placeholders got a mesh.
function MeshSwap.apply(): number
	local count = 0
	for _, root in { workspace:FindFirstChild("Map"), workspace:FindFirstChild("Plots") } do
		if root then
			count += applyTo(root:GetChildren(), root)
		end
	end
	if slidePcdPlaced then
		slidePcdPlaced = false
		FountainColliders.retirePcd()
	end
	return count
end

return MeshSwap
