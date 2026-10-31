--!strict
--[[
	ObbyParts (shared visuals, contract/obby.md §5)

	Builds the obby course as Instances from ObbyCourse data: one Part per ObbyCourse.Part (a TrussPart for
	ladders) and the Goo Ring's decor behind the start pad. The client builds it (visuals/client/ObbyCourseView)
	from the slot the server publishes, like the backdrop, so the server's world and its part budget never carry the
	course. Moving parts get their rest CFrame and motion as attributes (the OBBY_* names in Constants);
	visuals/client/ObbyFx plays them. Belts get a surface velocity, ice no friction. Also holds the obby's sign
	colours and label helper, which server/ObbyView's portal shares.

	The Goo Ring sign is a SurfaceGui (guides/roblox-world-labels.md): its 1-stud line reads from about 20 studs on a
	phone; the runner appears about 7 studs from it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local ObbyCourse = require(Shared:WaitForChild("ObbyCourse"))

local ObbyParts = {}

-- Sign and ring colours, shared with the portal (server/ObbyView).
ObbyParts.COLORS = table.freeze({
	ring = Color3.fromRGB(150, 230, 70),
	floor = Color3.fromRGB(170, 255, 140),
	sign = Color3.fromRGB(46, 38, 70),
	ink = Color3.fromRGB(255, 255, 255),
	stroke = Color3.fromRGB(30, 22, 48),
})
ObbyParts.FONT = Enum.Font.FredokaOne
ObbyParts.PIXELS_PER_STUD = 50

-- Look per part kind: colour (or three tones), material, transparency. No Neon: it blooms into blobs against the
-- obby sky, so even the "glow" tiles are saturated SmoothPlastic.
type Look = { colors: { Color3 }, material: Enum.Material, transparency: number? }
local LOOKS: { [string]: Look } = {
	start = { colors = { Color3.fromRGB(120, 226, 170) }, material = Enum.Material.SmoothPlastic },
	pad = { colors = { Color3.fromRGB(214, 226, 238) }, material = Enum.Material.SmoothPlastic },
	finish = { colors = { Color3.fromRGB(255, 206, 64) }, material = Enum.Material.SmoothPlastic },
	jelly = {
		colors = { Color3.fromRGB(255, 120, 190), Color3.fromRGB(120, 220, 120), Color3.fromRGB(110, 170, 255) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.15,
	},
	goo = {
		colors = { Color3.fromRGB(150, 230, 70), Color3.fromRGB(120, 205, 60) },
		material = Enum.Material.SmoothPlastic,
	},
	bubble = {
		colors = { Color3.fromRGB(170, 235, 255), Color3.fromRGB(200, 225, 255), Color3.fromRGB(190, 255, 240) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.3,
	},
	ice = { colors = { Color3.fromRGB(190, 230, 255) }, material = Enum.Material.Ice },
	rope = {
		colors = { Color3.fromRGB(230, 180, 90), Color3.fromRGB(210, 160, 80), Color3.fromRGB(240, 200, 110) },
		material = Enum.Material.Wood,
	},
	tile = {
		colors = { Color3.fromRGB(160, 110, 240), Color3.fromRGB(255, 160, 60), Color3.fromRGB(110, 200, 230) },
		material = Enum.Material.SmoothPlastic,
	},
	post = { colors = { Color3.fromRGB(70, 60, 90) }, material = Enum.Material.SmoothPlastic },
	bar = { colors = { Color3.fromRGB(235, 70, 120) }, material = Enum.Material.SmoothPlastic },
	trampoline = {
		colors = { Color3.fromRGB(80, 170, 255), Color3.fromRGB(255, 110, 200) },
		material = Enum.Material.SmoothPlastic,
	},
	cannon = { colors = { Color3.fromRGB(255, 140, 40) }, material = Enum.Material.SmoothPlastic },
	blob = {
		colors = { Color3.fromRGB(130, 230, 90) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.1,
	},
	pipe = {
		colors = { Color3.fromRGB(150, 230, 70) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.7,
	},
	truss = { colors = { Color3.fromRGB(255, 120, 190) }, material = Enum.Material.SmoothPlastic },
	fan = { colors = { Color3.fromRGB(90, 96, 120) }, material = Enum.Material.DiamondPlate },
	wind = {
		colors = { Color3.fromRGB(205, 230, 250) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.85,
	},
	plank = {
		colors = { Color3.fromRGB(200, 150, 90), Color3.fromRGB(180, 130, 75) },
		material = Enum.Material.Wood,
	},
	gate = { colors = { Color3.fromRGB(235, 70, 120) }, material = Enum.Material.SmoothPlastic, transparency = 0.2 },
	-- Belts: orange pushes right, blue pushes left.
	belt = {
		colors = { Color3.fromRGB(255, 150, 50), Color3.fromRGB(70, 170, 255) },
		material = Enum.Material.SmoothPlastic,
	},
	glow = {
		colors = { Color3.fromRGB(255, 200, 50), Color3.fromRGB(80, 215, 120), Color3.fromRGB(70, 170, 240) },
		material = Enum.Material.SmoothPlastic,
	},
	log = {
		colors = { Color3.fromRGB(160, 105, 60), Color3.fromRGB(140, 90, 50) },
		material = Enum.Material.Wood,
	},
	wave = {
		colors = { Color3.fromRGB(110, 220, 90) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.15,
	},
	puncher = { colors = { Color3.fromRGB(255, 90, 140) }, material = Enum.Material.SmoothPlastic },
	gust = {
		colors = { Color3.fromRGB(235, 250, 255) },
		material = Enum.Material.SmoothPlastic,
		transparency = 0.96,
	},
}

-- The Goo Ring home (`Course.home`): the yard's ring at `scale`, standing on the start pad's back edge and facing
-- along the course, so a runner pops out of it facing the sections. "BACK TO BASE" is painted on the start pad in
-- front of it (a SurfaceGui on the pad's top: a 1.1-stud line reads from the start pad on a phone).
local HOME = table.freeze({
	scale = 0.72, -- of the yard ring: about 9 studs tall, a 6-stud opening a character walks through
	labelSize = Vector3.new(1.5, 0.05, 6.4), -- studs, lying on the start pad (a Top canvas is Z wide, X tall)
	labelInset = 4.6, -- studs from the ring's middle to the label's centre: clear of the ring's puddle
	labelTurn = 90, -- degrees about Y
	maxDistance = 60,
	text = "BACK TO BASE",
})

local ICE = PhysicalProperties.new(0.9, 0, 0.5, 100, 1)

-- The course frame as a CFrame: X forward, Y up, Z right (ObbyCourse's course-local axes).
local function frameCFrame(frame: ObbyCourse.Frame): CFrame
	local a = math.rad(frame.yaw)
	local forward = Vector3.new(math.sin(a), 0, math.cos(a))
	local right = Vector3.new(-math.cos(a), 0, math.sin(a))
	local o = frame.origin
	return CFrame.fromMatrix(Vector3.new(o[1], o[2], o[3]), forward, Vector3.yAxis, right)
end

local function localVec(cf: CFrame, axis: string?): Vector3
	if axis == "x" then
		return cf.XVector
	elseif axis == "y" then
		return cf.YVector
	end
	return cf.ZVector
end

local function makePart(spec: ObbyCourse.Part, frameCf: CFrame, parent: Instance)
	local look = LOOKS[spec.look] or LOOKS.pad
	local part: BasePart = if spec.shape == "truss" then Instance.new("TrussPart") else Instance.new("Part")
	part.Name = spec.look
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = look.material
	part.Color = look.colors[math.clamp(spec.tone or 1, 1, #look.colors)]
	part.Transparency = look.transparency or 0
	part.CastShadow = false
	local center = frameCf * CFrame.new(spec.pos[1], spec.pos[2], spec.pos[3])
	local disc = spec.shape == "disc"
	if disc then
		-- A cylinder's axis is its X: lay it on its side so a flat face points up.
		(part :: Part).Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(spec.size[2], spec.size[1], spec.size[3])
		part.CFrame = center * CFrame.Angles(0, 0, math.rad(90))
	else
		if spec.shape == "ball" then
			(part :: Part).Shape = Enum.PartType.Ball
		elseif spec.shape == "log" then
			-- A cylinder's axis is its X, which already runs along the course.
			(part :: Part).Shape = Enum.PartType.Cylinder
		end
		part.Size = Vector3.new(spec.size[1], spec.size[2], spec.size[3])
		part.CFrame = center
	end
	if spec.ghost then
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	end
	if spec.ice then
		part.CustomPhysicalProperties = ICE
	end
	if spec.conveyor then
		local v = spec.conveyor
		part.AssemblyLinearVelocity = frameCf.XVector * v[1] + frameCf.YVector * v[2] + frameCf.ZVector * v[3]
	end
	local motion = spec.motion
	if motion then
		part:SetAttribute(Constants.OBBY_MOTION, motion.kind)
		part:SetAttribute(Constants.OBBY_BASE, part.CFrame)
		part:SetAttribute(Constants.OBBY_PHASE, motion.phase or 0)
		if motion.period then
			part:SetAttribute(Constants.OBBY_PERIOD, motion.period)
		end
		if motion.kind == "slide" or motion.kind == "punch" then
			part:SetAttribute(Constants.OBBY_AXIS, localVec(frameCf, motion.axis))
			part:SetAttribute(Constants.OBBY_AMP, motion.amp or 0)
		elseif motion.kind == "gust" then
			-- The axis points the way it blows; the power is the speed.
			local power = motion.power or 0
			local sign = if power < 0 then -1 else 1
			part:SetAttribute(Constants.OBBY_AXIS, localVec(frameCf, motion.axis) * sign)
			part:SetAttribute(Constants.OBBY_POWER, math.abs(power))
			part:SetAttribute(Constants.OBBY_DUTY, motion.duty or 0.5)
		elseif motion.kind == "melt" then
			part:SetAttribute(Constants.OBBY_DELAY, motion.delay or 0.7)
			part:SetAttribute(Constants.OBBY_AWAY, motion.away or 2.5)
		elseif motion.kind == "flip" then
			part:SetAttribute(Constants.OBBY_DUTY, motion.duty or 0.65)
		elseif motion.kind == "shrink" then
			part:SetAttribute(Constants.OBBY_MIN, motion.min or 0.3)
			part:SetAttribute(Constants.OBBY_SHRINK_AXES, if disc then "yz" else "xz")
		elseif motion.kind == "bounce" or motion.kind == "lift" then
			part:SetAttribute(Constants.OBBY_POWER, motion.power or 50)
		elseif motion.kind == "swing" or motion.kind == "rock" then
			part:SetAttribute(Constants.OBBY_AMP, motion.amp or 0)
			part:SetAttribute(Constants.OBBY_ARM, motion.arm or 0)
		end
	end
	part.Parent = parent
end

function ObbyParts.signLabel(parent: Instance, name: string, text: string, y: number, h: number, maxSize: number)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0.05, y)
	label.Size = UDim2.fromScale(0.9, h)
	label.Font = ObbyParts.FONT
	label.Text = text
	label.TextColor3 = ObbyParts.COLORS.ink
	label.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = ObbyParts.COLORS.stroke
	stroke.Thickness = 3
	stroke.Parent = label
	label.Parent = parent
end

local function decor(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

-- The Goo Ring: kit meshes (shared/modeling-kit models obby_goo_ring, obby_goo_swirl; Shared.MeshAssets), shared by
-- the yard portal (server/ObbyView, swapped by server/MeshSwap) and the ring home (buildHome, swapped on the client by
-- visuals/client/ObbyCourseView). The numbers are the yard size (scale 1), from the kit model.
ObbyParts.GOO = table.freeze({
	ring = "obby_goo_ring_eyes", -- MeshAsset names
	swirl = "obby_goo_swirl",
	ringSize = Vector3.new(12.489, 12.076, 5.438), -- the ring mesh's native size (studs)
	swirlSize = Vector3.new(9.2, 9.2, 0.9),
	centre = 5.914, -- the ring's centre above its foot (the kit model's CZ)
	swirlBack = 0.3, -- the swirl stands this far behind the ring's middle, so the drips hang in front of it
	spin = 1.2, -- radians a second the swirl turns (visuals/client/ObbyFx)
	-- The ring, swirl and sign kit models were built facing kit +Y, so after the import yaw they face the slot's +Z:
	-- their slots are turned this much so the eyes and the sign's face look along the slot's front (-Z).
	faceTurn = CFrame.Angles(0, math.pi, 0),
	glow = Color3.fromRGB(170, 120, 255),
	sparkle = { Color3.fromRGB(255, 200, 245), Color3.fromRGB(190, 160, 255) },
})

-- An invisible, non-colliding box the mesh swap fills with kit mesh `name` (attribute MeshAsset).
local function meshSlot(name: string, asset: string, size: Vector3, cf: CFrame, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Transparency = 1
	decor(part)
	part:SetAttribute("MeshAsset", asset)
	part.Parent = parent
	return part
end

-- A standing Goo Ring at `scale` of the yard size: the ring mesh and the swirl inside it, which turns on each client
-- (Constants.GOO_SPIN and GOO_PIVOT on the swirl's slot, played by visuals/client/ObbyFx) with a purple glow and
-- sparkles drifting into it. `ground` is the point under the ring's centre, its LookVector the way the eyes face (you
-- walk through along that axis). Decor only. Names are `prefix` .. "GooRing" / "GooSwirl". Returns the swirl slot.
function ObbyParts.gooRing(ground: CFrame, scale: number, parent: Instance, prefix: string): Part
	local G = ObbyParts.GOO
	local size = G.ringSize * scale
	meshSlot(prefix .. "GooRing", G.ring, size, ground * CFrame.new(0, size.Y / 2, 0) * G.faceTurn, parent)
	local centre = ground * CFrame.new(0, G.centre * scale, G.swirlBack * scale) -- +Z: away from the way it faces
	local swirl = meshSlot(prefix .. "GooSwirl", G.swirl, G.swirlSize * scale, centre * G.faceTurn, parent)
	swirl:SetAttribute(Constants.GOO_SPIN, G.spin)
	swirl:SetAttribute(Constants.GOO_PIVOT, centre)
	local light = Instance.new("PointLight")
	light.Color = G.glow
	light.Brightness = 1.6
	light.Range = 14 * scale
	light.Shadows = false
	light.Parent = swirl
	-- Sparkles drifting in towards the vortex's core: a disc emitter in the ring's plane, shooting inwards.
	local at = Instance.new("Attachment")
	at.Name = "Sparkles"
	at.CFrame = CFrame.Angles(math.rad(90), 0, 0) -- the attachment's Y axis along the ring's normal: its disc is the swirl
	at.Parent = swirl
	local fx = Instance.new("ParticleEmitter")
	fx.Shape = Enum.ParticleEmitterShape.Disc
	fx.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	fx.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	fx.ShapePartial = 1
	fx.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	fx.Color = ColorSequence.new(G.sparkle[1], G.sparkle[2])
	fx.LightEmission = 1
	fx.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5 * scale), NumberSequenceKeypoint.new(1, 0) })
	fx.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	fx.Lifetime = NumberRange.new(1.2, 1.8)
	fx.Speed = NumberRange.new(2 * scale, 2.6 * scale)
	fx.Rate = 10
	fx.RotSpeed = NumberRange.new(-90, 90)
	fx.LockedToPart = true
	fx.Parent = at
	return swirl
end

-- The Goo Ring home on the start pad's back edge (x = 0 in the course frame), facing along the course, and the
-- "BACK TO BASE" label painted on the start pad in front of it.
local function buildHome(frameCf: CFrame, parent: Instance)
	local ground = frameCf * CFrame.lookAt(Vector3.zero, Vector3.xAxis) -- course-local: X forward, the eyes look down it
	ObbyParts.gooRing(ground, HOME.scale, parent, "Home")
	local label = Instance.new("Part")
	label.Name = "HomeLabel"
	label.Size = HOME.labelSize
	label.Transparency = 1
	-- lying on the pad's top, turned so the text runs across the course and reads from the start pad
	label.CFrame = ground
		* CFrame.new(0, HOME.labelSize.Y / 2 + 0.01, -HOME.labelInset)
		* CFrame.Angles(0, math.rad(HOME.labelTurn), 0)
	decor(label)
	label.Parent = parent
	local gui = Instance.new("SurfaceGui")
	gui.Name = "HomeLabelGui"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ObbyParts.PIXELS_PER_STUD
	gui.MaxDistance = HOME.maxDistance
	gui.LightInfluence = 0
	gui.Adornee = label
	ObbyParts.signLabel(gui, "Title", HOME.text, 0.08, 0.84, ObbyParts.PIXELS_PER_STUD)
	gui.Parent = label
end

-- The course as a Model named Constants.OBBY_COURSE (attribute Slot), in the frame given; not parented.
function ObbyParts.build(course: ObbyCourse.Course, frame: ObbyCourse.Frame): Model
	local model = Instance.new("Model")
	model.Name = Constants.OBBY_COURSE
	model:SetAttribute("Slot", course.slot)
	local frameCf = frameCFrame(frame)
	for _, spec in course.parts do
		makePart(spec, frameCf, model)
	end
	buildHome(frameCf, model)
	return model
end

return ObbyParts
