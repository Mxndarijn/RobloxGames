--!strict
--[[
	FountainTierFx (VisualsClient module, FEATURES.FountainTiers, CONTRACT.md §19)

	Draws the fountain's tier from the workspace attribute Constants.FOUNTAIN_TIER_ATTRIBUTE (the server
	sets it only with the flag on; absent = tier 1 = as built): the goo crown light
	(Map.Volcano.Crater.CraterGlow) takes the tier's glow colour; the built colour is remembered in an
	attribute and put back at tier 1.
	Local changes only; never fires remotes. Studio only: the SlimeUI attribute PcwFountainTier (1..4) forces
	the tier, for the pc-watcher shots.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local FountainTiers = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FountainTiers"))

local FountainTierFx = {}

local ORIG_COLOR, ORIG_BRIGHTNESS = "FountainTierOrigColor", "FountainTierOrigBrightness"

local started = false
local shown = 0 -- tier on screen (0 = none yet)

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

-- Sets the glow for `tier` (idempotent: nothing happens while the tier is on screen).
function FountainTierFx.apply(tier: number)
	if tier == shown then
		return
	end
	setGlow(tier)
	shown = tier
end

function FountainTierFx.start()
	if started then
		return
	end
	started = true
	local sinceCheck = 0
	RunService.Heartbeat:Connect(function(dt)
		sinceCheck += dt
		if sinceCheck < 0.5 then
			return
		end
		sinceCheck = 0
		local tier = currentTier()
		if tier > 1 or shown > 1 then
			local ok, err = pcall(FountainTierFx.apply, tier)
			if not ok then
				warn(`[VisualsClient] FountainTierFx: {err}`)
			end
		end
	end)
end

return FountainTierFx
