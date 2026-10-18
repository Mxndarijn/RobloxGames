--!strict
--[[
	PvpEffects (client, FEATURES.PvP, CONTRACT.md §26.1 "Client effects")

	The look and sound of PvP, driven by PvpEvent `Effect` / `TrapPlaced` / `TrapCleared`. Built ONLY from Roblox
	built-in instances (ParticleEmitter, Highlight, Beam, Trail, Attachment, Sound; textures are rbxasset:// built-ins),
	all transient: each is destroyed within its plan's `seconds` (PvpEffectsLogic.plan) and counted, so
	`activeCount()` is 0 once the effects ended. Zero BaseParts when idle: emitters sit on the characters' existing parts
	or on an Attachment under Workspace.Terrain; the only Part is the flat marker of a placed Goo Trap (owner only) /
	Bounce Pad, destroyed on TrapCleared. The victim's client also applies the payload `velocity` to its own root
	(it owns the character; the server's own set is weak for a real player) and shakes its camera for <= 0.3 s.

	PvpEffects.start(remote) connects PvpEvent (init.client calls it only with the flag on); PvpEffects.play(payload)
	is the same entry for a probe; PvpEffects.activeCount() / markerCount(); PvpEffects.stop().
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PvpKnockbackRules = require(Shared:WaitForChild("PvpKnockbackRules"))

local Logic = require(script.Parent.PvpEffectsLogic)
local SlimeLod = require(script.Parent.SlimeLod)
local SoundController = require(script.Parent.SoundController)
local Sounds = require(script.Parent.Sounds)

local PvpEffects = {}

local tracker = Logic.tracker()
local connection: RBXScriptConnection? = nil
local markers: { [string]: Part } = {}
local highlights: { [Instance]: { highlight: Highlight, untilAt: number } } = {}
local highlightCount = 0
local shakes: { { startedAt: number, seconds: number, amplitude: number } } = {}
local SHAKE_BIND = "PvpEffectsShake"

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

local function flash(character: Model, color: Color3, seconds: number)
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
	if seconds <= 0.3 then
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

local function beam(from: BasePart?, toAttachment: Attachment, spec: { seconds: number, color: Logic.RGB })
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
	b.Width0 = 0.6
	b.Width1 = 0.25
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

local function playEffect(payload: { [string]: any })
	local localId = Players.LocalPlayer.UserId
	local plan = Logic.plan(payload, Config.PVP, lowQuality())
	if not plan then
		return
	end
	local isTarget = payload.target == localId
	local targetCharacter = characterOf(payload.target)
	if isTarget and plan.applyVelocity and payload.velocity then
		applyLaunch(targetCharacter, payload.velocity)
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
	if plan.highlight and targetCharacter then
		flash(targetCharacter, color3(plan.highlight.color), plan.highlight.seconds)
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
end

local function placeMarker(payload: { [string]: any })
	local trapId, position = payload.trapId, payload.position
	if type(trapId) ~= "string" or typeof(position) ~= "Vector3" then
		return
	end
	local marker = Logic.markerFor(payload.itemId, Config.PVP_TOOLS, Config.PVP)
	if not marker or not Logic.markerVisible(marker, payload.owner, Players.LocalPlayer.UserId) then
		return
	end
	local old = markers[trapId]
	if old then
		old:Destroy()
	end
	local part = Instance.new("Part")
	part.Name = "PvpMarker"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.2, marker.diameter, marker.diameter)
	part.CFrame = CFrame.new(position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	part.Color = color3(marker.color)
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = 0.4
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = workspace
	markers[trapId] = part
	track(part, "marker", marker.seconds or 3600)
	part.Destroying:Connect(function()
		if markers[trapId] == part then
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

function PvpEffects.start(remote: RemoteEvent)
	if connection then
		return
	end
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
	stopShake()
	for _, part in markers do
		part:Destroy()
	end
end

return PvpEffects
