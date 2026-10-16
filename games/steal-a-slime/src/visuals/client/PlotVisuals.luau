--!strict
--[[
	PlotVisuals (VisualsClient module)

	  * PlotDecor.apply on every workspace.Plots.Plot_<i> at UPDATE_RATE Hz
	    against workspace:GetServerTimeNow() (lock barrier + countdown sign,
	    rebirth trim / pillars / banners, SlimeDex board),
	    plus a bobbing, spinning Crown on top-band plots.
	  * RareSpawn effects on wild slimes (State == "Wild") by the RareSpawn
	    attribute (CONTRACT §8.4, Legendary+) or else Tier, kept in a
	    local workspace folder "ClientRareFx" and posed on the slime's pivot
	    every frame; removed when the slime stops being wild or goes away.
	Reads attributes only; never fires remotes. Local changes only.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local Visuals = ReplicatedStorage:WaitForChild("Visuals")
local PlotDecor = require(Visuals:WaitForChild("PlotDecor"))
local RareSpawn = require(Visuals:WaitForChild("RareSpawn"))

local PlotVisuals = {}

PlotVisuals.UPDATE_RATE = 4 -- plot decor refreshes per second
PlotVisuals.MAX_FX_DISTANCE = 600 -- beams are visible from far away on purpose

type Crown = { part: BasePart, base: CFrame }

local crowns: { [Instance]: Crown } = {}
local fx: { [Model]: Model } = {} -- wild slime -> its RareFx model
local fxFolder: Folder? = nil

local function folder(): Folder
	if not fxFolder or not fxFolder.Parent then
		local f = Instance.new("Folder")
		f.Name = "ClientRareFx"
		f.Parent = workspace
		fxFolder = f
	end
	return fxFolder :: Folder
end

local function refreshPlots(now: number)
	local plots = workspace:FindFirstChild(Constants.PLOTS_FOLDER)
	if not plots then
		return
	end
	for _, plot in plots:GetChildren() do
		if plot:IsA("Model") then
			local ok, err = pcall(PlotDecor.apply, plot, now)
			if not ok then
				warn(`[VisualsClient] PlotDecor {plot.Name}: {err}`)
			end
			local decor = plot:FindFirstChild("RebirthDecor")
			local crown = decor and decor:FindFirstChild("Crown")
			if crown and crown:IsA("BasePart") and not crowns[plot] then
				crowns[plot] = { part = crown, base = crown.CFrame }
			end
		end
	end
end

local function stepCrowns(t: number)
	for plot, crown in crowns do
		if not plot.Parent or crown.part.Transparency >= 1 then
			continue
		end
		crown.part.CFrame = crown.base * CFrame.new(0, math.sin(t * 1.5) * 0.6, 0) * CFrame.Angles(0, t * 0.9, 0)
	end
end

local function dropFx(slime: Model)
	local model = fx[slime]
	if model then
		model:Destroy()
		fx[slime] = nil
	end
end

local function syncFx(slime: Model)
	-- RareSpawn (CONTRACT §8.4) marks Legendary+ drops; Tier covers the rest.
	local rare = slime:GetAttribute(Constants.RARE_ATTRIBUTE)
	local tier = if type(rare) == "number" then rare else slime:GetAttribute("Tier")
	local wild = slime:GetAttribute("State") == "Wild"
	local current = fx[slime]
	if not wild or type(tier) ~= "number" then
		dropFx(slime)
		return
	end
	if current and current:GetAttribute("Tier") == tier then
		return
	end
	dropFx(slime)
	local size = slime:GetAttribute("Size")
	local model = RareSpawn.build(tier, if type(size) == "number" then size else nil)
	if model then
		RareSpawn.place(model, slime:GetPivot(), os.clock())
		model.Parent = folder()
		fx[slime] = model
	end
end

local watched: { [Model]: { RBXScriptConnection } } = {}

local function onSlime(instance: Instance)
	if not instance:IsA("Model") or watched[instance] then
		return
	end
	local function sync()
		syncFx(instance)
	end
	watched[instance] = {
		instance:GetAttributeChangedSignal("State"):Connect(sync),
		instance:GetAttributeChangedSignal("Tier"):Connect(sync),
		instance:GetAttributeChangedSignal(Constants.RARE_ATTRIBUTE):Connect(sync),
	}
	sync()
end

local function onSlimeRemoved(instance: Instance)
	local model = instance :: Model
	for _, c in watched[model] or {} do
		c:Disconnect()
	end
	watched[model] = nil
	dropFx(model)
end

local function stepFx(t: number, cameraPos: Vector3)
	for slime, model in fx do
		if not slime.Parent then
			onSlimeRemoved(slime)
			continue
		end
		local pivot = slime:GetPivot()
		if (pivot.Position - cameraPos).Magnitude <= PlotVisuals.MAX_FX_DISTANCE then
			RareSpawn.place(model, pivot, t)
			if model:GetAttribute("Tier") == 6 then
				local beam = model:FindFirstChild("Beam")
				if beam and beam:IsA("BasePart") then
					beam.Color = Color3.fromHSV((t * 0.15) % 1, 0.55, 1)
				end
			end
		end
	end
end

function PlotVisuals.start()
	CollectionService:GetInstanceAddedSignal(Constants.SLIME_TAG):Connect(onSlime)
	CollectionService:GetInstanceRemovedSignal(Constants.SLIME_TAG):Connect(onSlimeRemoved)
	for _, model in CollectionService:GetTagged(Constants.SLIME_TAG) do
		onSlime(model)
	end
	local nextRefresh = 0
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		if t >= nextRefresh then
			nextRefresh = t + 1 / PlotVisuals.UPDATE_RATE
			refreshPlots(workspace:GetServerTimeNow())
		end
		stepCrowns(t)
		local camera = workspace.CurrentCamera
		if camera then
			stepFx(t, camera.CFrame.Position)
		end
	end)
end

return PlotVisuals
