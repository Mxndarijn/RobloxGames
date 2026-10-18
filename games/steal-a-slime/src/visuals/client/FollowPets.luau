--!strict
--[[
	FollowPets (VisualsClient module)

	Every player whose attribute PetSlimeId (Constants.PET_ATTRIBUTE) is set
	gets a small client-only copy of that slime trotting behind them. The copy
	is cloned from the slime's replicated model (tag Constants.SLIME_TAG,
	attribute SlimeId), stripped of prompts, tags, welds to the outside and
	gameplay attributes, scaled to SCALE and anchored, and stands on a low-poly
	cloud (MeshAssets "pet_cloud", CreateMeshPartAsync once, cloned per pet; no
	cloud if it fails to load). The cloud + pet glide after the owner with the
	pure PetFollow spring (one RenderStepped connection for every pet). Pets
	live in a local workspace folder "ClientPets"; no remotes, nothing
	replicates.
]]

local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local MeshAssets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MeshAssets"))
local PetFollow = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("PetFollow"))

local PetRig = require(script.Parent:WaitForChild("PetRig"))

local FollowPets = {}

FollowPets.SCALE = 0.55 -- the slime on the cloud: 1.65 studs wide, readable at phone size
FollowPets.CLOUD_SCALE = 0.9 -- of the native 3.3 x 1.2 x 2.4 mesh
FollowPets.CLOUD_SINK = 0.12 -- the slime's foot sinks this far into the cloud's top (studs)
FollowPets.POLL = 0.5
FollowPets.MAX_DISTANCE = 200
-- Follow motion (offset behind and right of the owner, spring, bob) lives in PetFollow.

type Pet = { model: Model, slimeId: string, follow: PetFollow.State, hasCloud: boolean }

local function findSource(slimeId: string): Model?
	for _, model in CollectionService:GetTagged(Constants.SLIME_TAG) do
		if model:IsA("Model") and model:GetAttribute("SlimeId") == slimeId then
			return model
		end
	end
	return nil
end

local function makePet(source: Model, userId: number): Model?
	local pet = source:Clone()
	if not pet then
		return nil
	end
	pet.Name = `Pet_{userId}`
	PetRig.stripLife(pet) -- the clone may carry the #71 life rig; pets are rigid
	CollectionService:RemoveTag(pet, Constants.SLIME_TAG)
	for _, name in { "OwnerUserId", "State", "Price", Constants.BOSS_ATTRIBUTE } do
		pet:SetAttribute(name, nil)
	end
	for _, inst in pet:GetDescendants() do
		for _, tag in CollectionService:GetTags(inst) do
			CollectionService:RemoveTag(inst, tag)
		end
		if inst:IsA("ProximityPrompt") or inst:IsA("BaseScript") then
			inst:Destroy()
		elseif inst:IsA("WeldConstraint") then
			local p0, p1 = inst.Part0, inst.Part1
			if not (p0 and p0:IsDescendantOf(pet)) or not (p1 and p1:IsDescendantOf(pet)) then
				inst:Destroy()
			end
		elseif inst:IsA("BasePart") then
			inst.Anchored = true
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false
			inst.CastShadow = false
		end
	end
	pcall(function()
		pet:ScaleTo(FollowPets.SCALE)
	end)
	return pet
end

-- The cloud MeshPart, loaded once: "loading" until the first CreateMeshPartAsync ends, then "ready" or "failed".
local cloudTemplate: MeshPart? = nil
local cloudStatus: string = "loading"

local function cloudIs(status: string): boolean
	return cloudStatus == status
end

local function loadCloud()
	local meshId = MeshAssets.meshId("pet_cloud")
	local entry = MeshAssets.get("pet_cloud")
	if not (meshId and entry and entry.size) then
		cloudStatus = "failed"
		return
	end
	local ok, mesh = pcall(function()
		return (AssetService :: any):CreateMeshPartAsync(meshId, {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Automatic,
		})
	end)
	if ok and mesh then
		local part: MeshPart = mesh
		local size = entry.size :: { number }
		part.Name = "Cloud"
		part.Size = Vector3.new(size[1], size[2], size[3]) * FollowPets.CLOUD_SCALE
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		cloudTemplate = part
		cloudStatus = "ready"
	else
		cloudStatus = "failed"
	end
end

-- Wrap the slime clone: Model "Pet_<id>" = cloud (PrimaryPart) + "Slime" standing on its top. With no cloud a
-- small invisible Mount is the PrimaryPart and the slime stands level with where the cloud's underside would
-- be. The wrapper's pivot is the cloud centre: PetFollow's goal. Returns the wrapper and whether it has a cloud.
local function mount(slime: Model, userId: number): (Model, boolean)
	local wrapper = Instance.new("Model")
	wrapper.Name = `Pet_{userId}`
	slime.Name = "Slime"
	local template = cloudTemplate
	local anchor: BasePart
	local halfHeight: number
	if template then
		anchor = template:Clone()
		halfHeight = anchor.Size.Y / 2
	else
		local part = Instance.new("Part")
		part.Name = "Mount"
		part.Size = Vector3.new(1, 1, 1)
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		anchor = part
		halfHeight = -PetFollow.OFFSET_Y - 3 -- ground level: the slime's foot sits at the owner's feet
	end
	anchor.CFrame = CFrame.new()
	anchor.Parent = wrapper
	wrapper.PrimaryPart = anchor
	-- slime centred over the anchor, foot sunk CLOUD_SINK into the top
	slime:PivotTo(CFrame.new())
	local box, size = slime:GetBoundingBox()
	local foot = box.Position.Y - size.Y / 2
	local sink = if template then FollowPets.CLOUD_SINK else 0
	slime:PivotTo(CFrame.new(-box.Position.X, halfHeight - sink - foot, -box.Position.Z))
	slime.Parent = wrapper
	return wrapper, template ~= nil
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function FollowPets.start()
	local folder = Instance.new("Folder")
	folder.Name = "ClientPets"
	folder.Parent = workspace
	local pets: { [Player]: Pet } = {}

	local function remove(player: Player)
		local pet = pets[player]
		if pet then
			pet.model:Destroy()
			pets[player] = nil
		end
	end

	local function sync()
		for player in pets do
			if player.Parent ~= Players then
				remove(player)
			end
		end
		for _, player in Players:GetPlayers() do
			local id = player:GetAttribute(Constants.PET_ATTRIBUTE)
			local pet = pets[player]
			if type(id) ~= "string" then
				remove(player)
			elseif
				not pet
				or pet.slimeId ~= id
				or not pet.model.Parent
				or (cloudIs("ready") and not pet.hasCloud) -- the cloud arrived after this pet was made
			then
				remove(player)
				local source = findSource(id)
				local root = rootOf(player)
				local slime = source and makePet(source, player.UserId)
				if slime and root and not cloudIs("loading") then
					local model, hasCloud = mount(slime, player.UserId)
					model.Parent = folder -- PetFollow's first step snaps it next to the owner
					pets[player] = {
						model = model,
						slimeId = id,
						follow = PetFollow.new(math.random() * math.pi * 2),
						hasCloud = hasCloud,
					}
				elseif slime then
					slime:Destroy() -- next poll, once the cloud load has ended
				end
			end
		end
	end

	task.spawn(loadCloud)
	task.spawn(function()
		while true do
			local ok, err = pcall(sync)
			if not ok then
				warn(`[VisualsClient] pets: {err}`)
			end
			task.wait(FollowPets.POLL)
		end
	end)

	-- One connection drives every pet. Per pet: plain-number PetFollow step, one CFrame build for PivotTo.
	local maxSq = FollowPets.MAX_DISTANCE * FollowPets.MAX_DISTANCE
	RunService.RenderStepped:Connect(function(dt: number)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local eye = camera.CFrame.Position
		for player, pet in pets do
			local root = rootOf(player)
			if root then
				local pos = root.Position
				local off = pos - eye
				if off:Dot(off) < maxSq then
					local yaw = math.rad(root.Orientation.Y)
					local f = pet.follow
					PetFollow.step(f, dt, pos.X, pos.Y, pos.Z, yaw)
					local half = f.yaw * 0.5
					pet.model:PivotTo(CFrame.new(f.x, f.y + f.bob, f.z, 0, math.sin(half), 0, math.cos(half)))
				end
			end
		end
	end)
end

return FollowPets
