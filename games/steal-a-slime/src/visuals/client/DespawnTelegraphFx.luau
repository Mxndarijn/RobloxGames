--!strict
--[[
	DespawnTelegraphFx (VisualsClient module, FEATURES.DespawnTelegraph)
	(Not named DespawnTelegraph: tests/Members.spec keys modules by file name
	and Shared has that one.)

	Wild slime models (tag Constants.SLIME_TAG, State == "Wild") carry the
	attribute DespawnAt (Constants.DESPAWN_AT_ATTRIBUTE, server time) for the
	last Config.DESPAWN_TELEGRAPH_SECONDS before the server removes them.
	While it is set this shows, client-only:
	  * a shrink to SHRINK_TO (factor from Shared.DespawnTelegraph.shrinkFactor)
	No fade, blink or highlight: the slime stays fully opaque until the drop.
	Once the model is removed after DespawnAt, a slime-green sparkle
	poof with a small smoke puff at its last position, plus an optional
	sound (Config.DESPAWN_POOF_SOUND; skipped while the id is the 0
	placeholder).

	Shrink: Model:ScaleTo is preferred (it scales mesh packages, welds and
	offsets around the bottom-centre pivot). If GetScale / ScaleTo fails,
	the fallback scales every BasePart's Size and its offset from Body, so
	procedural Part / MeshPart trees (eyes and other welded parts included)
	shrink together around Body's centre. Sizes and offsets are restored on
	untrack.

	FX data and timing math live in Shared.DespawnTelegraph. Reads attributes
	only; never fires remotes or moves the model.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local Timing = require(Shared:WaitForChild("DespawnTelegraph"))

local FX = Timing.FX

local DespawnTelegraphFx = {}

DespawnTelegraphFx.SHRINK_TO = FX.shrinkTo -- model scale factor at DespawnAt
DespawnTelegraphFx.POOF_TEXTURE = FX.texture
DespawnTelegraphFx.POOF_COUNT = FX.count
DespawnTelegraphFx.POOF_GRACE = 1.5 -- removed within this many seconds after DespawnAt = despawn (not a grab)
DespawnTelegraphFx.POOF_LIFETIME = 1 -- seconds before the poof part is destroyed (longer with a sound)

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

type Fallback = { part: BasePart, size: Vector3, offset: CFrame }

type Track = {
	model: Model,
	body: BasePart,
	baseScale: number?, -- nil: GetScale unavailable, use the Size fallback
	fallback: { Fallback }?, -- set once the Size fallback is in use
	factor: number, -- last applied shrink factor
}

local tracks: { [Model]: Track } = {}

local function despawnAt(model: Model): number?
	local value = model:GetAttribute(Constants.DESPAWN_AT_ATTRIBUTE)
	if model:GetAttribute("State") == "Wild" and type(value) == "number" then
		return value
	end
	return nil
end

-- A real "rbxassetid://<n>" with n > 0, else nil (placeholder / malformed).
local function poofSoundId(): string?
	if not Config.DESPAWN_POOF_SOUND then
		return nil
	end
	local id = Config.DESPAWN_POOF_SOUND_ID
	local n = if type(id) == "string" then tonumber(string.match(id, "^rbxassetid://(%d+)$")) else nil
	if n and n > 0 then
		return id
	end
	return nil
end

local function emitter(texture: string, transparency: NumberSequence): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Rate = 0
	e.LightEmission = 0.3
	e.SpreadAngle = Vector2.new(180, 180)
	e.Transparency = transparency
	e.Color = ColorSequence.new(rgb(FX.colorBright), rgb(FX.color))
	return e
end

local lastPoofSound = -math.huge

local function poof(position: Vector3)
	local part = Instance.new("Part")
	part.Name = "DespawnPoof"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Position = position

	local sparkle = emitter(FX.texture, NumberSequence.new(0.1, 1))
	sparkle.Lifetime = NumberRange.new(0.4, 0.7)
	sparkle.Speed = NumberRange.new(6, 10)
	sparkle.Size = NumberSequence.new(1.2, 0)
	sparkle.Rotation = NumberRange.new(0, 360)
	sparkle.Parent = part

	local smoke = emitter(FX.smokeTexture, NumberSequence.new(0.6, 1))
	smoke.Lifetime = NumberRange.new(0.5, 0.8)
	smoke.Speed = NumberRange.new(1, 3)
	smoke.Size = NumberSequence.new(1.5, 2.5)
	smoke.LightEmission = 0
	smoke.Parent = part

	local lifetime = DespawnTelegraphFx.POOF_LIFETIME
	local sound: Sound? = nil
	local soundId = poofSoundId()
	if soundId and os.clock() - lastPoofSound >= (Config.DESPAWN_POOF_SOUND_GAP or 0) then
		lastPoofSound = os.clock()
		local s = Instance.new("Sound")
		s.SoundId = soundId
		s.Volume = 0.3
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 8
		s.RollOffMaxDistance = 50
		local sfx = game:GetService("SoundService"):FindFirstChild("SFX")
		s.SoundGroup = if sfx and sfx:IsA("SoundGroup") then sfx else nil
		s.Parent = part
		sound = s
		lifetime = 3
	end

	part.Parent = workspace
	sparkle:Emit(FX.count)
	smoke:Emit(FX.smokeCount)
	if sound then
		pcall(sound.Play, sound)
	end
	task.delay(lifetime, function()
		part:Destroy()
	end)
end

-- Size fallback: every BasePart's size and its offset from Body times factor.
-- Body stays put (anchored, and the idle animator pivots it), so the slime
-- shrinks around Body's centre instead of the bottom pivot.
local function applyFallback(t: Track, factor: number)
	local fallback = t.fallback
	if not fallback then
		return
	end
	local bodyCFrame = t.body.CFrame
	for _, f in fallback do
		if f.part.Parent then
			f.part.Size = Vector3.new(Timing.fallbackSizeXYZ(f.size.X, f.size.Y, f.size.Z, factor))
			if f.part ~= t.body then
				-- Position / Orientation, not CFrame: setting CFrame on a part joined
				-- by a WeldConstraint moves the whole assembly (Body included);
				-- these move only this part and re-base its weld.
				local cf = bodyCFrame * CFrame.new(f.offset.Position * factor) * f.offset.Rotation
				local rx, ry, rz = cf:ToOrientation()
				f.part.Position = cf.Position
				f.part.Orientation = Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz))
			end
		end
	end
end

local function startFallback(t: Track)
	local fallback = {}
	local bodyCFrame = t.body.CFrame
	for _, d in t.model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(fallback, { part = d, size = d.Size, offset = bodyCFrame:ToObjectSpace(d.CFrame) })
		end
	end
	t.fallback = fallback
	t.baseScale = nil
end

-- Client-side only (scale does not replicate back). ScaleTo first; any
-- failure switches this track to the Size fallback for good.
local function setFactor(t: Track, factor: number)
	if math.abs(t.factor - factor) < 1e-3 then
		return
	end
	t.factor = factor
	local baseScale = t.baseScale
	if baseScale then
		local ok = pcall(t.model.ScaleTo, t.model, baseScale * factor)
		if ok then
			return
		end
		pcall(t.model.ScaleTo, t.model, baseScale) -- undo a partial scale before the fallback snapshot
		startFallback(t)
	end
	applyFallback(t, factor)
end

local function untrack(model: Model)
	local t = tracks[model]
	if not t then
		return
	end
	tracks[model] = nil
	if t.model.Parent then
		setFactor(t, 1)
	end
end

local function track(model: Model)
	local body = model:FindFirstChild("Body")
	if tracks[model] or not (body and body:IsA("BasePart")) then
		return
	end
	local okScale, scale = pcall(model.GetScale, model)
	local t: Track = {
		model = model,
		body = body,
		baseScale = if okScale and type(scale) == "number" and scale > 0 then scale else nil,
		fallback = nil,
		factor = 1,
	}
	if not t.baseScale then
		startFallback(t)
	end
	tracks[model] = t
end

local function refresh(model: Model)
	if despawnAt(model) then
		track(model)
	else
		untrack(model)
	end
end

local function watch(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	instance:GetAttributeChangedSignal(Constants.DESPAWN_AT_ATTRIBUTE):Connect(function()
		refresh(instance)
	end)
	instance:GetAttributeChangedSignal("State"):Connect(function()
		refresh(instance)
	end)
	refresh(instance)
end

local function onRemoved(instance: Instance)
	local t = tracks[instance :: Model]
	if not t then
		return
	end
	local at = despawnAt(t.model)
	local now = workspace:GetServerTimeNow()
	if at and now >= at - 0.25 and now <= at + DespawnTelegraphFx.POOF_GRACE then
		poof(t.body.Position)
	end
	untrack(t.model)
end

local function step(t: Track, now: number)
	local at = despawnAt(t.model)
	if not at then
		return
	end
	local p = Timing.progress(now, at, Config.DESPAWN_TELEGRAPH_SECONDS)
	-- ScaleTo pivots at the bottom centre, so the slime shrinks into the ground.
	setFactor(t, Timing.shrinkFactor(p, DespawnTelegraphFx.SHRINK_TO))
end

function DespawnTelegraphFx.start()
	if not Config.FEATURES.DespawnTelegraph then
		return
	end
	CollectionService:GetInstanceAddedSignal(Constants.SLIME_TAG):Connect(watch)
	CollectionService:GetInstanceRemovedSignal(Constants.SLIME_TAG):Connect(onRemoved)
	for _, model in CollectionService:GetTagged(Constants.SLIME_TAG) do
		watch(model)
	end
	RunService.RenderStepped:Connect(function()
		local now = workspace:GetServerTimeNow()
		for _, t in tracks do
			step(t, now)
		end
	end)
end

return DespawnTelegraphFx
