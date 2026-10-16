--!strict
--[[
	FountainTierFx (VisualsClient module, FEATURES.FountainTiers, CONTRACT.md §19)

	Draws the fountain's tier from the workspace attribute Constants.FOUNTAIN_TIER_ATTRIBUTE (the server
	sets it only with the flag on; absent = tier 1 = nothing added):
	  * the lantern-post ring and the floating crest (clones of ReplicatedStorage.FountainTierMeshes,
	    posed by FountainTierDecor, tinted per tier; the crest spins and bobs);
	  * the goo crown light (Map.Volcano.Crater.CraterGlow) takes the tier's glow colour; the built colour is
	    remembered in an attribute and put back at tier 1.
	Local changes only; never fires remotes. Studio only: the SlimeUI attribute PcwFountainTier (1..4) forces
	the tier, for the pc-watcher shots.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local FountainTiers = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FountainTiers"))
local Visuals = ReplicatedStorage:WaitForChild("Visuals")
local FountainTierDecor = require(Visuals:WaitForChild("FountainTierDecor"))

local FountainTierFx = {}

local FOLDER_NAME = "ClientFountainTier"
local ORIG_COLOR, ORIG_BRIGHTNESS = "FountainTierOrigColor", "FountainTierOrigBrightness"

local started = false
local shown = 0 -- tier on screen (0 = none yet)
local crest: BasePart? = nil
local crestBase: CFrame? = nil

local function currentTier(): number
	if RunService:IsStudio() and Players.LocalPlayer then
		local gui = Players.LocalPlayer:FindFirstChild("PlayerGui")
		local ui = gui and gui:FindFirstChild("SlimeUI")
		local forced = ui and ui:GetAttribute("PcwFountainTier")
		if type(forced) == "number" then
			return math.clamp(math.floor(forced), 1, FountainTiers.MAX_TIER)
		end
	end
	local tier = workspace:GetAttribute(Constants.FOUNTAIN_TIER_ATTRIBUTE)
	return if type(tier) == "number" then math.clamp(math.floor(tier), 1, FountainTiers.MAX_TIER) else 1
end

local function folder(): Folder
	local existing = workspace:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = FOLDER_NAME
	f.Parent = workspace
	return f
end

local function craterGlow(): PointLight?
	local map = workspace:FindFirstChild("Map")
	local volcano = map and map:FindFirstChild("Volcano")
	local crater = volcano and volcano:FindFirstChild("Crater")
	local light = crater and crater:FindFirstChild("CraterGlow")
	return if light and light:IsA("PointLight") then light else nil
end

local function setGlow(tier: number)
	local light = craterGlow()
	if not light then
		return
	end
	if light:GetAttribute(ORIG_COLOR) == nil then
		light:SetAttribute(ORIG_COLOR, light.Color)
		light:SetAttribute(ORIG_BRIGHTNESS, light.Brightness)
	end
	if tier <= 1 then
		light.Color = light:GetAttribute(ORIG_COLOR) :: Color3
		light.Brightness = light:GetAttribute(ORIG_BRIGHTNESS) :: number
		return
	end
	local look = FountainTiers.look(tier)
	light.Color = Color3.fromRGB(look.glow[1], look.glow[2], look.glow[3])
	light.Brightness = (light:GetAttribute(ORIG_BRIGHTNESS) :: number) * look.glowBrightness
end

local function build(pose: FountainTierDecor.Pose, templates: Instance?): BasePart?
	local template = if templates then templates:FindFirstChild(pose.mesh) else nil
	if not (template and template:IsA("BasePart")) then
		return nil
	end
	local mesh = template:Clone()
	mesh.Name = pose.mesh
	mesh.Color = Color3.fromRGB(pose.color[1], pose.color[2], pose.color[3])
	mesh.Material = (Enum.Material :: any)[pose.material]
	mesh.CFrame = CFrame.new(pose.position[1], pose.position[2], pose.position[3])
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.CanTouch = false
	mesh.CastShadow = false
	return mesh
end

-- Rebuilds ring / crest / glow for `tier` (idempotent: nothing happens while the tier is on screen).
function FountainTierFx.apply(tier: number, templates: Instance?)
	if tier == shown then
		return
	end
	local f = folder()
	f:ClearAllChildren()
	crest = nil
	crestBase = nil
	local poses = FountainTierDecor.poses(tier)
	if poses.ring then
		local ring = build(poses.ring, templates)
		if ring then
			ring.Parent = f
		end
	end
	if poses.crest then
		local part = build(poses.crest, templates)
		if part then
			part.Parent = f
			crest = part
			crestBase = part.CFrame
		end
	end
	setGlow(tier)
	-- Not drawn yet (templates still publishing): try again next refresh.
	shown = if (poses.ring or poses.crest) and f:FindFirstChildOfClass("MeshPart") == nil then 0 else tier
end

function FountainTierFx.start()
	if started then
		return
	end
	started = true
	local templates = ReplicatedStorage:FindFirstChild("FountainTierMeshes")
	local sinceCheck = 0
	RunService.Heartbeat:Connect(function(dt)
		sinceCheck += dt
		if sinceCheck >= 0.5 then
			sinceCheck = 0
			templates = templates or ReplicatedStorage:FindFirstChild("FountainTierMeshes")
			local tier = currentTier()
			if tier > 1 or shown > 1 then
				local ok, err = pcall(function()
					FountainTierFx.apply(tier, templates)
				end)
				if not ok then
					warn(`[VisualsClient] FountainTierFx: {err}`)
				end
			end
		end
		local part, base = crest, crestBase
		if part and base and part.Parent then
			local bob, yaw = FountainTierDecor.crestMotion(os.clock())
			part.CFrame = base * CFrame.new(0, bob, 0) * CFrame.Angles(0, yaw, 0)
		end
	end)
end

return FountainTierFx
