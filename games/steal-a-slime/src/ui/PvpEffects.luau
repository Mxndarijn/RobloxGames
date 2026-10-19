--!strict
--[[
	PvpEffects (client, FEATURES.PvP, CONTRACT.md §26.1 "Client effects")

	The look and sound of PvP, driven by PvpEvent `Effect` / `TrapPlaced` / `TrapCleared`. Built ONLY from Roblox
	built-in instances (ParticleEmitter, Highlight, Beam, Trail, Attachment, Sound, BillboardGui; textures are rbxasset://
	built-ins), all transient: each is destroyed within its plan's `seconds` (PvpEffectsLogic.plan) and counted, so
	`activeCount()` is 0 once the effects ended. Zero BaseParts when idle: emitters sit on the characters' existing parts
	or on an Attachment under Workspace.Terrain. The Parts are the client-only marker of a placed Goo Trap (seen by
	everyone: glowing for its owner, a faint shimmer for others; the PvpModels placeholder or its uploaded mesh) / Bounce
	Pad, destroyed on TrapCleared, and the flat goo splat a Goo Blaster blob leaves, gone after its seconds. A goo blob is
	one particle flying the server's arc (PvpEffectsLogic.blobVelocity); its impact waits for the flight. Glove specials:
	a BONK! / CHOMP! popup, lightning to a chained player, the Bounce Glove pogo (the victim's own client bounces), gold
	confetti. The victim's client also applies the payload `velocity` to its own root (it owns the character; the
	server's own set is weak for a real player), shakes its camera for <= 0.3 s and, hit by a blob, gets goo on the
	edge of its screen.

	Animations ride the same events (CONTRACT.md §26.3): the attacker of a use plays its item's animation (not the
	local player, whose own client already played it on the click; not the Bat, whose swing comes from BatSwingAt),
	the owner of a placed trap / pad plays the throw and a pushed target plays the `hit` recoil (ui/PvpAnim).

	PvpEffects.start(remote, anim?) connects PvpEvent (`anim` = the ui/PvpAnim handle); PvpEffects.play(payload)
	is the same entry for a probe; PvpEffects.activeCount() / markerCount(); PvpEffects.stop().
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MeshAssets = require(Shared:WaitForChild("MeshAssets"))
local PvpKnockbackRules = require(Shared:WaitForChild("PvpKnockbackRules"))
local PvpModels = require(Shared:WaitForChild("PvpModels"))

local Logic = require(script.Parent.PvpEffectsLogic)
local SlimeLod = require(script.Parent.SlimeLod)
local SoundController = require(script.Parent.SoundController)
local Sounds = require(script.Parent.Sounds)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme

local PvpEffects = {}

-- Sizes of the client-built PvP bits (studs unless px). Colours come from the plan (PvpEffectsLogic) or Widgets.Theme.
local LOOK = table.freeze({
	popupPx = Vector2.new(140, 48), -- the BONK! / CHOMP! label
	popupText = 34,
	popupY = 3, -- studs above the head
	popupRise = 2, -- studs it floats up while fading
	boltWidth = 0.5,
	boltCurve = 3, -- studs of random bend at each end of the lightning
	splatHeight = 0.12,
	splatProbe = 30, -- studs a splat looks down for the ground
	screenSplat = table.freeze({ -- goo blobs on the edge of a hit player's screen: scale position and size
		{ 0.02, 0.1, 0.18 },
		{ 0.88, 0.05, 0.14 },
		{ 0.0, 0.72, 0.2 },
		{ 0.85, 0.7, 0.2 },
		{ 0.4, 0.88, 0.16 },
		{ 0.45, -0.04, 0.12 },
	}),
	markerScale = 1.6, -- a placed trap's placeholder model / mesh is this much bigger than in the hand
})
local AXIS_TURN: { [string]: CFrame } = {
	X = CFrame.new(),
	Y = CFrame.Angles(0, 0, math.rad(90)),
	Z = CFrame.Angles(0, math.rad(90), 0),
}

local tracker = Logic.tracker()
local connection: RBXScriptConnection? = nil
local markers: { [string]: Instance } = {}
local highlights: { [Instance]: { highlight: Highlight, untilAt: number } } = {}
local highlightCount = 0
local shakes: { { startedAt: number, seconds: number, amplitude: number } } = {}
local SHAKE_BIND = "PvpEffectsShake"
local anim: any = nil -- the ui/PvpAnim handle given to start (nil = no animations)

local function lowQuality(): boolean
	local ok, settings = pcall(function()
		return UserSettings():GetService("UserGameSettings")
	end)
	return ok and SlimeLod.isLow(Config.SLIME_LOD, SlimeLod.readQuality(settings)) or false
end

local function color3(c: Logic.RGB): Color3
	return Color3.new(c[1], c[2], c[3])
end

local function colorSequence(colors: { Logic.RGB }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(color3(colors[1]))
	end
	local points = {}
	for i, c in colors do
		table.insert(points, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), color3(c)))
	end
	return ColorSequence.new(points)
end

-- Counts `instance` as live under `kind` until it is destroyed or `seconds` pass; returns the early release.
local function track(instance: Instance, kind: string, seconds: number): () -> ()
	tracker.acquire(kind)
	local released = false
	local function release()
		if released then
			return
		end
		released = true
		tracker.release(kind)
		if instance.Parent then
			instance:Destroy()
		end
	end
	instance.Destroying:Connect(function()
		if not released then
			released = true
			tracker.release(kind)
		end
	end)
	task.delay(seconds, release)
	return release
end

local function characterOf(userId: any): Model?
	local p = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	return p and p.Character
end

local function rootOf(character: Model?): BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function handOf(character: Model?): BasePart?
	if not character then
		return nil
	end
	for _, name in { "RightHand", "Right Arm", "HumanoidRootPart" } do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

-- A transient Attachment at a world point (under Terrain: no BasePart is created).
local function anchorAt(position: Vector3, seconds: number): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Parent = workspace.Terrain
	attachment.WorldPosition = position
	track(attachment, "attachment", seconds)
	return attachment
end

local function playSfx(name: string?, parent: Instance?, involved: boolean)
	if not name then
		return
	end
	if involved and SoundController.play(name) then
		return
	end
	local id = Sounds.resolve(name)
	if not id or not parent then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = 0.8
	sound.RollOffMaxDistance = 90
	local group = SoundService:FindFirstChild("SFX")
	if group and group:IsA("SoundGroup") then
		sound.SoundGroup = group
	end
	sound.Parent = parent
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	track(sound, "sound", 4)
	sound:Play()
end

local function emitBurst(parent: Instance, burst: Logic.Burst, seconds: number)
	if burst.height and parent:IsA("BasePart") then
		local offset = Instance.new("Attachment")
		offset.Position = Vector3.new(0, burst.height, 0)
		offset.Parent = parent
		track(offset, "attachment", seconds)
		parent = offset
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Texture = burst.texture or ""
	emitter.Color = colorSequence(burst.colors)
	emitter.LightEmission = 0.4
	emitter.Lifetime = NumberRange.new(0.4, 0.9)
	emitter.Speed = NumberRange.new(burst.speed * 0.5, burst.speed)
	emitter.SpreadAngle = if burst.ring then Vector2.new(85, 85) else Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, burst.lift, 0)
	emitter.Size = NumberSequence.new(burst.size)
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	emitter.Parent = parent
	track(emitter, "emitter", seconds)
	emitter:Emit(burst.count)
end

local function flash(character: Model, color: Color3, seconds: number, impact: Color3?)
	local now = os.clock()
	local entry = highlights[character]
	if entry then
		entry.highlight.FillColor = color
		entry.untilAt = math.max(entry.untilAt, now + seconds)
		return
	end
	if highlightCount >= Logic.HIGHLIGHT_CAP then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = 0.4
	highlight.OutlineTransparency = 0.2
	highlight.Adornee = character
	highlight.Parent = character
	local newEntry = { highlight = highlight, untilAt = now + seconds }
	highlights[character] = newEntry
	highlightCount += 1
	local release = track(highlight, "highlight", seconds + 5) -- the loop below ends it; this is the backstop
	highlight.Destroying:Connect(function()
		if highlights[character] == newEntry then
			highlights[character] = nil
			highlightCount -= 1
		end
	end)
	if impact then
		-- the first instant is a bright impact flash that settles into the effect colour
		highlight.FillColor = impact
		highlight.FillTransparency = 0.05
		local fade = if seconds <= 0.3
			then { FillTransparency = 1, OutlineTransparency = 1 }
			else { FillTransparency = 0.4 }
		local goal: { [string]: any } = { FillColor = color }
		for key, value in fade do
			goal[key] = value
		end
		TweenService:Create(highlight, TweenInfo.new(math.min(seconds, 0.3), Enum.EasingStyle.Quad), goal):Play()
	elseif seconds <= 0.3 then
		TweenService:Create(highlight, TweenInfo.new(seconds), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
	end
	local function check()
		local remaining = newEntry.untilAt - os.clock()
		if remaining > 0.01 and highlight.Parent then
			task.delay(remaining, check)
		else
			release()
		end
	end
	task.delay(seconds, check)
end

local function stopShake()
	pcall(function()
		RunService:UnbindFromRenderStep(SHAKE_BIND)
	end)
end

local function shake(seconds: number, amplitude: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local entry = { startedAt = os.clock(), seconds = seconds, amplitude = amplitude }
	table.insert(shakes, entry)
	tracker.acquire("shake")
	if #shakes == 1 then
		RunService:BindToRenderStep(SHAKE_BIND, Enum.RenderPriority.Camera.Value + 1, function()
			local cam = workspace.CurrentCamera
			local now = os.clock()
			local x, y = 0, 0
			for i = #shakes, 1, -1 do
				local s = shakes[i]
				local t = now - s.startedAt
				if t >= s.seconds then
					table.remove(shakes, i)
					tracker.release("shake")
				else
					local dx, dy = Logic.shakeOffset(t, s.seconds, s.amplitude)
					x, y = x + dx, y + dy
				end
			end
			if cam and (x ~= 0 or y ~= 0) then
				cam.CFrame = cam.CFrame * CFrame.new(x, y, 0)
			end
			if #shakes == 0 then
				stopShake()
			end
		end)
	end
end

-- The victim's own client launches its own root (it owns the character) and keeps friction off for the push.
local function applyLaunch(character: Model?, velocity: any)
	local root = rootOf(character)
	if not root then
		return
	end
	local v = PvpKnockbackRules.clampVelocity(velocity)
	if v.X == 0 and v.Y == 0 and v.Z == 0 then
		return
	end
	root.AssemblyLinearVelocity = Vector3.new(v.X, v.Y, v.Z)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 and not humanoid.PlatformStand then
		humanoid.PlatformStand = true
		task.delay(Config.PVP.KNOCKBACK_SECONDS, function()
			if humanoid.Parent then
				humanoid.PlatformStand = false
			end
		end)
	end
end

local function beam(
	from: BasePart?,
	toAttachment: Attachment,
	spec: { seconds: number, color: Logic.RGB, width: number? }
)
	if not from then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Parent = from
	track(a0, "attachment", spec.seconds)
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = toAttachment
	b.Color = ColorSequence.new(color3(spec.color))
	local width = spec.width or 0.6
	b.Width0 = width
	b.Width1 = width * 0.45
	b.Texture = "rbxasset://textures/particles/smoke_main.dds"
	b.TextureSpeed = 4
	b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.2) })
	b.FaceCamera = true
	b.LightEmission = 0.5
	b.Segments = 1
	b.Parent = a0
	track(b, "beam", spec.seconds)
end

local function trail(root: BasePart, seconds: number, total: number)
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Position, a1.Position = Vector3.new(0, 1, 0), Vector3.new(0, -1, 0)
	a0.Parent, a1.Parent = root, root
	track(a0, "attachment", total)
	track(a1, "attachment", total)
	local t = Instance.new("Trail")
	t.Attachment0, t.Attachment1 = a0, a1
	t.Lifetime = 0.4
	t.Color = ColorSequence.new(Color3.new(1, 1, 1))
	t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	t.LightEmission = 0.5
	t.Parent = root
	track(t, "trail", total)
	task.delay(seconds, function()
		t.Enabled = false
	end)
end

-- The goo blob: one particle that leaves `from` and flies the server's arc to `to` in `flight` seconds.
local function emitBlob(from: Vector3, to: Vector3, flight: number, spec: { size: number, color: Logic.RGB })
	local g = Config.PVP.BLOB_GRAVITY
	local v = Logic.blobVelocity(from, to, flight, g)
	local velocity = Vector3.new(v.X, v.Y, v.Z)
	if velocity.Magnitude < 1e-3 then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = workspace.Terrain
	attachment.WorldCFrame = CFrame.lookAt(from, from + velocity)
	track(attachment, "attachment", flight + 0.5)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.EmissionDirection = Enum.NormalId.Front
	emitter.SpreadAngle = Vector2.new(0, 0)
	emitter.Speed = NumberRange.new(velocity.Magnitude)
	emitter.Acceleration = Vector3.new(0, -g, 0)
	emitter.Drag = 0
	emitter.Lifetime = NumberRange.new(math.max(flight, 0.05))
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(color3(spec.color))
	emitter.LightEmission = 0.35
	emitter.Size = NumberSequence.new(spec.size)
	emitter.Transparency = NumberSequence.new(0.05)
	emitter.Parent = attachment
	track(emitter, "emitter", flight + 0.5)
	emitter:Emit(1)
end

-- A word over a character's head ("BONK!") that floats up and fades.
local function popup(character: Model?, spec: { text: string, color: Logic.RGB, seconds: number })
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "PvpPopup"
	gui.Size = UDim2.fromOffset(LOOK.popupPx.X, LOOK.popupPx.Y)
	gui.StudsOffset = Vector3.new(0, LOOK.popupY, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = head :: any
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Theme.Font
	label.TextSize = LOOK.popupText
	label.Text = spec.text
	label.TextColor3 = color3(spec.color)
	label.TextStrokeColor3 = Theme.Ink
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Parent = head
	track(gui, "popup", spec.seconds)
	local info = TweenInfo.new(spec.seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffset = Vector3.new(0, LOOK.popupY + LOOK.popupRise, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
end

-- Lightning from a world point to a character's root (Thunder Glove chain).
local function bolt(from: Vector3, root: BasePart, spec: { color: Logic.RGB, seconds: number })
	local a0 = anchorAt(from, spec.seconds)
	local a1 = Instance.new("Attachment")
	a1.Parent = root
	track(a1, "attachment", spec.seconds)
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Color = ColorSequence.new(color3(spec.color))
	b.Width0 = LOOK.boltWidth
	b.Width1 = LOOK.boltWidth
	b.Segments = 12
	b.CurveSize0 = (math.random() * 2 - 1) * LOOK.boltCurve
	b.CurveSize1 = (math.random() * 2 - 1) * LOOK.boltCurve
	b.LightEmission = 1
	b.FaceCamera = true
	b.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	b.TextureSpeed = 6
	b.Parent = a0
	track(b, "beam", spec.seconds)
end

-- The Bounce Glove pogo on the victim's own client: after the push (the first bounce) it bounces again, lower each time.
local function pogo(character: Model?, heights: { number })
	local g = workspace.Gravity
	for i, at in Logic.pogoTimes(heights, g) do
		local h = heights[i + 1]
		task.delay(at, function()
			local root = rootOf(character)
			if root and h then
				local v = root.AssemblyLinearVelocity
				root.AssemblyLinearVelocity = Vector3.new(v.X * 0.5, math.sqrt(2 * g * h), v.Z * 0.5)
				playSfx("PvpBoing", root, true)
			end
		end)
	end
end

-- A flat goo splat / pool on the ground under `position` for `seconds`.
local function splat(position: Vector3, spec: { radius: number, seconds: number, color: Logic.RGB })
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local characters = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(characters, p.Character)
		end
	end
	params.FilterDescendantsInstances = characters
	local hit = workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -LOOK.splatProbe, 0), params)
	local ground = if hit then hit.Position else position
	local part = Instance.new("Part")
	part.Name = "PvpSplat"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(LOOK.splatHeight, spec.radius * 2, spec.radius * 2)
	part.CFrame = CFrame.new(ground + Vector3.new(0, LOOK.splatHeight / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	part.Color = color3(spec.color)
	part.Material = Enum.Material.Glass
	part.Transparency = 0.3
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = workspace
	track(part, "splat", spec.seconds)
	local fade = math.min(1, spec.seconds / 2)
	task.delay(spec.seconds - fade, function()
		if part.Parent then
			TweenService:Create(part, TweenInfo.new(fade), { Transparency = 1 }):Play()
		end
	end)
end

-- Goo on the edge of the local player's screen for `seconds` (a blob hit them).
local function screenSplat(seconds: number)
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "PvpGooSplat"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	for _, spot in LOOK.screenSplat do
		local blob = Instance.new("Frame")
		blob.BackgroundColor3 = Theme.Good
		blob.BackgroundTransparency = 0.15
		blob.BorderSizePixel = 0
		blob.Position = UDim2.fromScale(spot[1], spot[2])
		blob.Size = UDim2.fromScale(spot[3], spot[3])
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.Parent = blob
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = blob
		blob.Parent = gui
		TweenService:Create(blob, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		}):Play()
	end
	gui.Parent = playerGui
	track(gui, "screen", seconds)
end

local land: (payload: { [string]: any }, plan: Logic.Plan) -> ()

local function playEffect(payload: { [string]: any })
	local localId = Players.LocalPlayer.UserId
	local plan = Logic.plan(payload, Config.PVP, lowQuality())
	if not plan then
		return
	end
	if anim then
		if plan.attackerAnim and payload.attacker ~= localId and payload.itemId ~= "Bat" then
			anim.playItem(payload.attacker, payload.itemId)
		end
		if plan.targetHit and type(payload.target) == "number" then
			anim.play(payload.target, "hit")
		end
	end
	local from, to = payload.from, payload.to
	if plan.blob and typeof(from) == "Vector3" and typeof(to) == "Vector3" then
		local flight = plan.delay or 0
		local camera = workspace.CurrentCamera
		if not camera or Logic.inRange((camera.CFrame.Position - from).Magnitude) then
			emitBlob(from, to, flight, plan.blob)
		end
		task.delay(flight, land, payload, plan)
		return
	end
	land(payload, plan)
end

-- Everything that happens where the effect lands (at once, or when the blob arrives).
function land(payload: { [string]: any }, plan: Logic.Plan)
	local localId = Players.LocalPlayer.UserId
	local isTarget = payload.target == localId
	local targetCharacter = characterOf(payload.target)
	if isTarget and plan.applyVelocity and payload.velocity then
		applyLaunch(targetCharacter, payload.velocity)
		if plan.pogo then
			pogo(targetCharacter, plan.pogo)
		end
	end
	if isTarget and plan.screenSplat then
		screenSplat(plan.screenSplat)
	end
	local position = payload.position
	local root = if plan.onTarget then rootOf(targetCharacter) else nil
	local at: Vector3? = if root then root.Position elseif typeof(position) == "Vector3" then position else nil
	if not at then
		return
	end
	local camera = workspace.CurrentCamera
	if camera and not Logic.inRange((camera.CFrame.Position - at).Magnitude) then
		return
	end
	if isTarget and plan.shake then
		shake(plan.shake.seconds, plan.shake.amplitude)
	end
	local involved = isTarget or payload.attacker == localId
	local parent: Instance = root or anchorAt(at, plan.seconds)
	playSfx(plan.sfx, parent, involved)
	if plan.burst then
		local burstParent = parent
		if plan.burst.height and not root then
			burstParent = anchorAt(at + Vector3.new(0, plan.burst.height, 0), plan.seconds)
		end
		emitBurst(burstParent, plan.burst, plan.seconds)
	end
	if plan.ring then
		emitBurst(parent, plan.ring, plan.seconds)
	end
	if plan.highlight and targetCharacter then
		local impact = plan.highlight.impact
		flash(
			targetCharacter,
			color3(plan.highlight.color),
			plan.highlight.seconds,
			if impact then color3(impact) else nil
		)
	end
	if plan.beam then
		local from = handOf(characterOf(payload.attacker))
		local to = if root then root else nil
		local endAttachment = anchorAt(at, plan.beam.seconds)
		if to then
			endAttachment.Parent = to
		end
		beam(from, endAttachment, plan.beam)
	end
	if plan.trail and root then
		trail(root, plan.trail, plan.seconds)
	end
	if plan.popup then
		popup(targetCharacter, plan.popup)
	end
	if plan.bolt and root and typeof(payload.from) == "Vector3" then
		bolt(payload.from, root, plan.bolt)
	end
	if plan.splat then
		splat(at, plan.splat)
	end
end

-- The placeholder pieces of a placed trap (PvpModels.markerParts), or its uploaded mesh, centred on `center`.
local function markerModel(itemId: string, center: CFrame, look: Logic.MarkerLook, model: Model)
	local material = (Enum.Material :: any)[look.material] or Enum.Material.SmoothPlastic
	local meshName = PvpModels.markerMesh(itemId)
	local meshId = if meshName then MeshAssets.meshId(meshName) else nil
	local item = PvpModels.get(itemId)
	local function quiet(part: BasePart)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = material
		part.Transparency = math.max(part.Transparency, look.transparency)
		part.Parent = model
	end
	if meshId and item then
		local part = Instance.new("Part")
		part.Name = "Mesh"
		part.Size = Vector3.new(item.size[1], item.size[2], item.size[3]) * LOOK.markerScale
		part.CFrame = center * CFrame.new(0, part.Size.Y / 2, 0)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = meshId
		mesh.Scale = Vector3.one * LOOK.markerScale
		mesh.Parent = part
		quiet(part)
		return
	end
	for i, piece in PvpModels.markerParts(itemId) or {} do
		local part = Instance.new("Part")
		part.Name = `Piece{i}`
		local size = piece.size
		local turn = CFrame.new()
		if piece.shape == "Ball" then
			part.Shape = Enum.PartType.Ball
		elseif piece.shape == "Cylinder" then
			part.Shape = Enum.PartType.Cylinder
			turn = AXIS_TURN[piece.axis or "Y"]
			size = { size[2], size[1], size[1] }
		end
		local k = LOOK.markerScale
		part.Size = Vector3.new(size[1], size[2], size[3]) * k
		local r = piece.rotDeg or { 0, 0, 0 }
		-- the hand pieces sit forward of the fist (-Z); a placed trap is centred on its point
		part.CFrame = center
			* CFrame.new(piece.pos[1] * k, piece.pos[2] * k, (piece.pos[3] + 0.5) * k)
			* CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
			* turn
		part.Color = Color3.fromRGB(piece.color[1], piece.color[2], piece.color[3])
		part.Transparency = piece.transparency or 0
		quiet(part)
	end
end

local function placeMarker(payload: { [string]: any })
	local trapId, position = payload.trapId, payload.position
	if type(trapId) ~= "string" or typeof(position) ~= "Vector3" then
		return
	end
	local marker = Logic.markerFor(payload.itemId, Config.PVP_TOOLS, Config.PVP)
	local localId = Players.LocalPlayer.UserId
	if not marker or not Logic.markerVisible(marker, payload.owner, localId) then
		return
	end
	local old = markers[trapId]
	if old then
		old:Destroy()
	end
	local look = Logic.markerLook(marker, payload.owner == localId)
	local model = Instance.new("Model")
	model.Name = "PvpMarker"
	local part = Instance.new("Part")
	part.Name = "Disc"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.2, marker.diameter, marker.diameter)
	part.CFrame = CFrame.new(position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	part.Color = color3(marker.color)
	part.Material = (Enum.Material :: any)[look.material] or Enum.Material.SmoothPlastic
	part.Transparency = look.transparency
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = model
	if marker.glows then
		markerModel(payload.itemId, CFrame.new(position), look, model)
	end
	model.Parent = workspace
	markers[trapId] = model
	track(model, "marker", marker.seconds or 3600)
	model.Destroying:Connect(function()
		if markers[trapId] == model then
			markers[trapId] = nil
		end
	end)
end

function PvpEffects.play(payload: any)
	if type(payload) ~= "table" then
		return
	end
	local kind = payload.kind
	if kind == "TrapPlaced" then
		if anim and payload.owner ~= Players.LocalPlayer.UserId then
			anim.playItem(payload.owner, payload.itemId)
		end
		placeMarker(payload)
	elseif kind == "TrapCleared" then
		local part = if type(payload.trapId) == "string" then markers[payload.trapId] else nil
		if part then
			part:Destroy()
		end
	elseif kind == "Effect" or (kind == nil and payload.effect ~= nil) then
		playEffect(payload)
	end
end

-- Transient instances alive right now (emitters, highlights, beams, sounds, shakes...): 0 once the effects ended.
function PvpEffects.activeCount(): number
	return tracker.count() - tracker.count("marker")
end

function PvpEffects.markerCount(): number
	return tracker.count("marker")
end

function PvpEffects.start(remote: RemoteEvent, animHandle: any?)
	if connection then
		return
	end
	anim = animHandle
	connection = remote.OnClientEvent:Connect(function(payload: any)
		local ok, err = pcall(PvpEffects.play, payload)
		if not ok then
			warn(`[PvpEffects] {err}`)
		end
	end)
end

function PvpEffects.stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	anim = nil
	stopShake()
	for _, marker in markers do
		marker:Destroy()
	end
end

return PvpEffects
