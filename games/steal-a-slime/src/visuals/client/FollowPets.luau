--!strict
--[[
	FollowPets (VisualsClient module)

	Every player whose attribute PetSlimeId (Constants.PET_ATTRIBUTE) is set
	gets a small client-only copy of that slime trotting behind them. The copy
	is cloned from the slime's replicated model (tag Constants.SLIME_TAG,
	attribute SlimeId), stripped of prompts, tags, welds to the outside and
	gameplay attributes, scaled to SCALE and anchored, and stands on a low-poly
	cloud sized to it (PetCloud: a clone of the template the server publishes in
	ReplicatedStorage.PetCloudMeshes; the pet is made at once and gets the cloud
	when the template shows up, or stays on its invisible Mount if it never does).
	The cloud + pet glide after the owner with the pure PetFollow spring (one
	RenderStepped connection for every pet). Pets live in a local workspace folder "ClientPets"; no remotes, nothing
	replicates.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local PetCloud = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("PetCloud"))
local PetFollow = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("PetFollow"))

local PetRig = require(script.Parent:WaitForChild("PetRig"))

local FollowPets = {}

FollowPets.SCALE = 0.55 -- of the slime as built (its size and look kept); PetCloud grows the cloud to fit it
FollowPets.POLL = 0.5
FollowPets.MAX_DISTANCE = 200
-- Follow motion (offset behind and right of the owner, spring, bob) lives in PetFollow.

type Pet = { model: Model, slimeId: string, follow: PetFollow.State }

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
			elseif not pet or pet.slimeId ~= id or not pet.model.Parent then
				remove(player)
				local source = findSource(id)
				local root = rootOf(player)
				local slime = source and makePet(source, player.UserId)
				if slime and root then
					local model = PetCloud.mount(slime, player.UserId, PetCloud.find(ReplicatedStorage))
					model.Parent = folder -- PetFollow's first step snaps it next to the owner
					pets[player] = {
						model = model,
						slimeId = id,
						follow = PetFollow.new(math.random() * math.pi * 2),
					}
				elseif slime then
					slime:Destroy()
				end
			elseif not PetCloud.hasCloud(pet.model) then
				local template = PetCloud.find(ReplicatedStorage) -- published after this pet was made
				if template then
					PetCloud.attach(pet.model, template)
				end
			end
		end
	end

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
