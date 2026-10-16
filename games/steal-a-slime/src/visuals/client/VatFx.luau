--!strict
--[[
	VatFx (VisualsClient module, FEATURES.MergeVat3, CONTRACT.md §21)

	Stands the merge_vat mesh (a clone of ReplicatedStorage.MergeVatMeshes.merge_vat, which the server only
	publishes with the flag on, or in Studio) over the LOCAL player's own plot MergeVat disc, 1 MeshPart; the
	disc and its goo are only made invisible (the MergePrompt on the disc keeps working). Other plots keep
	their disc. Local changes only. Studio only: the SlimeUI attribute PcwMergeVat = true forces it on Plot_1.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local VatDecor = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("VatDecor"))

local VatFx = {}

local FOLDER_NAME = "ClientMergeVat"
local ORIG = "VatFxOrigTransparency"

local started = false
local shownPlot: Instance? = nil

local function forced(): boolean
	if RunService:IsStudio() and Players.LocalPlayer then
		local gui = Players.LocalPlayer:FindFirstChild("PlayerGui")
		local ui = gui and gui:FindFirstChild("SlimeUI")
		return ui ~= nil and ui:GetAttribute("PcwMergeVat") == true
	end
	return false
end

local function ownPlot(): Model?
	local plots = workspace:FindFirstChild(Constants.PLOTS_FOLDER)
	if not (plots and Players.LocalPlayer) then
		return nil
	end
	if forced() then
		local first = plots:FindFirstChild("Plot_1")
		return if first and first:IsA("Model") then first else nil
	end
	for _, plot in plots:GetChildren() do
		if plot:IsA("Model") and plot:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId then
			return plot
		end
	end
	return nil
end

local function setDiscHidden(vat: BasePart, hidden: boolean)
	for _, part: Instance? in { vat :: Instance?, vat:FindFirstChild("Goo") } do
		if part and part:IsA("BasePart") then
			if hidden then
				if part:GetAttribute(ORIG) == nil then
					part:SetAttribute(ORIG, part.Transparency)
				end
				part.Transparency = 1
			else
				local was = part:GetAttribute(ORIG)
				if type(was) == "number" then
					part.Transparency = was
					part:SetAttribute(ORIG, nil)
				end
			end
		end
	end
end

local function clear()
	local f = workspace:FindFirstChild(FOLDER_NAME)
	if f then
		f:Destroy()
	end
	local plot = shownPlot
	if plot then
		local vat = plot:FindFirstChild("MergeVat")
		if vat and vat:IsA("BasePart") then
			setDiscHidden(vat, false)
		end
	end
	shownPlot = nil
end

-- Shows the vat over `plot`'s disc (nil = remove it). Idempotent.
function VatFx.apply(plot: Model?, templates: Instance?)
	if plot == shownPlot and (plot == nil or workspace:FindFirstChild(FOLDER_NAME)) then
		return
	end
	clear()
	if not plot then
		return
	end
	local vat = plot:FindFirstChild("MergeVat")
	local template = if templates then templates:FindFirstChild(VatDecor.MESH) else nil
	if not (vat and vat:IsA("BasePart") and template and template:IsA("BasePart")) then
		return
	end
	local pose = VatDecor.pose(vat.Position.X, vat.Position.Y, vat.Position.Z)
	local mesh = template:Clone()
	mesh.Name = VatDecor.MESH
	mesh.Size = Vector3.new(pose.size[1], pose.size[2], pose.size[3])
	local base = plot:FindFirstChild("Base")
	local turn = if base and base:IsA("BasePart") then base.CFrame.Rotation else CFrame.new()
	mesh.CFrame = CFrame.new(pose.position[1], pose.position[2], pose.position[3]) * turn
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.CanTouch = false
	local f = Instance.new("Folder")
	f.Name = FOLDER_NAME
	f.Parent = workspace
	mesh.Parent = f
	setDiscHidden(vat, true)
	shownPlot = plot
end

function VatFx.start()
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
		local templates = ReplicatedStorage:FindFirstChild("MergeVatMeshes")
		if not templates and shownPlot == nil then
			return
		end
		local ok, err = pcall(function()
			VatFx.apply(if templates and (Config.FEATURES.MergeVat3 or forced()) then ownPlot() else nil, templates)
		end)
		if not ok then
			warn(`[VisualsClient] VatFx: {err}`)
		end
	end)
end

return VatFx
