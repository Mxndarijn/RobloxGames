--!strict
--[[
	VisualsClient (owner: Archer) -> StarterPlayerScripts.VisualsClient

	Client-only looks on every model tagged Constants.SLIME_TAG:
	  * idle jiggle (bob + tilt) and random blinks
	  * "Carried": struggles in bursts with rests between (CarryWriggle) and
	    nervous blinking. A rigged slime wriggles through its FaceRoot /
	    SkinRoot Motor6D Transforms (face and skin together; SlimeLifeRunner
	    lets go of a carried slime); an unrigged one through the carry joint
	    if it is a Weld / Motor6D
	  * "Escaping": the same calm idle as everywhere else; the server glides
	    it home (no bounces, contract/slime-walk.md)
	  * Slime Rain particles, goo blobs and a colour tint while workspace
	    attribute Constants.RAIN_ATTRIBUTE ("SlimeRain") is true
	  * tutorial arrow (TutorialArrow) for the Player attribute TutorialStepId
	  * night sky (NightSky): Sky + Atmosphere, night look on ClockTime
	  * follow pets (FollowPets) for the Player attribute PetSlimeId
	  * despawn warning (DespawnTelegraphFx) on wild slimes with DespawnAt
	  * fountain tiers (FountainTierFx, FEATURES.FountainTiers): goo glow from the workspace attribute FountainTier
	  * weather (WeatherFx, FEATURES.Weather): Rain / Snow / Starfall emitters + tint from the workspace attribute Weather
	  * pad habitat looks (HabitatFx, FEATURES.Habitats) from the Pad Habitat attribute
	  * ritual circle effects (RitualFx, FEATURES.CoopRitual): motes, beams, charge ring and the completion burst
	  * Mystery Egg cracks, glow and ready sparkles (EggFx) from the egg's EggHatchAt / EggHatchSeconds
	  * the Mystery Egg hatch show on the pad (EggHatchFx) from a hatched slime's HatchedAt / HatchedFrom / HatchLucky
	  * home plot marker (HomePlotMarker): beacon, floor rim, "YOUR PLOT" tag and edge arrow on the local player's own plot
	  * plot cosmetics (PlotVisuals: PlotDecor on plot attributes) and
	    rare-spawn beams / glow on wild slimes by Tier (RareSpawn)
	  * slime fountain (still Map.Volcano.Crater): goo spray ("Smoke"),
	    sparkle glints ("Embers") and "Eruption" splash puffs on the crown,
	    with a splash burst every
	    ERUPT_EVERY seconds (faster during Slime Rain)
	Reads attributes only; never fires remotes. One RenderStepped loop, slimes
	far from the camera are skipped.

	Pivot animation only touches anchored Bodies (pad, wild, escaping) that
	SlimeLifeRunner does not animate (model attribute LifeMode "motor": its
	Transform carries the life, and a second pivot writer would show the
	replication steps); a slime it takes over gets its pivot back once. Each
	frame it checks whether the server moved the model since our last write
	and, if so, rebases on the server's pivot, so it never fights replication.
	The base is drawn through a StepTrack (Lib core): a wild slime it animates
	(a Mystery Egg on the lane, a slime too far away for a rig) glides at frame
	rate instead of stepping at the replication rate.
	The walking boss (model attributes BossWalkSeed / BossWalkAt / BossWalkUntil)
	instead rebases every frame on its BossWander pose at server time: the same
	plan the server walks, drawn at frame rate instead of at replication rate.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Lighting = game:GetService("Lighting")

local BossWander = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BossWander"))
local CarryWriggle = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("CarryWriggle"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local Effects = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("Effects"))
local StepTrack = require(ReplicatedStorage:WaitForChild("Lib"):WaitForChild("core"):WaitForChild("StepTrack"))

local MAX_DISTANCE = 150
local BLINK_TIME = 0.12
local LIFE_MODE_ATTRIBUTE = "LifeMode" -- SlimeLifeRunner (ui/SlimeMotor.MODE_ATTRIBUTE): which driver animates the slime
local RAIN_ATTRIBUTE = Constants.RAIN_ATTRIBUTE
local ERUPT_EVERY = { 9, 16 } -- seconds between fountain splash bursts
local ERUPT_EVERY_RAIN = { 3, 6 }

type Track = {
	model: Model,
	body: BasePart,
	eyes: { BasePart },
	phase: number,
	seed: number, -- per slime, for CarryWriggle
	base: CFrame?, -- server pivot we animate around
	written: CFrame?, -- last pivot we wrote
	glide: StepTrack.Track?, -- the base position, smooth at frame rate
	yaw: number, -- the base heading, smooth at frame rate
	glidedAt: number,
	nextBlink: number,
	blinkUntil: number,
	joint: JointInstance?,
	jointC1: CFrame?,
	wriggling: boolean, -- the rig roots' Transforms hold a carry wriggle
}

local tracks: { [Model]: Track } = {}
local bossWalks: { [Model]: { key: string, plan: BossWander.Plan } } = {}
-- Tagged models whose Body hasn't replicated yet (the tag can arrive first): picked up when it does.
local pending: { [Model]: RBXScriptConnection } = {}

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
		if not pending[instance] then
			pending[instance] = instance.ChildAdded:Connect(function(child)
				if child.Name == "Body" then
					pending[instance]:Disconnect()
					pending[instance] = nil
					-- after the rest of the model (eyes) has landed; skip a slime
					-- removed in between, or its track would never be dropped
					task.defer(function()
						if instance.Parent and instance:HasTag(Constants.SLIME_TAG) then
							onSlime(instance)
						end
					end)
				end
			end)
		end
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
		seed = math.random(1, 1000000),
		nextBlink = os.clock() + 1 + math.random() * 4,
		blinkUntil = 0,
		yaw = 0,
		glidedAt = 0,
		wriggling = false,
	}
end

-- SlimeRig's FaceRoot / SkinRoot Motor6Ds on Body: one Transform on both moves face and skin together.
local RIG_ROOTS = { "FaceRoot", "SkinRoot" }
local function rigRoots(body: BasePart): { Motor6D }
	local out = {}
	for _, name in RIG_ROOTS do
		local m = body:FindFirstChild(name)
		if m and m:IsA("Motor6D") and m.Part0 == body then
			table.insert(out, m)
		end
	end
	return out
end

local function restoreJoint(track: Track)
	if track.joint and track.jointC1 and track.joint.Parent then
		track.joint.C1 = track.jointC1
	end
	track.joint, track.jointC1 = nil, nil
	if track.wriggling then
		track.wriggling = false
		-- SlimeLifeRunner may already own the Transforms again (it rigs a slime the frame it is put down)
		if track.model:GetAttribute(LIFE_MODE_ATTRIBUTE) ~= "motor" then
			for _, m in rigRoots(track.body) do
				m.Transform = CFrame.new()
			end
		end
	end
end

local function onSlimeRemoved(instance: Instance)
	local track = tracks[instance :: Model]
	if track then
		restoreJoint(track)
		tracks[instance :: Model] = nil
	end
	bossWalks[instance :: Model] = nil
	local waiting = pending[instance :: Model]
	if waiting then
		waiting:Disconnect()
		pending[instance :: Model] = nil
	end
end

-- The server's carry joint: a Weld / Motor6D on Body that the factory did
-- not make (the factory uses WeldConstraints, SlimeRig its FaceRoot / SkinRoot motors).
local function findCarryJoint(body: BasePart): JointInstance?
	for _, joint in body:GetJoints() do
		if
			joint:IsA("JointInstance")
			and (joint.Part0 == body or joint.Part1 == body)
			and not (joint:IsA("Motor6D") and table.find(RIG_ROOTS, joint.Name))
		then
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

-- The fountain centre the boss walk is laid out round (the server's WorldView crater()).
local function craterCentre(): Vector3
	local map = workspace:FindFirstChild(Constants.MAP_FOLDER)
	local volcano = map and map:FindFirstChild("Volcano")
	local crater = volcano and volcano:FindFirstChild("Crater")
	return if crater and crater:IsA("BasePart") then crater.Position else Vector3.new(0, 20, 0)
end

-- The walking boss's pose now (its BossWander plan at server time) at height `y`, or nil for any other slime.
local function bossWalkPose(model: Model, y: number): CFrame?
	local seed = model:GetAttribute(Constants.BOSS_WALK_SEED_ATTRIBUTE)
	local at = model:GetAttribute(Constants.BOSS_WALK_AT_ATTRIBUTE)
	if type(seed) ~= "number" or type(at) ~= "number" then
		bossWalks[model] = nil
		return nil
	end
	local key = `{seed}|{at}`
	local walk = bossWalks[model]
	if not walk or walk.key ~= key then
		local fresh: { key: string, plan: BossWander.Plan } =
			{ key = key, plan = BossWander.plan(seed, at, Config.BOSS.FIGHT_SECONDS) }
		bossWalks[model] = fresh
		walk = fresh
	end
	local now = workspace:GetServerTimeNow()
	local stopped = model:GetAttribute(Constants.BOSS_WALK_UNTIL_ATTRIBUTE)
	if type(stopped) == "number" then
		now = math.min(now, stopped)
	end
	local p, face = BossWander.pose(walk.plan, now)
	local origin = craterCentre()
	local spot = Vector3.new(origin.X + p[1], y, origin.Z + p[2])
	return CFrame.lookAt(spot, spot + Vector3.new(face[1], 0, face[2]))
end

local function headingOf(cf: CFrame): number
	local look = cf.LookVector
	return math.atan2(-look.X, -look.Z)
end

-- The server's pivot (stepwise, at the replication rate) drawn smooth: position through a StepTrack, heading
-- eased the same way; its tilt is kept.
local function glided(track: Track, base: CFrame, now: number): CFrame
	local p = base.Position
	local g = track.glide
	if not g then
		g = StepTrack.new(p.X, p.Y, p.Z, now)
		track.glide = g
		track.yaw = headingOf(base)
		track.glidedAt = now
	end
	local x, y, z = StepTrack.step(g, p.X, p.Y, p.Z, now)
	local target = headingOf(base)
	track.yaw = StepTrack.angle(track.yaw, target, now - track.glidedAt)
	track.glidedAt = now
	return CFrame.new(x, y, z) * CFrame.Angles(0, track.yaw - target, 0) * base.Rotation
end

local function animatePivot(track: Track, offset: CFrame, now: number)
	local current = track.model:GetPivot()
	if not (track.base and track.written and samePivot(current, track.written)) then
		track.base = current
	end
	-- The walking boss: its pose comes from the plan every frame, on the ground height the server last sent.
	local walk = bossWalkPose(track.model, (track.base :: CFrame).Y)
	local drawn
	if walk then
		track.base = walk
		track.glide = nil
		drawn = walk
	else
		drawn = glided(track, track.base :: CFrame, now)
	end
	local target = drawn * offset
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
		track.base, track.written, track.glide = nil, nil, nil
		local pitch, yaw, roll, lift = CarryWriggle.pose(now, track.seed)
		local roots = rigRoots(body)
		if #roots > 0 then
			local wriggle = CFrame.new(0, lift * size, 0) * CFrame.Angles(pitch, yaw, roll)
			for _, m in roots do
				m.Transform = wriggle
			end
			track.wriggling = true
			return
		end
		if not track.joint or not track.joint.Parent then
			track.joint = findCarryJoint(body)
			track.jointC1 = if track.joint then track.joint.C1 else nil
		end
		if track.joint and track.jointC1 then
			track.joint.C1 = track.jointC1 * CFrame.new(0, -lift * size, 0) * CFrame.Angles(pitch, yaw, roll)
		end
		return
	end
	restoreJoint(track)
	if not body.Anchored then
		track.base, track.written, track.glide = nil, nil, nil
		return
	end
	-- SlimeLifeRunner draws this one through its Transform: leave the pivot to the server (put our bob back once).
	-- The walking boss keeps its frame-rate walk from here.
	if
		track.model:GetAttribute(LIFE_MODE_ATTRIBUTE) == "motor"
		and track.model:GetAttribute(Constants.BOSS_WALK_SEED_ATTRIBUTE) == nil
	then
		if track.base and track.written and samePivot(track.model:GetPivot(), track.written) then
			track.model:PivotTo(track.base)
		end
		track.base, track.written, track.glide = nil, nil, nil
		return
	end

	local bob = (math.sin(t * 3) * 0.5 + 0.5) * 0.08 * size
	local tilt = math.sin(t * 2.2) * 0.04
	animatePivot(track, CFrame.new(0, bob, 0) * CFrame.Angles(tilt * 0.5, 0, tilt), now)
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
	-- Warm every kit mesh at once so nothing pops in after the first move.
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
local homePlotMarker = nil
do
	local ok, err = pcall(function()
		local module = require(script:WaitForChild("HomePlotMarker"))
		module.start()
		homePlotMarker = module
	end)
	if not ok then
		warn(`[VisualsClient] home plot marker disabled: {err}`)
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
		require(script:WaitForChild("HabitatFx")).start()
	end)
	if not ok then
		warn(`[VisualsClient] habitats disabled: {err}`)
	end
end
local ritualFx: any = nil
do
	local ok, err = pcall(function()
		ritualFx = require(script:WaitForChild("RitualFx")).start()
	end)
	if not ok then
		warn(`[VisualsClient] ritual fx disabled: {err}`)
	end
end
local eggFx: any = nil
do
	local ok, err = pcall(function()
		eggFx = require(script:WaitForChild("EggFx")).start()
	end)
	if not ok then
		warn(`[VisualsClient] egg fx disabled: {err}`)
	end
end
local eggHatchFx: any = nil
do
	local ok, err = pcall(function()
		eggHatchFx = require(script:WaitForChild("EggHatchFx")).start()
	end)
	if not ok then
		warn(`[VisualsClient] egg hatch show disabled: {err}`)
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
	if homePlotMarker then
		homePlotMarker.step(now, camera)
	end
	if eggFx then
		eggFx.tick(camera)
	end
	if eggHatchFx then
		eggHatchFx.tick(camera)
	end
	if ritualFx then
		ritualFx.tick(camera)
	end
	for model, track in tracks do
		if model.Parent then
			step(track, now, cameraPos)
		end
	end
	if rainPart then
		rainPart.CFrame = CFrame.new(cameraPos + Vector3.new(0, 45, 0))
	end
end)
