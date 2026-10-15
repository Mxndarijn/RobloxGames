--!strict
--[[
	FollowPets (VisualsClient module, FEATURES.FollowPets)

	Every player whose attribute PetSlimeId (Constants.PET_ATTRIBUTE) is set
	gets a small client-only copy of that slime trotting behind them. The copy
	is cloned from the slime's replicated model (tag Constants.SLIME_TAG,
	attribute SlimeId), stripped of prompts, tags, welds to the outside and
	gameplay attributes, scaled to SCALE and anchored. Pets live in a local
	workspace folder "ClientPets"; no remotes, nothing replicates.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local FollowPets = {}

FollowPets.SCALE = 0.45
FollowPets.POLL = 0.5
FollowPets.OFFSET = CFrame.new(2.6, 0, 3.2) -- behind and to the right of the player
FollowPets.MAX_DISTANCE = 200
FollowPets.FOLLOW_RATE = 8

type Pet = { model: Model, slimeId: string, phase: number }

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
	if not Config.FEATURES.FollowPets then
		return
	end
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
				local model = source and makePet(source, player.UserId)
				if model and root then
					model:PivotTo(root.CFrame * FollowPets.OFFSET)
					model.Parent = folder
					pets[player] = { model = model, slimeId = id, phase = math.random() * math.pi * 2 }
				elseif model then
					model:Destroy()
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

	RunService.RenderStepped:Connect(function(dt: number)
		local camera = workspace.CurrentCamera
		local now = os.clock()
		for player, pet in pets do
			local root = rootOf(player)
			if root and camera and (root.Position - camera.CFrame.Position).Magnitude < FollowPets.MAX_DISTANCE then
				-- Feet level: the HumanoidRootPart centre is ~3 studs above the ground.
				local bob = math.abs(math.sin(now * 6 + pet.phase)) * 0.6
				local goal = root.CFrame * FollowPets.OFFSET * CFrame.new(0, -3 + bob, 0)
				local alpha = 1 - math.exp(-dt * FollowPets.FOLLOW_RATE)
				pet.model:PivotTo(pet.model:GetPivot():Lerp(goal, alpha))
			end
		end
	end)
end

return FollowPets
