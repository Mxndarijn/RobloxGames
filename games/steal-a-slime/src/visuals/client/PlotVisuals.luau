--!strict
--[[
	PlotVisuals (VisualsClient module)

	  * PlotDecor.apply on every workspace.Plots.Plot_<i> at UPDATE_RATE Hz
	    against workspace:GetServerTimeNow() (lock barrier + countdown sign,
	    rebirth trim / pillars / banners, SlimeDex board),
	    plus a bobbing, spinning Crown on top-band plots, and the jar tower's
	    mascot and goo ooze (PlotMascot).
	  * RareSpawn effects on wild slimes (State == "Wild") by the RareSpawn
	    attribute (CONTRACT §8.4, Legendary+) or else Tier, kept in a
	    local workspace folder "ClientRareFx" and posed on the slime's pivot
	    every frame; removed when the slime stops being wild or goes away.
	  * Mythic / Secret looks (contract/slime-odds.md, TopTierFx): a pedestal light under pad slimes of Tier >= 6
	    (Secret: plus a sparkle column) on an invisible disc, one beam on the fountain crown while a Secret is
	    wild, and the Secret "fountain eruption" (camera shake + sky tint for TopTierFx.ERUPTION_SECONDS, bound
	    to render step only while it plays) when the workspace RareSpawnAt / RareSpawnTier name a fresh Secret
	    drop.
	  * Plot skins (FEATURES.PlotSkins, CONTRACT.md §15): PlotDecor.applySkin from the plot's
	    PlotSkin attribute (absent = flag off = untouched). Studio only: the SlimeUI attribute
	    PcwPlotSkin (a skin id) forces Plot_1's skin, for the shots.
	Reads attributes only; never fires remotes. Local changes only.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local Visuals = ReplicatedStorage:WaitForChild("Visuals")
local Effects = require(Visuals:WaitForChild("Effects"))
local PlotDecor = require(Visuals:WaitForChild("PlotDecor"))
local PlotMascot = require(Visuals:WaitForChild("PlotMascot"))
local RareSpawn = require(Visuals:WaitForChild("RareSpawn"))
local TopTierFx = require(Visuals:WaitForChild("TopTierFx"))

local PlotVisuals = {}

PlotVisuals.UPDATE_RATE = 4 -- plot decor refreshes per second
PlotVisuals.MAX_FX_DISTANCE = 150 -- beyond this the fx is unparented, never left behind at a stale spot

type Crown = { part: BasePart, base: CFrame }

local crowns: { [Instance]: Crown } = {}
local fx: { [Model]: Model } = {} -- wild slime -> its RareFx model
local pedestals: { [Model]: BasePart } = {} -- Mythic / Secret pad slime -> its pedestal disc
local fxFolder: Folder? = nil
local topFxFolder: Folder? = nil -- pedestals and the fountain beam (not swept with the RareFx orphans)
local fountainBeam: BasePart? = nil
local lastEruptionAt: number? = nil
local ERUPTION_BIND = "SecretBurst"

local function folder(): Folder
	if not fxFolder or not fxFolder.Parent then
		local f = Instance.new("Folder")
		f.Name = "ClientRareFx"
		f.Parent = workspace
		fxFolder = f
	end
	return fxFolder :: Folder
end

local function topFolder(): Folder
	if not topFxFolder or not topFxFolder.Parent then
		local f = Instance.new("Folder")
		f.Name = "ClientTopTierFx"
		f.Parent = workspace
		topFxFolder = f
	end
	return topFxFolder :: Folder
end

-- The skin a plot shows: the Studio-only PcwPlotSkin override on Plot_1, else its PlotSkin attribute.
local function skinOf(plot: Model): string?
	if RunService:IsStudio() and plot:GetAttribute(Constants.PLOT_INDEX_ATTRIBUTE) == 1 then
		local gui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
		local ui = gui and gui:FindFirstChild("SlimeUI")
		local forced = ui and ui:GetAttribute("PcwPlotSkin")
		if type(forced) == "string" and forced ~= "" then
			return forced
		end
	end
	local id = plot:GetAttribute(Constants.PLOT_SKIN_ATTRIBUTE)
	return if type(id) == "string" then id else nil
end

local function refreshSkin(plot: Model)
	local id = skinOf(plot)
	if id == nil then
		return
	end
	local index = plot:GetAttribute(Constants.PLOT_INDEX_ATTRIBUTE)
	local map = workspace:FindFirstChild("Map")
	local decor = map and map:FindFirstChild("Decor")
	local slot = decor and decor:FindFirstChild(`Mailbox_{index}`)
	PlotDecor.applySkin(plot, id, slot, ReplicatedStorage:FindFirstChild("PlotSkinMeshes"))
end

local function refreshPlots(now: number)
	local plots = workspace:FindFirstChild(Constants.PLOTS_FOLDER)
	if not plots then
		return
	end
	for _, plot in plots:GetChildren() do
		if plot:IsA("Model") then
			local viewer = Players.LocalPlayer
			local ok, err = pcall(PlotDecor.apply, plot, now, if viewer then viewer.UserId else nil)
			if not ok then
				warn(`[VisualsClient] PlotDecor {plot.Name}: {err}`)
			end
			local mascotOk, mascotErr = pcall(PlotMascot.apply, plot)
			if not mascotOk then
				warn(`[VisualsClient] PlotMascot {plot.Name}: {mascotErr}`)
			end
			local skinOk, skinErr = pcall(refreshSkin, plot)
			if not skinOk then
				warn(`[VisualsClient] PlotSkin {plot.Name}: {skinErr}`)
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

local function dropPedestal(slime: Model)
	local disc = pedestals[slime]
	if disc then
		disc:Destroy()
		pedestals[slime] = nil
	end
end

local function fxPart(name: string, size: Vector3, color: Color3, transparency: number): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Transparency = transparency
	p.Anchored = true
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local function buildPedestal(tier: number, size: number): BasePart?
	local spec = TopTierFx.pedestal(tier)
	if not spec then
		return nil
	end
	local color = RareSpawn.color(tier)
	local d = spec.diameter * size
	local disc = fxPart(`Pedestal_{tier}`, Vector3.new(0.15, d, d), color, TopTierFx.PEDESTAL_TRANSPARENCY)
	disc:SetAttribute("Tier", tier)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = spec.brightness
	light.Range = spec.range
	light.Shadows = false
	light.Parent = disc
	if spec.column then
		local e = Effects.emitter("RareSparkle")
		e.Rate = spec.column
		e.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
		e.EmissionDirection = Enum.NormalId.Right -- the rolled disc's +X points up
		e.Parent = disc
	end
	return disc
end

local function placePedestal(disc: BasePart, pivot: CFrame)
	disc.CFrame = CFrame.new(pivot.Position + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))
end

local function syncPedestal(slime: Model)
	local tier = slime:GetAttribute("Tier")
	if slime:GetAttribute("State") ~= "Pad" or type(tier) ~= "number" or TopTierFx.pedestal(tier) == nil then
		dropPedestal(slime)
		return
	end
	local current = pedestals[slime]
	if current and current:GetAttribute("Tier") == tier then
		return
	end
	dropPedestal(slime)
	local size = slime:GetAttribute("Size")
	local disc = buildPedestal(tier, if type(size) == "number" then size else 1)
	if disc then
		placePedestal(disc, slime:GetPivot())
		disc.Parent = topFolder()
		pedestals[slime] = disc
	end
end

local function syncFx(slime: Model)
	syncPedestal(slime)
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
	dropPedestal(model)
end

local function crater(): BasePart?
	local map = workspace:FindFirstChild(Constants.MAP_FOLDER)
	local volcano = map and map:FindFirstChild("Volcano")
	local part = volcano and volcano:FindFirstChild("Crater")
	return if part and part:IsA("BasePart") then part else nil
end

-- One beam on the fountain crown while a Secret is wild near the camera (built once, parked otherwise).
local function stepFountainBeam(show: boolean, t: number)
	local crown = if show then crater() else nil
	if not crown then
		if fountainBeam then
			fountainBeam.Parent = nil
		end
		return
	end
	local spec = TopTierFx.FOUNTAIN_BEAM
	local beam: BasePart = fountainBeam
		or fxPart(
			"SecretFountainBeam",
			Vector3.new(spec.height, spec.width, spec.width),
			RareSpawn.color(TopTierFx.SECRET_TIER),
			spec.transparency
		)
	fountainBeam = beam
	local top = crown.Position + Vector3.new(0, crown.Size.Y / 2 + spec.height / 2, 0)
	beam.CFrame = CFrame.new(top) * CFrame.Angles(0, 0, math.rad(90))
	beam.Transparency = spec.transparency + 0.1 * math.sin(t * 3)
	if not beam.Parent then
		beam.Parent = topFolder()
	end
end

local function tintEffect(): ColorCorrectionEffect
	local existing = Lighting:FindFirstChild(TopTierFx.TINT_NAME)
	if existing and existing:IsA("ColorCorrectionEffect") then
		return existing
	end
	local c = Instance.new("ColorCorrectionEffect")
	c.Name = TopTierFx.TINT_NAME
	c.Parent = Lighting
	return c
end

-- The Secret "fountain eruption": a splash burst on the crown, then ERUPTION_SECONDS of camera shake and sky tint.
-- Bound to render step (after the camera) only while it plays.
local function erupt()
	local crown = crater()
	local splash = crown and crown:FindFirstChild("Eruption")
	if splash and splash:IsA("ParticleEmitter") then
		splash:Emit(Effects.EMITTERS.Eruption.count or 24)
	end
	local tint = tintEffect()
	local c = TopTierFx.TINT
	local tintColor = Color3.fromRGB(c[1], c[2], c[3])
	local started = os.clock()
	RunService:UnbindFromRenderStep(ERUPTION_BIND)
	RunService:BindToRenderStep(ERUPTION_BIND, Enum.RenderPriority.Camera.Value + 1, function()
		local t = os.clock() - started
		local shake, k = TopTierFx.eruption(t)
		tint.TintColor = Color3.new(1, 1, 1):Lerp(tintColor, 0.35 * k)
		tint.Saturation = TopTierFx.TINT_SATURATION * k
		local camera = workspace.CurrentCamera
		if camera and shake > 0 then
			camera.CFrame = camera.CFrame * CFrame.new(math.sin(t * 47) * shake, math.sin(t * 61 + 1) * shake, 0)
		end
		if t >= TopTierFx.ERUPTION_SECONDS then
			tint.TintColor = Color3.new(1, 1, 1)
			tint.Saturation = 0
			RunService:UnbindFromRenderStep(ERUPTION_BIND)
		end
	end)
end

local function onRareSpawn()
	local tier = workspace:GetAttribute(Constants.RARE_SPAWN_TIER_ATTRIBUTE)
	local at = workspace:GetAttribute(Constants.RARE_SPAWN_AT_ATTRIBUTE)
	if at ~= lastEruptionAt and TopTierFx.erupts(tier, at, workspace:GetServerTimeNow()) then
		lastEruptionAt = at
		erupt()
	end
end

local function stepPedestals(cameraPos: Vector3)
	for slime, disc in pedestals do
		if not slime.Parent then
			onSlimeRemoved(slime)
			continue
		end
		local pivot = slime:GetPivot()
		if (pivot.Position - cameraPos).Magnitude <= PlotVisuals.MAX_FX_DISTANCE then
			placePedestal(disc, pivot)
			if not disc.Parent then
				disc.Parent = topFolder()
			end
		elseif disc.Parent then
			disc.Parent = nil
		end
	end
end

local function stepFx(t: number, cameraPos: Vector3)
	stepPedestals(cameraPos)
	local secretWild = false
	for slime, model in fx do
		if not slime.Parent then
			onSlimeRemoved(slime)
			continue
		end
		if slime:GetAttribute("State") ~= "Wild" then
			dropFx(slime)
			continue
		end
		local pivot = slime:GetPivot()
		if (pivot.Position - cameraPos).Magnitude <= PlotVisuals.MAX_FX_DISTANCE then
			if not model.Parent then
				model.Parent = folder()
			end
			RareSpawn.place(model, pivot, t)
			if model:GetAttribute("Tier") == TopTierFx.SECRET_TIER then
				secretWild = true
			end
		elseif model.Parent then
			model.Parent = nil
		end
	end
	stepFountainBeam(secretWild, t)
end

-- Defensive sweep: destroy any ClientRareFx child that no tracked slime owns.
local function sweepOrphans()
	local f = fxFolder
	if not f or not f.Parent then
		return
	end
	for _, orphan in RareSpawn.orphans(f:GetChildren(), fx) do
		orphan:Destroy()
	end
end

function PlotVisuals.start()
	CollectionService:GetInstanceAddedSignal(Constants.SLIME_TAG):Connect(onSlime)
	CollectionService:GetInstanceRemovedSignal(Constants.SLIME_TAG):Connect(onSlimeRemoved)
	for _, model in CollectionService:GetTagged(Constants.SLIME_TAG) do
		onSlime(model)
	end
	workspace:GetAttributeChangedSignal(Constants.RARE_SPAWN_AT_ATTRIBUTE):Connect(onRareSpawn)
	local nextRefresh = 0
	local nextSweep = 0
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		if t >= nextRefresh then
			nextRefresh = t + 1 / PlotVisuals.UPDATE_RATE
			refreshPlots(workspace:GetServerTimeNow())
		end
		if t >= nextSweep then
			nextSweep = t + 1
			sweepOrphans()
		end
		stepCrowns(t)
		local camera = workspace.CurrentCamera
		if camera then
			stepFx(t, camera.CFrame.Position)
		end
	end)
end

return PlotVisuals
