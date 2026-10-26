--!strict
--[[
	FollowPets (VisualsClient module)

	Every player whose attribute PetSlimeId (Constants.PET_ATTRIBUTE) is set
	gets a small client-only copy of that slime trotting behind them. The copy
	is cloned from the slime's replicated model (tag Constants.SLIME_TAG,
	attribute SlimeId), stripped of prompts, tags, welds to the outside and
	gameplay attributes, shrunk to a hand-sized pet (PetCloud.petScale) and anchored, and rides the seat its owner
	picked (Player attribute PetSeat, Constants.PET_SEAT_ATTRIBUTE: a Config.PET_SEATS id) sized to it (PetCloud: a
	clone of that seat's template the server publishes in ReplicatedStorage.PetCloudMeshes). While that template is
	not there the pet rides the plain cloud, and without any template an invisible Mount. The pet is made at once
	and built again (in place) when its seat changes or a better template shows up.
	The cloud + pet glide after the owner with the pure PetFollow spring (one
	RenderStepped connection for every pet). Pets live in a local workspace folder "ClientPets"; no remotes, nothing
	replicates.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local PetCloud = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("PetCloud"))
local PetFollow = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("PetFollow"))

local PetRig = require(script.Parent:WaitForChild("PetRig"))

local FollowPets = {}

FollowPets.POLL = 0.5
FollowPets.MAX_DISTANCE = 200
-- Follow motion (offset behind and right of the owner, spring, bob) lives in PetFollow.

-- `shown`: the template the pet rides (its mesh name), nil on a Mount.
type Pet = { model: Model, slimeId: string, shown: string?, follow: PetFollow.State }

-- The template a pet of `player` should ride: its seat's, else the plain cloud's, else nil.
local function templateFor(player: Player): BasePart?
	local id = player:GetAttribute(Constants.PET_SEAT_ATTRIBUTE)
	for _, seat in Config.PET_SEATS do
		if seat.id == id then
			local own = PetCloud.find(ReplicatedStorage, seat.mesh)
			if own then
				return own
			end
			break
		end
	end
	return PetCloud.find(ReplicatedStorage)
end

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
	local _, size = PetCloud.visibleBox(pet)
	local factor = PetCloud.petScale(size)
	pcall(function()
		pet:ScaleTo(pet:GetScale() * factor)
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
			local template = templateFor(player)
			local shown = if template then template.Name else nil
			if type(id) ~= "string" then
				remove(player)
			elseif not pet or pet.slimeId ~= id or not pet.model.Parent or pet.shown ~= shown then
				-- Same slime on a new seat: keep where it glides, so it doesn't jump.
				local follow = if pet and pet.slimeId == id then pet.follow else nil
				remove(player)
				local source = findSource(id)
				local root = rootOf(player)
				local slime = source and makePet(source, player.UserId)
				if slime and root then
					local model = PetCloud.mount(slime, player.UserId, template)
					model.Parent = folder -- PetFollow's first step snaps it next to the owner
					pets[player] = {
						model = model,
						slimeId = id,
						shown = shown,
						follow = follow or PetFollow.new(math.random() * math.pi * 2),
					}
				elseif slime then
					slime:Destroy()
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
