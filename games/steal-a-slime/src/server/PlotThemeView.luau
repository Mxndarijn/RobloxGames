--!strict
--[[
	PlotThemeView (Roblox adapter)

	Keeps each plot's goo jar tower in its PlotSkin theme (FEATURES.PlotSkins, CONTRACT.md §15): when a plot's
	PlotSkin attribute changes (claim, equip, leave) it runs MeshSwap.themePlot for that plot, once the world's meshes
	are in (WorldMeshesReady). One swap per plot at a time; a change during a swap runs it again after. Holds no rules:
	WorldView sets the attribute from PlotSkins.current.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)
local MeshSwap = require(script.Parent.MeshSwap)

local PlotThemeView = {}

-- Starts watching every plot under workspace.Plots. Returns a cleanup that disconnects everything.
function PlotThemeView.start(): () -> ()
	local connections: { RBXScriptConnection } = {}
	local plots = workspace:FindFirstChild("Plots")
	if not (Config.FEATURES.PlotSkins and plots) then
		return function() end
	end
	local running: { [Instance]: boolean } = {}
	local again: { [Instance]: boolean } = {}

	local function ready(): boolean
		return workspace:GetAttribute(Constants.WORLD_MESHES_READY_ATTRIBUTE) == true
	end

	local function run(plot: Instance)
		if not ready() then
			return -- the ready signal below themes every plot
		end
		if running[plot] then
			again[plot] = true
			return
		end
		running[plot] = true
		task.spawn(function()
			repeat
				again[plot] = nil
				local ok, err = pcall(MeshSwap.themePlot, plot)
				if not ok then
					warn(`[PlotThemeView] {plot.Name}: {err}`)
				end
			until not again[plot]
			running[plot] = nil
		end)
	end

	for _, plot in (plots :: Instance):GetChildren() do
		table.insert(
			connections,
			plot:GetAttributeChangedSignal(Constants.PLOT_SKIN_ATTRIBUTE):Connect(function()
				run(plot)
			end)
		)
	end
	local function runAll()
		for _, plot in (plots :: Instance):GetChildren() do
			run(plot)
		end
	end
	if ready() then
		runAll()
	else
		table.insert(
			connections,
			workspace:GetAttributeChangedSignal(Constants.WORLD_MESHES_READY_ATTRIBUTE):Connect(function()
				if ready() then
					runAll()
				end
			end)
		)
	end
	return function()
		for _, c in connections do
			c:Disconnect()
		end
	end
end

return PlotThemeView
