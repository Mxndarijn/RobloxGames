--!strict
--[[
	PodiumRigs: the Roblox adapter for PodiumAvatars. Builds R15 rigs from
	HumanoidDescriptions and stands them on workspace Podium_<rank> parts
	(the plaza mesh slots), root-anchored, non-colliding, facing the fountain like
	the podium, with a Goo name board (name on a gold band, the stat under it).
	Rigs live in workspace.PodiumAvatars.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GooBoard = require(ReplicatedStorage.Shared.GooBoard)
local GooPalette = require(ReplicatedStorage.Shared.GooPalette)
local LabelFit = require(ReplicatedStorage.Lib.ui.LabelFit)
local PodiumAvatars = require(script.Parent.PodiumAvatars)
local WorldLayout = require(ReplicatedStorage.Visuals.WorldLayout)

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

-- The name board over a podium rig (canvas GooWorldSigns): glass with a gold band holding the name in Ink, the
-- total earned in outlined gold under it. Pixel-sized, so it is the same small size on screen however near or far
-- you stand, and hidden past `maxDistance`: it is only for players close to the podium.
PodiumRigs.BOARD_PX = table.freeze({ w = 120, h = 61, lift = 2.2, maxDistance = 50 })
PodiumRigs.BOARD = table.freeze({
	band = 0.44,
	radius = 0.22,
	drips = table.freeze({
		table.freeze({ x = 0.08, w = 0.05, len = 0.06 }),
		table.freeze({ x = 0.9, w = 0.044, len = 0.03 }),
	}),
	stroke = 1.5,
	glassTransparency = 0.06,
} :: GooBoard.Spec)

local DEPS: GooBoard.Deps = { Instance = Instance, Enum = Enum, UDim = UDim, UDim2 = UDim2, Color3 = Color3 }

-- An empty text (empty podium) means no label at all: none is created, an existing one is removed.
local function label(rig: Model, text: string)
	local gui = rig:FindFirstChild("NameLabel") :: BillboardGui?
	if text == "" then
		if gui then
			gui:Destroy()
		end
		return
	end
	local px = PodiumRigs.BOARD_PX
	if not gui then
		local made = Instance.new("BillboardGui")
		made.Name = "NameLabel"
		made.Size = UDim2.fromOffset(px.w, px.h)
		made.SizeOffset = Vector2.new(0, 0.5) -- the board's bottom edge sits over the head
		made.StudsOffsetWorldSpace = Vector3.new(0, px.lift, 0)
		made.MaxDistance = px.maxDistance
		made.LightInfluence = 0
		LabelFit.mark(made) -- each client shrinks it on a phone
		local adornee = rig:FindFirstChild("Head") or rig.PrimaryPart
		if adornee then
			made.Adornee = adornee
		end
		local card = GooBoard.build(made, DEPS, PodiumRigs.BOARD, px.w / px.h)
		GooBoard.paint(card, DEPS, GooPalette.Gold)
		local name = GooBoard.text(card, DEPS, "Name", GooPalette.Ink)
		name.Position = UDim2.fromScale(0.06, 0.07)
		name.Size = UDim2.fromScale(0.88, 0.31)
		local value = GooBoard.text(card, DEPS, "Value", GooPalette.Gold, 1.2)
		value.Position = UDim2.fromScale(0.1, 0.57)
		value.Size = UDim2.fromScale(0.8, 0.33)
		made.Parent = rig
		gui = made
	end
	local card = (gui :: BillboardGui):FindFirstChild(GooBoard.CARD)
	if card then
		local name, value = PodiumAvatars.splitLabel(text)
		local nameLabel = card:FindFirstChild("Name") :: TextLabel
		local valueLabel = card:FindFirstChild("Value") :: TextLabel
		nameLabel.Text = name
		valueLabel.Text = value
	end
end

-- Statue: only the root is anchored, so the Humanoid still builds the scaled R15 joints and layered clothing; no
-- collisions/queries/touches, no default nameplate or scripts.
local function freeze(rig: Model)
	for _, inst in rig:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.Anchored = inst.Name == "HumanoidRootPart"
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

-- The lowest foot bottom of an R15 rig in world Y, or nil when it has no feet.
local function feetBottom(rig: Model): number?
	local low: number? = nil
	for _, name in { "LeftFoot", "RightFoot" } do
		local foot = rig:FindFirstChild(name)
		if foot and foot:IsA("BasePart") then
			local y = foot.Position.Y - foot.Size.Y / 2
			low = if low then math.min(low, y) else y
		end
	end
	return low
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
			-- In the workspace before anchoring/placing, so the rig is scaled and its clothing wrapped first.
			model.Parent = folder()
			freeze(model)
			-- Stand on the middle of the podium's flat top (off the slot's centre: WorldLayout.podiumTopCentre), turned
			-- like its front. The kit front is the slot's +Z (MeshAssets, kit fronts face +Z) and a character looks
			-- along its own -Z, so the rig gets half a turn.
			local dx, dz = WorldLayout.podiumTopCentre(rank, base.Size.X, base.Size.Z)
			local top = base.CFrame * CFrame.new(dx, base.Size.Y / 2, dz) * CFrame.Angles(0, math.pi, 0)
			model:PivotTo(top)
			local box, size = model:GetBoundingBox()
			local lift = PodiumAvatars.standLift(top.Position.Y, feetBottom(model), box.Position.Y - size.Y / 2)
			model:PivotTo(top + Vector3.new(0, lift, 0))
			label(model, text)
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
