--!strict
--[[
	DespawnTelegraphFx (VisualsClient module, FEATURES.DespawnTelegraph)
	Sketch; owner Archer for the FX polish pass. (Not named DespawnTelegraph:
	tests/Members.spec keys modules by file name and Shared has that one.)

	Wild slime models (tag Constants.SLIME_TAG, State == "Wild") carry the
	attribute DespawnAt (Constants.DESPAWN_AT_ATTRIBUTE, server time) for the
	last Config.DESPAWN_TELEGRAPH_SECONDS before the server removes them.
	While it is set this shows, client-only:
	  * a countdown "5", "4", ... "1" above the slime (BillboardGui)
	  * Body blinking (LocalTransparencyModifier), faster towards the end
	  * a Highlight that pulses with the blink
	  * a shrink: the model scales (Model:ScaleTo) down to SHRINK_TO
	and, once the model is removed after DespawnAt, a small poof at its
	last position. Timing math lives in Shared.DespawnTelegraph. Reads
	attributes only; never fires remotes or moves the model.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local Timing = require(Shared:WaitForChild("DespawnTelegraph"))

local DespawnTelegraphFx = {}

DespawnTelegraphFx.SHRINK_TO = 0.55 -- model scale factor at DespawnAt
DespawnTelegraphFx.BLINK_HZ = { 2, 8 } -- blink rate at the start / end of the window
DespawnTelegraphFx.POOF_GRACE = 1.5 -- removed within this many seconds after DespawnAt = despawn (not a grab)

type Track = {
	model: Model,
	body: BasePart,
	baseScale: number,
	label: TextLabel,
	gui: BillboardGui,
	highlight: Highlight,
}

local tracks: { [Model]: Track } = {}

local function despawnAt(model: Model): number?
	local value = model:GetAttribute(Constants.DESPAWN_AT_ATTRIBUTE)
	if model:GetAttribute("State") == "Wild" and type(value) == "number" then
		return value
	end
	return nil
end

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
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.4, 0.7)
	emitter.Speed = NumberRange.new(6, 10)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(1.2, 0)
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Color = ColorSequence.new(Color3.fromRGB(235, 235, 235))
	emitter.Parent = part
	part.Parent = workspace
	emitter:Emit(24)
	task.delay(1, function()
		part:Destroy()
	end)
end

-- Client-side only (scale does not replicate back); pcall: ScaleTo rejects odd values.
local function setScale(model: Model, scale: number)
	if math.abs(model:GetScale() - scale) > 1e-3 then
		pcall(model.ScaleTo, model, scale)
	end
end

local function untrack(model: Model)
	local track = tracks[model]
	if not track then
		return
	end
	tracks[model] = nil
	track.gui:Destroy()
	track.highlight:Destroy()
	if track.model.Parent then
		track.body.LocalTransparencyModifier = 0
		setScale(track.model, track.baseScale)
	end
end

local function track(model: Model)
	local body = model:FindFirstChild("Body")
	if tracks[model] or not (body and body:IsA("BasePart")) then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "DespawnCountdown"
	gui.Size = UDim2.fromOffset(60, 60)
	gui.StudsOffsetWorldSpace = Vector3.new(0, body.Size.Y / 2 + 3, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = body
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 90, 90)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Parent = body
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(255, 90, 90)
	highlight.Adornee = model
	highlight.Parent = model
	tracks[model] = {
		model = model,
		body = body,
		baseScale = model:GetScale(),
		label = label,
		gui = gui,
		highlight = highlight,
	}
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
	t.label.Text = tostring(math.max(1, Timing.countdownSeconds(now, at)))
	local blink = DespawnTelegraphFx.BLINK_HZ
	local hz = blink[1] + (blink[2] - blink[1]) * p
	local on = math.sin(now * hz * math.pi * 2) > 0
	t.body.LocalTransparencyModifier = if on then 0.6 else 0
	t.highlight.OutlineTransparency = if on then 0 else 0.7
	-- Pivot is the bottom centre, so the slime shrinks into the ground.
	setScale(t.model, t.baseScale * (1 - (1 - DespawnTelegraphFx.SHRINK_TO) * p))
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
