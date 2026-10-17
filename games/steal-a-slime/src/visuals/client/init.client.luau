--!strict
--[[
	VisualsClient (owner: Archer) -> StarterPlayerScripts.VisualsClient

	Client-only looks on every model tagged Constants.SLIME_TAG:
	  * idle jiggle (bob + tilt) and random blinks
	  * "Carried": fast wriggle (animates the carry joint if it is a Weld /
	    Motor6D) and nervous blinking
	  * "Escaping": big bounces on top of the server's movement
	  * Slime Rain particles, goo blobs and a colour tint while workspace
	    attribute Constants.RAIN_ATTRIBUTE ("SlimeRain") is true
	  * tutorial arrow (TutorialArrow) for the Player attribute TutorialStepId
	  * night sky (NightSky): Sky + Atmosphere, night look on ClockTime
	  * follow pets (FollowPets) for the Player attribute PetSlimeId
	  * despawn warning (DespawnTelegraphFx) on wild slimes with DespawnAt
	  * revenge (RevengeFx, FEATURES.Revenge): highlight on the plots in the local Player attribute RevengePlots
	  * fountain tiers (FountainTierFx, FEATURES.FountainTiers): ring / crest / glow from the workspace attribute FountainTier
	  * merge vat look (VatFx, FEATURES.MergeVat3): the vat mesh over the local player's own plot vat
	  * Rain Magnet prop (RainMagnetFx, FEATURES.RainMagnet): the magnet mesh on the local player's own plot while the upgrade has a level
	  * weather (WeatherFx, FEATURES.Weather): Rain / Snow / Starfall emitters + tint from the workspace attribute Weather
	  * pad habitat looks (HabitatFx, FEATURES.Habitats) from the Pad Habitat attribute
	  * plot cosmetics (PlotVisuals: PlotDecor on plot attributes) and
	    rare-spawn beams / glow on wild slimes by Tier (RareSpawn)
	  * slime fountain (still Map.Volcano.Crater): goo spray ("Smoke"),
	    sparkle glints ("Embers") and "Eruption" splash puffs on the crown,
	    with a splash burst every
	    ERUPT_EVERY seconds (faster during Slime Rain)
	Reads attributes only; never fires remotes. One RenderStepped loop, slimes
	far from the camera are skipped.

	Pivot animation only touches anchored Bodies (pad, wild, escaping). Each
	frame it checks whether the server moved the model since our last write
	and, if so, rebases on the server's pivot, so it never fights replication.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Lighting = game:GetService("Lighting")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local Effects = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("Effects"))

local MAX_DISTANCE = 150
local BLINK_TIME = 0.12
local RAIN_ATTRIBUTE = Constants.RAIN_ATTRIBUTE
local ERUPT_EVERY = { 9, 16 } -- seconds between fountain splash bursts
local ERUPT_EVERY_RAIN = { 3, 6 }

type Track = {
	model: Model,
	body: BasePart,
	eyes: { BasePart },
	phase: number,
	base: CFrame?, -- server pivot we animate around
	written: CFrame?, -- last pivot we wrote
	nextBlink: number,
	blinkUntil: number,
	joint: JointInstance?,
	jointC1: CFrame?,
}

local tracks: { [Model]: Track } = {}

local function isEye(part: BasePart): boolean
	local n = part.Name
	return string.find(n, "^EyeWhite") ~= nil
		or string.find(n, "^Pupil") ~= nil
		or string.find(n, "^Iris") ~= nil
		or string.find(n, "^Shine%d") ~= nil
end

local function onSlime(instance: Instance)
	if not instance:IsA("Model") or tracks[instance] then
		return
	end
	local body = instance:FindFirstChild("Body")
	if not (body and body:IsA("BasePart")) then
		return
	end
	local eyes = {}
	for _, child in instance:GetChildren() do
		if child:IsA("BasePart") and isEye(child) then
			table.insert(eyes, child)
		end
	end
	tracks[instance] = {
		model = instance,
		body = body,
		eyes = eyes,
		phase = math.random() * math.pi * 2,
		nextBlink = os.clock() + 1 + math.random() * 4,
		blinkUntil = 0,
	}
end

local function restoreJoint(track: Track)
	if track.joint and track.jointC1 and track.joint.Parent then
		track.joint.C1 = track.jointC1
	end
	track.joint, track.jointC1 = nil, nil
end

local function onSlimeRemoved(instance: Instance)
	local track = tracks[instance :: Model]
	if track then
		restoreJoint(track)
		tracks[instance :: Model] = nil
	end
end

-- The server's carry joint: a Weld / Motor6D on Body that the factory did
-- not make (the factory only uses WeldConstraints).
local function findCarryJoint(body: BasePart): JointInstance?
	for _, joint in body:GetJoints() do
		if joint:IsA("JointInstance") and (joint.Part0 == body or joint.Part1 == body) then
			return joint
		end
	end
	return nil
end

local function samePivot(a: CFrame, b: CFrame): boolean
	return (a.Position - b.Position).Magnitude < 1e-3 and (a.LookVector - b.LookVector).Magnitude < 1e-3
end

local function setBlink(track: Track, closed: boolean)
	local value = if closed then 1 else 0
	for _, eye in track.eyes do
		eye.LocalTransparencyModifier = value
	end
end

local function animatePivot(track: Track, offset: CFrame)
	local current = track.model:GetPivot()
	if not (track.base and track.written and samePivot(current, track.written)) then
		track.base = current
	end
	local target = (track.base :: CFrame) * offset
	track.written = target
	track.model:PivotTo(target)
end

local function step(track: Track, now: number, cameraPos: Vector3)
	local body = track.body
	if (body.Position - cameraPos).Magnitude > MAX_DISTANCE then
		return
	end
	local state = track.model:GetAttribute("State")
	local size = (track.model:GetAttribute("Size") :: number?) or 1
	local t = now + track.phase

	-- Blink: nervous (fast) while carried.
	if now >= track.nextBlink then
		track.blinkUntil = now + BLINK_TIME
		track.nextBlink = now + (if state == "Carried" then 0.4 + math.random() * 0.6 else 2 + math.random() * 4)
		setBlink(track, true)
	elseif track.blinkUntil > 0 and now >= track.blinkUntil then
		track.blinkUntil = 0
		setBlink(track, false)
	end

	if state == "Carried" then
		track.base, track.written = nil, nil
		if not track.joint or not track.joint.Parent then
			track.joint = findCarryJoint(body)
			track.jointC1 = if track.joint then track.joint.C1 else nil
		end
		if track.joint and track.jointC1 then
			local wriggle = CFrame.Angles(math.sin(t * 17) * 0.12, math.sin(t * 11) * 0.25, math.sin(t * 23) * 0.18)
			track.joint.C1 = track.jointC1 * wriggle
		end
		return
	end
	restoreJoint(track)
	if not body.Anchored then
		track.base, track.written = nil, nil
		return
	end

	if state == "Escaping" then
		local hop = math.abs(math.sin(t * 7)) * 1.6 * size
		animatePivot(track, CFrame.new(0, hop, 0) * CFrame.Angles(0, 0, math.sin(t * 7) * 0.15))
	else
		local bob = (math.sin(t * 3) * 0.5 + 0.5) * 0.08 * size
		local tilt = math.sin(t * 2.2) * 0.04
		animatePivot(track, CFrame.new(0, bob, 0) * CFrame.Angles(tilt * 0.5, 0, tilt))
	end
end

-- Slime Rain: client-only emitters that follow the camera, plus a tint.
local rainPart: Part? = nil
local rainTint: ColorCorrectionEffect? = nil
local raining = false

local function setRain(active: boolean)
	raining = active
	if active and not rainPart then
		local part = Instance.new("Part")
		part.Name = "SlimeRainEmitter"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(120, 1, 120)
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Drops"
		emitter.Rate = 60
		emitter.Lifetime = NumberRange.new(3, 4)
		emitter.Speed = NumberRange.new(25, 35)
		emitter.EmissionDirection = Enum.NormalId.Bottom
		emitter.Size = NumberSequence.new(0.8, 0.5)
		emitter.LightEmission = 0.4
		emitter.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 255, 140)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 120, 220)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 200, 255)),
		})
		emitter.Parent = part
		-- Fewer, bigger, wobbling goo blobs among the drops.
		local blobs = Instance.new("ParticleEmitter")
		blobs.Name = "Blobs"
		blobs.Rate = 8
		blobs.Lifetime = NumberRange.new(3, 4)
		blobs.Speed = NumberRange.new(18, 24)
		blobs.EmissionDirection = Enum.NormalId.Bottom
		blobs.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.6),
			NumberSequenceKeypoint.new(0.5, 2.1),
			NumberSequenceKeypoint.new(1, 1.4),
		})
		blobs.RotSpeed = NumberRange.new(-90, 90)
		blobs.LightEmission = 0.6
		blobs.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		blobs.Color = ColorSequence.new(Color3.fromRGB(140, 255, 160), Color3.fromRGB(255, 150, 230))
		blobs.Parent = part
		part.Parent = workspace
		rainPart = part
		local tint = Instance.new("ColorCorrectionEffect")
		tint.Name = "SlimeRainTint"
		tint.TintColor = Color3.fromRGB(225, 255, 235)
		tint.Saturation = 0.25
		tint.Parent = Lighting
		rainTint = tint
	elseif not active and rainPart then
		rainPart:Destroy()
		rainPart = nil
		if rainTint then
			rainTint:Destroy()
			rainTint = nil
		end
	end
end

-- Fountain: client-only goo emitters on the static map, splash bursts.
local eruption: ParticleEmitter? = nil
local craterGlow: PointLight? = nil
local nextEruption = os.clock() + 4
local glowUntil = 0

local function addEmitter(parent: Instance, preset: string, name: string?): ParticleEmitter
	local existing = parent:FindFirstChild(name or preset)
	if existing and existing:IsA("ParticleEmitter") then
		return existing
	end
	local e = Effects.emitter(preset)
	e.Name = name or preset
	e.Parent = parent
	return e
end

local function setupVolcano()
	local map = workspace:WaitForChild(Constants.MAP_FOLDER, 30)
	local volcano = map and map:WaitForChild("Volcano", 30)
	local crater = volcano and volcano:WaitForChild("Crater", 30)
	if not (crater and crater:IsA("BasePart")) then
		return
	end
	addEmitter(crater, "CraterSmoke", "Smoke")
	addEmitter(crater, "CraterEmbers", "Embers")
	eruption = addEmitter(crater, "Eruption")
	craterGlow = crater:FindFirstChildWhichIsA("PointLight")
end

local function stepVolcano(now: number)
	if not eruption then
		return
	end
	if now >= nextEruption then
		local range = if raining then ERUPT_EVERY_RAIN else ERUPT_EVERY
		nextEruption = now + range[1] + math.random() * (range[2] - range[1])
		eruption:Emit(Effects.EMITTERS.Eruption.count or 24)
		glowUntil = now + 1.2
	end
	if craterGlow then
		local base = Effects.LIGHTS.CraterGlow.brightness
		craterGlow.Brightness = if now < glowUntil then base * (1 + 2 * (glowUntil - now) / 1.2) else base
	end
end

task.spawn(setupVolcano)
do
	-- v30 C2: warm every kit mesh at once so nothing pops in after the first move.
	local ok, err = pcall(function()
		require(script:WaitForChild("Preload")).start()
	end)
	if not ok then
		warn(`[VisualsClient] mesh preload disabled: {err}`)
	end
end
do
	local ok, err = pcall(function()
		require(script:WaitForChild("TutorialArrow")).start()
	end)
	if not ok then
		warn(`[VisualsClient] tutorial arrow disabled: {err}`)
	end
end
do
	local ok, err = pcall(function()
		require(script:WaitForChild("NightSky")).start()
	end)
	if not ok then
		warn(`[VisualsClient] night sky disabled: {err}`)
	end
end
do
	local ok, err = pcall(function()
		require(script:WaitForChild("FollowPets")).start()
	end)
	if not ok then
		warn(`[VisualsClient] follow pets disabled: {err}`)
	end
end
do
	local ok, err = pcall(function()
		require(script:WaitForChild("DespawnTelegraphFx")).start()
	end)
	if not ok then
		warn(`[VisualsClient] despawn telegraph disabled: {err}`)
	end
end
do
	local ok, err = pcall(function()
		require(script:WaitForChild("RevengeFx")).start()
	end)
	if not ok then
		warn(`[VisualsClient] revenge highlight disabled: {err}`)
	end
end
do
	local ok, err = pcall(function()
		require(script:WaitForChild("PlotVisuals")).start()
	end)
	if not ok then
		warn(`[VisualsClient] plot visuals disabled: {err}`)
	end
end
do
	local ok, err = pcall(function()
		require(script:WaitForChild("WeatherFx")).start()
	end)
	if not ok then
		warn(`[VisualsClient] weather disabled: {err}`)
	end
end
do
	local ok, err = pcall(function()
		require(script:WaitForChild("FountainTierFx")).start()
	end)
	if not ok then
		warn(`[VisualsClient] fountain tiers disabled: {err}`)
	end
end
do
	local ok, err = pcall(function()
		require(script:WaitForChild("VatFx")).start()
	end)
	if not ok then
		warn(`[VisualsClient] merge vat look disabled: {err}`)
	end
end
do
	local ok, err = pcall(function()
		require(script:WaitForChild("RainMagnetFx")).start()
	end)
	if not ok then
		warn(`[VisualsClient] rain magnet prop disabled: {err}`)
	end
end
do
	local ok, err = pcall(function()
		require(script:WaitForChild("HabitatFx")).start()
	end)
	if not ok then
		warn(`[VisualsClient] habitats disabled: {err}`)
	end
end

CollectionService:GetInstanceAddedSignal(Constants.SLIME_TAG):Connect(onSlime)
CollectionService:GetInstanceRemovedSignal(Constants.SLIME_TAG):Connect(onSlimeRemoved)
for _, model in CollectionService:GetTagged(Constants.SLIME_TAG) do
	onSlime(model)
end

workspace:GetAttributeChangedSignal(RAIN_ATTRIBUTE):Connect(function()
	setRain(workspace:GetAttribute(RAIN_ATTRIBUTE) == true)
end)
setRain(workspace:GetAttribute(RAIN_ATTRIBUTE) == true)

RunService.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local cameraPos = camera.CFrame.Position
	local now = os.clock()
	stepVolcano(now)
	for model, track in tracks do
		if model.Parent then
			step(track, now, cameraPos)
		end
	end
	if rainPart then
		rainPart.CFrame = CFrame.new(cameraPos + Vector3.new(0, 45, 0))
	end
end)
