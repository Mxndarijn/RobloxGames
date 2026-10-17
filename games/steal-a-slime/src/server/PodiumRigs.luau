--!strict
--[[
	PodiumRigs: the Roblox adapter for PodiumAvatars. Builds R15 rigs from
	HumanoidDescriptions and stands them on workspace Podium_<rank> parts
	(the plaza mesh slots), anchored, non-colliding, facing the fountain like
	the podium, with a name + stat BillboardGui. Rigs live in
	workspace.PodiumAvatars.
]]

local Players = game:GetService("Players")

local PodiumAvatars = require(script.Parent.PodiumAvatars)

local PodiumRigs = {}

local FOLDER = "PodiumAvatars"

local function folder(): Folder
	local existing = workspace:FindFirstChild(FOLDER)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = FOLDER
	made.Parent = workspace
	return made
end

local function podium(rank: number): BasePart?
	local part = workspace:FindFirstChild(`Podium_{rank}`, true)
	return if part and part:IsA("BasePart") then part else nil
end

-- An empty text (empty podium) means no label at all: none is created, an existing one is removed.
local function label(rig: Model, text: string)
	local gui = rig:FindFirstChild("NameLabel") :: BillboardGui?
	if text == "" then
		if gui then
			gui:Destroy()
		end
		return
	end
	if not gui then
		local made = Instance.new("BillboardGui")
		made.Name = "NameLabel"
		made.Size = UDim2.fromOffset(180, 46)
		made.StudsOffsetWorldSpace = Vector3.new(0, 1.5, 0)
		made.MaxDistance = 90
		local adornee = rig:FindFirstChild("Head") or rig.PrimaryPart
		if adornee then
			made.Adornee = adornee
		end
		local textLabel = Instance.new("TextLabel")
		textLabel.Name = "Text"
		textLabel.BackgroundTransparency = 1
		textLabel.Size = UDim2.fromScale(1, 1)
		textLabel.Font = Enum.Font.GothamBold
		textLabel.TextScaled = true
		textLabel.TextColor3 = Color3.new(1, 1, 1)
		textLabel.TextStrokeTransparency = 0.4
		textLabel.Parent = made
		made.Parent = rig
		gui = made
	end
	local textLabel = (gui :: BillboardGui):FindFirstChild("Text") :: TextLabel?
	if textLabel then
		textLabel.Text = text
	end
end

-- Statue: anchored, no collisions/queries/touches, no default nameplate or scripts.
local function freeze(rig: Model)
	for _, inst in rig:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.Anchored = true
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false
		elseif inst:IsA("Humanoid") then
			inst.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			inst.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		elseif inst:IsA("Script") or inst:IsA("LocalScript") then
			inst:Destroy()
		end
	end
end

-- Grey block stand-in for an empty slot or when every rig call failed.
local function placeholder(): Model
	local rig = Instance.new("Model")
	rig.Name = "PodiumPlaceholder"
	local body = Instance.new("Part")
	body.Name = "Head"
	body.Size = Vector3.new(2, 4, 1)
	body.Color = Color3.fromRGB(150, 150, 160)
	body.Material = Enum.Material.SmoothPlastic
	body.Transparency = 0.5
	body.Parent = rig
	rig.PrimaryPart = body
	return rig
end

function PodiumRigs.adapter(): PodiumAvatars.Adapter
	return {
		fetchDescription = function(userId: number): any
			return Players:GetHumanoidDescriptionFromUserIdAsync(userId)
		end,
		buildRig = function(description: any?): any
			local desc = description or Instance.new("HumanoidDescription")
			return Players:CreateHumanoidModelFromDescriptionAsync(desc, Enum.HumanoidRigType.R15)
		end,
		placeholder = placeholder,
		displayName = function(userId: number, fallback: string): string
			local player = Players:GetPlayerByUserId(userId)
			return if player then player.DisplayName else fallback
		end,
		mount = function(rank: number, rig: any, text: string)
			local model = rig :: Model
			local base = podium(rank)
			if not base then
				model:Destroy()
				return
			end
			model.Name = `PodiumRig_{rank}`
			freeze(model)
			-- The podium's front faces the fountain; stand on its top face.
			local top = base.CFrame * CFrame.new(0, base.Size.Y / 2, 0)
			model:PivotTo(top)
			local box, size = model:GetBoundingBox()
			local lift = top.Position.Y - (box.Position.Y - size.Y / 2)
			model:PivotTo(top + Vector3.new(0, lift, 0))
			label(model, text)
			model.Parent = folder()
		end,
		setLabel = function(rig: any, text: string)
			label(rig :: Model, text)
		end,
		destroy = function(rig: any)
			(rig :: Instance):Destroy()
		end,
		delay = function(seconds: number, fn: () -> ())
			task.delay(seconds, fn)
		end,
		warn = function(message: string)
			warn(message)
		end,
	}
end

return PodiumRigs
