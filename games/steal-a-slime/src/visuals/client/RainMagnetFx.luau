--!strict
--[[
	RainMagnetFx (VisualsClient module, FEATURES.RainMagnet, CONTRACT.md §23)

	Stands the rain_magnet mesh (a clone of ReplicatedStorage.RainMagnetMeshes.rain_magnet, published by the server
	with the flag on, or in Studio) on the LOCAL player's own plot beside the merge vat while the plot attribute
	Constants.PLOT_RAIN_MAGNET_ATTRIBUTE (the owner's upgrade level, set only with the flag on) is above 0: 1 MeshPart.
	Local changes only. Studio only: the SlimeUI attribute PcwRainMagnet = true forces it on Plot_1.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local MagnetDecor = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("MagnetDecor"))

local RainMagnetFx = {}

local FOLDER_NAME = "ClientRainMagnet"

local started = false
local shownPlot: Instance? = nil

local function forced(): boolean
	if RunService:IsStudio() and Players.LocalPlayer then
		local gui = Players.LocalPlayer:FindFirstChild("PlayerGui")
		local ui = gui and gui:FindFirstChild("SlimeUI")
		return ui ~= nil and ui:GetAttribute("PcwRainMagnet") == true
	end
	return false
end

-- The plot that should wear the magnet: the local player's own with a level, or Plot_1 when forced.
local function targetPlot(): Model?
	local plots = workspace:FindFirstChild(Constants.PLOTS_FOLDER)
	if not (plots and Players.LocalPlayer) then
		return nil
	end
	if forced() then
		local first = plots:FindFirstChild("Plot_1")
		return if first and first:IsA("Model") then first else nil
	end
	for _, plot in plots:GetChildren() do
		if
			plot:IsA("Model")
			and plot:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId
			and MagnetDecor.shown(plot:GetAttribute(Constants.PLOT_RAIN_MAGNET_ATTRIBUTE))
		then
			return plot
		end
	end
	return nil
end

local function clear()
	local f = workspace:FindFirstChild(FOLDER_NAME)
	if f then
		f:Destroy()
	end
	shownPlot = nil
end

-- Shows the magnet on `plot` (nil = remove it). Idempotent.
function RainMagnetFx.apply(plot: Model?, templates: Instance?)
	if plot == shownPlot and (plot == nil or workspace:FindFirstChild(FOLDER_NAME)) then
		return
	end
	clear()
	if not plot then
		return
	end
	local vat = plot:FindFirstChild("MergeVat")
	local template = if templates then templates:FindFirstChild(MagnetDecor.MESH) else nil
	if not (vat and vat:IsA("BasePart") and template and template:IsA("BasePart")) then
		return
	end
	local pose = MagnetDecor.pose()
	local base = plot:FindFirstChild("Base")
	local turn = if base and base:IsA("BasePart") then base.CFrame.Rotation else CFrame.new()
	local at = vat.Position + turn:VectorToWorldSpace(Vector3.new(pose.offset[1], pose.offset[2], pose.offset[3]))
	local mesh = template:Clone()
	mesh.Name = MagnetDecor.MESH
	mesh.Size = Vector3.new(pose.size[1], pose.size[2], pose.size[3])
	mesh.CFrame = CFrame.new(at) * turn
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.CanTouch = false
	local f = Instance.new("Folder")
	f.Name = FOLDER_NAME
	f.Parent = workspace
	mesh.Parent = f
	shownPlot = plot
end

function RainMagnetFx.start()
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
		local templates = ReplicatedStorage:FindFirstChild("RainMagnetMeshes")
		if not templates and shownPlot == nil then
			return
		end
		local ok, err = pcall(function()
			RainMagnetFx.apply(if templates then targetPlot() else nil, templates)
		end)
		if not ok then
			warn(`[VisualsClient] RainMagnetFx: {err}`)
		end
	end)
end

return RainMagnetFx
