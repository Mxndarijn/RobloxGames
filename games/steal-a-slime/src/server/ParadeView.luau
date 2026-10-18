--!strict
--[[
	ParadeView (Roblox adapter, owner: Phoenix, FEATURES.Parade)

	ParadeView.place(load): Folder?
	  Lays the goo lane on the plaza under workspace.Map.Plaza.ParadeLane: ONE
	  MeshPart, the kit's smooth curved goo channel (MeshAssets "slime_lane",
	  models/slime_lane.py: slide mouth, lead-in, ENTRY, round to the drain; crown
	  LANE_Y, soft rounded edges just under the ground), set at ParadeLane.MESH_PIVOT.
	  `load` (default MeshSwap.load, yields) fetches the mesh in the background. While the
	  mesh is not uploaded (no meshId) or fails to load, the lane is drawn from
	  ParadeLane.strips() instead: one Cylinder Part per segment (the lane from the slide
	  mouth through the lead-in to ENTRY and round to the drain). Each lies along
	  the lane, wide and sunk so only its crown shows: top LANE_Y on the
	  centreline, falling to the ground at the lane's edges (a soft rounded
	  edge), bends mitred so joints do not show. Visual only: anchored, no
	  collision, query or touch, so players walk over it and ground raycasts
	  (drops, landings) pass through. Glossy goo in the slide's water colour
	  (ParadeLane.COLOR). Idempotent.
	  Plaza.DrainMouth (always strips): ParadeLane.drainStrips(), the lane's goo carrying on from its end over the
	  drain's curb to just inside the rim, so the path visibly pours into the funnel.

	ParadeView.splash(effects): Instance?
	  The goo splash at the drain when a lane slime leaves (World event
	  "Drained"): Visuals.Effects' "Eruption" goo puffs on a short burst,
	  cleaned up with Debris. nil without Effects.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local MeshAssets = require(ReplicatedStorage.Shared.MeshAssets)
local MeshSwap = require(script.Parent.MeshSwap)
local ParadeLane = require(ReplicatedStorage.Shared.ParadeLane)

local ParadeView = {}

ParadeView.FOLDER = "ParadeLane"
ParadeView.MOUTH_FOLDER = "DrainMouth"
ParadeView.SPLASH_EMITTER = "Eruption" -- Visuals.Effects preset: goo splash puffs
ParadeView.SPLASH_COUNT = 24
ParadeView.SPLASH_SECONDS = 0.2 -- burst length (server emitters run on Rate; Emit doesn't replicate)

local GOO = ParadeLane.COLOR

local function layStrips(folder: Folder, strips: { any })
	for _, strip in strips do
		local c = strip.cf
		local part = Instance.new("Part")
		part.Name = strip.name
		part.Size = Vector3.new(strip.size[1], strip.size[2], strip.size[3])
		part.CFrame = CFrame.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Shape = if strip.shape == "Block" then Enum.PartType.Block else Enum.PartType.Cylinder
		part.Material = Enum.Material.SmoothPlastic
		part.Reflectance = 0.08
		part.Color = Color3.fromRGB(GOO[1], GOO[2], GOO[3])
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = folder
	end
end

-- The one lane MeshPart: laid like a MeshSwap slot (the box centre = the mesh's bbox centre, turned IMPORT_YAW).
local function layMesh(folder: Folder, mesh: MeshPart)
	local at = ParadeLane.MESH_PIVOT
	mesh.Name = "Lane"
	mesh.CFrame = CFrame.new(at[1], at[2], at[3]) * CFrame.Angles(0, math.rad(MeshAssets.IMPORT_YAW), 0)
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.CanTouch = false
	mesh.CastShadow = false
	mesh.Material = Enum.Material.SmoothPlastic
	mesh.Reflectance = 0.08
	mesh.Color = Color3.fromRGB(255, 255, 255) -- the vertex colours carry the goo (ParadeLane.COLOR) and its darker rim
	mesh.Parent = folder
end

function ParadeView.place(load: ((string) -> MeshPart?)?): Folder?
	local map = workspace:FindFirstChild(Constants.MAP_FOLDER)
	local plaza = map and map:FindFirstChild("Plaza")
	if not plaza then
		return nil
	end
	local existing = plaza:FindFirstChild(ParadeView.FOLDER)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = ParadeView.FOLDER
	folder.Parent = plaza
	-- The goo carries on from the lane's end over the drain's curb into the funnel (own folder: the lane mesh
	-- swap clears ParadeLane's children).
	local mouth = Instance.new("Folder")
	mouth.Name = ParadeView.MOUTH_FOLDER
	mouth.Parent = plaza
	layStrips(mouth, ParadeLane.drainStrips())
	if MeshAssets.meshId(ParadeLane.MESH) then
		-- The mesh loads in the background; the strips stand in until it is there (and stay if it never loads).
		layStrips(folder, ParadeLane.strips())
		task.spawn(function()
			local ok, mesh = pcall(load or MeshSwap.load, ParadeLane.MESH)
			if ok and mesh and folder.Parent then
				for _, d in folder:GetChildren() do
					d:Destroy()
				end
				layMesh(folder, mesh)
			elseif not ok then
				warn(`[Server] ParadeView lane mesh: {mesh}`)
			end
		end)
	else
		layStrips(folder, ParadeLane.strips())
	end
	return folder
end

function ParadeView.splash(effects: any): Instance?
	if not effects or type(effects.emitter) ~= "function" then
		return nil
	end
	local d = ParadeLane.DRAIN
	local holder = Instance.new("Part")
	holder.Name = "DrainSplash"
	holder.Size = Vector3.new(1, 1, 1)
	holder.Transparency = 1
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	-- The preset blows along local +X (the Crater cylinder's up): turn +X to world up.
	holder.CFrame = CFrame.new(d.x, d.lipY, d.z) * CFrame.Angles(0, 0, math.pi / 2)
	local emitter = effects.emitter(ParadeView.SPLASH_EMITTER) :: ParticleEmitter
	emitter.Rate = ParadeView.SPLASH_COUNT / ParadeView.SPLASH_SECONDS
	emitter.Parent = holder
	holder.Parent = workspace
	task.delay(ParadeView.SPLASH_SECONDS, function()
		emitter.Enabled = false
	end)
	Debris:AddItem(holder, ParadeView.SPLASH_SECONDS + emitter.Lifetime.Max + 0.5)
	return holder
end

return ParadeView
