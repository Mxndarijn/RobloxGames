--!strict
--[[
	EggFx (client only, contract/mystery-egg.md)

	Looks on every Mystery Egg model (tag Constants.SLIME_TAG with the
	EggKind attribute) resting on a pad, from its EggHatchAt /
	EggHatchSeconds attributes and the server clock:
	  * cracks: one set at 1/3 of the incubation, a second at 2/3;
	  * a glow in the kind's colour that pulses faster the closer the hatch;
	  * ready: a bright glow and sparkles until the owner hatches it.
	Everything it adds is local (never replicates) and goes when the egg
	leaves its pad or the model goes (a hatch rebuilds the model as its slime).
	The idle jiggle and the carry wriggle come from VisualsClient like any slime.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local EggModel = require(ReplicatedStorage.Visuals.EggModel)

local EggFx = {}

EggFx.MAX_DISTANCE = 140 -- studs: eggs further away skip the per-frame pulse

type Egg = {
	model: Model,
	body: BasePart,
	stage: number, -- 0 none, 1 first cracks, 2 more cracks, 3 ready
	light: PointLight?,
	sparkles: ParticleEmitter?,
	cracks: { BasePart },
}

-- Stage for a progress 0..1: 0, 1 (>= 1/3), 2 (>= 2/3), 3 (ready).
function EggFx.stage(progress: number): number
	if progress >= 1 then
		return 3
	elseif progress >= 2 / 3 then
		return 2
	elseif progress >= 1 / 3 then
		return 1
	end
	return 0
end

-- Glow pulses per second at a progress 0..1: slow at the start, quick near the hatch.
function EggFx.pulseRate(progress: number): number
	return 0.4 + 2.6 * math.clamp(progress, 0, 1) ^ 2
end

local CRACK_COLOR = Color3.fromRGB(40, 24, 20)
-- Each crack: yaw round the egg, height on the shell (-1 bottom .. 1 top), tilt.
local CRACKS = {
	{ { 0.3, 0.35, 25 }, { 2.4, 0.1, -30 }, { 4.4, 0.45, 15 } },
	{ { 1.2, -0.05, -20 }, { 3.3, 0.55, 35 }, { 5.4, 0.2, -10 } },
}

local function addCracks(egg: Egg, set: number)
	local rx = EggModel.WIDTH / 2
	local ry = EggModel.HEIGHT / 2
	for i, c in CRACKS[set] do
		local yaw, h, tilt = c[1], c[2], c[3]
		local ring = math.sqrt(math.max(0, 1 - h * h)) * rx
		local pos = Vector3.new(math.cos(yaw) * ring, h * ry, math.sin(yaw) * ring)
		local normal = Vector3.new(pos.X / (rx * rx), pos.Y / (ry * ry), pos.Z / (rx * rx)).Unit
		local at = pos + normal * 0.02
		local crack = Instance.new("Part")
		crack.Name = `EggCrack{set}_{i}`
		crack.Size = Vector3.new(0.09, 0.85, 0.05)
		crack.Color = CRACK_COLOR
		crack.Material = Enum.Material.SmoothPlastic
		crack.CanCollide = false
		crack.CanTouch = false
		crack.CanQuery = false
		crack.Massless = true
		crack.CastShadow = false
		crack.CFrame = egg.body.CFrame * CFrame.lookAt(at, at + normal) * CFrame.Angles(0, 0, math.rad(tilt))
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = egg.body
		weld.Part1 = crack
		weld.Parent = crack
		crack.Parent = egg.model
		table.insert(egg.cracks, crack)
	end
end

local function clear(egg: Egg)
	for _, crack in egg.cracks do
		crack:Destroy()
	end
	table.clear(egg.cracks)
	if egg.light then
		egg.light:Destroy()
		egg.light = nil
	end
	if egg.sparkles then
		egg.sparkles:Destroy()
		egg.sparkles = nil
	end
	egg.stage = 0
end

local function ensureGlow(egg: Egg)
	if egg.light then
		return
	end
	local kind = egg.model:GetAttribute(Constants.EGG_KIND_ATTRIBUTE)
	local light = Instance.new("PointLight")
	light.Name = "EggGlow"
	light.Color = EggModel.glowColor(if type(kind) == "string" then kind else "")
	light.Range = 8
	light.Brightness = 0
	light.Shadows = false
	light.Parent = egg.body
	egg.light = light
end

local function ensureSparkles(egg: Egg)
	if egg.sparkles then
		return
	end
	local kind = egg.model:GetAttribute(Constants.EGG_KIND_ATTRIBUTE)
	local p = Instance.new("ParticleEmitter")
	p.Name = "EggReady"
	p.Color = ColorSequence.new(EggModel.glowColor(if type(kind) == "string" then kind else ""))
	p.LightEmission = 1
	p.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	p.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	p.Lifetime = NumberRange.new(0.6, 1.1)
	p.Rate = 14
	p.Speed = NumberRange.new(2, 4)
	p.SpreadAngle = Vector2.new(180, 180)
	p.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	p.Parent = egg.body
	egg.sparkles = p
end

-- Applies the look for `progress` (nil = not resting on a pad / not incubating: everything off).
local function apply(egg: Egg, progress: number?, t: number, near: boolean)
	if progress == nil then
		if egg.stage ~= 0 or egg.light then
			clear(egg)
		end
		return
	end
	local stage = EggFx.stage(progress)
	if stage ~= egg.stage then
		if stage < egg.stage then
			clear(egg)
		end
		if stage >= 1 and egg.stage < 1 then
			addCracks(egg, 1)
		end
		if stage >= 2 and egg.stage < 2 then
			addCracks(egg, 2)
		end
		if stage >= 3 then
			ensureSparkles(egg)
		end
		egg.stage = stage
	end
	ensureGlow(egg)
	local light = egg.light :: PointLight
	if stage >= 3 then
		light.Brightness = 2.5 + 1.2 * math.sin(t * 6)
	elseif near then
		local wave = 0.5 + 0.5 * math.sin(t * math.pi * 2 * EggFx.pulseRate(progress))
		light.Brightness = (0.3 + 1.4 * progress) * wave
	end
end

-- Incubation progress 0..1 of an egg model at server time `now`, or nil off a pad / without a hatch clock.
function EggFx.progress(model: Instance, now: number): number?
	if model:GetAttribute("State") ~= "Pad" then
		return nil
	end
	local hatchAt = model:GetAttribute(Constants.EGG_HATCH_AT_ATTRIBUTE)
	local seconds = model:GetAttribute(Constants.EGG_HATCH_SECONDS_ATTRIBUTE)
	if type(hatchAt) ~= "number" or type(seconds) ~= "number" or seconds <= 0 then
		return nil
	end
	return math.clamp(1 - (hatchAt - now) / seconds, 0, 1)
end

export type Controller = { tick: (camera: Camera?) -> (), stop: () -> () }

-- Starts watching egg models. Call `tick` once a frame from the client's frame loop.
function EggFx.start(): Controller
	local eggs: { [Model]: Egg } = {}
	local conns: { RBXScriptConnection } = {}

	local function add(instance: Instance)
		if not instance:IsA("Model") or instance:GetAttribute(Constants.EGG_KIND_ATTRIBUTE) == nil then
			return
		end
		-- The tag can replicate before the parts stream in: wait for Body off the frame loop.
		task.spawn(function()
			local body = instance:WaitForChild("Body", 30)
			if
				body
				and body:IsA("BasePart")
				and instance:HasTag(Constants.SLIME_TAG)
				and not eggs[instance :: Model]
			then
				eggs[instance :: Model] = { model = instance :: Model, body = body, stage = 0, cracks = {} }
			end
		end)
	end
	local function remove(instance: Instance)
		local egg = eggs[instance :: Model]
		if egg then
			clear(egg)
			eggs[instance :: Model] = nil
		end
	end

	table.insert(conns, CollectionService:GetInstanceAddedSignal(Constants.SLIME_TAG):Connect(add))
	table.insert(conns, CollectionService:GetInstanceRemovedSignal(Constants.SLIME_TAG):Connect(remove))
	for _, model in CollectionService:GetTagged(Constants.SLIME_TAG) do
		add(model)
	end

	local function tick(camera: Camera?)
		local now = workspace:GetServerTimeNow()
		local t = os.clock()
		local eye = camera and camera.CFrame.Position
		for model, egg in eggs do
			if model.Parent then
				local near = eye == nil or (egg.body.Position - eye).Magnitude <= EggFx.MAX_DISTANCE
				apply(egg, EggFx.progress(model, now), t, near)
			end
		end
	end

	return {
		tick = tick,
		stop = function()
			for _, c in conns do
				c:Disconnect()
			end
			for model in eggs do
				remove(model)
			end
		end,
	}
end

return EggFx
