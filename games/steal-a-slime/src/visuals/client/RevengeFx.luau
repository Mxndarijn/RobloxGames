--!strict
--[[
	RevengeFx (VisualsClient module, FEATURES.Revenge)

	The server sets Player attribute RevengePlots (Constants.REVENGE_PLOTS_ATTRIBUTE,
	"3,5") on the victim only: the plots of thieves who robbed them in the last
	Config.REVENGE_SECONDS. This draws one Highlight (AlwaysOnTop, named
	RevengeHighlight) on the Base of each of those plots, for the local player only.
	Highlights are local to this client; nothing is sent to the server and a
	highlight disappears as soon as the attribute drops the plot.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local RevengePlots = require(Shared:WaitForChild("RevengePlots"))

local RevengeFx = {}

RevengeFx.HIGHLIGHT_NAME = "RevengeHighlight"
RevengeFx.COLOR = Color3.fromRGB(255, 70, 60)

local function plotBase(index: number): Instance?
	local plots = workspace:FindFirstChild(Constants.PLOTS_FOLDER)
	local plot = plots and plots:FindFirstChild(`Plot_{index}`)
	return plot and (plot:FindFirstChild("Base") or plot)
end

function RevengeFx.start()
	if not Config.FEATURES.Revenge then
		return
	end
	local player = Players.LocalPlayer
	local folder = Instance.new("Folder")
	folder.Name = "RevengeFx"
	folder.Parent = workspace
	local active: { [number]: Highlight } = {}

	local function refresh()
		local wanted: { [number]: boolean } = {}
		for _, index in RevengePlots.parse(player:GetAttribute(Constants.REVENGE_PLOTS_ATTRIBUTE)) do
			wanted[index] = true
			local current = active[index]
			if not current or not current.Adornee or not current.Adornee:IsDescendantOf(workspace) then
				if current then
					current:Destroy()
				end
				local adornee = plotBase(index)
				if adornee then
					local highlight = Instance.new("Highlight")
					highlight.Name = RevengeFx.HIGHLIGHT_NAME
					highlight.Adornee = adornee
					highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
					highlight.FillColor = RevengeFx.COLOR
					highlight.FillTransparency = 0.6
					highlight.OutlineColor = RevengeFx.COLOR
					highlight.OutlineTransparency = 0
					highlight:SetAttribute("PlotIndex", index)
					highlight.Parent = folder
					active[index] = highlight
				else
					active[index] = nil
				end
			end
		end
		for index, highlight in active do
			if not wanted[index] then
				highlight:Destroy()
				active[index] = nil
			end
		end
	end

	player:GetAttributeChangedSignal(Constants.REVENGE_PLOTS_ATTRIBUTE):Connect(refresh)
	task.spawn(function()
		-- Plots stream in / get rebuilt; re-adorn if a highlighted Base was replaced.
		while true do
			task.wait(1)
			refresh()
		end
	end)
	refresh()
end

return RevengeFx
