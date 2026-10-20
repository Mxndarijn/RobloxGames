--!strict
--[[
	RitualFx (VisualsClient module, FEATURES.CoopRitual, contract/coop-ritual.md)

	Client-only effects on workspace.Map.RitualCircle (built by server/RitualView, absent when the flag is
	off), driven by its attributes (the RITUAL_* names in Constants) and the server clock:
	  * Idle: a few lilac motes drift up off the disc; the orb bobs and turns slowly and glows softly
	  * a spot gets taken: a small green puff on it and a beam from the spot to the orb
	  * Charging: the beams turn gold and widen, sparks are pulled in to the orb, the orb grows and spins
	    faster, and the dashes of the ground ring light up with the HOLD_SECONDS countdown
	  * completion (Charging -> Cooldown): a short light flash, one shockwave ring over the ground and a
	    gold / goo sparkle shower
	  * Cooldown: the orb (dimmed by the server) gives off a thin wisp and its light goes out; the ring
	    shows as a faint grey track whose dashes light up again (bright lilac, the next one fading in) as
	    the rest runs down
	The look numbers live in Visuals.RitualLook and the particle presets in Visuals.Effects. Everything it
	adds is local; it never fires remotes. Past RitualLook.MAX_DISTANCE from the camera it stops the
	emitters and skips the per-frame work. Call `tick` once a frame from the client's frame loop.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local Visuals = ReplicatedStorage:WaitForChild("Visuals")
local Effects = require(Visuals:WaitForChild("Effects"))
local RitualLook = require(Visuals:WaitForChild("RitualLook"))

local RitualFx = {}

RitualFx.FOLDER_NAME = "ClientRitualFx"
RitualFx.CIRCLE_NAME = "RitualCircle" -- server/RitualView.MODEL_NAME
RitualFx.FIND_EVERY = 1 -- seconds between looks for the circle while it isn't there

export type Controller = { tick: (camera: Camera?) -> (), stop: () -> () }

type Spot = { part: BasePart, attach: Attachment, beam: Beam, puff: ParticleEmitter, taken: boolean }

type Rig = {
	model: Model,
	folder: Folder,
	centre: Vector3,
	orb: BasePart,
	orbBase: CFrame,
	orbSize: Vector3,
	orbAttach: Attachment,
	glow: PointLight,
	motes: ParticleEmitter,
	swirl: ParticleEmitter,
	rest: ParticleEmitter,
	shower: ParticleEmitter,
	spots: { Spot },
	ring: { BasePart },
	shock: { BasePart }, -- dashes of the expanding completion ring
	added: { Instance }, -- local instances parented into the server's parts (removed on stop)
	phase: string,
	yaw: number,
	shockAt: number?,
	near: boolean,
}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function decor(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function holder(name: string, cframe: CFrame, size: Vector3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Transparency = 1
	part.Size = size
	part.CFrame = cframe
	decor(part)
	part.Parent = parent
	return part
end

local function findCircle(): Model?
	local map = workspace:FindFirstChild(Constants.MAP_FOLDER)
	local model = map and map:FindFirstChild(RitualFx.CIRCLE_NAME) or workspace:FindFirstChild(RitualFx.CIRCLE_NAME)
	return if model and model:IsA("Model") then model else nil
end

local function build(model: Model): Rig?
	local base = model:FindFirstChild("Base")
	local orb = model:FindFirstChild("Orb")
	if not (base and base:IsA("BasePart") and orb and orb:IsA("BasePart")) then
		return nil
	end
	local old = workspace:FindFirstChild(RitualFx.FOLDER_NAME)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = RitualFx.FOLDER_NAME
	local added: { Instance } = {}
	-- The base disc is a Cylinder rolled flat: its radius is Size.Y / 2, its top is Size.X / 2 up.
	local radius = base.Size.Y / 2
	local top = base.Position.Y + base.Size.X / 2
	local centre = Vector3.new(base.Position.X, top, base.Position.Z)

	local moteHolder = holder(
		"Motes",
		CFrame.new(centre + Vector3.new(0, 0.3, 0)),
		Vector3.new(radius * 1.6, 0.1, radius * 1.6),
		folder
	)
	local motes = Effects.emitter("RitualMote")
	motes.Parent = moteHolder

	local shell = holder("SwirlShell", orb.CFrame, Vector3.one * 10, folder)
	shell.Shape = Enum.PartType.Ball
	local swirl = Effects.emitter("RitualSwirl")
	swirl.Shape = Enum.ParticleEmitterShape.Sphere
	swirl.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	swirl.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	swirl.Enabled = false
	swirl.Parent = shell

	local orbAttach = Instance.new("Attachment")
	orbAttach.Name = "RitualFxOrb"
	orbAttach.Parent = orb
	table.insert(added, orbAttach)
	local glow = Effects.light("RitualGlow")
	glow.Parent = orb
	table.insert(added, glow)
	local rest = Effects.emitter("RitualRest")
	rest.Enabled = false
	rest.Parent = orbAttach
	local shower = Effects.emitter("RitualShower")
	shower.Rate = 0
	shower.Parent = orbAttach

	local spots: { Spot } = {}
	local i = 1
	while true do
		local part = model:FindFirstChild(`Spot_{i}`)
		if not (part and part:IsA("BasePart")) then
			break
		end
		local attach = Instance.new("Attachment")
		attach.Name = "RitualFxSpot"
		attach.Parent = part
		attach.WorldPosition = part.Position + Vector3.new(0, part.Size.X / 2, 0)
		table.insert(added, attach)
		local beam = Instance.new("Beam")
		beam.Name = "RitualBeam"
		beam.Attachment0 = attach
		beam.Attachment1 = orbAttach
		beam.FaceCamera = true
		beam.LightEmission = 0.6
		beam.LightInfluence = 0
		beam.Segments = 12
		beam.CurveSize0 = 2.5
		beam.Transparency = NumberSequence.new(0.5, 0.15)
		beam.Enabled = false
		beam.Parent = attach
		local puff = Effects.emitter("RitualJoin")
		puff.Rate = 0
		puff.Parent = attach
		table.insert(spots, {
			part = part,
			attach = attach,
			beam = beam,
			puff = puff,
			taken = part:GetAttribute(Constants.RITUAL_TAKEN_ATTRIBUTE) == true,
		})
		i += 1
	end

	-- The dashes lie on the raised "Ring" band (between the Inner and Ring discs), just above its top.
	local ringPart = model:FindFirstChild("Ring")
	local innerPart = model:FindFirstChild("Inner")
	local ringRadius = radius - 0.7
	local dashY = 0.1
	if ringPart and ringPart:IsA("BasePart") then
		local outer = ringPart.Size.Y / 2
		local inner = if innerPart and innerPart:IsA("BasePart") then innerPart.Size.Y / 2 else outer - 0.9
		ringRadius = (outer + inner) / 2
		dashY = ringPart.Position.Y + ringPart.Size.X / 2 - top + 0.05
	end
	local ring: { BasePart } = {}
	local n = RitualLook.RING_SEGMENTS
	local dash = 2 * math.pi * ringRadius / n * 0.6
	for s = 1, n do
		-- Dash 1 starts at the top of the ring as seen from the plaza and they light clockwise.
		local a = (s - 0.5) / n * 2 * math.pi
		local p = centre + Vector3.new(math.sin(a) * ringRadius, dashY, math.cos(a) * ringRadius)
		local seg = Instance.new("Part")
		seg.Name = `RingDash_{s}`
		seg.Material = Enum.Material.Neon
		seg.Size = Vector3.new(0.4, 0.08, dash)
		seg.CFrame = CFrame.lookAt(p, p + Vector3.new(math.cos(a), 0, -math.sin(a)))
		seg.Transparency = 1
		decor(seg)
		seg.Parent = folder
		table.insert(ring, seg)
	end

	local shock: { BasePart } = {}
	for s = 1, n do
		local seg = Instance.new("Part")
		seg.Name = `ShockDash_{s}`
		seg.Material = Enum.Material.Neon
		seg.Color = rgb(RitualLook.COLORS.charge)
		seg.Size = Vector3.new(0.3, 0.05, 1)
		seg.Transparency = 1
		decor(seg)
		seg.Parent = folder
		table.insert(shock, seg)
	end

	folder.Parent = workspace
	local phase = model:GetAttribute(Constants.RITUAL_PHASE_ATTRIBUTE)
	return {
		model = model,
		folder = folder,
		centre = centre,
		orb = orb,
		orbBase = orb.CFrame,
		orbSize = orb.Size,
		orbAttach = orbAttach,
		glow = glow,
		motes = motes,
		swirl = swirl,
		rest = rest,
		shower = shower,
		spots = spots,
		ring = ring,
		shock = shock,
		added = added,
		phase = if type(phase) == "string" then phase else "Idle",
		yaw = 0,
		shockAt = nil,
		near = true,
	}
end

local function teardown(rig: Rig)
	for _, inst in rig.added do
		inst:Destroy()
	end
	rig.folder:Destroy()
	if rig.orb.Parent then
		rig.orb.CFrame = rig.orbBase
		rig.orb.Size = rig.orbSize
	end
end

local function setNear(rig: Rig, near: boolean)
	if rig.near == near then
		return
	end
	rig.near = near
	if not near then
		rig.motes.Enabled = false
		rig.swirl.Enabled = false
		rig.rest.Enabled = false
		rig.glow.Enabled = false
		for _, spot in rig.spots do
			spot.beam.Enabled = false
		end
	end
end

local function complete(rig: Rig, t: number)
	rig.shockAt = t
	rig.shower:Emit(Effects.EMITTERS.RitualShower.count or 30)
end

local function apply(rig: Rig, dt: number, t: number, now: number)
	local model = rig.model
	local phaseValue = model:GetAttribute(Constants.RITUAL_PHASE_ATTRIBUTE)
	local phase = if type(phaseValue) == "string" then phaseValue else "Idle"
	if phase ~= rig.phase then
		if RitualLook.completed(rig.phase, phase) then
			complete(rig, t)
		end
		rig.phase = phase
	end
	local chargeEndsAt = model:GetAttribute(Constants.RITUAL_CHARGE_ENDS_ATTRIBUTE) :: number?
	local readyAt = model:GetAttribute(Constants.RITUAL_READY_AT_ATTRIBUTE) :: number?
	local charge = RitualLook.charge(phase, chargeEndsAt, now)
	local fill, tint = RitualLook.ring(phase, chargeEndsAt, readyAt, now)
	local resting = phase == "Cooldown"

	local bob, spin, scale = RitualLook.orb(phase, charge, t)
	rig.yaw = (rig.yaw + spin * dt) % (2 * math.pi)
	rig.orb.CFrame = rig.orbBase * CFrame.new(0, bob, 0) * CFrame.Angles(0, rig.yaw, 0)
	rig.orb.Size = rig.orbSize * scale

	local base = Effects.LIGHTS.RitualGlow.brightness
	local flash = 0
	if rig.shockAt then
		flash = math.max(0, 1 - (t - rig.shockAt) / RitualLook.FLASH_SECONDS)
	end
	rig.glow.Enabled = not resting or flash > 0
	rig.glow.Color = if flash > 0
		then Color3.new(1, 1, 1)
		else rgb(RitualLook.color(if phase == "Charging" then "charge" else "idle"))
	rig.glow.Brightness = base * (1 + 1.5 * charge) + 3 * flash

	rig.motes.Enabled = phase == "Idle"
	rig.swirl.Enabled = phase == "Charging"
	rig.rest.Enabled = resting

	local beamColor = ColorSequence.new(
		rgb(RitualLook.COLORS.taken):Lerp(
			rgb(RitualLook.COLORS.charge),
			if phase == "Charging" then 0.4 + 0.6 * charge else 0
		)
	)
	local width = RitualLook.beamWidth(charge)
	for _, spot in rig.spots do
		local taken = spot.part:GetAttribute(Constants.RITUAL_TAKEN_ATTRIBUTE) == true
		if taken and not spot.taken then
			spot.puff:Emit(Effects.EMITTERS.RitualJoin.count or 12)
		end
		spot.taken = taken
		spot.beam.Enabled = taken and not resting
		if taken then
			spot.beam.Color = beamColor
			spot.beam.Width0 = width
			spot.beam.Width1 = width * 0.6
		end
	end

	local litColor = rgb(RitualLook.color(tint))
	local trackColor = rgb(RitualLook.COLORS.rest)
	for s, seg in rig.ring do
		local level = RitualLook.dashLevel(fill, s)
		seg.Transparency = RitualLook.dashTransparency(level, tint)
		seg.Color = if level > 0 then litColor else trackColor
	end

	local shockAt = rig.shockAt
	if shockAt and t - shockAt < RitualLook.SHOCK_SECONDS then
		local r, transparency = RitualLook.shock((t - shockAt) / RitualLook.SHOCK_SECONDS)
		local count = #rig.shock
		local dash = 2 * math.pi * r / count * 0.6
		for s, seg in rig.shock do
			local a = (s - 0.5) / count * 2 * math.pi
			local p = rig.centre + Vector3.new(math.sin(a) * r, 0.1, math.cos(a) * r)
			seg.Size = Vector3.new(0.3, 0.05, dash)
			seg.CFrame = CFrame.lookAt(p, p + Vector3.new(math.cos(a), 0, -math.sin(a)))
			seg.Transparency = transparency
		end
	elseif shockAt then
		for _, seg in rig.shock do
			seg.Transparency = 1
		end
		rig.shockAt = nil
	end
end

-- Starts watching for the circle. Call `tick` once a frame from the client's frame loop.
function RitualFx.start(): Controller
	local rig: Rig? = nil
	local lastLook = -math.huge
	local last = os.clock()

	local function tick(camera: Camera?)
		local t = os.clock()
		local dt = math.min(t - last, 0.1)
		last = t
		local current = rig
		if current and current.model.Parent == nil then
			teardown(current)
			current = nil
			rig = nil
		end
		if not current then
			if t - lastLook < RitualFx.FIND_EVERY then
				return
			end
			lastLook = t
			local model = findCircle()
			current = if model then build(model) else nil
			rig = current
			if not current then
				return
			end
		end
		local near = camera == nil or (camera.CFrame.Position - current.centre).Magnitude <= RitualLook.MAX_DISTANCE
		setNear(current, near)
		if near then
			apply(current, dt, t, workspace:GetServerTimeNow())
		else
			-- Keep the phase current so walking back in after a ritual doesn't replay its burst.
			local phase = current.model:GetAttribute(Constants.RITUAL_PHASE_ATTRIBUTE)
			current.phase = if type(phase) == "string" then phase else current.phase
		end
	end

	return {
		tick = tick,
		stop = function()
			if rig then
				teardown(rig)
				rig = nil
			end
		end,
	}
end

return RitualFx
