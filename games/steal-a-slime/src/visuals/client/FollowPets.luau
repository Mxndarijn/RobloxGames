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
	A player who picked a SlimeDex species for the pet (Player attribute PetSpecies, Constants.PET_SPECIES_ATTRIBUTE)
	gets that species instead: a copy of its kit mesh from this player's kit folder (PlayerGui.SlimeKits, which the
	server fills for every picked pet in the server), worn like the SlimeDex preview. Until the kit is there the pet is
	the Auto slime above. A picked pet shows even when its owner has no slime.
	The cloud + pet fly after the owner on PetFollow's leash (one RenderStepped connection for every pet); the owner's
	Humanoid (FloorMaterial, Jumping / Freefall state) tells PetFollow when they are in the air, so a jump doesn't throw the cloud up. Pets live in a local workspace folder "ClientPets"; no remotes, nothing
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

local MeshAssets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MeshAssets"))

local PetRig = require(script.Parent:WaitForChild("PetRig"))

local FollowPets = {}

FollowPets.POLL = 0.5
FollowPets.MAX_DISTANCE = 200
-- Follow motion (leash, springs, jump hold, bob) lives in PetFollow.

-- `key`: what rides ("slime:<SlimeId>" or "species:<id>"); a new key builds the pet again.
-- `shown`: the template the pet rides (its mesh name), nil on a Mount.
-- `source`: the replicated model or kit mesh it was cloned from; a hatch or kit rebuild destroys it, so the pet is
-- cloned again.
type Pet = { model: Model, key: string, source: Instance, shown: string?, follow: PetFollow.State }

local IMPORT_TURN = CFrame.Angles(0, math.rad(MeshAssets.IMPORT_YAW), 0)
local KIT_PREFIX = "slime_"

-- The kit mesh of `speciesId` in this player's kit folder, or nil while it is not there.
local function findKit(speciesId: string): BasePart?
	local gui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local folder = gui and gui:FindFirstChild(Constants.SLIME_KITS_FOLDER)
	local kit = folder and folder:FindFirstChild(KIT_PREFIX .. speciesId)
	if kit and kit:IsA("BasePart") then
		return kit
	end
	return nil
end

-- A pet model of a picked species: its kit mesh worn like the SlimeDex preview (Color white, turned to face -Z),
-- shrunk to a pet like a cloned slime.
local function makeSpeciesPet(kit: BasePart, userId: number): Model
	local pet = Instance.new("Model")
	pet.Name = `Pet_{userId}`
	local part = kit:Clone()
	part.Name = "Mesh"
	part.Color = Color3.new(1, 1, 1)
	part.CFrame = IMPORT_TURN
	PetCloud.decor(part)
	part.Parent = pet
	pet.PrimaryPart = part
	local _, size = PetCloud.visibleBox(pet)
	pcall(function()
		pet:ScaleTo(pet:GetScale() * PetCloud.petScale(size))
	end)
	return pet
end

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

-- The slime's replicated model; never a Mystery Egg (eggs don't ride the cloud).
local function findSource(slimeId: string): Model?
	for _, model in CollectionService:GetTagged(Constants.SLIME_TAG) do
		if
			model:IsA("Model")
			and model:GetAttribute("SlimeId") == slimeId
			and model:GetAttribute(Constants.EGG_KIND_ATTRIBUTE) == nil
		then
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
			local species = player:GetAttribute(Constants.PET_SPECIES_ATTRIBUTE)
			local kit = if type(species) == "string" and species ~= "" then findKit(species) else nil
			local key = if kit then `species:{species}` elseif type(id) == "string" then `slime:{id}` else nil
			local pet = pets[player]
			local template = templateFor(player)
			local shown = if template then template.Name else nil
			if key == nil then
				remove(player)
			elseif not pet or pet.key ~= key or not pet.model.Parent or not pet.source.Parent or pet.shown ~= shown then
				-- A new pet or seat keeps where it flies, so it doesn't jump.
				local follow = if pet then pet.follow else nil
				remove(player)
				local root = rootOf(player)
				local source: Instance?, slime: Model? = nil, nil
				if kit then
					source, slime = kit, makeSpeciesPet(kit, player.UserId)
				else
					local model = findSource(id :: string)
					source, slime = model, model and makePet(model, player.UserId)
				end
				if slime and source and root then
					local model = PetCloud.mount(slime, player.UserId, template)
					model.Parent = folder -- PetFollow's first step snaps it next to the owner
					pets[player] = {
						model = model,
						key = key,
						source = source,
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
					local humanoid = (root.Parent :: Instance):FindFirstChildOfClass("Humanoid")
					local state = humanoid and humanoid:GetState()
					local grounded = humanoid == nil
						or (
							humanoid.FloorMaterial ~= Enum.Material.Air
							and state ~= Enum.HumanoidStateType.Jumping
							and state ~= Enum.HumanoidStateType.Freefall
						)
					PetFollow.step(f, dt, pos.X, pos.Y, pos.Z, yaw, grounded)
					local half = f.yaw * 0.5
					pet.model:PivotTo(CFrame.new(f.x, f.y + f.bob, f.z, 0, math.sin(half), 0, math.cos(half)))
				end
			end
		end
	end)
end

return FollowPets
